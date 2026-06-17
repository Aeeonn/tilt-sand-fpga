# Project conventions

Living document. Update it when a convention changes — don't let it drift from what the
code actually does.

## Toolchain

- Quartus Prime Lite **23.1std.1** (`C:\intelFPGA_lite\23.1std`), device `10M50DAF484C7G`,
  top-level entity `top`.
- Simulation: **Questa Intel FPGA Starter Edition** (`questa_fse\win64\vsim.exe`). No
  Verilator/Icarus on this machine — PROJECT_IDEAS.md's "Verilator for the inner loop"
  is superseded by a Questa-only flow. Keep per-module testbenches small enough that
  vsim compile+run stays fast (seconds, not minutes).
- Python 3.14 available for golden models (`sim/golden/`).

## Language

- **SystemVerilog (.sv)** for both RTL and testbenches.
- RTL sticks to a synthesizable subset: `always_ff`/`always_comb`, `logic`, packed
  arrays, `enum` for FSM states, `parameter`/`localparam`. No classes, no dynamic
  arrays, no `always_latch` (intentional latches: don't).
- Testbenches may use the full SV toolbox: `initial`/`task`/`function`, `$display`,
  file I/O, assertions (`assert property` where useful).

## Directory layout

```
rtl/
  platform/   reusable infrastructure (clocking, reset, IO, accelerometer, debug)
  sand/       CA-engine datapath (grid_mem, margolus_engine, block_rule, lfsr, ...)
  top.sv      top-level module (matches TOP_LEVEL_ENTITY "top")
sim/
  tb/         one testbench per RTL module: tb_<module>.sv
  golden/     Python reference models, one per module needing one
  scripts/    vsim .do files: do_<module>.do
  out/        simulation output artifacts (vga_frame.txt, .png) — gitignored
docs/
  CONVENTIONS.md   this file
  STATUS.md        per-milestone resource/timing snapshot
  SPEC_<module>.md one per non-trivial module, written before its RTL
constraints/
  sand_falling.sdc   timing constraints (project name: sand_falling)
```

`.qsf` carries **synthesizable RTL only** (`rtl/**.sv` as `SYSTEMVERILOG_FILE`).
Testbenches are not added to the Quartus project; they're run standalone via
`vsim -do sim/scripts/do_<module>.do`. This keeps the synthesis file list honest and
avoids NativeLink complexity.

## Naming

- Clocks: `clk_<freq>` (`clk_100`, `clk_25`). Reset: `rst_n` (active-low, synchronous
  release — see below). Avoid bare `clk`/`rst` once more than one domain exists.
- Registered/pipelined versions of a signal get a numeric suffix per stage:
  `foo_q1`, `foo_q2`, not `foo_reg`/`foo_reg2`.
- Active-low signals end in `_n`.
- FSM state enums: `typedef enum logic [N:0] {S_IDLE, S_..., } state_e;` with the
  state register named `state`/`state_q` and next-state `state_d`.

## Reset strategy

Async-assert / sync-deassert, active-low (`rst_n`), one synchronizer per clock domain
(`rtl/platform/reset_sync.sv`). The board has no dedicated reset button wired in the
.qsf; M0 derives the async reset source from `KEY[0]` (active-low, pressed = reset) via
a `set_false_path` on the raw pin into each synchronizer's first stage — see
`constraints/sand_falling.sdc`.

## Clock domains

One PLL (`rtl/platform/pll_sys.sv`, ALTPLL) fed by `MAX10_CLK1_50`:

| Output | Freq | Use | Phase |
|---|---|---|---|
| c0 | 100 MHz | system domain (`clk_100`) | 0° |
| c1 | 100 MHz | unused (was SDRAM clock-out; SDRAM removed) | −3 ns |
| c2 | 25 MHz | VGA pixel domain (`clk_25`) | 0° |

`clk_100` and `clk_25` are asynchronous. The only signal crossing between them
is the single-bit double-buffer `front`-select flag (toggled when the CA engine
finishes a grid update and the next vsync arrives), resynchronized with a 2-FF
synchronizer in the `clk_25` domain. The grid data itself crosses through the
dual-clock grid BRAM (`grid_mem`), not through fabric. `set_clock_groups
-asynchronous` in `constraints/sand_falling.sdc` cuts these paths from STA — the
correct treatment for synchronizer-based CDC.

Any future single-bit crossing: 2-FF synchronizer, document at the instantiation site.
Any future bus/stream crossing: async FIFO with gray-coded pointers, formally checked
where practical.

## Integer / fixed-point

The sand CA engine is integer/material logic — there is no fixed-point datapath
(the Margolus block rule is combinational material/density logic; the
accelerometer tilt→gravity quantization uses integer compares on the sensor
vector). If a future module does need fixed-point, annotate each signal with a
`// Qm.f` comment and keep its Python golden model in the same Q-format (integer
math with explicit shifts, never floats) so diffs are bit-exact.

## On-chip memory (M9K)

Large RAMs (the cell grid, line buffers) go in M9K. On this MAX 10 device there are
two hard rules learned in M2:

- **Don't initialise inferred RAM with `$readmemh`.** Quartus reports *"uninferred
  because MIF is not supported for the selected family"* and the array collapses to
  registers. Instead instantiate **`altsyncram`** directly (as `rtl/sand/bram_tdp.sv`
  does, the way `pll_sys` wraps `altpll`): exact `numwords`, `.init_file` = a `.mif`,
  `outdata_reg = "UNREGISTERED"` for 1-cycle read latency. Simulation then needs
  `vsim -L altera_mf_ver`.
- **Initialised memory needs ERAM config mode.** The `.qsf` must carry
  `set_global_assignment -name INTERNAL_FLASH_UPDATE_MODE "SINGLE IMAGE WITH ERAM"`
  or Quartus errors *"Current Internal Configuration mode does not support memory
  initialization or ROM."* (MAX 10 reserves on-chip flash to preload M9K at power-up.)

Generate `.mif` images from the Python golden (`sim/golden/sand_grid.py`) so the
init data has one source of truth shared with the testbenches' `.mem` files.

## Agent contract (verification discipline)

No RTL module is considered done without, in this order:
1. `docs/SPEC_<module>.md` — interface, behavior, timing, edge cases. Written first.
2. `sim/golden/<module>.py` — Python reference model, where the module does anything
   computational (skip for pure structural glue like synchronizers).
3. `sim/tb/tb_<module>.sv` — self-checking: prints `PASS`/`FAIL` per check and a final
   summary line `TB <module>: N/N PASS` or `*** FAIL ***` with a nonzero count. No
   "looks right in the waveform" — the testbench decides.
4. `sim/scripts/do_<module>.do` — vsim script: compile + run + quit, exit code reflects
   pass/fail.
5. For modules that touch FIFOs/arbiters/CDC: `assert property` checks for the
   invariant in question (no underflow/overflow, starvation bound, etc.).
6. For synthesizable modules included in `top.sv`: `.qsf` updated, and a Quartus
   map/fit/STA run stays clean (no new timing violations, no unmapped pins). Record
   LE/M9K/DSP/fmax in `docs/STATUS.md`.

## Status tracking

`docs/STATUS.md` holds one row per milestone: date, LE/M9K/DSP usage, fmax for each
clock domain, and what was verified in simulation vs. on hardware. Update it whenever
`quartus_sh` is run to completion.

## Build artifacts

Quartus and ModelSim generate numerous reports and databases (`db/`, `incremental_db/`,
`*.rpt`, `*.sof`, `transcript`, `work/`, etc.). These are excluded from version control
via `.gitignore` and should be cleaned up regularly to keep the working directory
manageable.

**To clean up after a Quartus/ModelSim session:**
```powershell
# Remove Quartus artifacts
Remove-Item db, incremental_db -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item *.rpt, *.rpt.htm, *.sof, *.pof, *.jdi, *.smsg, *.done, *.eqn* -Force -ErrorAction SilentlyContinue
Remove-Item *.map.summary, *.fit.summary, *.sta.summary, *.sld, *_assignment_defaults.qdf -Force -ErrorAction SilentlyContinue

# Remove ModelSim artifacts
Remove-Item work, sim/work, transcript -Recurse -Force -ErrorAction SilentlyContinue
```

All build artifacts are git-ignored; they'll regenerate cleanly on the next build.
