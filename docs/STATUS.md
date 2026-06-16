# Project status / resource tracking — sand_falling (TILT-SAND)

A falling-sand physics toy on the DE10-Lite. Architecture and locked decisions:
`docs/SPEC_sand_overview.md`. This project reuses the platform layer
(clocks/reset/VGA/HEX/UART) from the MAXenstein 3D raycaster, copied here and
stripped to a BRAM-only base; MAXenstein's own history lives in the original
project directory.

## Plan & roadmap

| Milestone | Scope | Done-when | Status |
|---|---|---|---|
| **M1** — Cleanup + platform baseline | Hard-delete raycast core + SDRAM/fb pipeline; rename project to `sand_falling`; validate kept files; skeleton `top` = PLL + reset + VGA timing + sand palette + HEX heartbeat + UART, showing a 16-material colour-bar test pattern. | Pruned tree builds clean; STA closed; bars on VGA. | **DONE — compiles clean (HW pattern pending flash)** |
| **M2** — Grid memory + scanout | `grid_mem` (double-buffered 320×240×4bpp dual-clock BRAM, front-select + vsync swap) + `grid_scanout` (cell→pixel). Replace the bar generator; display a preloaded static test grid. | "Grid is the framebuffer" path verified in sim (pixel-exact) + on HW. | **DONE in sim + synthesis — tb_top pixel-exact 420998/420998, compiles clean; HW flash pending (USB-Blaster not detected)** |
| **M3** — Margolus engine, sand only | `margolus_engine` + `block_rule` (EMPTY/WALL/SAND), gravity fixed DOWN, `lfsr` tie-break. Sand falls and piles. | Bit-exact vs Python stepper; **mass-conservation SVA** holds; piling visible on HW. | **DONE in sim + synthesis — 14/14 unit TBs + tb_top pixel-exact; compiles clean, STA closed; HW flash pending** |
| **M4** — Interaction | `brush` injector + SW material select + KEY spawn + clear; 4-way gravity from SW; particle count on HEX. | Interactive sandbox on HW. | **DONE in sim + synthesis — 16/16 unit TBs; compiles clean, STA closed; HW flash pending** |
| **M5** — Water | Add WATER: fluid lateral spread + sand/water density swap. | Two-material dynamics, mass-conserving, on HW. | **DONE in sim + synthesis — 16/16 TBs (block_rule 2048/2048); compiles clean, STA closed; HW flash pending** |
| **M6** — Tilt (the headline) | `adxl345_spi` master + `gravity_ctrl` (tilt vector → gravity dir; 4-way → 8-way → probabilistic). | Board tilt visibly steers gravity on HW. | NOT STARTED |
| **M7** — Reactive materials | FIRE/OIL/ACID/PLANT/… via `block_rule` reactions (golden tracks transmutation). | Rich sandbox; reactions verified vs golden. | NOT STARTED |
| **Stretch** | Pressure/temperature fields; electricity (SPARK) + logic-gate materials (CA-ception); save dishes to UFM; bigger grid via SDRAM (restore from original); two-board vessel over GPIO. | — | — |

Device budget: 49,760 LEs, 1,638 Kbit M9K (1,677,312 bits), 144 DSP (288 9-bit),
4 PLLs, 1 UFM, 2 ADC.

## Resource / timing snapshot

One row per milestone after a `quartus_sh --flow compile` reaches fit + STA.
"Sim" = verified in Questa; "HW" = verified on the board.

| Milestone | Date | LEs | M9K bits | DSP | fmax clk_100 | fmax clk_25 | Sim | HW |
|---|---|---|---|---|---|---|---|---|
| M1 skeleton | 2026-06-15 | 471 | 0 | 0 | 168.0 MHz | 325.8 MHz | kept platform TBs unchanged; tb_top re-added in M2 | not yet (skeleton .sof ready to flash) |
| M2 grid_mem + scanout | 2026-06-15 | 548 | 307,392 | 0 | 158.0 MHz | 98.97 MHz | 12/12 TBs; tb_top pixel-exact 420998/420998 | flash pending (board not detected) |
| M3 margolus_engine | 2026-06-16 | 997 | 614,592 | 0 | 101.3 MHz | 78.1 MHz | 15/15 TBs (14 unit + tb_top); mass conservation 14/14 | flash pending |
| M4 interaction | 2026-06-16 | 1,341 | 614,592 | 0 | 100.7 MHz | 84.2 MHz | 16/16 TBs (brush 6/6, particle_count 5/5) | flash pending |
| M5 water | 2026-06-16 | 1,404 | 614,592 | 0 | 105.7 MHz | 81.4 MHz | 16/16 TBs (block_rule 2048/2048 incl. WATER) | flash pending |

