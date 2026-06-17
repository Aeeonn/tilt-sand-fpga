`timescale 1ns/1ps
// =====================================================================
// tb_gravity_ctrl — verify tilt → direction mapping
// =====================================================================
module tb_gravity_ctrl;

	logic clk = 0, rst_n;
	logic signed [9:0] accel_x, accel_y;
	logic data_valid, sw_override;
	logic [1:0] sw_dir, grav_dir;

	int pass_count = 0, fail_count = 0;

	gravity_ctrl #(.THRESHOLD(50)) dut (
		.clk(clk), .rst_n(rst_n),
		.accel_x(accel_x), .accel_y(accel_y),
		.data_valid(data_valid),
		.sw_override(sw_override), .sw_dir(sw_dir),
		.grav_dir(grav_dir)
	);

	always #5 clk = ~clk;

	task automatic check(string nm, logic [1:0] expected);
		if (grav_dir === expected) pass_count++;
		else begin
			fail_count++;
			$display("FAIL %s: exp %0d got %0d @%0t", nm, expected, grav_dir, $time);
		end
	endtask

	task automatic pulse_data(input signed [9:0] x, input signed [9:0] y);
		accel_x = x; accel_y = y;
		@(negedge clk); data_valid = 1;
		@(posedge clk); #1; data_valid = 0;
		@(posedge clk); #1;  // let it register
	endtask

	initial begin
		rst_n = 0; accel_x = 0; accel_y = 0; data_valid = 0;
		sw_override = 0; sw_dir = 2'd0;
		#30;
		@(negedge clk); rst_n = 1;
		repeat (3) @(posedge clk);

		// Default after reset = DOWN
		check("reset default", 2'd0);

		// Tilt right: +X dominant, above threshold
		pulse_data(10'sd200, 10'sd10);
		check("tilt right", 2'd3);

		// Tilt left: -X dominant
		pulse_data(-10'sd200, 10'sd10);
		check("tilt left", 2'd2);

		// Tilt away: +Y dominant
		pulse_data(10'sd10, 10'sd200);
		check("tilt up", 2'd1);

		// Tilt toward: -Y dominant
		pulse_data(10'sd10, -10'sd200);
		check("tilt down", 2'd0);

		// Dead-zone: both below threshold → keep last direction (DOWN)
		pulse_data(10'sd10, -10'sd10);
		check("dead-zone keeps last", 2'd0);

		// Tilt right again
		pulse_data(10'sd150, 10'sd0);
		check("tilt right again", 2'd3);

		// Dead-zone → stays RIGHT
		pulse_data(10'sd5, 10'sd5);
		check("dead-zone stays right", 2'd3);

		// SW override
		sw_override = 1; sw_dir = 2'd1;
		@(posedge clk); #1;
		check("sw override UP", 2'd1);

		sw_override = 0;
		pulse_data(-10'sd300, 10'sd50);
		check("back to accel: left", 2'd2);

		if (fail_count == 0)
			$display("TB tb_gravity_ctrl: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_gravity_ctrl: %0d/%0d failed (%0d total)",
			         fail_count, fail_count, pass_count + fail_count);
		$finish;
	end

endmodule
