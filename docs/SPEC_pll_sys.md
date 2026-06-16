# SPEC: pll_sys

System PLL: a hand-instantiated `altpll` megafunction (from `altera_mf`) that
derives the M0 clock domains from the board's 50 MHz `MAX10_CLK1_50`
reference. See `docs/CONVENTIONS.md` "Clock domains (M0)" for the target
frequency table this implements.

## Interface

| Signal          | Dir | Width | Description |
|-----------------|-----|-------|-------------|
| `inclk0`        | in  | 1     | 50 MHz reference clock (`MAX10_CLK1_50`) |
| `arst`          | in  | 1     | Asynchronous reset, **active high** (ALTPLL `areset` convention) |
| `clk_100`       | out | 1     | c0: 100 MHz, 0 deg - system domain |
| `clk_100_shift` | out | 1     | c1: 100 MHz, -3 ns - reserved (M1), see CONVENTIONS.md |
| `clk_25`        | out | 1     | c2: 25 MHz, 0 deg - VGA pixel domain |
| `locked`        | out | 1     | High once the PLL has locked to `inclk0` |

`arst` is **active-high**, the opposite polarity of this project's `rst_n`
convention, because it connects directly to ALTPLL's `areset` port. `top.sv`
derives it from the board's active-low `KEY[0]` (`arst = ~KEY[0]`), and
combines `~KEY[0]` with `~locked` to drive the `arst_n` input of each domain's
`reset_sync`.

## ALTPLL configuration

`operation_mode = "NORMAL"`, internal feedback, `intended_device_family =
"MAX 10"`, `inclk0_input_frequency = 20000` (ps, i.e. the 50 MHz input
period). Per-output counters:

| Output | multiply | divide | phase_shift | Result |
|--------|----------|--------|-------------|--------|
| c0 (`clk_100`)       | 2 | 1 | 0 ps     | 100 MHz, 0 deg |
| c1 (`clk_100_shift`) | 2 | 1 | -3000 ps | 100 MHz, -3 ns |
| c2 (`clk_25`)        | 1 | 2 | 0 ps     | 25 MHz, 0 deg |

All other ALTPLL control inputs (`pllena`, `pfdena`, `clkena`, `extclkena`,
scan chain, dynamic phase/reconfig ports, `clkswitch`, `fbin`) are tied off to
their inactive/always-enabled values; this design uses none of those features.

## Behavior

- While `arst` is asserted, `locked` is low and the `clk_*` outputs are not a
  reliable clock.
- After `arst` deasserts (with `inclk0` running), `locked` rises once the PLL
  acquires lock. M0 places no fixed-cycle-count bound on this latency -
  downstream logic must wait for `locked`, not assume a specific delay.
- Once locked, `clk_100` and `clk_100_shift` are both 100 MHz (10000 ps
  period); `clk_25` is 25 MHz (40000 ps period). `clk_100_shift`'s rising
  edges follow `clk_100`'s corresponding edges by 7000 ps (`= (-3000 ps) mod
  10000 ps`), consistent with the configured -3 ns phase shift.
- `clk_100_shift` (c1) is unused by any other M0 module; it exists so the
  frequency/phase relationship is established and verified ahead of M1.

## Verification

`sim/golden/pll_sys.py` independently derives, from the target
frequency/phase table above (via exact `Fraction` arithmetic, *not* by
reading the RTL's ALTPLL parameters), the expected `clk_100` /
`clk_100_shift` / `clk_25` periods and the `clk_100_shift`-vs-`clk_100`
relative phase, and writes `sim/golden/pll_sys_consts.svh`.

`sim/tb/tb_pll_sys.sv` instantiates `pll_sys`, drives `inclk0` with a
free-running 50 MHz clock, asserts then releases `arst`, waits for `locked`
(a timeout is a FAIL, not a hang), and then:
- measures several periods of each `clk_*` output and compares against the
  generated constants;
- measures the `clk_100_shift`-vs-`clk_100` relative phase (mod the c0
  period) and compares against `` `PLL_C1_REL_PHASE_PS ``;
- checks `locked` is still high after the measurement window (no glitch).

This is a **functional** simulation of the `altpll` megafunction (via the
`altera_mf_ver` precompiled library bundled with Questa); it does not model
real silicon lock time or jitter. Real-hardware feasibility of this PLL
configuration (legal M/N/phase combination for the MAX 10 PLL hardware) is
confirmed separately by the Quartus fit/STA run.

`vsim` reports ~18 `vopt-2718`/`TFMPC` "missing connection" warnings for
`pll_inst` - these are optional `altpll` ports (scan chain, LVDS, dynamic
phase/reconfig, `extclk`, etc.) that this configuration doesn't use and are
intentionally left unconnected via named port connection. Expected, not a
defect.
