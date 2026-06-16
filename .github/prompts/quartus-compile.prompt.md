---
description: "Run a full Quartus Prime Lite compile (map → fit → assembler → STA) and parse the reports for resource usage, timing closure, and critical warnings."
agent: "FPGA HDL Steward"
tools: [execute, read, search]
argument-hint: "Optional: specific flow steps or extra Quartus args"
---

# Quartus Full Compile & Report

Run a complete Quartus Prime Lite compilation flow for the `sand_falling` project and summarize the results. First discover the active Quartus project by locating the `.qpf` / `.qsf` in the repository root. If more than one plausible project exists, stop and ask which one to compile.


## Steps

1. **Locate the Quartus installation** — check for `quartus_sh` in the system PATH or common install paths (`C:\intelFPGA_lite\*\quartus\bin64\`).

2. **Run the compilation flow** in order:
   ```
   quartus_map sand_falling
   quartus_fit sand_falling
   quartus_asm sand_falling
   quartus_sta sand_falling
   ```
   Run from the project root directory (`[the folder containing sand_falling.qpf](sand_falling.qpf)`).

3. **Parse the reports** and extract:

   ### Resource usage (from `sand_falling.fit.summary` or `sand_falling.fit.rpt`)
   - Total logic elements used / available
   - Total registers
   - Total memory bits (M9K)
   - Total PLLs
   - Total pins used / available

   ### Timing (from `sand_falling.sta.summary` or `sand_falling.sta.rpt`)
   - Worst-case setup slack for each clock domain
   - Whether timing is **MET** or **VIOLATED** for each clock
   - Worst failing path endpoint if slack is negative

   ### Critical warnings (from `sand_falling.fit.rpt` and `sand_falling.map.rpt`)
   - Any critical warnings (filter out routine info messages)
   - Latch inference warnings (these are bugs — flag them prominently)
   - Unconstrained clock warnings

4. **Present a summary table** like:

   | Metric | Value |
   |--------|-------|
   | Logic Elements | X / 49,760 |
   | Registers | X |
   | M9K Memory Bits | X / 1,677,312 |
   | PLLs | X / 4 |
   | Pins | X / 360 |
   | clk_100 Setup Slack | +X.XX ns (MET / VIOLATED) |
   | clk_25 Setup Slack | +X.XX ns (MET / VIOLATED) |
   | Critical Warnings | X |

5. If the compile corresponds to a milestone or user-requested baseline, update `docs/STATUS.md`. Otherwise, report the numbers and ask before editing status.

6. **Flag any issues** that need attention: timing violations, latch warnings, resource pressure, missing constraints.
