`timescale 1ns/1ps

`include "pll_sys_consts.svh"

module tb_pll_sys;

	// $time captured into a `longint` (rather than `time`) reads in this
	// module's time UNIT (ns), not its precision (ps). The PLL_*_PS constants
	// from pll_sys_consts.svh are in ps, so divide by 1000 (exact for all
	// values used here) before comparing.
	localparam int PS_PER_NS = 1000;

	localparam time INCLK0_PERIOD     = 20ns; // 50 MHz reference
	localparam int  N_PERIOD_SAMPLES  = 4;
	localparam time LOCK_TIMEOUT      = 10000ns;

	logic inclk0 = 0;
	logic arst;
	logic clk_100, clk_100_shift, clk_25, locked;

	int     pass_count = 0;
	int     fail_count = 0;
	longint t1, t2, t_c0, t_c1;
	bit     locked_seen;

	pll_sys dut (
		.inclk0       (inclk0),
		.arst         (arst),
		.clk_100      (clk_100),
		.clk_100_shift(clk_100_shift),
		.clk_25       (clk_25),
		.locked       (locked)
	);

	always #(INCLK0_PERIOD/2) inclk0 = ~inclk0;

	task automatic check(string name, longint got, longint exp);
		if (got === exp) begin
			pass_count++;
		end else begin
			fail_count++;
			$display("FAIL: %s - expected %0d got %0d at time %0t", name, exp, got, $time);
		end
	endtask

	task automatic check_bit(string name, logic got, logic exp);
		if (got === exp) begin
			pass_count++;
		end else begin
			fail_count++;
			$display("FAIL: %s - expected %b got %b at time %0t", name, exp, got, $time);
		end
	endtask

	initial begin
		arst = 1;
		@(posedge inclk0);
		check_bit("locked low while arst asserted", locked, 1'b0);

		repeat (4) @(posedge inclk0);
		arst = 0;

		fork
			begin
				wait (locked);
				locked_seen = 1'b1;
			end
			begin
				#(LOCK_TIMEOUT);
			end
		join_any
		disable fork;
		check_bit("locked asserts within timeout", locked_seen, 1'b1);

		// clk_100 (c0)
		for (int i = 0; i < N_PERIOD_SAMPLES; i++) begin
			@(posedge clk_100); t1 = $time;
			@(posedge clk_100); t2 = $time;
			check($sformatf("clk_100 period sample %0d", i), t2 - t1, `PLL_C0_PERIOD_PS / PS_PER_NS);
		end

		// clk_25 (c2)
		for (int i = 0; i < 2; i++) begin
			@(posedge clk_25); t1 = $time;
			@(posedge clk_25); t2 = $time;
			check($sformatf("clk_25 period sample %0d", i), t2 - t1, `PLL_C2_PERIOD_PS / PS_PER_NS);
		end

		// clk_100_shift (c1)
		for (int i = 0; i < N_PERIOD_SAMPLES; i++) begin
			@(posedge clk_100_shift); t1 = $time;
			@(posedge clk_100_shift); t2 = $time;
			check($sformatf("clk_100_shift period sample %0d", i), t2 - t1, `PLL_C1_PERIOD_PS / PS_PER_NS);
		end

		// Relative phase: clk_100_shift edge following a clk_100 edge, mod c0 period.
		@(posedge clk_100); t_c0 = $time;
		@(posedge clk_100_shift); t_c1 = $time;
		check("clk_100_shift relative phase vs clk_100",
					(t_c1 - t_c0) % (`PLL_C0_PERIOD_PS / PS_PER_NS), `PLL_C1_REL_PHASE_PS / PS_PER_NS);

		check_bit("locked still high after measurements", locked, 1'b1);

		if (fail_count == 0)
			$display("TB tb_pll_sys: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_pll_sys: %0d/%0d failed (%0d total)",
								fail_count, fail_count, pass_count + fail_count);

		$finish;
	end

endmodule
