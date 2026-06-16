// =====================================================================
// brush — particle emitter / grid injector (clk_100)
// =====================================================================
// Writes material into the back buffer between engine frames. Two modes:
//   inject: writes a 3×3 patch at the emitter (top-center)
//   clear:  fills the grid with EMPTY then redraws the WALL border
// Operates only when the engine is idle. See docs/SPEC_brush.md.
// =====================================================================
module brush #(
		parameter int GRID_W    = 320,
		parameter int GRID_H    = 240,
		parameter int CELL_BITS = 4,
		parameter int DEPTH     = GRID_W * GRID_H,
		parameter int ADDR_BITS = $clog2(DEPTH)
) (
		input  logic                 clk,
		input  logic                 rst_n,
		// control
		input  logic                 inject,      // brush active this frame
		input  logic                 clear,       // clear the grid
		input  logic [CELL_BITS-1:0] material,    // material to inject
		input  logic                 engine_busy, // engine is processing
		// grid_mem write port
		output logic                 wr_en,
		output logic [ADDR_BITS-1:0] wr_addr,
		output logic [CELL_BITS-1:0] wr_data,
		output logic                 busy,
		output logic                 done         // 1-cyc pulse: finished
);

	// Material constants
	localparam logic [CELL_BITS-1:0] MAT_EMPTY = '0;
	localparam logic [CELL_BITS-1:0] MAT_WALL  = 4'd1;

	// Emitter position (center-top, inside the border)
	localparam int EMIT_X = GRID_W / 2;
	localparam int EMIT_Y = 10;
	localparam int PATCH_SIZE = 3;   // 3×3

	// Pre-computed emitter patch addresses (avoids runtime multiply)
	localparam logic [ADDR_BITS-1:0] PATCH_ADDR [9] = '{
		(EMIT_Y-1)*GRID_W + (EMIT_X-1), (EMIT_Y-1)*GRID_W + EMIT_X, (EMIT_Y-1)*GRID_W + (EMIT_X+1),
		EMIT_Y*GRID_W + (EMIT_X-1),     EMIT_Y*GRID_W + EMIT_X,     EMIT_Y*GRID_W + (EMIT_X+1),
		(EMIT_Y+1)*GRID_W + (EMIT_X-1), (EMIT_Y+1)*GRID_W + EMIT_X, (EMIT_Y+1)*GRID_W + (EMIT_X+1)
	};

	// FSM
	typedef enum logic [2:0] {
		S_IDLE,
		S_INJECT,
		S_CLEAR,
		S_BORDER,
		S_DONE
	} state_e;

	state_e state, state_d;

	// Counters
	logic [ADDR_BITS-1:0] addr_q;          // linear address for clear
	logic [ADDR_BITS-1:0] row_base_q;      // base address of current row (for border)
	logic [3:0]           patch_idx_q;     // 0..8 for 3×3

	// Border tracking
	logic [9:0] bx_q, by_q;

	assign busy = (state != S_IDLE);

	// FSM next-state
	always_comb begin
		state_d = state;
		wr_en   = 1'b0;
		wr_addr = '0;
		wr_data = '0;
		done    = 1'b0;

		case (state)
			S_IDLE: begin
				if (!engine_busy) begin
					if (clear)
						state_d = S_CLEAR;
					else if (inject)
						state_d = S_INJECT;
					else begin
						done    = 1'b1;   // nothing to do, let engine start
						state_d = S_IDLE;
					end
				end
			end

			S_INJECT: begin
				if (patch_idx_q < PATCH_SIZE * PATCH_SIZE) begin
					wr_en   = 1'b1;
					wr_addr = PATCH_ADDR[patch_idx_q];
					wr_data = material;
				end
				if (patch_idx_q == 4'(PATCH_SIZE * PATCH_SIZE - 1))
					state_d = S_DONE;
			end

			S_CLEAR: begin
				wr_en   = 1'b1;
				wr_addr = addr_q;
				wr_data = MAT_EMPTY;
				if (addr_q == ADDR_BITS'(DEPTH - 1))
					state_d = S_BORDER;
			end

			S_BORDER: begin
				// Re-draw WALL border using row_base_q (no multiply)
				wr_en = 1'b1;
				wr_data = MAT_WALL;
				if (by_q == 0 || by_q == 10'(GRID_H - 1)) begin
					// full row
					wr_addr = row_base_q + bx_q;
				end else begin
					// left or right column only
					if (bx_q == 0)
						wr_addr = row_base_q;
					else
						wr_addr = row_base_q + ADDR_BITS'(GRID_W - 1);
				end

				if (by_q == 10'(GRID_H - 1) &&
				    ((by_q == 0 || by_q == 10'(GRID_H - 1)) ? (bx_q == 10'(GRID_W - 1)) : (bx_q == 10'd1)))
					state_d = S_DONE;
			end

			S_DONE: begin
				done    = 1'b1;
				state_d = S_IDLE;
			end

			default: state_d = S_IDLE;
		endcase
	end

	// Sequential
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			state       <= S_IDLE;
			addr_q      <= '0;
			row_base_q  <= '0;
			patch_idx_q <= '0;
			bx_q        <= '0;
			by_q        <= '0;
		end else begin
			state <= state_d;

			case (state)
				S_IDLE: begin
					addr_q      <= '0;
					row_base_q  <= '0;
					patch_idx_q <= '0;
					bx_q        <= '0;
					by_q        <= '0;
				end

				S_INJECT: begin
					patch_idx_q <= patch_idx_q + 4'd1;
				end

				S_CLEAR: begin
					addr_q <= addr_q + 1'b1;
				end

				S_BORDER: begin
					if (by_q == 0 || by_q == 10'(GRID_H - 1)) begin
						// full row scan
						if (bx_q == 10'(GRID_W - 1)) begin
							bx_q       <= '0;
							by_q       <= by_q + 10'd1;
							row_base_q <= row_base_q + ADDR_BITS'(GRID_W);
						end else begin
							bx_q <= bx_q + 10'd1;
						end
					end else begin
						// edges only: write col 0, then col W-1, then next row
						if (bx_q == 10'd0) begin
							bx_q <= 10'd1;   // signal: right edge next
						end else begin
							bx_q       <= 10'd0;
							by_q       <= by_q + 10'd1;
							row_base_q <= row_base_q + ADDR_BITS'(GRID_W);
						end
					end
				end

				default: ;
			endcase
		end
	end

endmodule
