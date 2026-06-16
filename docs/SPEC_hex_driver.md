# SPEC: hex_driver

Combinational 4-bit hex-to-seven-segment decoder for one DE10-Lite `HEXn` digit.

## Interface

| Signal  | Dir | Width | Description |
|---------|-----|-------|-------------|
| `value` | in  | 4     | Hex digit `0x0`-`0xF` |
| `seg`   | out | 7     | Segment drive, active-low, bit order `{g,f,e,d,c,b,a}` |

No `clk`/`rst_n` — purely combinational (`always_comb`).

`seg` maps directly onto `HEXn[6:0]`. `HEXn[7]` (decimal point) is **not** driven by
this module; the instantiation site ties it off (`1'b1` = off) or drives it separately.

## Segment layout

```
 _a_
f| |b
 -g-
e| |c
 -d-
```

## Truth table

Active-low: `0` = segment on, `1` = segment off. `seg = {g,f,e,d,c,b,a}`.

| value | lit segments    | seg (gfedcba) | hex    |
|-------|------------------|---------------|--------|
| 0x0   | a b c d e f      | 1000000       | 0x40   |
| 0x1   | b c              | 1111001       | 0x79   |
| 0x2   | a b d e g        | 0100100       | 0x24   |
| 0x3   | a b c d g        | 0110000       | 0x30   |
| 0x4   | b c f g          | 0011001       | 0x19   |
| 0x5   | a c d f g        | 0010010       | 0x12   |
| 0x6   | a c d e f g      | 0000010       | 0x02   |
| 0x7   | a b c            | 1111000       | 0x78   |
| 0x8   | a b c d e f g    | 0000000       | 0x00   |
| 0x9   | a b c d f g      | 0010000       | 0x10   |
| 0xA   | a b c e f g      | 0001000       | 0x08   |
| 0xB   | c d e f g        | 0000011       | 0x03   |
| 0xC   | a d e f          | 1000110       | 0x46   |
| 0xD   | b c d e g        | 0100001       | 0x21   |
| 0xE   | a d e f g        | 0000110       | 0x06   |
| 0xF   | a e f g          | 0001110       | 0x0E   |

`B` and `D` are rendered lowercase (`b`, `d`) to stay visually distinct from `8` and `0`.

## Verification

`sim/golden/hex_driver.py` derives this table independently from the "lit segments"
column (not by copying the hex literals) and writes `sim/golden/hex_driver_vectors.mem`
(16 lines, 7-bit binary, `gfedcba` order, MSB first). `sim/tb/tb_hex_driver.sv` reads
that file with `$readmemb` and sweeps `value` 0x0-0xF, comparing against `seg`.
