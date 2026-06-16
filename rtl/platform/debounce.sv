// 2-FF synchronizer + saturating-counter debouncer. See docs/SPEC_debounce.md.
module debounce #(
		parameter int CLK_FREQ_HZ = 100_000_000,
		parameter int DEBOUNCE_MS = 10
) (
		input  logic clk,
		input  logic rst_n,
		input  logic in_raw,
		output logic out
);

	localparam int COUNT_MAX = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
	localparam int CW = $clog2(COUNT_MAX + 1);

	logic [1:0]    sync_q;
	logic [CW-1:0] count_q;
	logic          out_q;

	wire in_sync = sync_q[1];

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) sync_q <= '0;
		else        sync_q <= {sync_q[0], in_raw};
	end

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			count_q <= '0;
			out_q   <= 1'b0;
		end else if (in_sync != out_q) begin
			if (count_q == CW'(COUNT_MAX)) begin
				out_q   <= in_sync;
				count_q <= '0;
			end else begin
				count_q <= count_q + 1'b1;
			end
		end else begin
			count_q <= '0;
		end
	end

	assign out = out_q;

endmodule
