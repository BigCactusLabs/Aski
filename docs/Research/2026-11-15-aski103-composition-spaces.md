---
title: "ASKI-103 — mask and glyph composition spaces"
slug: 2026-11-15-aski103-composition-spaces
date: 2026-11-15
status: complete
subsystem: [color-science, tile-grid]
summary: "KEEP current per-stage composition: 496 applicable rows pass a frozen mask and glyph diagnostic across 18 paths; 24 tile glyph rows are not applicable. The ASCII policy selects the Core Graphics raster space, while later Core Image operations and deferred consumers retain their own spaces. Defaults and goldens are unchanged."
related_specs: [Sources/Aski/Aski.docc/Masking.md, Sources/Aski/Aski.docc/Rendering.md]
---

# ASKI-103 — mask and glyph composition spaces

**Decision: KEEP the current per-stage behavior and document its scope.** All
496 applicable rows passed the [frozen protocol](../../Scripts/research/aski103-2026-11-15/PROTOCOL.md).
The remaining 24 rows are tile glyph-antialiasing placeholders: tiles have no
glyphs and no composition-policy knob. This is a compatibility decision for the
measured stages, not a universal quality ranking of encoded and linear blending.

The protocol and instrument were committed at
`e609764b0c186880a5175a037a4e9014e07007f0` before the first capture. Independent
source review checked route reachability and predictions. Before capture, its
target-width control was strengthened to run the actual reducer on a known
mixed raster; target-width glyph claims were narrowed to consistency. No
threshold changed after capture. [Results, CSV, and provenance](Results/2026-11-15-aski103-composition/README.md)
record one Apple M3 Max on macOS 27.0.1, Xcode 27.0, Swift 6.4.

## What the measurement establishes

- All 18 existing mask-color entry points were exercised in sRGB and Display P3,
  including cross-gamut engine output. ASCII paths used both composition
  policies. Each CI-output path used encoded and linear consumer contexts.
- The 432 opaque-mask rows distinguish encoded from linear-light branch
  interpolation at three coverage values, with and without a positive ground.
  The maximum RGB residual from the source-selected model was 1.25 code values
  against a limit of 4. The other model's smallest MAE was 32.75.
- The 48 ASCII glyph rows separately measure antialiasing against a matched
  transparent reference. Maximum RGB MAE was 0.2782 and maximum individual
  error 0.9381, below limits of 3 and 8. The 44 non-target-width rows separate
  the two models by at least 57.41 MAE. Target-width glyph rows are consistency
  checks; the synthetic reducer controls supply the known-difference test.
- All 16 controls passed, including tagged readback, CI mask processing,
  explicitly linear source-over, and the real target-width reducer. Their
  largest RGB residual was 0.4840, below the limit of 2.

The [Masking guide](../../Sources/Aski/Aski.docc/Masking.md) gives the route table.
The [Rendering guide](../../Sources/Aski/Aski.docc/Rendering.md) separates the
ASCII raster policy, glyph source-over, and target-width reduction. An ASCII
grid's linear policy does not override a deferred CI consumer. Forcing every
Core Image operation into encoded space would change filter math beyond this
mask experiment; the evidence does not justify that change.

## External evidence and limits

Apple's current [working-color-space documentation](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace.md)
states that inputs and outputs are color matched through the context's working
space, whose default is extended sRGB with linear gamma. An explicit RGB
working space is supported, so that default does not prohibit encoded
processing. The older [Core Image guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_performance/ci_performance.html)
is consistent with this default; the current API documentation reconfirms it.
Aski's explicit source-over space and consumer-dependent mask graph were also
checked against source and the selected SDK's `CIKernel.h`.

Tier coverage: owner API documentation and current Aski/SDK source were used.
No external benchmark, practitioner consensus, or human preference is claimed.
Neutral fixtures isolate transfer laws; the existing chromatic mask-color tests
cover declared paint-space interpretation. This single-host run does not prove
exact cross-host raster parity or effects-wide perceptual quality.

Production rendering code and golden files did not change. The full native gate
passed before capture; no golden re-record or frozen-reference no-harm census
was needed.
