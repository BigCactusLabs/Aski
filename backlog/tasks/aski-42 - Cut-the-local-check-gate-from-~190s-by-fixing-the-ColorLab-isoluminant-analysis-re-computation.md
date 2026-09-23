---
id: ASKI-42
title: >-
  Cut the local check gate from ~190s by fixing the ColorLab isoluminant
  analysis re-computation
status: Done
assignee: []
created_date: '2026-08-20 20:33'
updated_date: '2026-08-20 22:43'
labels:
  - performance
  - tests
  - gate
  - research-labs
dependencies: []
priority: high
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Measured 2026-08-20 on this machine (M-series, 10 P-cores + 4 E-cores, Swift 6.3.2, macOS 26.5.2), warm .build, one sample per phase:

    format       1.9s   build   4.5s   lifecycle 0.9s   repo-map 0.7s
    test-core  159.1s   media   8.2s   sentinels 3.0s   docc     8.4s
    total      186.7s

The core test phase is 85% of the gate. Isolating suites shows the whole phase rides one critical path: AskiColorLab alone measures 149.7s of it, and inside ColorLab, AskiColorLabIsoluminantRescueTests measures 190.2s in isolation. Every other suite is small (Snapshots 2.3s, AskiDemoTests 3.5s, Access/Decolor/HDR 10.0s, PresetLab 1.4s, ParallelWalkParity 34.8s).

Root cause, verified: IsoluminantRescueCommand.analyze(columns: 64, fixtureSize: 512) costs ~27.4s per call (28.2s for a single analyze-driven test vs 0.8s for a trivial test in the same suite), and the test target calls it 8 separate times with identical arguments. IsoluminantFixture.makeBattery(side: 512) is likewise rebuilt 5 times. Nothing is shared between tests. swift-testing runs those calls concurrently, so the ~220s of redundant CPU collapses onto a ~150-190s wall-clock critical path that saturates the cores and starves every other suite — which is why swift-testing reports a ~145s duration even for trivial precondition tests in the same run.

This corrects the framing of ASKI-41 and of PRs #11/#13. Build-side caching is not the lever here: the warm build is 4.5s, so Swift Build, LLVM CAS compilation caching, sccache/ccache, and remote caches together address under 3% of the gate.

