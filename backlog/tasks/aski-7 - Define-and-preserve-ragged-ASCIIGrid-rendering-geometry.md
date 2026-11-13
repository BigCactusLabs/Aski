---
id: ASKI-7
title: Define and preserve ragged ASCIIGrid rendering geometry
status: Done
assignee: []
created_date: 2026-08-18 18:01
updated_date: '2026-11-13T04:21:00Z'
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
- [x] #1 ASCIIGrid reports geometry that includes the widest row for public ragged input, matching TileGrid semantics.
- [x] #2 A grid with row lengths [1, 2] allocates enough direct and effects-rendered canvas width for both cells in the second row without clipping.
- [x] #3 A grid whose first row is empty and a later row is nonempty does not render as an empty 1x1 image.
- [x] #4 Coverage masks, direct image output, effects output, plain text, and attributed strings handle missing cells consistently under the documented ragged-row semantics.
- [x] #5 Rectangular converter-produced grids remain bit-identical, and focused regressions plus just check pass.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Trace current direct, effects, coverage and text behavior; freeze missing-cell semantics; report the widest row and add focused ragged regressions; verify rectangular output and run the local gates.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `ASCIIGrid` sets `columns` from `cells.first`, while `TileGrid` already reports the widest row and documents that its renderer tolerates per-row variation. ASCII image geometry and the effects ASCII raster use `grid.columns` and `grid.rows` for allocation, then iterate each row's actual cells. Therefore a longer later row can exceed the allocated width, and an empty first row reports zero columns even when later rows contain cells. Plain-text and attributed renderers also iterate actual row contents without padding.

Start here: follow the width value from `ASCIIGrid.init` into `ImageRenderer.renderGeometry`, `drawCells`, and `CellRasterBuilder.makeASCIIRaster`. Then inspect coverage construction: the ASCII mask builder allocates `grid.columns * grid.rows` bytes initialized to full coverage and paints actual cells. Widening the reported geometry will expose a policy question for missing positions; direct/effects masks must agree with the chosen semantics. Existing tile rendering is the closest precedent, not a complete ASCII policy because tile shapes and coverage initialization differ.

Constraints and dependencies: rectangular converter-produced grids must remain byte-identical. The change must cover direct images, effects images, plain text, attributed strings, coverage masks, and mask fallback paths. Current docs describe columns-by-rows image geometry but do not define how missing cells in ragged ASCII rows render. Current ASCII tests cover rectangular dimensions and empty grids only; the tile suite has a ragged fixture with an empty first row and checks widest-row dimensions.

Validation to run: add ASCII fixtures for an empty first row followed by content and for a later row longer than the first. Exercise direct and effects canvases, coverage/mask fallback, plain text, and attributed output. Re-run the existing rectangular compatibility tests, then `just check-fast` and the full `just check` gate.

First step: use the tile ragged tests as a fixture shape and record each ASCII renderer's current width, height, and missing-cell behavior before selecting the documented ragged geometry policy.

Source map: `Sources/Aski/ASCIIGrid.swift`, `Sources/Aski/Tiles/TileGrid.swift`, `Sources/Aski/Renderers/ImageRenderer.swift`, `Sources/Aski/Effects/Internal/CellRasterBuilder.swift`, `Sources/Aski/Masking/CoverageImageBuilder.swift`, `Sources/Aski/Renderers/PlainTextRenderer.swift`, `Tests/AskiTests/TileGridRenderingTests.swift`, `Tests/AskiTests/ASCIIGridTests.swift`.

All 51 focused native tests passed, including two exact rectangular goldens. New cases cover [1,2], [0,2], all-empty rows, plain/attributed text, later-cell ink, fractional scale, ground/no-ground, hard/soft coverage and solid/original-image fallback. Presence is applied after masked composition, so color-overlay and per-character spill are clipped at missing cells; lighting/global effects run afterward. Existing soft coverage interpolation inside supplied cells and direct per-cell edge antialiasing remain. Verified on 2026-11-12 with Xcode 27.0 (27A266a), Apple Swift 6.4, macOS 27.0.1. just check-fast passed 903 tests; exact just check passed 1500 core, 163 serialized media and 2 deadlock tests (1665 total), plus drift checks and DocC. The full gate tested base 3f6da15da41e7f91e58174fcc7ce40fc8d2f6668 plus source/test patch SHA-256 0321f22cae94e808d6c1494a417d75ee1e37ba7c1a7000cad6a9f3d800d6d9f2. Only DocC prose and backlog records changed afterward; final just docc passed. Exact goldens were unchanged. Independent Opus source review and lead review completed.

Audit 2026-11-12: merged as public PR #26 (d3f9439) on 2026-11-12.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ASCIIGrid reports the widest supplied row. Direct/effects canvases retain later content even when the first row is empty; plain and attributed text retain the supplied row lengths. Ragged masked composition preserves the canvas at absent cells using hard presence aligned with actual glyph dimensions. Explicit zero-coverage cells still get fallback. Rendering guide and CHANGELOG document the semantics.
<!-- SECTION:FINAL_SUMMARY:END -->
