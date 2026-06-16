# SPEC: particle_count — non-EMPTY cell counter for HEX display

## Purpose

Counts the number of non-EMPTY cells in the front buffer and presents the
result as a 16-bit value for the HEX display. Gives instant visual feedback
that the simulation is running (count increases when brush injects, stays
constant when only the engine runs).

## Interface

```systemverilog
module particle_count #(
    parameter int GRID_W    = 320,
    parameter int GRID_H    = 240,
    parameter int CELL_BITS = 4
) (
    input  logic                 clk,
    input  logic                 rst_n,
    // trigger
    input  logic                 start,       // 1-cyc: begin counting
    // grid_mem read port (front bank)
    output logic [ADDR_BITS-1:0] rd_addr,
    input  logic [CELL_BITS-1:0] rd_data,     // 1-cycle latency
    // result
    output logic [15:0]          count,       // latched result
    output logic                 busy,
    output logic                 done         // 1-cyc: count valid
);
```

## Behavior

When `start` is pulsed, the counter scans all DEPTH addresses sequentially,
counting cells where `rd_data != 0` (non-EMPTY). After DEPTH+1 cycles (one
extra for the BRAM read pipeline), `count` is latched and `done` pulses.

The count is performed once per frame, triggered after the engine finishes
(piggybacks on the front buffer which is stable during display). Since the
front buffer doesn't change during display, the count is exact.

Maximum value: 320×240 = 76,800 → fits in 17 bits, but 16 bits (65535) is
sufficient for display since the WALL border alone uses ~1,116 cells and we'll
never fill the entire grid. We saturate at 16'hFFFF.

### HEX display mapping

`top.sv` drives HEX5:HEX0 with the 16-bit count in hex:
- HEX3:HEX0 = count[15:0] (4 hex digits)
- HEX5:HEX4 = material selector value (or blank)

## Timing

Scan takes ~76,801 cycles @ 100 MHz = 0.77 ms. Engine frame takes ~2 ms.
Together: ~2.8 ms ≪ 16.67 ms (60 Hz). Plenty of room.

## Verification

- `tb_particle_count`: small 4×4 grid with known content, verify count matches
  expected value, verify done signal, verify busy during scan.
