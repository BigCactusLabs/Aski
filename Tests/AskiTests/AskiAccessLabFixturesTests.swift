import Aski
import Testing
import simd
@testable import AskiAccessLab

@Suite struct AskiAccessLabFixturesTests {
    @Test func palettesIncludeDefaultsAndGeneratedCandidate() {
        let palettes = AccessLabPalette.all
        #expect(palettes.map(\.id) == ["ansi16", "monochrome", "accessible-ansi16-v1"])
        #expect(palettes.map(\.candidateID) == ["default", "default", "generated"])
        #expect(palettes[0].colors.count == 16)
        #expect(palettes[1].colors.count == 1)
        #expect(palettes[2].colors.count == 16)
    }

    @Test func paletteSamplesIncludeBackgroundAndPairs() {
        let samples = AccessFixtures.paletteSamples(for: AccessLabPalette.all[1])
        #expect(samples.contains { $0.comparisonRole == .colorOnBlack })
        #expect(samples.contains { $0.comparisonRole == .colorOnWhite })
        #expect(samples.allSatisfy { $0.surface == .palette })
    }

    @Test func renderedSamplesUseSRGBGrid() throws {
        let samples = try AccessFixtures.renderedGridSamples(
            for: AccessLabPalette.all[0],
            columns: 24
        )
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.surface == .renderedGrid })
        #expect(samples.allSatisfy { $0.comparisonRole == .renderedAdjacentCells })
    }

    @Test func renderedGridRejectsDisplayP3BeforeScoring() {
        let grid = ASCIIGrid(
            cells: [[ASCIICell(character: "#", displayColor: .one, alpha: 1, brightness: 1)]],
            colorSpace: .displayP3
        )
        #expect(throws: AccessFixtureError.self) {
            try AccessFixtures.adjacentCellSamples(
                grid: grid,
                palette: AccessLabPalette.all[0],
                fixtureID: "bad"
            )
        }
    }
}
