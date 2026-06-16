// UART peek/poke register monitor protocol. See docs/SPEC_uart_monitor.md.
module uart_monitor (
		input  logic       clk,
		input  logic       rst_n,

		input  logic       rx_valid,
		input  logic [7:0] rx_data,

		input  logic       tx_busy,
		output logic       tx_start,
		output logic [7:0] tx_data,

		output logic [7:0] regs [16]
);

	localparam logic [7:0] CMD_PEEK = 8'h52; // 'R'
	localparam logic [7:0] CMD_POKE = 8'h57; // 'W'

	typedef enum logic [2:0] {
		S_IDLE, S_POKE_ADDR, S_POKE_DATA, S_PEEK_ADDR, S_SEND
	} state_e;
	state_e state_q, state_d;

	logic [3:0] addr_q, addr_d;
	logic [7:0] send_byte_q, send_byte_d;
	logic       tx_start_d;
	logic [7:0] tx_data_d;
	logic [7:0] regs_q [16], regs_d [16];

	always_comb begin
		state_d     = state_q;
		addr_d      = addr_q;
		send_byte_d = send_byte_q;
		tx_start_d  = 1'b0;
		tx_data_d   = tx_data;
		regs_d      = regs_q;

		unique case (state_q)
			S_IDLE: begin
				if (rx_valid) begin
					if (rx_data == CMD_PEEK)      state_d = S_PEEK_ADDR;
					else if (rx_data == CMD_POKE) state_d = S_POKE_ADDR;
				end
			end

			S_POKE_ADDR: begin
				if (rx_valid) begin
					addr_d  = rx_data[3:0];
					state_d = S_POKE_DATA;
				end
			end

			S_POKE_DATA: begin
				if (rx_valid) begin
					regs_d[addr_q] = rx_data;
					send_byte_d    = rx_data;
					state_d        = S_SEND;
				end
			end

			S_PEEK_ADDR: begin
				if (rx_valid) begin
					send_byte_d = regs_q[rx_data[3:0]];
					state_d     = S_SEND;
				end
			end

			S_SEND: begin
				if (!tx_busy) begin
					tx_start_d = 1'b1;
					tx_data_d  = send_byte_q;
					state_d    = S_IDLE;
				end
			end

			default: state_d = S_IDLE;
		endcase
	end

	always_ff @(posedge clk) begin
		if (!rst_n) begin
			state_q     <= S_IDLE;
			addr_q      <= '0;
			send_byte_q <= '0;
			tx_start    <= 1'b0;
			tx_data     <= '0;
			for (int i = 0; i < 16; i++) regs_q[i] <= '0;
		end else begin
			state_q     <= state_d;
			addr_q      <= addr_d;
			send_byte_q <= send_byte_d;
			tx_start    <= tx_start_d;
			tx_data     <= tx_data_d;
			regs_q      <= regs_d;
		end
	end

	assign regs = regs_q;

endmodule