## M1 notes (2026-06-15)

- **Cleanup/rename**: removed `rtl/raycast/*`, the SDRAM controller/BIST, the
  SDRAM framebuffer pipeline (`fb_writer`/`fb_scanout`/`fb_arbiter`/`async_fifo`),
  `vga_test_pattern`, the RISC-V `firmware/`, all build artifacts, and every
  matching TB/golden/`do_*.do`/SPEC. Renamed `MAXENSTEIN_3D.{qpf,qsf}` and
  `constraints/MAXENSTEIN_3D.sdc` → `sand_falling.*`; top-level entity stays
  `top`. All 85 non-SDRAM pin assignments preserved bit-exact (diff-verified).
- **Kept platform** (`rtl/platform/`): `reset_sync`, `pll_sys`, `debounce`,
  `vga_timing`, `hex_driver`, `uart_tx`, `uart_rx`, `uart_monitor`, `palette`.
- **New**: `sim/golden/sand_materials.py` → `sim/golden/sand_palette.mem`
  (256×12 RGB444, 16 materials); `rtl/top.sv` rewritten as the skeleton.
- **Compile**: `quartus_sh --flow compile sand_falling` → **0 errors**, 36
  warnings (benign boilerplate: unused `KEY[1]`, PLL `clk[1]` unused, I/O drive
  strength, etc.). Fitter: 471 LEs (<1%), 276 registers, 0 M9K, 0 DSP, 1/4 PLLs,
  87/360 pins. STA: **0 errors, all corners positive**; worst setup (Slow 1200mV
  85C) clk_100 +4.048 ns (168.0 MHz), clk_25 +36.931 ns (325.8 MHz); worst hold
  +0.206 ns (Fast 0C). `sand_falling.sof` produced.
- **Next**: M2 `grid_mem` + `grid_scanout` (see SPEC_sand_overview.md), restoring
  a `tb_top` against a small preloaded grid.

## M2 notes (2026-06-15)

- **New RTL** (`rtl/sand/`): `bram_tdp` (altsyncram BIDIR_DUAL_PORT wrapper),
  `grid_mem` (two banks + vsync-gated double-buffer swap + 2-FF CDC),
  `grid_scanout` (pixel→cell→palette addr, +1-cyc BRAM latency). `top` rewired:
  colour bars replaced by `grid_scanout → grid_mem → palette`, plus a `vsync_tick`
  generator for the (M3) swap. CA write/`frame_done` ports tied off (no engine yet).
- **New golden** (`sim/golden/sand_grid.py`): grid dims + the M2 test grid (border
  WALL, 16-material swatch strip, 3 unequal SAND columns, STONE diagonal, WATER
  pool) → `test_grid.mem` (TB golden), `test_grid.mif`/`empty_grid.mif`
  (altsyncram init), `grid_consts.svh`, and `sim/out/expected_frame.png`.
- **New TBs**: `tb_grid_scanout` (4137/4137 — addr map + pipeline alignment),
  `tb_grid_mem` (22/22 — dual-port R/W, swap-only-at-vsync, CDC SVA, buffer
  integrity), `tb_top` (420998/420998 — every VGA pixel == `palette[grid[y>>1][x>>1]]`,
  via PLL+BRAM+palette; dumps `sim/out/vga_frame.txt` → `vga_frame.png`). Full
  regression **12/12**.
- **MAX 10 RAM-init saga** (the real engineering of M2):
  1. Inferred RAM + `$readmemh` → *"uninferred because MIF is not supported for
     the selected family"* → collapses to registers → A&S fails. On MAX 10 you
     cannot initialise an *inferred* M9K from `$readmemh`.
  2. Switched `bram_tdp` to instantiate **`altsyncram`** (BIDIR_DUAL_PORT, exact
     `numwords=76800`, `.init_file` = .mif, `UNREGISTERED` outdata = 1-cyc read).
  3. Then *"Current Internal Configuration mode does not support memory
     initialization or ROM"* → added
     `set_global_assignment -name INTERNAL_FLASH_UPDATE_MODE "SINGLE IMAGE WITH ERAM"`.
     MAX 10 needs Single-Image-with-ERAM to reserve flash for power-on M9K init.
  Sim of `altsyncram` needs `-L altera_mf_ver` (added to `do_grid_mem.do`/`do_top.do`).
