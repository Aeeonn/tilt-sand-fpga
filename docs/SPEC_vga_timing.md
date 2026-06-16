# SPEC: vga_timing

640x480@~60Hz VGA timing generator from a 25 MHz pixel clock. Drives `VGA_HS`/`VGA_VS`
and tells the rest of the pipeline which pixel is currently being scanned out.

## Interface

| Signal     | Dir | Width | Description |
|------------|-----|-------|-------------|
| `clk`      | in  | 1     | Pixel clock, 25 MHz (`clk_25`) |
| `rst_n`    | in  | 1     | Active-low sync reset (already synchronized) |
| `hsync`    | out | 1     | Horizontal sync, **active low** |
| `vsync`    | out | 1     | Vertical sync, **active low** |
| `video_on` | out | 1     | High while `(pixel_x,pixel_y)` is in the visible 640x480 area |
| `pixel_x`  | out | 10    | Horizontal counter, 0..H_TOTAL-1. Meaningful pixel column (0..639) only when `video_on` |
| `pixel_y`  | out | 10    | Vertical counter, 0..V_TOTAL-1. Meaningful pixel row (0..479) only when `video_on` |

Parameters (defaults = standard 640x480@60 VESA timing):

| Parameter   | Default | Meaning |
|-------------|---------|---------|
| `H_VISIBLE` | 640 | visible columns |
| `H_FRONT`   | 16  | horizontal front porch |
| `H_SYNC`    | 96  | horizontal sync pulse width |
| `H_BACK`    | 48  | horizontal back porch |
| `V_VISIBLE` | 480 | visible rows |
| `V_FRONT`   | 10  | vertical front porch (lines) |
| `V_SYNC`    | 2   | vertical sync pulse width (lines) |
| `V_BACK`    | 33  | vertical back porch (lines) |

Derived: `H_TOTAL = H_VISIBLE+H_FRONT+H_SYNC+H_BACK = 800`,
`V_TOTAL = V_VISIBLE+V_FRONT+V_SYNC+V_BACK = 525`,
`FRAME_CYCLES = H_TOTAL*V_TOTAL = 420,000`.
At 25 MHz this gives a 59.52 Hz refresh — within spec for a 640x480@60 monitor.

## Behavior

Two free-running counters, reset to 0 by `rst_n`:

```
if (h_count == H_TOTAL-1) begin
  h_count <= 0;
  v_count <= (v_count == V_TOTAL-1) ? 0 : v_count + 1;
end else begin
  h_count <= h_count + 1;
end
```

Outputs are combinational functions of `h_count`/`v_count` (no extra latency):

```
hsync    = ~(h_count >= H_VISIBLE+H_FRONT && h_count < H_VISIBLE+H_FRONT+H_SYNC)
vsync    = ~(v_count >= V_VISIBLE+V_FRONT && v_count < V_VISIBLE+V_FRONT+V_SYNC)
video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE)
pixel_x  = h_count
pixel_y  = v_count
```

## Derived constants (for verification)

| Constant | Value |
|---|---|
| `H_TOTAL` | 800 |
| `V_TOTAL` | 525 |
| `FRAME_CYCLES` | 420000 |
| hsync active range (h_count) | [656, 752) — 96 cycles/line |
| vsync active range (v_count) | [490, 492) — 2 lines |
| video_on cycles/frame | 640 * 480 = 307200 |
| hsync active cycles/frame | `V_TOTAL * H_SYNC` = 50400 |
| vsync active cycles/frame | `V_SYNC * H_TOTAL` = 1600 |
| first/last `(pixel_x,pixel_y)` with `video_on=1` | `(0,0)` / `(639,479)` |

## Verification

`sim/golden/vga_timing.py` walks all `H_TOTAL*V_TOTAL` `(h_count,v_count)` pairs,
asserts the derived constants above hold, and emits `sim/golden/vga_timing_consts.svh`
(`` `define `` macros for the constants) for the testbench to `` `include ``.

`sim/tb/tb_vga_timing.sv` runs `FRAME_CYCLES + 10` cycles. Each cycle it advances an
independently-coded reference `(ref_h,ref_v)` pair and compares `hsync`/`vsync`/
`video_on`/`pixel_x`/`pixel_y` against the DUT (catches any per-cycle/edge-case
mismatch, including porch boundaries). Over the first `FRAME_CYCLES` cycles it also
accumulates total `video_on`, `hsync`-active and `vsync`-active cycle counts and checks
them against the `` `include ``d constants (catches whole-frame miscounts that a
per-cycle diff against a similarly-shaped reference might share).
