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
| 1 | WALL | 3 (max) | Immovable; nothing can displace it |
| 2 | SAND | 2 | Granular: falls, sinks through water, slides diagonally to pile |
| 3 | WATER | 1 | Fluid: falls, flows diagonally, levels horizontally |
| 4–15 | (various) | 2 | Granular solids — same physics as SAND |

## Rules (gravity = DOWN, canonical orientation)

All rules are **permutations** of the input multiset — no creation or destruction.
The four phases run sequentially on the canonical-DOWN block (a=TL b=TR c=BL d=BR).

### Phase 1: Vertical fall

A heavier cell sinks below a lighter one in the same column. Density ordering:
EMPTY(0) < WATER(1) < SAND/others(2) < WALL(3). WALL has max density so nothing
displaces it via the swap (this is what keeps walls immovable).

- SAND (and materials 4–15) fall into EMPTY or WATER.
- WATER falls into EMPTY.
- Both columns evaluated independently.

### Phase 2: Water diagonal flow

A top-row WATER cell blocked straight down (cell below not EMPTY) drains into an
EMPTY diagonal cell. This lets water flow around obstacles instead of getting
stuck on ledges.

### Phase 3: Water horizontal level

WATER spreads into an adjacent EMPTY cell in the same row, **rnd-biased per row**
(left-flow when rnd=1, right-flow when rnd=0). The directional bias makes net
flow alternate and converge to a flat surface instead of sloshing forever — this
is what fixed the "water hump / mixing" behaviour.

### Phase 4: Granular diagonal slide

A granular cell (SAND or 4–15) blocked by a solid below (not EMPTY, not WATER)
slides into an EMPTY diagonal — **probabilistic** (gated by rnd). Making the slide
probabilistic rather than greedy steepens the angle of repose so piles form proper
pyramids instead of spreading flat.

### Walls

WALL never moves (max density, and the granular/fluid rules exclude it as a source).

## Pipeline split (for timing)

The four phases are a deep combinational chain. They are split into two
sub-modules so `margolus_engine` can register a midpoint and evaluate them across
two clock cycles (closes timing at 100 MHz):

- `block_rule_fall`   — phases 1–2 (fall + water diagonal), no `rnd`.
- `block_rule_settle` — phases 3–4 (water level + sand diagonal), uses `rnd`.

`block_rule` itself is a thin combinational wrapper that rotates to canonical
DOWN, chains both stages, and rotates back — the reference for `tb_block_rule`
and the match target for `sim/golden/block_rule.py`.

## Conservation property (critical invariant)

The multiset `{n00, n01, n10, n11}` must equal `{c00, c01, c10, c11}` — a pure
permutation for all current materials (no reactions yet). The testbench checks
this exhaustively, and `margolus_engine` preserves it structurally.

## Verification

- `tb_block_rule`: exhaustive test of all 4^4 = 256 material combinations ×
  4 gravity dirs × 2 rnd values = **2048** cases. Each case checks conservation
  (multiset equality) and correctness vs the Python golden.
- Python golden: `sim/golden/block_rule.py` implements the same four-phase logic
  in one function; the TB compares RTL (wrapper of both stages) against it.
