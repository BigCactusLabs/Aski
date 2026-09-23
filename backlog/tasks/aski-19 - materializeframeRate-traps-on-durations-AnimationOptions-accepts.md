---
id: ASKI-19
title: 'materialize(frameRate:) traps on durations AnimationOptions accepts'
status: Done
assignee: []
created_date: '2026-08-19 05:21'
updated_date: '2026-08-20 04:14'
labels:
  - correctness
  - animation
  - robustness
dependencies:
  - ASKI-6
references:
  - Sources/Aski/Animation/AnimatedASCIIGrid.swift
  - Tools/AskiToolSupport/ToolArgumentBounds.swift
priority: medium
type: bug
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`AnimationOptions.init` accepts any finite positive `duration`. `AnimatedASCIIGrid.materialize(frameRate:)` then computes `scaledDuration = duration * Double(frameRate)` and converts it with an unchecked `Int(nearestWholeFrame)` / `Int(floor(scaledDuration))`, which traps once the product leaves Int's range.

Confirmed crash (SIGTRAP, fresh process): `converter.animate(image, columns: 8, options: AnimationOptions(duration: 1e300)).materialize(frameRate: 60)` -> 'Fatal error: Double value cannot be converted to Int because the result would be greater than Int.max'.

There is a second, softer failure well below the trap: the method materializes one full ASCIIGrid per frame into an array with no cap, so any duration x frameRate in the millions exhausts memory long before the conversion overflows. A one-day duration at 60 fps is already 5.18 million grids. `ToolArgumentBounds.materializedFrameCountIsValid` exists and caps this at 10,000 for the labs, which shows the library boundary is the layer currently missing the check.

Sibling of ASKI-6, which covers `grid(at:)` trapping on extreme finite times and cycling speeds. Same class (finite values the public boundary accepts producing unsafe arithmetic), different entry point, so it should be settled with the same rule.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 materialize(frameRate:) does not trap for any duration AnimationOptions accepts and any positive frameRate, up to Double.greatestFiniteMagnitude
- [x] #2 The frame count is bounded before allocation, with the limit and its overflow behaviour documented — an explicit thrown or precondition-documented rejection is acceptable, silent truncation is not
- [x] #3 The bound is settled consistently with ASKI-6's decision on grid(at:), so the two entry points do not disagree about which finite durations are supported
- [x] #4 Existing cadence, endpoint-on-frame handling and frame contents for realistic durations are byte-identical
- [x] #5 Regression covers duration 1e300, a duration whose product just exceeds the frame cap, and the existing endpoint-rounding cases; just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landed in merge commit da78b1a (Batch A), with a review-driven correction in 6241b0c.

materialize(frameRate:) now bounds the FRAME COUNT rather than the duration: AnimatedASCIIGrid.maxMaterializedFrameCount = 10_000, rejecting rather than truncating, because silently returning a shorter animation than the caller asked for is a worse failure than a visible one. Tools/AskiToolSupport reuses the constant so the labs pre-check and the library contract cannot drift.

AC#1, read literally, asks that materialize not trap for any accepted duration. It is met under the arm AC#2 explicitly sanctions — 'an explicit thrown or precondition-documented rejection is acceptable, silent truncation is not'. An oversized request is rejected at the boundary with the duration, frame rate and limit in the message.

AC#3: this agrees with the ASKI-6 decision rather than contradicting it. What is bounded is the frame count of ONE CALL, not the duration. Every duration AnimationOptions accepts stays fully reachable — through grid(at:), which is total for all finite times, or through materialize at a frame rate low enough to fit.

Review correction (6241b0c): the cap first ran BEFORE the cadence decision and bounded ceil(scaledDuration) + 1, which rejects a request landing exactly on the limit — an endpoint a few ULPs above a whole frame is snapped back onto that frame and costs one frame, not two, so duration Double(9999).nextUp at 1 fps produces exactly 10,000 frames but trapped as 'more than 10000'. The cap now runs after the cadence decision and bounds the exact implied count. Clamping lastCadenceStep at zero before the Int conversion also removed a latent trap on a large negative product; see ASKI-35 for the unvalidated public initializer that made it reachable at all.

Coverage: AnimationExtremeValueTests — duration 1e300, a product just past the cap, the ULP-nudged endpoint exactly at the cap, and the existing endpoint-rounding cases. The ULP test was verified failing against the pre-fix source, not just passing after.
<!-- SECTION:NOTES:END -->
