// =====================================================================
// gravity_ctrl — tilt vector → gravity direction
// =====================================================================
// Converts signed 10-bit X/Y accelerometer readings into a 2-bit
// gravity direction for the Margolus engine. Uses a dead-zone
// threshold to prevent jitter when the board is nearly flat.
//
// Axis mapping (DE10-Lite orientation, USB port facing away):
//   +X = tilt right  → gravity RIGHT (3)
//   -X = tilt left   → gravity LEFT  (2)
//   +Y = tilt away   → gravity UP    (1)
//   -Y = tilt toward → gravity DOWN  (0)
//
// When both axes are below the threshold, gravity stays at its last
// valid direction (hysteresis). The dominant axis wins (larger magnitude).
//
// See docs/SPEC_gravity_ctrl.md (if created).
// =====================================================================
module gravity_ctrl #(
		parameter int THRESHOLD = 50   // dead-zone: ~0.1g at ±2g/1024
) (
		input  logic        clk,
		input  logic        rst_n,
		input  logic signed [9:0] accel_x,
		input  logic signed [9:0] accel_y,
		input  logic        data_valid,   // pulse: new data available
		input  logic        sw_override,  // 1 = use sw_dir instead
		input  logic [1:0]  sw_dir,       // manual direction from switches
		output logic [1:0]  grav_dir      // 0=DOWN 1=UP 2=LEFT 3=RIGHT
);

	localparam logic [1:0] DIR_DOWN  = 2'd0;
	localparam logic [1:0] DIR_UP    = 2'd1;
	localparam logic [1:0] DIR_LEFT  = 2'd2;
	localparam logic [1:0] DIR_RIGHT = 2'd3;

	// Absolute values
	logic [9:0] abs_x, abs_y;
	assign abs_x = accel_x[9] ? (~accel_x + 10'd1) : accel_x;
	assign abs_y = accel_y[9] ? (~accel_y + 10'd1) : accel_y;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			grav_dir <= DIR_DOWN;
		end else if (sw_override) begin
			grav_dir <= sw_dir;
		end else if (data_valid) begin
			// Only update if at least one axis exceeds the dead-zone
			if (abs_x > THRESHOLD[9:0] || abs_y > THRESHOLD[9:0]) begin
				if (abs_x >= abs_y) begin
					// X dominant
					grav_dir <= accel_x[9] ? DIR_LEFT : DIR_RIGHT;
				end else begin
					// Y dominant
					grav_dir <= accel_y[9] ? DIR_DOWN : DIR_UP;
				end
			end
			// else: keep previous direction (hysteresis)
		end
	end

endmodule
