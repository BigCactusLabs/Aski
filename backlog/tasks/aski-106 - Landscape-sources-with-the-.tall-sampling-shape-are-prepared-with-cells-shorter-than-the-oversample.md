---
id: ASKI-106
title: >-
  Landscape sources with the .tall sampling shape are prepared with cells
  shorter than the oversample
status: To Do
assignee: []
created_date: '2026-11-10T21:30:00Z'
updated_date: '2026-11-10T21:30:00Z'
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
- [ ] #1 Downscaled landscape sources with the .tall sampling shape are prepared with every cell at least oversample pixels on both axes, pinned by a sweep in SamplingMaxPixelSizeTests
- [ ] #2 A landscape .tall conversion at oversample 1 no longer returns an empty grid
- [ ] #3 .square and .wide output, including the frozen Vesper preset, is unchanged; any golden that moves is re-recorded
- [ ] #4 CHANGELOG records the landscape .tall output change
<!-- AC:END -->
