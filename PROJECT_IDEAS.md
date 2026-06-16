# "Wait, you fit that on a DE10-Lite?" — Project Dossier

Written 2026-06-10. Purpose: candidate "insane but plausible" FPGA projects for stress-testing
AI HDL agents on the Terasic DE10-Lite (MAX 10 10M50DAF484C7G), with rankings, a recommended
first build, and an implementation roadmap.

Toolchain on this machine: Quartus Prime Lite 23.1std.1 (`C:\intelFPGA_lite\23.1std`), which
bundles **Questa Intel FPGA Starter Edition** (needs the free license from Intel's
Self-Service Licensing Center). The project .qsf already carries DE10-Lite pin assignments for
CLK/SDRAM/VGA/HEX/LEDR/SW/KEY/GSENSOR; GPIO + Arduino header pins must be added from the
DE10-Lite manual when first needed. `rtl/` and `sim/` are currently empty; the .qsf references
deleted files and needs pruning at project start.

---

## 0. What you are actually working with

**FPGA — 10M50DAF484C7G (slowest -7/C7 speed grade):**
- 49,760 logic elements
- 1,638 Kbit M9K block RAM = **~204 KB total on-chip RAM** (182 blocks)
- **144 hardware 18×18 multipliers**
- 4 PLLs, on-die flash (UFM) for assets that survive power-cycling
- 12-bit 1 MSPS SAR ADC (channels on the Arduino header)

**Board:**
- 64 MB SDRAM, 16-bit bus, rated ~143 MHz (run it at 100 MHz with a phase-shifted clock; ~200 MB/s peak)
- VGA out, 4 bits/channel = 4,096 colors (resistor DAC)
- ADXL345 3-axis accelerometer on SPI (±16 g, up to 3.2 kHz sample rate, 2 interrupt pins)
- 6× seven-segment, 10 switches, 10 LEDs, 2 push buttons
- 2×40 GPIO header (36 I/O), Arduino Uno R3 header
- USB-Blaster II = **JTAG only — there is no onboard USB-UART**. Add a $3 CP2102/FT232 dongle
  on GPIO, or use JTAG paths (SignalTap, In-System Memory Editor, System Console w/
  JTAG-to-Avalon master, Virtual JTAG)
- **No audio codec** — a 1-bit 2nd-order delta-sigma DAC on a GPIO pin + RC filter gives
  surprisingly clean audio; that's a deliberate sub-project, not a hack
- No SD slot (SPI microSD breakout on GPIO if a project needs bulk storage)

**Budget intuitions that shape everything below:**
- BRAM **cannot** hold a 640×480 framebuffer (460 KB at 12 bpp). Real framebuffers live in
  SDRAM; BRAM holds line FIFOs, tiles, LUTs, caches, and small grids. 320×240 at 8 bpp
  (palette) in SDRAM, double-buffered, scanned out pixel-doubled is *the* house style.
- Display scanout + render writes for that house style ≈ 10 MB/s — **5% of SDRAM bandwidth**.
  Bandwidth is rarely the wall; SDRAM controller correctness and I/O timing are.
- 144 multipliers × 100 MHz = 14.4 GMAC/s theoretical. That is real DSP/3D/NN horsepower.
- 50K LE comfortably fits a pipelined 32-bit CPU + caches + VGA + SDRAM + a custom
  accelerator, with room to spare. The C7 grade means well-pipelined logic closes ~100 MHz;
  130+ takes effort.

---

## 1. The twelve

### 1. MAXenstein 3D — pure-hardware textured raycaster
- **Wow:** a textured, explorable Wolfenstein-style 3D world at a locked 60 fps — with zero CPU anywhere on the die.
- **What it does:** for each of 320 screen columns, a DDA engine walks a tile map, computes perpendicular wall distance, and draws a perspective-correct textured, distance-shaded wall column into a double-buffered SDRAM framebuffer. You walk the maze with buttons/tilt; sprites, doors, and pickups run as FSMs.
- **Why impressive on an FPGA:** raycasting is "software's algorithm"; recast as a synchronous pipeline (ray setup → DDA step → distance → reciprocal → texture fetch → column DMA) it renders every pixel every frame with cycle-deterministic timing — no GPU, no CPU, no frame drops, ever.
- **HDL subsystems:** PLL/clocking + reset; VGA timing gen; SDRAM controller + multi-port arbiter; scanline prefetch FIFO (CDC); fixed-point DDA stepper; reciprocal unit (LUT + Newton); texture BRAM + column sampler; column-fill DMA; sprite projector/sorter with per-column depth test; game FSM (movement, collision-slide, doors); ADXL345 SPI master; debounce; delta-sigma audio bleeper; UART debug monitor.
- **Peripherals:** VGA, SDRAM, KEY/SW, accelerometer, HEX (fps/HUD), LEDs, GPIO (UART + audio).
- **Difficulty:** 7/10 · **Fit risk: Low** (~15–25K LE all-in)
- **Main risks:** SDRAM I/O timing (phase-shifted clock + input/output delay constraints); arbiter starvation between scanout and render; fixed-point overflow at near-zero wall distances.
- **Simplified version:** untextured colored walls at 160×120 in BRAM — no SDRAM at all.
- **Stretch:** floor/ceiling casting, enemies with AI FSMs + hitscan, lightmaps, level streaming from UFM flash, two-board deathmatch over a GPIO serial link, SNES gamepad input.
- **AI benchmark value:** golden-model frame diffing at every stage (Python renders the same fixed-point math; testbench compares pixel-exact); broadest single-project coverage of math, memory protocol, CDC, real-time pipelines, and gameplay FSMs; every milestone is visible on a monitor.