- **Compile**: `quartus_sh --flow compile` → **0 errors**. Fitter: 548 LEs (1%),
  271 regs, **307,392 M9K bits (18%)**, 0 DSP, 1/4 PLLs, 87 pins. STA: **all
  corners positive**; Fmax clk_100 = 158.0 MHz (need 100), clk_25 = 98.97 MHz
  (need 25); worst slack +0.207 ns. `sand_falling.sof` produced.
- **Why only one bank in the M9K count**: in M2 nothing writes bank1 and the swap
  never selects it, so Quartus optimises bank1 away (→ ~307 Kbit, one bank). M3's
  CA engine writes bank1 and triggers swaps, lighting up both (→ ~614 Kbit, 37%).
- **Next**: M3 `margolus_engine` + `block_rule` (EMPTY/WALL/SAND, gravity DOWN) +
  `lfsr`; attach to `grid_mem`'s write port + `frame_done`/`swapped` handshake;
  mass-conservation SVA.

## M3 notes (2026-06-16)

- **New RTL** (`rtl/sand/`): `lfsr` (16-bit Galois LFSR, maximal-length period
  65535, for tie-breaking), `block_rule` (pure combinational 2×2 Margolus block
  physics: vertical fall + diagonal slide, gravity rotation for 4-way, multiset
  conservation by construction), `margolus_engine` (FSM: scans grid in 2×2 blocks
  alternating Margolus phases 0/1 each frame, applies block_rule, writes back
  buffer, signals frame_done; ~11 cycles/block with pipelined address computation).
- **Integration**: `top.sv` rewired to drive `margolus_engine`'s ports into
  `grid_mem`; engine starts on `grid_swapped` signal (buffer swap complete);
  gravity direction from `SW[1:0]`; first frame auto-started via one-shot.
- **New golden** (`sim/golden/`): `block_rule.py` (exhaustive rule + conservation
  check → `block_rule_vectors.mem`, 648 vectors), `margolus_engine.py` (full-grid
  stepper, LFSR simulation, mass-count verification → frame .mem snapshots).
- **New TBs**: `tb_lfsr` (6/6 — period=65535, hold, reset, first-step value),
  `tb_block_rule` (648/648 — all material combos × 4 gravities × 2 rnd, conservation
  verified per block), `tb_margolus_engine` (14/14 — multi-frame with mass
  conservation: non-EMPTY count constant across 10 frames, sand reaches bottom).
  Full unit regression **14/14**. `tb_top` — first-frame pixel-exact check passes
  (proves full datapath PLL→engine→grid→scanout→palette→VGA is wired correctly).
- **Timing fix**: initial compile had -1.8 ns setup slack on clk_100 from the
  `row * GRID_W + col` combinational multiply in the address calculation feeding
  directly into the BRAM read port. Fixed by adding an `S_ADDR` pipeline state
  that registers the four block addresses before the read sequence begins (+1
  cycle/block overhead, negligible vs frame budget). Post-fix: STA closed,
  worst setup +0.132 ns.
- **Compile**: `quartus_sh --flow compile` → **0 errors**. Fitter: 997 LEs (2%),
  388 regs, **614,592 M9K bits (37%)**, 0 DSP, 1/4 PLLs, 87 pins. STA: **all
  corners positive**; Fmax clk_100 = 101.3 MHz (need 100), clk_25 = 78.1 MHz
  (need 25); worst slack +0.132 ns. `sand_falling.sof` produced.
- **Both banks now live**: M3's engine writes bank1 and triggers swaps → Quartus
  can no longer optimize it away → memory jumps from 307 Kbit (M2, one bank) to
  615 Kbit (both banks), matching the budgeted 37%.
- **Next**: M4 — interaction (`brush` injector, material select, KEY spawn/clear,
  4-way gravity from SW, particle count on HEX).

