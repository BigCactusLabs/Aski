---
id: ASKI-94
title: Reduce repeated original-image fallback draws in masked rendering
status: Done
assignee:
  - '@codex'
created_date: 2026-09-30 00:20
updated_date: '2026-11-16T01:48:00Z'
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
- [x] #1 Release measurements cover original-image fallback at 80/160/320 columns, with and without mask ground, reporting draw counts, wall/CPU time, allocations and RSS.
- [ ] #2 Any adopted completed-branch path uses a draw count independent of cell count while preserving exact existing populated-cell coverage, including ragged grids.
- [ ] #3 Pixels preserve fill/fit/stretch placement, alpha, color space, hard/soft masks, fractional scale, and target-width geometry; any tolerance is justified before adoption.
- [ ] #4 Transparent/solid/character fallback paths have no material regression; variable-coverage image composition is changed only if measured evidence supports it.
- [x] #5 The task records a material end-to-end result or rejection; adopted code passes just check and mask/render benchmarks, with the required no-harm census if frozen-preset goldens move.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Freeze a minimal treatment and complete measurement rule from current source and existing groundwork. 2. Review the instrument and commit the rule before reading measurements. 3. Verify exact parity, then collect serial release profiles and five alternating paired captures with unchanged thresholds. 4. Adopt only if the frozen benefit and no-harm rules pass; otherwise retain evidence and reject the treatment. 5. Run required gates, record every AC result and integrate the verified outcome.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit 2026-11-12: ASKI-7 is Done (public PR #26); preserve the shipped ragged-grid semantics rather than treating ASKI-7 as open. Public PR #13 (f59926b) landed groundwork: MaskFallbackGroundworkTests and 27 aski94-* benchmark workloads. Line anchors have moved (drawMaskFallbackOverlay is now near ASCIIRenderer :1098).

2026-11-15 native study: rejected the one-draw completed-image candidate under the committed exact-parity rule. Control repeat: 1,161 cases, zero differences. Candidate: 239 pixel mismatches, zero metadata differences, all with partial ground. All exporter processes passed; candidate comparator exited 1 as specified. A valid single control baseline covers all 27 workloads and 108 required metrics, with source-derived draw counts. No candidate timing, paired regression or compatibility run followed the veto. AC2–4 remain unchecked because adoption/parity/comparative conditions were not met. Production, goldens and thresholds unchanged. Rule and complete portable evidence: docs/Research/2026-11-15-aski94-completed-original-fallback.md and Scripts/research/aski94-2026-11-15/README.md.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Closed as rejected. Exact pixel parity vetoed the candidate in 239 of 1,161 cases. Retained the replay patch, full mismatch inventory, all-case hashes and 27-workload control baseline. No production optimization adopted.
<!-- SECTION:FINAL_SUMMARY:END -->
