# ``Aski``

Convert images to ASCII art with perceptually aware color and shape matching.

## Overview

Aski converts a `CGImage` into an ``ASCIIGrid``. The default pipeline uses:

1. ImageIO thumbnail decoding.
2. OKLAB color conversion with fused matrix transforms.
3. 60D log-polar shape-context character matching.
4. Ray Trace gamut mapping for display output.

Use ``DefaultConverter`` for the standard full-color pipeline, or configure ``ASCIIConverter`` with a custom character set, palette, and optional ``MaskOptions``.

```swift
import Aski

let grid = DefaultConverter().convert(image, columns: 80)
let text = grid.renderPlainText()
```

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

- ``AnimatedASCIIGrid``
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
