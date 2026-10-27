---
id: ASKI-88
title: Avoid full per-cell brightness pool sorting
status: To Do
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-10-27T15:54:00Z'
labels:
  - performance
  - matching
  - conversion
dependencies: []
references:
  - Sources/Aski/ShapeMatching.swift
  - Sources/Aski/Algorithms/LogPolarKernel.swift
  - Benchmarks/AskiBenchmarks/AnimationBenchmarks.swift
priority: medium
type: spike
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ShapeMatching.findBest (Sources/Aski/ShapeMatching.swift:125-139) allocates an N-entry tuple array and sorts every candidate for each cell, then examines only min(topK,N) entries. findRanked and poolIndices repeat the brightness ordering work. This costs O(N log N) per cell for 95-glyph standard and 256-glyph braille banks, including tone-only fallback cells. The default brightness limit is 12-36. Exact ties use candidate index and are part of the matcher contract.

Source mechanism verified during the 2026-09-29 sweep at c49bbd; impact and an alternative were not benchmarked. ASKI-28 studied brightness-filter quality; this task only studies the cost of producing exactly the existing pool and output.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The investigation reports repeated release time/allocations for N=8/95/256 and representative K values, plus 80/120-column conversions and ranked animation construction.
- [ ] #2 Any adopted selection path produces the exact existing pool membership/order, winners, ranked candidates, and residuals for equal brightness, midpoint ties, duplicate vectors, and zero/orthogonal descriptors.
- [ ] #3 Candidate distance arithmetic and deterministic tie rules remain unchanged in serial and parallel conversion.
- [ ] #4 The task records adopt/reject against a stated end-to-end benefit bar and checks setup cost and small-bank regressions.
- [ ] #5 If adopted, just check and relevant benchmarks pass without relaxed thresholds or a matcher-policy change.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Groundwork — 2026-10-27 (base 4c675957)

A sorted-brightness assumption is not an existing public contract: `GlyphBank.init` validates parallel-array counts, not brightness order, and the public `ShapeMatching` functions accept arbitrary arrays. The current control ranks the actual Float result of `abs(candidateBrightness[index] - queryBrightness)`, then original candidate index. Preserve that arithmetic and all scored/ranked wrappers, not only `findBest`.

First bounded candidate: a size-K selection buffer or heap ordered by that exact pair, followed by sorting the selected K. It avoids a new persistent representation and supports arbitrary input order. Compare against the unchanged full-sort control for N=8/95/256, K=1/12/24/36/N/>N, shuffled arrays, duplicate brightness, rounded midpoint ties, signed zero, and duplicate/zero/orthogonal descriptors. Keep N<=K as a control case and report setup plus small-bank costs.

A precomputed brightness index plus two-sided nearest expansion is a separate possible arm, not an assumed win: descending traversal on the left reverses duplicate-brightness indices, and distinct brightness values can have equal rounded Float distances. Either handle those equal-distance runs explicitly with original-index tie order or reject the arm. Do not sort the bank's canonical glyph arrays or alter nonfinite-input behavior in this performance task. Production code and adoption status are unchanged.
<!-- SECTION:NOTES:END -->
