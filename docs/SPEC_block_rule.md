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
| 3 | WATER | 1 | Fluid, **still** (no horizontal momentum) |
| 4 | WATER_R | 1 | Water carrying **+x** (canonical-right) momentum |
| 5 | WATER_L | 1 | Water carrying **−x** (canonical-left) momentum |
| 6–15 | (reserved) | 2 | Granular solids — same physics as SAND |

The three water IDs form one **water family**: all render the same blue, all
have density 1, and they interconvert freely (a still cell gains a tag when it
starts moving, sheds it when it stops or moves vertically). The momentum tag
lets water **slosh** — waves that overshoot equilibrium and decay — and **rise**
in communicating vessels, which a memoryless relaxation rule cannot do.

## Rules (gravity = DOWN, canonical orientation)

All rules conserve the **grouped** material multiset (see Conservation below).
Six phases run sequentially on the canonical-DOWN block (a=TL b=TR c=BL d=BR),
split across three pipeline sub-modules. Two random bits are used: `r0` (= rnd
bit 0) and `r1` (= rnd bit 1).

### Phase 1: Vertical fall (block_rule_fall)

A heavier cell sinks below a lighter one in the same column. Density ordering:
EMPTY(0) < water family(1) < SAND/others(2) < WALL(3). A water cell that moves
vertically **sheds its momentum tag** (becomes still WATER) — vertical motion is
independent of horizontal velocity.

### Phase 2: Diagonal flow — GRANULAR ONLY (block_rule_fall)

Any *granular* mobile cell (SAND / 6–15, **not** water) blocked straight down
slides into an EMPTY diagonal cell, giving ~45° pyramids. Water is **excluded**
here so its horizontal momentum is not dissipated diagonally; water spreads via
the momentum phases instead. `r0` breaks the left/right tie when both open.

### Phase 3: Rise (block_rule_flow)

Moving water blocked horizontally with EMPTY above climbs into that cell and
**reverses** direction. Within a block `a` is above `c` and `b` is above `d`, so
this redirects blocked horizontal momentum **upward**: water piles against
barriers (the overshoot crest) and rises in communicating vessels.

### Phase 4: Advection (block_rule_flow)

Tagged water glides one cell in its travel direction into an EMPTY neighbour,
keeping its velocity (ballistic → carries past equilibrium). Reflection off a
barrier is **lossy**: it reverses on `r0`, otherwise damps to still. Two opposing
flows (WATER_R next to WATER_L) cancel to still. Energy is shed at crests/walls.

### Phase 5: Cohesive repack (block_rule_settle)

A still WATER cell with a **supported** EMPTY neighbour (the cell below the
destination is non-empty) flows in and gains that direction's momentum. This
keeps the body dense (water glides along surfaces as a sheet rather than
spraying into air) and is what seeds the sloshing motion.

### Phase 6: Damping (block_rule_settle)

A moving cell occasionally (`r0 & r1`, ~12.5%) loses its momentum tag, so the
waves decay over several swings and the surface eventually settles flat.

### Walls

WALL never moves (max density, and the mobile-cell checks exclude it as a source).

### Design note (why momentum)

The previous rule was a memoryless downhill relaxation: it could not overshoot
equilibrium (no waves) or move water upward (no level equalization in a U-tube).
Encoding a horizontal-velocity tag in two spare material IDs adds the missing
state. Phases 3–5 convert height into horizontal motion and back (the slosh),
phase 4's lossy reflection and phase 6's gentle damping bleed energy so the
waves decay, and excluding water from the granular diagonal (phase 2) preserves
its momentum. Tuned in `sim/golden/_tune_a.py` until the slosh showed several
decaying overshoots and the U-tube equalized, before porting to RTL.

## Pipeline split (for timing)

The six phases are a deep combinational chain, split into **three** sub-modules
so `margolus_engine` registers two midpoints and evaluates them across three
clock cycles (closes timing at 100 MHz):

- `block_rule_fall`   — phases 1–2 (vertical fall + granular diagonal), `r0`.
- `block_rule_flow`   — phases 3–4 (water rise + momentum advection), `r0`.
- `block_rule_settle` — phases 5–6 (cohesive repack + damping), `r0` & `r1`.

`block_rule` itself is a thin combinational wrapper that rotates to canonical
DOWN, chains all three stages, and rotates back — the reference for
`tb_block_rule` and the match target for `sim/golden/block_rule.py`. Velocity tag
*values* ride through the rotation unchanged, so water sloshes perpendicular to
whatever gravity is active.

## Conservation property (critical invariant)

Strict multiset equality no longer holds (a WATER may become WATER_R/WATER_L).
The invariant is **grouped**: with the water family {WATER, WATER_R, WATER_L}
folded into a single bucket, the multiset `{n00,n01,n10,n11}` equals
`{c00,c01,c10,c11}`. Every non-water material count is individually preserved and
the total water count is preserved. `tb_block_rule` checks this exhaustively and
`margolus_engine` preserves it structurally.

## Verification

- `tb_block_rule`: exhaustive test of all 6^4 = 1296 material combinations ×
  4 gravity dirs × 4 rnd values = **20736** cases. Each case checks grouped
  conservation (water family folded) and correctness vs the Python golden.
- `tb_water_momentum`: dynamic RTL check driving `margolus_engine` over a slosh
  scenario — grouped mass stays constant, momentum tags appear while sloshing,
  and tags decay to zero once settled.
- Python golden: `sim/golden/block_rule.py` implements the same six-phase logic
  (wrapper of all three stages); the TB compares RTL against it. The look was
  tuned in `sim/golden/_tune_a.py` before porting.
