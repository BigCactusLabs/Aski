---
id: ASKI-1
title: Replace decoded-CGImage PNG round-trip with target-size preparation
status: Done
assignee: []
created_date: 2026-08-18 18:01
updated_date: '2026-11-10T20:41:00Z'
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
- [x] #1 A decoded CGImage can be prepared at the requested conversion dimensions without PNG encoding or a new CGImageSource round-trip.
- [x] #2 URL, Data, and other source-backed inputs retain their existing ImageIO thumbnail and orientation behavior.
- [x] #3 Tests cover alpha, orientation, wide-gamut or tagged-color input, portrait and landscape sizing, and conversion output fidelity under explicit tolerances.
- [x] #4 Representative static and video-frame benchmarks record before and after wall time, CPU time, and allocations or resident memory; the result demonstrates a material preparation-path improvement without a material end-to-end regression.
- [x] #5 just check and just bench pass without loosening an existing benchmark threshold.
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

2026-11-10 implementation (branch aski-1-direct-cgimage-preparation, PR https://github.com/BigCactusLabs/Aski/pull/23):
- 954a1c5 adds measurement-only preparation benchmarks; 091eaef pre-registers the census rule; 05af50c implements direct preparation (vImage Lanczos straight to the sampling lattice for an oversized source, CoreGraphics draw within budget, ImageIOThumbnail.decode(image:) removed); f1d9fff records the census; 6f032dc and b674dd5 update docs, CHANGELOG and the repo map; a56a570 merges main.
- AC1: samplingLattice(image:) in CellSampling.swift resamples the CGImage directly; no PNG encode and no CGImageSource. Pinned by TargetSizePreparationTests.
- AC2: decode(data:) and decode(source:) unchanged; ImageIOThumbnailTests adds EXIF-orientation tests for both and the CLI URL loader.
- AC3: TargetSizePreparationTests covers alpha, orientation, sRGB / Display P3 8- and 16-bit / extended-linear half float / gray / BGRA video frame, portrait and landscape sizing, and conversion fidelity against an area-averaged reference with stated tolerances.
- AC4: p50 before/after (one Mac): prepare photo 4032x3024 677.4 -> 27.8 ms wall, 22.7 -> 1.4 MB peak; prepare frame 1920x1080 21.9 -> 4.7 ms; 720p video benchmarks 33-85% faster wall, 41-68% less CPU. Trade-off for the owner: peak resident +8.3 MB and +5.3 MB on the two rotated end-to-end video benchmarks (likely the full-size RGBA8 copy of each CIContext-oriented frame; ASKI-2 removes that frame). Full table in the PR body.
- Census: NO HARM under the rule frozen at 091eaef. Frozen-preset production-arm MAE ratio x1.0000 (steerable) and x0.9991 (structure); GMSD x1.0000 and x1.0009 (non-gating). Note docs/Research/2026-11-10-aski-1-direct-cgimage-preparation.md.
- AC5: just check and just bench pass on merge commit a56a570 (main 810c908, PR #22, merged in; four conflicting mask snapshots and the DocC mask-ground-after figure re-recorded against the combined code), and on b674dd5 before the merge. No benchmark threshold changed.
- Goldens (18 snapshots, inline digests, two DocC figures) re-recorded on one Mac only; no second-host check.
- Visible change for owner review: in the DocC mask-ground figure (standard set) the picks inside the mask shift from letter shapes toward denser glyphs such as # and @. The census measures tone error, not glyph identity across sides, and the cause on this figure is not established. Before/after images are in the PR.

2026-11-10: the owner accepted both PR #23 calls (rotated-video peak memory, with ASKI-2 as the fix; the DocC glyph shift). Cause of the glyph shift: on main the 975x1280 portrait's ImageIO thumbnail was 119x158 against a 120-pixel width budget, so cellWidth was 1 and LogPolarKernel took its tone-only fallback (cellSupportsShapeDescriptor false); preparedSize rounds to 120, so cellWidth is 2 and the shape descriptor runs, giving ASKI-80's same-glyph runs. The rounding and resampler changes were not measured separately. CHANGELOG and PR body updated.

2026-11-10: PR #23 merged as ba98fc5 (merged tree = reviewed head 1fb9167). Owner accepted the rotated-video peak-memory rise (fix: ASKI-2) and the DocC glyph shift (cause: main sampled the portrait at cellWidth 1, tone-only).
<!-- SECTION:NOTES:END -->
