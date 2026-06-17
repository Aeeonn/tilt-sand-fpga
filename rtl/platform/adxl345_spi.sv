// =====================================================================
// adxl345_spi — SPI master for the ADXL345 3-axis accelerometer
// =====================================================================
// Periodically reads the X and Y acceleration registers (0x32..0x35)
// via SPI mode 3 (CPOL=1, CPHA=1). Outputs signed 10-bit X and Y
// values, updated at ~100 Hz (every ~1M clk_100 cycles).
//
// DE10-Lite ADXL345: SPI mode, 4-wire, ±2g default, 10-bit resolution.
// SPI clock: clk_100 / (2*CLK_DIV) — target ~2 MHz (CLK_DIV=25).
// See docs/SPEC_adxl345_spi.md.
// =====================================================================
module adxl345_spi #(
		parameter int CLK_DIV    = 25,      // SCLK = clk/(2*CLK_DIV) ≈ 2 MHz
		parameter int POLL_DIV   = 1000000  // read interval in clk cycles (~100 Hz)
) (
		input  logic        clk,
		input  logic        rst_n,
		// SPI pins
		output logic        spi_cs_n,
		output logic        spi_sclk,
		output logic        spi_mosi,
		input  logic        spi_miso,
		// Accelerometer data (signed 10-bit, ±2g)
		output logic signed [9:0] accel_x,
		output logic signed [9:0] accel_y,
		output logic        data_valid    // pulses when new x/y are latched
);

	// -----------------------------------------------------------------
	// SPI clock divider
	// -----------------------------------------------------------------
	localparam int DIV_BITS = $clog2(CLK_DIV);
	logic [DIV_BITS-1:0] div_cnt;
	logic sclk_en;   // pulses at SCLK rate (both edges)

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			div_cnt <= '0;
		end else begin
			if (div_cnt == DIV_BITS'(CLK_DIV - 1))
				div_cnt <= '0;
			else
				div_cnt <= div_cnt + 1'b1;
		end
	end
	assign sclk_en = (div_cnt == '0);

	// -----------------------------------------------------------------
	// Poll timer
	// -----------------------------------------------------------------
	localparam int POLL_BITS = $clog2(POLL_DIV);
	logic [POLL_BITS-1:0] poll_cnt;
	logic poll_tick;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n)
			poll_cnt <= '0;
		else if (poll_cnt == POLL_BITS'(POLL_DIV - 1))
			poll_cnt <= '0;
		else
			poll_cnt <= poll_cnt + 1'b1;
	end
	assign poll_tick = (poll_cnt == '0);

	// -----------------------------------------------------------------
	// FSM
	// -----------------------------------------------------------------
	typedef enum logic [3:0] {
		S_IDLE,
		S_INIT_START,   // configure ADXL345 (write POWER_CTL)
		S_INIT_TX,
		S_INIT_DONE,
		S_READ_START,   // multi-byte read: addr 0x32 (DATAX0), 4 bytes
		S_READ_TX,
		S_READ_RX,
		S_READ_DONE,
		S_LATCH
	} state_e;

	state_e state;
	logic initialized_q;

	// SPI shift register
	logic [7:0]  tx_byte;
	logic [7:0]  rx_byte;
	logic [2:0]  bit_cnt;      // 0..7
	logic [3:0]  byte_cnt;     // bytes in current transaction
	logic [3:0]  byte_idx;     // current byte index
	logic        sclk_q;
	logic        cs_n_q;
	logic        mosi_q;
	logic        sclk_phase;   // 0=setup edge, 1=sample edge

	// Data capture
	logic [7:0] rx_buf [4];    // DATAX0, DATAX1, DATAY0, DATAY1

	assign spi_cs_n = cs_n_q;
	assign spi_sclk = sclk_q;
	assign spi_mosi = mosi_q;

	// ADXL345 SPI commands
	// Write: {0, 0, addr[5:0]} (single-byte write)
	// Read multi: {1, 1, addr[5:0]} (multi-byte read)
	localparam logic [7:0] CMD_WRITE_POWER = 8'h2D;  // addr 0x2D = POWER_CTL
	localparam logic [7:0] VAL_MEASURE     = 8'h08;  // measurement mode
	localparam logic [7:0] CMD_READ_DATA   = 8'hF2;  // {1,1,110010} = MB read from 0x32

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			state         <= S_IDLE;
			initialized_q <= 1'b0;
			cs_n_q        <= 1'b1;
			sclk_q        <= 1'b1;   // CPOL=1: idle high
			mosi_q        <= 1'b0;
			bit_cnt       <= '0;
			byte_cnt      <= '0;
			byte_idx      <= '0;
			sclk_phase    <= 1'b0;
			accel_x       <= '0;
			accel_y       <= '0;
			data_valid    <= 1'b0;
			tx_byte       <= '0;
			rx_byte       <= '0;
			for (int i = 0; i < 4; i++) rx_buf[i] <= '0;
		end else begin
			data_valid <= 1'b0;

			case (state)
				S_IDLE: begin
					cs_n_q <= 1'b1;
					sclk_q <= 1'b1;
					if (!initialized_q)
						state <= S_INIT_START;
					else if (poll_tick)
						state <= S_READ_START;
				end

				// --- Init: write 0x08 to POWER_CTL (addr 0x2D) ---
				S_INIT_START: begin
					cs_n_q     <= 1'b0;
					byte_cnt   <= 4'd2;   // 2 bytes: addr + data
					byte_idx   <= '0;
					bit_cnt    <= '0;
					sclk_phase <= 1'b0;
					tx_byte    <= CMD_WRITE_POWER;
					state      <= S_INIT_TX;
				end

				S_INIT_TX: begin
					if (sclk_en) begin
						if (!sclk_phase) begin
							// Setup edge: drive MOSI, toggle SCLK low
							sclk_q     <= 1'b0;
							mosi_q     <= tx_byte[7];
							sclk_phase <= 1'b1;
						end else begin
							// Sample edge: toggle SCLK high
							sclk_q     <= 1'b1;
							sclk_phase <= 1'b0;
							tx_byte    <= {tx_byte[6:0], 1'b0};
							bit_cnt    <= bit_cnt + 3'd1;
							if (bit_cnt == 3'd7) begin
								byte_idx <= byte_idx + 4'd1;
								bit_cnt  <= '0;
								if (byte_idx == 4'd0)
									tx_byte <= VAL_MEASURE;
								else
									state <= S_INIT_DONE;
							end
						end
					end
				end

				S_INIT_DONE: begin
					cs_n_q        <= 1'b1;
					sclk_q        <= 1'b1;
					initialized_q <= 1'b1;
					state         <= S_IDLE;
				end

				// --- Read: multi-byte read from 0x32 (4 bytes: XL,XH,YL,YH) ---
				S_READ_START: begin
					cs_n_q     <= 1'b0;
					byte_cnt   <= 4'd5;   // 1 cmd + 4 data bytes
					byte_idx   <= '0;
					bit_cnt    <= '0;
					sclk_phase <= 1'b0;
					tx_byte    <= CMD_READ_DATA;
					state      <= S_READ_TX;
				end

				S_READ_TX: begin
					if (sclk_en) begin
						if (!sclk_phase) begin
							sclk_q     <= 1'b0;
							mosi_q     <= tx_byte[7];
							sclk_phase <= 1'b1;
						end else begin
							sclk_q     <= 1'b1;
							sclk_phase <= 1'b0;
							rx_byte    <= {rx_byte[6:0], spi_miso};
							tx_byte    <= {tx_byte[6:0], 1'b0};
							bit_cnt    <= bit_cnt + 3'd1;
							if (bit_cnt == 3'd7) begin
								byte_idx <= byte_idx + 4'd1;
								bit_cnt  <= '0;
								if (byte_idx == 4'd0) begin
									// Command byte sent; switch to receive
									tx_byte <= 8'h00;  // drive 0 while reading
								end else begin
									// Store received data byte
									rx_buf[byte_idx - 1] <= rx_byte;
									if (byte_idx == 4'd4)
										state <= S_READ_DONE;
								end
							end
						end
					end
				end

				S_READ_DONE: begin
					cs_n_q <= 1'b1;
					sclk_q <= 1'b1;
					state  <= S_LATCH;
				end

				S_LATCH: begin
					// Assemble signed 10-bit values (ADXL345: bits [9:0] of {HIGH, LOW})
					accel_x    <= {rx_buf[1][1:0], rx_buf[0]};
					accel_y    <= {rx_buf[3][1:0], rx_buf[2]};
					data_valid <= 1'b1;
					state      <= S_IDLE;
				end

				default: state <= S_IDLE;
			endcase
		end
	end

endmodule
