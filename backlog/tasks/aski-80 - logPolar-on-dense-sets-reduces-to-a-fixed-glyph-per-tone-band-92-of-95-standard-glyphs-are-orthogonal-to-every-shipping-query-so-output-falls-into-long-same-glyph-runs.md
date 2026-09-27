---
id: ASKI-80
title: >-
  logPolar on dense sets reduces to a fixed glyph per tone band: 92 of 95
  standard glyphs are orthogonal to every shipping query, so output falls into
  long same-glyph runs
status: In Progress
assignee: []
created_date: '2026-09-27 17:35'
updated_date: '2026-09-27 20:42'
labels:
  - research
  - matcher
  - algorithms
  - glyphs
dependencies: []
references:
  - docs/Research/2026-08-19-sampling-lattice-support-collapse.md
  - docs/Research/2026-08-19-selection-optimality-gap.md
  - Sources/Aski/ShapeMatching.swift
priority: high
type: spike
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MEASURE-FIRST. Found 2026-09-27 from the bcl-web canyon strip (Aski HEAD 6b6d251). Same root as ASKI-79, different symptom: on the dense sets the shape term is not blank-collapsed, but it stops describing the cell.

MECHANISM (verified with `@_spi(AskiResearch)` `cellQueryDescriptors` and `StandardCharacterSet.standard.shapeVectorLanes`)
At the shipping footprint every query occupies only bins 51, 54 and 56 (ASKI-55 support collapse; ASKI-79). Only 3 of the 95 standard glyphs have any mass there: `|`, `}` and `j`. For the other 92, q·g = 0, so d(q,g) = |q|² + |g|². Inside the 12-glyph tone pool the winner is then the pooled glyph with the smallest |g|², unless `|`, `}` or `j` is in the pool. That is a fixed lookup from tone band to glyph; the cell's shape plays no part.

MEASURED OUTPUT (library, BuiltInPalette.monochrome; runs = consecutive identical non-blank glyphs along a row)
- bcl-web canyon photo, 288 columns, standard/logPolar: 14 of 95 glyphs used; run mean 4.90, p95 18, max 162; 73.3% of non-blank cells sit in runs of 5 or more.
- nasa-occupancy-v1-cernan-portrait, 288 columns: 15 glyphs; mean 7.11, p95 28, max 252; 84.4% in runs of 5+. At 80 columns: 65.8%.
- nasa-steerable-v1-vavilov-crater, 80 columns: 7 glyphs; 62.7% in runs of 5+.
- braille/logPolar uses 7-15 of 256 glyphs, 41-85% of cells in runs of 5+.
- dotMatrix with Floyd–Steinberg (coverage 1) on the same inputs, standard: 32-94 glyphs used; run mean 1.26-1.98, p95 2-6; 3.0-34.1% in runs of 5+.
- Correlation of glyph raw density with cell OKLab L: logPolar standard 0.94-0.95, dotMatrix FS 0.98-1.00. logPolar is already acting as a tone quantizer, a coarse one.

VISIBLE EFFECT
Smooth photographic gradients render as rows of zzzz, ====, ||||, tttt, cccc that read as typed text rather than image. This is why bcl-web is moving its canyon strip off logPolar/standard.

REPRO
Convert any fixture with `ASCIIConverter(characterSet: .standard, palette: BuiltInPalette.monochrome)` at 80 and 288 columns and compute per-row run lengths of identical non-blank characters from `grid.cells`; compare `algorithm: .dotMatrix, options: RenderingOptions(coverage: 1)`. For the mechanism, count the pooled candidates whose lanes have a nonzero dot product with each cell's `cellQueryDescriptors` lanes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The selection-ceiling census (or a lab command) reports texture readouts next to MAE/GMSD: glyphs used, mean and p95 run length of identical non-blank glyphs per row, and share of cells in runs of 5 or more
- [x] #2 Per fixture and footprint, the share of standard and braille picks decided by |g|² alone (query orthogonal to every pooled candidate) is measured, confirming or refuting the mechanism
- [x] #3 Under a rule pre-registered before the decisive run, at least one intervention is measured against production on runs and MAE/GMSD together: an ASKI-55 support-restoring footprint, an error-diffused tone term, or a tie-break that does not repeat the left neighbour
- [x] #4 The outcome is recorded as a research note whatever the sign
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Batch 79-82. AC#1: PickTexture readouts (glyphsUsed, blankShare, runMean, runP95, runMax, run5Share) appended to the selection-ceiling census. AC#2: aski lab color query-orthogonality; the mechanism is confirmed on standard (55-59% of picks orthogonal on the PNG corpora, decided by |g|^2 alone) and refuted on braille (0% orthogonal; collapse comes from small non-zero overlaps). AC#3: under the rule frozen at 40bafb0, arm 1 (tone fallback) KILL and arm 2 (arm 1 plus serial Floyd-Steinberg tone centring, lab-only) INCONCLUSIVE: run5Share fell 0.27-0.38 against arm 1 but glyphsUsed did not rise on 3 of 4 rows and braille on steerable exceeded the 1.0100 MAE and GMSD guards. AC#4: docs/Research/2026-09-27-aski-79-80-orthogonality-fallback.md. Remaining routes are listed in the rule's section 7 (support restoration per ASKI-55, tone in the pool per the ASKI-30 track).
<!-- SECTION:NOTES:END -->
