# Getting Started

Load an image, turn it into a character grid, and choose how that grid leaves the workshop.

## Add the package

Aski requires Swift 6.3+ and targets iOS 18+, macOS 15+, and visionOS 2+. Add the
`Aski` library product to your target after adding the Swift package dependency.
The repository [README](https://github.com/BigCactusLabs/Aski/blob/main/README.md#use-in-swift)
contains the version-pinning and local-checkout instructions.

For file-to-file conversion without an app, start with <doc:CommandLine> instead.

## Load a CGImage

Already have a `CGImage`? Use it directly. For a small local image, ImageIO provides a
minimal loading path:

```swift
import Aski
import CoreGraphics
import Foundation
import ImageIO

enum ImageLoadingError: Error {
    case unreadableImage
}

func loadImage(at url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw ImageLoadingError.unreadableImage
    }
    return image
}

let image = try loadImage(at: URL(fileURLWithPath: "photo.jpg"))
```

Replace `photo.jpg` with a readable path. This example loads a full image; for large
inputs, use ImageIO thumbnail decoding before passing the image to Aski. The CLI does
that through its shared input loader. Conversion is synchronous, so schedule expensive
work away from your app's UI thread.

## Convert once

``DefaultConverter`` uses the standard printable-ASCII set and source-color output:

```swift
let grid = DefaultConverter().convert(image, columns: 80)
```

`columns` is the number of character cells across the image, not the eventual PNG
width. The result is an ``ASCIIGrid`` that can feed several renderers without another
conversion.

## Choose an output

Plain text contains glyphs and newlines, not color:

```swift
print(grid.renderPlainText())
```

Attributed text retains per-cell foreground colors for a text view or SwiftUI `Text`:

```swift
let attributed = grid.renderAttributedString()
```

Use a monospaced presentation and avoid line wrapping when displaying a character grid.
For raster output:

```swift
let rendered = grid.renderImage(
    font: .system(size: 12),
    backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    scale: 2,
    preserveSourceAspect: true
)
```

`rendered` is a `CGImage`, not a written PNG file. Encode it with your app's image-output
path, or use `aski render --render-png` for a file. `preserveSourceAspect: true` matches
the CLI's aspect choice; the library defaults to the historical glyph-cell aspect.

For a specified pixel width, use the `targetPixelWidth:` overload instead of `scale:`.
See <doc:Rendering> for bounds, fallback behavior, masking, and color-space details.

## Change the alphabet and palette

``ASCIIConverter`` exposes the character set, palette, algorithm, and rendering policies.
Spell out the concrete set and palette types so Swift can infer the converter's generics:

```swift
let converter = ASCIIConverter(
    characterSet: StandardCharacterSet.blocks,
    palette: BuiltInPalette.ansi16,
    algorithm: .dotMatrix,
    tileShape: .wide,
    colorSpace: .sRGB
)

let blockGrid = converter.convert(image, columns: 120)
```

This selects a dithered block treatment. The default algorithm is `.logPolar`; neither
choice is a promise of the best result for every source. See <doc:Algorithms> and
<doc:CharacterSets> for pairings, controls, and measured limitations.

The current default color policies are `linearLightAverage`, `oklabEuclidean`, and
`rayTrace`. `adaptiveL0` remains available for a legacy gamut comparison; experimental
palette metrics are labeled in <doc:PaletteMatching>. You do not need to choose a
research policy to use the package.

## Add a mask

Given another `CGImage` named `maskImage`, white mask pixels keep cells visible and
black pixels reveal the fallback:

```swift
let mask = MaskOptions(
    image: maskImage,
    fallback: .transparent,
    softEdges: true
)

let maskedGrid = DefaultConverter().convert(image, columns: 80, mask: mask)
```

A transparent mask fallback reveals the renderer's background; it does not itself make
an opaque render background transparent. See <doc:Masking> for soft edges, image
fallbacks, active-region grounds, and CLI equivalents.

## Make a custom character set

Use a font that contains your chosen glyphs, and render with the same monospaced family:

```swift
import CoreText

let font = CTFontCreateWithName("Menlo" as CFString, 32, nil)
let customSet = RasterizedCharacterSet(
    characters: Array(" .:-=+*#%@"),
    font: font
)

let customConverter = ASCIIConverter(
    characterSet: customSet,
    palette: BuiltInPalette.monochrome
)
```

For one complete, fixed visual recipe rather than a custom set, see <doc:Vesper>.
For movement and finishing treatments, continue to <doc:Animation> and <doc:Effects>.
