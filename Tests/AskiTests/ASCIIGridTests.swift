import Testing
import simd
@testable import Aski

@Suite struct ASCIIGridTests {
    @Test func gridConstructionPreservesDimensions() {
        let cells: [[ASCIICell]] = [
            [cell("A"), cell("B")],
            [cell("C"), cell("D")],
        ]

        let grid = ASCIIGrid(cells: cells, colorSpace: .sRGB)

        #expect(grid.rows == 2)
        #expect(grid.columns == 2)
        #expect(grid.colorSpace == .sRGB)
        #expect(grid.cells == cells)
    }

    @Test func emptyGridHasZeroRowsAndColumns() {
        let grid = ASCIIGrid(cells: [], colorSpace: .displayP3)

        #expect(grid.rows == 0)
        #expect(grid.columns == 0)
        #expect(grid.colorSpace == .displayP3)
    }

    private func cell(_ character: Character) -> ASCIICell {
        ASCIICell(character: character, displayColor: .one, alpha: 1, brightness: 0.5)
    }
}
