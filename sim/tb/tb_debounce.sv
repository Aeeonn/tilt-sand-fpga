`timescale 1ns/1ps

module tb_debounce;

	localparam time CLK_PERIOD = 10ns;

	logic clk = 0;
	logic rst_n;
	logic in_raw;
	logic out;

	int pass_count = 0;
	int fail_count = 0;

	// Small CLK_FREQ_HZ/DEBOUNCE_MS keeps COUNT_MAX (and sim time) tiny while
	// exercising the same logic as the real CLK_FREQ_HZ=100_000_000 instance.
	debounce #(
		.CLK_FREQ_HZ (1000),
		.DEBOUNCE_MS (10)
	) dut (
		.clk    (clk),
		.rst_n  (rst_n),
		.in_raw (in_raw),
		.out    (out)
	);

	always #(CLK_PERIOD/2) clk = ~clk;

	// From a settled state (counter==0): 2 cycles for the synchronizer to reach
	// the new value, COUNT_MAX increments, 1 commit cycle. See SPEC_debounce.md.
	localparam int LATENCY = dut.COUNT_MAX + 3;

	// Advance one clock edge and let always_ff NBA updates settle before sampling.
	task automatic step();
		@(posedge clk);
		#1;
	endtask

	// Hold in_raw constant long enough for the synchronizer and counter to
	// fully settle (sync_q == {in_raw,in_raw}, count_q == 0) before timing
	// the next transition.
	task automatic settle();
		repeat (4) step();
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
		rst_n  = 0;
		in_raw = 0;
		repeat (3) step();
		check("out low after reset", out, 1'b0);

		@(negedge clk);
		rst_n = 1;

		// --- Clean 0 -> 1 transition: out must hold for LATENCY-1 cycles, then flip. ---
		in_raw = 1;
		for (int i = 1; i < LATENCY; i++) begin
			step();
			check($sformatf("out still 0, %0d cycle(s) into clean 0->1", i), out, 1'b0);
		end
		step();
		check("out == 1 after LATENCY cycles (clean 0->1)", out, 1'b1);

		// --- Bounce around a stable '1': out must not move. ---
		repeat (3) begin
			in_raw = 0; step();
			in_raw = 1; step();
			check("out unaffected by short bounce while high", out, 1'b1);
		end
		settle();
		check("out settled high after bounce", out, 1'b1);

		// --- Clean 1 -> 0 transition. ---
		in_raw = 0;
		for (int i = 1; i < LATENCY; i++) begin
			step();
			check($sformatf("out still 1, %0d cycle(s) into clean 1->0", i), out, 1'b1);
		end
		step();
		check("out == 0 after LATENCY cycles (clean 1->0)", out, 1'b0);

		// --- Bounce around a stable '0': out must not move. ---
		repeat (3) begin
			in_raw = 1; step();
			in_raw = 0; step();
			check("out unaffected by short bounce while low", out, 1'b0);
		end
		settle();
		check("out settled low after bounce", out, 1'b0);

		// --- Repeat clean 0 -> 1 to confirm the module is reusable, not one-shot. ---
		in_raw = 1;
		for (int i = 1; i < LATENCY; i++) begin
			step();
			check($sformatf("out still 0, %0d cycle(s) into 2nd clean 0->1", i), out, 1'b0);
		end
		step();
		check("out == 1 after LATENCY cycles (2nd clean 0->1)", out, 1'b1);

		if (fail_count == 0)
			$display("TB tb_debounce: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_debounce: %0d/%0d failed (%0d total)",
								fail_count, fail_count, pass_count + fail_count);

		$finish;
	end

endmodule
