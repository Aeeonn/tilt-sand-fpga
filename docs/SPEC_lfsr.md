# SPEC: lfsr — 16-bit Galois LFSR PRNG

## Purpose

Provides pseudo-random bits for tie-breaking in `block_rule`. When two
symmetric moves are equally valid (e.g. sand with both diagonals open),
`rnd[0]` picks one so piles look natural rather than biased.

## Interface

```systemverilog
module lfsr #(
    parameter int WIDTH = 16,
    parameter logic [WIDTH-1:0] SEED = 16'hACE1
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             en,      // advance one step
    output logic [WIDTH-1:0] rnd      // current state (all bits usable)
);
```

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | System clock (`clk_100`) |
| rst_n | in | 1 | Active-low reset |
| en | in | 1 | Advance the LFSR one step when high |
| rnd | out | WIDTH | Current LFSR state; consumer uses any bit(s) |

## Behavior

- **Polynomial**: Galois LFSR, taps for 16 bits: `x^16 + x^14 + x^13 + x^11 + 1`
  (maximal-length, period 2^16 - 1 = 65535).
- On reset, `rnd <= SEED` (nonzero — the all-zero state is a fixed point of any
  LFSR and must be avoided).
- When `en` is high, the state advances one step per clock.
- When `en` is low, `rnd` holds its value.
- `margolus_engine` pulses `en` once per block evaluation, so the LFSR advances
  once per 2×2 block.

## Implementation notes

Galois form (XOR on feedback, not on tap chain) is cheaper in LEs and has
no combinational depth through the whole register. The taps are:
`if (rnd[0]) rnd <= (rnd >> 1) ^ 16'hB400;` else `rnd <= rnd >> 1;`

(16'hB400 = bits 15,13,12,10 set = the reflection of `x^16+x^14+x^13+x^11+1`.)

## Verification

- `tb_lfsr`: confirm period = 65535 (cycles back to seed after exactly 2^16-1
  steps), confirm no stuck-at-zero, confirm `en=0` holds state.
