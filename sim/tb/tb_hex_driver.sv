`timescale 1ns/1ps

module tb_hex_driver;

	logic [3:0] value;
	logic [6:0] seg;

	logic [6:0] expected [0:15];

	int pass_count = 0;
	int fail_count = 0;

	hex_driver dut (
		.value (value),
		.seg   (seg)
	);

	task automatic check(string name, logic [6:0] got, logic [6:0] exp);
		if (got === exp) begin
			pass_count++;
		end else begin
			fail_count++;
			$display("FAIL: %s - expected %07b got %07b at time %0t", name, exp, got, $time);
		end
	endtask

	initial begin
		$readmemb("sim/golden/hex_driver_vectors.mem", expected);

		for (int v = 0; v < 16; v++) begin
			value = v[3:0];
			#1;
			check($sformatf("seg pattern for value=0x%0h", v), seg, expected[v]);
		end

		if (fail_count == 0)
			$display("TB tb_hex_driver: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_hex_driver: %0d/%0d failed (%0d total)",
								fail_count, fail_count, pass_count + fail_count);

		$finish;
	end

endmodule
