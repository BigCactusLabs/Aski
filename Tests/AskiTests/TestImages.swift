import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestImages {
    /// Horizontal gradient, width x height sRGB, no transparent pixels.
    static func horizontalGradient(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        for x in 0..<width {
            let t = CGFloat(x) / CGFloat(width - 1)
            context.setFillColor(red: t, green: t, blue: t, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }

        return context.makeImage()!
    }

    /// A deterministic portrait-proxy: a DARK radial figure (dark centre → mid
    /// edge) carrying coarse concentric rings so every cell holds coherent edge
    /// structure. Dark-dominant on purpose: the `.logPolar` descriptor histograms
    /// *inverted* luma and gates out near-white pixels, so bright-centred
    /// synthetics collapse every cell to the space glyph. The tonal span drives
    /// the duotone palette end-to-end (dark figure → accent, mid ground → ink).
    /// Used by the ASTSK-47 Vesper preset golden so drift in any frozen knob is
    /// visible.
    static func structuredPortraitProxy(width: Int, height: Int) -> CGImage {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let cx = Double(width - 1) / 2
        let cy = Double(height - 1) / 2
        let maxR = min(cx, cy)
        let twoPi = 2 * Double.pi
        for y in 0..<height {
            for x in 0..<width {
                let dx = (Double(x) - cx) / maxR
                let dy = (Double(y) - cy) / maxR
                let r = (dx * dx + dy * dy).squareRoot()
                let envelope = max(0, 1 - r)  // 1 at centre → 0 at edge
                // Coherent curved edges logPolar responds to, COARSE enough (period
                // ~34 px) to survive the converter's decimation to a ~76-col grid as
                // multi-cell structure — high-frequency detail just aliases to flat.
                let rPixels = ((Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy))
                    .squareRoot()
                let rings = 0.22 * sin(rPixels * (twoPi / 34))
                // DARK-dominant: the logPolar descriptor histograms *inverted* luma
                // and skips pixels below a 0.05 darkness gate, so a bright-centred
                // fixture collapses every cell to the space glyph. A dark figure on
                // a mid ground keeps darkness mass in every cell while still spanning
                // enough tonal range to engage both duotone colors.
                let lum = max(0, min(1, (1 - envelope) * 0.45 + 0.06 + rings))
                let value = UInt8((lum * 255).rounded())
                let offset = (y * width + x) * 4
                buffer[offset + 0] = value
                buffer[offset + 1] = value
                buffer[offset + 2] = value
                buffer[offset + 3] = 255
            }
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = CGDataProvider(data: Data(buffer) as CFData)!
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    /// Near-black everywhere except a white band from `bandTop` to the bottom
    /// edge. Sized so the band occupies exactly the bottom grid row's share of
    /// source height, it is invisible to any sampler that drops the bottom
    /// remainder — which is what the ASKI-65 regression asserts against.
    static func bottomBandProxy(width: Int, height: Int, bandTop: Int) -> CGImage {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let level: UInt8 = y >= bandTop ? 255 : 8
            for x in 0..<width {
                let offset = (y * width + x) * 4
                buffer[offset] = level
                buffer[offset + 1] = level
                buffer[offset + 2] = level
                buffer[offset + 3] = 255
            }
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = CGDataProvider(data: Data(buffer) as CFData)!
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    static func solidDisplayP3Red(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        let red = CGColor(colorSpace: colorSpace, components: [1, 0, 0, 1])!
        context.setFillColor(red)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()!
    }

    static func verticalSplitMask(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!

        let split = width / 2
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: split, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: split, y: 0, width: width - split, height: height))

        return context.makeImage()!
    }

    /// Encode a CGImage as JPEG data for use with ImageIO.
    static func jpegData(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func jpegSource(_ image: CGImage) -> CGImageSource {
        let data = jpegData(image)
        return CGImageSourceCreateWithData(data as CFData, nil)!
    }

    /// Draw `image` into a fixed device-RGB 8-bit premultiplied-last context and
    /// return the raw bytes, so a byte comparison is independent of the source
    /// image's tagged colour space. Shared by `ImageRendererGoldenTests` (G0
    /// raw-byte golden) and `EffectsCompatTests` (legacy/new byte-identity).
    /// (The lab's `HDRArtifacts.raster8` is the same idea but lives in a separate
    /// target — not worth `@_spi`-exposing for a research lab.)
    static func deviceRGBBytes(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }
}
