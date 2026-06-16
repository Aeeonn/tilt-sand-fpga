# uart_monitor — peek/poke register monitor protocol

## Interface

| Signal   | Dir | Width | Description |
|---|---|---|---|
| clk      | in  | 1 | clock |
| rst_n    | in  | 1 | active-low sync reset |
| rx_valid | in  | 1 | from `uart_rx`: pulse, `rx_data` holds a freshly received byte |
| rx_data  | in  | 8 | from `uart_rx.data_out` |
| tx_busy  | in  | 1 | from `uart_tx`: 1 while a byte is transmitting |
| tx_start | out | 1 | to `uart_tx`: 1-cycle pulse, latch `tx_data` and begin transmit |
| tx_data  | out | 8 | to `uart_tx.data_in`: byte to transmit |
| regs     | out | 16 x 8 | register file `regs[0..15]`, written by POKE, read by PEEK |

## Protocol

Two commands, sent host -> board over UART:

- **POKE**: `0x57 ('W'), addr, data` (3 bytes) -> `regs[addr[3:0]] <= data`;
  monitor replies with `data` (1 byte) as a write-acknowledgement/echo.
- **PEEK**: `0x52 ('R'), addr` (2 bytes) -> monitor replies with
  `regs[addr[3:0]]` (1 byte).

Only `addr[3:0]` is used (16 registers); `addr[7:4]` is ignored. Any other
first byte is treated as an unknown command and silently ignored (the FSM
stays/returns to idle, no reply). The host must wait for each reply before
sending the next command (single request/response in flight).

## Edge cases

- `rst_n`: returns to idle; `regs` reset to all-zero.
- Unknown command byte: ignored, no reply, no state change.
- A reply is only sent once `tx_busy==0`; with the host waiting for each
  reply this is always immediate in practice.

## Verification

`sim/golden/uart_monitor.py` models the protocol at the byte-stream level:
`run(regs, rx_bytes) -> (final_regs, tx_bytes)`. `sim/tb/tb_uart_monitor.sv`
drives `rx_valid`/`rx_data` directly (the UART framing itself is verified by
`tb_uart_tx`/`tb_uart_rx`/`tb_uart_loopback`), holds `tx_busy=0`, records every
`tx_start` pulse's `tx_data`, and checks the final `regs[]` and recorded
tx-byte sequence against the golden model for a POKE/PEEK/POKE/unknown/PEEK
sequence.
