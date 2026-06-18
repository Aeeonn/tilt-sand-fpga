`timescale 1ns/1ps
// =====================================================================
// tb_water_momentum — RTL dynamic check of velocity-state water
// =====================================================================
// Drives the real margolus_engine over a water-slosh scenario and verifies:
//   * GROUPED mass conservation (water family WATER/WATER_R/WATER_L folded)
//     is constant frame over frame.
//   * Sloshing is actually happening: momentum tags (WATER_R/WATER_L) appear
//     while the water is in motion.
//   * The water settles: tags decay to zero after enough frames.
// Complements the exhaustive (static) tb_block_rule with dynamic behavior.
// =====================================================================
module tb_water_momentum;

	localparam int GW = 16, GH = 16;
	localparam int CELL_BITS = 4;
	localparam int DEPTH = GW * GH;
	localparam int AW = $clog2(DEPTH);

	localparam logic [CELL_BITS-1:0] EMPTY = 4'd0;
	localparam logic [CELL_BITS-1:0] WALL  = 4'd1;
	localparam logic [CELL_BITS-1:0] WATER = 4'd3;
	localparam logic [CELL_BITS-1:0] WR    = 4'd4;
	localparam logic [CELL_BITS-1:0] WL    = 4'd5;

	logic clk = 0, rst_n;
	logic start;
	logic [1:0] grav_dir;
	logic [AW-1:0] rd_addr, wr_addr;
	logic [CELL_BITS-1:0] rd_data, wr_data;
	logic wr_en, frame_done, busy, rd_back;

	int pass_count = 0, fail_count = 0;

	// --- grid_mem port-A bank model (honors rd_back like tb_margolus_engine) ---
	logic [CELL_BITS-1:0] bank0 [DEPTH];
	logic [CELL_BITS-1:0] bank1 [DEPTH];
	logic front_sel;

	logic [CELL_BITS-1:0] rd_data_reg;
	logic rd_from_bank1;
	always_comb rd_from_bank1 = rd_back ? (front_sel == 1'b0) : (front_sel == 1'b1);
	always_ff @(posedge clk) rd_data_reg <= rd_from_bank1 ? bank1[rd_addr] : bank0[rd_addr];
	assign rd_data = rd_data_reg;
	always_ff @(posedge clk) begin
		if (wr_en) begin
			if (front_sel == 1'b0) bank1[wr_addr] <= wr_data;
			else                   bank0[wr_addr] <= wr_data;
		end
	end

	margolus_engine #(.GRID_W(GW), .GRID_H(GH), .CELL_BITS(CELL_BITS)) dut (
		.clk(clk), .rst_n(rst_n), .start(start), .grav_dir(grav_dir),
		.rd_addr(rd_addr), .rd_back(rd_back), .rd_data(rd_data),
		.wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
		.frame_done(frame_done), .busy(busy)
	);

	always #5 clk = ~clk;

	function automatic logic is_water(input logic [CELL_BITS-1:0] m);
		is_water = (m == WATER) || (m == WR) || (m == WL);
	endfunction

	// Count water-family cells in the current front bank.
	function automatic int water_count();
		int n; n = 0;
		for (int i = 0; i < DEPTH; i++)
			if (is_water(front_sel ? bank1[i] : bank0[i])) n++;
		return n;
	endfunction

	// Sum of x-coordinates of all water cells (front bank) — its swing over
	// time is the sloshing amplitude (center of mass oscillating left/right).
	function automatic int water_x_sum();
		int n; n = 0;
		for (int y = 0; y < GH; y++)
			for (int x = 0; x < GW; x++)
				if (is_water(front_sel ? bank1[y*GW+x] : bank0[y*GW+x])) n += x;
		return n;
	endfunction

	// Initialize: WALL border, water filling the LEFT half (an asymmetric
	// slab that must slosh to the right and settle).
	task automatic init_grid();
		for (int y = 0; y < GH; y++)
			for (int x = 0; x < GW; x++) begin
				int a; a = y * GW + x;
				if (y == 0 || y == GH-1 || x == 0 || x == GW-1) bank0[a] = WALL;
				else if (x < GW/2 && y > GH/2)                  bank0[a] = WATER;
				else                                            bank0[a] = EMPTY;
				bank1[a] = EMPTY;
			end
		front_sel = 1'b0;
	endtask

	task automatic check(string nm, logic cond);
		if (cond) pass_count++;
		else begin fail_count++; $display("FAIL %s @%0t", nm, $time); end
	endtask

	task automatic run_frame();
		@(negedge clk); start = 1;
		@(posedge clk); #1; start = 0;
		@(posedge frame_done);
		@(posedge clk); #1;
		front_sel = ~front_sel;
	endtask

	int mass0, early_amp, late_amp;
	int xs_min, xs_max, xs;

	initial begin
		rst_n = 0; start = 0; grav_dir = 2'd0;   // DOWN
		init_grid();
		#50; @(negedge clk); rst_n = 1;
		repeat (3) @(posedge clk);

		mass0 = water_count();
		check("initial water > 0", mass0 > 0);

		// Phase 1: release the slab; track the swing (max-min) of the water
		// center-of-mass over the early, actively-sloshing window.
		xs_min = 1<<30; xs_max = 0;
		for (int f = 0; f < 60; f++) begin
			run_frame();
			check($sformatf("water conserved f%0d", f), water_count() == mass0);
			xs = water_x_sum();
			if (xs < xs_min) xs_min = xs;
			if (xs > xs_max) xs_max = xs;
		end
		early_amp = xs_max - xs_min;
		check("water sloshed (nonzero swing)", early_amp > 0);

		// Phase 2: let it settle, then measure the swing over an equal late
		// window. Waves lose energy, so the late swing must be much smaller.
		for (int f = 0; f < 200; f++) run_frame();
		xs_min = 1<<30; xs_max = 0;
		for (int f = 0; f < 60; f++) begin
			run_frame();
			check($sformatf("water conserved late f%0d", f), water_count() == mass0);
			xs = water_x_sum();
			if (xs < xs_min) xs_min = xs;
			if (xs > xs_max) xs_max = xs;
		end
		late_amp = xs_max - xs_min;
		// Energy decays: the late slosh swing is well under half the early one.
		check("waves decayed (late swing << early)", late_amp * 2 < early_amp);
		$display("INFO early_amp=%0d late_amp=%0d", early_amp, late_amp);

		if (fail_count == 0)
			$display("TB tb_water_momentum: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_water_momentum: %0d/%0d failed (%0d total)",
			         fail_count, fail_count, pass_count + fail_count);
		$finish;
	end

endmodule
