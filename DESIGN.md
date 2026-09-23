# Aski Design Notes

## Overview

Aski converts images to ASCII art via a 60-dimensional log-polar histogram of per-pixel inverted-luma weights, matched against a character-set bank by brightness-prefiltered squared L2 distance. This file documents the technical lineage of the descriptor. The package is Apache-2.0-licensed; this file is informational.

## Algorithm Overview

### The 60D log-polar descriptor

Per-pixel weight is inverted ITU-R BT.601 luma over encoded sRGB:

```
w(p) = 1 - (0.299·R + 0.587·G + 0.114·B)
```

Weights are accumulated into a histogram laid out in log-polar geometry: **5 log-spaced radial bins × 12 uniform angular bins = 60 bins**, then L1-normalized. The layout follows the canonical Shape Context construction of Belongie, Malik, and Puzicha (2002), adapted to dense per-cell histograms rather than sparse point sets.

> **How many of those 60 bins are actually reachable depends on `oversample`, and at the default it is very few.** The converter thumbnails to `max(columns, rows) × oversample` and takes an integer cell pitch, so the cell ends up exactly `oversample` pixels wide. At the default `oversample: 2` the descriptor's radius gate admits 2–3 pixels of 8 and reaches **2–3 of the 60 bins** — after L1 normalization, a 1-to-2 parameter statistic rather than a shape basis. Glyph reference descriptors are built on a square 64×64 raster and average 27.9 non-zero bins, so query and candidate do not share a support. Raising `oversample` lifts reachable support (48 of 60 at `32`) but does **not** measurably improve pick quality — it is a null, not a fix. This is a property of the sampling regime, not of the descriptor design described here. Measured in `docs/Research/2026-08-19-sampling-lattice-support-collapse.md` and `docs/Research/2026-08-19-selection-optimality-gap.md`; ASKI-26 and ASKI-29 completed the support/convention and shipping-regime replay follow-ups, and neither promoted a replacement.

### Edge-blend gating

An optional Sobel-Feldman edge response is blended with the inverted-luma signal via `RenderingOptions.edgeEmphasis` ∈ [0, 1]:

- `0` (default) → pure inverted luma
- `1` → pure Sobel magnitude
- Intermediate values → linear blend in the per-pixel weight signal

The blend happens at weight-accumulation time, before histogram normalization.

### Why inverted luma, not OKLab

The shape pass is intentionally decoupled from the OKLab color pipeline. The shape signal is "ink density" over encoded sRGB — dark source pixels produce high weights — computed independently of the color resolution step. Coupling them would entangle two orthogonal concerns: glyph selection (a structural match against the character-set bank) and ink color (a separate OKLab nearest-neighbor against the active palette).

### Why log-polar geometry

Center-weighted radial sampling matches glyph structure: most of a glyph's discriminating mass lives near the center, with stroke endpoints reaching toward the periphery. Twelve angular bins decompose stroke orientation at 30° resolution, which is enough to distinguish horizontals, verticals, diagonals, and their negations without overfitting to per-glyph orientation noise.

That is the design rationale. Two measured caveats belong next to it. First, at the default `oversample` only 3 of the 12 angular bins are reachable per cell (see the note above), so the 30° decomposition is a property of the geometry rather than of what the shipping configuration resolves. Second, `maxRadius` inscribes the sampling disc in the cell's **shorter** axis, which covers ~79% of a square glyph raster but only ~39% of a 1:2 source cell, excluding the top and bottom quarters of every cell. Xu, Zhang and Wong (SIGGRAPH 2010), cited below as the 60-bin source, tile *N* isotropic log-polar windows across a non-square cell precisely to avoid this; Aski uses *N* = 1. The bin count matches the published baseline; the sampling does not. Tracked as ASKI-26.

### Matching: brightness top-K prefilter + squared L2

For each cell of the source image:

1. Compute the 60D descriptor `q`.
2. Filter the character-set bank to a top-`K` shortlist by ascending `|candidate.L − query.L|`, where `K = 12 + round(density × 24)` and `density` is the user-supplied character-density parameter ∈ [0, 1].
3. Compute squared L2 distance `‖q − c‖²` across the 60D lanes for each `c` in the shortlist.
4. Pick the minimum-distance candidate. Ties break first on `|candidate.L − query.L|`, then on candidate index (stable ordering).

The two-stage structure (brightness prefilter, then L2) decouples luminance resolution from shape resolution: characters are picked for the right brightness first, then refined by shape within that brightness band.

Steps 1–4 assume the cell footprint can carry a descriptor at all. When either cell axis is a single pixel — reachable at `oversample: 1` on most source aspects — the radius gate admits nothing and `q` is all zeros. That is not a tie: `‖0 − c‖²` is `c`'s own squared norm, and the space glyph is the bank's only zero-norm entry, so it wins outright wherever the prefilter admits it and the shape term describes only the candidates rather than the cell. The converter detects this from the resolved pitch alone (`min(cellWidth, cellHeight) > 1`, evaluated once per conversion) and skips steps 1, 3 and 4, ranking on raw glyph brightness. The result is a brightness ramp: degraded, but the cell's real tone rather than a blank grid. Fixed in ASKI-25.

### Color pipeline

Independent of the shape pipeline. The image's per-cell average color (encoded-average for `ColorSamplingPolicy.encodedAverageLegacy`, linear-light-average for `.linearLightAverage`) is mapped into OKLab via fused linear-sRGB → LMS → cube-rooted LMS' → OKLab matrices (`FUSED_LINEAR_SRGB_TO_LMS`, `LMS_PRIME_TO_OKLAB` in `ColorConversion.swift`). The Display P3 path uses the parallel `FUSED_LINEAR_P3_TO_LMS`. Cube roots use `cbrt` (Swift stdlib, IEEE-754-correct) — not `sign · pow(·, 1/3)`. Palette matching against the active palette defaults to OKLab Euclidean distance;
`PaletteMatchingPolicy` (HyAB and two Helmlab policies) can override it — see the
Palette Matching article in the DocC catalog.

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