Frontier research, 2026-08-20 (see Notes for the source table): the SwiftPM compilation-caching pitch (forums.swift.org/t/pitch-compilation-caching-support-in-swiftpm/88079, 2026-07-06, PR swiftlang/swift-package-manager#10246) is still OPEN and unmerged, and it maps onto Swift Build settings, so it needs the swiftbuild backend. Swift Build became SwiftPM's default on main in PR #9661 (2026-01-28) and is expected in Swift 6.4; the rollout plan (forums.swift.org/t/swiftpm-on-swift-build-october-update/82889) recommends it broadly in 2026H1 and removes the native backend in 2026H2. Its measured performance is contested — swiftlang/swift-build#1111 (opened 2026-02-20, still open) reports 60-90s no-change builds from an uncached TargetBuildGraph. None of that changes a 4.5s warm build.

Two smaller, real levers found in the same research:
- swift-testing .serialized does NOT isolate a suite from unrelated concurrent tests (mbrandonw, forums.swift.org/t/running-tests-serially-or-in-parallel/72935, 2026-01-06; swiftlang/swift-testing#686 asks for this pattern to be documented). Collapsing the media and sentinel phases into the core process therefore requires nesting them under ONE containing .serialized suite, and even then it does not exclude core tests from running alongside. Only worth ~11s, and it risks re-opening the ASKI-39 contention the serial partition was added to prevent.
- Scripts/validate-docc.sh runs dump-symbol-graph over every target on each pass (8.4s). swift-docc-plugin supports --target; and the Aski symbol graph only needs regenerating when Sources/Aski changes, not when catalog Markdown changes.
- ST-0025 (tag-based test filtering, in review 2026-06-11..26, impl swiftlang/swift-testing#1531) would replace the brittle name-regex partitioning in the justfile with real tags once it ships. Not actionable on 6.3.2.

swift test --num-workers exists but requires --parallel and is an XCTest-process knob; its effect on swift-testing's in-process task scheduling is unverified. Do not assume it helps.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A single shared, lazily-computed IsoluminantRescueCommand.analyze(columns: 64, fixtureSize: 512) result (and one shared makeBattery(side: 512) battery) is reused across every test in AskiColorLabIsoluminantRescueTests, with no change to any assertion or verdict.
- [ ] #2 Re-measured with the same per-phase script and at least 5 warm samples: median total just check wall time drops by at least 90s versus the 186.7s baseline recorded above, and the per-phase medians are recorded in the task notes.
- [x] #3 just check stays green end-to-end (1260 core + 149 media + 2 sentinels, or the then-current counts) and no test is skipped, filtered out, or loosened to reach the target.
- [x] #4 The remaining critical path is re-profiled after the fix by timing suites in isolation, and the next-largest contributor (currently ParallelWalkParityTests at 34.8s) is either addressed or explicitly recorded as accepted cost.
- [x] #5 Scripts/validate-docc.sh is measured against a --target-scoped or symbol-graph-cached variant; adopt it only if it is faster AND still fails on a deliberately broken symbol link (falsification check, per the ASTSK-25 warm-cache precedent).
- [x] #6 No build-system change is adopted as part of this task: --build-system swiftbuild, compilation caching, and any external compiler cache stay out of scope and remain tracked by ASKI-41.
- [x] #7 AGENTS.md and README.md gate descriptions are updated only if the phase structure actually changes; if only test internals change, the docs are left alone.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Frontier-search source table (2026-08-20, all links retrieved this run):

T1 primary
- https://forums.swift.org/t/swiftpm-development-update-default-build-system-change/85548 — Swift Build becomes SwiftPM's default on main, PR #9661, 2026-01-28; expected in 6.4; revert via --build-system native.
- https://forums.swift.org/t/swiftpm-on-swift-build-october-update/82889 — rollout plan: recommend 2026H1, remove legacy backend 2026H2; 92% of SPI packages build on Linux.
- https://forums.swift.org/t/pitch-compilation-caching-support-in-swiftpm/88079 — swift package build-cache pitch, 2026-07-06; claims 68% (SwiftPM), 75% (SwiftSyntax), 67% (Vapor) faster fully-cached CLEAN debug builds. Clean, not warm.
- https://github.com/swiftlang/swift-package-manager/pull/10246 — that pitch's implementation: OPEN, unmerged, maps to Swift Build settings overrides.
- https://developer.apple.com/documentation/testing/parallelization — .serialized semantics.
- https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0025-tag-based-test-execution-filtering.md — ST-0025 tag: prefix for --filter/--skip; active review 2026-06-11..2026-06-26; impl swiftlang/swift-testing#1531.
- https://www.swift.org/blog/swift-6.3-released/ — 6.3, 2026-03-24; Swift Build opt-in; prebuilt swift-syntax for macros.

T2 maintenance / counter-signal
- https://github.com/swiftlang/swift-build/issues/1111 — opened 2026-02-20, still open, no assignee: uncached TargetBuildGraph causes 60-90s no-change builds on large graphs.
- https://github.com/swiftlang/swift-testing/issues/1086 — 'Expose parallelism' (worker count), opened 2025-04-21, open, no maintainer reply, no PR.
- https://github.com/swiftlang/swift-testing/issues/686 — the containing-.serialized-suite pattern is still an undocumented, unassigned-in-practice docs request.
- https://forums.swift.org/t/compilation-cache-remote-service-for-swift-build/84956 — swift build ignores cas-plugin-* flags; no CLI equivalent of COMPILATION_CACHE_REMOTE_SERVICE_PATH today.

T4/T5 practitioner
- https://forums.swift.org/t/running-tests-serially-or-in-parallel/72935 — mbrandonw, 2026-01-06: two separately .serialized suites can still run in parallel WITH EACH OTHER. This is the fact that blocks collapsing the media phase.
- https://tuist.dev/blog/2025/10/22/xcode-cache and Xcode 26 COMPILATION_CACHE_ENABLE_CACHING reports — 24-77% local-cache wins on large modular apps; explicitly noted that SPM dependencies are not yet cacheable. Different problem shape from a single package with a 4.5s warm build.

Cross-model triangulation: an independent GPT sweep run in parallel agreed on the Swift Build timeline, the .serialized limitation, the absence of SwiftPM test-impact analysis, and that sccache/ccache/Bazel are not worth it for one package. It additionally surfaced --disable-index-store, --num-workers (verified locally: exists, requires --parallel), and swift-docc-plugin --target. It did NOT find the dominant local cost; that came from measurement, not from the literature.

Counter-case considered and rejected: the standard practitioner advice is to keep the synchronous pre-commit gate under a few seconds and push slow checks to CI. Aski cannot do that — hosted CI runners lack GPU passthrough and media-engine access, so the local gate IS the authoritative gate (AGENTS.md, 'Gates run locally'). The available version of that advice is the existing check-fast / check split, which already exists. So the fix is to make the authoritative gate cheaper, not to move it.

Baseline command used, for re-measurement parity:
  per-phase timing of the eight just check steps, warm .build, one sample each; suite isolation via xcrun swift test --skip-build --filter <suite>.

== ASKI-42 execution record (2026-08-20, branch aski-42) ==

Fixes landed (3 commits, one PR):
1. Tests/AskiTests/AskiColorLabIsoluminantRescueTests.swift — shared `static let` battery + `Result`-wrapped analysis across all identical-argument tests (AC#1). Test-scoping traits rejected: swift-testing copies trait instances per test (maintainer guidance, forums thread 79244); static-let lazy init is the supported thread-safe sharing pattern.
2. Tools/AskiColorLab/IsoluminantRescue/IsoluminantRescueCommand.swift — per-key single-flight memo cache (OSAllocatedUnfairLock) for recorder-less analyze() calls; the run() e2e tests recomputed analyze(64,512) three more times with identical args. Recorder-present calls bypass the cache (plumbing sentinel unaffected). Cache is inert in CLI use (one analyze per process).
3. Scripts/validate-docc.sh — Aski symbol graph cached under .build/aski-docc-symbols-cache keyed on Aski sources + Package.swift/resolved + toolchain + SDK; plus --no-transform-for-static-hosting on the validation convert (AC#5). Falsification passed both directions: broken symbol link fails on cold AND warm cache; public-symbol rename invalidates the key. 4.09s -> 1.71s medians in isolation. ASTSK-25 rationale preserved.

AC#2 re-measurement (same per-phase script, 5 warm samples, medians):
  format 1.7  build 3.4  lifecycle 0.9  repo-map 0.8
  test-core 85.2  media 7.7  sentinels 2.9  docc 2.0
  TOTAL median 114.2s (samples 103.2/104.3/114.2/115.1/119.5)
  Drop vs 186.7s baseline: 72.5s — TARGET (>=90s) NOT MET; AC#2 left unchecked.
  Why the ceiling: remaining test-core is distributed distinct work, not redundancy. Isolation re-profile (AC#4): IsoluminantRescue 190.2->33.2s; ColorLab whole 149.7->~50s; ParallelWalkParity 33.8s (unchanged — serial-vs-parallel duplication IS the parity oracle, repeated converts are the determinism check; recorded as ACCEPTED COST); ShapeResidual 20.7s; DecolorRun 7.3s; Ranked 8.6s; SamplingLattice 9.8s. The 85s wall is aggregate CPU across ~200 suites on 10 P-cores; no single shareable computation remains. The original >=90s estimate assumed ~220s of redundant CPU; the truly redundant share proved smaller once the memo collapsed it to single-flight.

AC#3: 1260 core + 149 media + 2 sentinels, all passing across 5 consecutive full-gate samples; no test skipped, filtered, or loosened.
AC#6: no build-system changes (ASKI-41 untouched). AC#7: phase structure unchanged; docs left alone.
<!-- SECTION:NOTES:END -->
