---
id: ASKI-1
title: Replace decoded-CGImage PNG round-trip with target-size preparation
status: To Do
assignee: []
created_date: '2026-08-18 18:01'
updated_date: '2026-09-10 04:15'
labels:
  - performance
  - conversion
  - image-io
dependencies: []
priority: high
type: enhancement
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A decoded CGImage currently enters conversion by first being encoded as PNG and then decoded again. Profiling found conversion preparation dominated the sampled path, and an isolated probe showed this preparation pattern is orders of magnitude slower than direct target-size drawing. Remove this avoidable work while preserving source-backed ImageIO behavior and output fidelity.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A decoded CGImage can be prepared at the requested conversion dimensions without PNG encoding or a new CGImageSource round-trip.
- [ ] #2 URL, Data, and other source-backed inputs retain their existing ImageIO thumbnail and orientation behavior.
- [ ] #3 Tests cover alpha, orientation, wide-gamut or tagged-color input, portrait and landscape sizing, and conversion output fidelity under explicit tolerances.
- [ ] #4 Representative static and video-frame benchmarks record before and after wall time, CPU time, and allocations or resident memory; the result demonstrates a material preparation-path improvement without a material end-to-end regression.
- [ ] #5 just check and just bench pass without loosening an existing benchmark threshold.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `ASCIIConverter.convert(_:columns:mask:)` enters `prepareConversion`, resolves grid dimensions and a thumbnail cap, then calls `ImageIOThumbnail.decode(image:maxPixelSize:)`. For an oversized direct `CGImage`, that helper allocates mutable data, creates a PNG destination, finalizes it, creates a new `CGImageSource`, and then invokes the normal ImageIO thumbnail path. Small images return the original image. The normal source/data paths use `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailWithTransform: true`, immediate caching, and a calculated decoder subsample factor. After decode, `samplingLattice` draws into an exact `columns * cellWidth × rows * cellHeight` RGBA8 raster with high interpolation. That ASKI-65 contract must remain intact.

Start here: inspect `ImageIOThumbnail.decode(image:)`, `makeThumbnail`, and `ASCIIConverter.prepareConversion`; then inspect `CellSampling.samplingLattice` and `readRGBA8`. File based tools already open one `CGImageSource` and call `ImageIOThumbnail.decode(source:maxPixelSize:)` through `DemoImageIO.loadThumbnailForConversion`, so their orientation-normalized source behavior is a separate path. `docs/architecture.md` records this boundary: CLI tools decode from a source before conversion, while direct library callers pass a `CGImage`.

Constraints and dependencies: ASKI-1 is the prerequisite for ASKI-2. Preserve alpha, source orientation, tagged color or wide gamut conversion, portrait and landscape sizing, and the current sRGB/Display P3 target color-space handling. Do not regress the uniform exact lattice or the one-pixel footprint fallback. ASKI-63's target-width renderer is already shipped and is downstream of this preparation work. There is no current converter overload accepting URL or Data; the public ImageIO data/source helpers and tool-support source path are the source-backed behavior to preserve.

Validation to run: add or extend ImageIO and converter tests for alpha, orientation, tagged color, portrait/landscape geometry, and output tolerance; retain `SamplingLatticeContractTests`. Then run `just check` and `just bench`; ASKI-1 requires before/after wall time, CPU time, allocation or resident-memory evidence and no loosened threshold.

First step: isolate the current direct-image preparation boundary and compare a target-size draw against the PNG/source round-trip while feeding the existing lattice and color conversion unchanged.

Source map: `Sources/Aski/ImageIOThumbnail.swift`, `Sources/Aski/ASCIIConverter.swift`, `Sources/Aski/CellSampling.swift`, `Tools/AskiToolSupport/ImageFileIO.swift`, `Tests/AskiTests/ImageIOThumbnailTests.swift`, `Tests/AskiTests/SamplingLatticeContractTests.swift`.
<!-- SECTION:NOTES:END -->
