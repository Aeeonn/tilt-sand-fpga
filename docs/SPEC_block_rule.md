# SPEC: block_rule — Margolus 2×2 block physics (combinational)

## Purpose

Pure combinational function: given a 2×2 block of four cells, the current
gravity direction, and a random bit for tie-breaking, produce the updated
four cells after one CA step. This is the physics core of the falling-sand
engine.

## Interface

```systemverilog
module block_rule #(
    parameter int CELL_BITS = 4
) (
    input  logic [1:0]           grav_dir,   // 0=DOWN 1=UP 2=LEFT 3=RIGHT
    input  logic                 rnd,        // tie-break bit from lfsr
    input  logic [CELL_BITS-1:0] c00, c01,   // top-left, top-right   (row 0)
                                 c10, c11,   // bottom-left, bot-right (row 1)
    output logic [CELL_BITS-1:0] n00, n01,   // updated block
                                 n10, n11
);
```

### Cell layout (gravity = DOWN)

```
 c00 | c01       row 0 (top)
 ----+----
 c10 | c11       row 1 (bottom)
```

Gravity DOWN means material falls from row 0 to row 1.

### Gravity directions

| grav_dir | Meaning | "Down" in block coordinates |
|----------|---------|---------------------------|
| 2'd0 | DOWN | row 0 → row 1 |
| 2'd1 | UP | row 1 → row 0 |
| 2'd2 | LEFT | col 1 → col 0 |
| 2'd3 | RIGHT | col 0 → col 1 |

Implementation: rotate the input block so the gravity direction maps to the
canonical DOWN orientation, apply the DOWN rule, then rotate the result back.

## Materials

| ID | Name | Density | Behavior |
|----|------|---------|----------|
| 0 | EMPTY | 0 | Vacuum; anything falls into it |
| 1 | WALL | — | Immovable; never participates in swaps |
| 2 | SAND | 2 | Granular: falls, flows diagonally, sinks through water |
| 3 | WATER | 1 | Fluid: falls, flows diagonally, spreads laterally |
| 4–15 | (various) | 2 | Granular solids — same physics as SAND |

## Rules (gravity = DOWN, canonical orientation)

All rules are **permutations** of the input multiset — no creation or destruction.

### Phase 1: Vertical fall

A heavier cell in row 0 displaces a lighter cell directly below (same column,
row 1). Density ordering: EMPTY(0) < WATER(1) < SAND/others(2). WALL is immovable.

- SAND (and materials 4–15) fall into EMPTY or WATER.
- WATER falls into EMPTY.
- Both columns are evaluated independently.

### Phase 2: Diagonal flow (any mobile cell)

If a mobile cell (not EMPTY, not WALL) is still in row 0 after phase 1, it is
blocked straight down (the cell below is not EMPTY — otherwise it would have
fallen). It flows into the diagonal cell in row 1 (opposite column) if that
cell is EMPTY.

This makes granular materials pile at an angle of repose, and crucially lets
WATER drain around obstacles instead of getting stuck on sand ledges. If both
diagonals are open, `rnd` picks left vs right.

### Phase 3: Lateral spread (fluid — WATER only)

WATER in row 0 spreads sideways to an adjacent EMPTY cell in the same row when
blocked below. WATER in row 1 spreads sideways unconditionally. `rnd` breaks
symmetric ties. This gives water a flat surface (sand piles, water levels out).

### Walls

WALL cells never move. No swap involves a WALL as source or destination.

### Identity

If no rule applies, output = input (block is unchanged).

## Conservation property (critical invariant)

The multiset `{n00, n01, n10, n11}` must equal `{c00, c01, c10, c11}` — a pure
permutation for all current materials (no reactions yet). The testbench checks
this exhaustively, and `margolus_engine` preserves it structurally.

## Verification

- `tb_block_rule`: exhaustive test of all 4^4 = 256 material combinations ×
  4 gravity dirs × 2 rnd values = **2048** cases. Each case checks conservation
  (multiset equality) and correctness vs the Python golden.
- Python golden: `sim/golden/block_rule.py` implements the same three-phase
  logic; the TB compares RTL output against it for every case.
