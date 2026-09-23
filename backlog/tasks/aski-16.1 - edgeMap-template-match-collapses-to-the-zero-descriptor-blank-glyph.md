---
id: ASKI-16.1
title: edgeMap template match collapses to the zero-descriptor blank glyph
status: Done
assignee: []
created_date: '2026-08-19 05:16'
updated_date: '2026-08-20 20:01'
labels:
  - correctness
  - algorithms
  - edge-map
dependencies: []
references:
  - Sources/Aski/Algorithms/EdgeMapKernel.swift
  - Sources/Aski/Algorithms/ShapeContext.swift
parent_task_id: ASKI-16
priority: high
type: bug
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`EdgeMapKernel.pickScored` scores every glyph in the set against the bucket's canonical template with squared L2 over the 60D log-polar descriptor, then takes the argmin. `ShapeContext.histogram60` L1-normalizes its output, so every inked glyph has descriptor mass exactly 1 — but a blank glyph rasterizes to an all-zero field and normalizes to the ZERO VECTOR (measured mass 0.0 for ' ' in every built-in set).

Squared L2 from a template to the zero vector is just the template's own energy, sum(t_i^2). For these peaky, L1-normalized templates that is 0.10 (cross) to 0.21 (diagDesc) — a constant floor that sits BELOW the distance to genuinely similar glyphs, because two different unit-mass distributions with peaks in different bins are farther apart than either is from the origin. The blank glyph therefore wins whenever no real glyph lands very close.

Measured argmin per bucket:
- .diagonal: SPACE wins all five buckets (horizontal 0.2063, vertical 0.2063, diagAsc 0.1994, diagDesc 0.2107, cross 0.1032); '/' and '\\' rank third.
- .cross: horizontal SPACE 0.2063 (over '+' 0.2262), diagAsc SPACE 0.1994, cross SPACE 0.1032 (over '+' 0.1136).
- .lines: diagAsc SPACE 0.1994, diagDesc SPACE 0.2107. Horizontal survives by only 2.4% ('-' 0.2014 vs SPACE 0.2063).

Consequence: on charsets built for this algorithm, `.edgeMap` returns blank for above-threshold edge cells — indistinguishable from the intentional below-threshold blank, so the failure reads as 'the image had no edges'.

Note the match loop scans 0..<characters.count with no blank-glyph exclusion, unlike the below-threshold path which deliberately routes through `resolveBlankGlyphIndex`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An above-threshold edge cell never resolves to the blank glyph through the template-match path on any built-in character set
- [ ] #2 The fix is stated as a rule — exclude the blank/zero-mass glyph from the template pool, or use a metric that is not biased toward low descriptor mass (e.g. cosine or chi-squared) — and the choice is justified against both options
- [ ] #3 Regression asserts the winning glyph per bucket for .lines, .cross, .diagonal and .mixed, including a case where the correct glyph currently loses to SPACE by less than 5 percent
- [ ] #4 The intentional below-threshold blank path and the .blank bucket keep returning resolveBlankGlyphIndex
<!-- AC:END -->
