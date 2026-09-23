---
id: ASKI-65
title: >-
  Converters drop the bottom source rows: resample the thumbnail to an exact
  grid multiple (GH #36)
status: Done
assignee: []
created_date: '2026-09-02 04:40'
updated_date: '2026-09-02 07:21'
labels:
  - bug
dependencies: []
priority: high
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub issue #36. All three converter paths (ASCIIConverter.prepareConversion, ASCIIConverter+Temporal, TileGridConverter) take cellWidth = thumbnail.width / cols and cellHeight = thumbnail.height / rows and sample from the origin, so thumbnail.height % rows bottom rows (and width % cols right columns) are never read, while the renderer under preserveSourceAspect draws the grid at the full source aspect. Measured on a 3072x2048 source at 384 columns (rows = 116): NCC of the render against the top 1856 source rows is 0.954 versus 0.674 against all 2048, i.e. the bottom 9.4 percent is dropped and the covered region is stretched over the full frame (43 CSS px vertical drift at 1440/DPR2 in the bcl-web consumer). ASKI-25 made this truncation an explicit contract and aborted the fractional-lattice fix on the merits (2x4 and 2x5 cells reach disjoint log-polar bins, so mixed row heights would interleave disjoint descriptor supports). Its record names the truncation-free fix that keeps a uniform pitch: make the sampled raster an exact multiple of the grid. Fix: keep the floored integer pitch, then draw the decoded thumbnail into an RGBA8 buffer of exactly (cols * cellWidth) x (rows * cellHeight) pixels with high-quality interpolation, so every source pixel contributes, the pitch stays uniform (2x4 at the frozen preset), and droppedX == droppedY == 0 by construction. Every golden churns; that is expected and authorized by the issue.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All three converter paths sample a raster whose size is exactly columns*cellWidth by rows*cellHeight; SamplingGeometry.droppedX and droppedY are 0 for every arm of the existing SamplingLatticeContractTests sweep and the shipping arm (thumbnail 160, columns 80, oversample 2) keeps a uniform 2x4 pitch
- [x] #2 The AskiColorLab SampledSource lattice mirror and any other instrument that re-partitions the source use the same exact-multiple raster, so research callers and the converter agree
- [x] #3 A regression test reproduces the issue's geometry (3072x2048 source, 384 columns, rows 116) and asserts the sampled raster covers the full source height: a synthetic image with a distinct band in the bottom 9 percent must show that band in the bottom grid rows
- [x] #4 Comments in prepareConversion, CellSampling, SamplingGeometry and ASCIIConverter+Research that describe the truncation contract are rewritten to describe the exact-multiple raster; docs that state the 10 percent drop are updated
- [x] #5 Goldens and snapshots regenerated where they churn; just check green locally; benchmark thresholds untouched
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design locked 2026-09-02 from ASKI-25 Implementation Notes: fractional/uneven cell bounds rejected on the merits (2x4 vs 2x5 cells reach disjoint log-polar bins). Fix keeps the floored integer pitch and draws the decoded thumbnail into a raster of exactly columns*cellWidth x rows*cellHeight with high-quality interpolation, so coverage is total and the pitch stays uniform. Branch aski-65 in a sibling worktree; Claude implementer dispatched; frontier-search on cell-partition practice running in parallel as a check.

Frontier-search check (2026-09-02, source-verified): chafa resamples the source to exactly columns*8 x rows*8 via smolscale then reads rigid 8x8 cells (chafa-canvas.c, chafa-pixops.c) - the same exact-multiple design as this fix. libcaca (dither.c) and jp2a (image.c) use uneven integer bounds y0=r*H/R, y1=(r+1)*H/R, the option ASKI-25 rejected for disjoint descriptor supports. OpenCV INTER_AREA is true fractional-area; Pillow BOX is centroid membership, not fractional area. No published measurement of uneven-cell artifacts at ASCII grid scale was found.

Implementation landed on branch aski-65 (3 commits on 64a8f98): samplingLattice helper in CellSampling.swift, three call sites, readRGBA8 width:height: overload with .high interpolation; same-size draw verified byte-identical. Regression test bottomSourceBandReachesTheBottomGridRow confirmed fail->pass at the issue geometry. 7 snapshots + 2 DocC renders re-recorded, none loosened. media 152/152, deadlock sentinels 2/2, docc PASS. OPEN: core phase 1529/1532 - competitionRampsYieldGradedDoseResponse (ASTSK-36 dose-response instrument) now reports 2 distinct levels against a >=3 bar because its 512px/64-col fixture (rows 29, cell 8x17) is squeezed 3.7 percent vertically by the lattice; the lab no-downscale premise (converterWouldDownscale guard) no longer implies native sampling unless side is a multiple of both columns and rows. Owner decision needed: (a) resize the isoluminant battery to an exact lattice and re-run ASTSK-36, (b) give the no-downscale lab family an exact-lattice geometry, or (c) accept the re-measured dose-response and re-baseline the bar with a fresh verdict.

Codex PR review P1 (same finding as the escalation) ruled option (b): labs refuse non-exact fixtures (latticeWouldResample in isoluminant, shape-residual, decolor) and the isoluminant battery is authored at the exact-lattice height (ToolArgumentBounds.exactLatticeHeight; 512x522 at 64 cols). Re-measurement on exact lattices: 8x18 inert at every lambda on 4 geometries, 8x19 binary (onset below 0.25), 8x20 inert - the 2026-06-11 graded curve existed only on the defective 8x17 (2.125 aspect) truncated cell. Bar unchanged; graded assertions pinned withKnownIssue; addendum appended to docs/Research/2026-06-11-isoluminant-dose-response.md; follow-up ASKI-66 filed.

MERGED to main 2026-09-02 via PR #37 (merge 611703d, branch d4348f3). Final gate on the branch: core 1532/1532 with 3 known issues (ASKI-66 pins), media 152/152, sentinels 2/2, docc PASS. Codex P1 thread answered and resolved. Worktree and branches removed. GH #36 closed by the merge.
<!-- SECTION:NOTES:END -->
