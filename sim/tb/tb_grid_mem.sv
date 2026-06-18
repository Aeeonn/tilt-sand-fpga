`timescale 1ns/1ps
// =====================================================================
// tb_grid_mem — dual-port access + vsync-gated double-buffer swap + CDC
// =====================================================================
// Two asynchronous clocks (clk_a 100-ish, clk_b 25-ish). Small 8x4 grid.
// Verifies:
//   * port-A write to BACK bank, read FRONT bank; port-B read FRONT bank
//   * swap happens ONLY at a vsync_tick that follows a frame_done
//   * frame_done with no vsync does not swap; vsync with no pending does not
//   * front_a follows front_b across the CDC; swapped pulses once per swap
//   * double-buffer integrity: each bank retains its own data across swaps
//   * SVA: front_b never changes except one cycle after a vsync_tick
// Init-from-file is covered end-to-end by tb_top (real test_grid.mem).
// =====================================================================
module tb_grid_mem;

	localparam int GRID_W = 8, GRID_H = 4;
	localparam int CELL_BITS = 4;
	localparam int DEPTH = GRID_W*GRID_H, AW = $clog2(DEPTH);   // 32, 5

	localparam time CKA = 2ns;     // ~clk_100
	localparam time CKB = 7ns;     // ~clk_25, deliberately async / non-integer

	logic clk_a = 0, clk_b = 0, rst_n_a, rst_n_b;

	logic [AW-1:0]        rd_addr = 0, wr_addr = 0, px_addr = 0;
	logic [CELL_BITS-1:0] rd_data, wr_data = 0, px_data;
	logic                 wr_en = 0, frame_done = 0, vsync_tick = 0;
	logic                 rd_back = 0;
	logic                 swapped, front_a, front_b;

	int pass_count = 0, fail_count = 0, printed = 0;
	localparam int MAXP = 12;

	grid_mem #(.GRID_W(GRID_W), .GRID_H(GRID_H), .CELL_BITS(CELL_BITS)) dut (
		.clk_a(clk_a), .rst_n_a(rst_n_a),
		.rd_addr(rd_addr), .rd_back(rd_back), .rd_data(rd_data),
		.wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
		.frame_done(frame_done), .swapped(swapped), .front_a(front_a),
		.clk_b(clk_b), .rst_n_b(rst_n_b),
		.vsync_tick(vsync_tick), .px_addr(px_addr), .px_data(px_data),
		.front_b(front_b)
	);

	always #(CKA/2) clk_a = ~clk_a;
	always #(CKB/2) clk_b = ~clk_b;

	// count swapped pulses
	int swap_pulses = 0;
	always_ff @(posedge clk_a) if (rst_n_a && swapped) swap_pulses++;

	// SVA: front_b only ever changes the cycle after a vsync_tick.
	a_front_b_only_on_vsync: assert property (
		@(posedge clk_b) disable iff (!rst_n_b)
		(front_b !== $past(front_b)) |-> $past(vsync_tick)
	) else begin
		fail_count++;
		$display("FAIL SVA: front_b changed without a preceding vsync_tick @%0t", $time);
	end

	task automatic ck_bit(string nm, logic got, logic exp);
		if (got === exp) pass_count++;
		else begin
			fail_count++;
			if (printed < MAXP) begin
				$display("FAIL %s: exp %b got %b @%0t", nm, exp, got, $time); printed++;
			end
		end
	endtask

	task automatic ck_cell(string nm, logic [CELL_BITS-1:0] got, logic [CELL_BITS-1:0] exp);
		if (got === exp) pass_count++;
		else begin
			fail_count++;
			if (printed < MAXP) begin
				$display("FAIL %s: exp %0h got %0h @%0t", nm, exp, got, $time); printed++;
			end
		end
	endtask

	task automatic a_write(input [AW-1:0] a, input [CELL_BITS-1:0] d);
		@(negedge clk_a); wr_addr = a; wr_data = d; wr_en = 1;
		@(posedge clk_a); #1; wr_en = 0;
	endtask

	task automatic a_read(input [AW-1:0] a, output [CELL_BITS-1:0] d);
		@(negedge clk_a); rd_addr = a;
		@(posedge clk_a); #1;             // BRAM registers dout
		d = rd_data;
	endtask

	// Read the BACK bank in place (rd_back=1).
	task automatic a_read_back(input [AW-1:0] a, output [CELL_BITS-1:0] d);
		@(negedge clk_a); rd_addr = a; rd_back = 1;
		@(posedge clk_a); #1;
		d = rd_data;
		@(negedge clk_a); rd_back = 0;
	endtask

	task automatic b_read(input [AW-1:0] a, output [CELL_BITS-1:0] d);
		@(negedge clk_b); px_addr = a;
		@(posedge clk_b); #1;
		d = px_data;
	endtask

	task automatic pulse_frame_done();
		@(negedge clk_a); frame_done = 1;
		@(posedge clk_a); #1; frame_done = 0;
	endtask

	task automatic pulse_vsync();
		@(negedge clk_b); vsync_tick = 1;
		@(posedge clk_b); #1; vsync_tick = 0;
	endtask

	// full swap: frame_done, let it cross, vsync, let front cross back.
	task automatic do_swap();
		pulse_frame_done();
		repeat (5) @(posedge clk_b);
		pulse_vsync();
		repeat (6) @(posedge clk_a);
	endtask

	logic [CELL_BITS-1:0] d;

	initial begin
		rst_n_a = 0; rst_n_b = 0;
		#50;
		@(negedge clk_a); rst_n_a = 1;
		@(negedge clk_b); rst_n_b = 1;
		repeat (4) @(posedge clk_a);

		// after reset both fronts are bank 0
		ck_bit("front_a reset", front_a, 1'b0);
		ck_bit("front_b reset", front_b, 1'b0);

		// --- write pattern P1 into the BACK bank (bank1, since front=0) ---
		a_write(5'd1,  4'h3);
		a_write(5'd7,  4'hA);
		a_write(5'd31, 4'h5);

		// negative: vsync with no pending frame -> no swap
		pulse_vsync();
		repeat (6) @(posedge clk_a);
		ck_bit("no swap on vsync w/o frame_done (front_b)", front_b, 1'b0);
		ck_bit("no swap on vsync w/o frame_done (front_a)", front_a, 1'b0);

		// negative: frame_done but no vsync -> pending set, still no swap
		pulse_frame_done();
		repeat (8) @(posedge clk_b);
		ck_bit("no swap on frame_done w/o vsync (front_b)", front_b, 1'b0);

		// now the vsync consumes the pending -> first swap, front -> 1
		pulse_vsync();
		repeat (6) @(posedge clk_a);
		ck_bit("swap1 front_b", front_b, 1'b1);
		ck_bit("swap1 front_a", front_a, 1'b1);

		// front is now bank1 = P1: read it back on both ports
		a_read(5'd1,  d); ck_cell("P1 a_read[1]",  d, 4'h3);
		a_read(5'd7,  d); ck_cell("P1 a_read[7]",  d, 4'hA);
		a_read(5'd31, d); ck_cell("P1 a_read[31]", d, 4'h5);
		b_read(5'd1,  d); ck_cell("P1 b_read[1]",  d, 4'h3);
		b_read(5'd7,  d); ck_cell("P1 b_read[7]",  d, 4'hA);

		// --- write pattern P2 into the new BACK bank (bank0) ---
		a_write(5'd0, 4'hF);
		a_write(5'd1, 4'hC);
		a_write(5'd7, 4'h6);

		// swap2: front -> 0 (bank0 = P2)
		do_swap();
		ck_bit("swap2 front_b", front_b, 1'b0);
		ck_bit("swap2 front_a", front_a, 1'b0);
		a_read(5'd0, d); ck_cell("P2 a_read[0]", d, 4'hF);
		a_read(5'd1, d); ck_cell("P2 a_read[1]", d, 4'hC);
		a_read(5'd7, d); ck_cell("P2 a_read[7]", d, 4'h6);
		b_read(5'd0, d); ck_cell("P2 b_read[0]", d, 4'hF);

		// swap3: back to bank1 — P1 must be intact (double-buffer integrity)
		do_swap();
		ck_bit("swap3 front_b", front_b, 1'b1);
		a_read(5'd1,  d); ck_cell("P1 intact a_read[1]",  d, 4'h3);
		a_read(5'd31, d); ck_cell("P1 intact a_read[31]", d, 4'h5);

		// exactly three swaps happened
		ck_cell("swap pulse count", swap_pulses[CELL_BITS-1:0], 4'd3);

		// --- in-place (rd_back) read of the BACK bank for multi-pass ---
		// front is bank1 now; back bank = bank0. Write a value into the back
		// bank and read it straight back via rd_back without swapping.
		a_write(5'd2,  4'h9);
		a_write(5'd10, 4'hE);
		a_read_back(5'd2,  d); ck_cell("rd_back back[2]",  d, 4'h9);
		a_read_back(5'd10, d); ck_cell("rd_back back[10]", d, 4'hE);
		// rd_back=0 must still read the FRONT bank (bank1 = P1 intact)
		a_read(5'd1,  d); ck_cell("front read after rd_back", d, 4'h3);
		// no swap should have occurred from the in-place activity
		ck_cell("swap count unchanged after rd_back", swap_pulses[CELL_BITS-1:0], 4'd3);

		if (fail_count == 0)
			$display("TB tb_grid_mem: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_grid_mem: %0d/%0d failed (%0d total)",
							fail_count, fail_count, pass_count + fail_count);
		$finish;
	end

endmodule
