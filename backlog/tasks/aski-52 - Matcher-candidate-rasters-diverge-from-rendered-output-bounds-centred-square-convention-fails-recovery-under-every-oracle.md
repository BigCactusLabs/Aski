---
id: ASKI-52
title: >-
  Matcher candidate rasters diverge from rendered output: bounds-centred square
  convention fails recovery under every oracle
status: Done
assignee: []
created_date: '2026-08-24 03:37'
updated_date: '2026-08-28 18:13'
labels:
  - research
  - algorithms
  - oracle
dependencies: []
priority: high
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The ASKI-32 calibrated screen (docs/Research/2026-08-23-aski32-calibrated-recovery.md §3a, as corrected by the pre-merge cross-model review in §3b) held the reference fixed — a typographic GlyphCellRaster picture of what the default-tile Courier renderer draws — and scored it against the candidate vocabulary the matcher actually indexes per BuildStandardVectors: bounds-centred Core Text rasters for text glyphs, position-faithful square BrailleRasterizer rasters for braille. The finding is a split, and the split is the evidence. TEXT charsets collapse for all five oracles (blocks at best 5/8, standard at most 18/95, mean ranks to 29/95): five metrics with disjoint failure modes agreeing means the defect is the candidate convention — bounds-centring erases position, the square footprint erases aspect. BRAILLE is exonerated: against its BrailleRasterizer vocabulary MAE/RMSE/SSIM/HaarPSI recover 256/256 at production geometry and only GMSD fails (163/256, ⣿→⠀), so the one charset whose candidate data never had the bounds-centring defect is the one that recovers. This is a selection-machinery finding upstream of any metric choice; it converges with the descriptor support-collapse record and the ASKI-16 orientation-blindness dead end. NOT an output-quality claim — production scores photographic cells, not pictures of glyphs. The question: what does selection quality gain if the TEXT-glyph raster vocabulary (shape vectors, brightness values, oracle candidates) is rebuilt on a position-faithful convention (the braille pipeline is the in-repo existence proof), and what does it break (bundled .bin shape vectors, archived comparability)?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A lab arm scores production picks with typographic-convention candidates against the same photographic corpus the ceiling uses, isolating the convention delta on real sources rather than glyph pictures
- [ ] #2 The interaction with the bundled .bin ShapeData vectors is stated: which artifacts would need regeneration, and whether archived verdicts stay comparable
- [ ] #3 ASKI-16's edgeMap-local matcher design consumes or explicitly declines the typographic convention, with the choice recorded on that task
- [ ] #4 Any default change is gated behind the standing no-reconstruction-metric-default-change rule; this task alone changes no defaults
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24 (deep pass): OVERLAP: same defect as ASKI-26 from the opposite end; both regenerate ShapeData .bin vectors and break archived comparability — whichever lands first moves the other's baseline. Sequence together.

SHIPPED as measurement in PR #32 (merged 2026-08-28, a12daa2/8d5eb1b). Verdict: no promotion — convention delta small and charset-dependent; note at docs/Research/2026-08-28-aski52-26-candidate-convention.md. Promotion cost (AC#2) recorded in note §6; consume/decline on ASKI-16 recorded (deferred). Polarity finding split to ASKI-60.
<!-- SECTION:NOTES:END -->
