# PLAN: Option A — Velocity-State Water (momentum, waves, rise)

Status: **IMPLEMENTED** (2026-06-18). See `docs/STATUS.md` →
"Velocity-state water" for the as-built summary and results. This plan is
retained as the design record. Notable deltas from the original plan:
- The rule needed **6 phases** (added explicit *rise* and *cohesive repack*),
  split across **three** pipeline stages (new `block_rule_flow` module) rather
  than two — the deeper rule and 3-stage split actually *improved* STA slack.
- **4-gravity momentum was kept** (not deferred): storing tags in the canonical
  frame and rotating with the block gives correct slosh under all gravities.
- Exhaustive vectors grew to **20736** (6⁴×4 gravities×4 rnd); the rule uses
  two LFSR bits (`r0`, `r1`).
Fallback / rollback point: commit `a35bfec` (throttled leveling).

---

## 1. Goal & success criteria

Today's water is a memoryless downhill relaxation: it has **no momentum**, so it
cannot overshoot equilibrium (no waves) and cannot move upward (no level
equalization). This was confirmed empirically (slosh probe: 0 overshoots; U-tube
probe: right side rose to height 1 vs left's 14).

Option A gives each water cell a **horizontal momentum tag**. A prototype
(`sim/golden/_proto_a.py`) already produced genuine sloshing on the *unchanged*
Margolus engine: tilt swung `+7.5 → +0.7 → −7.5 → +7.5` (4 overshoots), mass
conserved.

**Done when:**

1. A released asymmetric slab **oscillates left↔right, overshooting level**, and
   the amplitude **decays over time** to flat (tunable energy loss).
2. Water can **rise**: a U-tube / communicating-vessels fill equalizes levels
   (right side climbs, not stuck at height 1).
3. Water still **looks like a cohesive blue liquid** (no gas dispersal).
4. **Mass conserved** under the new grouped invariant (below).
5. **Engine, memory, CDC, and display pipeline unchanged.** No BRAM growth.
6. Full regression green: exhaustive `tb_block_rule`, `tb_margolus_engine`,
   `tb_top`, Quartus 0 errors, STA closed.

**Explicit non-goals (MVP):** true incompressible pressure, vertical momentum
columns, and full 4-gravity momentum (see §6 for the gravity limitation and the
planned follow-up).

---

## 2. Encoding decision (4-bit cells — NO memory growth)

The cell stays **4 bits**. Water becomes a 3-member family sharing one color:

| ID | Name | Meaning | Palette |
|----|------|---------|---------|
| 3 | `WATER`   | still / no horizontal momentum | blue `34f` |
| 4 | `WATER_R` | moving **right** (+x) | blue `34f` |
| 5 | `WATER_L` | moving **left**  (−x) | blue `34f` |

`is_water(m) = (m >= 3 && m <= 5)` — a tidy synthesizable range check; the whole
family has density 1 and is mobile.

**Why this encoding:**

- **No BRAM increase** — cells stay 4-bit, memory stays at 37 %. The engine,
  `grid_mem`, `grid_scanout`, `brush`, `particle_count`, and HUD widths are all
  untouched (they're parameterized on `CELL_BITS`, which does not change).
- Palette: set entries 4 and 5 to the same blue as 3 → moving water is visually
  identical to still water. One-line change in `sand_materials.py`.
- `brush` injects still `WATER` (ID 3) exactly as today; `SW[5:2]` material
  select is unaffected (still picks ID 3).
- `particle_count` counts `cell != EMPTY` → moving water is non-empty, still
  counts correctly. No change.

**Tradeoff (accepted, documented):** IDs 4 and 5 were aspirational `OIL`/`FIRE`
in the M7 roadmap (unstarted, stretch). We reclaim them for water velocity and
shift those reactive materials to later IDs when M7 begins. `sand_materials.py`
(the source of truth) is updated accordingly with a comment.

**Alternative considered & rejected — widen cell to 6 bits** (`material[3:0]` +
`vel[5:4]`): keeps all 16 material IDs free, but **BRAM 37 % → ~55 %** and forces
palette-address masking plus re-verification of every `CELL_BITS`-parameterized
module. Not worth it for the MVP; revisit only if the M7 material budget gets
tight.

---

## 3. Physics — the new block rule (canonical-DOWN frame)

Operate on the rotated block `a=TL b=TR c=BL d=BR` as today. Phases, in order
(each a conservative permutation of the *grouped* materials):

1. **Vertical fall** (unchanged): heavier sinks by density. A water cell that
   moves vertically is **neutralized to still `WATER`** (vertical motion sheds
   horizontal momentum).
2. **Advection** (new, the wave carrier): a moving-water cell glides into an
   adjacent `EMPTY` in its travel direction, **keeping its tag**:
   `WATER_R · EMPTY → EMPTY · WATER_R`, and mirror for `WATER_L`. Ballistic →
   overshoots equilibrium.
3. **Reflection** (new, makes the wave return): moving water blocked by a
   non-empty cell **reverses**: `WATER_R` hitting something → becomes `WATER_L`,
   and mirror. This is the bounce off a wall / the far water mass.
4. **Acceleration** (new, starts the slosh): a **still** `WATER` on a ledge
   (supported below, `EMPTY` to one side) gains momentum toward the gap →
   becomes `WATER_R`/`WATER_L`. Converts height/potential into horizontal motion.
5. **Damping** (new, the energy loss): when opposing flows meet head-on
   (`WATER_R` next to `WATER_L`) or a moving cell is fully blocked, decay to
   still `WATER` **gated by `rnd`** (so it loses energy gradually, not instantly).
   `rnd` rate sets the decay envelope — this is the main realism tuning knob.

"Supported below" within the block = the cell beneath is non-empty. Across block
boundaries the Margolus phase alternation handles coupling, exactly as the
current rule relies on.

The prototype implements 1–4 with weak 5; the production rule will **tune
damping** (§7) so waves visibly lose energy and settle.

---

## 4. Conservation invariant (changes — important)

Strict multiset equality **no longer holds** (a `WATER` may become `WATER_R`).
The new invariant is **grouped**:

- `count(EMPTY)`, `count(WALL)`, `count(SAND)`, and every other non-water ID are
  individually preserved, **and**
- `count(WATER) + count(WATER_R) + count(WATER_L)` is preserved.

This must be updated in:

- `sim/golden/block_rule.py` — `check_conservation()` compares grouped counts;
  the exhaustive generator asserts the grouped invariant.
- `sim/tb/tb_block_rule.sv` — the in-TB conservation check folds IDs 4 and 5
  into the water bucket before comparing.
- `sim/tb/tb_margolus_engine.sv` — the multi-frame "mass" count already counts
  `!= EMPTY`, which still holds; add a grouped-water check for rigor.

---

## 5. File-by-file change list (no new RTL modules)

**RTL (physics only; engine/memory/display untouched):**

- `rtl/sand/block_rule_fall.sv` — recognize the water family (range check);
  add advection + acceleration; neutralize tag on vertical move. Carries `rnd`.
- `rtl/sand/block_rule_settle.sv` — reflection + `rnd`-gated damping (replaces
  the throttled-level phase; leveling becomes implicit in advection/damping).
- `rtl/sand/block_rule.sv` — wrapper unchanged in structure; just re-documents
  the new phases. Rotation logic unchanged (tags are world-horizontal; see §6).
- `rtl/sand/margolus_engine.sv` — **no structural change**; still feeds
  `lfsr_rnd[0]` to both stages. (If timing needs a 3rd stage, see §8.)

**Palette / materials:**

- `sim/golden/sand_materials.py` — relabel IDs 4,5 as `WATER_R`,`WATER_L` with
  blue color; note the OIL/FIRE deferral. Regenerate `sand_palette.mem`.

**Golden model:**

- `sim/golden/block_rule.py` — implement phases 1–5; grouped conservation;
  regenerate `block_rule_vectors.mem` (now 6 materials → 6⁴·4·2 = **10 368**
  vectors).

**Testbenches / scripts:**

- `sim/tb/tb_block_rule.sv` — `NUM_VECTORS = 10368`; grouped conservation check.
- `sim/tb/tb_margolus_engine.sv` — grouped-water conservation; keep pile checks.
- **New directed momentum TB** (`sim/tb/tb_water_momentum.sv`) — self-checking:
  (a) slosh slab shows ≥2 tilt sign-flips then settles; (b) U-tube right column
  rises above height 1. Golden-referenced via a small Python vector/sequence.
- `sim/scripts/do_water_momentum.do` — new do-script; register in the regression
  runner.

**Docs:**

- `docs/SPEC_block_rule.md` — rewrite the phase section for momentum water;
  update the conservation statement to grouped.
- `docs/STATUS.md` — new dated section after Quartus passes.
- `sand_falling.qsf` — **no new synthesizable files** (no new modules); confirm
  nothing to add. TBs are never added to the qsf.

---

## 6. Gravity handling (MVP scope + limitation)

The tag is stored in **world coordinates** (`WATER_R` = +x, `WATER_L` = −x).
Momentum dynamics (advection/reflection/accelerate/damp) run when **gravity is
vertical (DOWN or UP)** — the perpendicular slosh axis is then horizontal, which
matches the tag.

When **gravity is horizontal (LEFT/RIGHT)**, the perpendicular axis is vertical;
the horizontal tag doesn't map cleanly. **MVP behavior:** under horizontal
gravity, moving water is treated as still `WATER` (tags decay), so water still
flows correctly via fall+advection but without slosh-momentum. This is a
**documented limitation**, not a bug.

Rationale: sloshing against side walls under normal downward gravity is the
headline effect; tilting to a side wall is a transient. Bounding the MVP here
keeps the rotation logic simple and the rule small (timing-friendly).

**Planned follow-up (not in this MVP):** store the tag as
*perpendicular-to-gravity* (2 states in canonical frame) and rotate it with the
block, giving correct momentum under all 4 gravities. Deferred to keep scope and
timing in check.

---

## 7. Damping tuning methodology

Damping (`rnd`-gated decay) sets the wave realism. Tune in Python before RTL:

- Harness: the slosh probe from `_proto_a.py`, instrumented to report (a) number
  of tilt zero-crossings (overshoots) and (b) the decay envelope (peak tilt per
  swing).
- **Target:** ~2–4 visible swings, each smaller than the last, settling to flat
  within a few seconds of wall-clock (≈ a few hundred passes). Not frictionless
  (proto was), not over-damped (no visible wave).
- Sweep the damp probability (e.g. damp on `rnd` vs `rnd & lfsr[k]` for a lower
  rate) and pick the envelope that looks like real water. Lock the chosen rate
  into the golden + RTL together so they stay bit-exact.

---

## 8. Timing plan & risk

The rule grows (more cases). Current settle-stage setup slack is only
**+0.052 ns** at 100 MHz — little headroom.

- First attempt: keep the existing 2-stage split (fall | settle), rebalance which
  phases live in which stage so both fit.
- **Mitigation if STA fails:** add a **third pipeline stage** in the engine
  (S_STAGE1/2/3 with a second registered midpoint). The engine already has the
  multi-pass budget (≈250k cyc/pass, plenty under the frame), so one extra cycle
  per block (13 → 14) is negligible. This is a localized, low-risk change.
- Fallback of last resort: drop `NUM_PASSES` from 8 to keep per-frame time within
  budget if a 3rd stage is added (it won't be needed for timing, only if the
  per-frame cycle budget tightens — it won't at 14 cyc/block either).

---

## 9. Other risks & mitigations

| Risk | Mitigation |
|------|-----------|
| Grouped conservation lets a real mass leak hide | Golden asserts grouped invariant on **all** 10 368 vectors; engine TB checks per-frame grouped count; directed TB checks totals. |
| Tag persists incorrectly when gravity changes | MVP decays tags under horizontal gravity (§6); transient only. |
| Moving water "tunnels" through thin walls | Reflection fires on **any** non-empty neighbor; exhaustive TB covers WALL/SAND/water neighbors. |
| Visual graininess during fast advection (`>.>.>`) | Damping + cohesion tuning (§7); advection only into EMPTY keeps bodies dense. |
| Brush/particle_count interaction | Brush injects still WATER (unchanged); particle_count uses `!= EMPTY` (unchanged). Verified in `tb_top`. |

---

## 10. Implementation order (with checkpoints)

1. **Materials/palette:** update `sand_materials.py` (IDs 4,5 → water family),
   regenerate `sand_palette.mem`. ✔ palette self-check passes.
2. **Golden model:** implement phases 1–5 + grouped conservation in
   `block_rule.py`; regenerate vectors. ✔ generator asserts conservation on
   10 368 vectors.
3. **Damping tuning** (§7) in Python; lock the rate. ✔ slosh shows decaying
   overshoots; U-tube rises.
4. **RTL:** port the tuned rule into `block_rule_fall`/`settle`/wrapper. ✔
   `get_errors` clean.
5. **Exhaustive TB:** `tb_block_rule` 10368/10368 (RTL == golden, grouped
   conservation). ✔
6. **Engine + integration TBs:** `tb_margolus_engine`, new
   `tb_water_momentum`, `tb_top`. ✔ all pass.
7. **Synthesis:** Quartus compile; **STA must close**. If not, add 3rd pipeline
   stage (§8) and re-run. ✔ 0 errors, positive slack.
8. **Docs:** `SPEC_block_rule.md`, `STATUS.md`. Clean up `_proto_a.py`,
   `_proto_b.py`.
9. **Commit** + mirror `gravity_accel` to `master`.

---

## 11. Rollback

All work is on-branch. If the momentum rule proves unsatisfactory or busts
timing irrecoverably, revert to `a35bfec` (throttled leveling) — a single
`git revert`/`git reset` restores the current good water with no other impact,
since engine/memory/display were never touched.
