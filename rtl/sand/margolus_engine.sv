// =====================================================================
// margolus_engine — Margolus 2×2 block CA scan engine (clk_100 FSM)
// =====================================================================
// Scans the grid in 2×2 blocks (alternating Margolus phases), applies
// block_rule to each block, writes results to the back buffer, then
// signals frame_done. See docs/SPEC_margolus_engine.md.
//
// Multi-pass: each displayed frame runs NUM_PASSES Margolus steps so the
// physics advances NUM_PASSES cells per displayed frame (natural-looking
// flow speed). Pass 0 reads the FRONT bank and writes the BACK bank.
// Passes 1..NUM_PASSES-1 read AND write the BACK bank in place (rd_back=1),
// which is safe because Margolus processes disjoint 2×2 blocks. The
// Margolus phase toggles every pass and persists across frames.
//
// Timing budget per block: 13 cycles. Phase 0: 160×120 = 19200 blocks.
// One pass ≈ 250k cycles @ 100 MHz ≈ 2.5 ms. NUM_PASSES passes per frame.
// =====================================================================
module margolus_engine #(
		parameter int GRID_W     = 320,
		parameter int GRID_H     = 240,
		parameter int CELL_BITS  = 4,
		parameter int NUM_PASSES = 8,    // Margolus steps per displayed frame
		parameter int ADDR_BITS  = $clog2(GRID_W * GRID_H)
) (
		input  logic                 clk,
		input  logic                 rst_n,
		input  logic                 start,       // 1-cyc: begin a new frame
		input  logic [1:0]           grav_dir,    // gravity direction

		// grid_mem port-A interface (read front/back bank, write back bank)
		output logic [ADDR_BITS-1:0] rd_addr,
		output logic                 rd_back,     // 1: read BACK bank (in-place pass)
		input  logic [CELL_BITS-1:0] rd_data,     // 1-cycle latency from BRAM
		output logic                 wr_en,
		output logic [ADDR_BITS-1:0] wr_addr,
		output logic [CELL_BITS-1:0] wr_data,

		// handshake
		output logic                 frame_done,  // 1-cyc pulse when frame is complete
		output logic                 busy
);

	// -----------------------------------------------------------------
	// Block coordinate sizing
	// -----------------------------------------------------------------
	// Phase 0: 160 × 120 blocks; Phase 1: 159 × 119 interior blocks.
	localparam int BX_MAX_P0 = GRID_W / 2;   // 160
	localparam int BY_MAX_P0 = GRID_H / 2;   // 120
	localparam int BX_MAX_P1 = GRID_W / 2 - 1;   // 159
	localparam int BY_MAX_P1 = GRID_H / 2 - 1;   // 119

	localparam int BX_BITS = $clog2(BX_MAX_P0);  // 8
	localparam int BY_BITS = $clog2(BY_MAX_P0);  // 7

	// Pass-counter width (at least 1 bit even if NUM_PASSES==1).
	localparam int PASS_BITS = (NUM_PASSES <= 1) ? 1 : $clog2(NUM_PASSES);

	// -----------------------------------------------------------------
	// FSM states
	// -----------------------------------------------------------------
	typedef enum logic [3:0] {
		S_IDLE,
		S_ADDR,    // register the 4 cell addresses (breaks multiply timing path)
		S_READ0,   // issue addr for c00, capture nothing
		S_READ1,   // issue addr for c01, capture c00
		S_READ2,   // issue addr for c10, capture c01
		S_READ3,   // issue addr for c11, capture c10
		S_APPLY,   // capture c11; advance LFSR
		S_STAGE1,  // block_rule_fall combinational → register midpoint
		S_STAGE2,  // block_rule_settle combinational → register result
		S_WRITE0,  // write n00
		S_WRITE1,  // write n01
		S_WRITE2,  // write n10
		S_WRITE3,  // write n11
		S_NEXT     // advance block coordinates or go to S_DONE
	} state_e;

	state_e state, state_d;

	// -----------------------------------------------------------------
	// Registers
	// -----------------------------------------------------------------
	logic                 phase_q;            // Margolus phase (0 or 1)
	logic [PASS_BITS-1:0] pass_q;             // current pass index (0..NUM_PASSES-1)
	logic [BX_BITS-1:0]  bx_q;              // block x coordinate
	logic [BY_BITS-1:0]  by_q;              // block y coordinate
	logic [CELL_BITS-1:0] c00_q, c01_q, c10_q, c11_q;  // captured cells
	logic [CELL_BITS-1:0] n00_q, n01_q, n10_q, n11_q;  // registered block_rule output

	// Pre-computed and registered addresses for the current block
	logic [ADDR_BITS-1:0] addr_c00_q, addr_c01_q, addr_c10_q, addr_c11_q;

	// Cell coordinates for current block (combinational, used to compute addrs)
	logic [9:0] row0, row1, col0, col1;

	always_comb begin
		if (phase_q == 1'b0) begin
			// Phase 0: blocks at even (x,y)
			col0 = {bx_q, 1'b0};              // 2 * bx
			col1 = {bx_q, 1'b1};              // 2 * bx + 1
			row0 = {by_q, 1'b0};              // 2 * by
			row1 = {by_q, 1'b1};              // 2 * by + 1
		end else begin
			// Phase 1: blocks offset by (1,1)
			col0 = {bx_q, 1'b1};              // 2 * bx + 1
			col1 = {bx_q[BX_BITS-1:0], 1'b0} + 10'd2;  // 2 * bx + 2
			row0 = {by_q, 1'b1};              // 2 * by + 1
			row1 = {by_q[BY_BITS-1:0], 1'b0} + 10'd2;  // 2 * by + 2
		end
	end

	// Linear addresses (row-major): addr = row * GRID_W + col
	// These are registered in S_ADDR to break the critical path.
	logic [ADDR_BITS-1:0] addr_c00_c, addr_c01_c, addr_c10_c, addr_c11_c;
	assign addr_c00_c = row0 * GRID_W + col0;
	assign addr_c01_c = row0 * GRID_W + col1;
	assign addr_c10_c = row1 * GRID_W + col0;
	assign addr_c11_c = row1 * GRID_W + col1;

	// -----------------------------------------------------------------
	// LFSR instance
	// -----------------------------------------------------------------
	logic        lfsr_en;
	logic [15:0] lfsr_rnd;

	lfsr #(.WIDTH(16), .SEED(16'hACE1)) u_lfsr (
		.clk  (clk),
		.rst_n(rst_n),
		.en   (lfsr_en),
		.rnd  (lfsr_rnd)
	);

	// -----------------------------------------------------------------
	// block_rule split into two pipelined stages (registered midpoint) so
	// the combinational rule fits the clk_100 period. Stage 1 (fall +
	// greedy diagonal) uses rnd; stage 2 (greedy water level) does not.
	// -----------------------------------------------------------------
	logic [CELL_BITS-1:0] n00, n01, n10, n11;   // final rotated-back result (comb)

	// Rotate captured cells to canonical-DOWN (a=TL b=TR c=BL d=BR).
	logic [CELL_BITS-1:0] rot_a, rot_b, rot_c, rot_d;
	always_comb begin
		case (grav_dir)
			2'd0: begin rot_a = c00_q; rot_b = c01_q; rot_c = c10_q; rot_d = c11_q; end
			2'd1: begin rot_a = c11_q; rot_b = c10_q; rot_c = c01_q; rot_d = c00_q; end
			2'd2: begin rot_a = c10_q; rot_b = c00_q; rot_c = c11_q; rot_d = c01_q; end
			2'd3: begin rot_a = c01_q; rot_b = c11_q; rot_c = c00_q; rot_d = c10_q; end
			default: begin rot_a = c00_q; rot_b = c01_q; rot_c = c10_q; rot_d = c11_q; end
		endcase
	end

	// Stage 1: fall + greedy diagonal (combinational), registered in S_STAGE1.
	// rnd is stable here (lfsr only advances in S_APPLY).
	logic [CELL_BITS-1:0] f_a, f_b, f_c, f_d;
	block_rule_fall #(.CELL_BITS(CELL_BITS)) u_fall (
		.rnd(lfsr_rnd[0]),
		.a_i(rot_a), .b_i(rot_b), .c_i(rot_c), .d_i(rot_d),
		.a_o(f_a),   .b_o(f_b),   .c_o(f_c),   .d_o(f_d)
	);

	// Registered midpoint (canonical orientation).
	logic [CELL_BITS-1:0] mid_a_q, mid_b_q, mid_c_q, mid_d_q;

	// Stage 2: greedy water level (combinational), from the midpoint.
	logic [CELL_BITS-1:0] s_a, s_b, s_c, s_d;
	block_rule_settle #(.CELL_BITS(CELL_BITS)) u_settle (
		.a_i(mid_a_q), .b_i(mid_b_q), .c_i(mid_c_q), .d_i(mid_d_q),
		.a_o(s_a),     .b_o(s_b),     .c_o(s_c),     .d_o(s_d)
	);

	// Rotate stage-2 output back to the original orientation (combinational).
	always_comb begin
		case (grav_dir)
			2'd0: begin n00 = s_a; n01 = s_b; n10 = s_c; n11 = s_d; end
			2'd1: begin n00 = s_d; n01 = s_c; n10 = s_b; n11 = s_a; end
			2'd2: begin n00 = s_b; n01 = s_d; n10 = s_a; n11 = s_c; end
			2'd3: begin n00 = s_c; n01 = s_a; n10 = s_d; n11 = s_b; end
			default: begin n00 = s_a; n01 = s_b; n10 = s_c; n11 = s_d; end
		endcase
	end

	// -----------------------------------------------------------------
	// Block limit for current phase
	// -----------------------------------------------------------------
	logic [BX_BITS-1:0] bx_limit;
	logic [BY_BITS-1:0] by_limit;

	assign bx_limit = phase_q ? BX_BITS'(BX_MAX_P1 - 1) : BX_BITS'(BX_MAX_P0 - 1);
	assign by_limit = phase_q ? BY_BITS'(BY_MAX_P1 - 1) : BY_BITS'(BY_MAX_P0 - 1);

	// Read source: front bank on pass 0, back bank (in-place) on later passes.
	assign rd_back = (pass_q != '0);

	// -----------------------------------------------------------------
	// FSM next-state + output logic
	// -----------------------------------------------------------------
	always_comb begin
		state_d    = state;
		rd_addr    = '0;
		wr_en      = 1'b0;
		wr_addr    = '0;
		wr_data    = '0;
		lfsr_en    = 1'b0;
		frame_done = 1'b0;
		busy       = (state != S_IDLE);

		case (state)
			S_IDLE: begin
				if (start) state_d = S_ADDR;
			end

			S_ADDR: begin
				// Addresses are registered on this cycle's rising edge
				state_d = S_READ0;
			end

			S_READ0: begin
				rd_addr = addr_c00_q;
				state_d = S_READ1;
			end

			S_READ1: begin
				rd_addr = addr_c01_q;
				state_d = S_READ2;
			end

			S_READ2: begin
				rd_addr = addr_c10_q;
				state_d = S_READ3;
			end

			S_READ3: begin
				rd_addr = addr_c11_q;
				state_d = S_APPLY;
			end

			S_APPLY: begin
				// c11 captured at this edge; advance LFSR for the next block.
				lfsr_en = 1'b1;
				state_d = S_STAGE1;
			end

			S_STAGE1: begin
				// stage-1 (fall + water diagonal) registered into the midpoint
				state_d = S_STAGE2;
			end

			S_STAGE2: begin
				// stage-2 (water level + sand diagonal) registered into n*_q
				state_d = S_WRITE0;
			end

			S_WRITE0: begin
				wr_en   = 1'b1;
				wr_addr = addr_c00_q;
				wr_data = n00_q;
				state_d = S_WRITE1;
			end

			S_WRITE1: begin
				wr_en   = 1'b1;
				wr_addr = addr_c01_q;
				wr_data = n01_q;
				state_d = S_WRITE2;
			end

			S_WRITE2: begin
				wr_en   = 1'b1;
				wr_addr = addr_c10_q;
				wr_data = n10_q;
				state_d = S_WRITE3;
			end

			S_WRITE3: begin
				wr_en   = 1'b1;
				wr_addr = addr_c11_q;
				wr_data = n11_q;
				state_d = S_NEXT;
			end

			S_NEXT: begin
				if (bx_q == bx_limit && by_q == by_limit) begin
					// Last block of this pass.
					if (pass_q == PASS_BITS'(NUM_PASSES - 1)) begin
						// Final pass — frame complete.
						frame_done = 1'b1;
						state_d    = S_IDLE;
					end else begin
						// More passes to run — start the next pass in place.
						state_d = S_ADDR;
					end
				end else begin
					state_d = S_ADDR;
				end
			end

			default: state_d = S_IDLE;
		endcase
	end

	// -----------------------------------------------------------------
	// FSM state register + block coordinate advancement
	// -----------------------------------------------------------------
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			state       <= S_IDLE;
			phase_q     <= 1'b0;
			pass_q      <= '0;
			bx_q        <= '0;
			by_q        <= '0;
			c00_q       <= '0;
			c01_q       <= '0;
			c10_q       <= '0;
			c11_q       <= '0;
			mid_a_q     <= '0;
			mid_b_q     <= '0;
			mid_c_q     <= '0;
			mid_d_q     <= '0;
			n00_q       <= '0;
			n01_q       <= '0;
			n10_q       <= '0;
			n11_q       <= '0;
			addr_c00_q  <= '0;
			addr_c01_q  <= '0;
			addr_c10_q  <= '0;
			addr_c11_q  <= '0;
		end else begin
			state <= state_d;

			// Register addresses during S_ADDR (breaks the multiply critical path)
			if (state == S_IDLE && start) begin
				// First block: register addresses immediately as we move to S_ADDR
				addr_c00_q <= addr_c00_c;
				addr_c01_q <= addr_c01_c;
				addr_c10_q <= addr_c10_c;
				addr_c11_q <= addr_c11_c;
			end else if (state == S_NEXT && !(bx_q == bx_limit && by_q == by_limit)) begin
				// Next block: register addresses as we move back to S_ADDR
				// (bx_q/by_q have been advanced by this point — use combinational addrs)
			end
			if (state == S_ADDR) begin
				// Re-capture in case bx_q/by_q changed in S_NEXT
				addr_c00_q <= addr_c00_c;
				addr_c01_q <= addr_c01_c;
				addr_c10_q <= addr_c10_c;
				addr_c11_q <= addr_c11_c;
			end

			// Capture cells from rd_data pipeline (1-cycle BRAM latency)
			case (state)
				S_READ1: c00_q <= rd_data;   // issued addr_c00 in READ0, data arrives now
				S_READ2: c01_q <= rd_data;
				S_READ3: c10_q <= rd_data;
				S_APPLY: c11_q <= rd_data;
				default: ;
			endcase

			// Register block_rule outputs across two pipeline stages.
			// S_STAGE1: c11_q is valid → register stage-1 (fall + diagonal)
			//           midpoint. rnd (lfsr_rnd[0]) is consumed combinationally
			//           by u_fall this cycle; stage 2 needs no rnd.
			if (state == S_STAGE1) begin
				mid_a_q <= f_a;
				mid_b_q <= f_b;
				mid_c_q <= f_c;
				mid_d_q <= f_d;
			end
			// S_STAGE2: register the rotated-back stage-2 (settle) result.
			if (state == S_STAGE2) begin
				n00_q <= n00;
				n01_q <= n01;
				n10_q <= n10;
				n11_q <= n11;
			end

			// Block coordinate advancement
			case (state)
				S_IDLE: begin
					if (start) begin
						bx_q   <= '0;
						by_q   <= '0;
						pass_q <= '0;
					end
				end
				S_NEXT: begin
					if (!(bx_q == bx_limit && by_q == by_limit)) begin
						if (bx_q == bx_limit) begin
							bx_q <= '0;
							by_q <= by_q + 1'b1;
						end else begin
							bx_q <= bx_q + 1'b1;
						end
					end else begin
						// Pass complete — toggle Margolus phase (persists across
						// frames) and advance the pass counter.
						phase_q <= ~phase_q;
						bx_q    <= '0;
						by_q    <= '0;
						if (pass_q == PASS_BITS'(NUM_PASSES - 1))
							pass_q <= '0;            // final pass → back to IDLE
						else
							pass_q <= pass_q + 1'b1; // start next in-place pass
					end
				end
				default: ;
			endcase
		end
	end

endmodule
