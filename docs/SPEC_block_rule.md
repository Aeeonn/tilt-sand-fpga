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
The three phases run sequentially on the canonical-DOWN block (a=TL b=TR c=BL d=BR).

### Phase 1: Vertical fall

A heavier cell sinks below a lighter one in the same column. Density ordering:
EMPTY(0) < WATER(1) < SAND/others(2) < WALL(3). WALL has max density so nothing
displaces it via the swap (this is what keeps walls immovable).

- SAND (and materials 4–15) fall into EMPTY or WATER.
- WATER falls into EMPTY.
- Both columns evaluated independently.

### Phase 2: Diagonal flow (greedy, any mobile cell)

Any mobile cell (not EMPTY, not WALL) still in the top row after phase 1 is
blocked straight down (cell below not EMPTY — otherwise it would have fallen),
so it slides into an EMPTY diagonal cell in the bottom row. This is **greedy**
(not gated by rnd) so material spreads as fast as it falls:

- Granular materials reach a natural ~45° angle of repose → proper pyramids.
- Water drains around obstacles and spreads outward.

`rnd` only breaks the left/right tie when *both* diagonals are open.

### Phase 3: Water horizontal level (throttled by `rnd`)

WATER swaps into an adjacent EMPTY cell in the same row (each row
independently), but **only when `rnd` is set** (~half the time). Throttling
sideways flow to ~half rate while the vertical fall runs every step makes
falling outpace spreading, so a falling body stays cohesive instead of
dispersing into a half-density "gas". On the floor the random gating produces
chaotic sloshing that still settles to a flat surface.

### Walls

WALL never moves (max density, and the mobile-cell checks exclude it as a source).

### Design note (greedy diagonal, throttled level)

An earlier revision gated the **diagonal** slide on `rnd` to steepen sand piles.
On hardware this throttled granular/water lateral flow far too hard: water
formed a slow bell-curve hump (minutes to level) and sand built tall narrow
towers. The diagonal flow is now **greedy** (every blocked cell slides every
step) → natural ~45° sand pyramids and fast drainage.

The **horizontal water level** (phase 3) is instead throttled on `rnd`. Greedy
leveling flattened water but dispersed a *falling* blob into a half-density gas
(it spread sideways as fast as it fell, and swapped water↔empty on already-flat
water every phase). Throttling only the level step lets the unthrottled fall
win the race: the blob falls cohesively, then the random gating makes the body
slosh chaotically before settling flat — closer to real liquid motion.

## Pipeline split (for timing)

The phases are a deep combinational chain. They are split into two sub-modules
so `margolus_engine` can register a midpoint and evaluate them across two clock
cycles (closes timing at 100 MHz):

- `block_rule_fall`   — phases 1–2 (vertical fall + greedy diagonal flow),
                        uses `rnd` for the left/right tie-break.
- `block_rule_settle` — phase 3 (throttled water horizontal level), uses the
                        same `rnd` bit as the gate.

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
- Python golden: `sim/golden/block_rule.py` implements the same three-phase
  logic in one function; the TB compares RTL (wrapper of both stages) against it.
