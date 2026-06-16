# uart_loopback — TX/RX integration test

## Purpose

Connects `uart_tx.tx_serial` directly to `uart_rx.rx_serial` (no external wires)
to confirm the two modules agree on framing (8N1, LSB-first, `CLKS_PER_BIT`)
end-to-end. Both modules are unit-verified individually
(`tb_uart_tx`, `tb_uart_rx`); this test only checks the composed behavior.

## Verification

`sim/tb/tb_uart_loopback.sv` instantiates both modules with `CLKS_PER_BIT=4`
(fast sim), pulses `tx_start` for each test byte, and waits (timeout-guarded)
for `rx_valid`. For a clean loopback, `data_out` must equal the byte sent and
`rx_error` must be 0. Tests bytes `0x00, 0xFF, 0xA5, 0x3C, 0x01, 0x80`.
