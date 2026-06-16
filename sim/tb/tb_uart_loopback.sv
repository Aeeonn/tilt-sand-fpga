`timescale 1ns/1ps

// Self-checking testbench: uart_tx -> uart_rx loopback. See docs/SPEC_uart_loopback.md.
module tb_uart_loopback;

	localparam int  CLKS_PER_BIT = 4; // small, for fast sim (HW default is 868)
	localparam time CLK_PERIOD   = 10ns;
	localparam time TIMEOUT      = 100 * CLK_PERIOD;

	logic       clk = 0;
	logic       rst_n = 0;

	logic [7:0] data_in;
	logic       tx_start, tx_busy, tx_done;
	logic       tx_serial;

	logic [7:0] data_out;
	logic       rx_valid, rx_error;

	int pass_count = 0;
	int fail_count = 0;

	uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
		.clk      (clk),
		.rst_n    (rst_n),
		.data_in  (data_in),
		.tx_start (tx_start),
		.tx_busy  (tx_busy),
		.tx_serial(tx_serial),
		.tx_done  (tx_done)
	);

	uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
		.clk      (clk),
		.rst_n    (rst_n),
		.rx_serial(tx_serial),
		.data_out (data_out),
		.rx_valid (rx_valid),
		.rx_error (rx_error)
	);

	always #(CLK_PERIOD/2) clk = ~clk;

	task automatic step();
		@(posedge clk);
		#1;
	endtask

	task automatic check(string name, logic [31:0] got, logic [31:0] exp);
		if (got === exp) pass_count++;
		else begin
			fail_count++;
			$display("FAIL: %s - expected %0d got %0d at time %0t", name, exp, got, $time);
		end
	endtask

	task automatic check_bit(string name, logic got, logic exp);
		if (got === exp) pass_count++;
		else begin
			fail_count++;
			$display("FAIL: %s - expected %b got %b at time %0t", name, exp, got, $time);
		end
	endtask

	// Pulse tx_start for one byte and wait (timeout-guarded) for rx_valid on
	// the looped-back rx_serial; check data_out/rx_error.
	task automatic send_and_check(input logic [7:0] byte_val, input string label);
		bit valid_seen;

		data_in  = byte_val;
		tx_start = 1'b1;
		step();
		tx_start = 1'b0;

		fork
			begin
				wait (rx_valid);
				valid_seen = 1'b1;
			end
			begin
				#(TIMEOUT);
			end
		join_any
		disable fork;

		check_bit({label, ": rx_valid pulses"}, valid_seen, 1'b1);
		if (valid_seen) begin
			check({label, ": data_out"}, {24'b0, data_out}, {24'b0, byte_val});
			check_bit({label, ": rx_error"}, rx_error, 1'b0);
		end

		repeat (4) step();
	endtask

	initial begin
		repeat (2) step();
		rst_n = 1'b1;
		repeat (2) step();

		send_and_check(8'h00, "byte 00");
		send_and_check(8'hFF, "byte ff");
		send_and_check(8'hA5, "byte a5");
		send_and_check(8'h3C, "byte 3c");
		send_and_check(8'h01, "byte 01");
		send_and_check(8'h80, "byte 80");

		if (fail_count == 0)
			$display("TB tb_uart_loopback: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_uart_loopback: %0d/%0d failed (%0d total)",
								fail_count, fail_count, pass_count + fail_count);

		$finish;
	end

endmodule
