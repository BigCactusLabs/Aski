# Getting Started

Convert a `CGImage` into plain text, attributed text, or a rendered image.

## Convert to Plain Text

Use ``DefaultConverter`` when you want the built-in printable ASCII character set and full-color output.

```swift
import Aski

let grid = DefaultConverter().convert(myImage, columns: 80)
print(grid.renderPlainText())
```

## Configure the Converter

Use ``ASCIIConverter`` directly when you want a different built-in character set, palette, tile shape, output color space, or color-pipeline policy.

```swift
let converter = ASCIIConverter(
    characterSet: StandardCharacterSet.blocks,
    palette: BuiltInPalette.ansi16,
    tileShape: .wide,
    colorSpace: .sRGB
)

let grid = converter.convert(myImage, columns: 120)
```

## Compare Color Pipeline Policies

The default color pipeline uses ``ColorSamplingPolicy/linearLightAverage``, ``PaletteMatchingPolicy/oklabEuclidean``, and ``GamutMappingPolicy/rayTrace``. For A/B experiments or legacy comparisons, switch the policy parameters explicitly:

```swift
let rayTraceDefault = ASCIIConverter(
    characterSet: StandardCharacterSet.standard,
    palette: BuiltInPalette.fullColor,
    colorSampling: .linearLightAverage,
    paletteMatching: .oklabEuclidean,
    gamutMapping: .rayTrace
)

let adaptiveL0Legacy = ASCIIConverter(
    characterSet: StandardCharacterSet.standard,
    palette: BuiltInPalette.fullColor,
    colorSampling: .linearLightAverage,
    paletteMatching: .oklabEuclidean,
    gamutMapping: .adaptiveL0
)
```

## Render an Image

Use ``ASCIIGrid/renderImage(font:backgroundColor:scale:preserveSourceAspect:)`` to turn a grid back into a `CGImage`.

```swift
import CoreGraphics

let rendered = grid.renderImage(
    font: .system(size: 12),
    backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    scale: 2
)
```

## Apply a Mask

To restrict output to a source mask, pass ``MaskOptions`` during conversion. White mask pixels keep cells visible; black pixels reveal the fallback.

```swift
let mask = MaskOptions(
    image: maskImage,
    fallback: .transparent,
    softEdges: true
)

let maskedGrid = DefaultConverter().convert(myImage, columns: 80, mask: mask)
```

See <doc:Masking> for coverage sampling, fallback, soft-edge, and invert semantics.

## Build a Custom Character Set

Runtime character sets are font dependent. Pass the same monospace font family that you plan to render with.

```swift
import CoreText

let font = CTFontCreateWithName("Menlo" as CFString, 32, nil)
let customSet = RasterizedCharacterSet(
    characters: Array(" .:-=+*#%@"),
    font: font
)

let converter = ASCIIConverter(
    characterSet: customSet,
    palette: BuiltInPalette.monochrome
)
```
