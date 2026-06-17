# SPEC: hud_overlay — on-screen status HUD

## Purpose

Draws a live status bar across the top of the VGA frame so the user can see,
at a glance, what they're about to spawn, which way gravity points, and how
much material is in the dish. Pure combinational — a function of pixel
position and a few status inputs. Composited over the grid in `top.sv`.

## Interface

```systemverilog
module hud_overlay (
    input  logic [9:0]  pixel_x,
    input  logic [9:0]  pixel_y,
    input  logic [11:0] sel_color,   // selected material colour (RGB444)
    input  logic [1:0]  grav_dir,    // 0=DOWN 1=UP 2=LEFT 3=RIGHT
    input  logic [15:0] count,       // live particle count
    output logic        ov_on,       // 1 = draw overlay (else show grid)
    output logic [11:0] ov_rgb       // overlay colour (RGB444)
);
```

## Elements (top 16 pixel rows of the 640×480 frame)

| Element | Region (pixels) | Meaning |
|---------|-----------------|---------|
| Material swatch | x[4..19] y[0..15] | Framed box filled with `sel_color` — the colour of the material KEY[1] spawns |
| Gravity D-pad | dots around (34, 8) | Four dots; the active `grav_dir` is white, others dim grey |
| Particle bar | x[48..607] y[3..12] | Horizontal bar; fill length = `count >> 4` (clamped to 558 px) |

The D-pad dots: UP (33–35, 1–3), DOWN (33–35, 12–14), LEFT (27–29, 7–9),
RIGHT (39–41, 7–9). The bar fills cyan from x=49; full at count ≈ 8928.

## Composition / timing

`hud_overlay` is combinational from the current `pixel_x/pixel_y`. In `top.sv`
its outputs are delayed by 2 pixel clocks to align with the grid palette output
(scanout +1 BRAM, palette +1), then composited:

```
VGA = video_on ? (ov_on ? ov_rgb : grid_color) : black
```

`sel_color` comes from a second `palette` instance reading
`{4'b0, selected_material}`. The status inputs (material, gravity, count) cross
from `clk_100` into `clk_25` through 2-FF registers — display-only, so a
one-frame tear on a multi-bit value is invisible; the SDC already cuts
`clk_100 ↔ clk_25` as asynchronous.

## Verification

- `tb_hud_overlay`: drives representative pixel coordinates and status values,
  checks `ov_on`/`ov_rgb` for the swatch fill/frame, each gravity dot
  (active vs dim) for all four directions, the bar (empty vs filled vs frame),
  and confirms no overlay below the HUD region.
