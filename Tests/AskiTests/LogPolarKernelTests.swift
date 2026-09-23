import Testing
import simd
@testable import Aski

@Suite("Aski.Algorithms.LogPolarKernel")
struct LogPolarKernelTests {

    /// edgeEmphasis is wired through `ConversionContext.options.edgeEmphasis`
    /// into LogPolarKernel.extractShapeVector. At edgeEmphasis=0 the shape
    /// vector is built from (1 − luminance); at edgeEmphasis=1 from Sobel
    /// magnitude (peak-normalized). For a step-edge cell the two have
    /// genuinely different spatial distributions, so the picked glyph must
    /// differ for at least one of the cells across the image.
    ///
    /// Tested at the kernel level (not the converter) because the converter's
    /// thumbnail step shrinks default-call cell sizes to 2×N, below the
    /// Sobel guard `w >= 3, h >= 3`.
    @Test func edgeEmphasisChangesPickedGlyph() {
        let cellWidth = 16
        let cellHeight = 16
        let columns = 4
        let rows = 4
        let pixelWidth = cellWidth * columns
        let pixelHeight = cellHeight * rows

        // Striped image with a vertical edge inside every cell column. Edges
        // sit at the column-internal midline (x = c*cellWidth + cellWidth/2
        // for each cell column c). Sobel fires inside each cell, producing
        // a sharp magnitude peak at the stripe transition; (1 − luminance)
        // is a half-dark/half-bright split. Different spatial distributions
        // → different shape histograms → different picked glyphs.
        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let inCellX = x % cellWidth
                let v: UInt8 = inCellX < cellWidth / 2 ? 0 : 255
                let off = (y * pixelWidth + x) * 4
                pixels[off] = v
                pixels[off + 1] = v
                pixels[off + 2] = v
                pixels[off + 3] = 255
            }
        }
        let charset = StandardCharacterSet.standard

        let pickAt: (Float) -> [Character] = { edgeEmphasis in
            let opts = RenderingOptions(edgeEmphasis: edgeEmphasis)
            let ctx = ConversionContext(
                pixels: pixels,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                cellWidth: cellWidth,
                cellHeight: cellHeight,
                columns: columns,
                rows: rows,
                palette: .passThrough,
                options: ResolvedRenderingOptions(opts),
                colorSpace: .sRGB
            )
            let kernel = LogPolarKernel(characterSet: charset)
            var picked: [Character] = []
            for r in 0..<rows {
                for c in 0..<columns {
                    let stats = CellStats(displayColor: .one, alpha: 1, adjustedL: 0.5, rawL: 0.5)
                    picked.append(kernel.score(cell: CellCoord(column: c, row: r), stats: stats, in: ctx))
                }
            }
            return picked
        }
        let zero = pickAt(0)
        let high = pickAt(1)
        let differingCells = zip(zero, high).filter { $0 != $1 }.count
        #expect(
            differingCells >= 1,
            """
            edgeEmphasis=1 produced identical output to edgeEmphasis=0 \
            across all \(zero.count) cells — Sobel weighting is likely \
            not wired through the kernel.
            """)
    }

    @Test func matchReturnsWinnerAsFirstRankedIndex() {
        let cellWidth = 16
        let cellHeight = 16
        let context = ConversionContext(
            pixels: [UInt8](repeating: 128, count: cellWidth * cellHeight * 4),
            pixelWidth: cellWidth,
            pixelHeight: cellHeight,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            columns: 1,
            rows: 1,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB
        )
        let kernel = LogPolarKernel(characterSet: StandardCharacterSet.standard)
        let result = kernel.match(
            cell: CellCoord(column: 0, row: 0),
            stats: CellStats(displayColor: .one, alpha: 1, adjustedL: 0.5, rawL: 0.5),
            in: context,
            resultLimit: 6
        )

        #expect(result.rankedIndices.count == 6)
        #expect(result.rankedIndices.first == result.winnerIndex)
        #expect(result.winnerCharacter == StandardCharacterSet.standard.characters[result.winnerIndex])
    }
}
