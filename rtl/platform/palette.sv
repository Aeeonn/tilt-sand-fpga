// 256x12 palette ROM: addr = 8bpp pixel value, data = {R[3:0],G[3:0],B[3:0]}.
// Initialized from sim/golden/framebuffer_palette.mem (grayscale ramp,
// palette[i] = {i[7:4], i[7:4], i[7:4]}). See docs/SPEC_framebuffer.md.
module palette #(
		parameter PALETTE_FILE = "framebuffer_palette.mem"
) (
		input  logic       clk,
		input  logic [7:0] addr,
		output logic [3:0] red,
		output logic [3:0] green,
		output logic [3:0] blue
);

	logic [11:0] mem [0:255];
	logic [11:0] data_q;

	initial $readmemh(PALETTE_FILE, mem);

	always_ff @(posedge clk) data_q <= mem[addr];

	assign red   = data_q[11:8];
	assign green = data_q[7:4];
	assign blue  = data_q[3:0];

endmodule
