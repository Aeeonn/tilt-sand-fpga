`timescale 1ns/1ps
// =====================================================================
// tb_hud_overlay — verify the on-screen status HUD regions/colours
// =====================================================================
// hud_overlay is pure combinational. Drive pixel coords + status and
// check ov_on / ov_rgb at representative points.
// =====================================================================
module tb_hud_overlay;

	logic [9:0]  pixel_x, pixel_y;
	logic [11:0] sel_color;
	logic [1:0]  grav_dir;
	logic [15:0] count;
	logic        ov_on;
	logic [11:0] ov_rgb;

	int pass_count = 0, fail_count = 0;

	hud_overlay dut (
		.pixel_x(pixel_x), .pixel_y(pixel_y),
		.sel_color(sel_color), .grav_dir(grav_dir), .count(count),
		.ov_on(ov_on), .ov_rgb(ov_rgb)
	);

	task automatic chk(string nm, logic exp_on, logic [11:0] exp_rgb, logic check_rgb);
		#1;
		if (ov_on !== exp_on) begin
			fail_count++;
			$display("FAIL %s: ov_on exp %0b got %0b @(%0d,%0d)", nm, exp_on, ov_on, pixel_x, pixel_y);
		end else if (check_rgb && (ov_rgb !== exp_rgb)) begin
			fail_count++;
			$display("FAIL %s: ov_rgb exp %03h got %03h @(%0d,%0d)", nm, exp_rgb, ov_rgb, pixel_x, pixel_y);
		end else begin
			pass_count++;
		end
	endtask

	initial begin
		sel_color = 12'hED6;   // sand colour
		grav_dir  = 2'd0;      // DOWN
		count     = 16'd0;

		// --- Swatch fill (inside x5..18, y1..14) shows sel_color ---
		pixel_x = 10'd10; pixel_y = 10'd8;
		chk("swatch fill", 1'b1, 12'hED6, 1'b1);

		// --- Swatch frame (x4, y8 border) shows white ---
		pixel_x = 10'd4; pixel_y = 10'd8;
		chk("swatch frame", 1'b1, 12'hFFF, 1'b1);

		// --- A gap between swatch and d-pad (x23, y8) is empty ---
		pixel_x = 10'd23; pixel_y = 10'd8;
		chk("gap empty", 1'b0, 12'h000, 1'b0);

		// --- Gravity DOWN dot active (white) when grav_dir=DOWN ---
		grav_dir = 2'd0;
		pixel_x = 10'd34; pixel_y = 10'd13;
		chk("grav down active", 1'b1, 12'hFFF, 1'b1);

		// --- Gravity UP dot inactive (dim) when grav_dir=DOWN ---
		pixel_x = 10'd34; pixel_y = 10'd2;
		chk("grav up dim", 1'b1, 12'h333, 1'b1);

		// --- Switch to UP: up dot now white, down dim ---
		grav_dir = 2'd1;
		pixel_x = 10'd34; pixel_y = 10'd2;
		chk("grav up active", 1'b1, 12'hFFF, 1'b1);
		pixel_x = 10'd34; pixel_y = 10'd13;
		chk("grav down dim", 1'b1, 12'h333, 1'b1);

		// --- LEFT dot ---
		grav_dir = 2'd2;
		pixel_x = 10'd28; pixel_y = 10'd8;
		chk("grav left active", 1'b1, 12'hFFF, 1'b1);

		// --- RIGHT dot ---
		grav_dir = 2'd3;
		pixel_x = 10'd40; pixel_y = 10'd8;
		chk("grav right active", 1'b1, 12'hFFF, 1'b1);

		// --- Particle bar: count=0 → no fill at x60 ---
		count = 16'd0;
		pixel_x = 10'd60; pixel_y = 10'd7;
		chk("bar empty at x60", 1'b0, 12'h000, 1'b0);

		// --- Particle bar: count large → fill at x60 (cyan) ---
		// len = count>>4; need len > (60-49)=11 → count > 176
		count = 16'd2000;   // len = 125, fills past x60
		pixel_x = 10'd60; pixel_y = 10'd7;
		chk("bar fill at x60", 1'b1, 12'h0CF, 1'b1);

		// --- Bar frame corner (x48,y3) white ---
		pixel_x = 10'd48; pixel_y = 10'd3;
		chk("bar frame", 1'b1, 12'hFFF, 1'b1);

		// --- Below the HUD (y=100) is all grid (no overlay) ---
		pixel_x = 10'd10; pixel_y = 10'd100;
		chk("below HUD empty", 1'b0, 12'h000, 1'b0);

		if (fail_count == 0)
			$display("TB tb_hud_overlay: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_hud_overlay: %0d/%0d failed (%0d total)",
			         fail_count, fail_count, pass_count + fail_count);
		$finish;
	end

endmodule
