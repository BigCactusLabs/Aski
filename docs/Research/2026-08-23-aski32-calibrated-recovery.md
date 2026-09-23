---
title: "Calibrated production-geometry recovery — the ASKI-27 cell-arm inversion was instrumental, the house oracle survives it, and the matcher's own candidate convention fails all five oracles"
slug: 2026-08-23-aski32-calibrated-recovery
date: 2026-08-23
status: complete
subsystem: [shape-context, frontier]
summary: "ASKI-32. The house-oracle audit adopted MAE while admitting its strongest counter-evidence was unanswered: on the one screen arm that drew the reference into the converter's real 38x76 cell block, the ranking inverted — MAE recovered 7 of 256 braille glyphs where GMSD recovered 168 — and the arm was confounded by the probe's rasterizer, which sizes the font to the raster height and lands the reference on an uncalibrated ink fraction. This note builds the instrument that arm was missing. GlyphCellRaster draws a glyph the way production output draws it — baseline and advance positioning with the point size derived from the renderer's own geometry rule, braille through the production dot rasterizer — and two new screen arms use it. calibratedSamePath, the gate, renders both sides through that one convention and differs only in draw resolution: the reference at the native block, the candidate at footprint scale. Ink calibration is measured, not assumed: mean ink-fraction delta 0.004 to 0.045 against 0.034 to 0.177 on the confounded arm. On this repaired arm the inversion disappears: MAE, RMSE and SSIM recover every glyph on every charset — 8 of 8, 95 of 95, 256 of 256 — while GMSD still misses 11 of 95 on standard and 4 of 256 on braille. The house-oracle decision is reaffirmed on production geometry, no longer only on blur evidence plus the IJCV prior. The second arm is the surprise, and a pre-merge cross-model review narrowed it before it over-claimed. calibratedCell scores the typographic reference against the matcher's real candidate vocabulary — bounds-centred Core Text rasters for text glyphs, and (per BuildStandardVectors) position-faithful BrailleRasterizer rasters for braille. On the text charsets all five oracles collapse together: blocks at best 5 of 8, standard at most 18 of 95, mean ranks to 29 of 95. On braille the luminance-aware oracles and HaarPSI recover 256 of 256 and only GMSD fails (163 of 256, worst confusion a full cell read as blank) — braille is exonerated precisely because its matcher data never had the bounds-centring defect. A text-charset failure shared by five metrics with disjoint failure modes is not an oracle defect; it is the candidate convention: bounds-centring erases position and the square footprint erases aspect, which converges with the descriptor support-collapse record and the ASKI-16 orientation-blindness dead end from the code path rather than the metric path. The photographic-source variant is rejected as a recovery instrument for want of a ground-truth glyph; what survives of it is the standing observation that production never scores a picture of a glyph, so the calibrated arms bound the oracle, and only a preference instrument can bound the picture."
related_specs: [docs/Research/2026-08-19-house-oracle-audit.md, docs/Research/Discoveries.md]
datasets: []
runners: [AskiColorLab]
next_action: "ASKI-30's decisive run is unblocked: its gate was this task, and the house oracle held. File the candidate-convention finding as its own task — on the TEXT charsets the matcher's bounds-centred square rasters fail recovery against default-tile-rendered references under every oracle (braille is exonerated: its BrailleRasterizer-generated vocabulary recovers 256/256 under every luminance-aware oracle), a selection-machinery defect upstream of any metric choice whose natural first consumer is the ASKI-16 edgeMap-local matcher design. Do not read calibratedCell's collapse as production being 'wrong by that much' — the arm measures raster-convention mismatch at selection time, not output quality."
---

# ASKI-32 — Calibrated production-geometry recovery

**Status:** SETTLED. The §3b counter-evidence of the parent note is answered: instrumental.
**Branch:** `aski-32` · **Date executed:** 2026-08-23 · **Task:** ASKI-32
**Parent:** [2026-08-19 — House-oracle audit](2026-08-19-house-oracle-audit.md), esp. §9. This note is
the follow-up that §9 says "gates ASKI-30's decisive run". It changes no number in the parent.

## 1. Question

The parent note adopted MAE as the house per-cell oracle on a footprint identity arm, a blur control,
and the IJCV 2021 prior — and recorded, in its own corrections section, that no arm measured the
production downscale with a calibrated source. Its `cell` arm, the only one that drew the reference
into the converter's resolved 38×76 block, inverted the ranking (MAE 7/256 braille vs GMSD 168/256)
and was confounded: `GlyphRaster` sizes the font to the raster height, so a glyph drawn into a 1:2
block is clipped at the sides and lands on an ink fraction never calibrated against the square
candidate it competes with. Confounded is not answered. This task builds the calibrated arm and asks:
does the inversion survive it?

## 2. Instrument

