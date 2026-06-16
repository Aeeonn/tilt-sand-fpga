# SPEC: reset_sync

## Purpose

Convert an asynchronous, possibly glitchy reset source into a synchronous-release,
active-low reset (`rst_n`) for one clock domain, avoiding recovery/removal violations
on downstream registers' reset inputs.

## Interface

| Port     | Dir | Width | Description                  |
|----------|-----|-------|-------------------------------|
| `clk`    | in  | 1     | destination clock              |
| `arst_n` | in  | 1     | async reset source, active-low |
| `rst_n`  | out | 1     | synchronized reset, active-low |

Parameter `STAGES` (default 2, must be >= 2): number of synchronizer flip-flops.

## Behavior

- `arst_n` low (at any time, async): `rst_n` goes low immediately (same delta-cycle).
- `arst_n` high: `rst_n` rises STAGES clock cycles after release — stays low for the
  first STAGES-1 cycles, then rises on the STAGES-th posedge.
- Implementation: STAGES-bit shift register with async clear, shifting in 1'b1.

## Edge cases

- Metastability on the first stage after `arst_n` release is the reason for the 2+
  stage chain; STAGES=2 is the minimum safe value for this device/speed grade.
- `arst_n` glitching low again mid-release re-clears the whole chain immediately.

## SDC implications

The raw async reset source pin needs `set_false_path -from <pin>` to this module's
first flip-flop, since that path is not meant to meet setup/hold relative to `clk`.

## One instance per clock domain

Each clock domain that needs a synchronized reset gets its own `reset_sync` instance
fed by the same `arst_n` source — do not share one synchronizer's output across domains.
