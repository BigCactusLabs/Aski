---
id: ASKI-95
title: Measure bounded reuse of fallback effect noise rasters
status: In Progress
assignee: []
created_date: '2026-09-30T00:20:00Z'
updated_date: '2026-11-25T17:58:16Z'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit 2026-11-12: public PR #13 (f59926b) landed FallbackNoiseGroundworkTests. seededNoise call sites moved to about :221 and :253, definition about :265.

Audit 2026-11-24: the anchors moved again after bc0e31f (PR #29). At b676dce the `seededNoise` call sites are Sources/Aski/Effects/Internal/StockCIEffectKernel.swift:231 and :251, and the definition is at :263; find them by symbol name. The ASKI-94 and ASKI-89 rejections cover other paths and do not change this task.

2026-11-25 frozen decision rule (set by the lead before any measurement; recorded verbatim before timing):
R1 Reachability. Establish, with file:line evidence, every configuration in which the stock Core Image dust/grain fallback runs in a shipping build (metallib missing or failing to load, unsupported device or OS, an explicit option, tests only). If it runs in no supported shipping configuration, the verdict is REJECT and no candidate is built.
R2 Ceiling. Measure raster construction (seededNoise alone) separately from the end-to-end fallback render, release configuration, serial, under the gate lock: 512x512 and 1920x1080 output; dust, grain, and dust+grain chains; repeated same-seed and changing-seed workloads; at least 5 repetitions per case, reporting medians and spread. If raster construction is under 10% of the end-to-end same-seed repeated render wall time for the 1920x1080 dust+grain chain (the most a perfect cache could save), the verdict is REJECT and no candidate is built.
R3 Candidate. Only if R1 and R2 both pass: build a bounded reuse candidate keyed by every raster-affecting input, with an explicit retained-memory bound and lifetime, deterministic under concurrent calls. ADOPT only if all hold: byte-identical output to the control across every measured case and the existing effect tests; paired (alternating control/candidate, at least 5 pairs) median end-to-end wall-time improvement of at least 10% for the 1920x1080 dust+grain same-seed case; no changing-seed case and no Metal-path case regresses by more than 2%; retained memory within the stated bound. Otherwise REJECT and keep the candidate only as a replay patch.

2026-11-25 operational definitions (lead ruling, registered before timing):
- End-to-end fallback render = the production effect stage only: EffectsRenderEngine.runEffectChainSync on a fixed CGImage-backed WxH gradient input with a reducedQuality(.metallibUnsupported) EffectContext in extended linear sRGB, then EffectsRenderEngine.shared.context.createCGImage(RGBA8, sRGB). Glyph rasterization and composition are excluded; this smaller denominator makes R2 easier to pass.
- Raster construction = one call of a verbatim replica of the private StockCIEffectKernel.seededNoise (harness Scripts/research/aski95-2026-11-25/, copied into Tests/AskiTests only for replay; no production seam). The harness checks source-text identity and byte equivalence: production dust/grain fallbacks over a clear input rendered in RGBAf equal the same operations fed the replica raster, with the replica's byte-to-value map checked injective.
- R2 share = 2 x median(raster, 1920x1080, same seed) / median(fallback end-to-end, 1920x1080, dust+grain, same seed), because that chain constructs the raster twice.
- Timing: release (xcrun swift test -c release), one serial process under the gate lock, 3 warmups then 15 timed repetitions per case, cases interleaved round-robin; Metal-path end-to-end rows are recorded descriptively for R3.
<!-- SECTION:NOTES:END -->
