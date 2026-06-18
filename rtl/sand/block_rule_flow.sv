// =====================================================================
// block_rule_flow — Margolus block physics, stage 2 of 3 (combinational)
// =====================================================================
// Middle phases of the block rule on the canonical-DOWN block (water momentum):
//   3. Rise   — moving water blocked horizontally with EMPTY above climbs into
//      it and REVERSES direction. Within a block, a is above c and b is above
//      d, so this redirects blocked horizontal momentum upward: water piles
//      against barriers (overshoot) and rises in communicating vessels.
//   4. Advect — tagged water glides one cell in its travel direction into an
//      EMPTY neighbour (ballistic → carries past equilibrium). Reflection off a
//      barrier is LOSSY (reverses on r0, else damps to still); two opposing
//      flows cancel to still. This sheds energy at crests/walls.
// Water family: WATER(3) still, WATER_R(4) +x, WATER_L(5) -x.
// Consumes the registered output of block_rule_fall; the engine registers this
// stage's output and feeds block_rule_settle. See docs.
// =====================================================================
module block_rule_flow #(
		parameter int CELL_BITS = 4
) (
		input  logic                 rnd,        // r0: lossy-reflection keep bit
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

	// One horizontal left/right pair: advection + lossy reflection + head-on.
	function automatic logic [2*CELL_BITS-1:0] advect(
			input logic [CELL_BITS-1:0] L, input logic [CELL_BITS-1:0] R,
			input logic r0);
		logic [CELL_BITS-1:0] nl, nr;
		nl = L; nr = R;
		if (L == MAT_WATER_R && R == MAT_EMPTY) begin
			nl = MAT_EMPTY; nr = MAT_WATER_R;            // glide right
		end else if (R == MAT_WATER_L && L == MAT_EMPTY) begin
			nl = MAT_WATER_L; nr = MAT_EMPTY;            // glide left
		end else if (L == MAT_WATER_R && R == MAT_WATER_L) begin
			nl = MAT_WATER;  nr = MAT_WATER;             // head-on damp
		end else begin
			// lossy reflection off a barrier / opposing mass
			if (L == MAT_WATER_R && R != MAT_EMPTY && !moving(R))
				nl = r0 ? MAT_WATER_L : MAT_WATER;
			if (R == MAT_WATER_L && L != MAT_EMPTY && !moving(L))
				nr = r0 ? MAT_WATER_R : MAT_WATER;
		end
		advect = {nl, nr};
	endfunction

	always_comb begin
		a = a_i; b = b_i; c = c_i; d = d_i;

		// Phase 3: RISE — blocked moving water with empty above climbs, reversing.
		if ((a == MAT_EMPTY) && (c == MAT_WATER_R) && (d != MAT_EMPTY)) begin
			a = MAT_WATER_L; c = MAT_EMPTY;
		end else if ((b == MAT_EMPTY) && (d == MAT_WATER_L) && (c != MAT_EMPTY)) begin
			b = MAT_WATER_R; d = MAT_EMPTY;
		end

		// Phase 4: momentum advection with lossy reflection / head-on damping.
		{a, b} = advect(a, b, rnd);
		{c, d} = advect(c, d, rnd);

		a_o = a; b_o = b; c_o = c; d_o = d;
	end

endmodule
