# Algorithms

How Aski matches characters to image cells.

## Overview

Aski ships two character-matching algorithms, each suited to a different
visual style. Set the algorithm on ``ASCIIConverter`` via the ``ASCIIAlgorithm``
parameter. Spell out `StandardCharacterSet` / `BuiltInPalette` explicitly —
`ASCIIConverter` is generic over `C` and `P`, so leading-dot member references
like `.lines` can't be inferred at the init call site:

```swift
let converter = ASCIIConverter(
    characterSet: StandardCharacterSet.standard,
    palette: BuiltInPalette.fullColor,
    algorithm: .logPolar
)
```

## Algorithms

- ``ASCIIAlgorithm/logPolar`` — 60D log-polar shape matching. The default;
  produces general-purpose ASCII art.
- ``ASCIIAlgorithm/dotMatrix`` — Brightness-based matching with
  Floyd–Steinberg dithering. Produces halftone-style output.

> Note: `logPolar` conversions walk the cell grid in parallel across rows once
> the grid is large enough (a fixed cell-count threshold),
> which speeds up larger outputs; the result is identical to a serial walk.
> `dotMatrix` always walks serially because its error diffusion carries state
> from one cell to the next. Output is deterministic for every algorithm
> regardless of grid size or core count.

## Recommended pairings

| Algorithm | Recommended character sets |
|---|---|
| `logPolar` | `standard`, `minimal`, `mixed`, `dots`, `braille` |
| `dotMatrix` | `minimal`, `blocks`, `dots`, `braille` |

Other combinations work but may produce mediocre output.

## Knob relevance

| Knob | logPolar | dotMatrix |
|---|:-:|:-:|
| `coverage` | – | ✓ FS dither strength |
| `density` | ✓ widens top-K | – |
| `edgeEmphasis` | ✓ Sobel-magnitude weighting | – |
| `brightness` | ✓ | ✓ |
| `contrast` | ✓ | ✓ |

``RenderingOptions`` also carries the research-only `shapeQueryPolarity`, which
selects the ink axis of the `logPolar` shape query and defaults to `.inverted`,
the shipped byte-identical behavior. See `docs/Research/` for experiment
verdicts and retained replay evidence.

Out-of-range values clamp silently.

## Oversampling

``ASCIIConverter`` accepts an `oversample` init parameter (default `2`) that
controls how aggressively the input is downsampled before per-cell feature
extraction. The converter thumbnails the source to roughly
`max(columns, rows) * oversample` pixels, then carves it into cells.

The cell pitch is a floored integer quotient, so it stays uniform across the
grid, and the thumbnail is then drawn into a *sampling lattice* of exactly
`columns * cellWidth × rows * cellHeight` before any cell is read. Sampling is
anchored at the origin and walks whole cells, so the lattice is tiled exactly:
every source row and column lands inside some cell and nothing is dropped off
the bottom or right edge. Folding the remainder in costs a rescale of at most
one cell pitch per axis, applied once at decode. This is a test-pinned contract;
`SamplingGeometry.droppedX`/`droppedY` report zero.

Earlier versions sampled the thumbnail at its own decoded size, which left a
bottom/right remainder of `thumbnailWidth % columns` by `thumbnailHeight % rows`
unread — bounded by the *grid* dimension rather than the cell pitch, so it spanned
several cells, about 10% of image height at `columns: 80`, `oversample: 2`. Because
the renderer still drew the grid over the full source aspect, the result read as a
vertically stretched image that drifted downward.

`oversample: 1` is supported but degraded. It drives the cell pitch to a single
pixel on one axis for most source aspects, which leaves the log-polar
descriptor with no reachable bins at all (see below), so those cells fall back
to a tone-only pick and the output reads as a brightness ramp rather than a
shape match. Use `1` only when decode cost dominates and shape fidelity does
not matter.

At `oversample = 2` the typical cell is `2 × N` pixels, which is below the
`3 × 3` minimum kernel size required for the Sobel-based `edgeEmphasis` knob
to fire. Callers using `algorithm: .logPolar` with non-zero
``RenderingOptions/edgeEmphasis`` should set `oversample: 4` (or higher) to
ensure the Sobel path is exercised. Other algorithms and zero-knob `logPolar`
are unaffected *in the sense that no code path is gated off* — but see below.

Default stays `2` to preserve bit-identical pre-A1 default output.

### Oversampling is not a quality knob

`oversample` also determines how much of the 60-bin log-polar descriptor is
reachable at all, and the effect is severe. The cell pitch is an integer
quotient of the thumbnail size, so the cell ends up exactly `oversample` pixels
wide — measured across source aspect ratios from 3:1 through 1:3, so this is not
a landscape-only quirk. At the default `2` the descriptor's radius gate admits
2–3 pixels of 8 and reaches **2–3 of the 60 bins**; at `oversample: 32` it
reaches 48.

It is tempting to read that as "raise `oversample` for better shape matching."
**Measurement says otherwise.** Over an exhaustive per-cell census on held-out
naturals, lifting reachable support from 3 bins to 48 moves the distance between
the production pick and the loss-optimal pick by 0.50 points on the `blocks`
charset and 0.03 on `standard`, and leaves the mean rank of the production pick
effectively unchanged (3.75 of 8 at 3 bins, 3.74 of 8 at 48). A ranker that
does not improve when handed sixteen times the information is not
information-limited.

So raise `oversample` when you need the Sobel-gated knob above, or when a
downstream stage wants a larger working image — not as a quality lever for
zero-knob `logPolar`, where it costs decode time and buys nothing measurable.
Evidence: `docs/Research/2026-08-19-sampling-lattice-support-collapse.md` and
`docs/Research/2026-08-19-selection-optimality-gap.md` in the repository.