### 2. Comanche-on-a-chip — voxel-space terrain flyover
- **Wow:** the famous 1992 *Comanche* heightmap renderer — smooth fly-over of fogged canyon terrain — running in silicon with the board tilted like a joystick.
- **What it does:** per screen column, marches a ray across a heightmap+colormap, drawing vertical terrain slabs front-to-back with distance fog; accelerometer = stick, buttons = throttle; palette tricks animate water and dusk.
- **Why impressive on an FPGA:** the algorithm is tiny but the memory system is the whole game — variable-length per-column loops over a big map turn into a streaming, row-locality-aware SDRAM access problem.
- **HDL subsystems:** the same VGA/SDRAM/framebuffer platform as #1; per-column ray walker; perspective divide unit; heightmap tile cache (BRAM); fog/palette blender; LFSR/value-noise generator for procedural maps; flight-dynamics FSM; accelerometer SPI.
- **Peripherals:** VGA, SDRAM, accelerometer, KEY/SW, HEX altimeter.
- **Difficulty:** 6/10 · **Fit risk: Low** (v1 with a 256×256 map lives entirely in BRAM)
- **Main risks:** random-access SDRAM latency per ray step once maps move off-chip (needs tile caching or row-sorted marching); fixed-point horizon stability.
- **Simplified version:** 256×256 BRAM map, 160×120 internal resolution.
- **Stretch:** procedurally infinite terrain (noise tiles generated on the fly), day/night cycle, missiles + particle effects, two-board race over GPIO.
- **AI benchmark value:** small algorithm, big architecture decisions — tests whether an agent reasons about latency/bandwidth rather than just writing correct RTL. Shares its platform with #1, so it's a cheap pivot or warm-up.

### 3. DOOM-class SoC — "it runs Doom"
- **Wow:** the board boots a RISC-V system you specified, loads DOOM1.WAD into SDRAM, and plays Doom on VGA with sound.
- **What it does:** RV32IM softcore (~100 MHz) with instruction/data caches, SDRAM main memory, memory-mapped framebuffer with palette, timer/IRQ, UART, SPI; `doomgeneric` ported on top; WAD loaded over UART/SPI-SD.
- **Why impressive on an FPGA:** it's a complete computer — CPU, caches, bus, DMA display, peripherals, toolchain, ported application — and Doom is the universally legible proof that all of it works at once. 64 MB SDRAM swallows the ~4 MB shareware WAD plus zone memory easily.
- **HDL subsystems:** CPU core (import VexRiscv/PicoRV32, or write your own RV32IM — "hard mode"), I$/D$ caches, Wishbone/AXI-lite interconnect, SDRAM controller, framebuffer DMA + palette, interrupt controller/timer, UART, SPI master, delta-sigma audio; on the SW side: linker script, startup code, board support layer.
- **Peripherals:** VGA, SDRAM, GPIO (UART dongle / microSD / PS/2 keyboard), KEY/SW, audio GPIO, HEX.
- **Difficulty:** 9/10 (dominated by integration + software) · **Fit risk: Medium** (10–20K LE; the risk is timing at 100 MHz and bring-up, not area)
- **Main risks:** cache/SDRAM corner cases (the classic "passes simulation, corrupts under sustained load"); GCC/newlib toolchain yak-shaving; reaching playable frame rates.
- **Simplified version:** run Tetris/Snake in C first; Doom at 160×100 stretched; use a proven open core instead of a homebrew one.
- **Stretch:** write the CPU yourself with a branch predictor; add a hardware blitter; OPL2-style FM music core; save games to UFM.
- **AI benchmark value:** the full-stack test — RTL, bus protocols, C porting, build systems, performance debugging. Long feedback loops make it a capstone rather than a starter.

