---
id: ASKI-58
title: Investigate bcl-web ASCII shader spike settings as atlas/ramp defaults
status: To Do
assignee: []
created_date: '2026-08-27 05:03'
updated_date: '2026-09-16 17:37'
labels: []
dependencies:
  - ASKI-15
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The bcl-web spike orbs/ascii-photo.html (bcl-web commit 59a835c) got a good look from an ad-hoc runtime atlas + shader settings. Investigate whether Aski's measured metrics confirm or improve on them, and fold the winners into the planned offline atlas/LUT export for the three.js garden (bcl-web docs/spikes/2026-08-25-threejs-ascii-garden.md).

Settings that worked:
- Ramp (hand-ordered by eye): " .\`':;-=+*oxX#%@" (16 glyphs) — check against Aski's measured ink-coverage ordering
- Directional edge glyphs: - \\ | / in 4 tangent-angle buckets (45° each, ASKI-16.2 tangent fix applied)
- Sobel over 3x3 neighboring cell lumas; edge override threshold ~0.55 on gradient magnitude (photo source; expect lower for clean rendered scenes)
- Luma mapping: luma * 1.25 clamped, then pow 0.6 before ramp index — compare with Aski's tone mapping
- Atlas: 64px cells, monospace at 0.82em, white on black, horizontal strip, linear filtering
- Palette quantization: warmth gate (r - max(g,b) > 0.08, luma > 0.22) → amber/gold ramp; else deep→sage→bone by luma

Deliverable: Aski-generated atlas PNG + palette LUT that beats the ad-hoc version on the same test photo (bcl-web img/morgan-newnham-2xwyPtG2Pzo-unsplash.jpg).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)
Current state: the charset pipeline can expose characters, normalized brightness, raw density, and shape lanes through ASCIICharacterSet. StandardCharacterSet loads committed ShapeData .bin resources, RasterizedCharacterSet can rasterize a custom set with CoreText, and GlyphBank/GlyphCellRaster provide internal or tool-side raster data. BuildStandardVectors writes only the built-in .bin resources. DemoImageIO can write a PNG, and AskiPresetLab can write candidate renders, a contact sheet, and a manifest. There is no current atlas exporter, palette LUT artifact, LUT schema, or same-photo comparison harness. The referenced bcl-web image and HTML are absent from this checkout; the supplied bcl snapshot is historical context only, so I did not inspect another repository or the web.

Start here: Sources/Aski/ASCIICharacterSet.swift, Sources/Aski/CharacterSets/StandardCharacterSet.swift, Sources/Aski/CharacterSets/RasterizedCharacterSet.swift, Sources/Aski/CharacterSets/GlyphBank.swift, Tools/BuildStandardVectors/BuildStandardVectors.swift, Tools/AskiToolSupport/GlyphCellRaster.swift, Tools/AskiToolSupport/ImageFileIO.swift, and Tools/AskiPresetLab/PresetLabCLI.swift. Charset and vector tests provide the current contracts for ordering, digest stability, and provenance.

Constraints and dependencies: treat the hand-ordered ramp, directional edge buckets, Sobel neighborhood, luma transform, atlas dimensions, font, filtering, and palette colors in ASKI-58 as historical candidate settings, not as current product contracts. The task has no acceptance criteria, so define a lab manifest and an explicit “beats” rule before measuring. Preserve the distinction between normalized brightness and raw density; do not infer selector thresholds or invent a public API. The named consumer is the bcl-web three.js garden. Verify its recorded checkout/revision, exact photo, and atlas/LUT contract at implementation time; this context pass did not inspect that sibling repository. Keep the exporter in Tools and promote defaults only after the frozen comparison.

Validation to run: after the corpus and metric or human rule are frozen, generate an atlas PNG and palette LUT with provenance, compare both paths on the exact photo, and run the focused charset/vector tests plus the applicable research and artifact gates. No assets, tests, builds, or experiments were run here.

First step: define the lab artifact schema and ordering contract from the existing raster and charset data, then verify the named bcl-web reference photo and consumer contract before implementing the comparison.

Source map: `Tests/AskiTests/StandardCharacterSetScalarValidationTests.swift`.
<!-- SECTION:NOTES:END -->
