---
id: ASKI-116
title: Re-measure fallback noise-image reuse with a corrected instrument
status: To Do
assignee: []
created_date: '2026-11-25T19:10:46Z'
labels:
  - performance
  - effects
  - research
dependencies:
  - ASKI-95
references:
  - docs/Research/2026-11-25-aski95-fallback-noise-reuse.md
priority: low
ordinal: 117000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up to ASKI-95, filed at the owner's request on 2026-11-25. ASKI-95's bounded noise-image cache kept all 96 outputs byte-identical and cut the 1920x1080 dust+grain Core Image fallback stage by a median 78.3%, but it was rejected on two changing-seed dust guards (+4.21% and +2.78% against a 2% limit). Those guards were confounded: the 2% limit sat below the measured run-to-run noise, and the changing-seed workloads were not guaranteed to miss the cache. This task re-measures with a corrected instrument and a rule registered before any timing.

Context: the fallback runs only where the Metal kernels are unavailable (devices without Apple GPU family 6, such as A12 iPhones and Intel Macs, or when the metallib fails to load). Seeds are fixed per EffectChain entry, so same-seed reuse is the realistic per-frame case. Replay material: Scripts/research/aski95-2026-11-25/ (harness, candidate-treatment.patch, CSVs) and docs/Research/2026-11-25-aski95-fallback-noise-reuse.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A decision rule, including an inconclusive branch, is appended to this task before any timing run
- [ ] #2 Changing-seed workloads use per-case disjoint seed streams so every lookup misses, and same-seed workloads are sized or bounded so the cache does not thrash
- [ ] #3 A/A control pairs establish the noise floor on the measuring host before guard thresholds are fixed, and every threshold sits above that floor
- [ ] #4 Retained bytes are reported per workload alongside the timings
- [ ] #5 The cache is adopted only if the frozen rule passes and the effect suites, just check and the effects benchmarks pass; otherwise the verdict and evidence are recorded in a research note and nothing ships
<!-- AC:END -->
