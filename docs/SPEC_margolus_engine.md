# SPEC: margolus_engine — Margolus 2×2 block CA scan engine

## Purpose

FSM that scans the grid in 2×2 blocks, applies `block_rule`, writes results
back, and signals `frame_done` when the full grid is processed. This drives
`grid_mem`'s double-buffer swap and is the core update loop.

## Interface

```systemverilog
module margolus_engine #(
    parameter int GRID_W    = 320,
    parameter int GRID_H    = 240,
    parameter int CELL_BITS = 4
) (
    input  logic                 clk,         // clk_100
    input  logic                 rst_n,
    input  logic                 start,       // 1-cyc: begin a new frame
    input  logic [1:0]           grav_dir,    // gravity direction for block_rule
    // grid_mem port-A (read front, write back)
    output logic [ADDR_BITS-1:0] rd_addr,
    input  logic [CELL_BITS-1:0] rd_data,     // 1-cycle latency
    output logic                 wr_en,
    output logic [ADDR_BITS-1:0] wr_addr,
    output logic [CELL_BITS-1:0] wr_data,
    // handshake
    output logic                 frame_done,  // 1-cyc pulse: frame complete
    output logic                 busy         // high while scanning
);
```

## Block partitioning (Margolus alternation)

Each frame uses one **phase**, alternating 0 and 1 each frame:

- **Phase 0**: blocks aligned at even (x,y) — block (bx,by) covers cells
  `(2*bx, 2*by)` to `(2*bx+1, 2*by+1)`.
- **Phase 1**: blocks offset by (1,1) — block (bx,by) covers cells
  `(2*bx+1, 2*by+1)` to `(2*bx+2, 2*by+2)`.

Phase 1 blocks that extend outside the grid (top row, left column, bottom
row, right column for odd-sized grids) are **held** — those cells pass through
unchanged. Since the border is WALL, this is equivalent to "walls never move."

Grid dimensions: 320×240. Phase 0 gives 160×120 = 19,200 blocks. Phase 1
gives 159×119 = 18,921 interior blocks (edge blocks held).

## FSM

```
S_IDLE → (start) → S_READ0 → S_READ1 → S_READ2 → S_READ3 → S_APPLY → S_WRITE → S_NEXT → S_DONE
                        ↑__________________________________________________________|
```

### States

| State | Description |
|-------|-------------|
| S_IDLE | Wait for `start`. Phase counter is already set for this frame. |
| S_READ0..3 | Issue 4 read addresses for the current 2×2 block, one per cycle. Each read has 1-cycle BRAM latency, so we pipeline: issue addr in READn, capture data in READn+1. |
| S_APPLY | All 4 cells captured; `block_rule` output is ready (combinational). Advance the LFSR. |
| S_WRITE | Write the 4 result cells back (4 cycles, one write per cycle to the back bank). |
| S_NEXT | Advance to the next block. If more blocks remain, go to S_READ0. If done, go to S_DONE. |
| S_DONE | Pulse `frame_done` for 1 cycle, toggle the internal phase, return to S_IDLE. |

### Read pipeline detail

The engine reads 4 cells per block. Grid_mem's port-A read has 1-cycle latency
(altsyncram UNREGISTERED output). The engine issues addresses on consecutive
cycles and captures data on the following cycle:

```
Cycle    Action             rd_addr          Captured
  0      issue addr c00     row0*W + col0    —
  1      issue addr c01     row0*W + col1    c00 ← rd_data
  2      issue addr c10     row1*W + col0    c01 ← rd_data
  3      issue addr c11     row1*W + col1    c10 ← rd_data
  4      (apply)            —                c11 ← rd_data
```

### Write sequence

4 cycles writing `n00, n01, n10, n11` to the back bank at the same addresses.

### Block scan order

Row-major by block row, then block column. For phase 0:
`by = 0,1,...,119; bx = 0,1,...,159`. For phase 1:
`by = 0,1,...,118; bx = 0,1,...,158` (interior blocks only).

### Cycle budget

Per block: 4 read + 1 apply + 4 write + 1 next = 10 cycles.
Phase 0: 19,200 blocks × 10 = 192,000 cycles @ 100 MHz = 1.92 ms.
Phase 1: 18,921 blocks × 10 = 189,210 cycles @ 100 MHz = 1.89 ms.
Total per frame: ~3.8 ms ≪ 16.67 ms (60 Hz) — vast headroom.

## Start / frame_done handshake with top

`top.sv` generates a `start` pulse to kick off each frame. In M3, the simplest
approach: `start` comes from the `swapped` signal from `grid_mem` — once the
buffers have swapped (at vsync), the engine immediately starts the next frame
on the new back buffer.

Sequence per frame:
1. Engine finishes → pulses `frame_done`.
2. `grid_mem` latches the done-toggle.
3. At next vsync, `grid_mem` swaps buffers → pulses `swapped`.
4. `top` sends `start` to the engine.
5. Engine processes the new back buffer.

If the engine finishes well before vsync (it will — 3.8 ms vs 16.67 ms),
it idles in S_IDLE until the swap completes and `start` arrives.

## Mass-conservation SVA

The engine (or its testbench) carries an assertion:

```systemverilog
// After each block_rule application: multiset in == multiset out.
// For M3 (EMPTY/WALL/SAND only), this is a pure permutation check.
```

The testbench also checks that the total non-EMPTY cell count across the entire
grid is constant frame-over-frame (the "headline invariant" from the overview
spec).

## Verification

- `tb_block_rule`: exhaustive rule check (648 cases), conservation per block.
- `tb_margolus_engine`: multi-frame simulation with a known initial grid
  (e.g. a sand column over empty space). Checks:
  - Frame-level mass conservation (non-EMPTY count constant).
  - Sand falls and piles (final state matches Python stepper).
  - `frame_done` pulses exactly once per frame.
  - `busy` goes high on start, low after done.
  - Bit-exact match vs Python golden for N frames.
- `tb_top` (updated): the full pipeline — engine writes grid, scanout reads it,
  VGA frame captured. Visual + mass-conservation check.
