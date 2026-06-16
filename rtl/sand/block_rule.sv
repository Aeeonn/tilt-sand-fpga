// =====================================================================
// block_rule — Margolus 2×2 block physics (pure combinational)
// =====================================================================
// Given a 2×2 block of cells, gravity direction, and a random bit,
// produces the updated block after one CA step. Materials are permuted
// (never created/destroyed) — multiset conservation is structural.
//
// M3 MVP materials: EMPTY(0), WALL(1), SAND(2).
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

	// --- Rotate input block to canonical DOWN orientation ---
	logic [CELL_BITS-1:0] r00, r01, r10, r11;

	always_comb begin
		case (grav_dir)
			2'd0: begin  // DOWN — identity
				r00 = c00; r01 = c01; r10 = c10; r11 = c11;
			end
			2'd1: begin  // UP — rotate 180°
				r00 = c11; r01 = c10; r10 = c01; r11 = c00;
			end
			2'd2: begin  // LEFT — rotate CW (left becomes down)
				r00 = c10; r01 = c00; r10 = c11; r11 = c01;
			end
			2'd3: begin  // RIGHT — rotate CCW (right becomes down)
				r00 = c01; r01 = c11; r10 = c00; r11 = c10;
			end
			default: begin
				r00 = c00; r01 = c01; r10 = c10; r11 = c11;
			end
		endcase
	end

	// --- Phase 1: vertical fall (each column independently) ---
	logic [CELL_BITS-1:0] v00, v01, v10, v11;

	always_comb begin
		v00 = r00; v01 = r01; v10 = r10; v11 = r11;

		// Left column: r00 falls into r10
		if (r00 == MAT_SAND && r10 == MAT_EMPTY) begin
			v00 = r10;  // EMPTY
			v10 = r00;  // SAND
		end

		// Right column: r01 falls into r11
		if (r01 == MAT_SAND && r11 == MAT_EMPTY) begin
			v01 = r11;  // EMPTY
			v11 = r01;  // SAND
		end
	end

	// --- Phase 2: diagonal slide (cells still in row 0 after phase 1) ---
	logic [CELL_BITS-1:0] d00, d01, d10, d11;
	logic left_can, right_can;

	always_comb begin
		d00 = v00; d01 = v01; d10 = v10; d11 = v11;

		// Left-top can slide to bottom-right if:
		//   v00 is SAND, v10 is blocking (not EMPTY), v11 is EMPTY
		left_can  = (v00 == MAT_SAND) && (v10 != MAT_EMPTY) && (v11 == MAT_EMPTY);

		// Right-top can slide to bottom-left if:
		//   v01 is SAND, v11 is blocking (not EMPTY), v10 is EMPTY
		right_can = (v01 == MAT_SAND) && (v11 != MAT_EMPTY) && (v10 == MAT_EMPTY);

		if (left_can && right_can) begin
			// Both want to slide — rnd picks one
			if (rnd) begin
				// Left slides: v00 <-> v11
				d00 = v11;
				d11 = v00;
			end else begin
				// Right slides: v01 <-> v10
				d01 = v10;
				d10 = v01;
			end
		end else if (left_can) begin
			d00 = v11;
			d11 = v00;
		end else if (right_can) begin
			d01 = v10;
			d10 = v01;
		end
	end

	// --- Rotate result back from canonical DOWN to the original orientation ---
	always_comb begin
		case (grav_dir)
			2'd0: begin  // DOWN — identity
				n00 = d00; n01 = d01; n10 = d10; n11 = d11;
			end
			2'd1: begin  // UP — rotate 180° back
				n00 = d11; n01 = d10; n10 = d01; n11 = d00;
			end
			2'd2: begin  // LEFT — rotate CCW back
				n00 = d01; n01 = d11; n10 = d00; n11 = d10;
			end
			2'd3: begin  // RIGHT — rotate CW back
				n00 = d10; n01 = d00; n10 = d11; n11 = d01;
			end
			default: begin
				n00 = d00; n01 = d01; n10 = d10; n11 = d11;
			end
		endcase
	end

endmodule
