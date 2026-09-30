---
id: ASKI-86
title: Reject incomplete benchmark runs and unavailable required metrics
status: To Do
assignee: []
created_date: '2026-09-30 00:20'
labels:
  - performance
  - benchmarks
  - tooling
dependencies: []
references:
  - justfile
  - Package.resolved
  - Benchmarks/AskiBenchmarks/Benchmarks.swift
  - Benchmarks/AskiBenchmarks/VideoPipelineBenchmarks.swift
priority: high
type: bug
ordinal: 87000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The 2026-09-29 sweep at c49bbdacdcaaafd6211f5503f23b492785127135 on Xcode 27 / Swift 6.4 found that the canonical benchmark plugin command returned exit 0 after a selected video workload failed setup with AVFoundation -11800 / OSStatus -12903 and produced no samples. The other five selected workloads still printed results. A video-only retry with host encoder access succeeded (wall p50 327 ms), so the failure was an execution constraint, not a proven encoder defect. Separately, allocatedResidentMemory was silently absent from result tables after explicit omission warnings because the active malloc backend did not produce it.

justfile:61-62 trusts the plugin exit status. Package.resolved pins package-benchmark 1.35.0; its BenchmarkRunner setup catch emits an error and returns. Reproduction selection: xcrun swift package --disable-sandbox benchmark --target AskiBenchmarks --filter '^(animation-build-gradient-80cols-k6|animation-grid-at-80cols|tile-quantize-rich-512x512-256cols-adaptive16|masked-ascii-convert-render-80cols|video-e2e-one-shot-720p-80cols-12frames|render-image-gradient-80cols)$' --no-progress in an execution context that denies video encoder setup.

This task owns validity/completeness of benchmark evidence. ASKI-5 owns numeric regression budgets and gate placement. Do not call an incomplete run passing or fill missing measurements with zero.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The canonical validation command exits nonzero when any selected workload fails setup/execution, returns no samples, or is unexpectedly absent; diagnostics identify the workload and cause.
- [ ] #2 An explicitly required unavailable metric fails validation or uses a documented, verified alternative; optional metric omissions are recorded and cannot satisfy a required budget.
- [ ] #3 Validation covers intentional setup failure, execution failure, empty selection, missing samples, unavailable required metrics, and a successful complete run.
- [ ] #4 Successful results retain workload identity, units, toolchain/backend identity, and enough information to distinguish a complete run from a partial one.
- [ ] #5 The solution preserves existing thresholds and the one-build just check ordering; relevant tooling checks, just check, and the validated benchmark subset pass.
<!-- AC:END -->
