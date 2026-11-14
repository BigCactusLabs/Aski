---
id: ASKI-86
title: Reject incomplete benchmark runs and unavailable required metrics
status: Done
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-11-13T06:33:00Z'
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
  - https://github.com/BigCactusLabs/Aski/pull/7
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
- [x] #1 The canonical validation command exits nonzero when any selected workload fails setup/execution, returns no samples, or is unexpectedly absent; diagnostics identify the workload and cause.
- [x] #2 An explicitly required unavailable metric fails validation or uses a documented, verified alternative; optional metric omissions are recorded and cannot satisfy a required budget.
- [x] #3 Validation covers intentional setup failure, execution failure, empty selection, missing samples, unavailable required metrics, and a successful complete run.
- [x] #4 Successful results retain workload identity, units, toolchain/backend identity, and enough information to distinguish a complete run from a partial one.
- [x] #5 The solution preserves existing thresholds and the one-build just check ordering; relevant tooling checks, just check, and the validated benchmark subset pass.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Inspect pinned native runner and allocator APIs; run bounded native success and genuine setup/execution failure captures without permanent fault switches; add runtime allocator observation if supported, portable regressions and precise evidence documentation. Preserve thresholds and check ordering; leave final acceptance to lead.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Existing work reconciled — 2026-10-27

PR #7 is open at 5493edb992ab57ee2c4a5e16e9ef8106068ab96e: https://github.com/BigCactusLabs/Aski/pull/7 . Its description reports native `just check`, complete six-workload smoke evidence, and required-unavailable-metric rejection. That is the PR's recorded evidence, not a new execution here. Genuine native setup/execution failure and allocator verification remain acceptance work; the complete-row short-write limitation remains documented.

The independent paired reader in `Scripts/research/compare-benchmarks.py` consumes this report contract without altering the capture producer or existing gate. See `docs/agents/paired-benchmarks.md`. Marked In Progress to reflect existing work, not Done.

Audit 2026-11-12: PR #7 is no longer open: it merged as 969ba20 on 2026-11-12 and describes itself as validation groundwork, not completion of this task. Its recorded evidence covers AC#3-5; AC#1 and AC#2 have synthetic coverage only. Closing is an owner call. PRs #9 and #10 use this task's branch as their base.

2026-11-13: owner ruling: AC#3-5 are met by public PR #7 (969ba20; synthetic setup/execution/empty/missing/required-metric coverage, inventory with units and provenance, just check passed with thresholds unchanged). AC#1 and AC#2 stay open: a genuine native setup/execution failure and a probed (not configured) allocator identity remain. Moved to To Do because no work is active.

2026-11-13: PRs #9 and #10 now target main, so deleting work/aski-86-benchmark-validity no longer closes them.

2026-11-13 bounded native replay: canonical just bench rejected genuine Foundation setup and execution failures (NSCocoaErrorDomain 256 / POSIX 20) with exit 1 despite plugin exit 0; a valid render workload still exported samples. Temporary failure registrations were restored. In-process allocator observations resolve the interposer image and show positive allocation/free counter deltas. Added parser regressions; host-access focused suite passed 53 tests with one existing expected failure (short-write limitation). Full smoke, just check and just test-infra remain integration gates; acceptance and completion belong to the lead.

2026-11-13 review repair 86-R1: raw allocator observations moved out of comparable identity into allocator_observations; identity retains only normalized observed backend and image basename. Mixed observed identities within a capture fail validation. Cross-run regression verifies distinct process IDs, paths and deltas remain comparable while changed observed backend remains incompatible. Retained native logs replayed through repaired parser; native helper unchanged. Final gates remain with lead.

Completed 2026-11-13 after native acceptance: actual Foundation setup/execution failures produced no samples while plugin exited zero and canonical validator exited one; explicitly required unavailable allocatedResidentMemory also failed. The actual benchmark process resolved the loaded interposer and positive malloc/free deltas. Stable backend identity excludes PID/path/deltas so compatible paired captures compare; raw observations remain. Full just check passed 1537 core/177 media/2 sentinels and DocC; test-infra passed 139 tests with one existing expected failure; all six canonical smoke workloads exported required wallClock/mallocCountTotal. Independent review and lead diagnostics fix complete. No thresholds/goldens/one-build ordering changed. Public compact evidence: Scripts/research/aski86-2026-11-13/. Only evidence/changelog/task metadata changed after the frozen source gate.
<!-- SECTION:NOTES:END -->
