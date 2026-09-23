---
title: "TileGrid Hardening Notes"
slug: TileGridInternalHardening
date: 2026-05-28
status: living
subsystem: [tile-grid]
summary: "Rendering-substrate invariants, matrix-generation expectations, and benchmark discipline for keeping TileGrid semantics stable. Records the 2026-05-28 decision to ratify TileGrid, TileGridConverter, and TileGridMode as public."
runners: [AskiTileMatrix]
---

# TileGrid Hardening Notes

**Public-packaging decision (2026-05-28): ratified public.** `TileGrid`, `TileGridConverter`, and `TileGridMode` are public because the `AskiTileMatrix` harness consumes them cross-module, and `AGENTS.md` carries no public-API stability contract — source-breaking changes remain acceptable when they improve output quality, fit, or performance. The notes below are therefore the rendering-substrate invariants to preserve when changing TileGrid, not a frozen public surface.

## Internal Consumer Invariants

- `ASCIICell` and `TileCell` share `displayColor`, `alpha`, and `brightness` semantics.
- `brightness` means adjusted source OKLAB L after `RenderingOptions`, not rendered display luminance.
- `TileGrid` rendering is render-time only: mode and shape must not require re-running conversion.
- `TileGrid` renderers must tolerate ragged rows by iterating actual row contents.
- Transparent cells are skipped. In mosaic mode, skipped cells reveal grout; in non-mosaic modes, skipped cells reveal background.
- `TileGrid.colorSpace` selects the output `CGImage` color space.

## Render Matrix Harness

Generate all 15 mode x shape combinations from one input:

```bash
swift run AskiTileMatrix path/to/input.png <scratch-dir> --columns 64 --scale 12
```

Use the harness when changing:

- `TileGrid+Rendering.swift`
- `CellShapePaths.swift`
- `TileShading.swift`
- `TileGridMode.swift`
- `TileCellShape.swift`

## Benchmark Ritual

Run focused conversion cost:

```bash
swift package --allow-writing-to-package-directory benchmark --target AskiBenchmarks --filter "tile-converter-256cols-adaptive16"
```

Run focused render cost:

```bash
swift package --allow-writing-to-package-directory benchmark --target AskiBenchmarks --filter "tile-render-64x64"
```

Run the large render case before changing path generation, caching, or bevel/stud drawing:

```bash
swift package --allow-writing-to-package-directory benchmark --target AskiBenchmarks --filter "tile-render-256x256-pixelart-square-scale32"
```

## Known Non-Goals

- Do not expand README or DocC just to make TileGrid look public-ready.
- Do not add B-subsystem effects in this hardening pass.
- Do not rename `ASCII*` public types.
- Do not make Wu/k-means helpers public for benchmark convenience.
