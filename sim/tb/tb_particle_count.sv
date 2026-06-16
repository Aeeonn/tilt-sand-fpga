`timescale 1ns/1ps
// =====================================================================
// tb_particle_count — verify cell counting on a small grid
// =====================================================================
module tb_particle_count;

	localparam int GW = 4, GH = 4;
	localparam int CELL_BITS = 4;
	localparam int DEPTH = GW * GH;
	localparam int AW = $clog2(DEPTH);

	logic clk = 0, rst_n;
	logic start;
	logic [AW-1:0] rd_addr;
	logic [CELL_BITS-1:0] rd_data;
	logic [15:0] count;
	logic busy, done;

	int pass_count = 0, fail_count = 0;

	particle_count #(.GRID_W(GW), .GRID_H(GH), .CELL_BITS(CELL_BITS)) dut (
		.clk(clk), .rst_n(rst_n),
		.start(start),
		.rd_addr(rd_addr), .rd_data(rd_data),
		.count(count), .busy(busy), .done(done)
	);

	always #5 clk = ~clk;

	// Small grid memory (simulates the front bank)
	logic [CELL_BITS-1:0] grid_mem [DEPTH];

	// 1-cycle read latency (like bram_tdp)
	always_ff @(posedge clk) begin
		rd_data <= grid_mem[rd_addr];
	end

	task automatic check(string nm, logic cond);
		if (cond) pass_count++;
		else begin
			fail_count++;
			$display("FAIL %s @%0t", nm, $time);
		end
	endtask

	initial begin
		rst_n = 0; start = 0;
		// Init grid: border = WALL(1), some SAND(2) inside
		for (int y = 0; y < GH; y++)
			for (int x = 0; x < GW; x++) begin
				if (y == 0 || y == GH-1 || x == 0 || x == GW-1)
					grid_mem[y*GW+x] = 4'd1;  // WALL
				else
					grid_mem[y*GW+x] = 4'd0;  // EMPTY
			end
		// Add 3 SAND cells inside
		grid_mem[1*GW+1] = 4'd2;
		grid_mem[1*GW+2] = 4'd2;
		grid_mem[2*GW+1] = 4'd2;
		// Expected non-EMPTY: 12 WALL (border of 4x4) + 3 SAND = 15
		// Actually 4x4 border: top=4, bottom=4, left=2, right=2 = 12 WALL

		#30;
		@(negedge clk); rst_n = 1;
		repeat (3) @(posedge clk);

		check("not busy initially", busy == 1'b0);

		// Trigger count
		@(negedge clk); start = 1;
		@(posedge clk); #1; start = 0;

		check("busy after start", busy == 1'b1);

		// Wait for done
		wait (done == 1'b1);
		@(posedge clk); #1;

		$display("TB: count = %0d (expected 15)", count);
		check("count value", count == 16'd15);
		check("not busy after done", busy == 1'b0);

		// --- Test 2: all-empty grid ---
		for (int i = 0; i < DEPTH; i++)
			grid_mem[i] = 4'd0;

		@(negedge clk); start = 1;
		@(posedge clk); #1; start = 0;
		wait (done == 1'b1);
		@(posedge clk); #1;

		$display("TB: count = %0d (expected 0)", count);
		check("empty grid count", count == 16'd0);

		if (fail_count == 0)
			$display("TB tb_particle_count: %0d/%0d PASS", pass_count, pass_count);
		else
			$display("*** FAIL *** tb_particle_count: %0d/%0d failed (%0d total)",
			         fail_count, fail_count, pass_count + fail_count);
		$finish;
	end

endmodule
