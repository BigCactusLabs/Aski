# ``Aski``

Pictures, reconsidered as type: convert images into character grids and render them your way.

## Overview

Aski is a Swift library for Apple platforms, with a macOS `aski` command-line client.
It converts a `CGImage` into an ``ASCIIGrid``; the same grid can produce plain text,
colored attributed text, or a rendered image. Masks, animation, effects, and video
build on that engine. ``TileGridConverter`` offers pixel-art, brick, and mosaic output
without character matching.

Start with <doc:GettingStarted> for the library or <doc:CommandLine> for file-based
workflows. The package requires Swift 6.3+ and targets iOS 18+, macOS 15+, and visionOS 2+.

```swift
import Aski
import CoreGraphics

func characterText(from image: CGImage) -> String {
    DefaultConverter().convert(image, columns: 80).renderPlainText()
}
```

``DefaultConverter`` selects the standard full-color pipeline. Configure
``ASCIIConverter`` for another character set, palette, algorithm, or ``MaskOptions``.
The default color path uses linear-light sampling, OKLab Euclidean palette matching,
and Ray Trace gamut mapping. Glyph selection is a separate brightness-prefiltered
60D log-polar pass; <doc:Algorithms> documents its sampling and quality limitations.

Aski is public and pre-1.0, not API-frozen. Ordinary library features, experimental
policies, and research SPI have different readiness levels. In particular,
<doc:HDRRendering> requires `@_spi(AskiResearch)` and is not ordinary public API.

## Topics

### Converting Images

- ``ASCIIConverter``
- ``DefaultConverter``
- ``VesperPreset``

### Output

- ``ASCIIGrid``
- ``AnimatedASCIIGrid``
- ``ASCIICell``
- ``RenderColorSpace``

### Animating Output

- ``AnimationOptions``
- ``CyclingOptions``
- ``EntrancePattern``
- ``OngoingPattern``
- ``WaveDirection``
- ``AnimationEasing``
- ``AnimationAnchor``

### Mask Input

- ``MaskOptions``
- ``MaskFallback``

### Character Sets

- ``ASCIICharacterSet``
- ``StandardCharacterSet``
- ``RasterizedCharacterSet``

### Palettes

- ``ASCIIPalette``
- ``PaletteContent``
- ``PaletteColor``
- ``PaletteColorSpace``
- ``BuiltInPalette``

### Color Pipeline Policies

- ``ColorSamplingPolicy``
- ``PaletteMatchingPolicy``
- ``GamutMappingPolicy``
- ``RenderCompositionPolicy``

### Tile-grid Output

- ``TileGridConverter``
- ``TileGrid``
- ``TileCell``
- ``TileGridMode``
- ``TileCellShape``
- ``TilePalette``

### Video & GIF

- ``convertVideo(at:to:using:columns:font:backgroundColor:scale:export:targetFPS:pattern:effects:)``
- ``convertGIF(at:to:using:columns:font:backgroundColor:scale:loopCount:targetFPS:maximumFrameCount:)``
- ``ASCIIVideoDecoder``
- ``ASCIIVideoEncoder``
- ``ASCIIVideoFrame``
- ``RenderedVideoFrame``
- ``ASCIIGIFDecoder``
- ``ASCIIGIFEncoder``
- ``ASCIIGIFFrame``
- ``RenderedGIFFrame``
- ``VideoExportOptions``
- ``VideoCodec``
- ``GIFContainerInfo``
- ``GIFEncodeReport``
- ``ResampleReport``

### Fonts

- ``ASCIIFont``

### Articles

- <doc:GettingStarted>
- <doc:CommandLine>
- <doc:Rendering>
- <doc:Vesper>
- <doc:HDRRendering>
- <doc:Masking>
- <doc:Animation>
- <doc:Algorithms>
- <doc:CharacterSets>
- <doc:Effects>
- <doc:Video>
- <doc:Migrating-to-A1>
- <doc:Tiles>
- <doc:PaletteMatching>
