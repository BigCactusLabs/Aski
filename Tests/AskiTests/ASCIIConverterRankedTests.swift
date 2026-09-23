import Testing
@testable import Aski

@Suite struct ASCIIConverterRankedTests {
    @Test func rankedWinnerMatchesPublicConvertForAllAlgorithms() {
        let image = TestImages.horizontalGradient(width: 160, height: 80)
        for algorithm in [ASCIIAlgorithm.logPolar, .dotMatrix] {
            let converter = ASCIIConverter(
                characterSet: StandardCharacterSet.standard,
                palette: BuiltInPalette.fullColor,
                algorithm: algorithm
            )
            let publicGrid = converter.convert(image, columns: 24)
            let ranked = converter.convertWithRankedCandidates(image, columns: 24, candidateStride: 1)

            #expect(ranked.grid.cells == publicGrid.cells)
            #expect(ranked.grid.colorSpace == publicGrid.colorSpace)
            #expect(ranked.candidateStride == 1)
            #expect(ranked.candidates.count == publicGrid.rows * publicGrid.columns)
            #expect(ranked.candidateCounts.allSatisfy { $0 == 1 })
        }
    }

    @Test func logPolarRankedConversionReturnsFlatCandidates() {
        let image = TestImages.horizontalGradient(width: 160, height: 80)
        let converter = DefaultConverter()
        let ranked = converter.convertWithRankedCandidates(image, columns: 24, candidateStride: 6)

        #expect(ranked.grid.columns == 24)
        #expect(ranked.candidateStride == 6)
        #expect(ranked.candidates.count == ranked.grid.rows * ranked.grid.columns * 6)
        #expect(ranked.candidateCounts.count == ranked.grid.rows * ranked.grid.columns)
        #expect(ranked.candidateCounts.contains { $0 > 1 })
    }
}
