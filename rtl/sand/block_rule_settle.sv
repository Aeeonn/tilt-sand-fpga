// =====================================================================
// block_rule_settle — Margolus block physics, stage 2 (combinational)
// =====================================================================
// Final phase of the block rule on the canonical-DOWN block:
//   3. Water level — THROTTLED horizontal flow: WATER spreads into an
//                    adjacent EMPTY cell in the same row, but only when the
//                    random bit `rnd` is set. Throttling leveling to ~half
//                    rate lets the (unthrottled) vertical fall outpace
//                    sideways spreading, so a falling body stays cohesive
//                    instead of dispersing into a half-density "gas". On the
//                    floor the random gating produces chaotic sloshing that
//                    still settles to a flat surface.
// Consumes the (already-rotated) output of block_rule_fall. The engine
// registers between the two stages for timing. See docs/SPEC_block_rule.md.
// =====================================================================
module block_rule_settle #(
		parameter int CELL_BITS = 4
) (
		input  logic                 rnd,        // throttle: level only when set
		input  logic [CELL_BITS-1:0] a_i, b_i, c_i, d_i,
		output logic [CELL_BITS-1:0] a_o, b_o, c_o, d_o
);

	localparam logic [CELL_BITS-1:0] MAT_EMPTY = 4'd0;
	localparam logic [CELL_BITS-1:0] MAT_WATER = 4'd3;

	logic [CELL_BITS-1:0] a, b, c, d;

	always_comb begin
		a = a_i; b = b_i; c = c_i; d = d_i;

		// Phase 3: throttled water horizontal level (each row independently).
		// Only fires when rnd is set so vertical fall outpaces sideways flow
		// (cohesive fall) and the floor sloshes chaotically before settling
		// flat. If exactly one of a row's two cells is WATER and the other
		// EMPTY, swap them.
		if (rnd) begin
			if      ((a == MAT_WATER) && (b == MAT_EMPTY)) {a, b} = {b, a};
			else if ((b == MAT_WATER) && (a == MAT_EMPTY)) {a, b} = {b, a};
			if      ((c == MAT_WATER) && (d == MAT_EMPTY)) {c, d} = {d, c};
			else if ((d == MAT_WATER) && (c == MAT_EMPTY)) {c, d} = {d, c};
		end

		a_o = a; b_o = b; c_o = c; d_o = d;
	end

endmodule
