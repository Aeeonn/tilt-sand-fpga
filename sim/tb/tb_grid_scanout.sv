`timescale 1ns/1ps
// =====================================================================
// tb_grid_scanout — pixel->cell address mapping + pipeline alignment
// =====================================================================
// Drives a tiny synthetic raster (8x4 grid -> 16x8 visible + small porches)
// and checks, every cycle:
//   * px_addr == cy*GRID_W + cx during video, 0 during blanking
//   * pal_addr == {4'b0, px_data}                 (combinational)
//   * video_on_q/hsync_q/vsync_q == inputs delayed by exactly 1 cycle
// The end-to-end pixel-exact image check on the real design is in tb_top.
// =====================================================================
module tb_grid_scanout;

	localparam int GRID_W = 8, GRID_H = 4;
	localparam int CELL_BITS = 4;
	localparam int AW = $clog2(GRID_W*GRID_H);     // 5

	// tiny raster (2x doubled visible + porches)
	localparam int HV = 2*GRID_W, HF = 2, HSY = 3, HB = 2;
	localparam int VV = 2*GRID_H, VF = 1, VSY = 2, VB = 1;
	localparam int HT = HV+HF+HSY+HB;              // 23
	localparam int VT = VV+VF+VSY+VB;              // 12

	localparam time CK = 2ns;

	logic clk = 0, rst_n;
	logic [9:0] pixel_x, pixel_y;
	logic video_on, hsync, vsync;
	logic [AW-1:0] px_addr;
	logic [CELL_BITS-1:0] px_data;
	logic [7:0] pal_addr;
	logic video_on_q, hsync_q, vsync_q;

	int pass_count = 0, fail_count = 0, printed = 0;
	localparam int MAXP = 10;

	// TB raster state (registered, mimics vga_timing's registered outputs)
	int h = 0, v = 0;

	assign pixel_x  = h[9:0];
	assign pixel_y  = v[9:0];
	assign video_on = (h < HV) && (v < VV);
	assign hsync    = ~((h >= HV+HF) && (h < HV+HF+HSY));
	assign vsync    = ~((v >= VV+VF) && (v < VV+VF+VSY));
	assign px_data  = h[3:0] ^ {2'b0, v[1:0]};     // arbitrary known stimulus

	grid_scanout #(.GRID_W(GRID_W), .GRID_H(GRID_H), .CELL_BITS(CELL_BITS)) dut (
		.clk(clk), .rst_n(rst_n),
		.pixel_x(pixel_x), .pixel_y(pixel_y),
		.video_on(video_on), .hsync(hsync), .vsync(vsync),
		.px_addr(px_addr), .px_data(px_data),
		.pal_addr(pal_addr),
		.video_on_q(video_on_q), .hsync_q(hsync_q), .vsync_q(vsync_q)
	);

	always #(CK/2) clk = ~clk;

	// advance raster + a 1-cycle delayed copy of the inputs (golden for *_q)
	logic von_d, hs_d, vs_d;
	always_ff @(posedge clk) begin
		if (!rst_n) begin
			h <= 0; v <= 0;
			von_d <= 1'b0; hs_d <= 1'b1; vs_d <= 1'b1;
		end else begin
			von_d <= video_on; hs_d <= hsync; vs_d <= vsync;
			if (h == HT-1) begin h <= 0; v <= (v == VT-1) ? 0 : v + 1; end
			else               h <= h + 1;
		end
	end

	task automatic ck_int(string nm, int got, int exp);
		if (got === exp) pass_count++;
		else begin
			fail_count++;
			if (printed < MAXP) begin
				$display("FAIL %s: exp %0d got %0d @%0t", nm, exp, got, $time);
				printed++;
			end
		end
	endtask

	task automatic ck_bit(string nm, logic got, logic exp);
		if (got === exp) pass_count++;
		else begin
			fail_count++;
			if (printed < MAXP) begin
				$display("FAIL %s: exp %b got %b @%0t", nm, exp, got, $time);
				printed++;
			end
		end
	endtask

	initial begin
		rst_n = 0;
		repeat (3) @(posedge clk);
		@(negedge clk); rst_n = 1;

		// run 3 full frames
		for (int cyc = 0; cyc < HT*VT*3; cyc++) begin
			@(posedge clk); #1;
			begin
				int cx, cy, exp_addr;
				cx = pixel_x >> 1;
				cy = pixel_y >> 1;
				exp_addr = video_on ? (cy*GRID_W + cx) : 0;

				ck_int($sformatf("px_addr cyc %0d", cyc), px_addr, exp_addr);
				ck_int($sformatf("pal_addr cyc %0d", cyc), pal_addr, {4'b0, px_data});

				// *_q are the inputs delayed by exactly one cycle (skip the
				// first cycle after reset while the delay reg fills).
				if (cyc > 0) begin
					ck_bit($sformatf("video_on_q cyc %0d", cyc), video_on_q, von_d);
					ck_bit($sformatf("hsync_q cyc %0d", cyc),    hsync_q,    hs_d);
					ck_bit($sformatf("vsync_q cyc %0d", cyc),    vsync_q,    vs_d);
				end
			end
		end

		if (fail_count == 0)
			$display("TB tb_grid_scanout: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_grid_scanout: %0d/%0d failed (%0d total)",
							fail_count, fail_count, pass_count + fail_count);
		$finish;
	end

endmodule
