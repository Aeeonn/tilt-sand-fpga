// 640x480@~60Hz VGA timing generator for a 25 MHz pixel clock.
// See docs/SPEC_vga_timing.md.
module vga_timing #(
		parameter int H_VISIBLE = 640,
		parameter int H_FRONT   = 16,
		parameter int H_SYNC    = 96,
		parameter int H_BACK    = 48,
		parameter int V_VISIBLE = 480,
		parameter int V_FRONT   = 10,
		parameter int V_SYNC    = 2,
		parameter int V_BACK    = 33
) (
		input  logic       clk,
		input  logic       rst_n,
		output logic       hsync,    // active low
		output logic       vsync,    // active low
		output logic       video_on,
		output logic [9:0] pixel_x,
		output logic [9:0] pixel_y
);

	localparam int H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
	localparam int V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

	logic [9:0] h_count;
	logic [9:0] v_count;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			h_count <= '0;
			v_count <= '0;
		end else if (h_count == H_TOTAL-1) begin
			h_count <= '0;
			v_count <= (v_count == V_TOTAL-1) ? '0 : v_count + 10'd1;
		end else begin
			h_count <= h_count + 10'd1;
		end
	end

	assign hsync    = ~(h_count >= H_VISIBLE+H_FRONT && h_count < H_VISIBLE+H_FRONT+H_SYNC);
	assign vsync    = ~(v_count >= V_VISIBLE+V_FRONT && v_count < V_VISIBLE+V_FRONT+V_SYNC);
	assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
	assign pixel_x  = h_count;
	assign pixel_y  = v_count;

endmodule
