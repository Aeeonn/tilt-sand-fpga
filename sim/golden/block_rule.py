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

# Density: higher = heavier (sinks). WALL = special (immovable).
# EMPTY=0, WATER=1, everything else (SAND + materials 4-15)=2.
def _density(mat):
    if mat == EMPTY:
        return 0
    if mat == WATER:
        return 1
    if mat == WALL:
        return 0  # unused — wall checked separately
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

    Phase 1: vertical fall (each column independently).
             - SAND falls into EMPTY or WATER
             - WATER falls into EMPTY
    Phase 2: diagonal flow (any mobile material: sand slides, water flows).
    Phase 3: lateral spread (fluid: WATER spreads sideways).

    Returns (n00, n01, n10, n11).
    """
    r00, r01, r10, r11 = c00, c01, c10, c11

    # Phase 1: vertical fall — left column
    if _falls_into(r00, r10):
        r00, r10 = r10, r00

    # Phase 1: vertical fall — right column
    if _falls_into(r01, r11):
        r01, r11 = r11, r01

    # Phase 2: diagonal flow — any mobile material (sand slides, water flows)
    # After phase 1, a mobile cell still in row 0 is blocked straight down,
    # so it flows into an EMPTY diagonal cell. Sand piles; water drains.
    left_can  = (_is_movable(r00) and r10 != EMPTY and r11 == EMPTY)
    right_can = (_is_movable(r01) and r11 != EMPTY and r10 == EMPTY)

    if left_can and right_can:
        if rnd:
            r00, r11 = r11, r00
        else:
            r01, r10 = r10, r01
    elif left_can:
        r00, r11 = r11, r00
    elif right_can:
        r01, r10 = r10, r01

    # Phase 3: lateral spread — WATER flows sideways when blocked below
    # WATER in row 0 spreads to an adjacent EMPTY in the same row
    # WATER in row 1 spreads to an adjacent EMPTY in the same row
    # (only if blocked below — i.e., the cell below in the block is not EMPTY)
    # For row 0: water at (0,0) can spread to (0,1) if (0,1) is EMPTY and (1,0) blocks
    #            water at (0,1) can spread to (0,0) if (0,0) is EMPTY and (1,1) blocks
    w_left  = (r00 == WATER and r10 != EMPTY and r01 == EMPTY)
    w_right = (r01 == WATER and r11 != EMPTY and r00 == EMPTY)

    if w_left and w_right:
        # Both want to spread — rnd picks one
        if rnd:
            r00, r01 = r01, r00
        else:
            r01, r00 = r00, r01  # same effect since both swap
    elif w_left:
        r00, r01 = r01, r00
    elif w_right:
        r01, r00 = r00, r01

    # Lateral spread for row 1 (bottom row)
    w_left_b  = (r10 == WATER and r11 == EMPTY)
    w_right_b = (r11 == WATER and r10 == EMPTY)

    if w_left_b and w_right_b:
        if rnd:
            r10, r11 = r11, r10
        else:
            pass  # only one moves
    elif w_left_b:
        r10, r11 = r11, r10
    elif w_right_b:
        r11, r10 = r10, r11

    return r00, r01, r10, r11


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
