// =====================================================================
// lfsr — 16-bit Galois LFSR pseudo-random number generator
// =====================================================================
// Provides random bits for tie-breaking in block_rule. Galois form:
// XOR on feedback, single-gate depth. Polynomial: x^16+x^14+x^13+x^11+1
// (maximal-length, period 2^16-1 = 65535). See docs/SPEC_lfsr.md.
// =====================================================================
module lfsr #(
		parameter int                WIDTH = 16,
		parameter logic [WIDTH-1:0]  SEED  = 16'hACE1
) (
		input  logic             clk,
		input  logic             rst_n,
		input  logic             en,
		output logic [WIDTH-1:0] rnd
);

	// Galois taps for x^16 + x^14 + x^13 + x^11 + 1
	// Reflection: bits 15, 13, 12, 10 = 0xB400
	localparam logic [WIDTH-1:0] POLY = 16'hB400;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			rnd <= SEED;
		end else if (en) begin
			if (rnd[0])
				rnd <= (rnd >> 1) ^ POLY;
			else
				rnd <= rnd >> 1;
		end
	end

endmodule
