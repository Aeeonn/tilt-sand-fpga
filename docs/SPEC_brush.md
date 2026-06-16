# SPEC: brush — particle emitter / grid injector

## Purpose

Writes material cells into the back buffer between engine frames, giving the
user a way to spawn particles. In M4, the brush is a fixed-position emitter
(center of the grid) that injects one row of cells per frame when KEY[1] is
held. Future milestones may add cursor movement.

## Interface

```systemverilog
module brush #(
    parameter int GRID_W    = 320,
    parameter int GRID_H    = 240,
    parameter int CELL_BITS = 4
) (
    input  logic                 clk,
    input  logic                 rst_n,
    // control
    input  logic                 inject,      // 1 = brush active this frame
    input  logic                 clear,       // 1 = clear the entire grid
    input  logic [CELL_BITS-1:0] material,    // material to inject
    input  logic                 engine_busy, // engine is processing
    // grid_mem write port (shared with engine via mux in top)
    output logic                 wr_en,
    output logic [ADDR_BITS-1:0] wr_addr,
    output logic [CELL_BITS-1:0] wr_data,
    output logic                 busy,        // brush is writing
    output logic                 done         // 1-cyc: brush operation complete
);
```

## Behavior

### Injection mode (`inject` && !`clear`)

When `inject` is asserted and the engine is not busy, the brush writes a small
pattern of cells (a 3×3 square) at the emitter position (center-top of the
grid: x=160, y=10). Material is `material`.

Only writes EMPTY cells — does not overwrite existing material (non-destructive).
This means spawning into a full area does nothing (no duplication).

### Clear mode (`clear`)

When `clear` is asserted and the engine is not busy, the brush fills the entire
back buffer with EMPTY (0), then re-draws the WALL border. This resets the
simulation. Takes GRID_W*GRID_H + border cycles.

### Timing

The brush operates in the gap between engine frames. The sequence is:
1. Engine finishes (`frame_done`) → buffer swap at vsync
2. `swapped` fires → brush gets control if `inject` or `clear` is active
3. Brush writes (a few cycles for inject, ~77k for clear)
4. Brush asserts `done`
5. Engine starts the next frame

If neither `inject` nor `clear`, `done` fires immediately so the engine starts.

### Emitter position (M4)

Fixed at `(GRID_W/2, 10)` — top-center, inside the border. The 3×3 pattern
is: (cx-1..cx+1) × (cy-1..cy+1). Only writes to cells that are currently EMPTY
(reads not needed — just write unconditionally; mass conservation is maintained
because inject only adds to EMPTY cells which the engine treats as "nothing").

**Note on mass conservation**: The brush intentionally *breaks* strict
conservation — it's a material *source*. The particle count display makes this
visible. Conservation SVA in the engine remains valid (the engine itself never
creates/destroys); the brush is the only path that adds material.

## Verification

- `tb_brush`: small grid, verify inject writes correct cells, clear fills with
  EMPTY + WALL border, done signal timing, no writes when engine_busy.
