// 2+ stage async-assert / sync-deassert reset synchronizer.
// See docs/SPEC_reset_sync.md.
module reset_sync #(
		parameter int STAGES = 2
) (
		input  logic clk,
		input  logic arst_n,
		output logic rst_n
);

	initial assert (STAGES >= 2)
		else $error("reset_sync: STAGES must be >= 2");

	logic [STAGES-1:0] sync_q;

	always_ff @(posedge clk or negedge arst_n) begin
		if (!arst_n) sync_q <= '0;
		else sync_q <= {sync_q[STAGES-2:0], 1'b1};
	end

	assign rst_n = sync_q[STAGES-1];

endmodule
