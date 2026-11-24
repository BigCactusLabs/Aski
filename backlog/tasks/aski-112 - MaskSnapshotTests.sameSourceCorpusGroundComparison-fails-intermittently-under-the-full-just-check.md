---
id: ASKI-112
title: >-
  MaskSnapshotTests.sameSourceCorpusGroundComparison fails intermittently under
  the full just check
status: To Do
assignee: []
created_date: '2026-11-24T20:58:27Z'
updated_date: '2026-11-24T21:37:04Z'
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
<!-- SECTION:NOTES:END -->
