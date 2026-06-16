# SPEC: TILT-SAND — system architecture overview

A 320×240-cell falling-sand physics toy on the DE10-Lite. The whole grid is
updated every frame in hardware (zero CPU), rendered to VGA, and — eventually —
its gravity is driven by the board's physical tilt (ADXL345 accelerometer).

This document is the top-level architecture. Each non-trivial module gets its
own `docs/SPEC_<module>.md` (written before its RTL, per `CONVENTIONS.md`).

## Decisions (locked)

| Axis | Choice | Why |
|---|---|---|
| Cell memory | **BRAM, double-buffered; no SDRAM** | 320×240×4bpp ×2 = 614 Kbit = ~37% of the 1,638 Kbit M9K. The grid *is* the framebuffer. SDRAM's burst/refresh model fights a CA's fine-grained read-modify-write and buys nothing here. |
| Update scheme | **Margolus 2×2 block CA** | Mass conservation is *structural* (a 1-line SVA, not an enforcement problem); no double-move/duplication hazards; gravity = relabel which corner is "down"; disjoint blocks parallelize trivially. Cost: slightly blockier than a cell-sweep powder game (acceptable; a cell-based polish pass is a documented stretch). |
| Tilt sequencing | **Switch-gravity MVP first, accel after** | Prove engine + render end-to-end with deterministic SW-selected 4-way gravity, then add ADXL345 SPI so its bugs are isolated from the engine's. |

## Data model

- Grid: `GRID_W=320` × `GRID_H=240` cells, **4 bits/cell** (16 material IDs).
- Materials and their VGA colours are defined once in
  `sim/golden/sand_materials.py` (the golden source of truth) and baked into
  `sim/golden/sand_palette.mem` for `palette.sv`. MVP uses `EMPTY(0)`,
  `WALL(1)`, `SAND(2)`, then `WATER(3)`; the rest exist for later milestones.
- Cell value `c` maps to palette address `{4'b0, c}`, so material `i` is
  palette entry `i`.

## Memory architecture (`grid_mem`)

Two BRAM **banks**, each `GRID_W*GRID_H` × 4 bits, true dual-port:

```
            port A (clk_100)            port B (clk_25)
  bank 0    CA engine R or W            grid_scanout read
  bank 1    CA engine R or W            grid_scanout read
```

- A 1-bit `front` register selects the displayed bank. `grid_scanout` always
  reads `bank[front]` (port B). The CA engine reads `bank[front]` and writes
  `bank[~front]` (each via that bank's port A — different banks, so one op per
  bank per cycle; no port conflict).
- **Swap**: after the CA engine finishes a full-grid update, `front` toggles at
  the next VGA vsync. `front` crosses clk_100→clk_25 as a single bit through a
  2-FF synchronizer — the *only* data crossing between domains (the grid data
  CDC is handled by the dual-clock BRAM itself). This is why the SDC cuts
  clk_100↔clk_25 with `set_clock_groups -asynchronous`.

Budget: 2 × 320×240×4 = 614,400 bits (~37% M9K), leaving headroom for the
palette, line buffers, and future per-cell state (temperature/pressure stretch).

## Update engine (`margolus_engine` + `block_rule`)

The grid is partitioned into 2×2 **blocks**. Each frame uses one of two block
lattices (the Margolus alternation): **phase 0** aligns blocks at even (x,y);
**phase 1** offsets the lattice by (1,1). Over the two phases, material can
migrate any direction one cell at a time, with no global bias.

- `margolus_engine` (clk_100 FSM): streams the front bank row-pair by row-pair
  through small line buffers, forms each 2×2 block, calls `block_rule`, writes
  the 4 result cells into the back bank, and raises `frame_done` when the grid
  is complete. Handles phase alternation and the partial blocks at the
  bottom/right edge of an odd-phase lattice (they hold).
