# SPEC: grid_mem — double-buffered cell grid (dual-clock BRAM)

`rtl/sand/grid_mem.sv` (+ `rtl/sand/bram_tdp.sv`). The cell store for the CA
engine and the VGA scanout. "The grid *is* the framebuffer": two BRAM banks
ping-pong as front (displayed) / back (being computed). See
`docs/SPEC_sand_overview.md` for the system context and the locked decision to
use BRAM (no SDRAM).

## Role

- Hold the `GRID_W × GRID_H` grid, `CELL_BITS` bits/cell, **twice** (two banks).
- Let the CA engine (clk_a / `clk_100`) read the **front** bank and write the
  **back** bank in the same frame.
- Let `grid_scanout` (clk_b / `clk_25`) read the **front** bank for display.
- Swap front/back exactly at a VGA frame boundary, with all clock-domain
  crossings handled by 1-bit 2-FF synchronizers (the data itself crosses through
  the dual-clock BRAM, never through fabric).

## Parameters

| Param | Default | Meaning |
|---|---|---|
| `GRID_W` | 320 | grid width in cells |
| `GRID_H` | 240 | grid height in cells |
| `CELL_BITS` | 4 | bits per cell (16 material IDs) |
| `DEPTH` | `GRID_W*GRID_H` | 76 800 cells/bank (derived) |
| `ADDR_BITS` | `$clog2(DEPTH)` | 17 (derived) |
| `INIT0_FILE` | "" | `$readmemh` image for bank 0 (front at reset) |
| `INIT1_FILE` | "" | `$readmemh` image for bank 1 |

Addressing is **row-major**: `addr = y*GRID_W + x`, `x` fastest. Same convention
in the CA engine, `grid_scanout`, and every `.mem` image.

## Interface

```
// ---- CA / system domain (clk_a = clk_100) ----
input  clk_a, rst_n_a
input  [ADDR_BITS-1:0] rd_addr          // read FRONT (rd_back=0) or BACK (rd_back=1)
input                  rd_back          // 1: read BACK bank (in-place multi-pass)
output [CELL_BITS-1:0] rd_data          // 1-cycle registered read
input                  wr_en            // write BACK bank
input  [ADDR_BITS-1:0] wr_addr
input  [CELL_BITS-1:0] wr_data
input                  frame_done       // 1-cyc pulse: back buffer complete -> request swap
output                 swapped          // 1-cyc pulse when swap takes effect (clk_a view)
output                 front_a          // current front bank index, clk_a domain
// ---- scanout / pixel domain (clk_b = clk_25) ----
input  clk_b, rst_n_b
input                  vsync_tick       // 1-cyc pulse at start of vblank
input  [ADDR_BITS-1:0] px_addr          // read FRONT bank
output [CELL_BITS-1:0] px_data          // 1-cycle registered read
output                 front_b          // current front bank index, clk_b domain
```

## Memory structure

Two `bram_tdp` instances (true dual-port, independent clocks, `ramstyle="M9K"`,
1-cycle registered read on each port):

| | port A (clk_a) | port B (clk_b) |
|---|---|---|
| bank0 | read if front_a==0, else write | read (scanout) |
| bank1 | read if front_a==1, else write | read (scanout) |

Port-A routing each frame: the **front** bank's port A does the CA read
(`rd_addr`, `we=0`); the **back** bank's port A does the CA write
(`wr_addr`, `wr_en`, `wr_data`). `rd_data` is muxed from the front bank's
`dout_a`; `px_data` from the front bank's `dout_b`. Because a bank is in exactly
one role for the whole frame, port A never reads and writes the same bank
simultaneously (no read-during-write hazard).

**In-place multi-pass (`rd_back=1`):** the Margolus engine runs several passes
per displayed frame; passes after the first read *and* write the BACK bank.
When `rd_back` is high, `rd_data` is muxed from the **back** bank, and the back
bank's single port A is shared between read and write by issuing a write when
`wr_en` is asserted and the read at `rd_addr` otherwise. This is safe because
the engine's read and write cycles are time-separated (S_READ* vs S_WRITE*) and
Margolus processes disjoint 2×2 blocks. The FRONT bank is untouched on port A
during in-place passes, so scanout on port B is unaffected (no tearing).

Budget: 2 × 76 800 × 4 = 614 400 bits ≈ 37 % of the 1 638 Kbit M9K (block-rounded
~76 M9K of 182).

## Double-buffer swap + CDC

The displayed bank is selected by `front_b` (clk_b). Swap rule:

1. CA finishes writing the back bank → pulses `frame_done` (clk_a). This toggles
   an internal `done_tgl` (clk_a).
2. `done_tgl` crosses to clk_b through a 2-FF synchronizer; an edge detect sets
   `pending` (clk_b).
3. At the next `vsync_tick` with `pending` set: `front_b <= ~front_b`,
   `pending <= 0`. **Swap only ever happens at vblank** → no tearing.
4. `front_b` crosses back to clk_a through a 2-FF synchronizer → `front_a`. A
   1-cycle `swapped` pulse marks the change so the CA knows the just-written
   buffer is now displayed and it may start the next frame into the new back.

Only **two single bits** cross domains (`done_tgl` a→b, `front` b→a), each via a
2-FF synchronizer — exactly the CDC the `.sdc` `set_clock_groups -asynchronous`
between clk[0] and clk[2] is cutting. Grid *data* crosses only through the
dual-clock BRAM, which is designed for independent-clock access.

### Ordering contract (for the CA engine, M3+)

The CA must not start writing the back bank for frame N+1 until it has seen
`swapped` for frame N. With ~0.3 ms of CA work per 16.7 ms frame this idle wait
is free, and it guarantees the CA never writes the bank being displayed.

For M2 there is no CA: `wr_en=0`, `frame_done=0`, so `front` stays 0 and bank0
(preloaded from `INIT0_FILE`) is displayed statically.

## Timing

- Reads: 1 cycle (registered BRAM output) on both domains.
- `front_a`/`front_b` change only as described above; treat them as stable during
  any read whose result you intend to use (the CA honors this via `swapped`; the
  scanout only swaps during vblank when no visible pixel is being fetched).

## Verification (`sim/tb/tb_grid_mem.sv`, `do_grid_mem.do`)

Structural/control module → no Python golden (per CONVENTIONS, like the
synchronizers); the TB is the reference. Uses a **small** grid (e.g. 8×4) and two
asynchronous clocks. Checks:

1. **Init**: bank0 preloaded from a small `.mem` reads back correctly on both ports.
2. **Port A R/W**: write the back bank; read the front bank; values independent.
3. **Port B read**: scanout port reads the front bank, 1-cycle latency.
4. **Swap**: write a distinct pattern into the back bank, pulse `frame_done`,
   issue `vsync_tick`s on clk_b; assert `front_b` toggles **only** on a
   `vsync_tick` that follows a `frame_done`, that port B then reads the new
   front, that `front_a` follows and `swapped` pulses once.
5. **SVA** (CDC invariants): `front_b` never changes except on a `vsync_tick`
   while `pending`; back-to-back `frame_done` with no intervening vsync produces
   exactly one swap.

Final line: `TB tb_grid_mem: N/N PASS`.
