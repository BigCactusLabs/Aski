# Aski Design Notes

## Overview

Aski converts images to ASCII art via a 60-dimensional log-polar histogram of per-pixel inverted-luma weights, matched against a character-set bank by brightness-prefiltered squared L2 distance. This file explains the implemented descriptor, its lineage, and measured limitations. For package boundaries and the running pipeline, use the [architecture reference](docs/architecture.md); for change locations and verification, use the [agent navigation guide](docs/agents/navigation.md). This is implementation context, not the public API guide or a research roadmap.

## Source of truth

| Concern | Implementation | Contract or evidence |
| --- | --- | --- |
| Query extraction and edge blend | [LogPolarKernel](Sources/Aski/Algorithms/LogPolarKernel.swift) | [Algorithms guide](Sources/Aski/Aski.docc/Algorithms.md) |
| Histogram geometry and normalization | [ShapeContext](Sources/Aski/Algorithms/ShapeContext.swift) | [Footprint parity tests](Tests/AskiTests/ShapeContextFootprintTests.swift) |
| Brightness shortlist and winner order | [ShapeMatching](Sources/Aski/ShapeMatching.swift) | [Ranking contracts](Tests/AskiTests/BrightnessRankingContractTests.swift) |
| Candidate raster and bank | [RasterizedCharacterSet](Sources/Aski/CharacterSets/RasterizedCharacterSet.swift), [GlyphBank](Sources/Aski/CharacterSets/GlyphBank.swift) | [Character Sets guide](Sources/Aski/Aski.docc/CharacterSets.md) |
| Sampling, color, and palette resolution | [CellSampling](Sources/Aski/CellSampling.swift), [ColorConversion](Sources/Aski/ColorConversion.swift) | [Color-sampling tests](Tests/AskiTests/ColorSamplingPolicyTests.swift) |

Current code and tests define behavior. Dated research notes retain the settings,
inputs, and verdicts of each study; a proposed or rejected arm is not a shipping
feature. Before changing matching or baselines, read the
[research methodology](docs/agents/research-methodology.md).

## Algorithm Overview

### The 60D log-polar descriptor

The default query uses BT.601-style coefficients on the prepared, transfer-encoded RGB bytes:

```
w(p) = 1 - (0.299·R + 0.587·G + 0.114·B)
```

The prepared raster is in the converter's target gamut (sRGB by default, optionally Display P3); the descriptor does not first transform Display P3 to sRGB. These coefficients describe the implemented signal, not a claim of gamut-correct luminance. `ShapeQueryPolarity.direct` changes the signal only through `@_spi(AskiResearch)`; the ordinary default remains inverted.

Weights below `0.05` are excluded. Admitted pixels lie between radius `0.5` and half the shorter cell axis, inclusive, around `(width / 2, height / 2)`. Weights accumulate in raster order into a histogram laid out in log-polar geometry: **5 log-spaced radial bins × 12 uniform angular bins = 60 bins**, then L1-normalized when its sum is positive. No admitted mass produces 60 zeros. Production conversions reuse an immutable `ShapeContext.Footprint` pixel-to-bin map for each resolved cell size, preserving scalar accumulation order; the scalar implementation remains the glyph-building path and parity control. The layout follows the canonical Shape Context construction of Belongie, Malik, and Puzicha (2002), adapted to dense per-cell histograms rather than sparse point sets.

