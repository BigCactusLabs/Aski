import CoreGraphics
import Foundation
import Testing
@testable import Aski

/// ASKI-94: populated-cell coverage is not the grid's rectangular bounding box.
/// These are geometry/coverage contracts, not replacement render goldens.
@Suite struct MaskFallbackGroundworkTests {
    @Test(arguments: [false, true], [CGFloat(1), CGFloat(1.25)])
    func originalFallbackDoesNotFillMissingCells(grounded: Bool, scale: CGFloat) throws {
        let source = try Self.sourceImage()
        let cell = ASCIICell(character: " ", displayColor: .zero, alpha: 0, brightness: 0, coverage: 0)
        // Symmetric row lengths make the hole oracle independent of bitmap
        // memory row orientation. Sample cell interiors, not antialiased edges.
        let lengths = [4, 1, 0, 1, 4]
        for hardEdges in [false, true] {
            let grid = ASCIIGrid(
                cells: lengths.map { Array(repeating: cell, count: $0) }, colorSpace: .sRGB,
                maskFallback: .originalImage(source, sizing: .stretch),
                maskGroundColor: grounded ? CGColor(gray: 0.2, alpha: 1) : nil,
                maskUsesHardEdges: hardEdges
            )
            let image = grid.renderImage(font: .system(size: 20), backgroundColor: CGColor(gray: 0, alpha: 0), scale: scale)
            try #require(image.width > 4 && image.height > 5)
            let pixels = try Self.rgba(image)
            for row in 0..<5 {
                for column in 0..<4 {
                    let x = Int((Double(column) + 0.5) * Double(image.width) / 4)
                    let y = Int((Double(row) + 0.5) * Double(image.height) / 5)
                    let alpha = pixels[(y * image.width + x) * 4 + 3]
                    #expect(alpha == (column < lengths[row] ? 255 : 0))
                }
            }
        }
    }

    @Test func originalFallbackSizingKeepsItsCenteredPlacement() throws {
        let image = try Self.sourceImage()  // square source
        let canvas = CGRect(x: 10, y: 20, width: 200, height: 100)
        #expect(ASCIIGrid.fallbackImageRect(image: image, sizing: .stretch, canvas: canvas) == canvas)
        #expect(ASCIIGrid.fallbackImageRect(image: image, sizing: .fit, canvas: canvas) == CGRect(x: 60, y: 20, width: 100, height: 100))
        #expect(ASCIIGrid.fallbackImageRect(image: image, sizing: .fill, canvas: canvas) == CGRect(x: 10, y: -30, width: 200, height: 200))
    }

    private static func sourceImage() throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return try #require(context.makeImage())
    }

    private static func rgba(_ image: CGImage) throws -> [UInt8] {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
