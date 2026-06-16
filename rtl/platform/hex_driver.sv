// Combinational hex-to-seven-segment decoder. See docs/SPEC_hex_driver.md.
module hex_driver (
		input  logic [3:0] value,
		output logic [6:0] seg  // active-low, {g,f,e,d,c,b,a} -> HEXn[6:0]
);

	always_comb begin
		case (value)
			4'h0:   seg = 7'h40;
			4'h1:   seg = 7'h79;
			4'h2:   seg = 7'h24;
			4'h3:   seg = 7'h30;
			4'h4:   seg = 7'h19;
			4'h5:   seg = 7'h12;
			4'h6:   seg = 7'h02;
			4'h7:   seg = 7'h78;
			4'h8:   seg = 7'h00;
			4'h9:   seg = 7'h10;
			4'hA:   seg = 7'h08;
			4'hB:   seg = 7'h03;
			4'hC:   seg = 7'h46;
			4'hD:   seg = 7'h21;
			4'hE:   seg = 7'h06;
			4'hF:   seg = 7'h0E;
			default: seg = 7'h7F;
		endcase
	end

endmodule
