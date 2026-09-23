---
id: ASKI-34
title: CIImage infinite extent traps the raster builders
status: Done
assignee: []
created_date: '2026-08-20 03:14'
updated_date: '2026-08-24 15:36'
labels:
  - correctness
  - effects
  - masking
  - robustness
dependencies:
  - ASKI-17
references:
  - Sources/Aski/Effects/Internal/StockCIEffectKernel.swift
  - Sources/Aski/Masking/CoverageImageBuilder.swift
priority: medium
type: bug
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two builders convert a CIImage extent to pixel dimensions with an unchecked Int conversion:
- StockCIEffectKernel.swift:236-237 — Int(ceil(extent.width)) / Int(ceil(extent.height))
- CoverageImageBuilder.swift:58-59 — the same pattern

CoreImage returns CGRectInfinite for generator filters and some tiled filters, so extent.width can legitimately be infinite. The conversion then traps.

This is the same conversion defect as ASKI-17 but arrives by a different route: not a caller-supplied scale, but a CoreImage value that is infinite by design. ASKI-17 bounds derived geometry behind caller input and may have already covered the StockCIEffectKernel site; confirm the current state before starting, and scope this task to whatever remains.

The degradation choice is NOT settled and must not be improvised: an infinite extent may want a clamped or cropped rect rather than the empty-image fallback ASKI-17 uses, because the image genuinely exists and is merely unbounded. Decide deliberately and document the choice.

Found by a variant sweep during the Batch A validation work (ASKI-6/17/18/19/23/24); deferred to avoid widening that batch mid-flight. CoverageImageBuilder is also touched by ASKI-20, so sequence the two to avoid a conflict.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An infinite or non-finite CIImage extent degrades deliberately at both sites instead of trapping
- [x] #2 The chosen degradation (clamp, crop, or empty image) is documented with its rationale, and is consistent between the two sites
- [x] #3 The interaction with ASKI-17's derived-geometry bound is stated, so the two rules do not disagree about the effects path
- [x] #4 Regression drives a genuinely infinite-extent CIImage through the effects path and the coverage path
- [x] #5 Output for all finite-extent inputs is byte-identical, and just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24: implemented and merged to main in PR #28 (batch-validation wave, merge b835160); all ACs were already checked — status flip only.
<!-- SECTION:NOTES:END -->
