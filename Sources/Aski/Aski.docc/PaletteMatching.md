# Palette Matching

How Aski selects the closest palette entry for each cell.

## Overview

Aski matches each cell's sampled color to the nearest palette entry in
OKLab space. The metric used for "nearest" is configurable via
``PaletteMatchingPolicy`` on ``ASCIIConverter``.

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
  Euclidean distance over Helmlab MetricSpace-Lab. Monotonic at all
  distances, so it ranks distant palette candidates well. Opt-in.
- ``PaletteMatchingPolicy/helmlabCompressed`` — **Experimental.** The
  trained Helmlab Minkowski + monotonic-compression ΔE. Best on small
  color differences; saturates (~0.15) on very dissimilar pairs, so it can
  rank distant candidates poorly on small palettes. Opt-in.

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
across color spaces, so it is not a quality oracle. See the Helmlab MetricSpace
eval research note for the recorded numbers.
