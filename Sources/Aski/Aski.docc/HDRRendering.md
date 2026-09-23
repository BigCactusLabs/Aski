# HDR and Emissive Rendering

Render a grid with per-cell emission into an extended-range image for gain-map HDR output.

## Overview

Aski's source material is SDR, so its extended-range signal is **authored emission** — "bloom-above-white", where bright glyphs glow past paper-white — not photographic highlight recovery. The path is research-status: every symbol below is gated behind `@_spi(AskiResearch)` and requires

```swift
@_spi(AskiResearch) import Aski
```

The stable ``ASCIIGrid/renderImage(font:backgroundColor:scale:preserveSourceAspect:)`` path and its [0, 1] clamp are untouched; omitting the SPI import leaves default rendering byte-identical.

## The extended-range render

`ASCIIGrid.renderExtendedRangeImage(font:backgroundColor:scale:preserveSourceAspect:emission:)` renders the grid's SDR display colors with a per-cell emission gain applied in the **linear domain**, into a 16-bit half-float extended-linear context (extended linear sRGB or Display P3, matching the grid's ``RenderColorSpace``), so boosted channels exceed 1.0. It returns `CGImage?` and returns `nil` for every can't-render-faithfully path rather than degrading.

Geometry is shared with `renderImage`: for the same grid, font, scale, and `preserveSourceAspect`, the SDR base and the extended render are pixel-aligned. That alignment is the precondition for gain-map authoring — render the same grid twice (once with each method) and hand both images to Core Image to compute the gain map and write an Adaptive HDR HEIC, whose fallback layer *is* today's SDR render (a built-in no-harm guarantee). The HEIC authoring itself lives outside the package, in the `aski lab hdr` gate runner; the package's deliverable is the pixel-aligned image pair.

Displays apply their own tone mapping; in practice Apple platforms cap rendered headroom at roughly 3 stops, so `maxHeadroom` values beyond ~8× buy nothing.

### Opaque, full-coverage content only

Pixel alignment holds only for opaque cells — a translucent cell composites differently in the extended-linear context than in the 8-bit sRGB-gamma SDR render, and the gain map would encode that mismatch as spurious gain. The method therefore returns `nil` for grids with sub-1 mask coverage, a non-transparent ``MaskFallback``, a positive-alpha ``ASCIIGrid/maskGroundColor``, or any cell with `alpha < 1`. A nil, zero-alpha, or non-finite-alpha ground is an effective no-op and does not by itself reject the render. Mask-fallback, active-ground, and translucent emission are future work.

## Emission modes

`EmissionOptions` selects one of two sources:

- **Brightness curve** (`.brightnessCurve`, the default) — the gain is `1 + k * smoothstep(threshold, 1, cell.brightness)`. Emission keys on `cell.brightness` — the adjusted *source* OKLAB lightness — never on display-color luminance: under a monochrome palette every display color is white while `brightness` still tracks the source, so luminance keying would bloom every cell.
- **Authored** (`.authored(spec)`) — from ASTSK-37. A `GlyphEmissionSpec` maps individual characters to boost values, and the gain is `1 + k * glyphBoost`; `threshold` is ignored, and glyphs absent from the spec do not emit. This makes emission art-directable per glyph instead of brightness-driven.

Both modes clamp the boosted linear channels to `[0, maxHeadroom]` and sanitize NaN/Inf inputs.

Two optional SPI protocols, `EmissivePalette` and `EmissiveCharacterSet`, let a palette or character set vend an authored `GlyphEmissionSpec`. No built-in type conforms; renderers always receive the resolved spec explicitly through `EmissionOptions`, because ``ASCIIGrid`` retains neither its source palette nor its character set.

## Validation

The path shipped opt-in after the ASTSK-10 lab spike passed all four frozen gates (SDR-fallback fidelity, `k = 0` identity round-trip, meaningful content headroom, NaN/Inf-clean float buffer); see `docs/Research/2026-06-16-hdr-emissive-spike.md` in the repository. The HDR lab re-runs those gates as a fail-fast check (`swift run aski lab hdr check`).
