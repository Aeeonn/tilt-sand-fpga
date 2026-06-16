#!/usr/bin/env python3
"""sand_falling — grid geometry, M2 test grid, and frame model (golden).

Single source of truth for the grid dimensions and the M2 "preloaded static test
grid". Run as a script to (re)generate, next to this file / under sim/:

    python sim/golden/sand_grid.py

emits:
  * sim/golden/grid_consts.svh   - GRID_W/H, CELL_BITS, ADDR_BITS, latencies
  * sim/golden/test_grid.mem     - 320x240 test grid ($readmemh, 1 nibble/line)
  * sim/golden/empty_grid.mem    - all-EMPTY grid (back bank init)
  * sim/out/expected_frame.png   - what the monitor should show in M2

Material IDs/colours come from sand_materials.py so the test grid, palette, and
RTL all agree.
"""

import os
import pathlib

from sand_materials import ID, palette_image, CELL_BITS

GRID_W = 320
GRID_H = 240
DEPTH = GRID_W * GRID_H
ADDR_BITS = (DEPTH - 1).bit_length()          # 17

# VGA read-pipeline latencies (see docs/SPEC_grid_scanout.md).
SCANOUT_BRAM_LAT = 1          # grid_mem registered read
SCANOUT_TOTAL_LAT = 2         # + palette registered read (in top)

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "out"


def new_grid(fill=0):
    return [[fill for _ in range(GRID_W)] for _ in range(GRID_H)]


def _rect(g, x0, y0, x1, y1, mat):
    """Fill the inclusive rectangle [x0,x1]x[y0,y1] (clipped) with mat."""
    for y in range(max(0, y0), min(GRID_H, y1 + 1)):
        for x in range(max(0, x0), min(GRID_W, x1 + 1)):
            g[y][x] = mat


def build_test_grid():
    """A deliberately asymmetric, palette-covering image.

    Features (each catches a class of bug):
      * 1-cell WALL border               -> edges / extent correct
      * 16 material swatches across top   -> palette + left-to-right order
      * three SAND columns of unequal len -> vertical addressing, not mirrored
      * a STONE diagonal                  -> (x,y) not transposed
      * a WATER pool across the bottom     -> large fill, row-major contiguity
    """
    g = new_grid(ID["EMPTY"])

    # WALL border (thickness 1)
    _rect(g, 0, 0, GRID_W - 1, 0, ID["WALL"])
    _rect(g, 0, GRID_H - 1, GRID_W - 1, GRID_H - 1, ID["WALL"])
    _rect(g, 0, 0, 0, GRID_H - 1, ID["WALL"])
    _rect(g, GRID_W - 1, 0, GRID_W - 1, GRID_H - 1, ID["WALL"])

    # 16 material swatches, 16x16 each, left-aligned strip near the top.
    sw = 16
    x0 = 16
    y0 = 16
    for mat in range(16):
        _rect(g, x0 + mat * sw, y0, x0 + mat * sw + sw - 1, y0 + sw - 1, mat)

    # Three SAND columns of different heights (asymmetric on purpose).
    for cx, h in ((48, 120), (96, 80), (144, 160)):
        _rect(g, cx, 60, cx + 2, 60 + h, ID["SAND"])

    # STONE diagonal from upper-left-ish to lower-right-ish.
    for i in range(0, 160):
        x = 170 + i
        y = 60 + i
        if 0 <= x < GRID_W and 0 <= y < GRID_H:
            g[y][x] = ID["STONE"]

    # WATER pool across the bottom interior.
    _rect(g, 1, 205, GRID_W - 2, GRID_H - 2, ID["WATER"])

    return g


def write_mem(g, path):
    with open(path, "w", newline="\n") as f:
        for y in range(GRID_H):
            for x in range(GRID_W):
                f.write(f"{g[y][x] & 0xF:x}\n")
    return path


