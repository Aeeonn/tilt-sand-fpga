# uart_rx — UART receiver (8N1)

## Interface

| Signal    | Dir | Width | Description |
|---|---|---|---|
| clk       | in  | 1 | clock |
| rst_n     | in  | 1 | active-low sync reset |
| rx_serial | in  | 1 | serial line; idles high; passed through a 2-FF synchronizer internally |
| data_out  | out | 8 | last received byte (qualified by `rx_valid`) |
| rx_valid  | out | 1 | 1-cycle pulse: `data_out` holds a freshly received byte |
| rx_error  | out | 1 | valid alongside `rx_valid`; high if the stop bit was not 1 (framing error) |

Parameter `CLKS_PER_BIT` (default 868 = round(100e6 / 115200)), must match the
transmitter's bit period.

## Behavior

8N1, LSB-first, mirrors `uart_tx`'s framing. `rx_serial` is double-flopped
(`rx_meta`/`rx_sync`) before use. From idle, a low on the synced line is treated as
a candidate start bit; it is re-checked at the bit's center
(`HALF_BIT = (CLKS_PER_BIT-1)/2` cycles later) to reject glitches — if it has
returned high, the frame is aborted back to idle with no output. Otherwise the clock
counter resets and the 8 data bits are sampled one per `CLKS_PER_BIT` cycles
(LSB first), followed by the stop bit. On the stop bit's last cycle, `rx_valid`
pulses, `data_out` presents the assembled byte, and `rx_error` reports whether the
stop bit read 0 instead of 1.

## Edge cases

- Glitch shorter than `HALF_BIT` cycles on `rx_serial`: rejected, returns to idle,
  no `rx_valid`.
- Stop bit not 1 (framing error): `rx_valid` still pulses with the 8 data bits
  captured; `rx_error=1` flags the corrupted frame for the consumer to discard.
- `rst_n` mid-frame: returns to idle next cycle, no spurious `rx_valid`.

## Verification

`sim/golden/uart_rx.py` is the inverse of `uart_tx.py`'s `expected_frame`: given a
10-bit frame `[start, d0..d7, stop]`, returns `(byte, framing_error)`.
`sim/tb/tb_uart_rx.sv` instantiates `uart_rx` with `CLKS_PER_BIT=16` (fast sim;
real instantiation uses the 868 default), drives several full frames bit-by-bit
onto `rx_serial` (including one with a corrupted stop bit), and for each waits for
`rx_valid` (timeout-guarded) then checks `data_out`/`rx_error` against the golden
model.
