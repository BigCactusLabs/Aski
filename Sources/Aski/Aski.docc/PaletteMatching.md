# Palette Matching

How Aski selects the closest palette entry for each cell.

## Overview

For a fixed palette, Aski selects the nearest entry to each cell's sampled color
using ``PaletteMatchingPolicy`` on ``ASCIIConverter``. The default metric uses
OKLab; the experimental Helmlab metrics transform into their own matching space.
``PaletteContent/passThrough`` bypasses fixed-palette selection.

```swift
let converter = ASCIIConverter(
    characterSet: StandardCharacterSet.standard,
    palette: BuiltInPalette.ansi16,
    paletteMatching: .oklabEuclidean   // default
)
```

## Available metrics

- ``PaletteMatchingPolicy/oklabEuclidean`` — Default. 3D Euclidean
  distance in resolved OKLab; mirrors CSS Color 4 `DeltaEOK`.
- ``PaletteMatchingPolicy/oklabHyAB`` — **Experimental.** City-block
  lightness plus Euclidean chroma: `|ΔL| + √(Δa² + Δb²)`. HyAB-on-OKLab
  is an Aski hypothesis; see the case's doc-comment for the validation
  status, adjacent signals (Helmlab, Color.js OK2), and the 90-day
  re-check anchors.
- ``PaletteMatchingPolicy/helmlabEuclidean`` — **Experimental.** Plain
  Euclidean distance over Helmlab MetricSpace-Lab, without the compressed
  metric's saturation. No Aski palette-quality improvement has been established.
- ``PaletteMatchingPolicy/helmlabCompressed`` — **Experimental.** The
  trained Helmlab Minkowski distance followed by monotonic compression. Values
  bunch near 0.15 for very dissimilar pairs; that is not by itself evidence of
  collapsed winner selection or better rendered output. Opt-in.

## When to consider `oklabHyAB`

Concentrated divergence in chroma-sensitive cells, per the
`palette-match-ablation` evidence: zero divergence on
built-in `ansi16` and `monochrome` palettes; 1 of 15 rows divergent on
synthetic fixtures crafted to make the chroma-vs-lightness trade-off
visible. Adopt only after benchmarking against your application's
palette and source mix; the default ``PaletteMatchingPolicy/oklabEuclidean``
remains the right choice for most callers.

## When to consider the Helmlab metrics

Both Helmlab metrics are experimental opt-ins; the default
``PaletteMatchingPolicy/oklabEuclidean`` remains the right choice for most
callers. The evidence is Aski-internal and **thin**: the `helmlab-reference`
perturbation-recovery oracle (small-ΔE ground truth) ties at 100% across
``PaletteMatchingPolicy/oklabEuclidean``, ``PaletteMatchingPolicy/helmlabEuclidean``,
and ``PaletteMatchingPolicy/helmlabCompressed`` on the built-in palettes — i.e.
**no measured palette-matching win** for either Helmlab variant. The large-ΔE
visual review shows the monotonic compression keeps distinct picks (no selection
collapse) even on saturated primaries. The cross-metric `palette-match-ablation`
probe is a divergence/saturation signal only — its distances are not comparable
across color spaces, so it is not a quality oracle. The [Helmlab evaluation](https://github.com/BigCactusLabs/Aski/blob/main/docs/Research/2026-06-07-helmlab-metricspace-eval.md)
contains the recorded numbers and limits.