### 2a. `GlyphCellRaster` — the production output convention, made scoreable

`ImageRenderer` positions glyphs typographically: left cell edge, shared row baseline at `descent`,
point size tied to cell height by `glyphHeight = pointSize × 1.2` — and renders braille through
`BrailleRasterizer` dot geometry, not a text face. Meanwhile every raster the lab (and the matcher
itself — `RasterizedCharacterSet.rasterize` shares the same `CTLineGetImageBounds` code shape)
scores is **bounds-centred**, which erases position-only distinctions: `▄` and `▀` become one centred
bar, single-dot braille collapses. `GlyphCellRaster` (Tools/AskiToolSupport) inverts the renderer's
geometry rule instead: point size from block height, baseline + advance positioning, braille through
the production rasterizer. Scope, stated precisely: it models the renderer's **default-tile Courier**
branch — the branch whose 1:2 aspect the screen's resolved block has — not the shipped preset's
Courier Prime + `preserveSourceAspect` variant (`glyphHeight = pointSize × 0.6 × 2.2`) and not a
caller-supplied font. Every claim below is a claim about the default-tile Courier regime.

The rasterizer implements AC#1's staging literally: the glyph is rendered at **4× supersample** and
area-resampled (exact integer box average) *into* the requested block before the caller's one
`LumaResample` to the footprint. Rendering directly at block resolution would tie Core Text
hinting/antialiasing to the 38×76 block — and §3c below records that this is not a nicety: the
direct-render version left GMSD a residual failure on the gate that the hi-res stage removes. Unit
tests pin the properties the pipeline must keep: the half-block pair stays apart with ink in the
correct halves, corner braille dots stay in their quadrants, and the supersampled render differs
from a direct block-resolution render while carrying the same ink to antialiasing tolerance.
`GlyphRaster` is untouched, so every archived screen reproduces.

### 2b. Two new arms, and what "calibrated" means

| arm | reference | candidates | isolates |
| --- | --- | --- | --- |
| `calibratedSamePath` | typographic draw at the native 38×76 block → one `LumaResample` to 24×24 | typographic draw at a footprint-scale cell block → 24×24 | **gate**: production geometry with both sides through one path; only draw resolution differs |
| `calibratedCell` | same reference | the matcher's candidate vocabulary per `BuildStandardVectors`: bounds-centred square `GlyphRaster` for text glyphs, square `BrailleRasterizer` rasters for braille | what the matcher's own candidate convention costs at selection time |

The reference's information content is set by the block, not the footprint (parent §9's objection to
`roundTrip`), and the height-keyed clipping cannot occur because the point size derives from block
height through the renderer's rule. Calibration is **measured**: every screen row now reports the
mean and worst ink-fraction delta between each reference (at the footprint, post-resample) and the
candidate it must out-score, and `AskiColorLabReferenceRecoveryTests` bounds the gate arm's mean
delta. The confounded `cell` arm retroactively gets the same columns, which is what quantifies the
parent's confound instead of narrating it.

## 3. Results

Full screen, `columns: 80`, `oversample: 2`, 24px footprint, 3072 native side, release build.

**Ink calibration (mean Δ / worst Δ, per charset):**

| arm | blocks | standard | braille |
| --- | --- | --- | --- |
| `cell` (confounded, parent) | 0.177 / 0.354 | 0.078 / 0.124 | 0.034 / 0.069 |
| `calibratedSamePath` (gate) | 0.006 / 0.015 | 0.011 / 0.018 | 0.001 / 0.002 |

**`calibratedSamePath` — the repaired production-geometry gate:**

| oracle | blocks (8) | standard (95) | braille (256) |
| --- | --- | --- | --- |
| **MAE (house)** | **8 / 8** | **95 / 95** | **256 / 256** |
| RMSE | **8 / 8** | **95 / 95** | **256 / 256** |
| SSIM | **8 / 8** | **95 / 95** | **256 / 256** |
| HaarPSI | **8 / 8** | **95 / 95** | **256 / 256** |
| GMSD | **8 / 8** | **95 / 95** | **256 / 256** |

**The inversion disappears — entirely.** With the reference drawn at high resolution, resampled into
the real block at a calibrated ink fraction, **every oracle recovers every glyph** through the gate.
The gate therefore discriminates nothing: it is the validity check that the instrument is clean, and
all five metrics pass it. The §3b counter-evidence is answered in the strongest available form:
**wholly instrumental**, produced by the probe's rasterizer, quantified by the ink columns above.
What still separates the panel is the parent's blur control (`roundTrip`: GMSD misses on blocks
7/8 and braille 205/256 while MAE and RMSE are perfect) and the matcher-candidate arm below, where
GMSD is the only oracle that fails braille's position-faithful vocabulary.

