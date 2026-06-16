`timescale 1ns/1ps

// Self-checking testbench for uart_tx. See docs/SPEC_uart_tx.md.
module tb_uart_tx;

	localparam int  CLKS_PER_BIT = 4; // small, for fast sim (HW default is 868)
	localparam time CLK_PERIOD   = 10ns;

	logic       clk = 0;
	logic       rst_n = 0;
	logic [7:0] data_in = '0;
	logic       tx_start = 0;
	logic       tx_busy, tx_serial, tx_done;

	int pass_count = 0;
	int fail_count = 0;

	uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
		.clk      (clk),
		.rst_n    (rst_n),
		.data_in  (data_in),
		.tx_start (tx_start),
		.tx_busy  (tx_busy),
		.tx_serial(tx_serial),
		.tx_done  (tx_done)
	);

	always #(CLK_PERIOD/2) clk = ~clk;

	task automatic step();
		@(posedge clk);
		#1;
	endtask

	task automatic check_bit(string name, logic got, logic exp);
		if (got === exp) pass_count++;
		else begin
			fail_count++;
			$display("FAIL: %s - expected %b got %b at time %0t", name, exp, got, $time);
		end
	endtask

	// Send one byte; check the framed bit sequence (sampled on the first cycle of
	// each bit's CLKS_PER_BIT-cycle window) plus tx_busy/tx_done/idle behavior.
	task automatic send_and_check(input logic [7:0] byte_val);
		logic [9:0] expected; // {stop, d7..d0, start}
		expected = {1'b1, byte_val, 1'b0};

		check_bit("idle: tx_serial high before start", tx_serial, 1'b1);
		check_bit("idle: tx_busy low before start", tx_busy, 1'b0);

		data_in  = byte_val;
		tx_start = 1'b1;
		step();
		tx_start = 1'b0;
		step();

		for (int n = 0; n < 10; n++) begin
			check_bit($sformatf("byte %02h bit %0d value", byte_val, n), tx_serial, expected[n]);
			check_bit($sformatf("byte %02h bit %0d busy", byte_val, n), tx_busy, 1'b1);
			// Last bit: stop one cycle short so tx_done's pulse (which lands on the
			// final cycle of the stop bit's window, since tx_done lags state by 1
			// cycle) can be observed below.
			repeat (n < 9 ? CLKS_PER_BIT : CLKS_PER_BIT-1) step();
		end

		check_bit($sformatf("byte %02h done pulse", byte_val), tx_done, 1'b1);
		check_bit($sformatf("byte %02h busy low after", byte_val), tx_busy, 1'b0);
		check_bit($sformatf("byte %02h serial idle after", byte_val), tx_serial, 1'b1);

		step(); // advance to clean idle (tx_done falls) before the next byte
	endtask

	initial begin
		repeat (2) step();
		rst_n = 1'b1;
		repeat (2) step();

		send_and_check(8'h00);
		send_and_check(8'hFF);
		send_and_check(8'hA5);
		send_and_check(8'h3C);
		send_and_check(8'h01);
		send_and_check(8'h80);

		if (fail_count == 0)
			$display("TB tb_uart_tx: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_uart_tx: %0d/%0d failed (%0d total)",
								fail_count, fail_count, pass_count + fail_count);

		$finish;
	end

endmodule
