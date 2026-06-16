// UART transmitter, 8N1, LSB-first. See docs/SPEC_uart_tx.md.
module uart_tx #(
		parameter int CLKS_PER_BIT = 868 // 100e6 / 115200
) (
		input  logic       clk,
		input  logic       rst_n,
		input  logic [7:0] data_in,
		input  logic       tx_start,
		output logic       tx_busy,
		output logic       tx_serial,
		output logic       tx_done
);

	typedef enum logic [1:0] {S_IDLE, S_START, S_DATA, S_STOP} state_e;
	state_e state_q, state_d;

	logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt_q, clk_cnt_d;
	logic [2:0] bit_idx_q, bit_idx_d;
	logic [7:0] data_q, data_d;
	logic       tx_serial_d;
	logic       tx_done_d;

	always_comb begin
		state_d     = state_q;
		clk_cnt_d   = clk_cnt_q;
		bit_idx_d   = bit_idx_q;
		data_d      = data_q;
		tx_serial_d = 1'b1;
		tx_done_d   = 1'b0;

		unique case (state_q)
			S_IDLE: begin
				if (tx_start) begin
					data_d    = data_in;
					clk_cnt_d = '0;
					state_d   = S_START;
				end
			end

			S_START: begin
				tx_serial_d = 1'b0;
				if (clk_cnt_q == CLKS_PER_BIT-1) begin
					clk_cnt_d = '0;
					bit_idx_d = '0;
					state_d   = S_DATA;
				end else begin
					clk_cnt_d = clk_cnt_q + 1'b1;
				end
			end

			S_DATA: begin
				tx_serial_d = data_q[bit_idx_q];
				if (clk_cnt_q == CLKS_PER_BIT-1) begin
					clk_cnt_d = '0;
					if (bit_idx_q == 3'd7) begin
						state_d = S_STOP;
					end else begin
						bit_idx_d = bit_idx_q + 1'b1;
					end
				end else begin
					clk_cnt_d = clk_cnt_q + 1'b1;
				end
			end

			S_STOP: begin
				tx_serial_d = 1'b1;
				if (clk_cnt_q == CLKS_PER_BIT-1) begin
					clk_cnt_d = '0;
					tx_done_d = 1'b1;
					state_d   = S_IDLE;
				end else begin
					clk_cnt_d = clk_cnt_q + 1'b1;
				end
			end

			default: state_d = S_IDLE;
		endcase
	end

	always_ff @(posedge clk) begin
		if (!rst_n) begin
			state_q   <= S_IDLE;
			clk_cnt_q <= '0;
			bit_idx_q <= '0;
			data_q    <= '0;
			tx_serial <= 1'b1;
			tx_done   <= 1'b0;
		end else begin
			state_q   <= state_d;
			clk_cnt_q <= clk_cnt_d;
			bit_idx_q <= bit_idx_d;
			data_q    <= data_d;
			tx_serial <= tx_serial_d;
			tx_done   <= tx_done_d;
		end
	end

	assign tx_busy = (state_q != S_IDLE);

endmodule
