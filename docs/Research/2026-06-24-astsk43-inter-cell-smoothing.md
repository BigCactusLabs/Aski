---
title: "ASTSK-43 Inter-Cell State Smoothing Before Glyph Selection - Verdict"
slug: 2026-06-24-astsk43-inter-cell-smoothing
date: 2026-06-24
status: complete
subsystem: [shape-context, frontier]
summary: "KILL, robust across columns {48,64,80,96}. A cheap lab-only input-side screen (self-guided guided filter on the source luma, same converter raw vs smoothed, composited render scored vs the original source by a source-conditioned seam-continuity metric M1 plus GMSD cross-checked by HaarPSI) showed the inter-cell-smoothing lever is inert: zero glyph-pick changes on line art and near-noise with a slight HaarPSI regression on naturals. The frozen per-cell mechanism could not be realized lab-only (per-cell 60D query descriptors are internal to Sources/Aski); the input-side screen is a superset, so its null kills the subset cheaply. Mechanistic finding: ASCII seam-breaking is largely structural (monospace side-bearing gutters at every cell seam), not selection-jitter, so selection/state smoothing cannot bridge it. Default rendering byte-identical; no Sources/Aski hook built."
related_specs: [docs/Research/2026-06-18-neural-cellular-automata-implicit-decoder.md]
datasets: [docs/Research/Corpus/nasa-structure-v1]
runners: [AskiColorLab]
next_action: "No default promotion task. Boundary continuity is gutter-limited; a real fix would need a rendering-model change (sub-cell stroke continuation / non-monospace), a separate larger task — not chased here. Next in batch: ASTSK-42 (steerable channel)."
---

# ASTSK-43 — Inter-cell state smoothing before glyph selection

**Status:** SETTLED — **KILL** (2026-06-24, robust across columns {48,64,80,96}). Constants were frozen
(below) before any measurement; results + verdict appended after the run, no constant tuned to a result.
**Branch:** `astsk-43-inter-cell-smoothing` · **Date frozen:** 2026-06-24
**Design lineage:** 2026-06-18 NCA brief → 2026-06-24 frontier-search bolster (`docs/Research/Discoveries.md`,
2026-06-24 entry + sub-entry) → this gate.

---

## Pre-registration (frozen 2026-06-24, BEFORE measurement — do not tune to pass)

### Hypothesis
A cheap inter-cell smoothing pass over the continuous pre-quantization field, before per-cell glyph
selection, reduces stroke breakage at cell boundaries without washing out genuine detail.

### Intervention actually run (Unit 3 = a CHEAP LAB-ONLY SCREEN — registered deviation from the frozen mechanism)

The frozen design (task note + Discoveries) is a self-guided guided filter (He–Sun–Tang) on the **per-cell
grid** of continuous cell-state (3×3, r=1 = the 8 grid-neighbors), then the existing argmax. **The lab
cannot realize that faithfully**: the per-cell 60D query descriptor is `internal` to `Sources/Aski`
(`LogPolarKernel.extractShapeVector`, private; needs `ConversionContext`), so there is **no lab-only path to
re-pick glyphs from a smoothed cell state**. A faithful build requires an off-by-default `Sources/Aski`
hook.

Per Aski research culture (screen the signal cheaply before touching `Sources/Aski` — ASTSK-31 AC#6,
ASTSK-35, ASTSK-7), Unit 3 instead runs the **input-side screen**:

1. Take the fixture's source luma (`[Float]`, native resolution).
2. Apply the **Unit-1 self-guided guided filter** `GuidedFilter.selfGuided` to it: **radius = round(imageWidth
   / columns)** px (≈ one cell each way → spans cell boundaries = inter-cell scale), **ε = 0.01** (on the
   [0,1] luma-variance scale: smooths inter-region jitter with stddev ≲ 0.1, preserves genuine boundaries
   ≳ 0.1), **single pass**.
