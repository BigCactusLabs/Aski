---
id: ASKI-78
title: >-
  Decide how ShapeData survives Core Text drift: vendored deterministic glyph
  rasterizer or explicit per-OS rasters
status: To Do
assignee: []
created_date: 2026-09-23 15:47
updated_date: '2026-10-27T15:56:00Z'
labels:
  - spike
  - gate
dependencies: []
priority: medium
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The ASKI-51 audit TRIGGERED on macOS 27.0 (26A428) / Xcode 27.0 (27A266a) / Swift 6.4 during ASKI-77: 9 of 10 ShapeData v3 sets drift (max component delta 0.0452 in blocks, tolerance 0.001), and the standard set's brightness-sorted order changed; braille is byte-identical. The committed .bin files were NOT regenerated, as the policy requires when a trigger fires, so current selection output is unchanged (all text and selection goldens pass on macOS 27). The policy's required follow-up is this task: choose between vendoring a deterministic text glyph rasterizer and defining explicit per-OS golden rasters, then validate the choice. Until it lands, any change that needs ShapeData regeneration (schema, raster construction, glyph inventory, accepted matching change) is blocked. Render snapshots are separate: ASKI-77 re-recorded them on macOS 27, and they now fail on macOS 26.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both options are costed against Aski evidence: selection effect of the macOS 27 drift on the frozen preset (selection-ceiling MAE and GMSD with in-memory regenerated vectors versus committed), and the maintenance cost of per-OS rasters
- [ ] #2 The owner records the decision; the chosen mechanism is implemented and the ASKI-51 audit either no longer depends on the OS rasterizer or is keyed per OS
- [ ] #3 docs/Research/2026-09-04-aski51-core-text-drift-policy.md is updated with the macOS 27 TRIGGERED result and the decision
- [ ] #4 Decide how rendered goldens (PNG snapshots and the G0 byte golden) handle more than one OS: separate rasters per OS, a perceptual comparison, or macOS-27-only as accepted in ASKI-77 (PR #2 review). If they stay macOS-27-only, document it where the gate is described
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Groundwork — 2026-10-27 (base 4c675957)

Factor font choice from rasterizer choice before costing the two routes. `Tools/BuildStandardVectors/BuildStandardVectors.swift` resolves system Courier at 32 pt, while the canonical Vesper renderer uses bundled Courier Prime at 14 pt. Swapping both font and rasterizer in one trial would obscure what changed.

Bounded experiment: retain committed ShapeData as the selection control; first compare Core Text/system Courier with Core Text using identical bundled Courier Prime bytes at the same descriptor-generation point size and geometry, then compare that same bundled font through a pinned alternate rasterizer. Record font hashes, library/build configuration, canvas, placement/baseline, glyph order, grayscale coverage and hint/bitmap policy. Run the exact-lattice MAE/GMSD census before interpreting regenerated descriptors. In parallel, cost explicit per-OS assets and their regeneration/selection rules. This is preparation for the required owner decision, not a choice to add FreeType or regenerate production bytes.

Apple's `CTFontCreatePathForGlyph` returns glyph outlines; rendering those paths with Core Graphics still does not establish OS-independent pixels. FreeType exposes `FT_LOAD_NO_HINTING`, `FT_LOAD_NO_BITMAP`, and `FT_RENDER_MODE_NORMAL` for controlled grayscale trials, but those switches alone do not prove cross-host byte stability. Demonstrate that with pinned inputs and multiple hosts before promising deterministic assets. Existing committed ShapeData and the recorded macOS-27 rendered-golden baseline remain the controls.

Primary sources inspected: https://developer.apple.com/documentation/coretext/ctfontcreatepathforglyph(_:_:_:) ; https://freetype.org/freetype2/docs/reference/ft2-glyph_retrieval.html .
<!-- SECTION:NOTES:END -->
