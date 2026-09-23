# HDR and Emissive Rendering

An experimental path for making glyphs glow above SDR white.

## Overview

Aski's source material is SDR, so its extended-range signal is **authored emission** — "bloom-above-white", where bright glyphs glow past paper-white — not photographic highlight recovery. Extended-range rendering and its emission types are research-status, gated behind `@_spi(AskiResearch)`:

```swift
@_spi(AskiResearch) import Aski
```

The public SDR ``ASCIIGrid/renderImage(font:backgroundColor:scale:preserveSourceAspect:)`` path and its [0, 1] clamp are separate. Ordinary conversion and rendering do not enable emission. The SPI is an experimental integration surface, not a stability promise or a feature exposed by `aski render`.

## The extended-range render

`ASCIIGrid.renderExtendedRangeImage(font:backgroundColor:scale:preserveSourceAspect:emission:)` renders the grid's SDR display colors with a per-cell emission gain applied in the **linear domain**, into a 16-bit half-float extended-linear context (extended linear sRGB or Display P3, matching the grid's ``RenderColorSpace``), so boosted channels exceed 1.0. It returns `CGImage?` and returns `nil` for unsupported rendering conditions rather than silently degrading.

Geometry is shared with `renderImage`: for the same grid, font, scale, and `preserveSourceAspect`, the SDR base and the extended render are pixel-aligned. That alignment is the precondition for gain-map authoring — render the same grid twice (once with each method) and hand both images to Core Image to compute the gain map and write an Adaptive HDR HEIC with the SDR render as its fallback layer. HEIC authoring lives outside the library, in the `aski lab hdr` gate runner; the library supplies the pixel-aligned image pair.

`maxHeadroom` limits the authored signal, not the brightness a viewer will necessarily see. Available headroom and tone mapping depend on the display and playback conditions. Validate the exported file on the intended device; a larger gain is not automatically a more useful result.

### Opaque, full-coverage content only

Pixel alignment holds only for opaque cells — a translucent cell composites differently in the extended-linear context than in the 8-bit sRGB-gamma SDR render, and the gain map would encode that mismatch as spurious gain. The method therefore returns `nil` for grids with sub-1 mask coverage, a non-transparent ``MaskFallback``, a positive-alpha ``ASCIIGrid/maskGroundColor``, or any cell with `alpha < 1`. A nil, zero-alpha, or non-finite-alpha ground is an effective no-op and does not by itself reject the render. Mask-fallback, active-ground, and translucent emission are not supported by this path.

## Emission modes

`EmissionOptions` selects one of two sources:

- **Brightness curve** (`.brightnessCurve`, the default) — the gain is `1 + k * smoothstep(threshold, 1, cell.brightness)`. Emission keys on `cell.brightness` — the adjusted *source* OKLab lightness — never on display-color luminance: under a monochrome palette every display color is white while `brightness` still tracks the source, so luminance keying would bloom every cell.
- **Authored** (`.authored(spec)`) — a `GlyphEmissionSpec` maps individual characters to boost values, and the gain is `1 + k * glyphBoost`; `threshold` is ignored, and glyphs absent from the spec do not emit.

Both modes clamp the boosted linear channels to `[0, maxHeadroom]` and sanitize NaN/Inf inputs.

Two optional SPI protocols, `EmissivePalette` and `EmissiveCharacterSet`, let a palette or character set vend an authored `GlyphEmissionSpec`. No built-in type conforms; renderers always receive the resolved spec explicitly through `EmissionOptions`, because ``ASCIIGrid`` retains neither its source palette nor its character set.

## Validation

The original ASTSK-10 lab spike passed four frozen gates: SDR-fallback fidelity, `k = 0` identity round-trip, meaningful content headroom, and a NaN/Inf-clean float buffer. The retained record is `docs/Research/2026-06-16-hdr-emissive-spike.md` in the repository; it is evidence for that experiment, not a universal display-quality claim.

From a macOS checkout, rerun the lab's fail-fast check with an explicit artifact directory:

```bash
xcrun swift run aski lab hdr check --output-dir /tmp/aski-hdr
```

See <doc:CommandLine> for source-checkout setup and <doc:Rendering> for ordinary SDR output.
