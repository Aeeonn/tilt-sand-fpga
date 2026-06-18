// =====================================================================
// block_rule — Margolus 2×2 block physics (combinational wrapper)
// =====================================================================
// Given a 2×2 block of cells, gravity direction, and a 2-bit random value,
// produces the updated block after one CA step. Materials are permuted under
// the GROUPED invariant (water family members WATER/WATER_R/WATER_L convert
// among themselves; every other material count is preserved).
//
// Materials: EMPTY(0), WALL(1), SAND(2), WATER(3), WATER_R(4), WATER_L(5),
// and 6-15 (reserved). Density: EMPTY(0) < water family(1) < granular(2) <
// WALL(3). Water carries a horizontal-momentum tag so it sloshes (waves that
// overshoot and decay) and can rise in communicating vessels.
//
// Six sequential phases, split across THREE sub-modules so the engine can
// pipeline them across three clock cycles for timing closure:
//   block_rule_fall   — 1. vertical fall (tag-shedding)  2. granular diagonal
//   block_rule_flow   — 3. rise (momentum→height)        4. advection
//   block_rule_settle — 5. cohesive repack               6. damping
//
// This wrapper rotates the block to the canonical-DOWN orientation, chains all
// three stages combinationally, and rotates back. Velocity tag *values* ride
// through the rotation unchanged, so water sloshes perpendicular to whatever
// gravity is active. It is the reference for tb_block_rule and matches
// sim/golden/block_rule.py. margolus_engine instantiates the three stages with
// registers between them. See docs/SPEC_block_rule.md.
// =====================================================================
module block_rule #(
		parameter int CELL_BITS = 4
) (
		input  logic [1:0]           grav_dir,   // 0=DOWN 1=UP 2=LEFT 3=RIGHT
		input  logic [1:0]           rnd,        // {r1, r0} random bits
		input  logic [CELL_BITS-1:0] c00, c01,   // top-left, top-right
		                             c10, c11,   // bottom-left, bottom-right
		output logic [CELL_BITS-1:0] n00, n01,
		                             n10, n11
);

	// Rotate input so gravity maps to DOWN (a=TL b=TR c=BL d=BR).
	logic [CELL_BITS-1:0] a, b, c, d;
	always_comb begin
		case (grav_dir)
			2'd0: begin a = c00; b = c01; c = c10; d = c11; end  // DOWN
			2'd1: begin a = c11; b = c10; c = c01; d = c00; end  // UP    (180°)
			2'd2: begin a = c10; b = c00; c = c11; d = c01; end  // LEFT  (CW)
			2'd3: begin a = c01; b = c11; c = c00; d = c10; end  // RIGHT (CCW)
			default: begin a = c00; b = c01; c = c10; d = c11; end
		endcase
	end

	// Stage 1: vertical fall (tag-shedding) + granular diagonal (uses r0).
	logic [CELL_BITS-1:0] f_a, f_b, f_c, f_d;
	block_rule_fall #(.CELL_BITS(CELL_BITS)) u_fall (
		.rnd(rnd[0]),
		.a_i(a), .b_i(b), .c_i(c), .d_i(d),
		.a_o(f_a), .b_o(f_b), .c_o(f_c), .d_o(f_d)
	);

	// Stage 2: rise + momentum advection (uses r0 for lossy reflection).
	logic [CELL_BITS-1:0] g_a, g_b, g_c, g_d;
	block_rule_flow #(.CELL_BITS(CELL_BITS)) u_flow (
		.rnd(rnd[0]),
		.a_i(f_a), .b_i(f_b), .c_i(f_c), .d_i(f_d),
		.a_o(g_a), .b_o(g_b), .c_o(g_c), .d_o(g_d)
	);

	// Stage 3: cohesive repack + damping (uses r0 & r1 for the damp gate).
	logic [CELL_BITS-1:0] s_a, s_b, s_c, s_d;
	block_rule_settle #(.CELL_BITS(CELL_BITS)) u_settle (
		.rnd0(rnd[0]), .rnd1(rnd[1]),
		.a_i(g_a), .b_i(g_b), .c_i(g_c), .d_i(g_d),
		.a_o(s_a), .b_o(s_b), .c_o(s_c), .d_o(s_d)
	);

	// Rotate result back to the original orientation.
	always_comb begin
		case (grav_dir)
			2'd0: begin n00 = s_a; n01 = s_b; n10 = s_c; n11 = s_d; end  // DOWN
			2'd1: begin n00 = s_d; n01 = s_c; n10 = s_b; n11 = s_a; end  // UP
			2'd2: begin n00 = s_b; n01 = s_d; n10 = s_a; n11 = s_c; end  // LEFT
			2'd3: begin n00 = s_c; n01 = s_a; n10 = s_d; n11 = s_b; end  // RIGHT
			default: begin n00 = s_a; n01 = s_b; n10 = s_c; n11 = s_d; end
		endcase
	end

endmodule
