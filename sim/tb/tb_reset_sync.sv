`timescale 1ns/1ps

module tb_reset_sync;

	localparam int STAGES = 2;
	localparam time CLK_PERIOD = 10ns; // 100 MHz

	logic clk = 0;
	logic arst_n;
	logic rst_n;

	int pass_count = 0;
	int fail_count = 0;

	reset_sync #(.STAGES(STAGES)) dut (
		.clk    (clk),
		.arst_n (arst_n),
		.rst_n  (rst_n)
	);

	always #(CLK_PERIOD/2) clk = ~clk;

	// Advance one clock edge and let always_ff NBA updates settle before sampling.
	task automatic step();
		@(posedge clk);
		#1;
	endtask

	task automatic check(string name, logic got, logic exp);
		if (got === exp) begin
			pass_count++;
		end else begin
			fail_count++;
			$display("FAIL: %s - expected %b got %b at time %0t", name, exp, got, $time);
		end
	endtask

	initial begin
		// Power-on: hold async reset asserted.
		arst_n = 0;
		repeat (2) step();
		check("reset asserted at power-on", rst_n, 1'b0);

		// Release away from an edge, then walk through the synchronizer.
		@(negedge clk);
		arst_n = 1;
		for (int i = 0; i < STAGES-1; i++) begin
			step();
			check($sformatf("rst_n still low %0d cycle(s) after release", i+1), rst_n, 1'b0);
		end
		step();
		check("rst_n high after STAGES cycles", rst_n, 1'b1);

		repeat (2) step();
		check("rst_n stays high in steady state", rst_n, 1'b1);

		// Async assert mid-cycle: rst_n must drop without waiting for a clock edge.
		step();
		arst_n = 0;
		#1;
		check("rst_n asserts asynchronously", rst_n, 1'b0);

		// Release again from a different phase, confirm the same release timing.
		@(negedge clk);
		arst_n = 1;
		for (int i = 0; i < STAGES-1; i++) begin
			step();
			check($sformatf("rst_n still low %0d cycle(s) after 2nd release", i+1), rst_n, 1'b0);
		end
		step();
		check("rst_n high after 2nd release", rst_n, 1'b1);

		if (fail_count == 0)
			$display("TB tb_reset_sync: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_reset_sync: %0d/%0d failed (%0d total)",
								fail_count, fail_count, pass_count + fail_count);

		$finish;
	end

endmodule
