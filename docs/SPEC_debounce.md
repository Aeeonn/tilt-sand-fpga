# SPEC: debounce

## Purpose

Synchronize an asynchronous board-level input (e.g. `KEY[0]`) into `clk`'s domain and
suppress mechanical bounce, producing a clean level output.

## Interface

| Port     | Dir | Width | Description                          |
|----------|-----|-------|----------------------------------------|
| `clk`    | in  | 1     | destination clock                       |
| `rst_n`  | in  | 1     | synchronous active-low reset            |
| `in_raw` | in  | 1     | raw async input, any polarity           |
| `out`    | out | 1     | debounced, synchronized output, same polarity as `in_raw` |

Parameters:
- `CLK_FREQ_HZ` (default 100_000_000) — clock frequency, used to size the debounce
  counter.
- `DEBOUNCE_MS` (default 10) — required stable time before `out` follows `in_raw`.

`COUNT_MAX = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS` clock cycles.

Polarity-agnostic by design: top-level decides whether `KEY[i]` (active-low) is
inverted before or after this module.

## Behavior

1. `in_raw` passes through a 2-FF synchronizer -> `in_sync`.
2. A saturating counter increments while `in_sync != out`, and resets to 0 whenever
   `in_sync == out`.
3. When the counter reaches `COUNT_MAX`, `out <= in_sync` and the counter resets to 0.

Net effect: `out` follows `in_sync` only after `in_sync` has differed from `out` for
`COUNT_MAX` consecutive cycles. Starting from a settled state (counter==0), a clean,
held input change reaches `out` after exactly `COUNT_MAX + 3` cycles (2 cycles for the
synchronizer to settle to the new value + `COUNT_MAX` increments + 1 commit cycle).
Bounces shorter than that never move `out`.

## Edge cases

- Reset clears the synchronizer, counter, and `out` to 0 — if `in_raw`'s idle level is
  not 0, `out` will report the wrong level until the first debounce period elapses
  after reset. Acceptable for buttons (idle = released = whatever `KEY` reads when not
  pressed feeds in already inverted/not by the caller).
- Repeated short bounces around the current `out` value never accumulate — the counter
  resets every time `in_sync` matches `out`, regardless of how it got there.
