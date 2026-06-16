// =====================================================================
// block_rule — Margolus 2×2 block physics (pure combinational)
// =====================================================================
// Given a 2×2 block of cells, gravity direction, and a random bit,
// produces the updated block after one CA step. Materials are permuted
// (never created/destroyed) — multiset conservation is structural.
//
// Materials: EMPTY(0), WALL(1), SAND(2), WATER(3).
// Density: EMPTY < WATER < SAND. WALL never moves.
// See docs/SPEC_block_rule.md for the full rule description.
// =====================================================================
module block_rule #(
		parameter int CELL_BITS = 4
) (
		input  logic [1:0]           grav_dir,   // 0=DOWN 1=UP 2=LEFT 3=RIGHT
		input  logic                 rnd,        // tie-break bit
		input  logic [CELL_BITS-1:0] c00, c01,   // top-left, top-right
		                             c10, c11,   // bottom-left, bottom-right
		output logic [CELL_BITS-1:0] n00, n01,
		                             n10, n11
);

	// Material IDs (must match sand_materials.py)
	localparam logic [CELL_BITS-1:0] MAT_EMPTY = 4'd0;
	localparam logic [CELL_BITS-1:0] MAT_WALL  = 4'd1;
	localparam logic [CELL_BITS-1:0] MAT_SAND  = 4'd2;
	localparam logic [CELL_BITS-1:0] MAT_WATER = 4'd3;

	// --- Helper: "falls into" — src is heavier and mobile, dst is lighter ---
	function automatic logic falls_into(input logic [CELL_BITS-1:0] src, dst);
		// WALL never moves; EMPTY never falls
		if (src == MAT_WALL || dst == MAT_WALL) return 1'b0;
		if (src == MAT_EMPTY) return 1'b0;
		// SAND falls into EMPTY or WATER; WATER falls into EMPTY
		case (src)
			MAT_SAND:  return (dst == MAT_EMPTY || dst == MAT_WATER);
			MAT_WATER: return (dst == MAT_EMPTY);
			default:   return 1'b0;
		endcase
	endfunction

	// --- Rotate input block to canonical DOWN orientation ---
	logic [CELL_BITS-1:0] r00, r01, r10, r11;

	always_comb begin
		case (grav_dir)
			2'd0: begin r00 = c00; r01 = c01; r10 = c10; r11 = c11; end
			2'd1: begin r00 = c11; r01 = c10; r10 = c01; r11 = c00; end
			2'd2: begin r00 = c10; r01 = c00; r10 = c11; r11 = c01; end
			2'd3: begin r00 = c01; r01 = c11; r10 = c00; r11 = c10; end
			default: begin r00 = c00; r01 = c01; r10 = c10; r11 = c11; end
		endcase
	end

	// --- Phase 1: vertical fall (each column independently) ---
	logic [CELL_BITS-1:0] v00, v01, v10, v11;

	always_comb begin
		v00 = r00; v01 = r01; v10 = r10; v11 = r11;

		// Left column
		if (falls_into(r00, r10)) begin
			v00 = r10;
			v10 = r00;
		end

		// Right column
		if (falls_into(r01, r11)) begin
			v01 = r11;
			v11 = r01;
		end
	end

	// --- Phase 2: diagonal slide (SAND only — granular behavior) ---
	logic [CELL_BITS-1:0] d00, d01, d10, d11;
	logic left_can, right_can;

	always_comb begin
		d00 = v00; d01 = v01; d10 = v10; d11 = v11;

		// SAND slides diagonally only when blocked by non-displaceable below
		// (blocked = not EMPTY and not WATER, since sand already fell through those)
		left_can  = (v00 == MAT_SAND) && (v10 != MAT_EMPTY) && (v10 != MAT_WATER) && (v11 == MAT_EMPTY);
		right_can = (v01 == MAT_SAND) && (v11 != MAT_EMPTY) && (v11 != MAT_WATER) && (v10 == MAT_EMPTY);

		if (left_can && right_can) begin
			if (rnd) begin
				d00 = v11; d11 = v00;
			end else begin
				d01 = v10; d10 = v01;
			end
		end else if (left_can) begin
			d00 = v11; d11 = v00;
		end else if (right_can) begin
			d01 = v10; d10 = v01;
		end
	end

	// --- Phase 3: lateral spread (WATER — fluid behavior) ---
	logic [CELL_BITS-1:0] w00, w01, w10, w11;
	logic wl_top, wr_top, wl_bot, wr_bot;

	always_comb begin
		w00 = d00; w01 = d01; w10 = d10; w11 = d11;

		// Top row: WATER spreads sideways when blocked below
		wl_top = (d00 == MAT_WATER) && (d10 != MAT_EMPTY) && (d01 == MAT_EMPTY);
		wr_top = (d01 == MAT_WATER) && (d11 != MAT_EMPTY) && (d00 == MAT_EMPTY);

		if (wl_top && wr_top) begin
			if (rnd) begin
				w00 = d01; w01 = d00;
			end
			// else: neither moves (symmetric deadlock without rnd)
		end else if (wl_top) begin
			w00 = d01; w01 = d00;
		end else if (wr_top) begin
			w01 = d00; w00 = d01;
		end

		// Bottom row: WATER spreads sideways (unconditionally — it's at the bottom)
		wl_bot = (w10 == MAT_WATER) && (w11 == MAT_EMPTY);
		wr_bot = (w11 == MAT_WATER) && (w10 == MAT_EMPTY);

		if (wl_bot && wr_bot) begin
			if (rnd) begin
				w10 = d11; w11 = d10;
			end
		end else if (wl_bot) begin
			w10 = d11; w11 = d10;
		end else if (wr_bot) begin
			w11 = d10; w10 = d11;
		end
	end

	// --- Rotate result back from canonical DOWN to original orientation ---
	always_comb begin
		case (grav_dir)
			2'd0: begin n00 = w00; n01 = w01; n10 = w10; n11 = w11; end
			2'd1: begin n00 = w11; n01 = w10; n10 = w01; n11 = w00; end
			2'd2: begin n00 = w01; n01 = w11; n10 = w00; n11 = w10; end
			2'd3: begin n00 = w10; n01 = w00; n10 = w11; n11 = w01; end
			default: begin n00 = w00; n01 = w01; n10 = w10; n11 = w11; end
		endcase
	end

endmodule
