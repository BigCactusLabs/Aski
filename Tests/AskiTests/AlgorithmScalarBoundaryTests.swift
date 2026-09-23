import Foundation
import Testing
@_spi(AskiResearch) @testable import Aski

/// ASKI-33: public matching scalars must resolve before an algorithm converts
/// them to an integer.
@Suite struct AlgorithmScalarBoundaryTests {
    @Test func densityNonFiniteAndExtremeFiniteValuesMatchTheSanitizedPublicRender() {
        let atZero = render(density: 0)
        let atOne = render(density: 1)

        for value in [Float.nan, .infinity, -.infinity, -Float.greatestFiniteMagnitude] {
            #expect(bitIdentical(render(density: value), atZero), "density=\(value)")
        }
        #expect(bitIdentical(render(density: .greatestFiniteMagnitude), atOne))
    }

    @Test func validMatchingScalarsMatchThePreChangeGolden() {
        let density = [Float(0), 0.5, 1].map { fingerprint(render(density: $0)) }
        #expect(density == [3_953_831_385_894_595_474, 6_780_983_386_489_683_440, 15_902_162_367_071_341_054])
    }

    private func render(
        density: Float = 0,
        algorithm: ASCIIAlgorithm = .logPolar
    ) -> ASCIIGrid {
        ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor,
            algorithm: algorithm,
            options: RenderingOptions(density: density)
        ).convert(TestImages.horizontalGradient(width: 160, height: 80), columns: 24)
    }

    private func bitIdentical(_ lhs: ASCIIGrid, _ rhs: ASCIIGrid) -> Bool {
        guard lhs.cells.count == rhs.cells.count else { return false }
        for (leftRow, rightRow) in zip(lhs.cells, rhs.cells) {
            guard leftRow.count == rightRow.count else { return false }
            for (left, right) in zip(leftRow, rightRow) {
                guard
                    left.character == right.character,
                    left.displayColor.x.bitPattern == right.displayColor.x.bitPattern,
                    left.displayColor.y.bitPattern == right.displayColor.y.bitPattern,
                    left.displayColor.z.bitPattern == right.displayColor.z.bitPattern,
                    left.alpha.bitPattern == right.alpha.bitPattern,
                    left.brightness.bitPattern == right.brightness.bitPattern,
                    left.coverage.bitPattern == right.coverage.bitPattern
                else { return false }
            }
        }
        return true
    }

    private func fingerprint(_ grid: ASCIIGrid) -> UInt64 {
        let serialized = grid.cells.flatMap { $0 }.map { cell in
            "\(cell.character)|\(cell.displayColor.x.bitPattern)|\(cell.displayColor.y.bitPattern)|\(cell.displayColor.z.bitPattern)|\(cell.alpha.bitPattern)|\(cell.brightness.bitPattern)|\(cell.coverage.bitPattern)"
        }.joined(separator: ",")
        return fingerprint(serialized.utf8)
    }

    private func fingerprint(_ bytes: String.UTF8View) -> UInt64 {
        bytes.reduce(14_695_981_039_346_656_037) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
