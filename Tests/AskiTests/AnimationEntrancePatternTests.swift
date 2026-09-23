import Testing
@testable import Aski

@Suite struct AnimationEntrancePatternTests {
    @Test func cascadeLeftToRightRevealsFirstColumnBeforeLast() {
        let firstAtStart = PatternEvaluator.entranceAlpha(
            .cascadeLR(),
            coord: AnimationCellCoordinate(column: 0, row: 0, columns: 4, rows: 2),
            time: 0,
            duration: 1
        )
        let firstAfterStart = PatternEvaluator.entranceAlpha(
            .cascadeLR(),
            coord: AnimationCellCoordinate(column: 0, row: 0, columns: 4, rows: 2),
            time: 0.05,
            duration: 1
        )
        let last = PatternEvaluator.entranceAlpha(
            .cascadeLR(),
            coord: AnimationCellCoordinate(column: 3, row: 0, columns: 4, rows: 2),
            time: 0,
            duration: 1
        )

        #expect(firstAtStart == 0)
        #expect(firstAfterStart > 0)
        #expect(last == 0)
    }

    @Test func cascadeCompletesAfterDuration() {
        for pattern in [EntrancePattern.cascadeLR(), .cascadeRL(), .cascadeTB()] {
            let alpha = PatternEvaluator.entranceAlpha(
                pattern,
                coord: AnimationCellCoordinate(column: 3, row: 1, columns: 4, rows: 2),
                time: 1.5,
                duration: 1
            )
            #expect(alpha == 1)
        }
    }

    @Test func centerRevealReachesCenterBeforeCorner() {
        let center = PatternEvaluator.entranceAlpha(
            .reveal(origin: .center),
            coord: AnimationCellCoordinate(column: 2, row: 2, columns: 5, rows: 5),
            time: 0.1,
            duration: 1
        )
        let corner = PatternEvaluator.entranceAlpha(
            .reveal(origin: .center),
            coord: AnimationCellCoordinate(column: 0, row: 0, columns: 5, rows: 5),
            time: 0.1,
            duration: 1
        )

        #expect(center > corner)
    }
}
