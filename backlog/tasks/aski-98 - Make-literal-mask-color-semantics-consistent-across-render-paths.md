---
id: ASKI-98
title: Make literal mask color semantics consistent across render paths
status: To Do
assignee: []
created_date: '2026-11-05T20:27:00Z'
updated_date: '2026-11-10T02:25:00Z'
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
- [x] #1 A non-neutral Generic RGB solid fallback and visible ground reproduce the current path split with independent pixel references.
- [ ] #2 One documented contract is applied to direct and async/effects ASCII and tile paths, including engine gamut adaptation; named caller colors keep their tags.
- [ ] #3 Regression checks cover partial coverage, alpha, both gamuts and hard/soft edges; migration notes describe any output change and the full local gate passes.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Phase 1 (2026-11-09, commit 3000663): characterization tests in Tests/AskiTests/LiteralMaskColorCharacterizationTests.swift reproduce the split with independent Core Graphics references for contract A (color-match the declared space) and B (literal components in the grid gamut). Generic RGB and unnamed RGB: A on direct ASCII, target-width ASCII and the direct tile pixelArt fallback overlay; B on every Core Image mask path (sync effects, async, CIImage, engine same- and cross-gamut) and on the direct tile renderer's ground and partial-coverage mosaic reroutes. Direct ASCII ground is A but direct tile ground is B. sRGB, Display P3 and device RGB colors follow A everywhere. Separate finding: the Core Image mask compositor weights soft coverage 0.5 as about 0.214 (Device Gray coverage linearized), while the CG overlay uses 0.5. Contract choice awaits the lead's ruling.
<!-- SECTION:NOTES:END -->
