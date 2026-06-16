#!/usr/bin/env python3
"""Golden model for rtl/platform/hex_driver.sv. See docs/SPEC_hex_driver.md.

Derives the active-low seven-segment patterns from the "lit segments" table
independently of the RTL's hex literals, and writes the vectors that
sim/tb/tb_hex_driver.sv reads via $readmemb.
"""

import pathlib

# Segment letters that are lit (driven low) for each hex digit.
LIT_SEGMENTS = {
    0x0: "abcdef",
    0x1: "bc",
    0x2: "abdeg",
    0x3: "abcdg",
    0x4: "bcfg",
    0x5: "acdfg",
    0x6: "acdefg",
    0x7: "abc",
    0x8: "abcdefg",
    0x9: "abcdfg",
    0xA: "abcefg",
    0xB: "cdefg",
    0xC: "adef",
    0xD: "bcdeg",
    0xE: "adefg",
    0xF: "aefg",
}

# Bit position of each segment within seg[6:0] = {g,f,e,d,c,b,a}.
BIT_POSITION = {"a": 0, "b": 1, "c": 2, "d": 3, "e": 4, "f": 5, "g": 6}


def seg_pattern(value: int) -> str:
    """Return the 7-bit active-low pattern for `value`, MSB-first as gfedcba."""
    lit = LIT_SEGMENTS[value]
    bits = ["1"] * 7  # active-low: default off
    for ch in lit:
        bits[6 - BIT_POSITION[ch]] = "0"  # lit segment -> driven low
    return "".join(bits)


def main() -> None:
    out_path = pathlib.Path(__file__).parent / "hex_driver_vectors.mem"
    lines = [seg_pattern(v) for v in range(16)]
    out_path.write_text("\n".join(lines) + "\n")
    print(f"wrote {out_path} ({len(lines)} vectors)")


if __name__ == "__main__":
    main()
