// =====================================================================
// block_rule_settle — Margolus block physics, stage 2 (combinational)
// =====================================================================
// Last two phases of the block rule on the canonical-DOWN block:
//   3. Water level    — fluid spreads horizontally into adjacent EMPTY,
//                       rnd-biased so it converges to a flat surface.
//   4. Sand diagonal  — granular cell blocked by a solid below slides
//                       into an empty diagonal, PROBABILISTIC (rnd) for a
//                       steeper angle of repose (real pyramids).
// Consumes the (already-rotated) output of block_rule_fall. The engine
// registers between the two stages for timing. See docs/SPEC_block_rule.md.
// =====================================================================
module block_rule_settle #(
		parameter int CELL_BITS = 4
) (
		input  logic                 rnd,
		input  logic [CELL_BITS-1:0] a_i, b_i, c_i, d_i,
		output logic [CELL_BITS-1:0] a_o, b_o, c_o, d_o
);

	localparam logic [CELL_BITS-1:0] MAT_EMPTY = 4'd0;
	localparam logic [CELL_BITS-1:0] MAT_WALL  = 4'd1;
	localparam logic [CELL_BITS-1:0] MAT_WATER = 4'd3;

	function automatic logic is_granular(input logic [CELL_BITS-1:0] mat);
		is_granular = (mat != MAT_EMPTY) && (mat != MAT_WALL) && (mat != MAT_WATER);
	endfunction

	logic [CELL_BITS-1:0] a, b, c, d;

	always_comb begin
		a = a_i; b = b_i; c = c_i; d = d_i;

		// Phase 3: water horizontal level (rnd-biased per row)
		if      ((a == MAT_WATER) && (b == MAT_EMPTY) &&  rnd) {a, b} = {b, a};
		else if ((b == MAT_WATER) && (a == MAT_EMPTY) && !rnd) {a, b} = {b, a};
		if      ((c == MAT_WATER) && (d == MAT_EMPTY) &&  rnd) {c, d} = {d, c};
		else if ((d == MAT_WATER) && (c == MAT_EMPTY) && !rnd) {c, d} = {d, c};

		// Phase 4: granular diagonal slide (probabilistic)
		if      (is_granular(a) && (c != MAT_EMPTY) && (c != MAT_WATER) && (d == MAT_EMPTY) &&  rnd)
			{a, d} = {d, a};
		else if (is_granular(b) && (d != MAT_EMPTY) && (d != MAT_WATER) && (c == MAT_EMPTY) && !rnd)
			{b, c} = {c, b};

		a_o = a; b_o = b; c_o = c; d_o = d;
	end

endmodule
