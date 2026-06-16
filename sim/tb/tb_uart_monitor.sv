`timescale 1ns/1ps

// Self-checking testbench for uart_monitor. See docs/SPEC_uart_monitor.md.
module tb_uart_monitor;

	localparam time CLK_PERIOD = 10ns;

	logic       clk = 0;
	logic       rst_n = 0;
	logic       rx_valid = 1'b0;
	logic [7:0] rx_data = 8'h00;
	logic       tx_busy = 1'b0;
	logic       tx_start;
	logic [7:0] tx_data;
	logic [7:0] regs [16];

	int pass_count = 0;
	int fail_count = 0;

	uart_monitor dut (
		.clk     (clk),
		.rst_n   (rst_n),
		.rx_valid(rx_valid),
		.rx_data (rx_data),
		.tx_busy (tx_busy),
		.tx_start(tx_start),
		.tx_data (tx_data),
		.regs    (regs)
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

	// Pulse rx_valid for one cycle with the given byte, then two idle cycles.
	task automatic send_byte(input logic [7:0] b);
		rx_valid = 1'b1;
		rx_data  = b;
		step();
		rx_valid = 1'b0;
		repeat (2) step();
	endtask

	// Recorded tx bytes, one entry per tx_start pulse.
	logic [7:0] tx_q [$];

	always @(posedge clk) begin
		#1;
		if (tx_start) tx_q.push_back(tx_data);
	end

	initial begin
		repeat (2) step();
		rst_n = 1'b1;
		repeat (2) step();

		// POKE reg[3] = 0xA5, then PEEK reg[3] -> expect 0xA5
		send_byte(8'h57); send_byte(8'h03); send_byte(8'hA5);
		send_byte(8'h52); send_byte(8'h03);

		// POKE reg[15] = 0x42
		send_byte(8'h57); send_byte(8'h0F); send_byte(8'h42);

		// Unknown command byte, ignored
		send_byte(8'h99);

		// PEEK reg[0] -> still 0x00 (untouched)
		send_byte(8'h52); send_byte(8'h00);

		repeat (4) step(); // let final tx_start settle

		check("regs[3]",  {24'b0, regs[3]},  {24'b0, 8'hA5});
		check("regs[15]", {24'b0, regs[15]}, {24'b0, 8'h42});
		check("regs[0]",  {24'b0, regs[0]},  {24'b0, 8'h00});

		check("tx_q.size", tx_q.size(), 32'd4);
		if (tx_q.size() == 4) begin
			check("tx[0] (poke echo 0xA5)", {24'b0, tx_q[0]}, {24'b0, 8'hA5});
			check("tx[1] (peek reg3 0xA5)", {24'b0, tx_q[1]}, {24'b0, 8'hA5});
			check("tx[2] (poke echo 0x42)", {24'b0, tx_q[2]}, {24'b0, 8'h42});
			check("tx[3] (peek reg0 0x00)", {24'b0, tx_q[3]}, {24'b0, 8'h00});
		end

		if (fail_count == 0)
			$display("TB tb_uart_monitor: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_uart_monitor: %0d/%0d failed (%0d total)",
								fail_count, fail_count, pass_count + fail_count);

		$finish;
	end

endmodule
