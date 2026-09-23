---
id: ASKI-17
title: Render entry points trap on accepted large-but-finite scale and font size
status: Done
assignee: []
created_date: '2026-08-19 05:19'
updated_date: '2026-08-20 04:14'
labels:
  - correctness
  - rendering
  - robustness
dependencies: []
references:
  - Sources/Aski/Renderers/ImageRenderer.swift
  - Sources/Aski/Tiles/TileGrid+Rendering.swift
  - Sources/Aski/Effects/Internal/CellRasterBuilder.swift
  - Sources/Aski/ASCIIFont.swift
priority: high
type: bug
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every raster path guards only `scale > 0, scale.isFinite` and then computes pixel dimensions with an unchecked `Int(ceil(...))`. Nothing bounds the product of columns, glyph size and scale, so a large-but-accepted finite value overflows the Double-to-Int conversion and traps instead of degrading.

Confirmed crashes (SIGTRAP, each in a fresh process):
- `ASCIIGrid.renderImage(font:backgroundColor:scale: 1e30)` -> ImageRenderer.renderGeometry, `Int(ceil(CGFloat(columns) * glyphWidth * scale))`
- `TileGrid.renderImage(scale: 1e30)` -> `Int(ceil(maxX))`
- `ASCIIGrid.renderImage(font: ASCIIFont(name: "Menlo", size: .infinity), scale: 1)` -> same conversion; `ASCIIFont.init(name:size:)` validates nothing, so an infinite or huge point size reaches the renderer

The same unguarded conversion also sits in `CellRasterBuilder.makeASCIIRaster` and `makeTileRaster`, which back the effects and CIImage overloads.

This is a graceful-degradation gap, not a missing feature: both renderers already have a `pixelWidth > 0, pixelHeight > 0` check and a documented 1x1 empty-image fallback for degenerate geometry. The Int conversion simply traps before that check can run, so the intended fallback is unreachable at the top of the range while it works fine at the bottom.

The scale guard is the natural place for the bound; whether the fix rejects, clamps, or falls back to the empty image should be one rule applied consistently across all four sites and both grid types.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 renderImage on ASCIIGrid and TileGrid returns the documented empty-image fallback (or throws a caller-matchable error on the throwing overloads) instead of trapping, for scale values up to Double.greatestFiniteMagnitude
- [x] #2 The same bound covers a non-finite or extreme ASCIIFont.pointSize, either by validating at ASCIIFont construction or by bounding the derived geometry
- [x] #3 CellRasterBuilder.makeASCIIRaster and makeTileRaster apply the identical rule, so the effects and CIImage overloads degrade the same way as the direct paths
- [x] #4 Regression covers scale 1e30, Double.greatestFiniteMagnitude, an infinite font size, and a huge finite font size, across ASCIIGrid direct, TileGrid direct, effects and CIImage paths
- [x] #5 Output for all currently-valid scale and font-size combinations is byte-identical, and just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landed in merge commit da78b1a (Batch A).

One shared helper, RenderPixelBounds.pixelExtent (Sources/Aski/Renderers/ImageRenderer.swift), applied at every raster site so the rule cannot drift: ImageRenderer.renderGeometry, CellRasterBuilder (two sites) and TileGrid+Rendering. It returns nil for a non-finite or out-of-range extent, and each caller then takes its ALREADY DOCUMENTED empty-image fallback. The fallback was unreachable before: the Int(ceil(...)) conversion trapped before the existing pixelWidth > 0 guard could run, so the intended degradation worked at the bottom of the numeric range and crashed at the top.

Cap is 1 << 20 per axis, per-axis rather than total-pixel-count: every CGContext on these paths is created with data: nil and guard-let checked, so a geometry passing both axis caps but too large to allocate already returns the empty image. Verified, not assumed.

AC#2 resolved by bounding the DERIVED GEOMETRY rather than validating ASCIIFont.init — a non-finite pointSize falls out naturally as a non-finite product. One rule at one layer, across four call sites. ASKI-35 depends on this decision and must not add a competing check on the same input.

A third unguarded conversion in CellRasterBuilder, in a different function from the two this task named, was found by a variant sweep and is included.

Coverage: RenderGeometryBoundsTests across ASCIIGrid direct, TileGrid direct, effects and CIImage paths. Byte-identity is real here — 89 committed snapshots, all compared exact (no precision: anywhere in the repo), all green, none re-recorded.
<!-- SECTION:NOTES:END -->
