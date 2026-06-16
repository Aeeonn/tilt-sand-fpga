# SPEC: grid_scanout — cell grid → VGA pixel address

`rtl/sand/grid_scanout.sv`. Turns the VGA raster position into a `grid_mem` read
address and the resulting cell into a palette address, with the sync signals
delayed to stay aligned with the pixel data through the read pipeline. Runs in the
`clk_25` (pixel) domain. See `docs/SPEC_sand_overview.md`.

## Pixel → cell mapping

The 320×240 grid is shown on 640×480 by **2×2 pixel doubling**:

```
cx = pixel_x >> 1      // 0..319
cy = pixel_y >> 1      // 0..239
cell_addr = cy*GRID_W + cx     // row-major, matches grid_mem
```

During the visible region (`pixel_x<640`, `pixel_y<480`) `cx∈[0,319]`,
`cy∈[0,239]`, so `cell_addr` is always in `[0, DEPTH-1]`. During blanking the
address is forced to 0 (the output is blanked anyway) so `grid_mem` is never
addressed out of range.

`GRID_W=320 = (1<<8)+(1<<6)`, so `cy*GRID_W` is a constant multiply the synthesizer
reduces to two shifts and an add — no DSP.

## Interface

```
input  clk, rst_n                       // clk_25 domain
input  [9:0] pixel_x, pixel_y           // from vga_timing (registered counters)
input        video_on, hsync, vsync     // from vga_timing
output [ADDR_BITS-1:0] px_addr          // -> grid_mem.px_addr (combinational)
input  [CELL_BITS-1:0] px_data          // <- grid_mem.px_data (1 cyc after px_addr)
output [7:0] pal_addr                   // -> palette.addr  = {4'b0, cell}
output       video_on_q, hsync_q, vsync_q  // sync delayed to align with pal_addr
```

Parameters `GRID_W`, `GRID_H`, `CELL_BITS`, `ADDR_BITS` mirror `grid_mem`.

## Pipeline / latency (the alignment contract)

| cycle | event |
|---|---|
| T   | `pixel_x/y` valid → `px_addr` (combinational), `video_on/hsync/vsync` valid |
| T+1 | `grid_mem` returns `px_data`; `pal_addr = {4'b0, px_data}`; `*_q` = sync delayed by **1** (matches BRAM read) |
| T+2 | `palette` (in `top`) returns RGB; `top` delays `*_q` by **1** more (matches palette) |

So `grid_scanout` delays the sync by exactly the BRAM read latency (1), and `top`
adds the one-cycle palette delay it already had for the colour-bar path. Net VGA
data path latency = **2** `clk_25` cycles, and the output sync is delayed
identically — so the emitted stream is self-consistent: when `VGA_HS/VS` say
"visible pixel (col,row)", `VGA_RGB` is exactly `palette[grid[row>>1][col>>1]]`.
This is what makes the frame **pixel-exact** and is the core check in the TBs.

Constants (`GRID_W/H`, `CELL_BITS`, `ADDR_BITS`, `SCANOUT_BRAM_LAT=1`,
`SCANOUT_TOTAL_LAT=2`) are emitted by `sim/golden/sand_grid.py` into
`sim/golden/grid_consts.svh` so RTL params and TB expectations can't drift.

## Verification (`sim/tb/tb_grid_scanout.sv`, `do_grid_scanout.do`)

Drive a small synthetic raster (small grid + small visible area + porches) with a
TB-internal 1-cycle memory preloaded to a known pattern. Checks:

1. `px_addr == cy*GRID_W + cx` for every visible pixel; `0` during blanking.
2. After the pipeline latency, `pal_addr == {4'b0, grid[cy*GRID_W+cx]}`.
3. `video_on_q/hsync_q/vsync_q` are the inputs delayed by exactly 1 cycle.
4. Full-raster reconstruction equals `palette[grid[...]]` (pixel-exact), proving
   no transpose / off-by-one / mirror.

Final line: `TB tb_grid_scanout: N/N PASS`.

The end-to-end pixel-exact check on the *real* design (PLL + grid_mem + scanout +
palette) lives in `tb_top`, which also dumps `sim/out/vga_frame.txt` for a PNG.
