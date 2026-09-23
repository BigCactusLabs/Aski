import Testing
@testable import Aski

@Suite struct AnimationOngoingPatternTests {
    @Test func pulseClosesOverPeriod() {
        let coord = AnimationCellCoordinate(column: 0, row: 0, columns: 4, rows: 4)
        let a = PatternEvaluator.ongoingAlpha(.pulse(period: 1, depth: 1), coord: coord, time: 0)
        let b = PatternEvaluator.ongoingAlpha(.pulse(period: 1, depth: 1), coord: coord, time: 1)

        #expect(abs(a - b) < 0.000_001)
    }

    @Test func pulseDepthZeroIsNoOp() {
        let coord = AnimationCellCoordinate(column: 2, row: 2, columns: 4, rows: 4)
        #expect(PatternEvaluator.ongoingAlpha(.pulse(period: 1, depth: 0), coord: coord, time: 0.5) == 1)
    }

    @Test func horizontalWaveVariesByColumn() {
        let left = PatternEvaluator.ongoingAlpha(
            .wave(amplitude: 0.5, frequency: 1, direction: .horizontal),
            coord: AnimationCellCoordinate(column: 0, row: 0, columns: 4, rows: 4),
            time: 0.125
        )
        let right = PatternEvaluator.ongoingAlpha(
            .wave(amplitude: 0.5, frequency: 1, direction: .horizontal),
            coord: AnimationCellCoordinate(column: 1, row: 0, columns: 4, rows: 4),
            time: 0.125
        )

        #expect(left != right)
    }

    @Test func softKnobsClampAndNaNFallsBack() {
        let coord = AnimationCellCoordinate(column: 0, row: 0, columns: 4, rows: 4)
        let wave = PatternEvaluator.ongoingAlpha(
            .wave(amplitude: .nan, frequency: 1, direction: .horizontal),
            coord: coord,
            time: 0.25
        )
        let pulse = PatternEvaluator.ongoingAlpha(
            .pulse(period: 1, depth: .nan),
            coord: coord,
            time: 0.5
        )

        #expect((0...1).contains(wave))
        #expect((0...1).contains(pulse))
    }
}
