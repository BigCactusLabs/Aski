---
id: ASKI-103
title: >-
  Soft mask edges mix opaque branches in encoded values on Core Graphics paths
  and in linear light on Core Image paths
status: To Do
assignee: []
created_date: '2026-11-10T19:09:00Z'
updated_date: '2026-11-13T05:21:00Z'
labels:
  - correctness
  - rendering
  - masking
dependencies: []
priority: low
type: bug
ordinal: 104000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while fixing ASKI-101. After ASKI-101 every render path applies the same coverage weight, but the colors that weight mixes are combined in each path's compositing space. Under the default RenderCompositionPolicy.encodedDisplay8Bit, the Core Graphics overlay paths (direct ASCII, target width, direct tile pixelArt/brick fallback) mix encoded values, while the Core Image mask compositor (effects, async, renderCIImage, AskiRenderEngine, any render with a ground, rerouted tile mosaic) mixes in the shared context's extended linear sRGB working space. Measured on a one-cell sRGB grid with a zero-alpha glyph, an opaque white solid fallback and an opaque black background: direct ASCII gives 191/128/64 at coverage 0.25/0.5/0.75, the effects path gives 225/187/138. Under the opt-in extendedLinearPerGamut policy the direct path already mixes in linear light and agrees with the effects path. Over transparent content the alpha is identical on every path, which MaskColorContractTests.softCoverageIsALinearWeightOnEveryPath pins. The same encoded-versus-linear split likely applies to glyph antialiasing edges on the effects path versus direct rendering; confirm before scoping.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Measure the split on every MaskColorContractTests path under both composition policies, for soft mask edges and for glyph antialiasing edges
- [ ] #2 Decide whether Core Image paths should follow the grid's RenderCompositionPolicy, with a pre-registered rule and the frozen-preset no-harm census if any frozen-preset golden would move
- [ ] #3 Document the outcome in the Masking and Rendering guides
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-13: related: ASKI-107 measures linear-light cell averages, which this task's composition policy affects.
<!-- SECTION:NOTES:END -->
