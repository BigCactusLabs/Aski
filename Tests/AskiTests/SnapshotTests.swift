import AppKit
import CoreGraphics
import SnapshotTesting
import Testing
@testable import Aski

@MainActor
@Suite(.serialized) struct SnapshotTests {

    @Test func plainTextGradient80cols() {
        let image = TestImages.horizontalGradient(width: 800, height: 100)
        let text = DefaultConverter().convert(image, columns: 80).renderPlainText()

        assertSnapshot(of: text, as: .lines, named: "gradient-80cols")
    }

    @Test func plainTextDiagonalStructure() {
        let image = Self.diagonalGradient(width: 400, height: 240)
        let text = DefaultConverter().convert(image, columns: 40).renderPlainText()

        assertSnapshot(of: text, as: .lines, named: "diagonal-40cols")
    }

    @Test func renderedImageSmallGrid() {
        let cells = [
            [cell("A", .init(1, 0, 0)), cell("B", .init(0, 1, 0))],
            [cell("C", .init(0, 0, 1)), cell("D", .one)],
        ]
        let grid = ASCIIGrid(cells: cells, colorSpace: .sRGB)
        let image = grid.renderImage(
            font: .courierPrime(size: 16),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )

        assertSnapshot(of: nsImage(from: image), as: .image, named: "small-grid-rendered")
    }

    @Test func plainTextLogPolarGradient80cols() {
        let image = TestImages.horizontalGradient(width: 800, height: 100)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor,
            algorithm: .logPolar
        )
        let text = converter.convert(image, columns: 80).renderPlainText()
        assertSnapshot(of: text, as: .lines, named: "logpolar-gradient-80cols")
    }

    @Test func plainTextDotMatrixGradient80cols() {
        let image = TestImages.horizontalGradient(width: 800, height: 100)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.minimal,
            palette: BuiltInPalette.fullColor,
            algorithm: .dotMatrix,
            options: RenderingOptions(coverage: 0.7)
        )
        let text = converter.convert(image, columns: 80).renderPlainText()
        assertSnapshot(of: text, as: .lines, named: "dotmatrix-gradient-80cols")
    }

    @Test func brailleGridRendersAsImage() {
        // 8×8 cells of progressively-filled braille, rendered to verify the
        // ImageRenderer braille special case produces an image with non-trivial
        // foreground content.
        var rows: [[ASCIICell]] = []
        for r in 0..<4 {
            var row: [ASCIICell] = []
            for c in 0..<8 {
                let codepoint = UInt32(0x2800 + r * 64 + c * 8)
                row.append(
                    ASCIICell(
                        character: Character(UnicodeScalar(codepoint)!),
                        displayColor: SIMD3(1, 1, 1),
                        alpha: 1,
                        brightness: Float(r * 8 + c) / 32
                    ))
            }
            rows.append(row)
        }
        let grid = ASCIIGrid(cells: rows, colorSpace: .sRGB)
        let image = grid.renderImage(
            font: .courierPrime(size: 24),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        assertSnapshot(of: nsImage(from: image), as: .image, named: "braille-rendered-grid")
    }

    /// Per-charset rendered-image snapshot (one per new built-in). Validates that
    /// the ImageRenderer pipeline produces stable output for each new charset,
    /// with the braille variant exercising the BrailleRasterizer special case.
    @Test(arguments: [
        ("dots", StandardCharacterSet.dots),
        ("lines", StandardCharacterSet.lines),
        ("diagonal", StandardCharacterSet.diagonal),
        ("cross", StandardCharacterSet.cross),
        ("diamond", StandardCharacterSet.diamond),
        ("mixed", StandardCharacterSet.mixed),
    ])
    func newCharsetRendersAsImage(name: String, charset: StandardCharacterSet) {
        let grid = Self.glyphGrid(for: charset)
        let rendered = grid.renderImage(
            font: .courierPrime(size: 18),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        assertSnapshot(of: nsImage(from: rendered), as: .image, named: "\(name)-rendered")
    }

    /// Renderer-only fixture: every glyph appears exactly once, independent of
    /// matching-algorithm behavior. This keeps charset rendering coverage from
    /// inheriting an algorithm's selection failures or removal lifecycle.
    private static func glyphGrid(for charset: StandardCharacterSet) -> ASCIIGrid {
        let characters = charset.characters
        let columns = min(8, characters.count)
        let rows = (characters.count + columns - 1) / columns
        var cells: [[ASCIICell]] = []
        cells.reserveCapacity(rows)

        for row in 0..<rows {
            var line: [ASCIICell] = []
            let remaining = characters.count - row * columns
            line.reserveCapacity(min(columns, remaining))
            for column in 0..<min(columns, remaining) {
                let index = row * columns + column
                let character = characters[index]
                let fraction = Float(index) / Float(max(1, characters.count - 1))
                line.append(
                    ASCIICell(
                        character: character,
                        displayColor: SIMD3(fraction, 1 - fraction, 0.75),
                        alpha: 1,
                        brightness: fraction
                    ))
            }
            cells.append(line)
        }

        return ASCIIGrid(cells: cells, colorSpace: .sRGB)
    }

    private func cell(_ character: Character, _ color: SIMD3<Float>) -> ASCIICell {
        ASCIICell(character: character, displayColor: color, alpha: 1, brightness: 0.5)
    }

    private func nsImage(from image: CGImage) -> NSImage {
        NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private static func diagonalGradient(width: Int, height: Int) -> CGImage {
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

        for y in 0..<height {
            for x in 0..<width {
                let t = CGFloat(x + y) / CGFloat(width + height - 2)
                context.setFillColor(red: t, green: t, blue: t, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        return context.makeImage()!
    }
}
