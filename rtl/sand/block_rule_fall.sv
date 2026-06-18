// =====================================================================
// block_rule_fall — Margolus block physics, stage 1 of 3 (combinational)
// =====================================================================
// First two phases of the block rule on the canonical-DOWN block:
//   1. Vertical fall — heavier cell sinks below a lighter one (density). A
//      water cell that moves vertically sheds its horizontal-momentum tag
//      (becomes still WATER).
//   2. Diagonal flow — GRANULAR ONLY: sand/other granular blocked straight
//      down slides into an empty diagonal (~45° pyramids). Water is excluded
//      so its horizontal momentum is not dissipated diagonally; water spreads
//      via the momentum phases in block_rule_flow / block_rule_settle.
// Water family: WATER(3) still, WATER_R(4) +x, WATER_L(5) -x — all density 1.
// Operates already-rotated cells (a=TL b=TR c=BL d=BR). The engine registers
// this stage's output, then feeds block_rule_flow. See docs/SPEC_block_rule.md.
// =====================================================================
module block_rule_fall #(
		parameter int CELL_BITS = 4
) (
		input  logic                 rnd,        // r0: left/right diagonal tie-break
		input  logic [CELL_BITS-1:0] a_i, b_i, c_i, d_i,
		output logic [CELL_BITS-1:0] a_o, b_o, c_o, d_o
);

	localparam logic [CELL_BITS-1:0] MAT_EMPTY   = 4'd0;
	localparam logic [CELL_BITS-1:0] MAT_WALL    = 4'd1;
	localparam logic [CELL_BITS-1:0] MAT_WATER   = 4'd3;
	localparam logic [CELL_BITS-1:0] MAT_WATER_R = 4'd4;
	localparam logic [CELL_BITS-1:0] MAT_WATER_L = 4'd5;

	function automatic logic is_water(input logic [CELL_BITS-1:0] m);
		is_water = (m == MAT_WATER) || (m == MAT_WATER_R) || (m == MAT_WATER_L);
	endfunction

	function automatic logic is_mobile(input logic [CELL_BITS-1:0] mat);
		is_mobile = (mat != MAT_EMPTY) && (mat != MAT_WALL);
	endfunction

	function automatic logic [1:0] density(input logic [CELL_BITS-1:0] m);
		if (m == MAT_EMPTY)                                          density = 2'd0;
		else if (m == MAT_WATER || m == MAT_WATER_R || m == MAT_WATER_L)
		                                                            density = 2'd1;
		else if (m == MAT_WALL)                                     density = 2'd3;
		else                                                        density = 2'd2;
	endfunction

	logic [CELL_BITS-1:0] a, b, c, d;
	logic la, rb;

	always_comb begin
		a = a_i; b = b_i; c = c_i; d = d_i;

		// Phase 1: vertical fall by density. A water cell moving down sheds its
		// momentum tag (becomes still WATER); the vacated cell takes whatever
		// was below (still-tagged if that was water).
		if (is_water(a) && (density(a) > density(c))) begin
			a = is_water(c) ? MAT_WATER : c;
			c = MAT_WATER;
		end else if (is_mobile(a) && (density(a) > density(c))) begin
			{a, c} = {c, a};
		end
		if (is_water(b) && (density(b) > density(d))) begin
			b = is_water(d) ? MAT_WATER : d;
			d = MAT_WATER;
		end else if (is_mobile(b) && (density(b) > density(d))) begin
			{b, d} = {d, b};
		end

		// Phase 2: greedy diagonal flow — GRANULAR ONLY (water excluded so its
		// horizontal momentum is preserved for the slosh phases). A granular
		// top cell blocked straight down slides into an EMPTY diagonal; `rnd`
		// breaks the left/right tie when both diagonals are open.
		la = is_mobile(a) && !is_water(a) && (c != MAT_EMPTY) && (d == MAT_EMPTY);
		rb = is_mobile(b) && !is_water(b) && (d != MAT_EMPTY) && (c == MAT_EMPTY);
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

