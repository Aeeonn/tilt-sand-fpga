# AGENTS.md

This is a real FPGA/SystemVerilog repository for the Terasic DE10-Lite / Intel MAX 10. Treat it as hardware engineering, not generic software.

## Read first

Before meaningful work, inspect:

- `docs/CONVENTIONS.md`
- `docs/STATUS.md`
- relevant `docs/SPEC_*.md`
- relevant RTL under `rtl/`
- relevant testbenches under `sim/tb/`
- relevant Questa scripts under `sim/scripts/`
- `.qsf` / `.sdc` if synthesis, top-level ports, clocks, pins, memory, or constraints are involved

If the user prompt conflicts with the repo state, report the discrepancy and ask before editing.

## Core rules

- Do not rush into edits.
- Ask before architecture changes, file cleanup, renames, deletes, top-level port changes, pin changes, clock/CDC changes, SDRAM/VGA timing changes, or project direction changes.
- Preserve verified RTL unless there is a documented reason to change it.
- Keep edits minimal and localized.
- No “looks right” verification.
- Do not claim hardware confirmation unless the board was actually tested.
- If verification was not run, say so clearly.

## Verification contract

No nontrivial RTL work is complete without:

1. Relevant spec/doc update when behavior or interface changes.
2. Python golden model when the behavior is computational.
3. Self-checking SystemVerilog testbench.
4. Questa do-script.
5. Relevant simulation PASS counts.
6. Quartus map/fit/STA for top-level or synthesizable integration changes.
7. `docs/STATUS.md` update after a meaningful successful Quartus compile.

## Project conventions

- SystemVerilog `.sv` for RTL and testbenches.
- RTL uses synthesizable subset: `always_ff`, `always_comb`, `logic`, packed arrays, enums, `parameter` / `localparam`.
- No intentional latches.
- `.qsf` contains synthesizable RTL only.
- Testbenches are not added to Quartus.
- Reset is active-low `rst_n`.
- Clock names are explicit, e.g. `clk_100`, `clk_25`.
- Fixed-point signals require Q-format comments.
- Follow `docs/CONVENTIONS.md` if any rule here is ambiguous.

## Known caution zones

Be extra careful with:

- VGA timing
- `clk_100` to `clk_25` CDC
- `async_fifo` FWFT behavior and `ramstyle = "logic"`
- SDRAM burst/page boundaries
- PLL/generated-clock constraints
- `.qsf` pin assignments
- `$readmemh` and ROM/RAM inference differences between Questa and Quartus
- fixed-point Q-format changes
- raycast/sprite/painter timing-critical multiply paths
- any change that may reduce `clk_100` timing margin

## Current-project warning

The repository may contain advanced MAXenstein/raycast work even if the folder/project name suggests `sand_falling`.

Do not delete or replace existing work based only on the folder name. First inspect `docs/STATUS.md`, the `.qpf` / `.qsf`, and the RTL tree. If the user wants to pivot to TILT-SAND, propose a fork/migration plan and ask before cleanup.
