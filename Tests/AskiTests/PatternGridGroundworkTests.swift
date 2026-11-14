import CoreGraphics
import Foundation
import Testing
@testable import Aski

/// ASKI-91: a neutral shortcut must preserve the current multiply-by-one
/// semantics, not just ordinary finite alpha. Native Apple-platform tests.
@Suite struct PatternGridGroundworkTests {
    @Test func neutralOverlayPreservesRaggedCellsAndMaskMetadata() throws {
        let base = try Self.grid(ragged: true)
        for pattern in [OngoingPattern.pulse(period: 1, depth: 0), .wave(amplitude: 0, frequency: 1)] {
            let actual = base.applyingOngoingPattern(pattern, at: .infinity)
            Self.expectGrid(actual, matches: base) { _, _, original in Self.scalarMultiply(original.alpha, 1) }
        }
    }

    @Test func pulseOverlayAndAnimatedFramesMatchScalarAcrossConcurrentInvocations() async throws {
        let ragged = try Self.grid(ragged: true)
        let rectangular = try Self.grid(ragged: false)
        let cases: [(period: Double, depth: Double, time: Double)] = [
            (1, 0.8, 0.375), (0.7, 0.3, 0.62), (1, 1, 0.5),
            (1, 0.8, 1.0.nextDown), (1, 0.8, 1), (1, 0.8, 1.0.nextUp),
            (2, 0.2, -1), (2, 0.2, .nan), (2, 0.2, .infinity), (2, 0.2, -.infinity),
            (0.125, 0.3, .greatestFiniteMagnitude), (1, .nan, 0.5), (1, .infinity, 0.5),
            (1, -2, 0.5), (1, 2, 0.5),
        ]
        await withTaskGroup(of: Void.self) { group in
            for (period, depth, time) in cases {
                group.addTask {
                    let resolvedTime = time.isFinite ? max(0, time) : 0
                    let pattern = OngoingPattern.pulse(period: period, depth: depth)
                    let pulse = Self.scalarPulse(period: period, depth: depth, time: resolvedTime)
                    let overlay = ragged.applyingOngoingPattern(pattern, at: time)
                    Self.expectGrid(overlay, matches: ragged) { _, _, original in original.alpha * Float(pulse) }

                    for entrance in [nil, EntrancePattern.reveal(origin: .init(x: -0.25, y: 0.5))] {
                        let frame = Self.animated(rectangular, entrance: entrance, ongoing: pattern).grid(at: time)
                        Self.expectGrid(frame, matches: rectangular) { column, row, original in
                            let coord = AnimationCellCoordinate(
                                column: column, row: row, columns: rectangular.columns, rows: rectangular.rows)
                            // Entrance evaluation is unchanged. Only the pulse oracle is independent.
                            let entranceAlpha =
                                entrance.map { PatternEvaluator.entranceAlpha($0, coord: coord, time: resolvedTime, duration: 1) } ?? 1
                            return original.alpha * Float(min(1, max(0, entranceAlpha * pulse)))
                        }
                    }
                }
            }
        }
    }

    @Test func combinedRevealAndPulseRoundsAfterMultiplyingInDouble() throws {
        let base = try Self.grid(ragged: false)
        let entrance = EntrancePattern.reveal(origin: .init(x: -0.25, y: 0.5))
        let time = 0.375
        let pulse = Self.scalarPulse(period: 1, depth: 0.8, time: time)
        let coord = AnimationCellCoordinate(column: 0, row: 0, columns: base.columns, rows: base.rows)
        let entranceAlpha = PatternEvaluator.entranceAlpha(entrance, coord: coord, time: time, duration: 1)
        let expected = Float(entranceAlpha * pulse)
        let premature = Float(entranceAlpha * Double(Float(pulse)))
        #expect(base.cells[0][0].alpha == 1)
        #expect(expected.bitPattern != premature.bitPattern)

        let frame = Self.animated(base, entrance: entrance, ongoing: .pulse(period: 1, depth: 0.8)).grid(at: time)
        #expect(frame.cells[0][0].alpha.bitPattern == expected.bitPattern)
    }

    @Test func publicOverlayResolvesNonfiniteAndNegativeTimeBeforeEvaluation() {
        let cell = ASCIICell(character: "#", displayColor: .zero, alpha: 0.75, brightness: 0.5)
        let grid = ASCIIGrid(cells: [[cell, cell], [cell]], colorSpace: .sRGB)
        for pattern in [OngoingPattern.pulse(period: 1, depth: 0.8), .wave(amplitude: 0.4, frequency: 1, direction: .diagonal)] {
            let expected = grid.applyingOngoingPattern(pattern, at: 0)
            for time in [-1, Double.nan, .infinity, -.infinity] {
                #expect(grid.applyingOngoingPattern(pattern, at: time).cells == expected.cells)
            }
        }
    }

