---
id: ASKI-27
title: >-
  Re-audit the per-cell pick-quality oracle: GMSD is ranked last of 11 as an
  optimization objective
status: Done
assignee: []
created_date: '2026-08-19 05:57'
updated_date: '2026-08-19 17:26'
labels: []
dependencies: []
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every archived descriptor verdict (ASTSK-31 regime oracle, ASTSK-35 basis augmentation, ASTSK-42 steerable channel) was decided by per-cell GMSD between the chosen glyph raster and the source block, cross-checked by HaarPSI. A 2026-08-19 frontier sweep surfaced two primary results that impeach that instrument. (1) Ding, Ma, Wang and Simoncelli, IJCV 2021, rank GMSD LAST of 11 full-reference metrics used as an optimization objective in a four-task human study and diagnose it as luminance-blind; they find plain MAE competitive and MS-SSIM's advantage over MAE statistically insignificant. GMSD pools by the STANDARD DEVIATION of the gradient-magnitude-similarity map, so a per-cell argmin rewards uniform mediocrity over a glyph that is right across most of the cell and wrong in a corner - which is the wrong preference for a tone-plus-structure medium. (2) Xu, Zhang and Wong (SIGGRAPH 2010, Figure 7) already demonstrated that the loss-optimal pick under alignment-sensitive full-reference metrics is perceptually wrong for glyph selection specifically. Additionally GMSD and HaarPSI are not a disjoint pair (both are gradient/wavelet structure metrics) and HaarPSI's pooling uses a global denominator, so per-cell argmax under it is not cleanly well-posed. Aski's GMSD also omits the canonical 2x2 mean filter and dyadic subsample, so published correlation numbers do not transfer to this variant. AskiColorLab selection-ceiling already runs a third, luminance-aware, separable MAE oracle; this task is the audit that decides what the house oracle should be.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A luminance-aware separable per-cell objective is adopted or explicitly rejected with reasons, and the choice is documented as the house oracle
- [x] #2 Reference-recovery screen is run as a disqualifier: when the source cell IS a rendered glyph, each candidate oracle must make that glyph the unique argmin at the scoring footprint
- [x] #3 At least one archived decisive run is re-scored under the chosen oracle and the verdict is reported as held or flipped
- [x] #4 If any verdict flips, the oracle-agreement protocol fires and the affected research notes are marked superseded rather than edited in place
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-19, branch `aski-27-house-oracle`. All four ACs settled; lab + docs only, `Sources/Aski` untouched. Verdict note: docs/Research/2026-08-19-house-oracle-audit.md.

**AC#1 — house oracle is MAE.** Luminance-aware, separable, cheapest of the panel, the metric Ding et al. (IJCV 2021) find competitive, and the only family perfect on both gating arms of the screen. RMSE is its same-family cross-check, single-scale SSIM the disjoint one. GMSD and HaarPSI are DISQUALIFIED from defining an optimum (no argmin, no ceiling, no "loss-optimal" claim) and kept only as comparators. MS-SSIM was excluded by arithmetic, not preference: its 5-scale pyramid needs ~161px against a 24px footprint; LPIPS/DISTS/MILO fail the same test by more.

**AC#2 — reference-recovery screen, run first, disqualified two oracles.** New `ReferenceRecovery` lab arm + `AskiColorLabReferenceRecoveryTests`. Four source constructions, five oracles, three charsets. At the footprint itself (resample an identity) ALL five oracles recover every reference on blocks/standard/braille — nothing is blind in the trivial sense. Adding only the converter's own anisotropic cell block, rasterizer held fixed (`roundTrip`), splits the panel: MAE/RMSE/SSIM stay at 8/8, 95/95, 256/256; GMSD loses the half-block pair `▄→▀` (a pure position swap at identical ink) and 51/256 braille; HaarPSI loses 20/256. Zero soft-fail ties anywhere — every failure is a strict miss. The disqualification is SCOPED to argmin/ceiling use, not to the A/B comparison of two realizable renderings the archived kills actually made, so no verdict flips.

**AC#3 — ceiling re-scored as a bound, and the margin does not survive the corpus.** Re-ran selection-ceiling under all five oracles at columns 80, exhaustive census (8640 cells/arm), oversample 2/4/8/16/32 — reaching the 48-of-60-bin regime the archived kills ran at. Under the house oracle the `standard` ranking headroom is 1.83/2.41/2.29/2.09/2.19% on nasa-steerable-v1, below the +3.0% bar at every arm. The SAME measurement on the harness default corpus (nasa-structure-v1) gives 2.88/3.93/3.53/3.50/3.54% — above the bar from oversample 4 up. The margin that re-read the kill record as unwinnable is thinner than the difference between two corpora; the reading is not robust and must not be quoted without naming the corpus.

**AC#4 — no verdict flipped; the reading change is superseded, not edited.** New note supersedes 2026-08-19-selection-optimality-gap §4/§5; a forward-pointer call-out was ADDED at the top of that note with its numbers and verdict left as written.

**Two instrument defects found on the way.** (1) `selection-ceiling --corpus` defaults to the 2048px nasa-structure-v1 while both 2026-08-19 notes report the 3072px nasa-steerable-v1, and their §8 reproduce command omits the flag — worth up to 10 gap points. With the corpus passed explicitly every archived number reproduces EXACTLY (blocks GMSD 51.65%, HaarPSI 327.38%, MAE 61.78%, meanRank 3.75/8; standard 18.71%/2.26%; braille MAE 3.58%), which is also the proof the two added oracles are inert on the incumbents. The `--corpus` help text now states the trap. (2) `GlyphRaster` centres every glyph by its CTLine image bounds, erasing position-only distinctions before any oracle sees them; all five oracles lose the same ~70/256 braille references on the fixed-aspect downscale arm, within a spread of 3. That is one bottleneck upstream of the whole panel and it bounds every lab result about position-sensitive charsets.

**Strengthened, not qualified:** the tone-only inversion on the ASTSK-47-frozen sparse preset holds under all FIVE oracles (MAE 0.56329 production vs 0.24637 tone-only, 2.3x), and under the house oracle the production pick there averages rank 7.22/8. ASKI-30 is unblocked and its priority rises. ASKI-28 stays low (pool term 2.85-3.08% under the house oracle). What is NOT unblocked is any human-visible magnitude claim — the parked human-preference/VLM A/B arbiter is still the missing instrument, so the README positioning claim stays as it is.

**Also landed (ASKI-29 AC#2 only):** the ShapeResidual harness now records the converter's resolved cell footprint and reachable-bin count on every FixtureAnalysis and prints them next to every rho (the synthetic battery reads 25x64, 48/60 bins), so a verdict measured at 48 bins can never again be quoted against a preset that runs at 2-3.
<!-- SECTION:NOTES:END -->