### 4. PPU-1 — a from-scratch fantasy console
- **Wow:** a complete invented game console — custom PPU, APU, DMA, gamepads, and its own written "programmer's manual" — running games built for it.
- **What it does:** SNES-lite scanline PPU (two scrolling tilemap layers, 64 sprites with per-line limits, 256-color palettes, raster IRQs for wobble/gradient effects), 8-voice wavetable/FM APU, OAM DMA, small softcore running game code from SDRAM "cartridges" loaded over UART.
- **Why impressive on an FPGA:** consoles are the apex of "many hard-real-time subsystems agreeing about every cycle" — raster effects only work if PPU, CPU, DMA, and bus arbitration are cycle-exact.
- **HDL subsystems:** PPU fetch pipeline + sprite evaluator + priority/palette mux; APU mixer/envelopes; DMA engine; VRAM/OAM/CGRAM BRAM banks with arbitration; CPU + bus; gamepad shift-register reader (SNES pads are a 3-wire protocol, $4); boot ROM; UART cart loader.
- **Peripherals:** VGA, audio GPIO, GPIO gamepads, SDRAM, UART, HEX debug.
- **Difficulty:** 8/10 · **Fit risk: Medium** (~20–30K LE with CPU)
- **Main risks:** sprite-per-line evaluation timing; CPU/DMA/PPU bus arbitration; unbounded scope creep (consoles grow features forever).
- **Simplified version:** one background layer + 16 sprites, pure-HDL pong/shmup instead of a CPU.
- **Stretch:** Mode-7-style affine layer (DSP multipliers), HDMA gradients, save RAM in UFM, a second controller, a demoscene "cartridge."
- **AI benchmark value:** the agent must *author its own spec* (register map, memory map, timing diagrams) and then stay consistent with it across modules — directly tests architecture discipline and documentation, the thing agents are weakest at.

### 5. DMG-MAX — Game Boy hardware clone
- **Wow:** real, unmodified Game Boy ROMs running on logic you wrote — graded automatically by the community's brutally precise accuracy test suites.
- **What it does:** SM83 CPU, cycle-accurate PPU (mode timing, pixel-FIFO fetcher), 4-channel APU, timers/interrupts/OAM-DMA, MBC1/MBC3 cartridge banking from SDRAM-loaded ROMs, 4× upscale to VGA, delta-sigma audio, buttons or SNES pad as the joypad.
- **Why impressive on an FPGA:** software emulators can hide timing sins behind abstraction; in hardware, the real timing *is* the design. Passing blargg/mooneye means matching 1989 silicon cycle-for-cycle.
- **HDL subsystems:** SM83 core + control; PPU FIFO fetcher + sprite engine + LCD timing; APU (square/wave/noise, envelopes, frame sequencer); OAM DMA; MBC mappers; SDRAM ROM cache; upscaler; delta-sigma DAC; UART ROM loader; save-RAM persistence to UFM.
- **Peripherals:** VGA, SDRAM, audio GPIO, KEY/SW or GPIO pad, UART.
- **Difficulty:** 9/10 · **Fit risk: Low–Medium** (~12K LE; BRAM use is small)
- **Main risks:** mid-scanline register-write behavior in the PPU; obscure APU edge cases; use homebrew/test ROMs and your own cartridge backups.
- **Simplified version:** "GB-ish" relaxed-timing mode that runs homebrew; skip serial and Game Boy Color.
- **Stretch:** GBC support, link cable between two boards over GPIO, fast-forward, palette shaders.
- **AI benchmark value:** **the best objective scoring available anywhere** — blargg/mooneye/dmg-acid2 give pass/fail ground truth at every step and run fully in simulation, so an agent's progress is a measurable score curve, not a vibe.

### 6. TinyQuad — a real 3D rasterizer GPU
- **Wow:** a spinning, flat/Gouraud-shaded, z-buffered Stanford bunny pushed through an honest geometry + raster pipeline small enough to read end to end.
- **What it does:** vertex fetch → 4×4 fixed-point matrix transform (DSP-heavy) → frustum clip → perspective divide → backface cull → half-space triangle rasterizer with depth test → framebuffer; models in flash/SDRAM; accelerometer rotates the model; switches toggle pipeline stages live.
- **Why impressive on an FPGA:** it is the actual GPU lineage — geometry engine + raster backend + depth buffer — at a millionth of a modern GPU's budget, and every stage is inspectable.
- **HDL subsystems:** matrix MAC array; divider/reciprocal units; clipper FSM (the dragon); edge-function rasterizer with tile stepping; z-buffer manager (tile z in BRAM or z in SDRAM); framebuffer DMA; vertex fetch + command FIFO; fps counter.
- **Peripherals:** VGA, SDRAM, accelerometer, SW (mode toggles), HEX (fps/tri count).
- **Difficulty:** 8.5/10 · **Fit risk: Medium** (multiplier-rich; z-bandwidth needs tiling)
- **Main risks:** clipping correctness (historically the most bug-dense unit in graphics); z-buffer bandwidth (a full-res 16-bit z is 150 KB — tile it); screen-space fixed-point precision in edge functions.
- **Simplified version:** wireframe-only (Bresenham) with painter's sort, ~100 triangles.
- **Stretch:** textured triangles, two light sources, OBJ upload over UART, 10K-triangle scenes, microcoded "vertex shader."
- **AI benchmark value:** dense arithmetic correctness + pipeline hazard management, verified per-stage against a software rasterizer — tests whether an agent can decompose a textbook pipeline into individually provable silicon stages.

