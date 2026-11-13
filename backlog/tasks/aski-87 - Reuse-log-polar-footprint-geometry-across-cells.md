---
id: ASKI-87
title: Reuse log-polar footprint geometry across cells
status: Done
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-11-13T05:22:00Z'
labels:
  - performance
  - conversion
  - matching
dependencies: []
references:
  - Sources/Aski/Algorithms/ShapeContext.swift
  - Sources/Aski/Algorithms/LogPolarKernel.swift
  - Benchmarks/AskiBenchmarks/Benchmarks.swift
  - https://github.com/BigCactusLabs/Aski/pull/8
documentation:
  - docs/benchmark-validation.md
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
- [x] #1 Before adoption, repeated release measurements include geometry preparation and report wall/CPU time and allocations for small grids, 80/120-column conversions, oversample 4/8, serial/parallel walks, and repeated frames.
- [x] #2 Descriptor lanes, ordinary/ranked winners, residuals, and final grids are bit-identical to the control across odd/even/degenerate footprints, threshold boundaries, both query polarities, and edge emphasis.
- [x] #3 Geometry reuse has bounded lifetime/storage and is safe under parallel row conversion without shared mutable scratch.
- [x] #4 The task records a material end-to-end benefit against a stated decision bar, or a rejection if only the isolated histogram improves.
- [x] #5 If adopted, just check and relevant conversion/animation benchmarks pass without loosening thresholds; any output-changing experiment is scoped separately under the research rules.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
2026-11-12 bounded validation: integrate PR #8 with main 2c3d1bd; commit a scalar control that removes only footprint setup/use, retaining all main fixes and identical instruments. Keep all 52 workloads and wall/CPU/allocation metrics, original warmup/iteration limits, and five adjacent alternating pairs if a full preparation capture projects within 20 minutes. Gate native parity first, cross-model review the instrument, and require the committed 5% primary benefit and 3% reproducible regression rule before adoption. Publish complete evidence and merge only the exact validated head.

2026-11-12 maintainer decision: merge with the explicitly recorded exception for the 2.10% primary; retain the original rule and numeric result unchanged, carry forward the passing executable gate, and run no additional benchmarks.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Existing work reconciled — 2026-10-27

PR #8 is open at 0af4bf6a71871b9efa5fc29d871edf00c4d3bc86: https://github.com/BigCactusLabs/Aski/pull/8 . It reports native parity and `just check`; the five-pair, 52-workload adoption measurement remains outstanding. Retain its scalar-control reconstruction, setup-inclusive timing and small/dotMatrix controls. `Scripts/research/compare-benchmarks.py` plus `docs/agents/paired-benchmarks.md` now provides the portable readout for the full predeclared inventory. Source cleanliness, identical harnesses, native parity and noisy-result judgment remain separate. No speedup or adoption claimed; task stays open.

### Native bounded replay — 2026-11-12

Measured candidate 51b736924fbcd4f4868ef5adf99fac9dfa51b3cd against scalar control 0c8c1bfeef85f44990e6bd0f5c7590010ca44708, based on main 2c3d1bd. Only footprint setup/use differs; instruments and dependencies match. All 52 workloads, three metrics and five adjacent alternating pairs completed in 641.749 seconds. All 1,560 raw exports and 780 paired rows are retained under Scripts/research/aski87-2026-11-12; reproduce.py verifies hashes, units, sample counts and medians. Every cell has ten samples per arm.

Seven of eight preregistered primary wall cases improve 6.85–15.71%. The 120-column, oversample-4 parallel case improves 2.10% (five of five directions improve) and misses the per-case 5% rule. All 108 end-to-end wall/CPU/allocation guards pass. A separately registered three-minute focused repeat stopped after one complete pair and a remaining-time inventory timeout; it is retained and cannot replace the full result. No more performance retries are planned. The full experiment does not meet its registered rule; AC4 and adoption were held pending the explicit decision recorded below.

Native just check at 2890a8b passed 1,537 core tests, 177 media tests, both sentinels, build/drift/format and DocC, including both scalar parity suites. Independent Opus review found no production correctness defect; its allocation rounding concern was addressed before measurement with identical unscaled output in both arms. Six existing conversion/animation captures are valid; the four animation workloads pass unchanged absolute budgets. No golden, public API, timed workload or threshold changes. Final publication just check passed in 156.719 seconds with the same 1,537 core / 177 media / two sentinel counts and DocC, on source 51b7369 plus the evidence/docs/backlog tree. Only result metadata and this note changed afterward; tested executable inputs and the decision rule are unchanged. Claims are limited to this synthetic gradient on one active Mac desktop; tile/temporal paths lack paired coverage and logical storage is not RSS.

### Explicit adoption decision — 2026-11-12

The maintainer approved merging PR #8 with the recorded exception: the 120-column, oversample-4 parallel primary improves 2.10% rather than 5%. The other seven primary cases improve 6.85–15.71%, all 108 regression guards pass, and exact native parity plus the full local gate pass. AC4 is accepted with this specific exception. The pre-run rule, complete evidence, incomplete focused attempt and numeric not_supported result are preserved; no threshold is changed or extra benchmark run made. Only decision/changelog/backlog metadata follows the passing final gate, so executable validation carries forward. Claims remain limited to the measured synthetic gradient on one Mac.

Audit 2026-11-12: the paired control commit 0c8c1bf is reachable only from cdx/pr8-short-control-20261112; keep that branch or tag the commit before any cleanup.

2026-11-13: owner confirmed the adoption exception (2.10% measured benefit against the pre-registered 5% bar), as recorded in 2f09985 and f1c54e2. The original rule and its not_supported result stand unchanged.

2026-11-13: control commit 0c8c1bf is preserved by the annotated tag evidence/aski87-control (pushed), so the cdx/pr8-short-control branch can be cleaned up safely.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Prepared log-polar footprint geometry is adopted with explicit maintainer acceptance of one 2.10% primary benefit below the registered 5% bar. Seven other primaries improve 6.85–15.71%; all 108 regression guards and exact scalar parity pass. All 52 workloads, three metrics and five pairs took 10m42s. Full just check passed 1,537 core / 177 media / two sentinels plus DocC; unchanged animation budgets pass. Raw evidence and the original not_supported numeric verdict remain committed. No public API, output, golden or budget-threshold changes; scope is one synthetic gradient on one Mac.
<!-- SECTION:FINAL_SUMMARY:END -->
