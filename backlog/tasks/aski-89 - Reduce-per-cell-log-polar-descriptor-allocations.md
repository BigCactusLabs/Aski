---
id: ASKI-89
title: Reduce per-cell log-polar descriptor allocations
status: To Do
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-10-27T15:54:00Z'
labels:
  - performance
  - conversion
  - allocations
dependencies: []
references:
  - Sources/Aski/Algorithms/LogPolarKernel.swift
  - Sources/Aski/Algorithms/ShapeContext.swift
  - Sources/Aski/GridRowWalk.swift
  - https://www.swift.org/blog/swift-6.2-released/
priority: medium
type: spike
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LogPolarKernel.swift:304 creates grayscale storage per cell, ShapeContext.swift:21 allocates 60 histogram floats, and LogPolarKernel.swift:280-289 allocates/repackages 15 SIMD4 lanes. Edge emphasis adds Sobel storage at :322. These temporaries scale with cell count and repeat for every frame. The 2026-09-29 c49bbd release conversion run reported roughly 16K mallocs for the 80-column workload, but no allocation profile attributed that total to these arrays.

Swift's current official guidance describes InlineArray and Span as tools for fixed/contiguous storage; deployment compatibility and actual benefit must be checked here before choosing any storage change. ASKI-13 owns renderer/Core Text allocations and ASKI-72 already consolidated converter loops. This task owns descriptor/extractor scratch only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A release allocation profile attributes grayscale, histogram, SIMD-lane, and optional Sobel costs separately from unrelated conversion allocations.
- [ ] #2 Measurements cover ordinary, ranked, residual and temporal paths, 80/120-column and larger grids, edge emphasis, higher oversampling, and forced serial/parallel execution.
- [ ] #3 Any adopted storage path preserves exact descriptors and grids, respects retained research descriptor lifetimes, and has no shared mutable scratch or concurrency warnings.
- [ ] #4 Any newer standard-library storage is verified against Swift 6.3+ and the package's iOS 18/macOS 15/visionOS 2 deployment minimums.
- [ ] #5 The task records allocation reduction and a material end-to-end result or a rejection; adopted code passes just check and relevant benchmarks without relaxed thresholds.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Groundwork — 2026-10-27 (base 4c675957)

Deployment check against the minimum supported compiler source: Swift 6.3's `InlineArray` declaration is `@available(SwiftStdlib 6.2, *)`; its availability macros map that to iOS/macOS/visionOS 26, above this package's iOS 18 / macOS 15 / visionOS 2 floors. A newer compiler is not permission to use it unconditionally. By contrast, `Span` uses the back-deployed `SwiftCompatibilitySpan 5.0` availability, but is a non-owning, nonescaping view and does not itself remove the owner array allocation. New Swift 6.4-only storage or temporary-allocation APIs also cannot silently raise the Swift 6.3 consumption minimum.

Start by attributing the four existing temporary families (grayscale, optional Sobel, 60 histogram floats, 15 SIMD lanes). Prefer a bounded experiment that removes an intermediate representation or uses invocation-owned scratch while keeping the escaping research descriptor an owned value. Avoid adding an availability-split production path before evidence warrants that extra maintenance. Native compile probes must cover all three deployment floors, ordinary/ranked/residual/temporal callers, and forced row modes; no storage optimization or speedup is claimed by this note.

Primary sources inspected: https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/stdlib/public/core/InlineArray.swift ; https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/utils/availability-macros.def ; https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/stdlib/public/core/Span/Span.swift ; https://www.swift.org/blog/swift-6.4-released/ .
<!-- SECTION:NOTES:END -->