### 7. SDF Shadertoy machine — real-time ray marcher
- **Wow:** animated raymarched scenes — the kind that normally need a GPU fragment shader — glowing on VGA from bare LUTs and DSP blocks.
- **What it does:** a deeply pipelined sphere-tracing core evaluates a procedural signed-distance scene (spheres, boxes, domain repetition, folds) ~16–32 steps per ray, computes normals by gradient, applies Phong + fog, renders 320×240 at 15–40 fps into SDRAM while LFOs animate scene parameters.
- **Why impressive on an FPGA:** ~50–100M SDF evaluations/s of fixed-point vector math, structured as one deep pipeline that rays *recirculate* through (throughput = f_clk / step_count) — a fragment shader frozen into silicon, eating a big slice of the 144 multipliers.
- **HDL subsystems:** ray generator; SDF evaluator pipeline (vector ALU: min/max/abs/mod/fold); fixed-point rsqrt + normalize; ray recirculation FIFO + loop control; shading unit; framebuffer DMA; parameter LFO/sequencer; scene-select mux.
- **Peripherals:** VGA, SDRAM, SW (scene select), accelerometer (camera), optional ADC audio-reactivity.
- **Difficulty:** 9/10 · **Fit risk: Medium–High** (multiplier and LE hungry; needs disciplined resource sharing)
- **Main risks:** Q-format range/precision across folds (number-format design *is* the project); recirculation deadlock/starvation; frame-rate cliffs as scenes grow.
- **Simplified version:** 2D SDF scenes (metaballs, neon signs) full-screen at 60 fps — still gorgeous, far cheaper — or 3D at 160×120.
- **Stretch:** soft shadows (second march), screen-space AO approximation, beat-synced scene morphs from audio input, a "shader bytecode" interpreter so new scenes don't require resynthesis.
- **AI benchmark value:** numerical architecture under a hard resource budget — Q-format reasoning, pipeline scheduling, and multiplier sharing, verified against a float golden model with explicit error bounds.

### 8. MAX-TRACKER — 32-voice FM synth workstation
- **Wow:** a 32-voice FM synthesizer + sample-accurate hardware sequencer playing chiptunes through a homemade 1-bit DAC, with a live oscilloscope/spectrum light show on VGA — a self-contained music computer with no CPU.
- **What it does:** DX7-style 4-operator FM voices time-multiplexed through one operator pipeline at 48 kHz (128 operators needed, 8× headroom at 50 MHz); ADSR envelopes, LFOs, mod matrix; pattern-based tracker sequencer from flash/SDRAM; SDRAM delay/chorus; VGA shows waveform, 1024-point FFT spectrum, and the pattern grid; switches/keys are transport + live jam controls; tilt = filter wah.
- **Why impressive on an FPGA:** audio rates are so slow for an FPGA that you can afford absurd polyphony with sample-exact determinism — and the whole signal chain (synthesis → FX → sigma-delta modulator) is yours down to the bit.
- **HDL subsystems:** phase-accumulator + sine-LUT operator core; envelope FSMs; voice scheduler; mod-matrix; state-variable filter; SDRAM delay-line DMA; 2nd-order delta-sigma modulator; tracker sequencer FSM; streaming FFT; scope/spectrum/UI compositor; font ROM.
- **Peripherals:** GPIO audio (RC filter), VGA, SDRAM, SW/KEY, accelerometer, HEX (BPM), UART (MIDI-over-serial stretch).
- **Difficulty:** 7/10 · **Fit risk: Low**
- **Main risks:** delta-sigma quality on a noisy GPIO pin (grounding/filtering); sequencer timing jitter if anything isn't sample-locked; UI scope creep.
- **Simplified version:** 8 voices, one hardcoded song, scope-only visualizer.
- **Stretch:** real MIDI-in via optoisolator, audio-in FX mode (ADC → reverb/delay → out = guitar pedalboard), wavetable upload over UART, generative Euclidean-rhythm mode in hardware.
- **AI benchmark value:** DSP correctness is bit-exactly checkable against numpy golden models (FFT, filters, envelopes), and any sample-drop bug is *audible* — a different verification muscle than graphics, plus hard steady-streaming design.

