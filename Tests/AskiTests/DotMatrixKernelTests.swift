import Testing
import simd
@testable import Aski

@Suite("Aski.Algorithms.DotMatrixKernel")
struct DotMatrixKernelTests {
    @Test func brightZeroPicksLowestBrightnessGlyph() {
        let kernel = DotMatrixKernel(
            characterSet: StandardCharacterSet.minimal,
            columns: 1,
            rows: 1,
            ditherStrength: 0
        )
        let ctx = makeContext()
        let stats = CellStats(displayColor: .zero, alpha: 1, adjustedL: 0, rawL: 0)
        let ch = kernel.score(cell: CellCoord(column: 0, row: 0), stats: stats, in: ctx)
        #expect(ch == StandardCharacterSet.minimal.characters.first!)
    }

    @Test func brightnessOnePicksHighestBrightnessGlyph() {
        let kernel = DotMatrixKernel(
            characterSet: StandardCharacterSet.minimal,
            columns: 1,
            rows: 1,
            ditherStrength: 0
        )
        let ctx = makeContext()
        let stats = CellStats(displayColor: .one, alpha: 1, adjustedL: 1.0, rawL: 1.0)
        let ch = kernel.score(cell: CellCoord(column: 0, row: 0), stats: stats, in: ctx)
        #expect(ch == StandardCharacterSet.minimal.characters.last!)
    }

    @Test func ditheringSpreadsBrightnessAcrossUniformGrid() {
        let kernel = DotMatrixKernel(
            characterSet: StandardCharacterSet.minimal,
            columns: 8,
            rows: 8,
            ditherStrength: 1.0
        )
        let ctx = makeContext()
        var distinctChars = Set<Character>()
        for r in 0..<8 {
            for c in 0..<8 {
                // Uniform 0.5 brightness across the grid.
                let stats = CellStats(displayColor: .one * 0.5, alpha: 1, adjustedL: 0.5, rawL: 0.5)
                let ch = kernel.score(cell: CellCoord(column: c, row: r), stats: stats, in: ctx)
                distinctChars.insert(ch)
            }
        }
        // FS dithering on uniform mid-grey should produce ≥ 2 distinct glyphs
        // (alternating between the two brightness-nearest candidates).
        #expect(
            distinctChars.count >= 2,
            "FS dither produced only \(distinctChars.count) distinct chars")
    }

    @Test func pickReturnsGlyphAndMatchingIndex() {
        let kernel = DotMatrixKernel(
            characterSet: StandardCharacterSet.minimal,
            columns: 2,
            rows: 1,
            ditherStrength: 1
        )
        let ctx = makeContext()
        let stats = CellStats(displayColor: .one * 0.5, alpha: 1, adjustedL: 0.5, rawL: 0.5)

        let first = kernel.pick(cell: CellCoord(column: 0, row: 0), stats: stats, in: ctx)
        let second = kernel.pick(cell: CellCoord(column: 1, row: 0), stats: stats, in: ctx)

        #expect(first.character == StandardCharacterSet.minimal.characters[first.index])
        #expect(second.character == StandardCharacterSet.minimal.characters[second.index])
    }

    private func makeContext() -> ConversionContext {
        ConversionContext(
            pixels: [UInt8](repeating: 128, count: 4),
            pixelWidth: 1,
            pixelHeight: 1,
            cellWidth: 1,
            cellHeight: 1,
            columns: 8,
            rows: 8,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB
        )
    }
}
