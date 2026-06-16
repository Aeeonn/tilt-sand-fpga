// =====================================================================
// sand_falling :: top  — M4 Interaction (brush + particle count + HEX)
// =====================================================================
// TILT-SAND falling-sand toy on the DE10-Lite.
//
//   pll_sys -> clk_100 (CA engine domain) + clk_25 (VGA pixel)
//   reset_sync x2 (KEY[0] = async reset)
//   vga_timing 640x480@60  (2x2 pixel-doubled view of the 320x240 grid)
//   margolus_engine  scans grid in 2x2 blocks, applies block_rule
//   brush            injects material (KEY[1]) or clears grid (SW[9])
//   particle_count   counts non-EMPTY cells for HEX display
//   grid_mem         double-buffered 320x240x4bpp cell store
//   grid_scanout     pixel -> cell -> palette address (clk_25)
//   palette (256x12 RGB444, sand material colours) -> VGA DAC
//   hex_driver x6    particle count on HEX3:0, material on HEX5:4
//   uart_rx/uart_monitor/uart_tx peek/poke debug channel
//
// M4: interactive sandbox — KEY[1] spawns material (SW[5:2] selects),
// SW[9] clears, SW[1:0] sets gravity direction, HEX shows particle count.
// =====================================================================
module top #(
		parameter int FB_WIDTH  = 320,
		parameter int FB_HEIGHT = 240,
		parameter int CELL_BITS = 4
) (
		input  logic       MAX10_CLK1_50,
		input  logic [1:0] KEY,
		input  logic [9:0] SW,

		input  logic       UART_RX,
		output logic       UART_TX,

		output logic       VGA_HS,
		output logic       VGA_VS,
		output logic [3:0] VGA_R,
		output logic [3:0] VGA_G,
		output logic [3:0] VGA_B,

		output logic [7:0] HEX0,
		output logic [7:0] HEX1,
		output logic [7:0] HEX2,
		output logic [7:0] HEX3,
		output logic [7:0] HEX4,
		output logic [7:0] HEX5,

		output logic [9:0] LEDR
);

	// -----------------------------------------------------------------
	// Clocks / reset
	// -----------------------------------------------------------------
	logic clk_100, clk_100_shift, clk_25, locked;
	logic rst_n_100, rst_n_25;
	logic arst_n_src;

	pll_sys u_pll (
		.inclk0       (MAX10_CLK1_50),
		.arst         (~KEY[0]),
		.clk_100      (clk_100),
		.clk_100_shift(clk_100_shift),   // unused (SDRAM removed); left for PLL clk[] indices
		.clk_25       (clk_25),
		.locked       (locked)
	);

	// Hold both domains in reset while KEY[0] is pressed or PLL not locked.
	assign arst_n_src = KEY[0] & locked;

	reset_sync u_reset_100 (.clk(clk_100), .arst_n(arst_n_src), .rst_n(rst_n_100));
	reset_sync u_reset_25  (.clk(clk_25),  .arst_n(arst_n_src), .rst_n(rst_n_25));

	// -----------------------------------------------------------------
	// VGA timing (clk_25): 640x480@60, a 2x2-doubled view of FB_WIDTH x
	// FB_HEIGHT cells.
	// -----------------------------------------------------------------
	logic       hsync, vsync, video_on;
	logic [9:0] pixel_x, pixel_y;

	vga_timing #(
		.H_VISIBLE(2 * FB_WIDTH), .H_FRONT(16), .H_SYNC(96), .H_BACK(48),
		.V_VISIBLE(2 * FB_HEIGHT), .V_FRONT(10), .V_SYNC(2), .V_BACK(33)
	) u_vga_timing (
		.clk     (clk_25),
		.rst_n   (rst_n_25),
		.hsync   (hsync),
		.vsync   (vsync),
		.video_on(video_on),
		.pixel_x (pixel_x),
		.pixel_y (pixel_y)
	);

	// -----------------------------------------------------------------
	// M3 grid -> framebuffer path:
	//   grid_scanout : pixel -> cell address           (+1 cyc: BRAM read)
	//   grid_mem     : double-buffered cell store; bank0 = preloaded grid
	//   margolus_engine : reads front, writes back, signals frame_done
	//   palette      : cell -> RGB444                   (+1 cyc: palette read)
	// Sync is delayed to match (scanout +1, top +1), so the emitted stream
	// is self-consistent and pixel-exact.
	// -----------------------------------------------------------------
	localparam int ADDR_BITS = $clog2(FB_WIDTH * FB_HEIGHT);

	// One pulse per frame at the start of vsync, for the (M3) buffer swap.
	logic vsync_q1, vsync_tick;
	always_ff @(posedge clk_25 or negedge rst_n_25) begin
		if (!rst_n_25) vsync_q1 <= 1'b1;
		else           vsync_q1 <= vsync;
	end
	assign vsync_tick = vsync_q1 & ~vsync;   // 1->0 edge (vsync is active-low)

	logic [ADDR_BITS-1:0] px_addr;
	logic [CELL_BITS-1:0] px_data;
	logic [7:0]           pal_addr;
	logic                 vid_s, hs_s, vs_s;

	grid_scanout #(
		.GRID_W(FB_WIDTH), .GRID_H(FB_HEIGHT), .CELL_BITS(CELL_BITS)
	) u_scanout (
		.clk       (clk_25),
		.rst_n     (rst_n_25),
		.pixel_x   (pixel_x),
		.pixel_y   (pixel_y),
		.video_on  (video_on),
		.hsync     (hsync),
		.vsync     (vsync),
		.px_addr   (px_addr),
		.px_data   (px_data),
		.pal_addr  (pal_addr),
		.video_on_q(vid_s),
		.hsync_q   (hs_s),
		.vsync_q   (vs_s)
	);

	// -----------------------------------------------------------------
	// M4: Interaction — brush + engine + particle_count sequencer
	// -----------------------------------------------------------------
	// Sequencing per frame:
	//   swapped → brush (inject/clear if requested) → brush.done
	//   → particle_count (scan front buffer) → pc.done → engine starts
	// -----------------------------------------------------------------
	logic [ADDR_BITS-1:0]  eng_rd_addr, eng_wr_addr;
	logic [CELL_BITS-1:0]  eng_rd_data, eng_wr_data;
	logic                  eng_wr_en, eng_frame_done, eng_busy;
	logic                  grid_swapped;
	logic [1:0]            grav_dir;

	// Gravity direction from SW[1:0]
	assign grav_dir = SW[1:0];

	// --- Debounce KEY[1] for brush trigger ---
	logic key1_db;
	debounce #(.CLK_FREQ_HZ(100_000_000), .DEBOUNCE_MS(10)) u_key1_db (
		.clk(clk_100), .rst_n(rst_n_100),
		.in_raw(KEY[1]), .out(key1_db)
	);

	// KEY[1] is active-low: pressed = 0. Brush injects while pressed.
	logic brush_inject, brush_clear;
	assign brush_inject = ~key1_db;        // inject while KEY[1] held
	assign brush_clear  = SW[9];           // clear when SW[9] is up

	// Material select: SW[5:2]
	logic [CELL_BITS-1:0] brush_material;
	assign brush_material = SW[5:2];

	// --- Brush instance ---
	logic                  brush_wr_en, brush_busy, brush_done;
	logic [ADDR_BITS-1:0]  brush_wr_addr;
	logic [CELL_BITS-1:0]  brush_wr_data;

	brush #(
		.GRID_W(FB_WIDTH), .GRID_H(FB_HEIGHT), .CELL_BITS(CELL_BITS)
	) u_brush (
		.clk        (clk_100),
		.rst_n      (rst_n_100),
		.inject     (brush_inject),
		.clear      (brush_clear),
		.material   (brush_material),
		.engine_busy(eng_busy),
		.wr_en      (brush_wr_en),
		.wr_addr    (brush_wr_addr),
		.wr_data    (brush_wr_data),
		.busy       (brush_busy),
		.done       (brush_done)
	);

	// --- Particle counter instance ---
	logic                  pc_busy, pc_done, pc_start;
	logic [ADDR_BITS-1:0]  pc_rd_addr;
	logic [CELL_BITS-1:0]  pc_rd_data;
	logic [15:0]           particle_cnt;

	particle_count #(
		.GRID_W(FB_WIDTH), .GRID_H(FB_HEIGHT), .CELL_BITS(CELL_BITS)
	) u_pc (
		.clk    (clk_100),
		.rst_n  (rst_n_100),
		.start  (pc_start),
		.rd_addr(pc_rd_addr),
		.rd_data(pc_rd_data),
		.count  (particle_cnt),
		.busy   (pc_busy),
		.done   (pc_done)
	);

	// --- Frame sequencer ---
	// State: after swapped, run brush -> then particle_count -> then engine
	typedef enum logic [2:0] {
		SEQ_WAIT_SWAP,
		SEQ_BRUSH,
		SEQ_COUNT,
		SEQ_ENGINE
	} seq_state_e;

	seq_state_e seq_state;
	logic       engine_start;

	always_ff @(posedge clk_100 or negedge rst_n_100) begin
		if (!rst_n_100) begin
			seq_state <= SEQ_WAIT_SWAP;
		end else begin
			case (seq_state)
				SEQ_WAIT_SWAP: begin
					if (grid_swapped)
						seq_state <= SEQ_BRUSH;
				end
				SEQ_BRUSH: begin
					if (brush_done)
						seq_state <= SEQ_COUNT;
				end
				SEQ_COUNT: begin
					if (pc_done)
						seq_state <= SEQ_ENGINE;
				end
				SEQ_ENGINE: begin
					// Engine will start; wait for it to finish + swap
					if (eng_frame_done)
						seq_state <= SEQ_WAIT_SWAP;
				end
				default: seq_state <= SEQ_WAIT_SWAP;
			endcase
		end
	end

	// First-frame kickstart (before any swap has occurred)
	logic first_start_q;
	always_ff @(posedge clk_100 or negedge rst_n_100) begin
		if (!rst_n_100)
			first_start_q <= 1'b0;
		else if (!first_start_q && !eng_busy && !brush_busy && !pc_busy)
			first_start_q <= 1'b1;
	end

	assign engine_start = (seq_state == SEQ_ENGINE && !eng_busy) |
	                       (~first_start_q & ~eng_busy & ~brush_busy & ~pc_busy);
	assign pc_start     = (seq_state == SEQ_BRUSH && brush_done);

	// --- Write port mux: brush has priority when busy ---
	logic                 grid_wr_en;
	logic [ADDR_BITS-1:0] grid_wr_addr;
	logic [CELL_BITS-1:0] grid_wr_data;

	always_comb begin
		if (brush_busy) begin
			grid_wr_en   = brush_wr_en;
			grid_wr_addr = brush_wr_addr;
			grid_wr_data = brush_wr_data;
		end else begin
			grid_wr_en   = eng_wr_en;
			grid_wr_addr = eng_wr_addr;
			grid_wr_data = eng_wr_data;
		end
	end

	// --- Read port mux: particle_count reads front when busy ---
	logic [ADDR_BITS-1:0] grid_rd_addr;
	logic [CELL_BITS-1:0] eng_rd_data_raw;

	always_comb begin
		if (pc_busy)
			grid_rd_addr = pc_rd_addr;
		else
			grid_rd_addr = eng_rd_addr;
	end

	// rd_data goes to both; they only use it when active
	assign eng_rd_data = pc_busy ? '0 : eng_rd_data_raw;
	assign pc_rd_data  = eng_rd_data_raw;

	// --- Engine instance ---
	margolus_engine #(
		.GRID_W(FB_WIDTH), .GRID_H(FB_HEIGHT), .CELL_BITS(CELL_BITS)
	) u_engine (
		.clk       (clk_100),
		.rst_n     (rst_n_100),
		.start     (engine_start),
		.grav_dir  (grav_dir),
		.rd_addr   (eng_rd_addr),
		.rd_data   (eng_rd_data),
		.wr_en     (eng_wr_en),
		.wr_addr   (eng_wr_addr),
		.wr_data   (eng_wr_data),
		.frame_done(eng_frame_done),
		.busy      (eng_busy)
	);

	// --- Grid memory ---
	grid_mem #(
		.GRID_W(FB_WIDTH), .GRID_H(FB_HEIGHT), .CELL_BITS(CELL_BITS),
		.INIT0_FILE("sim/golden/test_grid.mif"),
		.INIT1_FILE("sim/golden/empty_grid.mif")
	) u_grid (
		.clk_a     (clk_100),
		.rst_n_a   (rst_n_100),
		.rd_addr   (grid_rd_addr),
		.rd_data   (eng_rd_data_raw),
		.wr_en     (grid_wr_en),
		.wr_addr   (grid_wr_addr),
		.wr_data   (grid_wr_data),
		.frame_done(eng_frame_done),
		.swapped   (grid_swapped),
		.front_a   (),
		// scanout / pixel domain
		.clk_b     (clk_25),
		.rst_n_b   (rst_n_25),
		.vsync_tick(vsync_tick),
		.px_addr   (px_addr),
		.px_data   (px_data),
		.front_b   ()
	);

	logic [3:0] pal_r, pal_g, pal_b;
	palette #(
		.PALETTE_FILE("sim/golden/sand_palette.mem")
	) u_palette (
		.clk  (clk_25),
		.addr (pal_addr),
		.red  (pal_r),
		.green(pal_g),
		.blue (pal_b)
	);

	// Match the palette's 1-cycle latency (scanout already delayed sync by 1).
	logic vid_q, hs_q, vs_q;
	always_ff @(posedge clk_25 or negedge rst_n_25) begin
		if (!rst_n_25) begin
			vid_q <= 1'b0;
			hs_q  <= 1'b1;
			vs_q  <= 1'b1;
		end else begin
			vid_q <= vid_s;
			hs_q  <= hs_s;
			vs_q  <= vs_s;
		end
	end

	assign VGA_HS = hs_q;
	assign VGA_VS = vs_q;
	assign VGA_R  = vid_q ? pal_r : 4'h0;
	assign VGA_G  = vid_q ? pal_g : 4'h0;
	assign VGA_B  = vid_q ? pal_b : 4'h0;

	// -----------------------------------------------------------------
	// HEX display (clk_100): particle count on HEX3:0, material on HEX5:4
	// -----------------------------------------------------------------
	logic [6:0] hex_seg [6];
	hex_driver u_hex0 (.value(particle_cnt[ 3: 0]), .seg(hex_seg[0]));
	hex_driver u_hex1 (.value(particle_cnt[ 7: 4]), .seg(hex_seg[1]));
	hex_driver u_hex2 (.value(particle_cnt[11: 8]), .seg(hex_seg[2]));
	hex_driver u_hex3 (.value(particle_cnt[15:12]), .seg(hex_seg[3]));
	hex_driver u_hex4 (.value(brush_material),       .seg(hex_seg[4]));
	hex_driver u_hex5 (.value({2'b0, grav_dir}),     .seg(hex_seg[5]));

	assign HEX0 = {1'b1, hex_seg[0]};   // bit 7 = decimal point (off)
	assign HEX1 = {1'b1, hex_seg[1]};
	assign HEX2 = {1'b1, hex_seg[2]};
	assign HEX3 = {1'b1, hex_seg[3]};
	assign HEX4 = {1'b1, hex_seg[4]};
	assign HEX5 = {1'b1, hex_seg[5]};

	// -----------------------------------------------------------------
	// UART peek/poke monitor (clk_100) — debug channel, kept from the
	// platform. Register file unused for now (regs left open).
	// -----------------------------------------------------------------
	logic [7:0] mon_rx_data, mon_tx_data;
	logic       mon_rx_valid, mon_tx_start, mon_tx_busy;

	uart_rx u_uart_rx (
		.clk(clk_100), .rst_n(rst_n_100),
		.rx_serial(UART_RX), .data_out(mon_rx_data),
		.rx_valid(mon_rx_valid), .rx_error()
	);
	uart_monitor u_uart_monitor (
		.clk(clk_100), .rst_n(rst_n_100),
		.rx_valid(mon_rx_valid), .rx_data(mon_rx_data),
		.tx_busy(mon_tx_busy), .tx_start(mon_tx_start), .tx_data(mon_tx_data),
		.regs()
	);
	uart_tx u_uart_tx (
		.clk(clk_100), .rst_n(rst_n_100),
		.data_in(mon_tx_data), .tx_start(mon_tx_start),
		.tx_busy(mon_tx_busy), .tx_serial(UART_TX), .tx_done()
	);

	// -----------------------------------------------------------------
	// LEDR: SW echo + engine busy + brush busy indicators
	// -----------------------------------------------------------------
	assign LEDR = {eng_busy, brush_busy, SW[7:0]};

endmodule
