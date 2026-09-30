---
id: ASKI-94
title: Reduce repeated original-image fallback draws in masked rendering
status: To Do
assignee: []
created_date: '2026-09-30 00:20'
labels:
  - performance
  - rendering
  - masking
dependencies: []
references:
  - Sources/Aski/Renderers/ImageRenderer.swift
  - Benchmarks/AskiBenchmarks/MaskBenchmarks.swift
  - Tests/AskiTests/MaskSnapshotTests.swift
priority: medium
type: spike
ordinal: 95000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ImageRenderer.drawMaskFallbackOverlay (Sources/Aski/Renderers/ImageRenderer.swift:1113-1141) computes the same original-image sizing rectangle, clips, and calls CGContext.draw for every cell with fallback coverage. The mask-ground inactive branch calls it with completedBranch=true at :1034-1047, forcing inverse coverage to 1 for every existing cell. This repeats draw/setup work for a completed image branch. Clipping may limit raster work; the source does not prove a full-source rasterization per cell.

Verified at c49bbd during the 2026-09-29 sweep. Current mask benchmarks cover transparent/solid fallback, not original-image fallback. ASKI-13 covers Core Text layout/allocation rather than repeated raster-image draws. Preserve existing ragged-grid behavior while ASKI-7 remains open.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release measurements cover original-image fallback at 80/160/320 columns, with and without mask ground, reporting draw counts, wall/CPU time, allocations and RSS.
- [ ] #2 Any adopted completed-branch path uses a draw count independent of cell count while preserving exact existing populated-cell coverage, including ragged grids.
- [ ] #3 Pixels preserve fill/fit/stretch placement, alpha, color space, hard/soft masks, fractional scale, and target-width geometry; any tolerance is justified before adoption.
- [ ] #4 Transparent/solid/character fallback paths have no material regression; variable-coverage image composition is changed only if measured evidence supports it.
- [ ] #5 The task records a material end-to-end result or rejection; adopted code passes just check and mask/render benchmarks, with the required no-harm census if frozen-preset goldens move.
<!-- AC:END -->
