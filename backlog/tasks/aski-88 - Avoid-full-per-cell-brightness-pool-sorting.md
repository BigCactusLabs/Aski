---
id: ASKI-88
title: Avoid full per-cell brightness pool sorting
status: Done
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-11-13T10:22:00Z'
labels:
  - performance
  - matching
  - conversion
dependencies: []
references:
  - Sources/Aski/ShapeMatching.swift
  - Sources/Aski/Algorithms/LogPolarKernel.swift
  - Benchmarks/AskiBenchmarks/AnimationBenchmarks.swift
  - Scripts/research/aski88-2026-11-13/README.md
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
- [x] #1 The investigation reports repeated release time/allocations for N=8/95/256 and representative K values, plus 80/120-column conversions and ranked animation construction.
- [x] #2 Any adopted selection path produces the exact existing pool membership/order, winners, ranked candidates, and residuals for equal brightness, midpoint ties, duplicate vectors, and zero/orthogonal descriptors.
- [x] #3 Candidate distance arithmetic and deterministic tie rules remain unchanged in serial and parallel conversion.
- [x] #4 The task records adopt/reject against a stated end-to-end benefit bar and checks setup cost and small-bank regressions.
- [x] #5 If adopted, just check and relevant benchmarks pass without relaxed thresholds or a matcher-policy change.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Groundwork — 2026-10-27 (base 4c675957)

A sorted-brightness assumption is not an existing public contract: `GlyphBank.init` validates parallel-array counts, not brightness order, and the public `ShapeMatching` functions accept arbitrary arrays. The current control ranks the actual Float result of `abs(candidateBrightness[index] - queryBrightness)`, then original candidate index. Preserve that arithmetic and all scored/ranked wrappers, not only `findBest`.

First bounded candidate: a size-K selection buffer or heap ordered by that exact pair, followed by sorting the selected K. It avoids a new persistent representation and supports arbitrary input order. Compare against the unchanged full-sort control for N=8/95/256, K=1/12/24/36/N/>N, shuffled arrays, duplicate brightness, rounded midpoint ties, signed zero, and duplicate/zero/orthogonal descriptors. Keep N<=K as a control case and report setup plus small-bank costs.

A precomputed brightness index plus two-sided nearest expansion is a separate possible arm, not an assumed win: descending traversal on the left reverses duplicate-brightness indices, and distinct brightness values can have equal rounded Float distances. Either handle those equal-distance runs explicitly with original-index tie order or reject the arm. Do not sort the bank's canonical glyph arrays or alter nonfinite-input behavior in this performance task. Production code and adoption status are unchanged.

Audit 2026-11-12: public PR #14 (c81861c) landed groundwork: BrightnessPoolContractTests, BrightnessRankingContractTests, Scripts/research/brightness-pool/, docs/agents/brightness-pool-groundwork.md and 42 benchmark definitions. No captures have run. The sort is in findBestScored (CharacterMatcher, sort near :130); findBest wraps it.

2026-11-13 native heap evaluation: complete five-pair release study over all 42 names/four required metrics, with two excluded preparations and no retry. Four braille primaries pass (-25.40% to -28.37% median paired wall); all four standard primaries fail (+7.12% to +10.80%, 0/5 improving). Seventeen of 148 guards fail (13 CPU, four wall); all allocation/RSS guards pass. The frozen rule rejects this candidate. No bank-dependent exception or production heap is adopted.

Exact parity passed in both arms, including 21 optimized tests, and both full local gates passed (1541 core/177 media/two sentinels plus DocC). Candidate infrastructure passed 139 tests with one existing expected failure. Existing seven-workload capture and five unchanged absolute budgets passed. All selection/setup work is timed; no persistent index or setup cost is excluded. Desktop/system activity is disclosed, not described as quiet.

The bounded spike is complete as a rejection. Scripts/research/aski88-2026-11-13 retains the original amended pre-registration, 1680 raw histogram exports (five observations each), 840 paired rows, portable reproducer, exact source patches and native evidence. An independent exact-rational recomputation and the copied public packet replay agree. The shipping full sort, policies, goldens and thresholds remain unchanged; any new selection strategy needs a separately frozen investigation.
<!-- SECTION:NOTES:END -->
