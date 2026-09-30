---
id: ASKI-87
title: Reuse log-polar footprint geometry across cells
status: To Do
assignee: []
created_date: '2026-09-30 00:20'
labels:
  - performance
  - conversion
  - matching
dependencies: []
references:
  - Sources/Aski/Algorithms/ShapeContext.swift
  - Sources/Aski/Algorithms/LogPolarKernel.swift
  - Benchmarks/AskiBenchmarks/Benchmarks.swift
priority: medium
type: enhancement
ordinal: 88000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ShapeContext.histogram60 (Sources/Aski/Algorithms/ShapeContext.swift:24-48) recomputes radius, logarithm, atan2, clamps, and bin assignment for every admitted pixel of every cell. Footprint coordinates are constant within a prepared conversion; production extraction calls it from LogPolarKernel.swift:279. This is invariant computation, not a proposal to alter descriptor support or matcher quality (ASKI-55).

The 2026-09-29 sweep at c49bbd on Swift 6.4 compiled the current source with -O and compared it with a scratch prepared-geometry histogram. All 1,200 random/threshold/degenerate cases had bit-exact 60-bin output. Across five alternating passes, median times for 20,000 histograms were original/prepared 2.830/2.041 ms at 2x3, 2.815/1.992 ms at 3x3, 8.588/2.551 ms at 8x12, and 29.151/7.917 ms at 16x24. These numbers exclude geometry preparation and do not establish end-to-end gains. Current 80-column conversion wall p50 was 4.764 ms in one release run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Before adoption, repeated release measurements include geometry preparation and report wall/CPU time and allocations for small grids, 80/120-column conversions, oversample 4/8, serial/parallel walks, and repeated frames.
- [ ] #2 Descriptor lanes, ordinary/ranked winners, residuals, and final grids are bit-identical to the control across odd/even/degenerate footprints, threshold boundaries, both query polarities, and edge emphasis.
- [ ] #3 Geometry reuse has bounded lifetime/storage and is safe under parallel row conversion without shared mutable scratch.
- [ ] #4 The task records a material end-to-end benefit against a stated decision bar, or a rejection if only the isolated histogram improves.
- [ ] #5 If adopted, just check and relevant conversion/animation benchmarks pass without loosening thresholds; any output-changing experiment is scoped separately under the research rules.
<!-- AC:END -->
