---
id: ASKI-13
title: Measure and reduce per-cell Core Text rendering allocation
status: To Do
assignee: []
created_date: '2026-08-18 18:02'
updated_date: '2026-09-10 04:15'
labels:
  - performance
  - rendering
  - core-text
dependencies:
  - ASKI-5
priority: low
type: spike
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ImageRenderer currently constructs color and Core Text layout objects for each visible cell. Measure the cost on representative grids and determine whether a guarded lower-allocation rendering path materially improves render time without breaking custom-character layout, Unicode correctness, color, or positioning.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A repeatable benchmark reports render wall time, CPU time, and allocations for representative 80-column and larger grids across built-in and custom character sets.
- [ ] #2 The investigation identifies the allocation and layout share attributable to per-cell color, attributed-string, CTLine, and draw work using profiler evidence.
- [ ] #3 Any adopted fast path is limited to characters whose glyph mapping and positioning are proven equivalent, with the existing Core Text layout behavior retained for complex grapheme clusters and custom characters.
- [ ] #4 Rendered output preserves glyph choice, baseline, alignment, foreground and background color, alpha, and deterministic dimensions under exact comparison or explicit image tolerances.
- [ ] #5 The task records an adopt-or-reject decision based on a material end-to-end rendering improvement, not only a microbenchmark win.
- [ ] #6 If code is adopted, just check and just bench pass without loosening an existing benchmark threshold.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `ASCIIGrid.renderImage` and its target-width, extended-range, and mask-ground routes share `drawCells`. For every visible non-braille cell, `drawCells` computes effective alpha, invokes a foreground-color closure that creates a `CGColor`, constructs an `NSAttributedString` with the cell's `Character`, `font.ctFont`, and foreground color, creates a `CTLine`, sets the cell text position, and calls `CTLineDraw`. Braille code points bypass Core Text through `BrailleRasterizer`. Character mask fallbacks repeat the attributed-string and CTLine construction in `drawMaskFallbackOverlay`. `renderAttributedString` is a separate renderer that already batches adjacent identical colors into runs.

Start here: inspect `ImageRenderer.drawCells`, `drawMaskFallbackOverlay`, and `ASCIIFont.ctFont`; then inspect `RasterizedCharacterSet`, whose construction also rasterizes each custom `Character` through Core Text and image bounds. The image path is used by the video and GIF render pumps, so a render change affects static output and media throughput. Existing tests cover dimensions, foreground color, braille dispatch, mask fallback alpha/color, target-width geometry, and the byte-level G0 golden.

Constraints and dependencies: ASKI-13 depends on ASKI-5, which in turn depends on ASKI-1, ASKI-2, and ASKI-4. Any fast path must be limited to characters with proven glyph mapping and positioning equivalence; keep the Core Text layout path for complex grapheme clusters, Unicode cases, and custom characters. Preserve glyph choice, baseline, alignment, color space, foreground alpha, mask coverage, and deterministic dimensions. The G0 golden and existing snapshots are output guards; if the frozen preset goldens move, commit the selection-ceiling before/after MAE and GMSD no-harm CSV alongside any re-recorded goldens. Coordinate with ASKI-3 because both tasks touch renderer color creation.

Validation to run: add repeatable 80-column and larger render benchmarks over built-in and custom sets, reporting wall time, CPU time, malloc count, and resident-memory signal. Use profiler evidence to split color, attributed-string, CTLine, and draw cost, then exercise ImageRenderer, mask, Unicode/custom-character, and golden tests. If code is adopted, run `just check` and `just bench` without loosening an existing threshold; decide on end-to-end rendering gain, not an isolated allocation count.

First step: establish a baseline for `render-image-gradient-80cols` and a larger/custom-grid fixture, then measure whether color creation, attributed strings, CTLine creation, or drawing dominates before selecting a guarded cache or batching strategy.

Source map: `Sources/Aski/Renderers/ImageRenderer.swift`, `Sources/Aski/Renderers/AttributedStringRenderer.swift`, `Sources/Aski/CharacterSets/RasterizedCharacterSet.swift`, `Tests/AskiTests/ImageRendererGoldenTests.swift`, `Tests/AskiTests/ImageRendererTests.swift`, `Benchmarks/AskiBenchmarks/Benchmarks.swift`.
<!-- SECTION:NOTES:END -->
