# Rendering

Turn an ``ASCIIGrid`` into plain text, an attributed string, or a `CGImage`.

## Overview

Conversion and rendering are separate stages: an ``ASCIIConverter`` produces an ``ASCIIGrid``, and the grid renders itself. All three renderers are methods on ``ASCIIGrid``, so one conversion can feed any number of output formats. Each renderer honors the grid's mask state (per-cell `coverage` and the grid's ``MaskFallback``) in a way appropriate to its medium.

## Plain text

``ASCIIGrid/renderPlainText()`` emits a newline-separated `String` — no color, glyphs only.

```swift
let grid = DefaultConverter().convert(image, columns: 80)
print(grid.renderPlainText())
```

Masking degrades to text semantics: a cell with `coverage >= 0.5` prints its character; below that the renderer prints the fallback's text-replacement character, or a space when the fallback has none.

``ASCIIGrid/maskGroundColor`` is raster-only. Plain-text output ignores it and remains identical for grids that differ only by that field.

## Attributed string

``ASCIIGrid/renderAttributedString()`` produces a Foundation `AttributedString` with per-cell foreground colors, suitable for `Text(_:)` in SwiftUI or a text view. Consecutive cells with identical color and alpha are batched into a single attributed run for efficiency. Colors are vended as `UIColor`/`NSColor` in the grid's ``RenderColorSpace`` (sRGB or Display P3).

Masked cells (`coverage < 0.5`) render the fallback character when the fallback is `.character`, with alpha scaled by the cell's inverse coverage; other fallbacks degrade to a space.

Attributed-string output also ignores ``ASCIIGrid/maskGroundColor`` and remains identical for grids that differ only by that field.

## Image

``ASCIIGrid/renderImage(font:backgroundColor:scale:preserveSourceAspect:)`` draws the grid into an 8-bit `CGImage` with Core Text.

```swift
let rendered = grid.renderImage(
    font: .system(size: 12),
    backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    scale: 2   // @2x output
)
```

- `font` is an ``ASCIIFont`` — a monospaced font whose point size sets the glyph cell: cells are `pointSize * 0.6` wide and `pointSize * 1.2` tall by default.
- `preserveSourceAspect: true` makes cells as tall as the `.wide` source-sampling ratio instead, so the rendered image reproduces the source image's aspect ratio. The default `false` keeps the historical 2.0 glyph aspect (all existing PNG snapshot baselines depend on it).
- Braille cells (U+2800–U+28FF) are rasterized programmatically — no braille-capable font needs to be bundled.
- Mask fallbacks draw as an underlay: `.solid`, `.originalImage` (with `stretch`/`fill`/`fit` sizing), and `.character` fallbacks are painted per cell at inverse-coverage alpha before the visible glyphs.

### Exact pixel width

For monochrome monospaced fonts, the effective pixel size is `pointSize × scale` and nothing else; doubling the font size and doubling `scale` are the same operation. This was measured 2026-09-01 on the bundled Courier Prime and on Menlo at six size-times-scale ratios, 0 differing bytes; see the issue #33 research note.

``ASCIIGrid/renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:)`` sets the pixel width directly and derives the scale as `targetPixelWidth / (columns × pointSize × 0.6)`. The height follows the grid's glyph geometry; the width is never rounded.

The target-width path renders at four times the target size with subpixel glyph positioning enabled, then reduces every 4×4 block in linear light into the grid's render colour space. Under the default ``RenderCompositionPolicy/encodedDisplay8Bit`` that is an sRGB-decoded, alpha-premultiplied box average, re-encoded; under ``RenderCompositionPolicy/extendedLinearPerGamut`` the supersampled bitmap is already linear-tagged and is averaged with no transfer conversion. The direct single-pass arm lost the ASKI-63 gate on mean absolute error against an 8× reference and stays reachable only through the research SPI.

Because the public path draws at 4×, `targetPixelWidth` is bound by ``ASCIIGrid/maxTargetPixelWidth`` (a quarter of the renderer's pixel-extent ceiling) and the derived height by the same value. Out-of-range geometry returns the 1×1 fallback image, as the scale renderer does; `aski render --width` validates against the same constant and refuses to write a fallback image or a manifest for one.

Color fonts and fonts with optical-size axes are out of scope for this claim.

The image renderer is what ``VesperPreset/render(_:)`` and the video/GIF round-trip carriers call internally; see <doc:Vesper> and <doc:Video>.

An extended-range (HDR) sibling of `renderImage` exists behind `@_spi(AskiResearch)`; see <doc:HDRRendering>.

## Topics

### Renderers

- ``ASCIIGrid/renderPlainText()``
- ``ASCIIGrid/renderAttributedString()``
- ``ASCIIGrid/renderImage(font:backgroundColor:scale:preserveSourceAspect:)``
- ``ASCIIGrid/renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:)``

### Supporting types

- ``ASCIIFont``
- ``RenderColorSpace``
- ``MaskFallback``
