---
id: ASKI-92
title: Prepare adaptive tile palette color samples once
status: In Progress
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-11-13T06:40:00Z'
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
  - https://github.com/BigCactusLabs/Aski/pull/10
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
- [x] #2 Any adopted shared preparation preserves exact palette values/order and final tiles, including all-transparent input, empty clusters, and deterministic sample/arithmetic order.
- [ ] #3 Sample preparation is not repeated between Wu and k-means, without a material peak-memory or small-input regression.
- [ ] #4 Repeated end-to-end tile benchmarks show a material benefit against a stated bar, or the task records rejection.
- [ ] #5 If adopted, just check and tile/color benchmarks pass without relaxed thresholds or a quantization-policy change.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Apply the existing packed-sample production, parity controls and benchmark deltas onto current main. Preserve all intervening registrations and numerical behavior.
2. Verify the source diff and benchmark inventory without native execution during the source-only phase. Prepare the exact current-base treatment reversal and paired-capture commands.
3. After native host assignment, require exact palette and tile parity, the full local gate, five alternating pairs of all 66 end-to-end cases, and a separate 120-case phase attribution capture with process peak RSS and allocation evidence. Apply the existing 5% adaptive benefit and 3% regression guards before deciding adoption.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Existing work reconciled — 2026-10-27

Draft PR #10 is open at e53d62f01e220c041e3b98394e9a305b1a9295e3: https://github.com/BigCactusLabs/Aski/pull/10 . Native palette/tile parity and full gate remain unverified; the reported packed-stride probe is not a process-memory result. Follow its control recipe and compare all 66 end-to-end workloads. Run its 120 candidate phase probes separately; candidate-only helpers do not belong in the restored scalar control. The prepared sample buffer overlaps the Wu tables, so require allocation/RSS evidence as well as time. The new paired reader prepares the readout, not the adoption verdict. Task stays open.

Audit 2026-11-12: draft PR #10 targets work/aski-86-benchmark-validity, which merged as public PR #7; retarget it to main before that branch is deleted.

2026-11-13: draft PR #10 retargeted to main; GitHub reports it CONFLICTING, so a rebase onto main is needed before the A/B.

Overnight source port prepared on e9ac79bd48ab0d387d85cedf15f5bab244fc0aad. The frozen quantizers remain independent and final-tile parity uses the current converter lattice. The full E2E and phase selections are retained. The two count metrics request unscaled exports in both future measured arms. Native acceptance and all five ACs remain open.

2026-11-13 native candidate gate passed: just check (1547 core, 177 media, two deadlock sentinels and DocC), including all three packed-storage tests and seven shared-sample/quantizer/final-tile parity tests. No gate source changed. The candidate remains isolated; this is correctness evidence, not a performance or memory verdict. Commit the November 13 rule and scalar control before the five-pair study.
<!-- SECTION:NOTES:END -->
