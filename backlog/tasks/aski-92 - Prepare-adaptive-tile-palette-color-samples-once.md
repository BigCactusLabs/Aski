---
id: ASKI-92
title: Prepare adaptive tile palette color samples once
status: In Progress
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-11-13T08:41:00Z'
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
documentation:
  - Scripts/research/aski92-2026-11-13/README.md
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
- [x] #1 Release profiling separates sample preparation, Wu accumulation and k-means clustering for multiple lattice sizes, 8/16/64/256-color requests, sRGB/P3, and opaque/mixed-alpha inputs.
- [x] #2 Any adopted shared preparation preserves exact palette values/order and final tiles, including all-transparent input, empty clusters, and deterministic sample/arithmetic order.
- [ ] #3 Sample preparation is not repeated between Wu and k-means, without a material peak-memory or small-input regression.
- [ ] #4 Repeated end-to-end tile benchmarks show a material benefit against a stated bar, or the task records rejection.
- [x] #5 If adopted, just check and tile/color benchmarks pass without relaxed thresholds or a quantization-policy change.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Existing work reconciled — 2026-10-27

Draft PR #10 is open at e53d62f01e220c041e3b98394e9a305b1a9295e3: https://github.com/BigCactusLabs/Aski/pull/10 . Native palette/tile parity and full gate remain unverified; the reported packed-stride probe is not a process-memory result. Follow its control recipe and compare all 66 end-to-end workloads. Run its 120 candidate phase probes separately; candidate-only helpers do not belong in the restored scalar control. The prepared sample buffer overlaps the Wu tables, so require allocation/RSS evidence as well as time. The new paired reader prepares the readout, not the adoption verdict. Task stays open.

Audit 2026-11-12: draft PR #10 targets work/aski-86-benchmark-validity, which merged as public PR #7; retarget it to main before that branch is deleted.

2026-11-13: draft PR #10 retargeted to main; GitHub reports it CONFLICTING, so a rebase onto main is needed before the A/B.

2026-11-13 native replay: candidate 260ff2d versus scalar 4010636 has exact palette/tile parity and passing full gates (1547/1537 core, 177 media, 2 sentinels, DocC). A separate release diagnostic run completed all 120 phase workloads with wall, CPU, malloc and absolute RSS, six observations per cell. The existing 27-workload tile/color capture and unchanged Helmlab absolute budget passed. AC 1, 2 and 5 record these completed measurements and candidate checks; they do not mark adoption.

Both the original complete-study attempt and its sole unchanged fresh recovery stopped before any complete pair. Each hit SIGSEGV at 0x20c8 in malloc_interposer_reset during BenchmarkRunner initialization. Root cause remains unproved. No sample was substituted, no pin/threshold changed and no numeric benefit or rejection is claimed. Allocation-lifetime profiles at 160 and 512 in both arms remain unrun. AC 3 and 4 remain open; no shared-buffer production change is integrated. See Scripts/research/aski92-2026-11-13/README.md for crash excerpts, raw candidate-phase samples/table, frozen rules, source replay patches and native evidence hashes. Draft PR #10 and both isolated study branches remain preserved.

ASKI-109 now owns diagnosis of the reproduced allocator-reset failure. A new valid paired study remains dependent on resolving that instrumentation blocker.
<!-- SECTION:NOTES:END -->