> **Decision (AC#4).** The house-oracle decision is **reaffirmed on repaired evidence**. MAE stays
> the house oracle and passes the calibrated production-geometry gate everywhere; GMSD and HaarPSI
> stay disqualified from defining an optimum on the parent's own grounds — the blur control and the
> IJCV prior — plus GMSD's lone failure on the matcher's braille vocabulary at production geometry
> (§3a). Every ASKI-27 consequence stands unchanged: the panel's roles, the no-default-change rule
> for reconstruction metrics, and ASKI-30's specification on MAE. ASKI-30's decisive run is
> unblocked.

### 3a. `calibratedCell` — the matcher's candidate convention fails every oracle

| oracle | blocks | standard | braille | mean braille rank |
| --- | --- | --- | --- | --- |
| GMSD | 1 / 8 | 13 / 95 | 163 / 256 | 24.0 |
| HaarPSI | 4 / 8 | 16 / 95 | **256 / 256** | 1.0 |
| MAE | 3 / 8 | 9 / 95 | **256 / 256** | 1.0 |
| RMSE | 3 / 8 | 11 / 95 | **256 / 256** | 1.0 |
| SSIM | 2 / 8 | 18 / 95 | **256 / 256** | 1.0 |

Hold the reference fixed (a picture of what the default-tile Courier renderer draws) and swap in the
candidates the matcher actually indexes, and the **text charsets collapse for all five oracles**
while **braille survives for every luminance-aware oracle**. The split is the finding. The matcher's
braille vocabulary is generated by `BrailleRasterizer` (`BuildStandardVectors`) — square but
position-faithful, no bounds-centring — and against it MAE, RMSE, SSIM and HaarPSI recover every
glyph at production geometry; only GMSD fails (163/256, worst confusion `⣿→⠀`, the same
luminance-blind shape as everywhere else). The text charsets' candidates are bounds-centred Core
Text rasters, and there five metrics with disjoint failure modes collapse together — the parent's
own §3a argument shape: not an oracle failing, but the comparison being handed two conventions of
the same glyph. Bounds-centring erases position and the square footprint erases aspect; the one
charset whose candidate data never had that defect is the one that recovers.

This is a **selection-machinery finding, not an output-quality number**: production scores
photographic cells, not pictures of glyphs, so the arm does not say renders are "wrong by 60%". What
it does say: the raster vocabulary the matcher selects with is systematically unlike the raster
vocabulary the renderer draws with. That converges with two standing records — the shipped 60D
descriptor carrying 2–3 of 60 bins (support collapse), and ASKI-16's finding that log-polar templates
cannot separate orientation at glyph scale. Filed as its own follow-up task rather than absorbed
here — scoped to the text charsets; braille's candidate convention needs no rescue.

### 3b. Pre-merge review corrections

A cross-model review of this branch, before merge, caught four defects in the first landed version;
per the parent's §9 standard they are recorded rather than silently absorbed. (1) The rasterizer and
this note claimed "production output convention" flatly; the instrument models the default-tile
Courier branch only, and the scope statements above were narrowed accordingly. (2) The first
`calibratedCell` run scored braille against Core Text *fallback* rasters — nobody's convention: the
matcher's braille data is `BrailleRasterizer`-generated. With the matcher's real braille candidates
the row flips from "all five collapse (best 142/256)" to the split reported above, and the follow-up
task's scope was corrected before any work consumed it. (3) The test suite pinned only an ink-delta
bound; it now pins the calibrated gate's decisive outcome (luminance-aware oracles perfect, GMSD
failing) so a reversal fails `just check` loudly. (4) Braille dispatch keyed on scalar count where
the renderer keys on the first scalar; aligned. The gate-arm numbers in §3 were unaffected by all
four.

### 3c. Post-open review correction (2026-08-24) — the missing hi-res stage

A fifth defect was found on the open PR after the first verdict landed: the calibrated arms rendered
the reference *directly* at the resolved 38×76 block, skipping AC#1's high-resolution render →
resample-into-block stage, so Core Text hinting/antialiasing stayed tied to the block size. The fix
is the 4× supersample + integer box downsample now described in §2a. It was **verdict-refining, not
verdict-flipping** — and in the house oracle's favour: on the direct-render instrument GMSD retained
residual gate failures (7/8 blocks, 84/95 standard, 252/256 braille) that this note previously
reported as "GMSD still fails under production geometry". Those misses were themselves hinting
artifacts: with the stage in place GMSD recovers everything through the gate (§3), so the gate's
GMSD claim was withdrawn and the disqualification now rests entirely on the blur control, the §3a
braille-vocabulary failure, and the IJCV prior. All §3/§3a numbers in this note are from the
post-fix re-run; the pinned test was renamed to `everyOracleRecoversThroughTheCalibratedSamePathGate`
to state what the gate now shows.

