---
id: ASKI-106
title: >-
  Landscape sources with the .tall sampling shape are prepared with cells
  shorter than the oversample
status: Done
assignee: []
created_date: '2026-11-10T21:30:00Z'
updated_date: '2026-11-12T21:28:00Z'
labels:
  - correctness
  - sampling
dependencies:
  - ASKI-105
priority: low
type: bug
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
samplingMaxPixelSize (CellSampling.swift, shared by ASCIIConverter and TileGridConverter since ASKI-105) caps a landscape or square source's longest side, the width, at max(columns, rows) x oversample. The .tall sampling shape (sourceCellHeightOverWidth 0.5) gives a landscape source about 2 x columns x H/W rows. The prepared height is the cap times H/W, which leaves each cell about oversample x max(1/2, H/W) pixels high: below oversample for every landscape aspect. A 4:3 landscape at oversample 2 gets cells one pixel high. A sweep run during the PR 25 review found short cells in 74,547 of 81,346 downscaled landscape .tall cases (92%), and at oversample 1, 17,118 of 21,005 cases (81%) returned an empty grid. Library callers only: no CLI command selects .tall. ASKI-105 left this alone because fixing it changes landscape .tall output. A rule that also requires the prepared height to reach rows x oversample (a cap of at least ceil(rows x oversample x W/H) for landscape sources) would cover it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Downscaled landscape sources with the .tall sampling shape are prepared with every cell at least oversample pixels on both axes, pinned by a sweep in SamplingMaxPixelSizeTests
- [x] #2 A landscape .tall conversion at oversample 1 no longer returns an empty grid
- [x] #3 .square and .wide output, including the frozen Vesper preset, is unchanged; any golden that moves is re-recorded
- [x] #4 CHANGELOG records the landscape .tall output change
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Extend the shared sampling cap to protect both axes for landscape tall input; add numeric and real-lattice sweeps and oversample-one conversion regressions; verify square/wide and frozen-preset parity; document the output change and run the local gates.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The new regressions failed with 23 issues on unchanged production code, including both empty oversample-one conversions. After the fix, 41 focused tests passed, including the frozen Vesper golden. The sweep checks more than 3000 downscaled geometries at each of oversamples 1, 2 and 4. Verified on 2026-11-12 with Xcode 27.0 (27A266a), Apple Swift 6.4, macOS 27.0.1. just check-fast passed 903 tests; exact just check passed 1500 core, 163 serialized media and 2 deadlock tests (1665 total), plus drift checks and DocC. The full gate tested base 3f6da15da41e7f91e58174fcc7ce40fc8d2f6668 plus source/test patch SHA-256 0321f22cae94e808d6c1494a417d75ee1e37ba7c1a7000cad6a9f3d800d6d9f2. Only DocC prose and backlog records changed afterward; final just docc passed. Exact goldens were unchanged. Independent Opus source review and lead review completed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed landscape .tall preparation in both converters by passing sampling shape to the shared cap and protecting rows × oversample on the short axis. Includes one-row panoramas; small sources are not upscaled. Added arithmetic sweep, real lattice, empty-grid and overflow regressions. Square/wide and portrait behavior remain unchanged; CHANGELOG and Algorithms document the output change.
<!-- SECTION:FINAL_SUMMARY:END -->
