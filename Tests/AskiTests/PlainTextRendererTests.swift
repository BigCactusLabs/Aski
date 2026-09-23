import Testing
import simd
@testable import Aski

@Suite struct PlainTextRendererTests {
    @Test func rendersRowsWithNewlines() {
        let cells = [
            [cell("A"), cell("B")],
            [cell("C"), cell("D")],
        ]
        let grid = ASCIIGrid(cells: cells, colorSpace: .sRGB)
        let text = grid.renderPlainText()
        #expect(text == "AB\nCD")
    }

    @Test func emptyGridRendersToEmptyString() {
        let grid = ASCIIGrid(cells: [], colorSpace: .sRGB)
        #expect(grid.renderPlainText().isEmpty)
    }

    private func cell(_ character: Character) -> ASCIICell {
        ASCIICell(character: character, displayColor: .one, alpha: 1, brightness: 0.5)
    }
}
