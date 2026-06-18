// =====================================================================
// block_rule_settle — Margolus block physics, stage 2 (combinational)
// =====================================================================
// Final phase of the block rule on the canonical-DOWN block:
//   3. Water level — GREEDY horizontal flow: WATER spreads into an adjacent
//                    EMPTY cell in the same row. Combined with the diagonal
//                    flow in stage 1 and the Margolus phase alternation, this
//                    lets water level out to a flat surface quickly.
// Consumes the (already-rotated) output of block_rule_fall. The engine
// registers between the two stages for timing. See docs/SPEC_block_rule.md.
// =====================================================================
module block_rule_settle #(
		parameter int CELL_BITS = 4
) (
		input  logic [CELL_BITS-1:0] a_i, b_i, c_i, d_i,
		output logic [CELL_BITS-1:0] a_o, b_o, c_o, d_o
);

	localparam logic [CELL_BITS-1:0] MAT_EMPTY = 4'd0;
	localparam logic [CELL_BITS-1:0] MAT_WATER = 4'd3;

	logic [CELL_BITS-1:0] a, b, c, d;

	always_comb begin
		a = a_i; b = b_i; c = c_i; d = d_i;

		// Phase 3: greedy water horizontal level (each row independently).
		// If exactly one of a row's two cells is WATER and the other EMPTY,
		// swap them. Over the alternating Margolus lattice this redistributes
		// water sideways until the surface is flat.
		if      ((a == MAT_WATER) && (b == MAT_EMPTY)) {a, b} = {b, a};
		else if ((b == MAT_WATER) && (a == MAT_EMPTY)) {a, b} = {b, a};
		if      ((c == MAT_WATER) && (d == MAT_EMPTY)) {c, d} = {d, c};
		else if ((d == MAT_WATER) && (c == MAT_EMPTY)) {c, d} = {d, c};

		a_o = a; b_o = b; c_o = c; d_o = d;
	end

endmodule