### 9. PETRI-50 — reaction-diffusion / Lenia life tank
- **Wow:** a living, breathing colony of continuous-math organisms evolving at hundreds of generations per second — a desk pet made of differential equations.
- **What it does:** full-screen Gray-Scott reaction-diffusion in fixed point on a 320×240 grid (SDRAM ping-pong state, ~250 generations/s), false-color palette animation; tilting the board stirs the dish; switches sweep feed/kill parameters live through the whole pattern zoo (spots, stripes, mitosis, coral). Stretch: Lenia — continuous Life with 27×27 radial kernels.
- **Why impressive on an FPGA:** it's a SIMD-supercomputer access pattern — a line-buffered stencil pipeline sustaining ~10⁸ cell-updates/s — at a density a desktop CPU genuinely struggles to match in real time.
- **HDL subsystems:** stencil line buffers; fixed-point Laplacian/convolution datapath (DSP); double-buffered SDRAM state streamer; parameter controller; palette mapper; seeding/stir injector tied to the accelerometer; frame compositor.
- **Peripherals:** VGA, SDRAM, accelerometer, SW/KEY.
- **Difficulty:** 6.5/10 (Lenia: +2) · **Fit risk: Low–Medium** (Lenia: Medium–High — kernel decomposition cleverness required)
- **Main risks:** fixed-point PDE stability (saturation/clamping discipline); read-modify-write streaming order in SDRAM; Lenia's kernel bandwidth.
- **Simplified version:** classic Game of Life at thousands of generations/s full-screen with stochastic reseeding — still hypnotic.
- **Stretch:** Lenia (continuous artificial life — virtually nobody has put it in silicon), multi-species, a parameter-map mode where x/y screen position = feed/kill so the entire phase diagram lives on screen at once (the killer visual).
- **AI benchmark value:** stencil dataflow + numeric stability, with a 10-line numpy golden model — the cleanest possible instrument for "did the agent get fixed-point arithmetic actually right."

### 10. TILT-SAND — falling-sand physics toy
- **Wow:** a 76,800-cell powder-game sandbox (sand, water, oil, fire, acid, plant) that obeys the *physical tilt of the board* — pour, burn, and flood with your hands.
- **What it does:** a cellular-automaton materials engine updates every cell 60×/s with material-pair interaction rules and stochastic spread; the accelerometer rotates gravity; switches select the material, buttons spawn it; full-color VGA; HEX shows live particle count.
- **Why impressive on an FPGA:** software powder games are serial and chug at this scale — the FPGA updates the entire grid every frame, deterministically, double-buffered, with zero CPU; the tilt input makes the silicon feel alive.
- **HDL subsystems:** dual-buffer cell memory (BRAM at 4 bpp, SDRAM for bigger grids); direction-aware serpentine/Margolus update FSM; material interaction rule engine; LFSR PRNG; brush injector; palette renderer; accelerometer SPI + gravity quantizer.
- **Peripherals:** VGA, accelerometer, SW/KEY, LEDs (material indicator), HEX, optionally SDRAM.
- **Difficulty:** 6/10 · **Fit risk: Low**
- **Main risks:** update-order artifacts (left/right bias — alternate sweep direction or use Margolus blocks); rule-table explosion as materials multiply; diagonal-gravity correctness is genuinely subtle.
- **Simplified version:** sand + water + wall, gravity fixed down.
- **Stretch:** pressure/temperature fields, electricity + logic-gate materials (build circuits *inside* the sandbox — CA-ception), save/load dishes to UFM, two boards linked into one tall vessel over GPIO.
- **AI benchmark value:** rule-engine design with emergent behavior — the agent must write testable local rules and then verify *global invariants* (mass conservation across update passes) in simulation; assertion-driven verification shines.

### 11. MAXNET-1 — a neural inference engine you doodle on
- **Wow:** draw a digit on screen by tilting the board — a quantized neural network *in silicon* classifies it in under 100 µs and renders live confidence bars while you draw.
- **What it does:** tilt/button drawing canvas (28×28, upscaled on VGA) feeds an INT8 MLP (784→128→10) or small CNN on a pipelined MAC array; weights trained offline in PyTorch, quantized, streamed from SDRAM/UFM; per-class confidence bars + argmax on HEX, reclassifying continuously.
- **Why impressive on an FPGA:** not AI hype — an honest fixed-function MAC engine at a few GMAC/s with end-to-end quantization done correctly, at ~1000× lower latency than calling a framework.
- **HDL subsystems:** MAC array + accumulators; weight DMA/streamer; requantize/ReLU units (scale-shift-saturate); layer sequencer; drawing canvas BRAM + box-filter downsampler; confidence-bar renderer; UART weight loader; golden-vector self-test mode.
- **Peripherals:** VGA, accelerometer, SDRAM/UFM, KEY/SW, HEX, UART.
- **Difficulty:** 7.5/10 · **Fit risk: Low–Medium**
- **Main risks:** quantization accuracy collapse without calibration discipline; MAC utilization/scheduling; off-by-one in requant shifts (the classic *silent* killer).
- **Simplified version:** accelerometer gesture classifier (tiny 1-D conv net, 8 gestures → HEX) — no canvas needed.
- **Stretch:** small CNN, top-3 softmax display, audio keyword spotting through the ADC (MFCC pipeline — hard mode), doodle-class model ("cat or house?").
- **AI benchmark value:** forces a complete ML-to-RTL flow — training script → quantization → golden vectors → RTL — where the agent must keep two codebases (Python and Verilog) *provably bit-identical*. Catches hand-waving instantly.

