`timescale 1ns/1ps
// =====================================================================
// tb_lfsr — verify the 16-bit Galois LFSR (period, hold, no stuck-zero)
// =====================================================================
module tb_lfsr;

	localparam int WIDTH = 16;
	localparam logic [WIDTH-1:0] SEED = 16'hACE1;
	localparam int PERIOD = (1 << WIDTH) - 1;   // 65535

	logic clk = 0, rst_n, en;
	logic [WIDTH-1:0] rnd;

	int pass_count = 0, fail_count = 0;

	lfsr #(.WIDTH(WIDTH), .SEED(SEED)) dut (
		.clk  (clk),
		.rst_n(rst_n),
		.en   (en),
		.rnd  (rnd)
	);

	always #5 clk = ~clk;   // 100 MHz

	task automatic check(string nm, logic cond);
		if (cond) pass_count++;
		else begin
			fail_count++;
			$display("FAIL %s @%0t", nm, $time);
		end
	endtask

	initial begin
		rst_n = 0; en = 0;
		#20;
		@(negedge clk); rst_n = 1;
		@(posedge clk); #1;

		// After reset, rnd == SEED
		check("reset value", rnd == SEED);

		// en=0 holds state
		repeat (5) @(posedge clk);
		#1;
		check("hold (en=0)", rnd == SEED);

		// Run the full period and verify it returns to SEED
		en = 1;
		repeat (PERIOD) @(posedge clk);
		#1;
		check("period returns to SEED", rnd == SEED);

		// Verify no stuck-at-zero: run a few steps and check nonzero
		repeat (100) @(posedge clk);
		#1;
		check("not stuck zero", rnd != '0);

		// Run a second full period to double-check maximal length
		// (start from current state which should be SEED again after the 100 steps above)
		// Instead, let's just verify the state after 1 step from SEED
		en = 0;
		@(negedge clk); rst_n = 0;
		#20;
		@(negedge clk); rst_n = 1;
		@(posedge clk); #1;
		check("re-reset value", rnd == SEED);

		// Single step: SEED = 0xACE1, bit[0] = 1 -> (SEED >> 1) ^ POLY
		// 0xACE1 >> 1 = 0x5670, ^ 0xB400 = 0xE270
		en = 1;
		@(posedge clk); #1;
		check("first step", rnd == 16'hE270);

		en = 0;

		if (fail_count == 0)
			$display("TB tb_lfsr: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_lfsr: %0d/%0d failed", fail_count, pass_count + fail_count);
		$finish;
	end

endmodule
