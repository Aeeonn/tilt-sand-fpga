// =====================================================================
// block_rule_settle — Margolus block physics, stage 3 of 3 (combinational)
// =====================================================================
// Final phases of the block rule on the canonical-DOWN block (water momentum):
//   5. Repack — a still WATER cell with a SUPPORTED empty neighbour flows in
//      and gains that direction's momentum. "Supported" = the cell below the
//      destination is non-empty, so water glides along surfaces as a connected
//      sheet (stays dense) instead of spraying into mid-air. This keeps the
//      body cohesive and is the source of sloshing momentum.
//   6. Damp — a moving cell occasionally (r0 & r1, ~12.5%) loses its momentum
//      so the waves decay over several swings and settle flat.
// Water family: WATER(3) still, WATER_R(4) +x, WATER_L(5) -x.
// Consumes the registered output of block_rule_flow. See docs.
// =====================================================================
module block_rule_settle #(
		parameter int CELL_BITS = 4
) (
		input  logic                 rnd0,       // r0: damp gate
		input  logic                 rnd1,       // r1: damp gate
		input  logic [CELL_BITS-1:0] a_i, b_i, c_i, d_i,
		output logic [CELL_BITS-1:0] a_o, b_o, c_o, d_o
);

	localparam logic [CELL_BITS-1:0] MAT_EMPTY   = 4'd0;
	localparam logic [CELL_BITS-1:0] MAT_WATER   = 4'd3;
	localparam logic [CELL_BITS-1:0] MAT_WATER_R = 4'd4;
	localparam logic [CELL_BITS-1:0] MAT_WATER_L = 4'd5;

	function automatic logic moving(input logic [CELL_BITS-1:0] m);
		moving = (m == MAT_WATER_R) || (m == MAT_WATER_L);
	endfunction

	logic [CELL_BITS-1:0] a, b, c, d;

	always_comb begin
		a = a_i; b = b_i; c = c_i; d = d_i;

		// Phase 5: cohesive repack — a still water cell flows into a SUPPORTED
		// empty neighbour, gaining that direction's momentum. Top row (a,b) is
		// supported when the cell below the destination (d for a→b, c for b→a)
		// is non-empty; the bottom row (c,d) sits on the block below.
		if      ((a == MAT_WATER) && (b == MAT_EMPTY) && (d != MAT_EMPTY)) begin
			a = MAT_EMPTY; b = MAT_WATER_R;
		end else if ((b == MAT_WATER) && (a == MAT_EMPTY) && (c != MAT_EMPTY)) begin
			a = MAT_WATER_L; b = MAT_EMPTY;
		end
		if      ((c == MAT_WATER) && (d == MAT_EMPTY)) begin
			c = MAT_EMPTY; d = MAT_WATER_R;
		end else if ((d == MAT_WATER) && (c == MAT_EMPTY)) begin
			c = MAT_WATER_L; d = MAT_EMPTY;
		end

		// Phase 6: gentle damping (r0 & r1) so waves lose energy over time.
		if (moving(a) && rnd0 && rnd1) a = MAT_WATER;
		if (moving(d) && rnd0 && rnd1) d = MAT_WATER;

		a_o = a; b_o = b; c_o = c; d_o = d;
	end

endmodule

