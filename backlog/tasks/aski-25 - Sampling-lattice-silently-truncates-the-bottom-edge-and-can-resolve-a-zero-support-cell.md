---
id: ASKI-25
title: >-
  Sampling lattice silently truncates the bottom edge and can resolve a
  zero-support cell
status: Done
assignee: []
created_date: '2026-08-19 05:56'
updated_date: '2026-08-19 16:17'
labels: []
dependencies: []
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The converter takes an integer cell pitch (cellWidth = thumbnail.width / cols, cellHeight = thumbnail.height / rows) and samples strictly from (0,0) upward, so the remainder thumbnail.height - rows*cellHeight is never sampled. Measured at columns=80 on the nasa-steerable-v1 square fixtures: 16 of 160 thumbnail rows dropped at oversample 2 (10.0 percent of image height), 32 of 320 at oversample 4 (10.0 percent), 28 of 640 at oversample 8 (4.4 percent), 20 of 1280 at oversample 16 (1.6 percent). Across a source-aspect sweep at oversample 2 the drop ranges from 5 rows on a 3:1 source (3.4 percent) to 45 rows on a 1:3 source (9.4 percent). It is always the bottom edge, so the loss is systematic rather than noise. Because the dropped fraction is a function of oversample, it is also a confound for any experiment that sweeps oversample - the first version of both 2026-08-19 research notes measured through this misalignment and had to be re-run, moving the dense-charset optimality gaps by 2 to 6 times. Separately, a 1-pixel-wide cell passes the cellWidth > 0 guard but yields zero admitted pixels through the ShapeContext.histogram60 radius gate, producing an all-zero descriptor that is equidistant from every candidate and resolves to the space glyph; at oversample 1 with columns=120 on a 975x1280 portrait the pitch degenerates to cellWidth 0 and prepareConversion bails entirely. Same failure family as the ASTSK-47 portrait blank-render fix and backlog ASKI-16.1 edgeMap zero-descriptor collapse, but the logPolar path at low oversample is covered by neither. Evidence: docs/Research/2026-08-19-sampling-lattice-support-collapse.md section 5.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Bottom/right remainder is either sampled or the truncation is an explicit, documented, tested contract rather than silent
- [x] #2 A cell footprint that admits zero pixels through the histogram radius gate is detected and handled explicitly instead of silently resolving to the space glyph
- [x] #3 Regression tests cover the portrait low-oversample degenerate pitch and assert the measured drop is zero or contract-conformant
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Phase B1 landed on branch aski-25-sampling-lattice.

AC#2 - zero-support detection. Trigger is a PURE FUNCTION of the footprint: ConversionContext.cellSupportsShapeDescriptor = min(cellWidth, cellHeight) > 1, resolved once per conversion in the initializer. It is the exact complement of ShapeContext.histogram60's own 'guard minDimension > 1' early return (ShapeContext.swift:23). When false, LogPolarKernel takes an explicit brightness-only pick (ShapeMatching.poolIndices topK 1) in score / scoreScored / matchWithDescriptor. scoreScored surfaces Float.nan, the protocol's documented 'no shape residual' sentinel; distance(fromLanes:) returns .infinity on the empty-lane case so temporal hysteresis cannot hold a glyph it cannot score.

The trigger is deliberately NOT 'the histogram summed to zero'. A dark cell legitimately produces an all-zero histogram at any footprint because every pixel sits under the 0.05 weight gate (ShapeContext.swift:32); keying on the sum would rewrite every dark region of every render and overwrite the ASTSK-47-frozen preset.

Scope held: the shipping footprint is 2x4, so the fallback never fires at the frozen preset and every golden is byte-identical. thumbnailMaxPixelSize untouched. VesperPresetTests and the ASTSK-47 portrait regression tests pass unmodified. ASKI-16.1 (edgeMap) not touched.

Measured impact: at oversample 1 the thumbnail budget lands the pitch on 1x2 for essentially every source aspect and column count (975x1280, 1024x1024, 512x1536, 1536x512 all checked at columns 40-160), so the whole oversample-1 configuration used to render blank. It now paints.

AC#1 - truncation contract. Settled on the 'explicit, documented, tested contract' branch. The contract is: pitch is the floored integer quotient, sampling is origin-anchored, so the read rectangle is exactly columns*cellWidth x rows*cellHeight and the unread remainder is thumbnailWidth % columns by thumbnailHeight % rows. Note the remainder is bounded by the GRID dimension, not the cell pitch - it routinely spans several cells (16 rows against a cellHeight of 4 at the shipping arm). Documented at ASCIIConverter.prepareConversion, at both CellSampling samplers, on SamplingGeometry.droppedX/droppedY, and in the AskiColorLab SampledSource mirror.

AC#3 - regression tests. Tests/AskiTests/SamplingLatticeContractTests.swift, 5 tests: the modulus identity over a 7-arm source-aspect/oversample sweep, the shipping arm pinned at droppedY == 16 of 160, the oversample-1 never-silently-blank sweep over 5 arms including the reported 975x1280 case at both columns 120 (refused geometry) and columns 80 (1x2 pitch, must paint), the zero-support footprint detection, and the brightness-ordering contract of the fallback itself.

Phase B2 (fractional lattice) ABORTED, deliberately and with evidence, before any code was written. The specified mechanism - remainder distribution, per-cell height floor or floor+1 - collides with this note's own cell-height parity finding (section 3, consequence 2). Verified against the shipped code: a 2x4 cell reaches bins {51, 54, 56}, all radial bin 4; a 2x5 cell reaches bins {3, 8}, all radial bin 0. The two supports are DISJOINT. At the shipping arm (thumbnail 160, rows 36) remainder distribution yields 16 rows of height 5 and 20 rows of height 4, so 16 of 36 grid rows would be scored on a disjoint set of descriptor coordinates from the other 20, interleaved down a single image, at the frozen preset. Today the parity discontinuity 'never fires on any realistic render' because every row is 2x4; B2 would make it fire on every render. That is strictly worse than the uniform truncation it removes, so it was not landed - this is an abort on the merits, not on golden churn or benchmark budget.

The truncation-free fix that preserves uniform pitch is to make thumbnailHeight an exact multiple of rows, which means changing thumbnailMaxPixelSize - explicitly out of scope for this task. A cheaper partial option is to centre the lattice (origin offset droppedY/2) so the loss is split top and bottom instead of being systematically bottom-only; it keeps uniform pitch and costs nothing at runtime, but it still drops the same fraction and it churns every golden, so it is a product decision rather than a bug fix. Both are follow-up material.
<!-- SECTION:NOTES:END -->
