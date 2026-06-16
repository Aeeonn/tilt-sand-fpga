// =====================================================================
// grid_scanout — VGA raster position -> grid_mem read -> palette address
// =====================================================================
// clk_25 (pixel) domain. 2x2 pixel-doubles the 320x240 grid onto 640x480:
//   cell = (pixel_x>>1, pixel_y>>1),  addr = cy*GRID_W + cx  (row-major)
// Emits px_addr to grid_mem; one cycle later the returned cell becomes the
// palette address. Sync (video_on/hsync/vsync) is delayed by the BRAM read
// latency (1) so it stays aligned with the pixel data; top adds the one
// extra cycle for the palette read. See docs/SPEC_grid_scanout.md.
// =====================================================================
module grid_scanout #(
		parameter int GRID_W    = 320,
		parameter int GRID_H    = 240,
		parameter int CELL_BITS = 4,
		parameter int ADDR_BITS = $clog2(GRID_W * GRID_H)
) (
		input  logic                 clk,
		input  logic                 rst_n,
		input  logic [9:0]           pixel_x,
		input  logic [9:0]           pixel_y,
		input  logic                 video_on,
		input  logic                 hsync,
		input  logic                 vsync,

		output logic [ADDR_BITS-1:0] px_addr,    // -> grid_mem.px_addr (comb)
		input  logic [CELL_BITS-1:0] px_data,    // <- grid_mem.px_data (1 cyc later)

		output logic [7:0]           pal_addr,   // -> palette.addr
		output logic                 video_on_q, // sync aligned to pal_addr
		output logic                 hsync_q,
		output logic                 vsync_q
);

	// 2x2 pixel doubling. In the visible region cx<=319, cy<=239 so the
	// address is always in [0, DEPTH-1].
	logic [9:0] cx, cy;
	assign cx = {1'b0, pixel_x[9:1]};
	assign cy = {1'b0, pixel_y[9:1]};

	logic [ADDR_BITS-1:0] addr_c;
	assign addr_c  = cy * GRID_W + cx;             // constant mult -> shifts/add
	assign px_addr = video_on ? addr_c : '0;       // keep BRAM addr in range

	// Delay sync by the BRAM read latency (1) so it aligns with px_data,
	// which arrives one cycle after px_addr.
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			video_on_q <= 1'b0;
			hsync_q    <= 1'b1;
			vsync_q    <= 1'b1;
		end else begin
			video_on_q <= video_on;
			hsync_q    <= hsync;
			vsync_q    <= vsync;
		end
	end

	// px_data is now aligned with the delayed sync; form the palette address.
	assign pal_addr = {{(8 - CELL_BITS){1'b0}}, px_data};

endmodule
