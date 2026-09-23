import Aski
import Testing
import simd
@testable import AskiMotionLab

@Suite struct AskiMotionLabFrameTextRendererTests {
    private func cell(alpha: Float, coverage: Float) -> ASCIICell {
        ASCIICell(
            character: "#",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: alpha,
            brightness: 0.5,
            coverage: coverage
        )
    }

    @Test func cellVisibleOnlyWhenBothAlphaAndCoverageMeetThreshold() {
        let grid = ASCIIGrid(
            cells: [
                [
                    cell(alpha: 0.9, coverage: 1.0),
                    cell(alpha: 0.2, coverage: 1.0),
                    cell(alpha: 0.9, coverage: 0.2),
                ]
            ],
            colorSpace: .sRGB
        )
        #expect(FrameTextRenderer.render(grid) == "#  ")
    }

    @Test func thresholdIsInclusiveAtExactlyHalf() {
        let grid = ASCIIGrid(
            cells: [[cell(alpha: 0.5, coverage: 0.5)]],
            colorSpace: .sRGB
        )
        #expect(FrameTextRenderer.render(grid) == "#")
    }

    @Test func emptyGridRendersEmptyString() {
        let grid = ASCIIGrid(cells: [], colorSpace: .sRGB)
        #expect(FrameTextRenderer.render(grid) == "")
    }

    @Test func rowsAreNewlineSeparatedWithNoTrailingNewline() {
        let grid = ASCIIGrid(
            cells: [
                [cell(alpha: 1, coverage: 1)],
                [cell(alpha: 1, coverage: 1)],
            ],
            colorSpace: .sRGB
        )
        #expect(FrameTextRenderer.render(grid) == "#\n#")
    }
}
