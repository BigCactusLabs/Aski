---
id: ASKI-109
title: Diagnose allocator-reset crashes in native benchmark captures
status: Done
assignee: []
created_date: '2026-11-13T08:41:00Z'
updated_date: '2026-11-13T16:35:00Z'
labels:
  - benchmarks
  - infrastructure
dependencies: []
references:
  - Scripts/research/aski92-2026-11-13/failed-attempts.json
  - Benchmarks/AskiBenchmarks/Benchmarks.swift
  - >-
    https://github.com/ordo-one/malloc-interposer/blob/1.6.1/Sources/MallocInterposerC/src/interposer-darwin.c
priority: high
type: bug
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two unchanged ASKI-92 study attempts stopped before a complete pair with SIGSEGV at 0x20c8 in malloc_interposer_reset (interposer-darwin.c:201), called by BenchmarkRunner.run (BenchmarkRunner.swift:133), using malloc-interposer 1.4.0 and package-benchmark 1.35.0 on macOS 27.0.1 / Swift 6.4. A separate 120-workload phase and existing budgets passed. Preserve failed evidence and frozen identities in Scripts/research/aski92-2026-11-13. Root cause is unproved: separate the allocator lifecycle, registration and observed-allocator probe instead of assuming a cause. A bounded 1.6.1 source comparison found the destructor, TLS initialization/access and reset bodies unchanged; this does not exclude an indirect fix. Do not change pins or suppress validation based on version alone.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A minimal native reproduction or bounded diagnostic matrix separates probe, registration and allocator lifecycle effects, with failed commands, crash stacks and exact pins retained.
- [x] #2 Any fix has causal evidence and native regression coverage; real allocator observation, missing-metric rejection and nonzero process exits remain enforced.
- [x] #3 Fresh complete captures and unchanged absolute budgets pass with frozen identities; original invalid ASKI-92 observations are never pooled or replaced.
- [x] #4 Any dependency or instrumentation change passes full local just check and documents the scope of its evidence.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Preserve both invalid ASKI-92 captures, exact dependency pins and original crash stacks. Run a bounded matrix to separate the native allocator lifecycle from Aski registration and observation code; retain the unresolved original reset attribution.
2. Correct only the reproduced stale thread-local pointer defect and verify exact allocation/free counters in native O1/O3 regressions.
3. Package the pinned, attributed local dependency with supported SwiftPM edit routing and strict source, metric, process-exit and lock checks.
4. Run fresh complete captures, unchanged absolute budgets and the full local gate. Record the tested snapshot and evidence limits.
5. Resume ASKI-92 as a new committed study with no pooling of old invalid observations.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The bounded native matrix reproduced a stale thread-local counter pointer when a later pthread destructor allocates. Pristine source crashed 3/3; the one-line correction passed 3/3. Five negative controls passed on both variants. The standalone program contains no Aski registration or allocator-observation code. This proves the lifecycle defect, not the original reset/0x20c8 cause; the original FD-protocol causal replay was not completed.

Native O1/O3 count regressions passed: 12 corrected lifecycle cases, four exact main-thread controls, and exact marginal allocation/free/byte deltas. All 12 pristine lifecycle cases crashed. Repeated thread create/join in one long-lived process was not tested.

The final supported SwiftPM edit route settles an exact effective lock, preserves it during measurement and restores the original only from verified bytes. Unknown source, routing or lock changes still fail. Fresh qualification passed six smoke workloads, all 237 canonical workloads, all 11 unchanged absolute budgets, 942 fast tests, and the full local gate: 1,539 core tests, 178 media tests, two sentinels and DocC. The tested snapshot is base e287ae2 plus source patch f8263e0b. Integration adds public evidence, task/ledger records and documentation only. Independent cross-family review was unavailable; lead source review and native/portable checks completed.

Evidence: Scripts/research/aski109-2026-11-13/README.md and native-qualification.json. Old invalid ASKI-92 captures remain invalid. ASKI-92 restarts with fresh source identities and observations.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Corrected a reproduced malloc-interposer thread-cleanup defect with an attributed pinned local copy, supported SwiftPM edit routing, exact source and lock guards, and native count regressions. Complete fresh benchmark captures, unchanged budgets and the full local gate pass. ASKI-92 can restart as a separate fresh study. The original reset-crash cause remains unproved; no historical observation is salvaged.
<!-- SECTION:FINAL_SUMMARY:END -->
