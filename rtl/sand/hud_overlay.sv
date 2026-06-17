// =====================================================================
// hud_overlay — on-screen status HUD (pure combinational, clk_25)
// =====================================================================
// Draws a status bar across the top 16 pixel rows of the 640×480 frame.
// Three elements give the user live guidance:
//   1. Material swatch  — a framed box filled with the selected material's
//      palette colour (tells you what KEY[1] will spawn).
//   2. Gravity D-pad    — four dots (up/down/left/right); the active
//      gravity direction is lit white, the others dim grey.
//   3. Particle bar     — a horizontal bar whose length tracks the live
//      non-EMPTY cell count (fills as you add material).
//
// Pure function of pixel position + status inputs; no clock, no state.
// top.sv pipelines ov_on/ov_rgb to align with the palette output and
// composites the HUD over the grid colour. See docs/SPEC_hud_overlay.md.
// =====================================================================
module hud_overlay (
		input  logic [9:0]  pixel_x,
		input  logic [9:0]  pixel_y,
		input  logic [11:0] sel_color,   // selected material colour (RGB444)
		input  logic [1:0]  grav_dir,    // 0=DOWN 1=UP 2=LEFT 3=RIGHT
		input  logic [15:0] count,       // live particle count
		output logic        ov_on,       // 1 = draw overlay (else show grid)
		output logic [11:0] ov_rgb       // overlay colour (RGB444)
);

	// ---- Colours ----
	localparam logic [11:0] C_WHITE = 12'hFFF;
	localparam logic [11:0] C_DGRAY = 12'h333;
	localparam logic [11:0] C_BAR   = 12'h0CF;   // cyan

	// ---- Element 1: material swatch (framed box) ----
	// Outer frame x[4..19] y[0..15]; inner fill x[5..18] y[1..14].
	logic sw_outer, sw_fill, sw_frame;
	always_comb begin
		sw_outer = (pixel_x >= 10'd4)  && (pixel_x <= 10'd19) && (pixel_y <= 10'd15);
		sw_fill  = (pixel_x >= 10'd5)  && (pixel_x <= 10'd18) &&
		           (pixel_y >= 10'd1)  && (pixel_y <= 10'd14);
		sw_frame = sw_outer && !sw_fill;   // 1-px border
	end

	// ---- Element 2: gravity D-pad (3×3 dots around x34,y8) ----
	logic g_up, g_down, g_left, g_right;
	always_comb begin
		g_up    = (pixel_x >= 10'd33) && (pixel_x <= 10'd35) &&
		          (pixel_y >= 10'd1)  && (pixel_y <= 10'd3);
		g_down  = (pixel_x >= 10'd33) && (pixel_x <= 10'd35) &&
		          (pixel_y >= 10'd12) && (pixel_y <= 10'd14);
		g_left  = (pixel_x >= 10'd27) && (pixel_x <= 10'd29) &&
		          (pixel_y >= 10'd7)  && (pixel_y <= 10'd9);
		g_right = (pixel_x >= 10'd39) && (pixel_x <= 10'd41) &&
		          (pixel_y >= 10'd7)  && (pixel_y <= 10'd9);
	end

	logic up_act, down_act, left_act, right_act;
	assign down_act  = (grav_dir == 2'd0);
	assign up_act    = (grav_dir == 2'd1);
	assign left_act  = (grav_dir == 2'd2);
	assign right_act = (grav_dir == 2'd3);

	// ---- Element 3: particle count bar ----
	// Frame x[48..607] y[3..12]; fill x[49..] y[5..10], length ∝ count.
	// len = count>>4 clamped to 558 (full bar at count = 8928).
	localparam int BAR_X0  = 49;
	localparam int BAR_MAX = 558;
	logic [15:0] len_raw;
	logic [9:0]  bar_len;
	assign len_raw = count >> 4;
	assign bar_len = (len_raw > 16'(BAR_MAX)) ? 10'(BAR_MAX) : len_raw[9:0];

	logic bar_outer, bar_fill, bar_frame;
	always_comb begin
		bar_outer = (pixel_x >= 10'd48) && (pixel_x <= 10'd607) &&
		            (pixel_y >= 10'd3)  && (pixel_y <= 10'd12);
		// frame = 1-px outline of the outer rect
		bar_frame = bar_outer &&
		            ((pixel_x == 10'd48) || (pixel_x == 10'd607) ||
		             (pixel_y == 10'd3)  || (pixel_y == 10'd12));
		bar_fill  = (pixel_x >= 10'(BAR_X0)) && (pixel_x < (10'(BAR_X0) + bar_len)) &&
		            (pixel_y >= 10'd5) && (pixel_y <= 10'd10);
	end

	// ---- Composite (fills take priority over frames) ----
	always_comb begin
		ov_on  = 1'b0;
		ov_rgb = 12'h000;

		if (sw_fill) begin
			ov_on = 1'b1; ov_rgb = sel_color;
		end else if (sw_frame) begin
			ov_on = 1'b1; ov_rgb = C_WHITE;
		end else if (g_up) begin
			ov_on = 1'b1; ov_rgb = up_act    ? C_WHITE : C_DGRAY;
		end else if (g_down) begin
			ov_on = 1'b1; ov_rgb = down_act  ? C_WHITE : C_DGRAY;
		end else if (g_left) begin
			ov_on = 1'b1; ov_rgb = left_act  ? C_WHITE : C_DGRAY;
		end else if (g_right) begin
			ov_on = 1'b1; ov_rgb = right_act ? C_WHITE : C_DGRAY;
		end else if (bar_fill) begin
			ov_on = 1'b1; ov_rgb = C_BAR;
		end else if (bar_frame) begin
			ov_on = 1'b1; ov_rgb = C_WHITE;
		end
	end

endmodule
