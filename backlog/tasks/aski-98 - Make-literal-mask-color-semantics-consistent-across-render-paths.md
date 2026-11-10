---
id: ASKI-98
title: Make literal mask color semantics consistent across render paths
status: To Do
assignee: []
created_date: '2026-11-05T20:27:00Z'
updated_date: '2026-11-05T20:39:00Z'
labels: []
dependencies:
  - ASKI-3
references:
  - Sources/Aski/Renderers/ImageRenderer.swift
  - Sources/Aski/Tiles/TileGrid+Rendering.swift
  - Sources/Aski/Masking/MaskFallbackImageFactory.swift
priority: medium
type: bug
ordinal: 99000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-3 review found an existing contract split: synchronous ASCII and tile paths color-match Generic RGB solid mask fallback and ground colors through Core Graphics, while the effects/async mask factory interprets the same numeric components literally in the grid gamut. Named sRGB/P3 CGColors have explicit meaning. Reproduce this split, choose one public contract for literal colors, and apply it across direct, effects, engine, ASCII, and tile rendering. This is separate from ASKI-3 cell displayColor correction.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A non-neutral Generic RGB solid fallback and visible ground reproduce the current path split with independent pixel references.
- [ ] #2 One documented contract is applied to direct and async/effects ASCII and tile paths, including engine gamut adaptation; named caller colors keep their tags.
- [ ] #3 Regression checks cover partial coverage, alpha, both gamuts and hard/soft edges; migration notes describe any output change and the full local gate passes.
<!-- AC:END -->
