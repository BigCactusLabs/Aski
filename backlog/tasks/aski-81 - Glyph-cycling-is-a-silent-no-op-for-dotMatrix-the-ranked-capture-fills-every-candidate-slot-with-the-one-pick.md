---
id: ASKI-81
title: >-
  Glyph cycling is a silent no-op for dotMatrix: the ranked capture fills every
  candidate slot with the one pick
status: To Do
assignee: []
created_date: '2026-09-27 17:35'
labels:
  - animation
  - algorithms
dependencies: []
references:
  - Sources/Aski/ConversionEngine.swift
  - Sources/Aski/Animation/ScheduleBuilder.swift
  - Sources/Aski/Aski.docc/Animation.md
priority: medium
type: enhancement
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found 2026-09-27 from the bcl-web canyon strip (Aski HEAD 6b6d251).

WHAT HAPPENS
`RankedDotMatrixCapture` (Sources/Aski/ConversionEngine.swift, lines 52-66) sets the cell's candidate count to 1 and writes the one pick into every candidate slot. `ScheduleBuilder` (Sources/Aski/Animation/ScheduleBuilder.swift:64) lets a cell cycle only when it has at least 2 distinct candidates, so no dotMatrix cell ever cycles.

MEASURED
bcl-web canyon photo, 288 columns, `CyclingOptions(k: 4, speed: 1, intensity: 0.6, randomness: 0)`, 2 s at 8 fps, 17 materialized frames: 0.0% of pixels change per frame for braille, minimal, dots and a custom ramp under dotMatrix with coverage 1, against 13.9% for logPolar with standard.

WHY IT MATTERS NOW
Animation.md already says "With .dotMatrix, the animation keeps the winning character", so this is documented, but `animate()` accepts cycling options with no diagnostic. And dotMatrix with Floyd–Steinberg is the path that tracks tone best and avoids the same-glyph runs of ASKI-80 (run p95 2-6 vs 10-28 for logPolar standard). A consumer that wants tonal accuracy and a glyph shimmer has no Aski path: bcl-web's canyon strip would have to build its own cycle outside Aski.

OPTIONS TO WEIGH (not decided)
- Ranked candidates for dotMatrix: the k glyphs nearest in density to the cell's dithered target, with error diffusion carried from the base pick so the base frame is unchanged.
- Dither-variant candidates: k error-diffusion passes under a deterministic perturbation (seeded noise or scan order), each cell's candidates taken across passes.
- Or a precondition or diagnostic when cycling is requested with dotMatrix, if cycling there is out of scope.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One option is chosen and recorded with its reason: dotMatrix ranked candidates, dither-variant candidates, or a diagnostic when cycling is requested with dotMatrix
- [ ] #2 If candidates are added, the base frame stays byte-identical to convert(), and the mean ink-density difference between a cell's candidates and its base pick is measured and bounded
- [ ] #3 If candidates are added, the per-frame change rate at default CyclingOptions is reported against logPolar standard on the same fixtures
- [ ] #4 Animation.md describes the resulting behaviour
<!-- AC:END -->