> **How many of those 60 bins are actually reachable depends on `oversample`, and at the default it is very few.** In the recorded default-sampling measurements, the integer cell pitch was exactly `oversample` pixels wide. This is not a sizing rule for every shape or source size; the current [oversampling contract](Sources/Aski/Aski.docc/Algorithms.md#oversampling) also protects the short axis for portraits and `.tall` landscapes, without upscaling small sources. At the measured default `oversample: 2` the descriptor's radius gate admits 2–3 pixels of 8 and reaches **2–3 of the 60 bins** — after L1 normalization, a 1-to-2 parameter statistic rather than a shape basis. Glyph reference descriptors are built on a square 64×64 raster and average 27.9 non-zero bins, so query and candidate do not share a support. Raising `oversample` lifts reachable support (48 of 60 at `32`) but does **not** measurably improve pick quality — it is a null, not a fix. This is a property of the sampling regime, not of the descriptor design described here. Measured in the [sampling-support study](docs/Research/2026-08-19-sampling-lattice-support-collapse.md) and [selection-gap study](docs/Research/2026-08-19-selection-optimality-gap.md); ASKI-26 and ASKI-29 completed the support/convention and shipping-regime replay follow-ups, and neither promoted a replacement.

### Edge-blend gating

An optional Sobel-Feldman edge response is blended with the inverted-luma signal via `RenderingOptions.edgeEmphasis` ∈ [0, 1]:

- `0` (default) → pure inverted luma
- `1` → peak-normalized Sobel magnitude when the cell has a nonzero Sobel response
- Intermediate values → linear blend in the per-pixel weight signal

The blend happens before histogram accumulation and normalization. It leaves the base signal unchanged when the Sobel peak is zero, including footprints with an axis smaller than three pixels. Raising `edgeEmphasis` alone therefore does not activate edge detail on every default-sized cell.

### Why inverted luma, not OKLab

The descriptor uses encoded RGB rather than OKLab: dark source pixels produce high weights under the default inverted query. Candidate rasters use the opposite ink-high convention (white glyphs on black). That mismatch is retained behavior, documented in the [candidate-convention study](docs/Research/2026-08-28-aski52-26-candidate-convention.md), not evidence that both sides measure the same physical ink signal.

Matching and color are only partly separate. The brightness shortlist uses the cell's adjusted OKLab L, so `brightness`, `contrast`, and color sampling can change glyph selection as well as output color. The shape-distance stage then compares the separate descriptors; palette matching resolves display color independently of that distance.

### Why log-polar geometry

The descriptor groups mass by distance and angle from the cell center. Twelve angular bins give 30° sectors; the five radial bins divide the admitted disc on a logarithmic scale. This provides a radial/angular description, not the positional descriptor of the published tiled construction. Two measured caveats belong next to that geometry. First, at the default `oversample` only 3 of the 12 angular bins are reachable per cell (see the note above), so the 30° decomposition is a property of the geometry rather than of what the shipping configuration resolves. Second, `maxRadius` inscribes the sampling disc in the cell's **shorter** axis, which covers ~79% of a square glyph raster but only ~39% of a 1:2 source cell, excluding the top and bottom quarters of every cell. Xu, Zhang and Wong (SIGGRAPH 2010), cited below as the 60-bin source, tile *N* isotropic log-polar windows across a non-square cell precisely to avoid this; Aski uses *N* = 1. The bin count matches the published baseline; the sampling does not. The [ASKI-52/26 convention study](docs/Research/2026-08-28-aski52-26-candidate-convention.md) records the completed comparison and decision; it did not promote a replacement.

### Matching: brightness top-K prefilter + squared L2

For each cell of the source image:

1. Compute the 60D descriptor `q`.
2. Filter the character-set bank to a top-`K` shortlist by ascending `|candidateBrightness − adjustedL|`, where `K = 12 + round(density × 24)` and `density` is clamped to [0, 1] (non-finite values resolve to zero). `candidateBrightness` is the bank's normalized ink density, not a stored OKLab coordinate. The pool is capped at the number of available glyphs.
3. Compute squared L2 distance `‖q − c‖²` across the 60D lanes for each `c` in the shortlist.
4. Pick the minimum-distance candidate. Ties break first on `|candidateBrightness − adjustedL|`, then on candidate index (stable ordering).

The two-stage structure restricts the shape comparison to a brightness band. This describes the ranking contract; it does not establish that the nearest descriptor is the best rendered glyph. [Selection-ceiling research](docs/Research/2026-08-19-selection-optimality-gap.md) measures that distinction against rendered output.

Steps 1–4 assume the cell footprint can carry a descriptor at all. When either cell axis is a single pixel — reachable at `oversample: 1` on most source aspects — the radius gate admits nothing and `q` is all zeros. That is not a tie: `‖0 − c‖²` is `c`'s own squared norm, and a zero-descriptor space in the bank wins over nonzero candidates wherever the prefilter admits it and the shape term describes only the candidates rather than the cell. The converter detects this from the resolved pitch alone (`min(cellWidth, cellHeight) > 1`, evaluated once per conversion) and skips steps 1, 3 and 4, ranking on `brightnessValues` (normalized glyph density). The result is a brightness ramp: degraded, but the cell's real tone rather than a blank grid. Fixed in ASKI-25.

### Color pipeline

The color descriptor and palette distance are separate from the 60D shape distance, while adjusted OKLab L also supplies the glyph prefilter. The image's per-cell average color (encoded-average for `ColorSamplingPolicy.encodedAverageLegacy`, linear-light-average for `.linearLightAverage`) is mapped into OKLab via fused linear-sRGB → LMS → cube-rooted LMS' → OKLab matrices (`FUSED_LINEAR_SRGB_TO_LMS`, `LMS_PRIME_TO_OKLAB` in `ColorConversion.swift`). The Display P3 path uses the parallel `FUSED_LINEAR_P3_TO_LMS`. The implementation uses `cbrt` for the LMS cube roots. Palette matching against the active palette defaults to OKLab Euclidean distance;
`PaletteMatchingPolicy` exposes HyAB and two Helmlab alternatives as experimental opt-ins; see [Palette Matching](Sources/Aski/Aski.docc/PaletteMatching.md) for their evidence and limits. The default is `.linearLightAverage` sampling and `.oklabEuclidean` matching.

## References

1. Ottosson, B. (2020). *A perceptual color space for image processing*. https://bottosson.github.io/posts/oklab/
2. Ottosson, B. (2021). *Gamut clipping in OKLab and OKLCh*. https://bottosson.github.io/posts/gamutclipping/
3. Belongie, S., Malik, J., & Puzicha, J. (2002). *Shape matching and object recognition using shape contexts*. IEEE Transactions on Pattern Analysis and Machine Intelligence.
4. Xu, X., Zhang, L., & Wong, T.-T. (2010). *Structure-based ASCII art*. ACM Transactions on Graphics. https://cse.cuhk.edu.hk/~ttwong/papers/asciiart/asciiart.html
5. CSS Color 4 (W3C editor's draft). https://drafts.csswg.org/css-color-4/
6. ColorAide reference implementation. https://github.com/facelessuser/coloraide
7. Color.js reference implementation. https://github.com/color-js/color.js
8. ITU-R Recommendation BT.601. *Studio encoding parameters of digital television for standard 4:3 and wide-screen 16:9 aspect ratios*.
9. WWDC 2018 Session 219. *Image and Graphics Best Practices*. Apple Inc.

---

*Aski is Apache-2.0-licensed. See `LICENSE`. This file is part of the package source for reading convenience and version control; it is not API documentation.*