**Rejected as a recovery instrument, with the reason stated.** Recovery is defined by a ground-truth
glyph; a photographic block has none, so "did the oracle name the glyph it was handed" is not askable
of it. The two calibrated arms already carry what the variant was meant to buy — genuine native-block
information content through the production resample direction. What cannot be bought this way is
perceptual validity on non-glyph sources: an oracle perfect at recovering rendered glyphs may still
mis-rank two wrong-but-plausible picks on a photograph. That is the parent's §6 limit restated, and
it stays with the parked human-preference / VLM A-B instrument, not with any reconstruction screen.

## 5. Standing rules

1. Parent §7 rules stand unchanged, including MAE-first reporting and the screen-before-scoring gate.
2. **The calibrated gate joins the screen**: a future oracle must pass `footprint` and
   `calibratedSamePath`; `roundTrip` remains a blur control, `cell` and `calibratedCell` remain
   diagnostics.
3. **Name the convention.** Any raster comparison states which drawing convention produced each side
   (`GlyphRaster` bounds-centred vs `GlyphCellRaster` typographic); the ink-delta columns are the
   check that the two sides were calibrated at all.

## 5a. Frontier check (2026-08-23 sweep)

A same-day web sweep (dual-track, run against this design before it locked) converges with the
instrument and sharpens two characterizations the record carried:

- **MAE is position-sensitive, not position-blind.** The parent's "mass-sensitive and position-blind"
  shorthand overstates: pixelwise L1 charges exact-position error too. What distinguishes the
  families is that GMSD *discards luminance* and pools by the standard deviation of its similarity
  map — a spatially constant local distortion can score perfectly (Ding et al., IJCV 2021; Xue,
  Zhang, Mou, Bovik, IEEE TIP 2014).
- **The IJCV ranking, stated precisely:** GMSD ranks 11 of 11 as an optimization objective for
  denoising and deblurring, 10 of 11 for super-resolution and compression (CW-SSIM last there),
  Fig. 9. "Last of eleven" without the task split is slightly too flat; the disqualification here
  does not lean on it — it now rests on the calibrated production-geometry failure above.
- **No rasterization standard normalizes glyphs to equal ink fraction.** Font-rendering practice
  treats anti-aliased rasters as coverage fields to be composited in linear light (FreeType
  rasterizer docs; Waxweiler, FreeType hinting notes). The sweep's design guidance — measure each
  glyph's post-resample mean coverage against its candidate rather than per-glyph opacity-fitting,
  which would erase the signal under test — is exactly the measured-ink-delta construction of §2b.
  Xu et al.'s grayness normalization is the deliberate *shape-control* exception, and stays out of
  any tone-faithful arm.
- **Reference recovery is an established pre-screen, not a validation protocol** (Ding et al. use
  the continuous-optimization analogue). Known pitfalls the sweep lists — shared-raster-path bugs
  hiding calibration errors, resample-induced equivalence classes, aggregate top-1 hiding strata —
  are respectively addressed by the two-convention arm pair, the `distinctSources` column, and left
  open (per-class strata) as cheap future hardening. A position-swap / coverage-mutation stratified
  report is a natural extension for ASKI-52's lab arm.

## 6. Reproducing

```bash
# Full screen, all six arms (~30s release). Debug is ~70x slower.
swift run -c release AskiColorLab reference-recovery

# The suite that pins the gate, the rasterizer's position fidelity, and the
# ink-calibration bound (blocks charset; runs inside just check):
just test  # AskiColorLabReferenceRecoveryTests
```

## Sources

- [2026-08-19 — House-oracle audit](2026-08-19-house-oracle-audit.md) — the parent decision, its §9
  corrections, and the §3b counter-evidence this note answers.
- Ding, Ma, Wang, Simoncelli, IJCV 2021 (arXiv 2005.01338) — the prior the parent's decision leaned
  on; this note moves the decisive weight onto measured production geometry. Fig. 9 task split per §5a.
- Xue, Zhang, Mou, Bovik, *Gradient Magnitude Similarity Deviation*, IEEE TIP 2014 — GMSD's
  deviation pooling, designed for fixed-output IQA, not as a reconstruction objective.
- Mohammadi & Ascenso, *Perceptual Impact of the Loss Function on Deep-Learning Image Coding
  Performance*, PCS 2022 — the compression-task caveat on the IJCV ranking; task-dependence, not
  contradiction.
- FreeType rasterizer documentation and Waxweiler, *On Slight Hinting…* (freetype.org) — glyph
  rasters as coverage fields, linear-light compositing, size-dependent weight; why the calibration
  is measured per arm instead of normalized away.
- [`GlyphCellRaster`](../../Tools/AskiToolSupport/GlyphCellRaster.swift),
  [`ReferenceRecovery`](../../Tools/AskiColorLab/SamplingLattice/ReferenceRecovery.swift) — the
  instrument.
