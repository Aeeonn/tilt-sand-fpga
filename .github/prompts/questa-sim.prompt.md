---
description: "Run a Questa Intel FPGA simulation for a specific testbench and parse the PASS/FAIL results. Use when: running RTL unit tests, debugging a failing testbench, checking simulation transcript."
agent: "FPGA HDL Steward"
tools: [execute, read, search]
argument-hint: "Testbench module name (e.g. tb_vga_timing) — omit tb_ prefix if you prefer"
---

# Questa Simulation — Run & Report

Run a Questa Intel FPGA Starter Edition simulation for the specified testbench and report PASS/FAIL results.

## Steps

1. **Resolve the testbench name** — accept either `tb_foo` or `foo`; always look for `tb_<name>.sv`.

2. **Locate the do-script** — find `sim/scripts/do_<name>.do` or `sim/scripts/tb_<name>.do`. If no script exists, stop and ask before improvising a compile/simulate sequence.

3. **Locate the Questa installation** — check for `vsim` / `vlog` in PATH or common install paths:
   - `C:\intelFPGA_lite\*\questa_fse\win64\`
   - `C:\intelFPGA_lite\*\modelsim_ase\win64\`

4. **Run the simulation** from the project root:
   ```
   vsim -c -do "sim/scripts/do_<name>.do"
   ```
   Use `-c` (command-line / no GUI) unless the user explicitly asks for the waveform GUI.

5. **Parse the transcript** (`transcript` in the project root) for:
   - Lines matching `PASS` / `FAIL` / `ERROR` (case-insensitive)
   - The final summary line: `TB <module>: N/N PASS` or `*** FAIL ***`
   - Any `$fatal`, `$error`, or assertion failures
   - Simulation time at finish

6. **Present a result block**:

   ```
   Testbench : tb_<name>
   Do-script : sim/scripts/do_<name>.do
   Result    : PASS  (or FAIL — N failures)
   Sim time  : X ns
   ```

   If there are failures, list each one with its line/message from the transcript.

7. **On failure**:
   - Show the failing check(s) and the mismatch (expected vs actual)
   - Identify the likely RTL source location
   - Propose a minimal fix candidate — do NOT implement it without user confirmation

8. **Do not edit RTL** as part of this prompt. Report only. If a fix is warranted, the user should invoke the FPGA HDL Steward agent for implementation.
