---
id: ASKI-95
title: Measure bounded reuse of fallback effect noise rasters
status: To Do
assignee: []
created_date: '2026-09-30 00:20'
labels:
  - performance
  - effects
  - rendering
dependencies: []
references:
  - Sources/Aski/Effects/Internal/StockCIEffectKernel.swift
  - Sources/Aski/Effects/Internal/MetallibEffectKernel.swift
  - >-
    https://developer.apple.com/documentation/coreimage/cicontextoption/cacheintermediates
priority: low
type: spike
ordinal: 96000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
StockCIEffectKernel.swift:223-230 and :255-269 generate seeded noise for dust/grain on every application. seededNoise allocates width*height*4 bytes, fills the raster serially, then wraps it as CGImage/CIImage. Identical dimensions/seed produce identical raster bytes; a dust-plus-grain chain can construct it twice. MetallibEffectKernel.swift:18 confirms this is a fallback path, so its product frequency and practical cost are unknown.

Source mechanism verified at c49bbd during the 2026-09-29 sweep; no fallback profile or cache implementation was run. This is a lower-priority measurement task, not authority for unbounded global caching. Apple documents that Core Image caching trades repeated-render speed against memory; that does not prove reuse of this freshly constructed CPU raster.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A focused reduced-capability harness measures raster construction separately from final CI rendering at 512-square and 1080p output, repeated/changing seeds, and dust/grain/combined chains.
- [ ] #2 The task records fallback reachability/frequency assumptions and an adopt/reject decision against a stated material repeated-render benefit bar.
- [ ] #3 Any adopted reuse preserves exact seeded output, extent/origin and fallback semantics, remains deterministic under concurrent calls, and includes all raster-affecting inputs.
- [ ] #4 Retained raster memory has an explicit measured bound/lifetime; changing-seed workloads and normal Metal rendering have no material regression.
- [ ] #5 If adopted, just check and relevant effects/media benchmarks pass without relaxed thresholds.
<!-- AC:END -->