    // Keep this oracle's multiplication in release builds. Folding alpha * 1
    // to identity preserves a signaling NaN instead of quieting it.
    @_optimize(none)
    private static func scalarMultiply(_ alpha: Float, _ multiplier: Float) -> Float {
        alpha * multiplier
    }

    private static func scalarPulse(period: Double, depth: Double, time: Double) -> Double {
        // Frozen scalar expression from the pre-change evaluator.
        let resolvedDepth = depth.isFinite ? min(1, max(0, depth)) : 1
        let value = 1 - resolvedDepth / 2 + (resolvedDepth / 2) * sin(2 * Double.pi * time / period + Double.pi / 2)
        return resolvedDepth == 0 || !value.isFinite ? 1 : min(1, max(0, value))
    }

    private static func expectGrid(
        _ actual: ASCIIGrid,
        matches base: ASCIIGrid,
        alpha: (Int, Int, ASCIICell) -> Float
    ) {
        #expect(actual.cells.map(\.count) == base.cells.map(\.count))
        #expect(actual.columns == base.columns && actual.rows == base.rows)
        #expect(actual.colorSpace == base.colorSpace && actual.composition == base.composition)
        #expect(actual.maskUsesHardEdges == base.maskUsesHardEdges)
        #expect(actual.maskGroundColor?.components == base.maskGroundColor?.components)
        if case .originalImage(let image, .fit) = actual.maskFallback,
            case .originalImage(let source, .fit) = base.maskFallback
        {
            #expect(ObjectIdentifier(image) == ObjectIdentifier(source))
        } else {
            Issue.record("original-image fallback or fit sizing was lost")
        }
        for (row, lines) in zip(actual.cells, base.cells).enumerated() {
            for (column, cells) in zip(lines.0, lines.1).enumerated() {
                let (cell, original) = cells
                #expect(cell.alpha.bitPattern == alpha(column, row, original).bitPattern)
                #expect(cell.character == original.character)
                #expect(cell.displayColor.x.bitPattern == original.displayColor.x.bitPattern)
                #expect(cell.displayColor.y.bitPattern == original.displayColor.y.bitPattern)
                #expect(cell.displayColor.z.bitPattern == original.displayColor.z.bitPattern)
                #expect(cell.brightness.bitPattern == original.brightness.bitPattern)
                #expect(cell.coverage.bitPattern == original.coverage.bitPattern)
            }
        }
    }

    private static func grid(ragged: Bool) throws -> ASCIIGrid {
        let alphas: [Float] = [1, 0, -0.0, 0.25, -1, 2, .infinity, -.infinity, .nan, .signalingNaN]
        let row = alphas.enumerated().map { index, alpha in
            ASCIICell(
                character: index.isMultiple(of: 2) ? "#" : "+",
                displayColor: SIMD3<Float>(0.1, 0.3, Float(index) / 10), alpha: alpha, brightness: 0.6,
                coverage: Float(index % 5) / 4)
        }
        return ASCIIGrid(
            cells: ragged ? [row, [], Array(row.prefix(3))] : [row, Array(row.reversed())],
            colorSpace: .sRGB, composition: .extendedLinearPerGamut,
            maskFallback: .originalImage(try image(), sizing: .fit),
            maskGroundColor: CGColor(gray: 0.2, alpha: 1), maskUsesHardEdges: true
        )
    }

    private static func animated(_ base: ASCIIGrid, entrance: EntrancePattern?, ongoing: OngoingPattern) -> AnimatedASCIIGrid {
        let snapshot = CharacterSetSnapshot(characters: ["#", "+"])
        let candidates = ContiguousArray(base.cells.joined().map { UInt16($0.character == "#" ? 0 : 1) })
        let schedule = ScheduleBuilder.build(
            baseGrid: base, candidates: candidates, candidateStride: 1,
            candidateCounts: ContiguousArray(repeating: 1, count: candidates.count),
            characterSet: snapshot,
            options: AnimationOptions(duration: 1, cycling: nil, entrance: entrance, ongoing: ongoing)
        )
        return AnimatedASCIIGrid(baseGrid: base, duration: 1, seed: 0, schedule: schedule, characterSet: snapshot)
    }

    private static func image() throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try #require(context.makeImage())
    }
}
