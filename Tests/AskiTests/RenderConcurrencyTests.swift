import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Testing
@testable import Aski

/// The image renderers draw each cell from one `CTLine` per distinct character
/// that takes its color from the context fill color, instead of building an
/// attributed string with the cell color as an attribute. These tests draw the
/// same cells the old way, with an explicit per-cell foreground color, and
/// check that the renderers produce the same bytes. The grid mixes covered
/// glyphs with characters the font lacks (font fallback), translucent cells,
/// and both encoded gamuts.
@Suite struct RenderConcurrencyTests {
    private static let characters: [Character] = Array("@#a.漢😀┼★→Ω █")

    private static func grid(colorSpace: RenderColorSpace) -> ASCIIGrid {
        let rows = 4
        let columns = 7
        let cells = (0..<rows).map { row in
            (0..<columns).map { column -> ASCIICell in
                let index = row * columns + column
                return ASCIICell(
                    character: characters[index % characters.count],
                    displayColor: SIMD3(Float(index % 5) / 4, Float((index * 3) % 7) / 6, Float((index * 2) % 9) / 8),
                    alpha: [1, 0.6, 0.35][index % 3],
                    brightness: 0.5,
                    coverage: [1, 0.75][index % 2]
                )
            }
        }
        return ASCIIGrid(cells: cells, colorSpace: colorSpace)
    }

    /// Draws every cell with an attributed string that carries the cell color
    /// as its foreground color attribute.
    private static func drawReferenceCells(
        _ grid: ASCIIGrid,
        font: ASCIIFont,
        glyphWidth: CGFloat,
        glyphHeight: CGFloat,
        in context: CGContext
    ) {
        let baselineOffset = CTFontGetDescent(font.ctFont)
        for (rowIndex, row) in grid.cells.enumerated() {
            let y = CGFloat(grid.rows - rowIndex - 1) * glyphHeight + baselineOffset
            for (columnIndex, cell) in row.enumerated() {
                let alpha = max(0, min(1, cell.alpha * cell.coverage))
                guard alpha > 0 else { continue }
                let attributed = NSAttributedString(
                    string: String(cell.character),
                    attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font.ctFont,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                            grid.colorSpace.encodedColor(cell.displayColor, alpha: alpha),
                    ]
                )
                context.textPosition = CGPoint(x: CGFloat(columnIndex) * glyphWidth, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
        }
    }

    private static func bytes(_ image: CGImage?) -> Data? {
        image?.dataProvider?.data as Data?
    }

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func plainRenderMatchesPerCellColorAttributes(colorSpace: RenderColorSpace) throws {
        let grid = Self.grid(colorSpace: colorSpace)
        let font = ASCIIFont.courierPrime(size: 10)
        let scale: CGFloat = 1.25
        let background = CGColor(red: 0.1, green: 0.2, blue: 0.15, alpha: 1)
        let geometry = try #require(
            ASCIIGrid.renderGeometry(columns: grid.columns, rows: grid.rows, font: font, scale: scale, preserveSourceAspect: false))
        let context = try #require(
            CGContext(
                data: nil, width: geometry.pixelWidth, height: geometry.pixelHeight, bitsPerComponent: 8,
                bytesPerRow: geometry.pixelWidth * 4, space: grid.composition.cgColorSpace(for: grid.colorSpace),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(background)
        context.fill(
            CGRect(
                x: 0, y: 0, width: CGFloat(geometry.pixelWidth) / scale, height: CGFloat(geometry.pixelHeight) / scale))
        context.textMatrix = .identity
        Self.drawReferenceCells(
            grid, font: font, glyphWidth: geometry.glyphWidth, glyphHeight: geometry.glyphHeight, in: context)

        let rendered = grid.renderImage(font: font, backgroundColor: background, scale: scale)
        let reference = Self.bytes(context.makeImage())
        #expect(reference != nil)
        #expect(Self.bytes(rendered) == reference)
    }

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func cellRasterMatchesPerCellColorAttributes(colorSpace: RenderColorSpace) throws {
        let grid = Self.grid(colorSpace: colorSpace)
        let font = ASCIIFont.courierPrime(size: 10)
        let scale: CGFloat = 2
        let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: font, scale: scale)
        let rendered = try #require(raster.image.cgImage)

        let glyphWidth = font.pointSize * 0.6
        let glyphHeight = font.pointSize * 1.2
        let context = try #require(
            CGContext(
                data: nil, width: raster.pixelWidth, height: raster.pixelHeight, bitsPerComponent: 8,
                bytesPerRow: raster.pixelWidth * 4, space: grid.composition.cgColorSpace(for: grid.colorSpace),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        context.clear(
            CGRect(x: 0, y: 0, width: CGFloat(raster.pixelWidth) / scale, height: CGFloat(raster.pixelHeight) / scale))
        context.textMatrix = .identity
        Self.drawReferenceCells(grid, font: font, glyphWidth: glyphWidth, glyphHeight: glyphHeight, in: context)

        let reference = Self.bytes(context.makeImage())
        #expect(reference != nil)
        #expect(Self.bytes(rendered) == reference)
    }
}
