#!/usr/bin/env python3
"""block_rule.py — golden model for the Margolus 2×2 block rule.

Pure-Python implementation of the block_rule combinational logic.
Same two-phase approach: vertical fall first, then diagonal slide.
Used by tb_block_rule (via generated vectors) and margolus_engine.py.

Materials: EMPTY=0, WALL=1, SAND=2, WATER=3.
Density ordering: EMPTY < WATER < SAND (WALL is immovable).
"""

# Material IDs (must match sand_materials.py)
EMPTY = 0
WALL  = 1
SAND  = 2
WATER = 3
WR    = 4   # water carrying +x (canonical-right) momentum
WL    = 5   # water carrying -x (canonical-left)  momentum

# Density: higher = heavier (sinks). WALL is max so nothing can displace it
# via the vertical-fall swap. EMPTY=0, WATER=1, SAND/others=2, WALL=3.
def _density(mat):
    if mat == EMPTY:
        return 0
    if mat == WATER or mat == WR or mat == WL:
        return 1
    if mat == WALL:
        return 3  # immovable: nothing is denser
    return 2  # granular solid


def _is_water(mat):
    """Any member of the water momentum family (still or moving)."""
    return mat == WATER or mat == WR or mat == WL


def _moving(mat):
    """Water that carries horizontal momentum."""
    return mat == WR or mat == WL

# Gravity directions
G_DOWN  = 0
G_UP    = 1
G_LEFT  = 2
G_RIGHT = 3


def _is_mobile(mat):
    """A material that is not WALL (used by _falls_into for src/dst checks)."""
    return mat != WALL


def _is_movable(mat):
    """A cell that can move on its own (everything except EMPTY and WALL)."""
    return mat != EMPTY and mat != WALL


def _is_granular(mat):
    """Granular solid — slides diagonally but does not spread like a fluid."""
    return mat != EMPTY and mat != WALL and mat != WATER


def _falls_into(src, dst):
    """src displaces dst vertically if src is heavier and dst is lighter.
    WALL never moves. EMPTY never falls."""
    if not _is_mobile(src) or not _is_mobile(dst):
        return False
    if src == EMPTY:
        return False
    return _density(src) > _density(dst)


def _rule_down(c00, c01, c10, c11, r0, r1):
    """Apply the block rule with gravity = DOWN (canonical orientation).

    Working cells a=TL b=TR c=BL d=BR. Water carries a horizontal-momentum tag
    (WATER still / WR right / WL left) so it sloshes (waves that overshoot and
    decay) and can rise in communicating vessels. Phases (each conserves the
    grouped material count — see check_conservation):

      1. Vertical fall   — heavier sinks by density; a water cell that moves
                           vertically sheds its tag (becomes still WATER).
      2. Diagonal flow   — GRANULAR ONLY: sand etc. blocked straight down slide
                           into an empty diagonal → ~45° pyramids. Water is
                           excluded so its momentum is not dissipated.
      3. Rise            — moving water blocked horizontally with empty above
                           climbs and REVERSES (pile-up → overshoot + rise).
      4. Advection       — tagged water glides one cell in its travel direction
                           into empty; reflection off a barrier is lossy
                           (reverses on r0, else damps to still); head-on
                           opposing flows damp to still.
      5. Repack          — a still water cell flows into a supported empty
                           neighbour, gaining that direction's momentum (keeps
                           the body dense and seeds the sloshing).
      6. Damp            — a moving cell occasionally (~12.5 %, r0&r1) loses its
                           momentum so waves decay over several swings.

    r0, r1 are two independent random bits (LFSR). Returns (n00,n01,n10,n11).
    """
    a, b, c, d = c00, c01, c10, c11

    # Phase 1: vertical fall by density; vertical motion sheds h-momentum.
    if _is_water(a) and _density(a) > _density(c):
        a, c = (WATER if _is_water(c) else c), WATER
    elif _is_movable(a) and _density(a) > _density(c):
        a, c = c, a
    if _is_water(b) and _density(b) > _density(d):
        b, d = (WATER if _is_water(d) else d), WATER
    elif _is_movable(b) and _density(b) > _density(d):
        b, d = d, b

    # Phase 2: greedy diagonal flow — GRANULAR ONLY (sand pyramids).
    la = _is_movable(a) and not _is_water(a) and c != EMPTY and d == EMPTY
    rb = _is_movable(b) and not _is_water(b) and d != EMPTY and c == EMPTY
    if la and rb:
        if r0:
            a, d = d, a
        else:
            b, c = c, b
    elif la:
        a, d = d, a
    elif rb:
        b, c = c, b

    # Phase 3: RISE — blocked moving water with empty above climbs, reversing.
    if a == EMPTY and c == WR and d != EMPTY:
        a, c = WL, EMPTY
    elif b == EMPTY and d == WL and c != EMPTY:
        b, d = WR, EMPTY

    # Phase 4: momentum advection with lossy reflection / head-on damping.
    a, b = _advect(a, b, r0)
    c, d = _advect(c, d, r0)

    # Phase 5: cohesive repack — still water flows into a supported empty,
    # gaining that direction's momentum.
    if a == WATER and b == EMPTY and d != EMPTY:
        a, b = EMPTY, WR
    elif b == WATER and a == EMPTY and c != EMPTY:
        a, b = WL, EMPTY
    if c == WATER and d == EMPTY:
        c, d = EMPTY, WR
    elif d == WATER and c == EMPTY:
        c, d = WL, EMPTY

    # Phase 6: gentle damping so waves lose energy over time.
    if _moving(a) and r0 and r1:
        a = WATER
    if _moving(d) and r0 and r1:
        d = WATER

    return a, b, c, d


