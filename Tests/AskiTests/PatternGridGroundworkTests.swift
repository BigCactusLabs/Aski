import CoreGraphics
import Foundation
import Testing
@testable import Aski

/// ASKI-91: a neutral shortcut must preserve the current multiply-by-one
/// semantics, not just ordinary finite alpha. Native Apple-platform tests.
@Suite struct PatternGridGroundworkTests {
    @Test func neutralOverlayPreservesRaggedCellsAndMaskMetadata() throws {
        let alphas: [Float] = [0, -0.0, 0.25, 1, -1, 2, .infinity, -.infinity, .nan, .signalingNaN]
        let row = alphas.map {
            ASCIICell(character: "#", displayColor: SIMD3<Float>(0.1, 0.3, 0.7), alpha: $0, brightness: 0.6, coverage: 0.25)
        }
        let source = try Self.image()
        let ground = CGColor(gray: 0.2, alpha: 1)
        let base = ASCIIGrid(
            cells: [row, [], Array(row.prefix(3))], colorSpace: .sRGB,
            composition: .extendedLinearPerGamut,
            maskFallback: .originalImage(source, sizing: .fit), maskGroundColor: ground, maskUsesHardEdges: true
        )
        for pattern in [OngoingPattern.pulse(period: 1, depth: 0), .wave(amplitude: 0, frequency: 1)] {
            let actual = base.applyingOngoingPattern(pattern, at: .infinity)
            #expect(actual.cells.map(\.count) == [10, 0, 3])
            #expect(actual.columns == base.columns && actual.rows == base.rows)
            #expect(actual.colorSpace == base.colorSpace && actual.composition == base.composition)
            #expect(actual.maskUsesHardEdges)
            #expect(actual.maskGroundColor?.components == ground.components)
            if case .originalImage(let image, let sizing) = actual.maskFallback {
                #expect(ObjectIdentifier(image) == ObjectIdentifier(source))
                if case .fit = sizing {} else { Issue.record("fallback sizing changed") }
            } else {
                Issue.record("original-image fallback was lost")
            }
            for (actualRow, originalRow) in zip(actual.cells, base.cells) {
                for (cell, original) in zip(actualRow, originalRow) {
                    let expectedAlpha = original.alpha * Float(1)
                    #expect(cell.alpha.bitPattern == expectedAlpha.bitPattern)
                    #expect(cell.character == original.character && cell.displayColor == original.displayColor)
                    #expect(cell.brightness.bitPattern == original.brightness.bitPattern)
                    #expect(cell.coverage.bitPattern == original.coverage.bitPattern)
                }
            }
        }
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
