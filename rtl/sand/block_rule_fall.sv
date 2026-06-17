// =====================================================================
// block_rule_fall — Margolus block physics, stage 1 (combinational)
// =====================================================================
// First two phases of the block rule on the canonical-DOWN block:
//   1. Vertical fall   — heavier cell sinks below a lighter one (density).
//   2. Water diagonal  — top fluid blocked straight down drains to an
//                        empty diagonal (water flows around obstacles).
// Operates already-rotated cells (a=TL b=TR c=BL d=BR). The engine
// registers the output of this stage, then feeds block_rule_settle, so
// the 4-phase rule is split across two clock cycles for timing closure.
// See docs/SPEC_block_rule.md.
// =====================================================================
module block_rule_fall #(
		parameter int CELL_BITS = 4
) (
		input  logic [CELL_BITS-1:0] a_i, b_i, c_i, d_i,
		output logic [CELL_BITS-1:0] a_o, b_o, c_o, d_o
);

	localparam logic [CELL_BITS-1:0] MAT_EMPTY = 4'd0;
	localparam logic [CELL_BITS-1:0] MAT_WALL  = 4'd1;
	localparam logic [CELL_BITS-1:0] MAT_WATER = 4'd3;

	function automatic logic [1:0] density(input logic [CELL_BITS-1:0] mat);
		case (mat)
			MAT_EMPTY: density = 2'd0;
			MAT_WATER: density = 2'd1;
			MAT_WALL:  density = 2'd3;  // immovable: nothing is denser
			default:   density = 2'd2;
		endcase
	endfunction

	function automatic logic is_mobile(input logic [CELL_BITS-1:0] mat);
		is_mobile = (mat != MAT_EMPTY) && (mat != MAT_WALL);
	endfunction

	logic [CELL_BITS-1:0] a, b, c, d;

	always_comb begin
		a = a_i; b = b_i; c = c_i; d = d_i;

		// Phase 1: vertical fall (each column independently, by density)
		if (is_mobile(a) && (density(a) > density(c))) {a, c} = {c, a};
		if (is_mobile(b) && (density(b) > density(d))) {b, d} = {d, b};

		// Phase 2: water diagonal flow
		if      ((a == MAT_WATER) && (c != MAT_EMPTY) && (d == MAT_EMPTY))
			{a, d} = {d, a};
		else if ((b == MAT_WATER) && (d != MAT_EMPTY) && (c == MAT_EMPTY))
			{b, c} = {c, b};

		a_o = a; b_o = b; c_o = c; d_o = d;
	end

endmodule
