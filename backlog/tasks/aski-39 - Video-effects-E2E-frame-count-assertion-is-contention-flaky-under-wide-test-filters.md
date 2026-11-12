---
id: ASKI-39
title: >-
  Video effects E2E frame-count assertion is contention-flaky under wide test
  filters
status: Done
assignee: []
created_date: 2026-08-20 04:15
updated_date: '2026-11-12T21:28:00Z'
labels:
  - testing
  - video
  - flake
dependencies: []
references:
  - Tests/AskiTests/AskiVideoLabEffectsTests.swift:96
priority: medium
type: bug
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AskiVideoLabEffectsTests.cappedMP4EffectsDimAndPreserveFrameCount failed its frame-count assertion once during the Batch A work (merge commit da78b1a), inside a wide --filter run that was executing many suites concurrently. It then passed 5 of 5 re-runs, both isolated and under the same wide filter, and the diff in flight touched nothing in the video encode or effects path.

So the single failure is unexplained rather than understood. The suspicion is contention: the encoder round-trip is media-engine bound, and this repo has already seen contention-sensitive timing in the parallel tail (ASKI-58 had to budget wall-clock about 25 percent above the worst CONTENDED p90 for exactly this reason). A frame count that depends on encoder readiness under load would behave the same way.

Worth deliberate reproduction before it is believed or dismissed: run the suite under heavy concurrent load repeatedly and see whether the assertion is genuinely racy, or whether the frame count is deterministic and something else produced that one failure. If it is racy, the fix is to make the assertion depend on the encoder's reported frame count rather than on timing, not to relax the number.

Filed because the observation would otherwise be lost: it was written to the blotter during the batch and the blotter commit had to be dropped to get the branch pushed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The failure either reproduces under deliberate concurrent load, or is shown non-reproducible over a stated number of runs and the task is closed as such
- [x] #2 If racy, the assertion no longer depends on timing, and the test passes under load without weakening what it checks
- [x] #3 just check passes
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Run a fixed repeated concurrent-load protocol against the current decoded frame-count assertion; retain all results and state the non-reproducible limit if no failure occurs; run the serialized media phase and full local gate without weakening assertions.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-20: PR #13 moved every GIF|Video|MotionLab case out of the parallel core phase of `just check` into a `--no-parallel` media partition, which removes the contention this flake was attributed to. Not closed: the original failure was a single unreproduced event, so the serial partition is a plausible fix without a demonstrated repro. Close after the gate has run clean for a while, or if the frame-count assertion is shown to be contention-independent.

Board audit 2026-08-24 (deep pass): Line ref drifted: assertion now at AskiVideoLabEffectsTests.swift:104. Mitigation landed (media phase serialized in justfile); contention source is out of the gate. Closure is now a judgment call via AC#1's non-reproducible branch, not engineering.

### Implementer context — 2026-09-10 (base 952529a)

Current state: the only reported failure is the one recorded in this task: `AskiVideoLabEffectsE2ETests.cappedMP4EffectsDimAndPreserveFrameCount` failed once during Batch A merge commit `da78b1a` inside a wide concurrent filter. The task records five of five later reruns passing both isolated and under that filter, with no video encode/effects diff in flight. This remains an unexplained historical observation; no reproduced root cause exists.

Start here: `Tests/AskiTests/AskiVideoLabEffectsTests.swift` writes a six-frame MP4, runs the plain and effects paths with `--max-frames 6`, re-decodes each output through `ASCIIVideoDecoder.grids` using a no-op transform, and asserts both frame counts are exactly six before checking a 5% brightness reduction. The frame-count assertion is therefore a post-encode decode count, and the effects signal is a separate brightness assertion.

Constraints and dependencies: PR #13 landed the mitigation in `justfile`: the broad core phase skips `GIF|Video|MotionLab`, then `ASKI_SERIAL_MEDIA=1 just test-media` runs that partition with `--no-parallel`; the two encoder/deadlock sentinels also run separately with `--no-parallel`. `Tests/AskiTests/TestGateReuseTests.swift` structurally checks this ordering and filter. This removes media contention from the full `just check` gate, while direct ad-hoc `just test-media` retains its existing parallel scope. Do not relax the count assertion or claim a race from the single event. If deliberate load reproduces it, the task proposes making the check depend on an encoder-reported count; current `Sources/Aski/Video/ASCIIVideoEncoder.swift` has `write` return `Void`, so that report seam does not exist yet. A report alone must not replace independent decoded-output verification; establish the failing boundary before selecting a fix.

Validation to run: use a stated repeated concurrent-load protocol to satisfy AC #1, then run the current serialized media command and full `just check`. No build, test, or benchmark was run during this extraction. If the failure stays non-reproducible, record the run count, satisfy the full gate in AC #3, and use the non-reproducible disposition in AC #1; if it reproduces, isolate the timing-independent count source and rerun under load without weakening the assertion.

First step: inspect the current `justfile` partition and `TestGateReuseTests.mediaTestsRunInACompleteSerialPartition`, then perform the deliberate-load reruns against the exact `cappedMP4EffectsDimAndPreserveFrameCount` path.

Protocol fixed before execution: xcrun swift test --skip-build --parallel --maximum-repetitions 20 --repeat-until fail --filter AskiVideoLabEffectsE2ETests. The log confirms each of seven test methods ran 20 times (140 executions), including cappedMP4EffectsDimAndPreserveFrameCount on every repetition. Every target start overlapped another selected test lifetime; this establishes concurrent test overlap, not operation-level media-engine tracing. All passed in 6.510 seconds; no retry was used. AC #2’s conditional fix was unnecessary because no failure reproduced; its exact count assertion was preserved. This result does not establish race freedom or universal host behavior. Swift Testing control semantics were checked against Apple’s current parallelization documentation (https://developer.apple.com/documentation/testing/parallelization.md); suite-local serialization does not isolate unrelated tests. Verified on 2026-11-12 with Xcode 27.0 (27A266a), Apple Swift 6.4, macOS 27.0.1. just check-fast passed 903 tests; exact just check passed 1500 core, 163 serialized media and 2 deadlock tests (1665 total), plus drift checks and DocC. The full gate tested base 3f6da15da41e7f91e58174fcc7ce40fc8d2f6668 plus source/test patch SHA-256 0321f22cae94e808d6c1494a417d75ee1e37ba7c1a7000cad6a9f3d800d6d9f2. Only DocC prose and backlog records changed afterward; final just docc passed. Exact goldens were unchanged. Independent Opus source review and lead review completed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Closed through AC #1’s stated non-reproducible disposition. The existing six-frame decoded-output and brightness assertions passed in 20 parallel repetitions of the current video effects suite. No video implementation, assertion, threshold or gate-order change was made. The historical root cause remains unknown.
<!-- SECTION:FINAL_SUMMARY:END -->
