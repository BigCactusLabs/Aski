---
id: ASKI-18
title: OngoingPattern parameters are accepted at construction but fatal at evaluation
status: Done
assignee: []
created_date: '2026-08-19 05:20'
updated_date: '2026-08-20 04:14'
labels:
  - correctness
  - animation
  - api-contract
dependencies: []
references:
  - Sources/Aski/Animation/OngoingPattern.swift
  - Sources/Aski/Animation/PatternEvaluator.swift
  - Sources/Aski/Animation/AnimationOptions.swift
  - Sources/Aski/Animation/ASCIIGrid+OngoingPattern.swift
priority: medium
type: bug
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`OngoingPattern.wave(amplitude:frequency:direction:)` and `.pulse(period:depth:)` accept any Double at construction, and `AnimationOptions.init` passes `ongoing` straight through without validating it. `PatternEvaluator.ongoingAlpha` then preconditions on exactly those values at evaluation time, so the process dies deep inside a per-cell render loop rather than at the call the caller can see.

Confirmed crashes (SIGTRAP, fresh process each):
- `ASCIIGrid.applyingOngoingPattern(.pulse(period: 0), at: 0)` -> 'Aski/PatternEvaluator.swift:69: Precondition failed: pulse period must be finite and positive'
- `converter.animate(image, columns: 8, options: AnimationOptions(duration: 1, ongoing: .pulse(period: 0))).grid(at: 0.5)` -> same trap

Confirmed non-validating: `AnimationOptions(duration: 1, ongoing: .pulse(period: 0))`, `.pulse(period: .nan)` and `.wave(frequency: 0)` all construct successfully.

This is inconsistent with the sibling knob. `CyclingOptions.speed` carries the same finite-and-positive requirement and IS checked at the public boundary, by `animate(_:columns:options:mask:)` before any conversion work. `AnimationOptions.duration` is likewise checked in its own initializer. Only the ongoing-pattern parameters are left to fail late.

Both crash sites are reachable from public API with no unsafe or SPI import: `applyingOngoingPattern` is public on ASCIIGrid, and `convertVideo(pattern:)` threads a caller-supplied pattern into every video frame — so an invalid pattern kills a whole export mid-stream.

Same shape as ASKI-6 AC#2 (accepted-at-the-boundary values that produce an unsafe schedule), applied to the pattern knobs rather than cycling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The finite-and-positive requirement on wave frequency and pulse period is enforced at the public boundary — OngoingPattern construction, AnimationOptions.init, or both — matching how CyclingOptions.speed and AnimationOptions.duration are already handled
- [x] #2 ASCIIGrid.applyingOngoingPattern and ASCIIVideoFrame.applyingOngoingPattern cannot trap for any OngoingPattern value the API accepts
- [x] #3 The documented contract for each parameter states its valid domain, and whether an out-of-domain value is rejected or sanitized (as amplitude and depth already are via sanitizedClamped)
- [x] #4 Regression covers period 0, negative, and NaN; frequency 0, negative, and NaN, through animate + grid(at:), applyingOngoingPattern, and the convertVideo pattern path
- [x] #5 Valid patterns produce byte-identical output, and just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landed in merge commit da78b1a (Batch A).

OngoingPattern is an enum, so its cases cannot validate at construction. Every accepting entry point calls a new internal validate() instead — AnimationOptions.init, ASCIIConverter animate, ScheduleBuilder.build, ASCIIGrid.applyingOngoingPattern, ASCIIVideoFrame.applyingOngoingPattern and the convertVideo pattern path — and the list of those entry points is documented on the type.

AC#2 wording, read literally, asks that applyingOngoingPattern 'cannot trap for ANY value the API accepts'. It is met under the arm AC#3 sanctions: an unevaluable frequency or period is REJECTED at the boundary, which is a precondition failure. What was removed is the failure far from the caller's call site, not the failure. Three redesigns were weighed and rejected: converting the enum to a validating struct is a redesign, not a port (two call sites in the video labs switch over the cases), and sanitizing to a nearest valid value recreates the defect class filed as ASKI-22.

The reject-vs-clamp line is now documented on OngoingPattern: no sensible projection => structural => reject. amplitude and depth keep sanitizedClamped because every value projects sensibly into their range; period = 0 has no defensible nearest valid value, so substituting one would silently animate something other than what the caller asked for.

PatternEvaluator.ongoingAlpha keeps its precondition as a deliberate backstop — now unreachable from public API, retained so a future unguarded entry point fails loudly instead of computing garbage.

Gap the original spec missed: AnimationOptions.ongoing is a settable var, so init-only validation is bypassable by post-construction mutation. Re-checked at animate and ScheduleBuilder.build, with regression for the mutated case.

Coverage: AnimationOngoingPatternContractTests — period and frequency at 0, negative and NaN, through animate + grid(at:), both applyingOngoingPattern overloads, and the convertVideo path.
<!-- SECTION:NOTES:END -->
