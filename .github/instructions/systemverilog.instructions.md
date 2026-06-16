---
description: "Use when editing or creating SystemVerilog RTL or testbench files. Enforces synthesizable-subset rules for RTL modules, naming conventions, reset/clock standards, and Q-format annotation for the DE10-Lite MAX 10 project."
applyTo: "**/*.sv"
---

# SystemVerilog Conventions

## RTL (non-testbench) modules

- Use only the synthesizable subset: `always_ff`, `always_comb`, `logic`, packed arrays, enums, `parameter` / `localparam`.
- **No `always_latch`** — latches are never intentional. If synthesis infers a latch, it is a bug.
- Avoid `initial` blocks in general RTL control/datapath logic.
- `initial` blocks are allowed in synthesizable ROM/RAM/table modules only for `$readmemh` / `$readmemb` initialization, when already consistent with the project’s Questa/Quartus flow.
- Do not add simulation-only `initial` behavior to synthesizable logic.
- **No `#delay`** in RTL — delays are for testbenches only.
- Declare all signals as `logic`; avoid `wire` / `reg`.

## Clocks and resets

- Name clocks explicitly: `clk_100`, `clk_25`, `clk_pixel`, etc.
- Reset is **active-low**, named `rst_n`.
- Reset strategy: **async assert, sync deassert** via `reset_sync` module.
- Every `always_ff` block that uses reset must follow this pattern:
  ```systemverilog
  always_ff @(posedge clk or negedge rst_n)
      if (!rst_n) begin
          // reset values
      end else begin
          // clocked logic
      end
  ```
- Not every register requires reset. Reset only architecturally visible state, FSM state, valid flags, counters, and control registers. Pure datapath pipelines may be resetless if the valid protocol makes startup state irrelevant.


## Naming

- Modules: `snake_case` (e.g., `vga_timing`, `async_fifo`).
- Signals: `snake_case`.
- Parameters / localparams: `UPPER_SNAKE_CASE`.
- FSM enum types use `_e` suffix, e.g. `state_e`.
- FSM state values use `S_` prefix, e.g. `S_IDLE`, `S_READ`.
- Enum values: `UPPER_SNAKE_CASE` (e.g., `S_IDLE`, `S_READ`).

## Fixed-point arithmetic

- Every fixed-point signal must have a Q-format comment on its declaration:
  ```systemverilog
  logic signed [15:0] pos_x;  // Q8.8
  ```
- When two different Q-formats interact, add a comment explaining the alignment or rounding.

## Ports and interfaces

- Use `input logic` / `output logic` — never bare `input` / `output`.
- Group ports: clocks/resets first, then control, then data.
- Document port purpose with inline comments for non-obvious signals.

## File organization

- One module per `.sv` file. Filename must match module name.
- Testbenches use a `tb_` prefix: `tb_vga_timing.sv`.
- Testbenches are **never** added to the Quartus `.qsf` file list.

## Quartus / synthesis awareness

- Avoid constructs that Quartus Prime Lite 23.1 may not support (e.g., `unique case` may warn; prefer `case ... default`).
- Do not blindly force memories to M9K.
- Preserve documented memory attributes.
- Critical known case: `async_fifo` memory must remain `(* ramstyle = "logic" *)` to preserve FWFT read behavior.
- For ROM/RAM inference changes, check `docs/CONVENTIONS.md`, relevant `SPEC_*.md`, simulation behavior, and Quartus reports.
- Be aware that `$readmemh` behavior may differ between Questa and Quartus — always test both.

## CDC (clock-domain crossings)

- Never pass multi-bit signals across clock domains without a synchronizer or async FIFO.
- Single-bit CDC must use a double-flop synchronizer.
- Document every CDC path with a comment: `// CDC: clk_100 → clk_25`.

## Testbenches

- Must be **self-checking** with explicit PASS/FAIL counts.
- Each testbench must print PASS/FAIL per check and a final summary line:
  `TB <module>: N/N PASS`
  or an explicit `*** FAIL ***` / nonzero failure count.
- Each testbench must have a corresponding Questa do-script under `sim/scripts/`.
- Use `timescale 1ns/1ps`.
