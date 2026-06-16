# uart_tx — UART transmitter (8N1)

## Interface

| Signal    | Dir | Width | Description |
|---|---|---|---|
| clk       | in  | 1 | clock |
| rst_n     | in  | 1 | active-low sync reset |
| data_in   | in  | 8 | byte to transmit |
| tx_start  | in  | 1 | pulse (1 cycle) to begin sending `data_in`; ignored while `tx_busy` |
| tx_busy   | out | 1 | high while a frame is in flight |
| tx_serial | out | 1 | serial line; idles high |
| tx_done   | out | 1 | 1-cycle pulse on the cycle the frame completes (and `tx_busy` falls) |

Parameter `CLKS_PER_BIT` (default 868 = round(100e6 / 115200), for 115200 baud on
`clk_100`; ~0.006% baud error, well within UART tolerance).

## Behavior

8N1, LSB-first: 1 start bit (0) + 8 data bits + 1 stop bit (1), each held for
`CLKS_PER_BIT` clock cycles. `tx_serial` idles high. `tx_start` (sampled only while
idle) latches `data_in` and begins the frame; `tx_busy` is high for the whole frame
(start bit through stop bit). `tx_done` pulses for one cycle as `tx_busy` falls back
to idle.

## Edge cases

- `tx_start` while `tx_busy`: ignored, current frame finishes normally (no glitch).
- `rst_n` asserted mid-frame: returns to idle next cycle, `tx_serial` goes high.

## Verification

`sim/golden/uart_tx.py` builds the expected 10-bit frame (`start, d0..d7, stop`) for a
given byte. `sim/tb/tb_uart_tx.sv` instantiates `uart_tx` with `CLKS_PER_BIT=4` (fast
sim; real instantiation uses the 868 default), sends several bytes back-to-back, and
for each bit period samples `tx_serial`/`tx_busy` on the first cycle of that bit's
`CLKS_PER_BIT`-cycle window (where the registered output has settled) against the
golden frame. Also checks the `tx_done` pulse and idle levels before/after each byte.
