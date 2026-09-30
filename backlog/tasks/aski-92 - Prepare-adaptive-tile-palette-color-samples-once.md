---
id: ASKI-92
title: Prepare adaptive tile palette color samples once
status: To Do
assignee: []
created_date: '2026-09-30 00:20'
labels:
  - performance
  - tiles
  - color
dependencies: []
references:
  - Sources/Aski/Tiles/TilePalette+Resolved.swift
  - Sources/Aski/Tiles/WuQuantizer.swift
  - Sources/Aski/Tiles/KMeansRefinement.swift
  - Benchmarks/AskiBenchmarks/TileGridBenchmarks.swift
priority: medium
type: enhancement
ordinal: 93000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TilePalette.resolved (Sources/Aski/Tiles/TilePalette+Resolved.swift:17-29) runs Wu quantization and k-means over the same RGBA raster. WuQuantizer.swift:54 and KMeansRefinement.swift:78 independently skip transparent pixels, unpremultiply RGB, decode channels, and convert to OKLab in the same pixel order. K-means already retains the converted samples. This is two color-preparation passes before clustering.

Source mechanism verified at c49bbd in the 2026-09-29 sweep. The existing tile-quantize-rich-512x512-256cols-adaptive16 workload measured wall p50 49 ms, p90 51 ms in one release run; no profile attributed the total to preparation. ASKI-1 owns earlier input preparation and ASKI-3 owns renderer color-space semantics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release profiling separates sample preparation, Wu accumulation and k-means clustering for multiple lattice sizes, 8/16/64/256-color requests, sRGB/P3, and opaque/mixed-alpha inputs.
- [ ] #2 Any adopted shared preparation preserves exact palette values/order and final tiles, including all-transparent input, empty clusters, and deterministic sample/arithmetic order.
- [ ] #3 Sample preparation is not repeated between Wu and k-means, without a material peak-memory or small-input regression.
- [ ] #4 Repeated end-to-end tile benchmarks show a material benefit against a stated bar, or the task records rejection.
- [ ] #5 If adopted, just check and tile/color benchmarks pass without relaxed thresholds or a quantization-policy change.
<!-- AC:END -->
