#!/usr/bin/env python3
"""margolus_engine.py — golden model for the Margolus CA grid stepper.

Steps a full grid through N frames using the block_rule golden model.
Generates expected grid states for tb_margolus_engine verification.

Usage:
    python sim/golden/margolus_engine.py [--frames N] [--out DIR]

Outputs:
    grid_frame_<N>.mem  — expected grid state after frame N
    mass_counts.txt     — non-EMPTY cell count per frame (must be constant)
"""

import os
import sys
import pathlib

# Ensure we can import siblings
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from block_rule import block_rule, EMPTY, WALL, SAND
from sand_grid import GRID_W, GRID_H, new_grid, write_mem

# LFSR simulation (must match rtl/sand/lfsr.sv)
LFSR_SEED = 0xACE1
LFSR_POLY = 0xB400   # Galois taps for x^16+x^14+x^13+x^11+1


def lfsr_step(state):
    """One step of the 16-bit Galois LFSR."""
    if state & 1:
        return (state >> 1) ^ LFSR_POLY
    else:
        return state >> 1


def count_nonempty(grid):
    """Count cells that are not EMPTY."""
    return sum(1 for row in grid for c in row if c != EMPTY)


def step_frame(grid, phase, grav_dir, lfsr_state):
    """Apply one frame of the Margolus CA (one phase).

    Returns (new_grid, new_lfsr_state).
    """
    out = [row[:] for row in grid]  # deep copy
    state = lfsr_state

    if phase == 0:
        # Blocks aligned at even (x,y)
        for by in range(GRID_H // 2):
            for bx in range(GRID_W // 2):
                y = 2 * by
                x = 2 * bx
                c00 = grid[y][x]
                c01 = grid[y][x+1]
                c10 = grid[y+1][x]
                c11 = grid[y+1][x+1]
                rnd_bit = state & 3       # 2-bit rnd (r0,r1) for momentum rule
                state = lfsr_step(state)
                n00, n01, n10, n11 = block_rule(c00, c01, c10, c11, grav_dir, rnd_bit)
                out[y][x]     = n00
                out[y][x+1]   = n01
                out[y+1][x]   = n10
                out[y+1][x+1] = n11
    else:
        # Phase 1: blocks offset by (1,1). Interior blocks only.
        for by in range(GRID_H // 2 - 1):
            for bx in range(GRID_W // 2 - 1):
                y = 2 * by + 1
                x = 2 * bx + 1
                c00 = grid[y][x]
                c01 = grid[y][x+1]
                c10 = grid[y+1][x]
                c11 = grid[y+1][x+1]
                rnd_bit = state & 3       # 2-bit rnd (r0,r1) for momentum rule
                state = lfsr_step(state)
                n00, n01, n10, n11 = block_rule(c00, c01, c10, c11, grav_dir, rnd_bit)
                out[y][x]     = n00
                out[y][x+1]   = n01
                out[y+1][x]   = n10
                out[y+1][x+1] = n11

    return out, state


def build_m3_test_grid():
    """A small deterministic test grid for M3 verification.

    Features:
    - WALL border (like the M2 grid)
    - A 3-wide sand column suspended 10 rows above the floor
    - Enough empty space below for sand to fall and pile
    """
    g = new_grid(EMPTY)

    # WALL border
    for x in range(GRID_W):
        g[0][x] = WALL
        g[GRID_H-1][x] = WALL
    for y in range(GRID_H):
        g[y][0] = WALL
        g[y][GRID_W-1] = WALL

    # Sand column: 3 wide, 20 tall, centered at x=160, starting at y=50
    for y in range(50, 70):
        for x in range(159, 162):
            g[y][x] = SAND

    return g


def run_simulation(grid, num_frames, grav_dir=0, passes_per_frame=1):
    """Run num_frames displayed frames of the Margolus CA.

    Each displayed frame runs ``passes_per_frame`` Margolus steps (matching
    the RTL multi-pass engine). The Margolus phase toggles every pass and
    persists across frames. Returns list of (frame_num, grid, mass) tuples.
    """
    results = []
    lfsr_state = LFSR_SEED
    phase = 0
    mass0 = count_nonempty(grid)
    results.append((0, [row[:] for row in grid], mass0))

    for f in range(1, num_frames + 1):
        for _ in range(passes_per_frame):
            grid, lfsr_state = step_frame(grid, phase, grav_dir, lfsr_state)
            phase = 1 - phase
        mass = count_nonempty(grid)
        results.append((f, [row[:] for row in grid], mass))

    return results


def write_frame_mem(grid, path):
    """Write grid as a .mem file (one hex nibble per line, row-major)."""
    write_mem(grid, path)


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Margolus CA golden model")
    parser.add_argument("--frames", type=int, default=100,
                        help="Number of frames to simulate")
    parser.add_argument("--out", type=str, default=None,
                        help="Output directory (default: sim/golden/)")
    parser.add_argument("--grav", type=int, default=0,
                        help="Gravity direction (0=DOWN)")
    parser.add_argument("--passes", type=int, default=1,
                        help="Margolus steps per displayed frame (multi-pass)")
    args = parser.parse_args()

    here = pathlib.Path(__file__).resolve().parent
    out_dir = pathlib.Path(args.out) if args.out else here

    grid = build_m3_test_grid()
    mass0 = count_nonempty(grid)
    print(f"Initial grid: {GRID_W}x{GRID_H}, {mass0} non-empty cells")

    results = run_simulation(grid, args.frames, args.grav, args.passes)

    # Write key frames and mass counts
    mass_ok = True
    with open(out_dir / "mass_counts.txt", "w", newline="\n") as mf:
        mf.write(f"# frame  non_empty  (expected: {mass0})\n")
        for frame_num, g, mass in results:
            mf.write(f"{frame_num} {mass}\n")
            if mass != mass0:
                print(f"*** MASS VIOLATION frame {frame_num}: "
                      f"expected {mass0}, got {mass}")
                mass_ok = False

    # Write initial and final frames
    write_frame_mem(results[0][1], str(out_dir / "m3_grid_frame_0.mem"))
    write_frame_mem(results[-1][1], str(out_dir / f"m3_grid_frame_{args.frames}.mem"))

    # Write frame 1 for bit-exact TB comparison
    if args.frames >= 1:
        write_frame_mem(results[1][1], str(out_dir / "m3_grid_frame_1.mem"))

    print(f"Simulated {args.frames} frames, mass {'OK' if mass_ok else 'VIOLATED'}")
    print(f"  Frame 0 mass: {results[0][2]}")
    print(f"  Frame {args.frames} mass: {results[-1][2]}")
    if mass_ok:
        print("Mass conservation: PASS")
    else:
        print("*** Mass conservation: FAIL ***")
        sys.exit(1)


if __name__ == "__main__":
    main()
