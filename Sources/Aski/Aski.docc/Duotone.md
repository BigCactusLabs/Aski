# A Duotone Recipe

Combine a fixed two-color palette with block glyphs and a dark canvas.

## Convert and render

This example uses the ordinary library APIs. Copy it into your app and adjust the
colors, character set, or rendering parameters for your own look.

```swift
import Aski
import CoreGraphics
import simd

struct DuotonePalette: ASCIIPalette {
    let content: PaletteContent
}

func renderDuotone(_ image: CGImage) -> CGImage {
    let ink = PaletteColor(
        SIMD3<Float>(Float(0xE8) / 255, Float(0xE2) / 255, Float(0xD2) / 255),
        colorSpace: .sRGB)
    let accent = PaletteColor(
        SIMD3<Float>(Float(0x5E) / 255, Float(0x1B) / 255, Float(0x18) / 255),
        colorSpace: .displayP3)
    let converter = ASCIIConverter(
        characterSet: StandardCharacterSet.blocks,
        palette: DuotonePalette(content: .fixed([ink, accent])),
        algorithm: .logPolar,
        tileShape: .wide,
        options: RenderingOptions(brightness: 0, contrast: 0.15),
        colorSpace: .displayP3,
        oversample: 2)
    let grid = converter.convert(image, columns: 76)
    return grid.renderImage(
        font: .courierPrime(size: 14),
        backgroundColor: CGColor(
            srgbRed: CGFloat(0x16) / 255, green: CGFloat(0x16) / 255,
            blue: CGFloat(0x16) / 255, alpha: 1),
        scale: 2,
        preserveSourceAspect: true)
}
```

The palette declares each color's source space. The grid and image use Display P3;
the canvas is an explicitly tagged sRGB color. Keep those declarations when
reproducing this recipe. See <doc:PaletteMatching> and <doc:Rendering>.

For text or animation, keep the converter and grid instead of returning only the
image. Sample frames with `grid(at:)` or `materialize(frameRate:)`, then render each
grid with the same font, canvas, scale, and `preserveSourceAspect: true`. The
`AnimatedASCIIGrid.renderImage(at:...)` convenience has no `preserveSourceAspect`
parameter and does not reproduce this recipe's aspect-faithful geometry. See
<doc:Animation>.

## Output expectations

These settings describe one look, not universal best settings. Under this recipe,
opaque near-white regions with all-zero shape queries leave the dark canvas visible.
The current matcher's limitations are described in <doc:Algorithms>.

The bundled font removes one source of variation; it does not guarantee identical
Core Text or GPU output on every OS or device. The recorded regression baseline is
macOS 27 / Xcode 27, with host-dependent raster differences documented in the
[contributor guide](https://github.com/BigCactusLabs/Aski/blob/main/CONTRIBUTING.md#toolchain-and-snapshot-baseline).

For existing integrations using the removed named preset, see <doc:Migrating-to-A1>.
