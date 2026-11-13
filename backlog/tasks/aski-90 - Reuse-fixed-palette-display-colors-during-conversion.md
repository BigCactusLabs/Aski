---
id: ASKI-90
title: Reuse fixed-palette display colors during conversion
status: In Progress
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-11-13T06:36:00Z'
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
- [x] #2 Any adopted reuse produces exact display colors, alpha, brightness, palette tie behavior, and glyphs compared with the current fixed-palette control.
- [ ] #3 Pass-through conversion remains correct and incurs no material regression from fixed-palette preparation.
- [x] #4 Prepared data is scoped to all relevant palette/color-space/policy inputs and remains safe for parallel conversion.
- [ ] #5 The task records a material end-to-end result or rejection; adopted code passes just check and relevant color/conversion benchmarks without relaxed thresholds.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Port the original immutable display table, index matching, and independent scalar parity tests onto the current base. Preserve later sampling and footprint behavior.
2. Preserve all 70 end-to-end instruments. Add separate measurements for conversion preparation and for the display table alone.
3. Verify the source statically and hand off the exact current-base scalar control, native parity, and five-pair measurement protocol. Leave all acceptance criteria open until native evidence is reviewed.

4. Before native capture, use explicit allocation-count units, batch only the setup iterations, and add the shared TileGrid guard selection.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Existing work reconciled — 2026-10-27

PR #9 is open at 44489c76ae73c845bbe6fbc6a90085d1286b7e62: https://github.com/BigCactusLabs/Aski/pull/9 . It reports native parity and `just check`, but the five-pair comparison of all 70 workloads is pending. Its review also identified a missing standalone palette/display preparation timing or profile; include that attribution rather than inferring setup cost from end-to-end totals. Use the new paired reader and `docs/agents/paired-benchmarks.md` after collecting the exact frozen selection. No performance adoption or completion claimed.

Audit 2026-11-12: the CellSampling anchor moved to finalizeColor (about :668). PR #9 targets work/aski-86-benchmark-validity, which merged as public PR #7; retarget it to main before that branch is deleted. Its head is about 128 commits behind main, and main changed CellSampling.swift since, so expect a rebase conflict.

2026-11-13: PR #9 retargeted to main; GitHub reports it CONFLICTING, so a rebase onto main is needed before the A/B.

2026-11-13 source checkpoint on e9ac79bd: forward-ported the immutable display table and scalar parity suite. The 70 original end-to-end workloads retain their configurations and timing bodies. The 36 separate setup probes measure fresh matching-coordinate resolution plus display-table preparation across ANSI16, monochrome, and pass-through, both output spaces, and representative policies. Native parity, setup and conversion captures, and the adoption decision are pending.

Instrument repair before native capture: use unscaled allocation units on both ASKI-90 selections and time 1,000 fresh palette resolutions per setup sample. Eight separate TileGrid guards reuse ASKI-92's E2E instrument against ASKI-90's scalar and reuse arms. Native evidence remains pending.

2026-11-13 native candidate gate passed: just check (1544 core, 177 media, two deadlock sentinels, DocC), including all seven fixed-palette exact-parity/concurrency tests and the affected sampling, temporal and tile suites. Source snapshot remained unchanged during the gate. This establishes correctness of the isolated candidate, not benefit or pass-through performance. The committed November 13 pre-registration governs the upcoming five-pair timing study; no timing result is available yet.
<!-- SECTION:NOTES:END -->
