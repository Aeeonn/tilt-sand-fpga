#!/usr/bin/env python3
"""sand_falling — material table and palette generator (golden source of truth).

This is the single definition of the 16 material IDs (4 bits/cell) used by the
CA engine, the rule golden model, and the VGA palette. Run as a script to emit
``sand_palette.mem`` next to this file:

    python sim/golden/sand_materials.py

The .mem is a 256 x 12-bit RGB444 ROM image for ``rtl/platform/palette.sv``
(``$readmemh``): one 3-hex-digit value per line, palette address = the 8-bit
value ``{4'b0, material[3:0]}`` so material ``i`` maps to palette entry ``i``.
Entries 16..255 are black (reserved).

Physical properties (density, flammability, ...) will be added here as the rule
engine grows, keeping material semantics in one place. For now only IDs + colors
are defined (enough for the skeleton's palette and the first MVP materials).
"""

import os

# id, NAME, RGB444 (hex string, 3 nibbles R,G,B). IDs are fixed: 4 bits/cell.
MATERIALS = [
    (0,  "EMPTY", "000"),  # vacuum / air (falls through)
    (1,  "WALL",  "777"),  # immovable boundary / static solid
    (2,  "SAND",  "ed6"),  # granular powder (MVP)
    (3,  "WATER", "34f"),  # fluid, still / no horizontal momentum (MVP+1)
    (4,  "WATER_R", "34f"),  # water carrying +x momentum (same blue as WATER)
    (5,  "WATER_L", "34f"),  # water carrying -x momentum (same blue as WATER)
    (6,  "ACID",  "7e1"),  # dissolves some solids
    (7,  "PLANT", "2a2"),  # grows along water
    (8,  "STEAM", "bcd"),  # rises (inverse gravity)
    (9,  "SMOKE", "555"),  # rises, fades
    (10, "STONE", "976"),  # heavy static solid
    (11, "EMBER", "f92"),  # burning solid
    (12, "SALT",  "eee"),  # powder, dissolves in water
    (13, "LAVA",  "f30"),  # heavy hot fluid
    (14, "GLASS", "9ce"),  # static solid (sand + heat)
    (15, "SPARK", "ff6"),  # electricity carrier (stretch: CA-ception)
]

# Water momentum family: these IDs all render as water and behave as one fluid
# for mass-conservation purposes. WATER_R/WATER_L encode horizontal velocity so
# water can slosh (overshoot + decay) and rise in communicating vessels. The
# reactive materials OIL/FIRE that previously held IDs 4/5 move to free IDs when
# milestone M7 begins (none are implemented yet).
WATER_IDS = (3, 4, 5)

NUM_MATERIALS = len(MATERIALS)
CELL_BITS = 4
PALETTE_ENTRIES = 256

# Convenience name -> id and id -> rgb maps.
ID = {name: mid for mid, name, _ in MATERIALS}
RGB = {mid: rgb for mid, _, rgb in MATERIALS}


def _self_check():
    assert NUM_MATERIALS <= (1 << CELL_BITS), "more than 16 materials won't fit in 4 bits"
    ids = [mid for mid, _, _ in MATERIALS]
    assert ids == list(range(NUM_MATERIALS)), "material IDs must be contiguous from 0"
    for mid, name, rgb in MATERIALS:
        assert len(rgb) == 3 and all(c in "0123456789abcdef" for c in rgb), \
            f"{name}: RGB444 must be 3 lowercase hex nibbles, got {rgb!r}"
    return True


def palette_image():
    """Return the 256-entry list of 12-bit RGB444 ints (material id -> entry id)."""
    img = [0] * PALETTE_ENTRIES
    for mid, _, rgb in MATERIALS:
        img[mid] = int(rgb, 16)
    return img


def write_palette_mem(path):
    img = palette_image()
    with open(path, "w", newline="\n") as f:
        for v in img:
            f.write(f"{v:03x}\n")
    return path


if __name__ == "__main__":
    _self_check()
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sand_palette.mem")
    write_palette_mem(out)
    print(f"wrote {out} ({PALETTE_ENTRIES} entries, {NUM_MATERIALS} materials)")
    for mid, name, rgb in MATERIALS:
        print(f"  {mid:2d} {name:<6} #{rgb}")
