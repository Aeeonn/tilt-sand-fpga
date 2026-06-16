// UART receiver, 8N1, LSB-first, with 2-FF input synchronizer.
// See docs/SPEC_uart_rx.md.
module uart_rx #(
		parameter int CLKS_PER_BIT = 868 // 100e6 / 115200
) (
		input  logic       clk,
		input  logic       rst_n,
		input  logic       rx_serial,
		output logic [7:0] data_out,
		output logic       rx_valid,
		output logic       rx_error
);

	localparam int HALF_BIT = (CLKS_PER_BIT-1)/2;

	// 2-FF synchronizer for the async serial input.
	logic rx_meta, rx_sync;
	always_ff @(posedge clk) begin
		if (!rst_n) begin
			rx_meta <= 1'b1;
			rx_sync <= 1'b1;
		end else begin
			rx_meta <= rx_serial;
			rx_sync <= rx_meta;
		end
	end

	typedef enum logic [1:0] {S_IDLE, S_START, S_DATA, S_STOP} state_e;
	state_e state_q, state_d;

	logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt_q, clk_cnt_d;
	logic [2:0] bit_idx_q, bit_idx_d;
	logic [7:0] data_q, data_d;
	logic       rx_valid_d, rx_error_d;

	always_comb begin
		state_d    = state_q;
		clk_cnt_d  = clk_cnt_q;
		bit_idx_d  = bit_idx_q;
		data_d     = data_q;
		rx_valid_d = 1'b0;
		rx_error_d = 1'b0;

		unique case (state_q)
			S_IDLE: begin
				if (!rx_sync) begin
					clk_cnt_d = '0;
					state_d   = S_START;
				end
			end

			S_START: begin
				if (clk_cnt_q == HALF_BIT) begin
					if (!rx_sync) begin
						clk_cnt_d = '0;
						bit_idx_d = '0;
						state_d   = S_DATA;
					end else begin
						state_d = S_IDLE; // false start (glitch)
					end
				end else begin
					clk_cnt_d = clk_cnt_q + 1'b1;
				end
			end

			S_DATA: begin
				if (clk_cnt_q == CLKS_PER_BIT-1) begin
					clk_cnt_d         = '0;
					data_d[bit_idx_q] = rx_sync;
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
				if (clk_cnt_q == CLKS_PER_BIT-1) begin
					clk_cnt_d  = '0;
					rx_valid_d = 1'b1;
					rx_error_d = ~rx_sync; // stop bit should be 1
					state_d    = S_IDLE;
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
			rx_valid  <= 1'b0;
			rx_error  <= 1'b0;
		end else begin
			state_q   <= state_d;
			clk_cnt_q <= clk_cnt_d;
			bit_idx_q <= bit_idx_d;
			data_q    <= data_d;
			rx_valid  <= rx_valid_d;
			rx_error  <= rx_error_d;
		end
	end

	assign data_out = data_q;

endmodule
