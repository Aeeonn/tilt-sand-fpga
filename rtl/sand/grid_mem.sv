// =====================================================================
// grid_mem — double-buffered cell grid (dual-clock BRAM)
// =====================================================================
// Two bram_tdp banks ping-pong as front (displayed) / back (computed).
// "The grid IS the framebuffer." See docs/SPEC_grid_mem.md.
//
//   port A (clk_a = clk_100): CA engine reads FRONT bank, writes BACK bank
//   port B (clk_b = clk_25) : grid_scanout reads FRONT bank
//
// Swap: CA pulses frame_done -> at the next vsync_tick the front index
// toggles (no tearing). Only two single bits cross clock domains
// (done toggle a->b, front b->a), each through a 2-FF synchronizer; the
// grid data crosses through the dual-clock BRAM itself. The .sdc cuts
// clk[0]<->clk[2] with set_clock_groups -asynchronous accordingly.
// =====================================================================
module grid_mem #(
		parameter int GRID_W     = 320,
		parameter int GRID_H     = 240,
		parameter int CELL_BITS  = 4,
		parameter int DEPTH      = GRID_W * GRID_H,
		parameter int ADDR_BITS  = $clog2(DEPTH),
		parameter     INIT0_FILE = "",
		parameter     INIT1_FILE = ""
) (
		// ---- CA / system domain (clk_a) ----
		input  logic                 clk_a,
		input  logic                 rst_n_a,
		input  logic [ADDR_BITS-1:0] rd_addr,    // read FRONT (rd_back=0) or BACK (rd_back=1)
		input  logic                 rd_back,    // 1: read the BACK bank (in-place multi-pass)
		output logic [CELL_BITS-1:0] rd_data,    // 1-cycle registered
		input  logic                 wr_en,      // write BACK bank
		input  logic [ADDR_BITS-1:0] wr_addr,
		input  logic [CELL_BITS-1:0] wr_data,
		input  logic                 frame_done, // 1-cyc: back buffer complete
		output logic                 swapped,    // 1-cyc: swap took effect (clk_a)
		output logic                 front_a,    // front bank index (clk_a)

		// ---- scanout / pixel domain (clk_b) ----
		input  logic                 clk_b,
		input  logic                 rst_n_b,
		input  logic                 vsync_tick, // 1-cyc at vblank start
		input  logic [ADDR_BITS-1:0] px_addr,    // read FRONT bank
		output logic [CELL_BITS-1:0] px_data,    // 1-cycle registered
		output logic                 front_b     // front bank index (clk_b)
);

	// ---------------------------------------------------------------
	// Port-A routing.
	//   Normal pass (rd_back=0): front bank is read at rd_addr, back bank
	//   is written at wr_addr/wr_en.
	//   In-place pass (rd_back=1): the engine reads AND writes the BACK
	//   bank.  Reads and writes are time-separated by the engine FSM
	//   (S_READ* vs S_WRITE*), so the back bank's single port A is muxed:
	//   it issues a write when wr_en is asserted, otherwise it issues the
	//   read at rd_addr.  This is safe because Margolus processes disjoint
	//   2x2 blocks, so no block's read overlaps another block's write.
	// ---------------------------------------------------------------
	logic [ADDR_BITS-1:0] a0_addr, a1_addr;
	logic                 a0_we,   a1_we;
	logic [CELL_BITS-1:0] a0_din,  a1_din;
	logic [CELL_BITS-1:0] a0_dout, a1_dout;
	logic [CELL_BITS-1:0] b0_dout, b1_dout;

	// Back-bank port-A request (read when not writing, write when wr_en).
	logic [ADDR_BITS-1:0] back_addr;
	logic                 back_we;
	assign back_addr = wr_en ? wr_addr : rd_addr;
	assign back_we   = wr_en;

	always_comb begin
		if (front_a == 1'b0) begin
			// bank0 = front, bank1 = back
			a0_addr = rd_addr;   a0_we = 1'b0;    a0_din = '0;       // front: read only
			a1_addr = back_addr; a1_we = back_we; a1_din = wr_data;  // back: read/write
		end else begin
			// bank1 = front, bank0 = back
			a1_addr = rd_addr;   a1_we = 1'b0;    a1_din = '0;       // front: read only
			a0_addr = back_addr; a0_we = back_we; a0_din = wr_data;  // back: read/write
		end
	end

	// Read source: front bank by default, back bank during in-place passes.
	logic [CELL_BITS-1:0] front_dout, back_dout;
	assign front_dout = front_a ? a1_dout : a0_dout;
	assign back_dout  = front_a ? a0_dout : a1_dout;
	assign rd_data    = rd_back ? back_dout : front_dout;
	assign px_data    = front_b ? b1_dout : b0_dout;

	bram_tdp #(.DW(CELL_BITS), .DEPTH(DEPTH), .AW(ADDR_BITS), .INIT_FILE(INIT0_FILE)) bank0 (
		.clk_a(clk_a), .addr_a(a0_addr), .we_a(a0_we), .din_a(a0_din), .dout_a(a0_dout),
		.clk_b(clk_b), .addr_b(px_addr), .we_b(1'b0),  .din_b('0),     .dout_b(b0_dout)
	);
	bram_tdp #(.DW(CELL_BITS), .DEPTH(DEPTH), .AW(ADDR_BITS), .INIT_FILE(INIT1_FILE)) bank1 (
		.clk_a(clk_a), .addr_a(a1_addr), .we_a(a1_we), .din_a(a1_din), .dout_a(a1_dout),
		.clk_b(clk_b), .addr_b(px_addr), .we_b(1'b0),  .din_b('0),     .dout_b(b1_dout)
	);

	// ---------------------------------------------------------------
	// Swap control + CDC
	// ---------------------------------------------------------------
	// clk_a: a frame completion toggles done_tgl_a.
	logic done_tgl_a;
	always_ff @(posedge clk_a or negedge rst_n_a) begin
		if (!rst_n_a)         done_tgl_a <= 1'b0;
		else if (frame_done)  done_tgl_a <= ~done_tgl_a;
	end

	// clk_b: synchronize the done toggle, edge-detect into a pending flag,
	// and toggle front_b at the next vsync_tick.
	logic done_s1, done_s2, done_s3;
	logic pending_b;
	always_ff @(posedge clk_b or negedge rst_n_b) begin
		if (!rst_n_b) begin
			done_s1   <= 1'b0;
			done_s2   <= 1'b0;
			done_s3   <= 1'b0;
			pending_b <= 1'b0;
			front_b   <= 1'b0;
		end else begin
			done_s1 <= done_tgl_a;   // 2-FF synchronizer (s1,s2) + s3 for edge
			done_s2 <= done_s1;
			done_s3 <= done_s2;
			if (done_s2 ^ done_s3) pending_b <= 1'b1;            // frame completed
			if (vsync_tick && pending_b) begin
				front_b   <= ~front_b;
				pending_b <= 1'b0;
			end
		end
	end

	// clk_a: synchronize front_b back, expose front_a and a swapped pulse.
	logic front_s1, front_s2, front_a_d;
	always_ff @(posedge clk_a or negedge rst_n_a) begin
		if (!rst_n_a) begin
			front_s1  <= 1'b0;
			front_s2  <= 1'b0;
			front_a_d <= 1'b0;
		end else begin
			front_s1  <= front_b;    // 2-FF synchronizer
			front_s2  <= front_s1;
			front_a_d <= front_s2;
		end
	end
	assign front_a = front_s2;
	assign swapped = front_s2 ^ front_a_d;

endmodule
