// System PLL: 50 MHz MAX10_CLK1_50 -> 100 MHz / 100 MHz (-3 ns) / 25 MHz.
// See docs/SPEC_pll_sys.md.
module pll_sys (
		input  logic inclk0,        // 50 MHz reference (MAX10_CLK1_50)
		input  logic arst,          // async reset, active high
		output logic clk_100,       // c0: 100 MHz, 0 deg
		output logic clk_100_shift, // c1: 100 MHz, -3 ns (reserved, see CONVENTIONS.md)
		output logic clk_25,        // c2: 25 MHz, 0 deg
		output logic locked
);

	logic [5:0] clk_int;

	altpll #(
			.intended_device_family ("MAX 10"),
			.operation_mode         ("NORMAL"),
			.pll_type               ("AUTO"),
			.compensate_clock       ("CLK0"),
			.inclk0_input_frequency (20000),    // 50 MHz -> 20,000 ps period
			.clk0_multiply_by       (2),        // c0 = 100 MHz, 0 ps
			.clk0_divide_by         (1),
			.clk0_phase_shift       ("0"),
			.clk1_multiply_by       (2),        // c1 = 100 MHz, -3 ns
			.clk1_divide_by         (1),
			.clk1_phase_shift       ("-3000"),
			.clk2_multiply_by       (1),        // c2 = 25 MHz, 0 ps
			.clk2_divide_by         (2),
			.clk2_phase_shift       ("0"),
			.lpm_type               ("altpll")
	) pll_inst (
			.inclk              ({1'b0, inclk0}),
			.fbin               (1'b0),
			.pllena             (1'b1),
			.clkswitch          (1'b0),
			.areset             (arst),
			.pfdena             (1'b1),
			.clkena             (6'b111111),
			.extclkena          (4'b0000),
			.scanclk            (1'b0),
			.scanaclr           (1'b0),
			.scanclkena         (1'b0),
			.scanread           (1'b0),
			.scanwrite          (1'b0),
			.scandata           (1'b0),
			.phasecounterselect (4'b0000),
			.phaseupdown        (1'b0),
			.phasestep          (1'b0),
			.configupdate       (1'b0),
			.clk                (clk_int),
			.locked             (locked)
	);

	assign clk_100       = clk_int[0];
	assign clk_100_shift = clk_int[1];
	assign clk_25        = clk_int[2];

endmodule
