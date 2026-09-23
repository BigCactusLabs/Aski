---
id: ASKI-38
title: AnimatedASCIIGrid indexes the schedule with dimensions it does not re-verify
status: Done
assignee: []
created_date: '2026-08-20 03:15'
updated_date: '2026-08-24 15:36'
labels:
  - correctness
  - animation
dependencies:
  - ASKI-6
references:
  - Sources/Aski/Animation/AnimatedASCIIGrid.swift
  - Sources/Aski/Animation/ScheduleBuilder.swift
priority: low
type: bug
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AnimatedASCIIGrid.swift:40 subscripts schedule.candidates as:

    schedule.candidates[cellIndex * schedule.candidateStride + candidateSlot]

cellIndex derives from baseGrid.rows and baseGrid.columns, and candidateSlot from selectedCandidateSlot(), but the collection being indexed belongs to schedule — a different object. That baseGrid's dimensions agree with the schedule's cellCount and candidateStride is preconditioned at ScheduleBuilder construction time and not re-verified at this call site.

Same shape as the cross-collection indexing defect filed as ASKI-23 (matcher indices derived from candidateBrightness.count then used to subscript characters). The compensating control here is stronger — construction-time pairing rather than a parser invariant — so this is filed LOW pending a reachability answer.

The open question is whether a caller can pair an AnimatedASCIIGrid with a baseGrid whose dimensions differ from the schedule it was built against. If not reachable, the fix is a comment naming the construction-time guarantee, not a bounds check.

Found during the Batch A validation work; the animation worker on ASKI-6/18/19 was explicitly told to report rather than fix it, so check that task's notes before starting — ASKI-6 may already have made it unreachable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A determination is recorded on whether a public caller can pair a baseGrid and a schedule whose dimensions disagree, with the call path if so
- [x] #2 If reachable, the site either bounds-checks or is made structurally impossible; if not reachable, the construction-time guarantee is documented at the call site
- [x] #3 The resolution is consistent with whatever ASKI-6 settled about schedule construction
- [x] #4 just check passes and animation output is byte-identical
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24: implemented and merged to main in PR #28 (batch-validation wave, merge b835160); all ACs were already checked — status flip only.
<!-- SECTION:NOTES:END -->