def write_empty_mem(path):
    with open(path, "w", newline="\n") as f:
        f.write("0\n" * DEPTH)
    return path


def write_mif(g, path, width=CELL_BITS):
    """Intel MIF for altsyncram .init_file (bram_tdp). Row-major, one word/addr."""
    flat = [g[y][x] & ((1 << width) - 1) for y in range(GRID_H) for x in range(GRID_W)]
    with open(path, "w", newline="\n") as f:
        f.write(f"WIDTH={width};\nDEPTH={DEPTH};\n")
        f.write("ADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n")
        for addr, v in enumerate(flat):
            f.write(f"{addr:X} : {v:X};\n")
        f.write("END;\n")
    return path


def expected_frame(g):
    """640x480 list of (r,g,b) 8-bit tuples: palette[grid[y>>1][x>>1]]."""
    pal = palette_image()  # 256 entries of 12-bit RGB444
    frame = []
    for Y in range(480):
        row = []
        cy = Y >> 1
        for X in range(640):
            cx = X >> 1
            v = pal[g[cy][cx]]
            r4, g4, b4 = (v >> 8) & 0xF, (v >> 4) & 0xF, v & 0xF
            row.append((r4 * 17, g4 * 17, b4 * 17))  # nibble replicate -> 8-bit
        frame.append(row)
    return frame


def write_expected_png(g, path):
    from PIL import Image
    frame = expected_frame(g)
    img = Image.new("RGB", (640, 480))
    img.putdata([px for row in frame for px in row])
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    return path


def frametxt_to_png(txt_path, png_path):
    """Convert a tb_top VGA dump (W H header + RRGGBB/line) to a PNG."""
    from PIL import Image
    with open(txt_path) as f:
        w, h = (int(t) for t in f.readline().split())
        px = []
        for line in f:
            line = line.strip()
            if not line:
                continue
            px.append((int(line[0:2], 16), int(line[2:4], 16), int(line[4:6], 16)))
    img = Image.new("RGB", (w, h))
    img.putdata(px)
    img.save(png_path)
    return png_path


def write_consts_svh(path):
    path.write_text(
        "// Generated by sim/golden/sand_grid.py - do not edit by hand.\n"
        "`ifndef GRID_CONSTS_SVH\n"
        "`define GRID_CONSTS_SVH\n"
        f"`define GRID_W {GRID_W}\n"
        f"`define GRID_H {GRID_H}\n"
        f"`define GRID_CELL_BITS {CELL_BITS}\n"
        f"`define GRID_DEPTH {DEPTH}\n"
        f"`define GRID_ADDR_BITS {ADDR_BITS}\n"
        f"`define SCANOUT_BRAM_LAT {SCANOUT_BRAM_LAT}\n"
        f"`define SCANOUT_TOTAL_LAT {SCANOUT_TOTAL_LAT}\n"
        "`endif\n"
    )
    return path


def main():
    assert ADDR_BITS == 17, ADDR_BITS
    assert CELL_BITS == 4, CELL_BITS
    g = build_test_grid()

    write_consts_svh(HERE / "grid_consts.svh")
    write_mem(g, HERE / "test_grid.mem")          # $readmemh golden for TBs
    write_empty_mem(HERE / "empty_grid.mem")
    write_mif(g, HERE / "test_grid.mif")          # altsyncram init (bank0)
    write_mif(new_grid(ID["EMPTY"]), HERE / "empty_grid.mif")   # bank1
    png = write_expected_png(g, OUT / "expected_frame.png")

    # quick non-emptiness / coverage sanity
    flat = [c for row in g for c in row]
    mats = sorted(set(flat))
    print(f"grid {GRID_W}x{GRID_H} depth={DEPTH} addr_bits={ADDR_BITS}")
    print(f"materials present: {mats}")
    print(f"wrote grid_consts.svh, test_grid.mem ({DEPTH} cells), empty_grid.mem")
    print(f"wrote {png}")


if __name__ == "__main__":
    main()
