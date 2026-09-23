---
id: ASKI-37
title: >-
  Unguarded float-to-Int conversions across sampling, resampling and
  quantization
status: Done
assignee: []
created_date: '2026-08-20 03:15'
updated_date: '2026-08-24 14:41'
labels:
  - correctness
  - robustness
dependencies: []
references:
  - Sources/Aski/CellSampling.swift
  - Sources/Aski/ASCIIConverter.swift
  - Sources/Aski/Algorithms/LumaResample.swift
  - Sources/Aski/Video/ResampleSession.swift
  - Sources/Aski/Tiles/WuQuantizer.swift
  - Sources/Aski/CharacterSets/RasterizedCharacterSet.swift
  - Sources/Aski/Algorithms/ShapeContext.swift
priority: low
type: bug
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The residue of the Batch A variant sweep: float-to-Int conversions with no isFinite or range check in scope. Lower confidence than ASKI-33 — several of these are probably safe because their inputs are structurally bounded — so the first job is triage, not a blanket fix.

- CellSampling.swift:127 — max(1, Int(projectedRows)), projectedRows from geometry math, no isFinite check
- ASCIIConverter.swift:501 — Int(scaled), traced from float geometry math, no bound in scope
- Algorithms/LumaResample.swift:47-48 and :65 — Int(s0.rounded(.down)), Int(s1.rounded(.up)), Int(p.rounded(.down)) on float sample coordinates
- Video/ResampleSession.swift:160 — Int((start * targetFPS).rounded(...)), unclear whether start is bounded upstream
- Tiles/WuQuantizer.swift:288 — Int(normalized * Float(bins)), normalized presumed 0-1 but not asserted
- CharacterSets/RasterizedCharacterSet.swift:153 and :159 — max(1, Int(advance.width.rounded(.up))) and the ascent+descent twin, both on CTFont metrics with no isFinite check
- Algorithms/ShapeContext.swift:44 — min(11, Int(theta / (2 * .pi) * 12)) is bounded above but not below, and NaN is unchecked
- Algorithms/ShapeStructureChannels.swift:104 and :111 — Int((min(w,h)/2).rounded(.down)) and Int((dx*dx+dy*dy).squareRoot().rounded())
- Algorithms/EdgeMapKernel.swift:71 — Int((angle / (.pi/4)).rounded()) % 4; the modulo bounds the result but angle is unchecked for NaN

Two sites are already correct and are worth copying as the reference pattern rather than changing: Video/ResampleSession.swift:35 and :38 bound the Double against Int.max before converting, with an explanatory comment, and Algorithms/ShapeContext.swift:41 clamps on both sides.

Deferred from the Batch A work to avoid widening that batch mid-flight.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each listed site is triaged as genuinely reachable out-of-domain, or structurally bounded with the bound named
- [x] #2 Reachable sites adopt the existing correct pattern from ResampleSession.swift:35-38 rather than a new one
- [x] #3 CTFont metric reads in RasterizedCharacterSet are guarded, since font metrics come from outside the library
- [x] #4 Regression covers the sites judged reachable; structurally bounded sites get a comment naming the bound instead of a guard
- [x] #5 Output for all currently-valid inputs is byte-identical, and just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-24 implemented on aski-37 (commit 2f23214, merged to batch-validation ca19f1f). Triage: 6 sites structurally bounded (CellSampling.gridDimensions, LumaResample.resample1D, WuQuantizer.binIndex, ShapeContext.histogram60 angle bin, ShapeStructureChannels.radialProfile, EdgeMapKernel angle bucket) — each got a comment naming the bound, no guard. 2 sites reachable and fixed: ASCIIConverter.thumbnailMaxPixelSize (old guard used <= Double(Int.max), which rounds one past Int.max; now strict < with isFinite/positive checks) and RasterizedCharacterSet CTFont metrics (shared boundedCellMetric guard; invalid external metrics degrade to a 1px cell). ResampleSession.slot(of:) already guarded by ASKI-33/35, kept. Regressions: portraitThumbnailSizeRejectsTheDoubleIntMaxBoundary, outOfDomainCoreTextMetricsDegradeWithoutTrapping. Full just check green (1,308 core + 152 media + 2 sentinels).
<!-- SECTION:NOTES:END -->
