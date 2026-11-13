---
id: ASKI-90
title: Reuse fixed-palette display colors during conversion
status: In Progress
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-11-13T05:22:00Z'
labels:
  - performance
  - color
  - conversion
dependencies: []
references:
  - Sources/Aski/CellSampling.swift
  - Sources/Aski/ResolvedPalette.swift
  - Sources/Aski/ColorPipelinePolicies.swift
  - Benchmarks/AskiBenchmarks/HelmlabBenchmarks.swift
  - https://github.com/BigCactusLabs/Aski/pull/9
priority: medium
type: enhancement
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ConversionContext.finalizeColor (Sources/Aski/CellSampling.swift:497-507) matches a fixed palette entry and then repeats gamut mapping and display encoding for every cell. For a fixed entry, output color space and gamut policy, that display result is invariant. ResolvedPalette.swift:19-25 already prepares per-entry matching coordinates, but no display result is stored. Pass-through color remains genuinely per-cell.

This repeated work was source-verified at c49bbd during the 2026-09-29 sweep; savings were not measured. ASKI-3 concerns renderer color-space interpretation and ASKI-12 concerns interpolation semantics, neither of which this task changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Repeated release measurements report setup and conversion time, CPU and allocations for ANSI16/monochrome, small grids and 80/512 columns, both output spaces, and representative gamut/matching policies.
- [ ] #2 Any adopted reuse produces exact display colors, alpha, brightness, palette tie behavior, and glyphs compared with the current fixed-palette control.
- [ ] #3 Pass-through conversion remains correct and incurs no material regression from fixed-palette preparation.
- [ ] #4 Prepared data is scoped to all relevant palette/color-space/policy inputs and remains safe for parallel conversion.
- [ ] #5 The task records a material end-to-end result or rejection; adopted code passes just check and relevant color/conversion benchmarks without relaxed thresholds.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Existing work reconciled — 2026-10-27

PR #9 is open at 44489c76ae73c845bbe6fbc6a90085d1286b7e62: https://github.com/BigCactusLabs/Aski/pull/9 . It reports native parity and `just check`, but the five-pair comparison of all 70 workloads is pending. Its review also identified a missing standalone palette/display preparation timing or profile; include that attribution rather than inferring setup cost from end-to-end totals. Use the new paired reader and `docs/agents/paired-benchmarks.md` after collecting the exact frozen selection. No performance adoption or completion claimed.

Audit 2026-11-12: the CellSampling anchor moved to finalizeColor (about :668). PR #9 targets work/aski-86-benchmark-validity, which merged as public PR #7; retarget it to main before that branch is deleted. Its head is about 128 commits behind main, and main changed CellSampling.swift since, so expect a rebase conflict.

2026-11-13: PR #9 retargeted to main; GitHub reports it CONFLICTING, so a rebase onto main is needed before the A/B.
<!-- SECTION:NOTES:END -->
