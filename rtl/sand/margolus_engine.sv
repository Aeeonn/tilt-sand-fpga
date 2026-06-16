// =====================================================================
// margolus_engine — Margolus 2×2 block CA scan engine (clk_100 FSM)
// =====================================================================
// Scans the grid in 2×2 blocks (alternating Margolus phases), applies
// block_rule to each block, writes results to the back buffer, then
// signals frame_done. See docs/SPEC_margolus_engine.md.
//
// Timing budget per block: 10 cycles (4 read + 1 apply + 4 write + 1 next).
// Phase 0: 160×120 = 19200 blocks × 10 = 192k cycles @ 100 MHz = 1.92 ms.
// Total both phases: ~3.8 ms ≪ 16.67 ms (60 Hz).
// =====================================================================
module margolus_engine #(
		parameter int GRID_W    = 320,
		parameter int GRID_H    = 240,
		parameter int CELL_BITS = 4,
		parameter int ADDR_BITS = $clog2(GRID_W * GRID_H)
) (
		input  logic                 clk,
		input  logic                 rst_n,
		input  logic                 start,       // 1-cyc: begin a new frame
		input  logic [1:0]           grav_dir,    // gravity direction

		// grid_mem port-A interface (read front bank, write back bank)
		output logic [ADDR_BITS-1:0] rd_addr,
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
		S_APPLY,   // capture c11, block_rule is combinational
		S_RESULT,  // register block_rule output (breaks combinational depth)
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
	// block_rule instance (combinational)
	// -----------------------------------------------------------------
	logic [CELL_BITS-1:0] n00, n01, n10, n11;

	block_rule #(.CELL_BITS(CELL_BITS)) u_rule (
		.grav_dir(grav_dir),
		.rnd     (lfsr_rnd[0]),
		.c00     (c00_q),
		.c01     (c01_q),
		.c10     (c10_q),
		.c11     (c11_q),
		.n00     (n00),
		.n01     (n01),
		.n10     (n10),
		.n11     (n11)
	);

	// -----------------------------------------------------------------
	// Block limit for current phase
	// -----------------------------------------------------------------
	logic [BX_BITS-1:0] bx_limit;
	logic [BY_BITS-1:0] by_limit;

	assign bx_limit = phase_q ? BX_BITS'(BX_MAX_P1 - 1) : BX_BITS'(BX_MAX_P0 - 1);
	assign by_limit = phase_q ? BY_BITS'(BY_MAX_P1 - 1) : BY_BITS'(BY_MAX_P0 - 1);

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
				// c11 captured this cycle; block_rule output (n*) valid
				lfsr_en = 1'b1;   // advance LFSR for next block
				state_d = S_RESULT;
			end

			S_RESULT: begin
				// block_rule outputs registered on this edge (see sequential block)
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
					// All blocks processed — frame complete
					frame_done = 1'b1;
					state_d    = S_IDLE;
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
			bx_q        <= '0;
			by_q        <= '0;
			c00_q       <= '0;
			c01_q       <= '0;
			c10_q       <= '0;
			c11_q       <= '0;
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

			// Register block_rule outputs in S_RESULT (c11_q is now valid)
			if (state == S_RESULT) begin
				n00_q <= n00;
				n01_q <= n01;
				n10_q <= n10;
				n11_q <= n11;
			end

			// Block coordinate advancement
			case (state)
				S_IDLE: begin
					if (start) begin
						bx_q <= '0;
						by_q <= '0;
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
						// Frame done — toggle phase for next frame
						phase_q <= ~phase_q;
					end
				end
				default: ;
			endcase
		end
	end

endmodule
