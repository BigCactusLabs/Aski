import CoreGraphics
import Foundation
import Testing
@testable import Aski

@Suite struct ImageRendererAspectTests {
    /// Build a grid with `rows` x `columns` of plain opaque cells.
    private func grid(rows: Int, columns: Int) -> ASCIIGrid {
        let cell = ASCIICell(
            character: "#",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 1,
            brightness: 1,
            coverage: 1
        )
        let cells = Array(repeating: Array(repeating: cell, count: columns), count: rows)
        return ASCIIGrid(cells: cells, colorSpace: .sRGB)
    }

    @Test func defaultRenderUsesLegacyGlyphAspect() {
        // pointSize 10 -> glyphWidth 6, glyphHeight 12. 10 cols x 20 rows.
        let image = grid(rows: 20, columns: 10).renderImage(
            font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        #expect(image.width == 60)  // ceil(10 * 6)
        #expect(image.height == 240)  // ceil(20 * 12)
    }

    @Test func preserveSourceAspectUsesTallerCells() {
        // glyphHeight becomes glyphWidth(6) * sourceCellHeightOverWidth. That
        // ratio is a Float (2.2), which widens to ~2.20000004768, so
        // 20 * 6 * ratio ≈ 264.0000057 and ceil rounds to 265 (not the naive
        // 264 you'd get from exact decimal 2.2). Deterministic on IEEE-754.
        let image = grid(rows: 20, columns: 10).renderImage(
            font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1,
            preserveSourceAspect: true
        )
        #expect(image.width == 60)
        #expect(image.height == 265)
    }
}
