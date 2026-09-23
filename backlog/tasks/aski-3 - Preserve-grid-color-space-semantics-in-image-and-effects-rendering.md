---
id: ASKI-3
title: Preserve grid color-space semantics in image and effects rendering
status: To Do
assignee: []
created_date: '2026-08-18 18:01'
updated_date: '2026-09-10 04:15'
labels:
  - correctness
  - rendering
  - color
dependencies: []
priority: high
type: bug
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASCIICell.displayColor and TileCell.displayColor are encoded in the grid RenderColorSpace, but the direct ASCII, tile, and effects raster paths construct Generic RGB CGColors. This materially changes non-neutral sRGB and Display P3 values. AskiRenderEngine also changes the grid color-space tag without converting cell components. Correct the complete defect family so image output matches the documented cell-color contract and the already color-space-aware attributed-string path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Direct ASCIIGrid and TileGrid encoded 8-bit rendering interprets each displayColor in the grid declared sRGB or Display P3 space and preserves non-neutral components within one 8-bit quantization step.
- [ ] #2 Effects rasterization uses the same color-space-correct interpretation as direct rendering for ASCIIGrid and TileGrid.
- [ ] #3 Rendering through AskiRenderEngine with an engine color space that differs from the grid preserves colorimetry and emits the intended output color-space tag without retagging unchanged components.
- [ ] #4 Regression coverage includes the non-neutral discriminator (0.8, 0.2, 0.1) in sRGB and Display P3 and detects Generic RGB reinterpretation in direct, effects, and engine-adapted paths.
- [ ] #5 Alpha, mask fallback, composition-policy, braille, tile-shape, and attributed-string behavior remain correct, and focused tests plus just check pass.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `ASCIICell.displayColor` is documented as already display-ready in the grid `RenderColorSpace`. The encoded 8-bit composition policy selects an sRGB or Display P3 drawing space, but the direct image renderer builds foregrounds with `CGColor(red:green:blue:alpha:)`; the effects ASCII raster builder does the same. Tile direct and effects rendering share `RasterColorCache.color` and `renderCellsForRaster` in `Sources/Aski/Tiles/TileGrid+Rendering.swift`, where the same generic RGB constructor is used. Include `CellRasterBuilder.makeTileRaster` and both engine adaptation overloads in the defect family. Both draw actual cell components into a tagged context without an explicit component conversion at those call sites. The engine adaptation path reconstructs a grid with `colorSpace: colorSpace` while passing through the original cells, masks, and fallback metadata. That can change the interpretation of unchanged components. The attributed-string path is a useful contrast because it selects sRGB or Display P3 platform color constructors.

Start here: trace one non-neutral encoded cell through `ImageRenderer`, `CellRasterBuilder`, and `AskiRenderEngine` for both direct and non-default composition paths. Keep the `RenderCompositionPolicy.cgColorSpace(for:)` mapping in the trace; output tags alone do not prove component colorimetry. The HDR extended-range helper also has a separate decode path, so its inclusion in this scope needs an explicit decision.

Constraints and dependencies: preserve alpha, mask fallback, active mask ground, braille, tile-shape, and attributed behavior. Existing focused tests mostly check tags, primaries, or byte identity for sRGB cells; they do not provide the required non-neutral `(0.8, 0.2, 0.1)` sRGB/P3 discriminator across direct, effects, and engine-adapted output. The engine adaptation must also retain all mask fields when its color-space behavior is corrected.

Validation to run: add focused tests for the non-neutral discriminator and the existing fallback/composition cases, then run `just check-fast` and the full `just check` gate. Compare decoded pixel values and output tags, not only `CGColorSpace.name`; keep rectangular and no-effects compatibility assertions.

First step: capture the current direct, effects, and engine-adapted pixel/tag behavior with the same encoded cell and record the expected color-space interpretation before choosing the conversion boundary.

Source map: `Sources/Aski/ASCIICell.swift`, `Sources/Aski/Renderers/ImageRenderer.swift`, `Sources/Aski/Effects/Internal/CellRasterBuilder.swift`, `Sources/Aski/Effects/AskiRenderEngine.swift`, `Sources/Aski/ColorPipelinePolicies.swift`, `Tests/AskiTests/AskiRenderEngineTests.swift`, `Tests/AskiTests/RenderCompositionPropagationTests.swift`.
<!-- SECTION:NOTES:END -->
