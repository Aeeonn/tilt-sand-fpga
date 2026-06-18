// =====================================================================
// block_rule_fall — Margolus block physics, stage 1 (combinational)
// =====================================================================
// First two phases of the block rule on the canonical-DOWN block:
//   1. Vertical fall    — heavier cell sinks below a lighter one (density).
//   2. Diagonal flow    — GREEDY: any mobile cell blocked straight down
//                         slides into an empty diagonal (granular piles into
//                         ~45° pyramids, water drains and spreads). `rnd`
//                         only breaks the left/right tie when both open.
// Operates already-rotated cells (a=TL b=TR c=BL d=BR). The engine
// registers the output of this stage, then feeds block_rule_settle, so
// the block rule is split across two clock cycles for timing closure.
// See docs/SPEC_block_rule.md.
// =====================================================================
module block_rule_fall #(
		parameter int CELL_BITS = 4
) (
		input  logic                 rnd,        // left/right tie-break
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
	logic la, rb;

	always_comb begin
		a = a_i; b = b_i; c = c_i; d = d_i;

		// Phase 1: vertical fall (each column independently, by density)
		if (is_mobile(a) && (density(a) > density(c))) {a, c} = {c, a};
		if (is_mobile(b) && (density(b) > density(d))) {b, d} = {d, b};

		// Phase 2: GREEDY diagonal flow — any mobile cell still in the top row
		// is blocked straight down (cell below not EMPTY), so it slides into an
		// EMPTY diagonal cell. Greedy (not gated) so material spreads as fast as
		// it falls: granular → proper ~45° pyramids, water → drains and levels.
		// `rnd` only breaks the left/right tie when both diagonals are open.
		la = is_mobile(a) && (c != MAT_EMPTY) && (d == MAT_EMPTY);  // a → d (down-right)
		rb = is_mobile(b) && (d != MAT_EMPTY) && (c == MAT_EMPTY);  // b → c (down-left)
		if (la && rb) begin
			if (rnd) {a, d} = {d, a};
			else     {b, c} = {c, b};
		end else if (la) begin
			{a, d} = {d, a};
		end else if (rb) begin
			{b, c} = {c, b};
		end

		a_o = a; b_o = b; c_o = c; d_o = d;
	end

endmodule
