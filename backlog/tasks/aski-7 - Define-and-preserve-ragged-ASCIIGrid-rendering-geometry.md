---
id: ASKI-7
title: Define and preserve ragged ASCIIGrid rendering geometry
status: To Do
assignee: []
created_date: '2026-08-18 18:01'
updated_date: '2026-09-10 04:15'
labels:
  - rendering
  - correctness
dependencies: []
priority: medium
type: bug
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASCIIGrid derives columns only from the first row even though its public initializer accepts ragged cell arrays and renderers iterate the actual cells in every row. Longer later rows are drawn outside the allocated image, while a first empty row can collapse a grid with later content to the empty-image fallback. TileGrid already reports the widest row and documents that behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ASCIIGrid reports geometry that includes the widest row for public ragged input, matching TileGrid semantics.
- [ ] #2 A grid with row lengths [1, 2] allocates enough direct and effects-rendered canvas width for both cells in the second row without clipping.
- [ ] #3 A grid whose first row is empty and a later row is nonempty does not render as an empty 1x1 image.
- [ ] #4 Coverage masks, direct image output, effects output, plain text, and attributed strings handle missing cells consistently under the documented ragged-row semantics.
- [ ] #5 Rectangular converter-produced grids remain bit-identical, and focused regressions plus just check pass.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `ASCIIGrid` sets `columns` from `cells.first`, while `TileGrid` already reports the widest row and documents that its renderer tolerates per-row variation. ASCII image geometry and the effects ASCII raster use `grid.columns` and `grid.rows` for allocation, then iterate each row's actual cells. Therefore a longer later row can exceed the allocated width, and an empty first row reports zero columns even when later rows contain cells. Plain-text and attributed renderers also iterate actual row contents without padding.

Start here: follow the width value from `ASCIIGrid.init` into `ImageRenderer.renderGeometry`, `drawCells`, and `CellRasterBuilder.makeASCIIRaster`. Then inspect coverage construction: the ASCII mask builder allocates `grid.columns * grid.rows` bytes initialized to full coverage and paints actual cells. Widening the reported geometry will expose a policy question for missing positions; direct/effects masks must agree with the chosen semantics. Existing tile rendering is the closest precedent, not a complete ASCII policy because tile shapes and coverage initialization differ.

Constraints and dependencies: rectangular converter-produced grids must remain byte-identical. The change must cover direct images, effects images, plain text, attributed strings, coverage masks, and mask fallback paths. Current docs describe columns-by-rows image geometry but do not define how missing cells in ragged ASCII rows render. Current ASCII tests cover rectangular dimensions and empty grids only; the tile suite has a ragged fixture with an empty first row and checks widest-row dimensions.

Validation to run: add ASCII fixtures for an empty first row followed by content and for a later row longer than the first. Exercise direct and effects canvases, coverage/mask fallback, plain text, and attributed output. Re-run the existing rectangular compatibility tests, then `just check-fast` and the full `just check` gate.

First step: use the tile ragged tests as a fixture shape and record each ASCII renderer's current width, height, and missing-cell behavior before selecting the documented ragged geometry policy.

Source map: `Sources/Aski/ASCIIGrid.swift`, `Sources/Aski/Tiles/TileGrid.swift`, `Sources/Aski/Renderers/ImageRenderer.swift`, `Sources/Aski/Effects/Internal/CellRasterBuilder.swift`, `Sources/Aski/Masking/CoverageImageBuilder.swift`, `Sources/Aski/Renderers/PlainTextRenderer.swift`, `Tests/AskiTests/TileGridRenderingTests.swift`, `Tests/AskiTests/ASCIIGridTests.swift`.
<!-- SECTION:NOTES:END -->
