import CoreGraphics
import Testing
@testable import Aski

@Suite struct TextRendererMaskTests {
    @Test func rasterGroundDoesNotChangePlainOrAttributedText() {
        let cells = [
            [
                ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 1, coverage: 0.2),
                ASCIICell(character: "B", displayColor: .one, alpha: 1, brightness: 1, coverage: 0.8),
            ]
        ]
        let baseline = ASCIIGrid(
            cells: cells,
            colorSpace: .sRGB,
            maskFallback: .character("#", color: nil)
        )
        let grounded = ASCIIGrid(
            cells: cells,
            colorSpace: .sRGB,
            maskFallback: .character("#", color: nil),
            maskGroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        )

        #expect(grounded.renderPlainText() == baseline.renderPlainText())
        #expect(grounded.renderAttributedString() == baseline.renderAttributedString())
    }

    @Test func plainTextUsesSpaceForMaskedOutCellsWithoutCharacterFallback() {
        let grid = ASCIIGrid(
            cells: [
                [
                    ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 1, coverage: 1),
                    ASCIICell(character: "B", displayColor: .one, alpha: 1, brightness: 1, coverage: 0.49),
                ]
            ],
            colorSpace: .sRGB,
            maskFallback: .solid(.black),
            maskUsesHardEdges: false
        )

        #expect(grid.renderPlainText() == "A ")
    }

    @Test func plainTextUsesCharacterFallbackBelowThreshold() {
        let grid = ASCIIGrid(
            cells: [
                [
                    ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 1, coverage: 0.5),
                    ASCIICell(character: "B", displayColor: .one, alpha: 1, brightness: 1, coverage: 0.49),
                ]
            ],
            colorSpace: .sRGB,
            maskFallback: .character("#", color: nil),
            maskUsesHardEdges: false
        )

        #expect(grid.renderPlainText() == "A#")
    }

    @Test func attributedStringUsesSameCharactersAsPlainText() {
        let grid = ASCIIGrid(
            cells: [
                [
                    ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 1, coverage: 0),
                    ASCIICell(character: "B", displayColor: .one, alpha: 1, brightness: 1, coverage: 1),
                ]
            ],
            colorSpace: .sRGB,
            maskFallback: .character("*", color: nil),
            maskUsesHardEdges: false
        )

        #expect(String(grid.renderAttributedString().characters) == "*B")
    }
}
