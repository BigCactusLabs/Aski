---
id: ASKI-109
title: Diagnose allocator-reset crashes in native benchmark captures
status: To Do
assignee: []
created_date: '2026-11-13T08:41:00Z'
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
- [ ] #1 A minimal native reproduction or bounded diagnostic matrix separates probe, registration and allocator lifecycle effects, with failed commands, crash stacks and exact pins retained.
- [ ] #2 Any fix has causal evidence and native regression coverage; real allocator observation, missing-metric rejection and nonzero process exits remain enforced.
- [ ] #3 Fresh complete captures and unchanged absolute budgets pass with frozen identities; original invalid ASKI-92 observations are never pooled or replaced.
- [ ] #4 Any dependency or instrumentation change passes full local just check and documents the scope of its evidence.
<!-- AC:END -->