### 12. DEEP MAX — Belle-style hardware chess engine
- **Wow:** the board itself plays chess — combinational move generation and a hardware alpha-beta searcher examining millions of positions per second, Bell Labs' Belle (1983) reborn on a $90 board.
- **What it does:** a parallel 64-square attack/move-generation network produces legal moves in ~1 cycle; an iterative-deepening alpha-beta FSM with its stack in BRAM and a Zobrist-hashed transposition table in SDRAM searches; material + piece-square evaluation runs in DSPs; play it via a VGA board UI with switch/key cursor, or over UART speaking UCI-lite to a PC GUI.
- **Why impressive on an FPGA:** move generation — the bottleneck of every software engine — becomes a flat parallel circuit; this is the most famous custom-hardware lineage in computing history (Belle → Deep Thought → Hydra) at hobby scale.
- **HDL subsystems:** board state registers; attack/move network; move sorter (MVV-LVA); search FSM + BRAM stack; make/unmake incremental update; eval datapath; transposition table + Zobrist hashing; UART/UCI interface; VGA board renderer; chess clock on HEX.
- **Peripherals:** UART, VGA, SDRAM, KEY/SW, HEX (depth/eval).
- **Difficulty:** 9/10 · **Fit risk: Medium–High** (the attack network is LE-hungry; budget 15–25K LE)
- **Main risks:** legal-move corner cases (castling rights, en passant, pins — chess is a minefield); search FSM complexity; fitting the move network.
- **Simplified version:** a perft-only "move-generator correctness machine" + plays-legal-greedy chess; or 5×5 minichess.
- **Stretch:** quiescence search, opening book in flash, calibrated Elo matches vs depth-limited Stockfish, pondering on the opponent's time.
- **AI benchmark value:** **perft** gives exact, famous ground truth (perft(6) from the start position = 119,060,324 nodes — one number, no ambiguity) for a deeply combinational design plus a gnarly FSM; the all-digital feedback loop (UART, no monitor needed) makes iteration fast.

---

## Lightning round (seeds worth keeping)

- **SERV swarm:** 16× bit-serial RISC-V cores (~300 LE each!) on a NoC mesh, parallel-raytracing screen tiles — "a 16-core cluster on a MAX 10." (9/10, Medium)
- **Lab-on-board:** 16-ch 100 MS/s logic analyzer + 1 MSPS analog scope, 64 MB capture depth, VGA waveform UI, trigger engine — the instrument that then debugs every other project here. (7/10, Low)
- **N-body galaxy:** ~2,000 stars, O(N²) pipelined gravity with LUT+Newton rsqrt at 20–30 fps, phosphor-trail rendering in SDRAM, tilt = god-hand. (7/10, Low–Medium)
- **Video feedback synthesizer:** previous frame → affine resample + color rotation → next frame; IIR video feedback = infinite psychedelic tunnels; audio-reactive via ADC. (6.5/10, Medium)
- **Phosphor vector display:** simulate an analog vector CRT (beam dynamics, decay) in an SDRAM accumulation buffer; render Lissajous figures and wireframe "laser shows." (6/10, Medium)
- **Mandelbrot deep-zoom:** 8–16 parallel 64-bit fixed-point iterator pipelines, smooth coloring, auto-zoom bookmarks — outruns a 2005 desktop. (6/10, Low)
- **J1 Forth machine:** a ~200-line stack CPU + VGA terminal + flash filesystem = a self-hosted interactive computer where you live-poke hardware registers from a keyboard. (7/10, Low)
- **Pedalboard:** ADC line-in → hardware reverb/delay/pitch FX → delta-sigma out, scope + spectrum UI. Needs a simple input bias circuit. (7/10, Low–Medium)

---

## Rankings

### Most impressive but still plausible
1. **DOOM-class SoC** — the universally legible flex; proven feasible on this hardware class; the risk is integration effort, not physics.
2. **DMG-MAX Game Boy clone** — real ROMs running, with test-suite receipts to prove accuracy.
3. **SDF Shadertoy machine** — looks flatly impossible without a GPU; medium-high fit risk is the price of the gasp.
4. **PPU-1 fantasy console** — an entire invented console, manual and all.
5. **MAXenstein 3D** — instantly recognizable, runs at full frame rate, and is entirely yours.

