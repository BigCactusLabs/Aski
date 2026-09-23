---
id: ASKI-31
title: Sampling lattice still drops the bottom remainder - the pitch-preserving fixes
status: Done
assignee: []
created_date: '2026-08-19 15:25'
updated_date: '2026-09-02 20:04'
labels: []
dependencies: []
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-25 settled the truncation on the 'explicit, documented, tested contract' branch: the converter reads the top-left columns*cellWidth x rows*cellHeight rectangle and the bottom/right remainder (thumbnailWidth % columns by thumbnailHeight % rows) is never sampled. At the shipping arm that is 16 of 160 thumbnail rows, 10 percent of image height, always off the bottom. The contract is now honest, but the pixels are still unread.

The obvious fix - distribute the remainder so per-cell height is floor or floor+1 - was attempted and ABORTED on the merits during ASKI-25, with evidence. Cell-height parity flips which descriptor coordinates are reachable (2026-08-19-sampling-lattice-support-collapse.md section 3, consequence 2). Verified against the shipped code: a 2x4 cell reaches bins {51, 54, 56}, all in radial bin 4; a 2x5 cell reaches bins {3, 8}, all in radial bin 0. The supports are DISJOINT. Remainder distribution at the shipping arm (thumbnail 160, rows 36) gives 16 rows of height 5 and 20 rows of height 4, so 16 of 36 grid rows would be scored on disjoint descriptor coordinates from the other 20, interleaved down a single image, at the frozen preset. Today the parity discontinuity never fires on a realistic render because every row is 2x4. Non-uniform pitch would make it fire on every render. Do not reopen that approach without first resolving the parity split.

Two approaches remain, both of which preserve a UNIFORM cell pitch and therefore cannot trigger the parity split:

(a) Make the thumbnail an exact multiple of the grid. Change thumbnailMaxPixelSize so thumbnailHeight is divisible by rows (and width by columns), which drives droppedX and droppedY to zero with no change to the sampler. This was explicitly out of scope for ASKI-25 because thumbnailMaxPixelSize carries the ASTSK-47 portrait blank-render fix and its regression tests. It changes every golden.

(b) Centre the lattice. Offset the sampling origin by droppedY/2 and droppedX/2 so the loss is split between top and bottom instead of being systematically bottom-only. Keeps uniform pitch, costs one added base offset at runtime, needs no benchmark headroom. It does not recover the dropped fraction, it only stops the loss being one-sided. Also changes every golden.

Both are product decisions about the frozen preset's output, not bug fixes, so they need an explicit call before implementation. Evidence for the no-harm case should come from a selection-ceiling before/after under both MAE and GMSD so it composes with whichever house oracle ASKI-27 settles on.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The bottom/right remainder is either sampled or the sampled rectangle is deliberately centred, with the choice between approaches (a) and (b) recorded and justified
- [x] #2 Cell pitch stays uniform across the grid, verified by a test, so the cell-height parity split cannot fire
- [x] #3 Golden regeneration is deliberate and enumerated, and a selection-ceiling before/after is reported under both MAE and GMSD
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24 (deep pass): Not resolved by the ASKI-25 lattice fix (that documented the truncation, didn't remove it). Gotcha: AskiColorLabSamplingLatticeTests.swift:96 actively asserts droppedY > 0 on the shipping arm, so either approach must amend that test, not only goldens.

Audit 2026-09-02 (docs-audit PR #38): the 2026-08-24 gotcha above is now STALE and the description's premise has moved. ASKI-65 (PR #37, merged) drives droppedX/droppedY to zero by drawing the thumbnail into an exact columns*cellWidth x rows*cellHeight raster. So: the 'bottom/right remainder is never sampled / 16 of 160 thumbnail rows' claim in the description is no longer true of shipping code, and AskiColorLabSamplingLatticeTests.swift:96 now asserts the OPPOSITE of the gotcha - it reads '#expect(geometry.droppedY == 0)'. No test needs amending on that axis any more.

This task is NOT closed by ASKI-65. Status against the ACs:
- AC #2 SATISFIED. Cell pitch is uniform by construction (SamplingGeometry carries scalar cellWidth/cellHeight) and is tested - SamplingLatticeContractTests.swift:51 latticeIsAnExactMultipleOfTheGrid.
- AC #1 satisfied in substance, not in form. No row goes unread. But ASKI-65 took a THIRD approach rather than adjudicating (a) vs (b): resample the thumbnail into a lattice-sized raster. Approach (a) would also have shifted the source-to-thumbnail scale, so the distinguishing cost of the shipped approach is not the rescale magnitude - it is the SECOND resampling stage and its interpolation blur (CellSampling.swift:207 samplingLattice re-reads the thumbnail at pixelWidth x pixelHeight). That stage is new and unmeasured.
- AC #3 HALF DONE, and the missing half is the load-bearing one. Golden regeneration is deliberate and enumerated (commit 4db60d6 lists all six). The selection-ceiling before/after under BOTH MAE and GMSD was never run: no such invocation on any of the four ASKI-65 commits, no CSV, no docs/Research note for ASKI-65 at all. The instrument exists and was available (AskiColorLabCommand.swift, selection-ceiling subcommand).

THE OPEN WORK IS EXACTLY AC #3's MEASUREMENT: run the selection-ceiling before/after under MAE and GMSD across the ASKI-65 boundary. The description already explains why this is required - these are product decisions about the frozen preset's output, not bug fixes - and that reasoning applies with more force to the shipped third approach, which added an interpolation stage neither (a) nor (b) had. Re-recording a golden proves determinism, not no-harm.

2026-09-02 close-out: AC#3's missing half ran. Selection-ceiling before (64a8f98) / after (main with ASKI-65) under MAE and GMSD, reading rule pre-registered and committed before any number was read. Frozen preset (blocks, 76 col, oversample 2) production-arm MAE ratio after/before = 1.0016 on nasa-steerable-v1 and 1.0085 on nasa-structure-v1, both inside the 1.01 no-harm guard; GMSD agrees in direction (1.0041 / 1.0070). Effect decays to parity by oversample 16; standard and braille improve ~1.1% at oversample 2. Verdict NO HARM. AC#1's (a)/(b) choice is recorded after the fact as (c) - the shipped lattice raster - which dominates (b) and beats (a) at a measured cost of at most 0.85% MAE on blocks. Note: docs/Research/2026-09-02-aski-31-lattice-no-harm.md; artifacts: docs/Research/Results/2026-09-02-aski-31-lattice-no-harm/.
<!-- SECTION:NOTES:END -->