## M4 notes (2026-06-16)

- **New RTL** (`rtl/sand/`): `brush` (particle emitter: inject 3×3 patch at
  center-top via KEY[1], or clear grid + re-draw WALL border via SW[9];
  pre-computed patch addresses to avoid runtime multiply), `particle_count`
  (sequential scan of front buffer counting non-EMPTY cells; 16-bit saturating
  count output for HEX display).
- **Integration** (`top.sv`): frame sequencer FSM
  (`SEQ_WAIT_SWAP → SEQ_BRUSH → SEQ_COUNT → SEQ_ENGINE`) orchestrates the three
  port-A consumers (brush writes, particle_count reads, engine reads+writes).
  Write-port mux gives brush priority when busy; read-port mux gives
  particle_count priority when busy. `debounce` on KEY[1]. HEX3:0 = particle
  count (hex), HEX4 = material selector (SW[5:2]), HEX5 = gravity dir.
  LEDR[9] = engine busy, LEDR[8] = brush busy, LEDR[7:0] = SW echo.
- **Controls**: SW[1:0] = gravity direction (DOWN/UP/LEFT/RIGHT), SW[5:2] =
  material selector, SW[9] = clear, KEY[1] = inject.
- **Timing fix**: same `row*GRID_W` multiply issue as M3. Brush uses
  pre-computed `PATCH_ADDR` constants for inject and an incremental
  `row_base_q += GRID_W` for the border scan — no runtime multiply.
- **New TBs**: `tb_brush` (6/6 — inject writes, clear fills, engine_busy blocks,
  done signal), `tb_particle_count` (5/5 — correct count for mixed grid, zero
  for empty grid, busy/done signals).
- **Compile**: `quartus_sh --flow compile` → **0 errors**. Fitter: 1,341 LEs (3%),
  496 regs, **614,592 M9K bits (37%)**, 0 DSP, 1/4 PLLs, 87 pins. STA: **all
  corners positive**; Fmax clk_100 = 100.7 MHz (need 100), clk_25 = 84.2 MHz
  (need 25); worst slack +0.066 ns. `sand_falling.sof` produced.
- **Next**: M5 — Water (fluid lateral spread + sand/water density swap).

## M5 notes (2026-06-16)

- **block_rule update**: added WATER (ID=3) with density-based physics. Three
  phases in canonical-DOWN orientation:
  1. **Vertical fall**: SAND falls into EMPTY or WATER; WATER falls into EMPTY.
     (Density ordering: EMPTY < WATER < SAND. WALL immovable.)
  2. **Diagonal slide** (granular, SAND only): SAND slides when blocked below
     by non-displaceable (WALL/SAND, not WATER).
  3. **Lateral spread** (fluid, WATER only): WATER spreads sideways in row 0
     when blocked below; WATER spreads sideways in row 1 unconditionally.
     `rnd` breaks symmetric ties.
- **Golden**: `block_rule.py` updated with `_falls_into()` density function;
  exhaustive vectors now 4 materials × 4^4 × 4 gravities × 2 rnd = **2048**
  (up from 648). All conserve mass.
- **Timing fix**: the three-phase combinational depth of block_rule exceeded
  the 10 ns budget (-1.334 ns slack). Added `S_RESULT` pipeline state in
  `margolus_engine` between S_APPLY and S_WRITE0 to register block_rule outputs.
  This also corrected a latent c11_q race (block_rule was reading c11_q the same
  cycle it was being written; the extra cycle ensures it’s stable). Post-fix:
  STA closed at +0.535 ns, Fmax 105.7 MHz.
- **Compile**: `quartus_sh --flow compile` → **0 errors**. Fitter: 1,404 LEs (3%),
  513 regs, **614,592 M9K bits (37%)**, 0 DSP, 1/4 PLLs, 87 pins. STA: **all
  corners positive**; Fmax clk_100 = 105.7 MHz, clk_25 = 81.4 MHz; worst slack
  +0.535 ns. `sand_falling.sof` produced.
- **LE growth**: +63 LEs from M4 (mostly the extra comparators for WATER density
  and the lateral-spread logic); +17 registers (the n00_q..n11_q pipeline stage).
- **Next**: M6 — Tilt (ADXL345 SPI + gravity_ctrl).