3. Rebuild a grayscale image from the smoothed luma.
4. Run the **same** `ASCIIConverter` (identical character set / palette / options) on **raw** (baseline) vs
   **smoothed** (treatment) input. Only the input differs — a clean A/B.

**Validity argument.** This input-side smooth is a **superset** of the frozen per-cell-A mechanism: the
converter recomputes *both* the brightness pre-filter *and* the 60D descriptor from the smoothed pixels,
whereas per-cell-A would smooth brightness only. Therefore **C-KILL ⟹ per-cell-A almost certainly KILLs too**
(cheaply, no Sources touched). **C-PASS** is the only outcome that justifies building the faithful
off-by-default hook (or the cross-guided variant) as a follow-up. The guided filter being edge-preserving
(no gradient reversal, Unit 1) keeps this from being a naive wash.

### Measurement (native resolution, dual *agreeing* oracle)
- Composite each grid's chosen glyphs to a rendered pixel image: each cell rasterized via
  `GlyphRaster.luma(character:width:height:)` at **24 px** (the lab's `oracleCellSize`), tiled to
  `(cols·24) × (rows·24)`. Source resampled to the same dims via `LumaResample`.
- **Both** renders are scored against the **ORIGINAL (un-smoothed) source** — never against the smoothed
  source (that would be cheating).
- **M1** = `SeamContinuity.crossSeamCoherence(..., windowRadius: 2)` — source-conditioned cross-seam
  orientation coherence (higher = better). Cells = 24 px → seams at multiples of 24.
- **M2** = `GMSD.gmsd` (lower = better), cross-checked by **HaarPSI** (higher = better).
- Pools: **line-art** (`GlyphSheetFixture`) and **naturals** (`RealFixture`, NASA corpus). Aggregate =
  mean over each pool's fixtures.

### Decision rule (frozen)
Let Δ be treatment − baseline (mean per pool).

- **PASS** iff ALL of:
  1. **M1 lift (line-art):** `ΔM1 ≥ +0.01` absolute **AND** `≥ +2%` relative.
  2. **M2 no-regress (both pools):** `GMSD_treatment ≤ GMSD_baseline × 1.005` (≤ +0.5% rel).
  3. **HaarPSI agrees (both pools):** `HaarPSI_treatment ≥ HaarPSI_baseline × 0.995` (≥ −0.5% rel).
- **KILL** iff ANY of:
  - **Flat M1:** line-art M1 lift below the margin in (1).
  - **Naturals washout:** naturals GMSD up > 0.5% rel **OR** naturals HaarPSI down > 0.5% rel.
  - **Oracle disagreement:** on any pool, GMSD and HaarPSI disagree on the *sign* of the quality change
    (one says better, the other worse) → instrument failure → **re-run**, do not pick a winner.
- **Report the worst naturals case** (the single naturals fixture with the largest GMSD regression),
  regardless of verdict.

ε, radius rule, the M1 margin, and the no-regress tolerances above are chosen **once, now**, and are not
adjusted after seeing any number. Default rendering stays byte-identical (no `Sources/Aski` change in this
unit).

---

## Results

Run 2026-06-24, `swift run AskiColorLab inter-cell-smoothing --columns {48,64,80,96}`, committed NASA corpus
(1 line-art `glyphSheet` + 3 naturals: `earth-limb-sunrise`, `phoenix-night-grid`, `vavilov-crater`, all
2048²). After the O(N) summed-area-table fix to `GuidedFilter.boxMean` (a brute-force window was impractical
at native resolution × cell-scale radius). Δ = treatment − baseline, pooled means.

| cols | line-art ΔM1 / ΔGMSD / ΔHaarPSI | naturals ΔGMSD / ΔHaarPSI | worst naturals (ΔGMSD) | verdict |
|------|--------------------------------|---------------------------|------------------------|---------|
| 48   | **0.0000 / 0.0000 / 0.0000**   | −0.0003 / −0.0007 (−0.81%) | vavilov +0.0006        | KILL    |
| 64   | **0.0000 / −0.0000 / 0.0000**  | −0.0001 / −0.0005 (−0.64%) | vavilov +0.0003        | KILL    |
| 80   | 0.0004 / 0.0000 / −0.0000      | −0.0001 / −0.0008 (−0.87%) | vavilov +0.0004        | KILL    |
| 96   | 0.0000 / −0.0000 / 0.0000      | −0.0000 / −0.0006 (−0.69%) | vavilov +0.0004        | KILL    |

Three facts, identical across all four columns:

1. **The treatment changes nothing on line art.** On `glyphSheet` every per-fixture delta is exactly 0 (or
   ~1e-4): the edge-preserving guided filter (ε=0.01) leaves clean high-contrast strokes untouched, so **not
   one glyph pick flips**. The lever is inert on precisely the content where "strokes break at cell
   boundaries" is the stated problem.
2. **Naturals are pure noise with a slight downside.** GMSD is flat (±0.0006, mixed sign); HaarPSI drifts
   consistently **−0.6…−0.9%** with no compensating gain on any oracle. The gate's naturals-washout arm
   fires on the HaarPSI drift at every column.
3. **M1 is floored at ≈0** (line-art 0.0000–0.0030, naturals 0.0005–0.0019) for *both* arms — see the
   instrument caveat below. The KILL therefore does **not** rest on M1.

## Verdict

**KILL.** Robust across columns {48,64,80,96}. The input-side guided-filter screen produces **zero
improvement** in seam continuity or fidelity and a small consistent naturals HaarPSI regression. By the
pre-registered rule this is a KILL on two independent arms (flat M1 *and* naturals washout). Default
rendering is byte-identical — no `Sources/Aski` change was made.

**Per the pre-registration's validity argument, this also kills the narrower frozen mechanism cheaply.** The
input-side smooth is a *superset* of per-cell-A (the converter recomputes both brightness and the 60D
descriptor from the smoothed pixels, vs A smoothing brightness only). It moved *nothing* on the unfloored
M2/HaarPSI oracles and flipped *no* line-art pick → the strict subset A will not do better. **Do not build
the off-by-default `Sources/Aski` hook.** `occupancyMatching`-style promotion is unjustified.

### Mechanistic finding (why the lever is dead — the real takeaway)

Two signals converge on one mechanism. (a) M1 floors at ≈0 because, on a monospace glyph render, the cell
seams fall in the **inter-glyph side-bearing gutters** — the blank padding between characters — so the
source-conditioned coherence sampled *at the seam* is ~0 regardless of content. (b) The line-art deltas are
exactly 0 because there is no inter-cell *jitter* to smooth on clean strokes. Together: **seam-breaking in
ASCII art is largely structural, not selection-jitter.** A monospace grid *cannot* carry a stroke across a
cell boundary — the gutter is always there — so any intervention that only changes glyph *selection*
(inter-cell **state** smoothing included) cannot bridge it. Reducing boundary breakage would require changing
the **rendering model** (sub-cell stroke continuation / overlap, or a non-monospace layout), not the matcher
input. That is a different, larger task than ASTSK-43 and is not chased here.

### Instrument caveat (honest limitation)

`SeamContinuity` (M1) is correct as defined and validated on synthetic *continuous* fields (6 property
tests), but it is **largely uninformative on real glyph renders**: because cell seams coincide with
inter-glyph gutters, M1 sits near its floor for *any* ASCII output, so it cannot discriminate arms here. This
is a property of the glyph render model, not a bug. The dual-oracle design is what saved the gate: the
unfloored GMSD + HaarPSI carried the decision, and the inert line-art result corroborated it. **Lesson for
future seam metrics:** measure continuity at stroke locations, not at fixed cell boundaries, when the render
has structural gutters — or accept that boundary continuity is gutter-limited and measure something else.

### Reproduce
```bash
xcrun swift run AskiColorLab inter-cell-smoothing --columns 64   # KILL; --columns {48,80,96} identical
xcrun swift test --filter 'SeamContinuity|GuidedFilter|GridComposite|InterCellGate'   # 19 unit tests
```