def _advect(L, R, r0):
    """Horizontal momentum step for one left/right cell pair.

    Moving water glides into an empty neighbour keeping its velocity; a barrier
    reflects it (lossy: reverses on r0, else damps to still); two opposing
    flows cancel to still. Conserves the water-group count.
    """
    if L == WR and R == EMPTY:
        return EMPTY, WR
    if R == WL and L == EMPTY:
        return WL, EMPTY
    if L == WR and R != EMPTY and not _moving(R):
        L = WL if r0 else WATER
    if R == WL and L != EMPTY and not _moving(L):
        R = WR if r0 else WATER
    if L == WR and R == WL:
        return WATER, WATER
    return L, R


def _rotate_cw(c00, c01, c10, c11):
    """Rotate the block 90° clockwise."""
    return c10, c00, c11, c01


def _rotate_ccw(c00, c01, c10, c11):
    """Rotate the block 90° counter-clockwise."""
    return c01, c11, c00, c10


def _rotate_180(c00, c01, c10, c11):
    """Rotate the block 180°."""
    return c11, c10, c01, c00


def block_rule(c00, c01, c10, c11, grav_dir, rnd):
    """Apply the block rule for the given gravity direction.

    ``rnd`` is a 2-bit value (0..3); bit 0 = r0, bit 1 = r1. Velocity tags are
    stored in the canonical (perpendicular-to-gravity) frame: the block is
    rotated so gravity points DOWN, the rule runs, and the result is rotated
    back. Tag *values* ride through the rotation unchanged, so water sloshes
    perpendicular to whatever gravity is active. Returns (n00, n01, n10, n11).
    """
    r0 = rnd & 1
    r1 = (rnd >> 1) & 1
    if grav_dir == G_DOWN:
        return _rule_down(c00, c01, c10, c11, r0, r1)
    elif grav_dir == G_UP:
        # Rotate 180° so "up" becomes "down", apply, rotate back
        a, b, c, d = _rotate_180(c00, c01, c10, c11)
        a, b, c, d = _rule_down(a, b, c, d, r0, r1)
        return _rotate_180(a, b, c, d)
    elif grav_dir == G_LEFT:
        # Rotate CW so "left" becomes "down", apply, rotate back CCW
        a, b, c, d = _rotate_cw(c00, c01, c10, c11)
        a, b, c, d = _rule_down(a, b, c, d, r0, r1)
        return _rotate_ccw(a, b, c, d)
    elif grav_dir == G_RIGHT:
        # Rotate CCW so "right" becomes "down", apply, rotate back CW
        a, b, c, d = _rotate_ccw(c00, c01, c10, c11)
        a, b, c, d = _rule_down(a, b, c, d, r0, r1)
        return _rotate_cw(a, b, c, d)
    else:
        raise ValueError(f"invalid grav_dir {grav_dir}")


# Materials that all count as "water" for the grouped conservation invariant.
_WATER_GROUP = frozenset((WATER, WR, WL))


def _grouped(mats):
    """Multiset of materials with the whole water family folded into WATER."""
    return sorted(WATER if m in _WATER_GROUP else m for m in mats)


def check_conservation(c00, c01, c10, c11, n00, n01, n10, n11):
    """Verify materials are preserved under the GROUPED invariant.

    Strict multiset equality no longer holds because a WATER cell may become
    WR/WL and back. The invariant is: every non-water material count is
    preserved, and the total water-family count is preserved.
    """
    return _grouped([c00, c01, c10, c11]) == _grouped([n00, n01, n10, n11])


def generate_test_vectors(filename):
    """Generate exhaustive test vectors for tb_block_rule.

    Format: one line per case, space-separated:
      grav_dir rnd c00 c01 c10 c11 n00 n01 n10 n11
    All values in hex. rnd is a 2-bit value (0..3).
    6 materials ⁴ × 4 gravities × 4 rnd = 20 736 vectors.
    """
    materials = [EMPTY, WALL, SAND, WATER, WR, WL]
    count = 0
    with open(filename, "w", newline="\n") as f:
        for grav in range(4):
            for rnd in range(4):
                for c00 in materials:
                    for c01 in materials:
                        for c10 in materials:
                            for c11 in materials:
                                n00, n01, n10, n11 = block_rule(
                                    c00, c01, c10, c11, grav, rnd
                                )
                                assert check_conservation(
                                    c00, c01, c10, c11,
                                    n00, n01, n10, n11
                                ), (f"Conservation violated: "
                                    f"({c00},{c01},{c10},{c11}) -> "
                                    f"({n00},{n01},{n10},{n11}) "
                                    f"grav={grav} rnd={rnd}")
                                f.write(
                                    f"{grav:x} {rnd:x} "
                                    f"{c00:x} {c01:x} {c10:x} {c11:x} "
                                    f"{n00:x} {n01:x} {n10:x} {n11:x}\n"
                                )
                                count += 1
    return count


if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    vec_file = os.path.join(here, "block_rule_vectors.mem")
    n = generate_test_vectors(vec_file)
    print(f"wrote {vec_file} ({n} vectors)")
    # Quick self-check: 6 materials ^4 × 4 gravities × 4 rnd
    assert n == 4 * 4 * 6**4, f"expected {4*4*6**4}, got {n}"
    print("self-check: all vectors conserve mass (grouped) ✓")
