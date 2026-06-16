// =====================================================================
// bram_tdp — true dual-port RAM, independent clocks, registered reads
// =====================================================================
// Wraps Intel's altsyncram (BIDIR_DUAL_PORT) so it maps to MAX 10 M9K with
// a power-on .mif image. We instantiate the megafunction directly (like
// pll_sys wraps altpll) rather than inferring, because on MAX 10 an
// *inferred* RAM initialized from $readmemh is rejected ("MIF is not
// supported for the selected family") and collapses to registers. altsyncram
// also lets numwords be the exact depth (76 800), avoiding the 2^addr_width
// padding that inference forces.
//
// Each port: address is registered, output UNREGISTERED -> 1-cycle read
// latency. grid_mem uses port A as the CA engine's read/write port and port B
// as the scanout's read-only port (wren_b tied low). See docs/SPEC_grid_mem.md.
//
// Simulation needs the altera_mf library: vsim -L altera_mf_ver (see the
// do_*.do scripts). The init_file is read by the sim model too, so the
// preloaded grid appears in simulation exactly as on hardware.
// =====================================================================
module bram_tdp #(
		parameter int DW        = 4,
		parameter int DEPTH     = 76800,
		parameter int AW        = $clog2(DEPTH),
		parameter     INIT_FILE = ""        // .mif image, "" = uninitialized
) (
		input  logic          clk_a,
		input  logic [AW-1:0] addr_a,
		input  logic          we_a,
		input  logic [DW-1:0] din_a,
		output logic [DW-1:0] dout_a,

		input  logic          clk_b,
		input  logic [AW-1:0] addr_b,
		input  logic          we_b,
		input  logic [DW-1:0] din_b,
		output logic [DW-1:0] dout_b
);

	altsyncram #(
		.operation_mode                     ("BIDIR_DUAL_PORT"),
		.width_a                            (DW),
		.widthad_a                          (AW),
		.numwords_a                         (DEPTH),
		.width_b                            (DW),
		.widthad_b                          (AW),
		.numwords_b                         (DEPTH),
		.outdata_reg_a                      ("UNREGISTERED"),
		.outdata_reg_b                      ("UNREGISTERED"),
		.read_during_write_mode_mixed_ports ("DONT_CARE"),
		.init_file                          (INIT_FILE != "" ? INIT_FILE : "UNUSED"),
		.power_up_uninitialized             (INIT_FILE != "" ? "FALSE" : "TRUE"),
		.intended_device_family             ("MAX 10"),
		.lpm_type                           ("altsyncram")
	) u_ram (
		.clock0   (clk_a),
		.address_a(addr_a),
		.wren_a   (we_a),
		.data_a   (din_a),
		.q_a      (dout_a),
		.clock1   (clk_b),
		.address_b(addr_b),
		.wren_b   (we_b),
		.data_b   (din_b),
		.q_b      (dout_b)
	);

endmodule