### Best for testing an AI HDL agent
1. **DMG-MAX** — blargg/mooneye/dmg-acid2 run in simulation and emit pass/fail: an objective score curve for agent progress. Nothing else comes close for measurability.
2. **MAXenstein 3D** — golden-model pixel diffs at every milestone, broad subsystem coverage, short feedback loops, no software-toolchain detours.
3. **DEEP MAX chess** — perft is exact ground truth for brutally hard combinational + FSM reasoning, with an all-digital iteration loop.
4. **PPU-1** — uniquely tests spec authorship and multi-module consistency over a long horizon.
5. **MAXNET-1** — cross-language bit-exactness (PyTorch ↔ RTL) catches quantization hand-waving immediately.
(Honorable: DOOM SoC as the eventual full-stack capstone.)

---

## Recommendation: start with MAXenstein 3D

Reasons, in order:
1. **Pure HDL stress with no detours** — every hard thing is a hardware thing (SDRAM timing, CDC, fixed-point, arbitration, real-time pipelines). No GCC, no linker scripts, no "is the bug in the C port?"
2. **Every milestone is visible** — on the monitor, and *before that* as a PPM image rendered by the testbench. An agent (and you) can literally look at what the hardware thinks a frame is.
3. **Its platform is the substrate for half this list** — M0–M2 below (clocks + VGA + SDRAM + framebuffer + debug rig) is exactly what Comanche, TILT-SAND, PETRI-50, the raymarcher, and the rasterizer need. Nothing is wasted if you pivot.
4. **Failure modes decompose** — when a frame is wrong you can binary-search the pipeline stage by stage against the golden model.
5. **It reliably exposes the five classic AI-agent failure modes:** SDRAM I/O timing, clock-domain crossing, fixed-point overflow, arbiter starvation, and frame pacing — while still being a project that has been proven shippable on boards of this class.

### Roadmap

**M0 — Skeleton + debug rig ("hello, silicon")**
- RTL: prune dead file references from the .qsf; PLL (50 MHz in → 100 MHz system, 100 MHz −3 ns for SDRAM clock-out, 25 MHz pixel) + reset synchronizers; VGA timing generator (640×480@60 from 25 MHz — works on essentially all monitors) + test pattern; debounce; UART TX/RX + a tiny peek/poke register monitor protocol; HEX driver; heartbeat LED.
- Testbenches: VGA timing checker (assert exact sync widths, porches, frame period); UART loopback at-baud; debounce unit test.
- Verified in sim before hardware: hsync/vsync counts exact to the pixel; UART framing.
- Hardware: monitor shows the pattern; UART echo via dongle (until it arrives, In-System Sources & Probes over JTAG substitutes for buttons/readouts).
- Done when: pattern on screen, peek/poke works, SDC exists with all clocks + CDC false paths, timing report clean.

**M1 — SDRAM controller + verification harness (highest risk → earliest)**
- RTL: init sequencer, refresh scheduler (one AUTO REFRESH per 7.8 µs), CL3 burst read/write, simple request/grant user interface; built-in self-test FSM (PRBS addresses/data) reporting pass/fail + error counts to LEDs/HEX/UART.
- Testbenches: run against the vendor SDRAM behavioral model (Micron/ISSI) in Questa; SVA protocol checkers for tRCD/tRP/tRFC/refresh interval; randomized stress with a scoreboard.
- Verified in sim: full init; 10K+ random ops, zero scoreboard misses; no timing-parameter assertion ever fires.
- Hardware: BIST clean for hours, not minutes; SignalTap captures of init + first bursts; sweep PLL phase to find the data-valid eye, then lock it into the SDC (`set_input_delay`/`set_output_delay` against the shifted clock).
- Done when: overnight BIST = 0 errors and timing closes at 100 MHz.

**M2 — Framebuffer pipeline (the platform ships)**
- RTL: 2-port arbiter (scanout strictly above render, with a starvation bound); scanline prefetch FIFO crossing into the pixel domain (async FIFO, CDC done once, properly); 320×240@8 bpp double buffer in SDRAM; palette BRAM → 12-bit VGA; vsync-latched buffer swap; a test-pattern DMA writer (moving gradient) to prove tear-free swapping.
- Testbenches: arbiter fairness under a saturating writer — assert the scanout FIFO **never** underruns (this is *the* invariant of the whole project); FIFO gray-code CDC checks; full-frame dump → PPM → byte-diff against golden.
- Hardware: animated gradient, zero tearing; SignalTap watches minimum FIFO occupancy over minutes.
- Done when: min-occupancy > 0 under worst-case synthetic write load, frames pixel-exact in sim.

