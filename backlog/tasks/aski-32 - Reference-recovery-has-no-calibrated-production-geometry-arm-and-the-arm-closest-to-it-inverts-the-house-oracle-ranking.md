---
id: ASKI-32
title: >-
  Reference-recovery has no calibrated production-geometry arm, and the arm
  closest to it inverts the house-oracle ranking
status: Done
assignee: []
created_date: '2026-08-19 17:26'
updated_date: '2026-09-04 07:01'
labels:
  - research
  - oracle
dependencies: []
references:
  - docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md
priority: high
type: bug
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-27 adopted MAE as the house per-cell oracle and disqualified GMSD from defining an optimum. A pre-merge review of PR #3 found that the arm the note called the geometry gate does not measure production geometry, and the note was corrected in place (docs/Research/2026-08-19-house-oracle-audit.md section 9) rather than re-run.

The mechanism: ReferenceRecovery's roundTrip arm renders each glyph at the 24x24 scoring footprint, upsamples that raster into the 38x76 cell block, then resamples it straight back to 24x24. Its source is built FROM the footprint, so it can never carry more information than the footprint held. It varies blur, not sampling geometry. Production does the opposite trip: it starts from a genuine 38x76 block of photographic content at native resolution and downscales once. No arm of the screen measures that path with a calibrated source.

Why this matters rather than being cosmetic: the cell arm, the only one that draws the reference into the converter's own 38x76 block, INVERTS the ranking. MAE recovers 7 of 256 braille glyphs where GMSD recovers 168, and MAE's worst confusion is a full braille cell read as blank. That arm is confounded (GlyphRaster sizes the font to raster HEIGHT, so a glyph drawn into a 1:2 block is clipped at the sides and its ink fraction is not calibrated against the square 24x24 candidate), so it does not refute the decision as written. But confounded is not answered: the confound explains how the inversion COULD be an artifact, not that it is.

The two oracles fail in complementary ways, which is why the gate choice decides the verdict direction. MAE is mass-sensitive and position-blind; GMSD is position-sensitive and mass-blind. An arm that stresses only blur favours MAE. An arm that stresses anisotropic ink-fraction mismatch favours GMSD. A correctly built arm stresses both, and the informative outcome may well be that neither is clean on position-dense charsets.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A reference-recovery arm exists that carries genuine native-block information: the reference is rendered at high resolution and anisotropically resampled INTO the converter's resolved cell block, then LumaResample'd to the scoring footprint, so the source's information content is set by the block and not by the footprint.
- [x] #2 The GlyphRaster height-keyed font sizing confound is removed from that arm: the reference's ink fraction at the footprint is calibrated against the square candidate it is compared with, and the calibration method is stated and tested.
- [x] #3 The screen is re-run on all five oracles and all charsets, and the note records whether the MAE-vs-GMSD inversion survives, disappears, or resolves into both oracles failing. A three-way inconclusive is an acceptable outcome and must be reported as one.
- [x] #4 The house-oracle decision is either reaffirmed on the repaired evidence or revised. If revised, every ASKI-27 consequence is re-derived: the panel's roles, the standing rule that no reconstruction-metric result licenses a default change, and any queued task specified to run on MAE.
- [x] #5 A photographic-source variant is evaluated or explicitly rejected with a reason. Rendering a glyph and asking an oracle to name it is an idealisation; production never scores a picture of a glyph.
- [x] #6 GlyphRaster bounds-centering (Discoveries 2026-08-19): the centering that erases position-only distinctions is either fixed in the calibrated arm or explicitly measured as a bounded confound, not routed around silently
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Executed 2026-08-23 on branch aski-32 (commits 8bb8ce9 + note commit). Verdict: docs/Research/2026-08-23-aski32-calibrated-recovery.md. AC#1/#2: GlyphCellRaster (typographic production convention, braille via BrailleRasterizer) + two new screen arms; ink calibration measured per-row (gate arm meanInkΔ 0.004–0.045 vs 0.034–0.177 on the confounded cell arm) and bounded in AskiColorLabReferenceRecoveryTests. AC#3: full 5-oracle × 3-charset re-run — the §3b inversion DISAPPEARS on the calibrated same-path arm (MAE/RMSE/SSIM perfect everywhere; GMSD misses 11/95 standard, 4/256 braille): instrumental, as the parent suspected. AC#4: house oracle REAFFIRMED on production geometry; no ASKI-27 consequence changes; ASKI-30 decisive run unblocked. AC#5: photographic recovery rejected (no ground-truth glyph); perceptual validity stays with the parked VLM/human instrument. AC#6: bounds-centering fixed in the calibrated arm via GlyphCellRaster; measured — its cost is the calibratedCell collapse, filed as ASKI-52. Status stays In Progress until the branch PR (incl. just check) lands.

2026-08-24 post-open review (PR #27 comment r3840555607, codex bot P1): calibrated arms lacked AC#1's hi-res render → resample-into-block stage. Fixed in 76c23f7 (GlyphCellRaster 4x supersample + integer box downsample). Verdict-refining in the house oracle's favour: prior residual GMSD gate misses were hinting artifacts; all five oracles now recover everything through calibratedSamePath, so the gate is a validity check. Reaffirmation unchanged, grounds restated (note §3c). Full just check green; pushed.

2026-08-24: PR #27 MERGED to main (a47dcb5) after the batch-validation merge; research-index and backlog-note conflicts union-resolved (index regenerated via BuildResearchIndex), full just check green on the merged branch. All ACs done; ASKI-30 decisive run unblocked; ASKI-52 carries the candidate-convention finding.

2026-09-04 cross-check: ASKI-50 added pinned official MILO raw error and equation-27 contrast-weighted SSIM to a current exact-lattice ASTSK-42-style replay. Both new metrics, plus MAE, GMSD, and 1-HaarPSI, held the archived KILL at shipping 3/60 support and at a separate 48/60 comparator. There was no oracle split, so the ASKI-27 agreement protocol did not fire and MAE remains the house oracle. See docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md.
<!-- SECTION:NOTES:END -->
