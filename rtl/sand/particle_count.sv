// =====================================================================
// particle_count — non-EMPTY cell counter (clk_100)
// =====================================================================
// Scans the front buffer sequentially and counts cells != EMPTY.
// Result is a 16-bit saturating count displayed on HEX. Takes DEPTH+1
// cycles (~0.77 ms for 320×240). See docs/SPEC_particle_count.md.
// =====================================================================
module particle_count #(
		parameter int GRID_W    = 320,
		parameter int GRID_H    = 240,
		parameter int CELL_BITS = 4,
		parameter int DEPTH     = GRID_W * GRID_H,
		parameter int ADDR_BITS = $clog2(DEPTH)
) (
		input  logic                 clk,
		input  logic                 rst_n,
		// trigger
		input  logic                 start,       // 1-cyc: begin counting
		// grid_mem read port (front bank)
		output logic [ADDR_BITS-1:0] rd_addr,
		input  logic [CELL_BITS-1:0] rd_data,     // 1-cycle latency
		// result
		output logic [15:0]          count,       // latched result
		output logic                 busy,
		output logic                 done         // 1-cyc: count is valid
);

	typedef enum logic [1:0] {
		S_IDLE,
		S_SCAN,
		S_LAST,    // capture final rd_data (pipeline flush)
		S_DONE
	} state_e;

	state_e state, state_d;

	logic [ADDR_BITS-1:0] scan_addr_q;
	logic [16:0]          accum_q;        // 17-bit to detect saturation

	assign busy    = (state != S_IDLE);
	assign rd_addr = scan_addr_q;

	always_comb begin
		state_d = state;
		done    = 1'b0;

		case (state)
			S_IDLE: begin
				if (start) state_d = S_SCAN;
			end

			S_SCAN: begin
				if (scan_addr_q == ADDR_BITS'(DEPTH - 1))
					state_d = S_LAST;
			end

			S_LAST: begin
				// One extra cycle for the final BRAM read to arrive
				state_d = S_DONE;
			end

			S_DONE: begin
				done    = 1'b1;
				state_d = S_IDLE;
			end

			default: state_d = S_IDLE;
		endcase
	end

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			state      <= S_IDLE;
			scan_addr_q <= '0;
			accum_q    <= '0;
			count      <= '0;
		end else begin
			state <= state_d;

			case (state)
				S_IDLE: begin
					if (start) begin
						scan_addr_q <= '0;
						accum_q     <= '0;
					end
				end

				S_SCAN: begin
					scan_addr_q <= scan_addr_q + 1'b1;
					// rd_data arrives 1 cycle after issuing scan_addr_q
					// When scan_addr_q == 1, rd_data has addr 0's value, etc.
					if (scan_addr_q > 0) begin
						if (rd_data != '0)
							accum_q <= accum_q + 1'b1;
					end
				end

				S_LAST: begin
					// Capture rd_data for addr DEPTH-1 (issued last cycle of S_SCAN)
					if (rd_data != '0)
						accum_q <= accum_q + 1'b1;
				end

				S_DONE: begin
					// Latch final count (no more data to capture)
					count <= (accum_q[16]) ? 16'hFFFF : accum_q[15:0];
				end

				default: ;
			endcase
		end
	end

endmodule