**M3 — Raycast core, flat-shaded**
- RTL: per-column ray setup from 1024-entry sin/cos BRAM LUTs; DDA stepper against a 64×64 map in dual-port BRAM; perpendicular-distance computation; reciprocal unit (BRAM LUT + one Newton-Raphson step); column painter DMA (solid colors, N/S vs E/W shading, distance darkening). Suggested formats: Q12.12 positions, Q4.12 ray slopes — but deciding and *documenting* the Q-formats is part of the milestone.
- Golden model: a Python raycaster using the **same fixed-point arithmetic** (not floats), dumping per-column records (hit cell, side, distance, height) and full frames.
- Testbenches: 1,000 random poses, per-column bit-exact compare; full-frame render in Verilator → PPM diff == 0.
- Hardware: orbit-the-map attract mode, then free walk.
- This is where Q-format bugs surface; budget real time for it.

**M4 — Textures + movement**
- RTL: 8× 64×64 8-bit textures in BRAM (32 KB); column sampler (u from wall-hit fraction with the side-dependent flip, v stepped in fixed point — the off-by-one farm); movement FSM with collision slide; rotation via the sin/cos LUTs; accelerometer tilt-turn as an alternate control.
- Testbenches: texture addressing vs golden frames (this catches the u-flip and v-rounding bugs); collision unit tests (can't clip corners, sliding works).
- Hardware: textured world, 60 fps lock, fps on HEX.

**M5 — Sprites, doors, HUD, audio**
- RTL: sprite camera-transform + projection; per-column depth test against a 320×16-bit wall-distance buffer; transparent column runs; door FSMs mutating the map (dual-port BRAM earns its keep); HUD overlay compositor; delta-sigma bleeper SFX; attract/demo mode.
- Testbenches: sprite occlusion golden frames (sprite half-behind a wall edge); door FSM liveness (never wedges shut).
- Hardware: it's a game now. Demo it.

**M6 — Stretch tier (each a mini-benchmark of its own)**
Floor/ceiling casting (per-pixel perspective — significantly heavier math), enemies with AI FSMs + hitscan combat, level streaming from UFM, an FM jingle (steal project #8's operator core), SNES pad input, two-board deathmatch over a GPIO UART link.

### Verification strategy (the meta-deliverable for agent testing)

- **Golden-model discipline:** every math module gets a bit-exact Python reference using identical Q-formats; frame-level PPM diffs gate every merge. "Close enough" is banned — diffs are zero or it's a bug with a name.
- **Two-simulator stack:** **Verilator** for the inner loop (fast full-frame renders, CI regressions, image diffs — a frame of this design simulates in seconds) and **Questa** for what Verilator can't do well: the vendor SDRAM model and concurrent SVA protocol assertions.
- **Assertions everywhere:** FIFO never-underrun/overflow, arbiter starvation bounds, SDRAM timing parameters, CDC handshake protocols. Optionally SymbiYosys formal on the async FIFO and arbiter — cheap and high-value.
- **Self-checking hardware:** switch-selectable BIST modes (memory test, color bars, sprite test), fps and minimum-FIFO-occupancy reported on HEX/UART. Agents need observability; build the board to testify about itself.
- **On-chip debug:** SignalTap (trigger on assertion-style failure pulses like a FIFO underrun); In-System Memory Content Editor to poke the map/palette live over JTAG; a JTAG-to-Avalon master + System Console gives *scripted* (TCL) memory peek/poke with **zero extra hardware** — maximally agent-friendly; plus the UART monitor once the dongle arrives.
- **Quartus practice:** complete SDC from M0 (all clocks, SDRAM I/O delays, CDC false paths); Timing Analyzer must be clean at every milestone — reading timing reports is part of the benchmark; track LE/M9K/DSP usage per milestone in a table in the repo.

### Suggested repo shape

```
rtl/        platform/ (pll, vga, sdram, fifo, arbiter, uart, dsdac)
            raycast/  (dda, recip, column, sprite, game_fsm)
sim/        tb/ (per-module SV testbenches)  golden/ (python models)
            verilator/ (frame-render harness, ppm diff)
fpga/       quartus project, qsf (reuse existing pin block), sdc
tools/      image/map/texture converters, regression runner
docs/       SPEC.md per module — written *before* the RTL
```

**Agent contract** (what makes this a benchmark rather than a vibe): no module merges without its spec section, golden model, self-checking testbench, and assertions; CI = Verilator regression + image diffs; Quartus timing clean at every milestone.

### Sequel order

MAXenstein (platform + game) → keep the platform and pivot to **PETRI-50 or TILT-SAND** (fast wins on the same substrate) → **MAX-TRACKER** (different verification muscle: audio/DSP) → **DMG-MAX** (objective accuracy scoring) → **DOOM SoC** (full-stack capstone). That sequence stresses essentially every skill an HDL agent can have, with measurable outcomes at every step.
