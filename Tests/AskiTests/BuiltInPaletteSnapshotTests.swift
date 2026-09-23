import AppKit
import CoreGraphics
import SnapshotTesting
import Testing
@testable import Aski

@MainActor
@Suite(.serialized) struct BuiltInPaletteSnapshotTests {
    @Test func fullColorPaletteRender() {
        assertPaletteSnapshot(.fullColor, named: "full-color", testName: #function)
    }

    @Test func ansi16PaletteRender() {
        assertPaletteSnapshot(.ansi16, named: "ansi16", testName: #function)
    }

    @Test func monochromePaletteRender() {
        assertPaletteSnapshot(.monochrome, named: "monochrome", testName: #function)
    }

    private func assertPaletteSnapshot(_ palette: BuiltInPalette, named name: String, testName: String) {
        let image = Self.reviewImage(width: 240, height: 160)
        let grid = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: palette,
            algorithm: .logPolar,
            tileShape: .wide,
            colorSpace: .sRGB,
            oversample: 2
        ).convert(image, columns: 48)
        let rendered = grid.renderImage(
            font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )

        assertSnapshot(of: nsImage(from: rendered), as: .image, named: name, testName: testName)
    }

    private func nsImage(from image: CGImage) -> NSImage {
        NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private static func reviewImage(width: Int, height: Int) -> CGImage {
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

        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (1.0, 0.0, 0.0),
            (0.0, 1.0, 0.0),
            (0.0, 0.25, 1.0),
            (1.0, 1.0, 0.0),
        ]
        let halfWidth = width / 2
        let halfHeight = height / 2
        for row in 0..<2 {
            for column in 0..<2 {
                let color = colors[row * 2 + column]
                context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
                context.fill(
                    CGRect(
                        x: column * halfWidth,
                        y: row * halfHeight,
                        width: column == 0 ? halfWidth : width - halfWidth,
                        height: row == 0 ? halfHeight : height - halfHeight
                    ))
            }
        }

        return context.makeImage()!
    }
}
