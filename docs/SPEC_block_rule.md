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

## M3 materials (MVP)

| ID | Name | Density | Behavior |
|----|------|---------|----------|
| 0 | EMPTY | 0 | Vacuum; anything falls into it |
| 1 | WALL | ∞ | Immovable; never participates in swaps |
| 2 | SAND | 2 | Falls straight down; slides diagonally if blocked below |

## Rules (gravity = DOWN, canonical orientation)

All rules are **permutations** of the input multiset — no creation or destruction.

### Rule 1: Vertical fall

If a cell in row 0 is SAND and the cell directly below (same column, row 1) is
EMPTY, swap them.

```
 SAND | ?       →    EMPTY | ?
 -----+----          ------+----
 EMPTY| ?            SAND  | ?
```

(Same for the right column independently.)

### Rule 2: Diagonal slide

If SAND is in row 0, the cell directly below is occupied (SAND or WALL), but the
diagonal cell in row 1 (opposite column) is EMPTY, the sand slides diagonally.

If both diagonals are open, `rnd` picks left vs right. If only one is open,
take it. This is the only non-deterministic step.

### Rule 3: Walls

WALL cells never move. If WALL is in the "destination" position, no swap occurs.

### Rule 4: Identity

If no rule applies, output = input (block is unchanged).

### Priority

1. Vertical fall (both columns independently).
2. Diagonal slide (only for cells still in row 0 after step 1).

This two-phase evaluation within the combinational block prevents conflicts.

## Conservation property (critical invariant)

For M3 (EMPTY/WALL/SAND only): the multiset `{n00, n01, n10, n11}` must equal
`{c00, c01, c10, c11}` — a pure permutation. The testbench checks this
exhaustively, and `margolus_engine` carries an SVA for it across full frames.

## Verification

- `tb_block_rule`: exhaustive test of all 3^4 = 81 material combinations ×
  4 gravity dirs × 2 rnd values = 648 cases (small enough to enumerate fully).
  Each case checks conservation (multiset equality) and correctness vs the
  Python golden.
- Python golden: `sim/golden/block_rule.py` implements the same two-phase
  logic; the TB compares RTL output against it for every case.
