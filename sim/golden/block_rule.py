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

# Density: higher = heavier (sinks). WALL is max so nothing can displace it
# via the vertical-fall swap. EMPTY=0, WATER=1, SAND/others=2, WALL=3.
def _density(mat):
    if mat == EMPTY:
        return 0
    if mat == WATER:
        return 1
    if mat == WALL:
        return 3  # immovable: nothing is denser
    return 2  # granular solid

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


def _rule_down(c00, c01, c10, c11, rnd):
    """Apply the block rule with gravity = DOWN (canonical orientation).

    Working cells a=TL b=TR c=BL d=BR. Four sequential phases:
      1. Vertical fall  — heavier cell sinks below a lighter one (density).
      2. Water diagonal — top fluid blocked straight down drains to an empty
                          diagonal (water flows around obstacles).
      3. Water level    — fluid spreads horizontally into adjacent EMPTY,
                          rnd-biased so it converges flat instead of sloshing.
      4. Sand diagonal  — granular cell blocked by a solid below slides into
                          an empty diagonal, PROBABILISTIC (rnd) for a steeper
                          angle of repose (real pyramids).

    Each phase is a swap (or no-op) → a pure permutation (conserves mass).
    Returns (n00, n01, n10, n11).
    """
    a, b, c, d = c00, c01, c10, c11

    # Phase 1: vertical fall (each column independently, by density)
    if _is_movable(a) and _density(a) > _density(c):
        a, c = c, a
    if _is_movable(b) and _density(b) > _density(d):
        b, d = d, b

    # Phase 2: water diagonal flow — top fluid blocked straight down drains
    # into an empty diagonal (lets water flow around obstacles).
    if a == WATER and c != EMPTY and d == EMPTY:
        a, d = d, a
    elif b == WATER and d != EMPTY and c == EMPTY:
        b, c = c, b

    # Phase 3: water horizontal level — spread into adjacent EMPTY in each
    # row, rnd-biased so net flow alternates and converges to a flat surface.
    if a == WATER and b == EMPTY and rnd:
        a, b = b, a
    elif b == WATER and a == EMPTY and not rnd:
        a, b = b, a
    if c == WATER and d == EMPTY and rnd:
        c, d = d, c
    elif d == WATER and c == EMPTY and not rnd:
        c, d = d, c

    # Phase 4: granular diagonal slide — blocked by a solid below, slides
    # into an empty diagonal. PROBABILISTIC (rnd) → steeper angle of repose.
    if _is_granular(a) and c != EMPTY and c != WATER and d == EMPTY and rnd:
        a, d = d, a
    elif _is_granular(b) and d != EMPTY and d != WATER and c == EMPTY and not rnd:
        b, c = c, b

    return a, b, c, d


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

    Returns (n00, n01, n10, n11).
    """
    if grav_dir == G_DOWN:
        return _rule_down(c00, c01, c10, c11, rnd)
    elif grav_dir == G_UP:
        # Rotate 180° so "up" becomes "down", apply, rotate back
        a, b, c, d = _rotate_180(c00, c01, c10, c11)
        a, b, c, d = _rule_down(a, b, c, d, rnd)
        return _rotate_180(a, b, c, d)
    elif grav_dir == G_LEFT:
        # Rotate CW so "left" becomes "down", apply, rotate back CCW
        a, b, c, d = _rotate_cw(c00, c01, c10, c11)
        a, b, c, d = _rule_down(a, b, c, d, rnd)
        return _rotate_ccw(a, b, c, d)
    elif grav_dir == G_RIGHT:
        # Rotate CCW so "right" becomes "down", apply, rotate back CW
        a, b, c, d = _rotate_ccw(c00, c01, c10, c11)
        a, b, c, d = _rule_down(a, b, c, d, rnd)
        return _rotate_cw(a, b, c, d)
    else:
        raise ValueError(f"invalid grav_dir {grav_dir}")


def check_conservation(c00, c01, c10, c11, n00, n01, n10, n11):
    """Verify the multiset of materials is preserved (pure permutation)."""
    inp = sorted([c00, c01, c10, c11])
    out = sorted([n00, n01, n10, n11])
    return inp == out


def generate_test_vectors(filename):
    """Generate exhaustive test vectors for tb_block_rule.

    Format: one line per case, space-separated:
      grav_dir rnd c00 c01 c10 c11 n00 n01 n10 n11
    All values in hex.
    """
    materials = [EMPTY, WALL, SAND, WATER]
    count = 0
    with open(filename, "w", newline="\n") as f:
        for grav in range(4):
            for rnd in range(2):
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
    # Quick self-check
    assert n == 4 * 2 * 4**4, f"expected {4*2*4**4}, got {n}"
    print("self-check: all vectors conserve mass ✓")
