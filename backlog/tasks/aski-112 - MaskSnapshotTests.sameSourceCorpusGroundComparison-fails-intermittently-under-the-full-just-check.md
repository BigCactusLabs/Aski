---
id: ASKI-112
title: >-
  MaskSnapshotTests.sameSourceCorpusGroundComparison fails intermittently under
  the full just check
status: To Do
assignee: []
created_date: '2026-11-24T20:58:27Z'
updated_date: '2026-11-25T19:00:24Z'
labels:
  - testing
  - flake
  - masking
dependencies: []
references:
  - Tests/AskiTests/MaskSnapshotTests.swift
priority: medium
ordinal: 113000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The snapshot `docc-mask-ground-before` in `MaskSnapshotTests.sameSourceCorpusGroundComparison` (Tests/AskiTests/MaskSnapshotTests.swift, the `assertSnapshot` at about :180) fails occasionally during the core phase of `just check`, then passes when the suite runs alone and on an unchanged rerun. Recorded twice: the ASKI-67 PR #4 gate (2026-09) and the PR #34 gate on 2026-11-24 (blotter bl_00a656873d4745d045cc). Because a golden mismatch looks like rendering drift, each occurrence costs a diagnosis and a full gate rerun.

Evidence from 2026-11-24 (macOS 27.2.1, Xcode 27.0, Apple M5 Max): the failing image and the committed golden are both 288 by 336, and they differ in exactly one pixel, (197, 141), by 1 in one channel. The test uses the default exact image comparison, so a 1-LSB difference fails it. That suggests nondeterministic rendering under parallel load (for example Core Image or GPU scheduling, or a shared cache) rather than a real change, but the cause is not established. The same golden also guards the DocC asset mask-ground-before.png.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A reproduction procedure is recorded (for example repeated full core-phase runs, or the suite run concurrently with the other snapshot suites) with its observed failure rate, or the task records how many runs failed to reproduce it
- [ ] #2 The source of the 1-LSB difference is identified with file:line evidence (shared rendering state, a cache, a GPU/CPU path difference, or test-order dependence)
- [ ] #3 The fix makes the snapshot deterministic. Only if the cause is shown to be inherent backend nondeterminism may the comparison accept it, using the narrowest per-snapshot tolerance that admits the measured variance, documented at the call site; no suite-wide loosening and no golden re-recording unless the golden itself is shown wrong
- [ ] #4 just check passes three consecutive times on the gate host after the fix, and the blotter cut is resolved with this task
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-24: ASKI-78 AC#4 adopted option D for rendered goldens. Extra accepted digests cover only host variants that reproduce across repeated captures on that host. They do not cover this intermittent single-host difference, and AC#3 here still governs any tolerance.

2026-11-25 (worker run 1-2, base 99fc4c7, M5 Max, macOS 27.2.1, Xcode 27.2): Investigation found a reproducible Core Image decode-path switch; the one-pixel gate failure is still unreproduced. Keep the two apart.
Gate flake: 0 full core-phase runs made; no run produced a one-pixel, 1-LSB difference at (197, 141). One 4-byte, max-1 variant appeared once in 200 concurrent full renders (run 1) and was not isolated.
Procedure: Scripts/research/aski112-2026-11-25/ (README has exact commands; replay suite copied into Tests/AskiTests only for a run). Run 1 (exploratory probes): 13 runs; run 2: 4 runs (d1 retain 0/1/2, d3false retain 2), N = 300 each.
256-read switch: the test's source enters Core Image through CIImage(cgImage:) at Sources/Aski/Effects/Internal/BackgroundResolver.swift:20 (background, and the mask fallback via Sources/Aski/Masking/MaskFallbackImageFactory.swift:27-28), from a lazily decoded ImageIO JPEG (Tools/AskiToolSupport/ImageFileIO.swift:8-17). Once about 256 such reads are alive in one process, new reads switch to a different decode and the output changes across the whole image (86,477 bytes, max 22 levels). With reads released per iteration, 300 reads never switched. Post-switch output equals a bitmap of ImageIO's software decode (private hardware key false); the pre-switch output, which the committed golden matches, equals no bitmap-backed render. In run 1, a new CIContext switched at the same point, and non-JPEG renders did not advance the count.
Bitmap copy: an owned bitmap of the decoded bytes rendered identically over 300 serial reads and 200 concurrent renders, but differs from the golden (126,954 bytes on the background), so adopting it moves docc-mask-ground-before/after. Fix choice (production materialization vs test-only decode) and any re-record are pending the owner's ruling. No AC checked.

2026-11-25 correction: run 1 made 16 exploratory test invocations, not 13 (3 of them killed or timed out).
<!-- SECTION:NOTES:END -->