- `block_rule` (pure combinational): the physics.
  `f(c00,c01,c10,c11, gravity_dir, rnd) → (n00,n01,n10,n11)`. It is **computed**
  (density compare + small interaction logic), not a 16⁴ ROM. Properties it must
  satisfy and that the TB checks:
  - **Conservation**: the multiset of materials out == in, *except* for cells
    the rule explicitly transmutes (a reaction), which the golden model tracks
    exactly. For the MVP (EMPTY/WALL/SAND) it is pure permutation → exact
    multiset equality, a clean SVA.
  - **Determinism**: same inputs (incl. `rnd`) → same outputs.
  - **Walls are immovable**; `EMPTY` is the only thing solids fall into.
- `gravity_dir` ∈ {DOWN,UP,LEFT,RIGHT} for the MVP (later 8-way, then
  probabilistic blend from the tilt vector). The rule for non-DOWN directions is
  the DOWN rule with the block coordinates rotated.
- `rnd` comes from `lfsr` (PRNG) — breaks symmetric ties (e.g. sand with both
  lower diagonals open) so piles look natural instead of striped.

Timing budget: ~19,200 blocks/phase, a handful of cycles each, at 100 MHz ≪ the
16.67 ms frame — vast headroom, so the engine is never the bottleneck.

## Rendering (`grid_scanout` + `palette`)

`grid_scanout` (clk_25): for each visible pixel, cell = `(pixel_x>>1,
pixel_y>>1)` (2×2 pixel-doubling 320×240 → 640×480), reads `bank[front]` port B,
emits `{4'b0, cell}` to `palette` → `{VGA_R,VGA_G,VGA_B}`. One pixel of pipeline
delay absorbs the BRAM + palette read latency (sync/blank delayed to match).

## Input / control

- `SW`: material selector (MVP) and 4-way gravity direction (MVP, before the
  accelerometer lands).
- `KEY[1]`: brush — inject the selected material at the cursor/emitter
  (debounced). A reserved combo clears the grid (EMPTY + border WALL).
- `HEX`: live particle count (non-EMPTY cells) once the engine runs.
- `LEDR`: selected-material / status indicator.
- `UART`: retained peek/poke debug channel.
- Later: `adxl345_spi` → `gravity_ctrl` quantizes the tilt vector to a gravity
  direction (and, as a stretch, a probabilistic blend).

## Module inventory

New (this project):
`grid_mem`, `grid_scanout`, `margolus_engine`, `block_rule`, `lfsr`, `brush`,
`gravity_ctrl`, later `adxl345_spi`, `particle_count`.

Kept platform (unchanged, HW-proven): `pll_sys` (clk_100/clk_25), `reset_sync`,
`vga_timing`, `palette`, `hex_driver`, `debounce`, `uart_tx/uart_rx/uart_monitor`.

## Clocking / reset

`pll_sys` from `MAX10_CLK1_50`: `clk_100` (CA engine + control), `clk_25` (VGA +
scanout). (`clk_100_shift` exists for the now-removed SDRAM and is unused.)
Reset: async-assert / sync-deassert, active-low, `KEY[0]` source, one
`reset_sync` per domain. See `CONVENTIONS.md`.

## Verification strategy

Per `CONVENTIONS.md`'s agent contract (SPEC → Python golden → self-checking SV
TB → `do_*.do` → clean Quartus map/fit/STA), with CA-specific emphasis:

- `sand_materials.py` — materials/palette golden (done).
- `block_rule.py` + `tb_block_rule` — exhaustive/random `f` check vs golden;
  assertion: multiset conservation (exact for MVP).
- `<engine>.py` full-grid stepper + `tb_margolus_engine` — N-frame bit-exact
  grid compare; **SVA: non-EMPTY cell count constant across a frame** (the
  headline invariant — assertion-driven verification is the whole point of the
  benchmark).
- `tb_grid_mem` / `tb_grid_scanout` — addressing, dual-port, swap, pixel map.
- `tb_top` (shrunk grid) — drop a sand column, run frames, assert it reaches the
  floor and conserves mass; capture VGA frame for visual sanity.
- HW: flash, observe on VGA; HEX particle count sanity.

See `docs/STATUS.md` for the milestone roadmap and resource/timing snapshots.
