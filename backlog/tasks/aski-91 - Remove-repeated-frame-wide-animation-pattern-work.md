---
id: ASKI-91
title: Remove repeated frame-wide animation pattern work
status: To Do
assignee: []
created_date: '2026-09-30 00:20'
labels:
  - performance
  - animation
dependencies: []
references:
  - Sources/Aski/Animation/PatternEvaluator.swift
  - Sources/Aski/Animation/ASCIIGrid+OngoingPattern.swift
  - Sources/Aski/Animation/AnimatedASCIIGrid.swift
  - Benchmarks/AskiBenchmarks/AnimationBenchmarks.swift
priority: medium
type: spike
ordinal: 92000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PatternEvaluator.ongoingAlpha recomputes pulse parameter sanitization and sine for each cell although pulse alpha only depends on pattern/time. entranceAlpha calculates spatial start before its completed-reveal exit, and radialDistance repeats anchor normalization and four corner distances per cell. ASCIIGrid.applyingOngoingPattern maps/rebuilds every cell even for valid zero-depth or zero-amplitude overlays that leave the grid unchanged.

The 2026-09-29 sweep verified these paths at c49bbd. Existing animation grid benchmarks exercise cycling without entrance/ongoing patterns, so their roughly 20 microsecond p50 does not measure this workload. ASKI-11 is motion-conditioned selection; ASKI-18 fixed public validation and its validation-before-empty behavior must remain.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pattern-specific release benchmarks cover pulse, directional wave, radial reveal, completed reveal, and neutral overlays at 80/192/288 columns, reporting time and allocations.
- [ ] #2 Any adopted optimization preserves exact characters, alpha, color, coverage, composition/mask metadata, time boundaries, and behavior for nonfinite time and off-grid anchors.
- [ ] #3 Invalid pattern parameters are still rejected at the same public boundaries, including empty grids; valid neutral overlays preserve the current cell-value semantics.
- [ ] #4 Frame-wide work no longer scales with cell count where equivalence is proven, with bounded storage and a measured benefit rather than an assumed cache win.
- [ ] #5 The task records adopt/reject against a stated end-to-end bar; adopted code passes just check and animation/media benchmarks without relaxed thresholds.
<!-- AC:END -->
