import CoreGraphics
import Testing
@testable import Aski

@Suite struct ImageRendererTests {
    @Test func rendersImageWithExpectedSize() {
        let cells = (0..<10).map { _ in
            (0..<20).map { _ in cell("X") }
        }
        let grid = ASCIIGrid(cells: cells, colorSpace: .sRGB)

        let image = grid.renderImage(
            font: .system(size: 12),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )

        #expect(image.width == 144)
        #expect(image.height == 144)
    }

    @Test func scaleMultipliesPixelDimensions() {
        let grid = ASCIIGrid(cells: [[cell("X")]], colorSpace: .sRGB)

        let image = grid.renderImage(
            font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 2
        )

        #expect(image.width == 12)
        #expect(image.height == 24)
    }

    @Test func emptyGridRendersOnePixelImage() {
        let grid = ASCIIGrid(cells: [], colorSpace: .sRGB)

        let image = grid.renderImage(
            font: .system(size: 12),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )

        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    @Test func drawsCellForegroundColor() {
        let grid = ASCIIGrid(
            cells: [[cell("█", displayColor: .init(1, 0, 0))]],
            colorSpace: .sRGB
        )

        let image = grid.renderImage(
            font: .system(size: 20),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )

        let pixels = rgbaPixels(from: image)
        let hasRedPixel = pixels.contains { pixel in
            pixel.red > 128 && pixel.green < 64 && pixel.blue < 64
        }
        #expect(hasRedPixel)
    }

    @Test func brailleCellMatchesBrailleRasterizerDirectOutput() {
        // Choose a multi-dot codepoint so both the test and a CTLine fallback
        // would produce non-trivial output — but with distinguishable pixel
        // distributions.
        let codepoint: UInt32 = 0x281E  // bits 1, 2, 3, 4 set
        let fontSize: CGFloat = 32

        let cells = [
            [
                ASCIICell(
                    character: Character(UnicodeScalar(codepoint)!),
                    displayColor: SIMD3(1, 1, 1),
                    alpha: 1,
                    brightness: 1
                )
            ]
        ]
        let grid = ASCIIGrid(cells: cells, colorSpace: .sRGB)
        let rendered = grid.renderImage(
            font: .courierPrime(size: fontSize),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )

        // Reference: a fresh canvas of the same dimensions ImageRenderer used,
        // with BrailleRasterizer.draw filling the same cell rect.
        let glyphWidth = fontSize * 0.6
        let glyphHeight = fontSize * 1.2
        let pixelWidth = Int(ceil(glyphWidth))
        let pixelHeight = Int(ceil(glyphHeight))
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let refContext = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
            space: cs, bitmapInfo: bitmapInfo
        )!
        refContext.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        refContext.fill(CGRect(x: 0, y: 0, width: glyphWidth, height: glyphHeight))
        BrailleRasterizer.draw(
            codepoint: codepoint,
            foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            in: refContext,
            rect: CGRect(x: 0, y: 0, width: glyphWidth, height: glyphHeight)
        )
        let refImage = refContext.makeImage()!

        // Compare ON-pixel masks. ImageRenderer should reproduce the
        // BrailleRasterizer output up to anti-aliasing fuzz on dot edges —
        // ≥ 92% agreement is comfortable for filled-disc rendering; CTLine
        // fallback typically agrees on < 70%.
        let renderedMask = Self.onMask(rendered)
        let refMask = Self.onMask(refImage)
        let n = min(renderedMask.count, refMask.count)
        var agreeing = 0
        for i in 0..<n where renderedMask[i] == refMask[i] {
            agreeing += 1
        }
        let agreement = Double(agreeing) / Double(n)
        #expect(
            agreement >= 0.92,
            """
            ImageRenderer and BrailleRasterizer.draw agree on only \
            \(agreement) of \(n) pixels — ImageRenderer may be falling \
            through to CTLine for U+2800–U+28FF
            """)
    }

    private static func onMask(_ image: CGImage) -> [Bool] {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(
            data: &data, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: cs, bitmapInfo: bitmapInfo
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var mask = [Bool]()
        mask.reserveCapacity(data.count / 4)
        for idx in stride(from: 0, to: data.count, by: 4) {
            let total = Int(data[idx]) + Int(data[idx + 1]) + Int(data[idx + 2])
            mask.append(total > 128)
        }
        return mask
    }

    private func cell(
        _ character: Character,
        displayColor: SIMD3<Float> = .one
    ) -> ASCIICell {
        ASCIICell(character: character, displayColor: displayColor, alpha: 1, brightness: 0.5)
    }

    private func rgbaPixels(from image: CGImage) -> [Pixel] {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: &data,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return stride(from: 0, to: data.count, by: bytesPerPixel).map { index in
            Pixel(red: data[index], green: data[index + 1], blue: data[index + 2])
        }
    }
}

private struct Pixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}
