import Testing
import simd
@testable import Aski

@Suite struct GridDisplayProtocolTests {

    @Test func asciiAndTileCellsExposeSameDisplayFields() {
        let color = SIMD3<Float>(0.25, 0.5, 0.75)
        let ascii = ASCIICell(character: "A", displayColor: color, alpha: 0.4, brightness: 0.6)
        let tile = TileCell(displayColor: color, alpha: 0.4, brightness: 0.6)

        #expect(displayColor(of: ascii) == color)
        #expect(displayColor(of: tile) == color)
        #expect(displayAlpha(of: ascii) == 0.4)
        #expect(displayAlpha(of: tile) == 0.4)
        #expect(displayBrightness(of: ascii) == 0.6)
        #expect(displayBrightness(of: tile) == 0.6)
    }

    @Test func metricsWorkForBothGridTypes() {
        let ascii = ASCIIGrid(
            cells: [
                [
                    ASCIICell(character: "A", displayColor: .init(1, 0, 0), alpha: 1, brightness: 0.25),
                    ASCIICell(character: "B", displayColor: .init(0, 1, 0), alpha: 0.5, brightness: 0.75),
                ]
            ],
            colorSpace: .sRGB
        )
        let tile = TileGrid(
            cells: [
                [
                    TileCell(displayColor: .init(1, 0, 0), alpha: 1, brightness: 0.25),
                    TileCell(displayColor: .init(0, 1, 0), alpha: 0.5, brightness: 0.75),
                ]
            ],
            colorSpace: .sRGB
        )

        let asciiMetrics = gridDisplayMetrics(ascii)
        let tileMetrics = gridDisplayMetrics(tile)

        #expect(asciiMetrics.rows == 1)
        #expect(asciiMetrics.columns == 2)
        #expect(asciiMetrics.nonEmptyCellCount == 2)
        #expect(abs(asciiMetrics.averageAlpha - 0.75) < 0.0001)
        #expect(abs(asciiMetrics.averageBrightness - 0.5) < 0.0001)

        #expect(tileMetrics.rows == asciiMetrics.rows)
        #expect(tileMetrics.columns == asciiMetrics.columns)
        #expect(tileMetrics.nonEmptyCellCount == asciiMetrics.nonEmptyCellCount)
        #expect(abs(tileMetrics.averageAlpha - asciiMetrics.averageAlpha) < 0.0001)
        #expect(abs(tileMetrics.averageBrightness - asciiMetrics.averageBrightness) < 0.0001)
    }
}
