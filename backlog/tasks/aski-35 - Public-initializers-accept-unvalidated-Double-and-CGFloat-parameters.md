---
id: ASKI-35
title: Public initializers accept unvalidated Double and CGFloat parameters
status: Done
assignee: []
created_date: '2026-08-20 03:15'
updated_date: '2026-08-24 15:36'
labels:
  - correctness
  - api-contract
  - robustness
dependencies: []
references:
  - Sources/Aski/ASCIIFont.swift
  - Sources/Aski/Animation/AnimationAnchor.swift
  - Sources/Aski/Video/ASCIIGIFTypes.swift
  - Sources/Aski/Video/ResampleReport.swift
priority: medium
type: bug
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A sweep for the Batch A validation work found public initializers that accept a floating-point parameter and validate nothing, so an out-of-domain value is stored and surfaces later somewhere else:

- ASCIIFont.swift:15 — public init(name:size:), size unchecked, passed straight to CTFontCreateWithName
- ASCIIFont.swift:21 — public static func system(size:...), same
- The frozen-preset root file under Sources/Aski/ (the type named in the AGENTS.md root-file listing), lines 65-74 — public init taking fontSize and scale, neither checked
- AnimationAnchor.swift:5 — public init(x:y:), unclamped despite the named presets all lying in 0...1
- ASCIIGIFTypes.swift:12 and :23 — public init(...delay: TimeInterval), unchecked at init; a non-finite or non-positive delay is normalized much later at write time
- ResampleReport.swift:18 — public init(requestedFPS:achievedFPS:...), achievedFPS unchecked

IMPORTANT — do not relitigate the font size. ASKI-17 deliberately chose to bound the DERIVED GEOMETRY rather than validate ASCIIFont.init, so that one rule applies at one layer across four raster call sites. This task must not add a competing precondition to ASCIIFont that would make the same input fail in two different ways. Confirm the ASKI-17 bound covers the font and preset paths and, if it does, record both as intentionally-unvalidated with a pointer to that decision.

The pure data carriers (ResampleReport, the GIF report structs) may well be fine as-is; part of this task is deciding which of these are real contract gaps and which are correctly permissive, rather than mechanically adding guards.

(Preset type named indirectly here: the codename is carved out for Sources/Tests/Tools/DocC only and is forbidden in backlog prose.)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each listed initializer is classified as: validated at construction, intentionally permissive with the downstream bound named, or a real gap now fixed
- [x] #2 ASCIIFont and the frozen-preset initializer remain consistent with the ASKI-17 derived-geometry decision, with no second competing check on the same input
- [x] #3 AnimationAnchor states whether coordinates outside 0...1 are supported, clamped, or rejected, and behaves accordingly
- [x] #4 A GIF frame delay that is non-finite or non-positive is handled by one stated rule, at a single documented point in the pipeline
- [x] #5 Regression covers the gaps that were fixed; output for all currently-valid values is byte-identical and just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24: implemented and merged to main in PR #28 (batch-validation wave, merge b835160); all ACs were already checked — status flip only.
<!-- SECTION:NOTES:END -->
