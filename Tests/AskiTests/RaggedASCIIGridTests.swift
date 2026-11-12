import CoreGraphics
import Foundation
import Testing
@testable import Aski

@Suite struct RaggedASCIIGridTests {
    private let font = ASCIIFont.system(size: 20)
    private let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    private let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)

    @Test(arguments: [false, true])
    func widerLaterRowIsVisible(firstRowEmpty: Bool) throws {
        let first = firstRowEmpty ? [] : [cell(" ")]
        let grid = ASCIIGrid(cells: [first, [cell(" "), cell("⣿")]], colorSpace: .sRGB)
        #expect(grid.columns == 2)
        #expect(grid.rows == 2)

        let images = [
            grid.renderImage(font: font, backgroundColor: black, scale: 1),
            grid.renderImage(font: font, backgroundColor: black, targetPixelWidth: 24),
            renderEffects(grid, background: black, scale: 1),
        ]
        for image in images {
            try #require(image.width == 24)
            try #require(image.height == 48)
            let bytes = TestImages.deviceRGBBytes(image)
            let ink = (24..<48).contains { y in
                (12..<24).contains { x in
                    component(bytes, width: image.width, x: x, y: y, channel: 0) > 128
                }
            }
            #expect(ink)
            #expect(component(bytes, width: image.width, x: 18, y: 12, channel: 0) == 0)
        }
    }

    @Test func allEmptyRowsKeepTheirGeometryAndText() {
        let grid = ASCIIGrid(cells: [[], []], colorSpace: .sRGB)
        #expect(grid.columns == 0)
        #expect(grid.rows == 2)
        #expect(grid.renderPlainText() == "\n")
        #expect(String(grid.renderAttributedString().characters) == "\n")
        for image in [
            grid.renderImage(font: font, backgroundColor: black, scale: 1),
            renderEffects(grid, background: black, scale: 1),
        ] {
            #expect(image.width == 1)
            #expect(image.height == 1)
        }
    }

    @Test func textOnlyReplacesSuppliedCells() {
        let grid = ASCIIGrid(
            cells: [[cell("A")], [], [cell("B", coverage: 0), cell("C")]],
            colorSpace: .sRGB,
            maskFallback: .character("X", color: nil)
        )
        #expect(grid.renderPlainText() == "A\n\nXC")
        #expect(String(grid.renderAttributedString().characters) == "A\n\nXC")
    }

    @Test(arguments: [false, true], [false, true])
    func maskPaintDistinguishesMissingAndZeroCoverage(useGround: Bool, hardEdges: Bool) throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(blue)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let original = try #require(context.makeImage())
        let fallbacks: [MaskFallback] = [.solid(blue), .originalImage(original, sizing: .stretch)]
        // The top row ends at x = 20.328. Stretching the presence mask to the
        // ceiled 31 px canvas would shift that edge past the center of pixel 20.
        let scale: CGFloat = 0.847
        let canvasGrid = ASCIIGrid(
            cells: [[cell(" "), cell(" "), cell(" ")], [cell(" "), cell(" "), cell(" ")]],
            colorSpace: .sRGB
        )
        let canvasImages = [
            canvasGrid.renderImage(font: font, backgroundColor: green, scale: scale),
            renderEffects(canvasGrid, background: green, scale: scale),
        ]
        let canvasBytes = canvasImages.map(TestImages.deviceRGBBytes)
        for fallback in fallbacks {
            let grid = ASCIIGrid(
                cells: [[cell(" "), cell(" ", coverage: 0)], [cell(" "), cell(" "), cell(" ")]],
                colorSpace: .sRGB,
                maskFallback: fallback,
                maskGroundColor: useGround ? red : nil,
                maskUsesHardEdges: hardEdges
            )
            let images = [
                grid.renderImage(font: font, backgroundColor: green, scale: scale),
                renderEffects(grid, background: green, scale: scale),
            ]
            for (index, image) in images.enumerated() {
                try #require(image.width == 31)
                try #require(image.height == 41)
                let bytes = TestImages.deviceRGBBytes(image)
                #expect(component(bytes, width: image.width, x: 15, y: 10, channel: 2) > 240)
                // The direct per-cell overlay antialiases the fraction of pixel 20
                // that lies inside the painted cell. Probe the first full hole pixel.
                let holeX = index == 0 && !useGround ? 21 : 20
                let holeOffset = (10 * image.width + holeX) * 4
                let holePixel = holeOffset..<(holeOffset + 4)
                #expect(bytes[holePixel] == canvasBytes[index][holePixel])
                let activeChannel = useGround ? 0 : 1
                #expect(component(bytes, width: image.width, x: 5, y: 10, channel: activeChannel) > 240)
            }
        }
    }

    private func cell(_ character: Character, coverage: Float = 1) -> ASCIICell {
        ASCIICell(character: character, displayColor: .one, alpha: 1, brightness: 1, coverage: coverage)
    }

    private func renderEffects(_ grid: ASCIIGrid, background: CGColor, scale: CGFloat) -> CGImage {
        grid.renderImage(
            font: font,
            backgroundColor: background,
            scale: scale,
            composition: CompositionOptions(background: .solid(background))
        )
    }

    private func component(_ bytes: [UInt8], width: Int, x: Int, y: Int, channel: Int) -> UInt8 {
        bytes[(y * width + x) * 4 + channel]
    }
}
