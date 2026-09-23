---
id: ASKI-6
title: Prevent finite animation times and cycling speeds from trapping
status: Done
assignee: []
created_date: '2026-08-18 18:01'
updated_date: '2026-08-20 04:14'
labels:
  - animation
  - correctness
dependencies: []
priority: medium
type: bug
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AnimatedASCIIGrid.grid(at:) accepts every finite TimeInterval, but candidate-slot arithmetic can overflow to infinity and then convert NaN to Int. A participating cycling cell traps when queried at Double.greatestFiniteMagnitude. Extremely large finite cycling speeds can also underflow the stored Float period and reach the same unsafe arithmetic.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 grid(at:) returns a deterministic valid ASCIIGrid without trapping for Double.greatestFiniteMagnitude and other finite times whose intermediate arithmetic would otherwise overflow.
- [x] #2 Every accepted finite CyclingOptions.speed produces a safe representable schedule, or the public boundary rejects it through an explicit documented contract before schedule construction.
- [x] #3 Existing negative and non-finite time clamping, cycling participation, candidate ordering, seed determinism, and normal cadence remain unchanged.
- [x] #4 Regression coverage exercises a participating multi-candidate cell at maximum finite time and extreme finite speed values, and focused tests plus just check pass.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landed in merge commit da78b1a (Batch A).

grid(at:) is now total for every finite time: selectedCandidateSlot guards a non-finite derived progress and saturates to the first slot instead of trapping in Int(_:), then clamps the slot into range. CyclingOptions gained minSpeed/maxSpeed derived from whether 1/speed survives as a NORMAL Float in the schedule, with the +/-25% per-cell period jitter budgeted in — the actual representability boundary, not a guessed constant — plus validateSpeed() at the boundary.

AC#2 was taken via the 'rejects through an explicit documented contract' arm, not by making every finite speed safe.

Gap the original spec missed: CyclingOptions.speed is a settable var, so validating only at init is bypassable by post-construction mutation. Re-checked in ScheduleBuilder.build as well.

Coverage: AnimationExtremeValueTests (max finite time on a participating multi-candidate cell, extreme speeds) plus AnimationByteIdenticalGoldenTests, which captures pre-change values and compares with Float.bitPattern — the animation surface had no baseline coverage, so a green suite alone would not have shown byte-identity.
<!-- SECTION:NOTES:END -->
