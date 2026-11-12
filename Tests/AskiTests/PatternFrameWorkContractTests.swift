import Foundation
import Testing
@testable import Aski

/// ASKI-91: characterize frame-wide candidates before changing evaluation.
/// Same-host bit comparisons are not a cross-platform libm golden.
@Suite struct PatternFrameWorkContractTests {
    private static let coordinates = [
        AnimationCellCoordinate(column: 0, row: 0, columns: 1, rows: 1),
        AnimationCellCoordinate(column: 0, row: 0, columns: 80, rows: 40),
        AnimationCellCoordinate(column: 79, row: 39, columns: 80, rows: 40),
        AnimationCellCoordinate(column: 117, row: 51, columns: 192, rows: 96),
        AnimationCellCoordinate(column: 287, row: 143, columns: 288, rows: 144),
    ]

    @Test func pulseMatchesFrozenScalarArithmeticAtEveryCoordinate() {
        for period in [0.125, 1, 3] {
            for depth in [0.0, 0.3, 1] {
                let pattern = OngoingPattern.pulse(period: period, depth: depth)
                for time in [0, 0.125, 0.25, 0.5, 1, 10, Double.greatestFiniteMagnitude, .infinity, .nan] {
                    // Frozen expression from bbe65fa, not a call to the evaluator.
                    let value = 1 - depth / 2 + (depth / 2) * sin(2 * Double.pi * time / period + Double.pi / 2)
                    let expected = depth == 0 || !value.isFinite ? 1 : min(1, max(0, value))
                    for coord in Self.coordinates {
                        #expect(PatternEvaluator.ongoingAlpha(pattern, coord: coord, time: time).bitPattern == expected.bitPattern)
                    }
                }
            }
        }
    }

    @Test func directionalWaveKeepsItsSpatialDenominatorsAndOperationOrder() {
        for direction in [WaveDirection.horizontal, .vertical, .diagonal] {
            for coord in Self.coordinates {
                let spatial: Double
                switch direction {
                case .horizontal: spatial = Double(coord.column) / Double(max(coord.columns, 1))
                case .vertical: spatial = Double(coord.row) / Double(max(coord.rows, 1))
                case .diagonal: spatial = Double(coord.row + coord.column) / Double(max(coord.rows + coord.columns, 1))
                }
                for time in [0, 0.25.nextDown, 0.25, 0.25.nextUp, 0.5, 1, 10] {
                    let expected = 0.5 + 0.4 * sin(2 * Double.pi * 1.25 * time - 2 * Double.pi * spatial)
                    let actual = PatternEvaluator.ongoingAlpha(
                        .wave(amplitude: 0.4, frequency: 1.25, direction: direction), coord: coord, time: time)
                    #expect(actual.bitPattern == expected.bitPattern)
                }
            }
        }
    }

    @Test func neutralPatternsRemainUnitMultipliersEvenForNonfiniteTime() {
        let patterns: [OngoingPattern] = [
            .pulse(period: 1, depth: 0), .pulse(period: 1, depth: -2),
            .wave(amplitude: 0, frequency: 1), .wave(amplitude: -2, frequency: 1, direction: .diagonal),
        ]
        for pattern in patterns {
            for coord in Self.coordinates {
                for time in [-1, 0, 1, Double.nan, .infinity, -.infinity] {
                    #expect(PatternEvaluator.ongoingAlpha(pattern, coord: coord, time: time) == 1)
                }
            }
        }
    }

    @Test func nonfiniteAestheticParametersUseDefaultsRatherThanNeutralShortcuts() {
        for value in [Double.nan, .infinity, -.infinity] {
            for coord in Self.coordinates {
                let pulse = PatternEvaluator.ongoingAlpha(.pulse(period: 1, depth: value), coord: coord, time: 0.5)
                let wave = PatternEvaluator.ongoingAlpha(.wave(amplitude: value, frequency: 1), coord: coord, time: 0.25)
                #expect(pulse.bitPattern == PatternEvaluator.ongoingAlpha(.pulse(), coord: coord, time: 0.5).bitPattern)
                #expect(wave.bitPattern == PatternEvaluator.ongoingAlpha(.wave(), coord: coord, time: 0.25).bitPattern)
            }
        }
    }

    @Test func offGridRevealOriginIsNotClampedToTheGrid() {
        let coord = AnimationCellCoordinate(column: 0, row: 1, columns: 3, rows: 3)
        let actual = PatternEvaluator.entranceAlpha(.reveal(origin: .init(x: -1, y: 0.5)), coord: coord, time: 0.5, duration: 1)
        // Distance to this cell is 1; the farthest corner is sqrt(4 + 0.25).
        let expected = (0.5 - (1 / hypot(2, 0.5)) * 0.8) / 0.2
        #expect(actual.bitPattern == expected.bitPattern)
        #expect(actual > 0 && actual < 1)
        #expect(PatternEvaluator.entranceAlpha(.reveal(origin: .init(x: 0, y: 0.5)), coord: coord, time: 0.5, duration: 1) == 1)
    }

    @Test func invalidAnchorCoordinatesResolveIndependently() {
        for invalid in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            for coord in Self.coordinates {
                let actual = PatternEvaluator.entranceAlpha(.reveal(origin: .init(x: invalid, y: -1)), coord: coord, time: 0.75, duration: 1)
                let expected = PatternEvaluator.entranceAlpha(.reveal(origin: .init(x: 0.5, y: -1)), coord: coord, time: 0.75, duration: 1)
                #expect(actual.bitPattern == expected.bitPattern)
            }
        }
    }

    @Test func completedRevealIsUnitForEveryAnchorAndEasing() {
        for easing in [AnimationEasing.linear, .easeIn, .easeOut, .easeInOut] {
            for anchor in [AnimationAnchor.center, .init(x: -1, y: 2), .init(x: .nan, y: .infinity)] {
                for coord in Self.coordinates {
                    for time in [1, 1.0.nextUp, 5, Double.greatestFiniteMagnitude] {
                        #expect(PatternEvaluator.entranceAlpha(.reveal(origin: anchor, easing: easing), coord: coord, time: time, duration: 1) == 1)
                    }
                }
            }
        }
    }

    @Test func lastRevealCellDistinguishesTheEndpointFromItsPredecessor() {
        let corner = AnimationCellCoordinate(column: 2, row: 2, columns: 3, rows: 3)
        let pattern = EntrancePattern.reveal(origin: .topLeading)
        let before = PatternEvaluator.entranceAlpha(pattern, coord: corner, time: 1.0.nextDown, duration: 1)
        #expect(before < 1 && before > 0)
        #expect(PatternEvaluator.entranceAlpha(pattern, coord: corner, time: 1, duration: 1) == 1)
    }

    @Test func concurrentEvaluationDoesNotMixFrameParameters() async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<64 {
                group.addTask {
                    let coord = Self.coordinates[index % Self.coordinates.count]
                    let time = Double(index) / 64
                    let depth = Double(index % 8) / 8
                    let value = 1 - depth / 2 + (depth / 2) * sin(2 * Double.pi * time + Double.pi / 2)
                    let expected = depth == 0 ? 1 : min(1, max(0, value))
                    #expect(PatternEvaluator.ongoingAlpha(.pulse(period: 1, depth: depth), coord: coord, time: time).bitPattern == expected.bitPattern)
                }
            }
        }
    }
}
