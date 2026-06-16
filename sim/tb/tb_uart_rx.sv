`timescale 1ns/1ps

// Self-checking testbench for uart_rx. See docs/SPEC_uart_rx.md.
module tb_uart_rx;

	localparam int  CLKS_PER_BIT  = 16; // small, for fast sim (HW default is 868)
	localparam time CLK_PERIOD    = 10ns;
	localparam time FRAME_TIMEOUT = 12 * CLKS_PER_BIT * CLK_PERIOD;

	logic       clk = 0;
	logic       rst_n = 0;
	logic       rx_serial = 1'b1;
	logic [7:0] data_out;
	logic       rx_valid, rx_error;

	int pass_count = 0;
	int fail_count = 0;

	uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
		.clk      (clk),
		.rst_n    (rst_n),
		.rx_serial(rx_serial),
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

	// Drive a 10-bit frame {stop, d7..d0, start} onto rx_serial (one bit per
	// CLKS_PER_BIT cycles) while concurrently waiting for rx_valid (timeout-guarded):
	// with center-aligned start-bit sampling, rx_valid can pulse a few cycles before
	// the drive loop finishes, so the wait must run alongside it, not after.
	task automatic recv_and_check(input logic [9:0] frame, input logic [7:0] exp_byte,
																 input logic exp_err, input string label);
		bit valid_seen;

		fork
			begin
				for (int i = 0; i < 10; i++) begin
					rx_serial = frame[i];
					repeat (CLKS_PER_BIT) step();
				end
			end
			begin
				wait (rx_valid);
				valid_seen = 1'b1;
			end
			begin
				#(FRAME_TIMEOUT);
			end
		join_any
		disable fork;

		rx_serial = 1'b1; // ensure idle regardless of which branch finished first

		check_bit({label, ": rx_valid pulses"}, valid_seen, 1'b1);
		if (valid_seen) begin
			check({label, ": data_out"}, {24'b0, data_out}, {24'b0, exp_byte});
			check_bit({label, ": rx_error"}, rx_error, exp_err);
		end

		repeat (4) step(); // settle before next frame
	endtask

	initial begin
		repeat (2) step();
		rst_n = 1'b1;
		repeat (2) step();

		// {stop, d7..d0, start} for each byte (stop=1 => clean frame)
		recv_and_check({1'b1, 8'h00, 1'b0}, 8'h00, 1'b0, "byte 00");
		recv_and_check({1'b1, 8'hFF, 1'b0}, 8'hFF, 1'b0, "byte ff");
		recv_and_check({1'b1, 8'hA5, 1'b0}, 8'hA5, 1'b0, "byte a5");
		recv_and_check({1'b1, 8'h3C, 1'b0}, 8'h3C, 1'b0, "byte 3c");

		// Framing error: stop bit driven 0
		recv_and_check({1'b0, 8'h55, 1'b0}, 8'h55, 1'b1, "framing error");

		if (fail_count == 0)
			$display("TB tb_uart_rx: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_uart_rx: %0d/%0d failed (%0d total)",
								fail_count, fail_count, pass_count + fail_count);

		$finish;
	end

endmodule
