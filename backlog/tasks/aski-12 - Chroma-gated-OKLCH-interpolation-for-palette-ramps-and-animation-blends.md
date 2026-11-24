---
id: ASKI-12
title: Chroma-gated OKLCH interpolation for palette ramps and animation blends
status: To Do
assignee: []
created_date: '2026-08-18T18:02:00Z'
updated_date: '2026-11-24T21:27:33Z'
labels:
  - research
  - color
dependencies: []
priority: low
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Fresh primary from the 2026-07-29 frontier sweep: Uchida, arXiv 2606.15352 (Jun 2026) — chroma-gated differentiable OKLCH interpolation that gates between cylindrical OKLCH and Cartesian Oklab by chroma magnitude, killing color casts where hue angle is perceptually unstable (near-neutral colors). The mechanism is a few lines and slots directly into Aski's OKLAB color path wherever ramps or blends interpolate (ResolvedPalette ramps, animation color blends, duotone). Context: CSS Color 4's own oklch gamut-mapping/interpolation behavior is still contested at spec level (CSSWG #7071, #10579) — also track #10579's static gamut-mapping outcome against GamutMapping.swift while in here.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Hue-spread stress ramps (near-neutral through high-chroma) rendered before/after: measurable color-cast reduction vs the current interpolation path
- [ ] #2 No perf regression on the color-path benchmarks (thresholds in Benchmarks/AskiBenchmarks unchanged)
- [ ] #3 Colored no-harm guard: existing golden/duotone outputs byte-identical unless the change is opted into, or the diff is justified in the verdict
- [ ] #4 DROP cleanly if cast reduction is not visible on the contact sheet — this is a small win or nothing
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: production palette data is either pass-through or a fixed array of palette colors; `ResolvedPalette` stores source color, OKLab, and Helmlab values, and the default cell-matching policy selects the nearest OKLab entry; opt-in matching policies also exist in `Sources/Aski/ColorPipelinePolicies.swift`. The current source does not expose a production OKLCH/cylindrical interpolation helper or a palette-ramp API. The only inspected color blend is the research temporal-prior path, which linearly blends stored OKLab components before finalizing a cell. Ongoing animation patterns explicitly preserve colors and only modulate alpha. This means the task's named ramp/duotone call sites need scope confirmation against current source before implementation.

Start here: enumerate actual interpolation call sites and distinguish palette selection, display-color gamut mapping, and temporal smoothing. `ColorConversion` provides OKLab/RGB transforms, while `GamutMapping` handles gamut mapping; neither is an interpolation policy. Keep the existing nearest-palette behavior separate from any future ramp or animation blend experiment.

Constraints and dependencies: any proposed research arm needs a frozen control and a measurable near-neutral/high-chroma hue-spread fixture. Existing animation golden tests capture glyph and alpha behavior and do not prove color no-harm. Existing palette tests verify OKLab conversion and Display P3 matrices, but do not test ramps. Animation benchmarks already have fixed wall-time, CPU, and allocation budgets; no threshold loosening is justified by this source inventory.

Validation to run: first produce before/after ramp or blend samples over the stress fixture, measure cast or hue-spread reduction, and compare colored goldens for byte identity where the path is unchanged. Keep the existing benchmark thresholds, then run `just check-fast` and `just check`. If the stress result does not reduce the measured cast, the task's registered drop condition applies.

First step: identify the concrete production or research-only interpolation API that the proposed change targets; if no ramp/duotone call site exists, record that gap before selecting OKLCH gating or changing any default.

Source map: `Sources/Aski/ASCIIPalette.swift`, `Sources/Aski/ResolvedPalette.swift`, `Sources/Aski/CellSampling.swift`, `Sources/Aski/Animation/ASCIIConverter+Temporal.swift`, `Sources/Aski/Animation/AnimatedASCIIGrid.swift`, `Tests/AskiTests/ResolvedPaletteTests.swift`, `Tests/AskiTests/AnimationByteIdenticalGoldenTests.swift`, `Benchmarks/AskiBenchmarks/AnimationBenchmarks.swift`.

2026-11-24 target check (read-only sweep at f3f7663; no code changed). No production API builds a palette ramp, gradient or duotone, and animation keeps each cell's displayColor and changes only alpha (Sources/Aski/Animation/AnimatedASCIIGrid.swift:66-70). The only explicit two-endpoint colour blend is the research-SPI temporal OKLab blend (Sources/Aski/Animation/ASCIIConverter+Temporal.swift:182-185, @_spi(AskiResearch)). Production colour averaging (CellSampling.swift:557 and :596, the ImageRenderer.swift:520 supersample area average, WuQuantizer and KMeansRefinement OKLab centroids) and gamut mapping (GamutMapping.swift: Ray Trace default, adaptive L0 opt-in) are not ramps, and no production path interpolates hue angle; hue-angle sampling exists only in Tools/AskiColorLab gamut-sweep references.
External refresh: arXiv 2606.15352 is N. Uchida, 'Chroma-gated, differentiable OKLCH interpolation: Continuous Oklab fallback for color-cast reduction' (submitted 2026-06-13); it blends the OKLCH and Oklab paths with a chroma gate w(C) = C^n / (C^n + sigma^n). CSSWG #10579 is open with no adopted algorithm (last activity 2026-09-01). CSSWG #7071 was closed 2026-08-31, reopened 2026-11-08, and is open. Neither changes GamutMapping.swift.
Recommendation for the owner: close ASKI-12 because current source has no target for it; file a new task if a product feature adds a palette ramp, gradient, or colour-blend animation.
<!-- SECTION:NOTES:END -->
