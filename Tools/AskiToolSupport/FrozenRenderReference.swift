import Aski
import CoreGraphics
import simd

/// The fixed ASTSK-47 rendering recipe for research comparisons and raster regression tests.
package enum FrozenRenderReference {
    package static let columns = 76
    package static let ink = PaletteColor(
        SIMD3<Float>(Float(0xE8) / 255, Float(0xE2) / 255, Float(0xD2) / 255),  // #E8E2D2 bone
        colorSpace: .sRGB
    )
    package static let accent = PaletteColor(
        SIMD3<Float>(Float(0x5E) / 255, Float(0x1B) / 255, Float(0x18) / 255),  // #5E1B18 oxblood
        colorSpace: .displayP3
    )
    package static let contrast: Float = 0.15
    package static let colorSpace: RenderColorSpace = .displayP3
    package static let oversample = 2
    package static let fontSize: CGFloat = 14
    package static let scale: CGFloat = 2
    package static let backgroundColor = CGColor(
        srgbRed: CGFloat(0x16) / 255, green: CGFloat(0x16) / 255, blue: CGFloat(0x16) / 255,
        alpha: 1
    )

    package struct Palette: ASCIIPalette {
        package let content = PaletteContent.fixed([ink, accent])
    }

    package static var font: ASCIIFont { .courierPrime(size: fontSize) }

    package static func makeConverter() -> ASCIIConverter<StandardCharacterSet, Palette> {
        ASCIIConverter(
            characterSet: .blocks,
            palette: Palette(),
            algorithm: .logPolar,
            tileShape: .wide,
            options: RenderingOptions(brightness: 0, contrast: contrast),
            colorSpace: colorSpace,
            oversample: oversample
        )
    }

    package static func render(_ image: CGImage) -> CGImage {
        makeConverter()
            .convert(image, columns: columns)
            .renderImage(
                font: font,
                backgroundColor: backgroundColor,
                scale: scale,
                preserveSourceAspect: true
            )
    }
}
