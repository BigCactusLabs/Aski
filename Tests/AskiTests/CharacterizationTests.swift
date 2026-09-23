import CoreGraphics
import Numerics
import Testing
import simd
@testable import Aski

/// Frozen pre-A1 golden output for the legacy encoded-average sampling path.
/// Captured against `DefaultConverter()` before the kernel-extraction refactor
/// began, when `.encodedAverageLegacy` was the implicit default. Now that the
/// default is `.linearLightAverage`, this suite pins the legacy policy
/// explicitly to guard against regressions in the legacy code path.
/// The character must match exactly; floats are compared with ε = 1e-5 to
/// absorb harmless float reassociation drift from loop-order changes.
@Suite struct CharacterizationTests {
    private static let goldenColumns = 8
    private static let goldenImageWidth = 64
    private static let goldenImageHeight = 64

    private struct GoldenCell {
        let character: Character
        let displayColor: SIMD3<Float>
        let alpha: Float
        let brightness: Float
    }

    private static let golden: [[GoldenCell]] = [
        // row 0
        [
            GoldenCell(character: ".", displayColor: SIMD3(0.043137, 0.043137, 0.043137), alpha: 1.000000, brightness: 0.149577),
            GoldenCell(character: "-", displayColor: SIMD3(0.172549, 0.172549, 0.172549), alpha: 1.000000, brightness: 0.293128),
            GoldenCell(character: "*", displayColor: SIMD3(0.303922, 0.303921, 0.303922), alpha: 1.000000, brightness: 0.422083),
            GoldenCell(character: "t", displayColor: SIMD3(0.433333, 0.433333, 0.433333), alpha: 1.000000, brightness: 0.539972),
            GoldenCell(character: "z", displayColor: SIMD3(0.566667, 0.566667, 0.566667), alpha: 1.000000, brightness: 0.655004),
            GoldenCell(character: "e", displayColor: SIMD3(0.696078, 0.696078, 0.696078), alpha: 1.000000, brightness: 0.761985),
            GoldenCell(character: "m", displayColor: SIMD3(0.829412, 0.829412, 0.829412), alpha: 1.000000, brightness: 0.868404),
            GoldenCell(character: "#", displayColor: SIMD3(0.956863, 0.956863, 0.956863), alpha: 1.000000, brightness: 0.967153),
        ],
        // row 1
        [
            GoldenCell(character: ".", displayColor: SIMD3(0.043137, 0.043137, 0.043137), alpha: 1.000000, brightness: 0.149577),
            GoldenCell(character: "-", displayColor: SIMD3(0.172549, 0.172549, 0.172549), alpha: 1.000000, brightness: 0.293128),
            GoldenCell(character: "*", displayColor: SIMD3(0.303922, 0.303921, 0.303922), alpha: 1.000000, brightness: 0.422083),
            GoldenCell(character: "t", displayColor: SIMD3(0.433333, 0.433333, 0.433333), alpha: 1.000000, brightness: 0.539972),
            GoldenCell(character: "z", displayColor: SIMD3(0.566667, 0.566667, 0.566667), alpha: 1.000000, brightness: 0.655004),
            GoldenCell(character: "e", displayColor: SIMD3(0.696078, 0.696078, 0.696078), alpha: 1.000000, brightness: 0.761985),
            GoldenCell(character: "m", displayColor: SIMD3(0.829412, 0.829412, 0.829412), alpha: 1.000000, brightness: 0.868404),
            GoldenCell(character: "#", displayColor: SIMD3(0.956863, 0.956863, 0.956863), alpha: 1.000000, brightness: 0.967153),
        ],
        // row 2
        [
            GoldenCell(character: ".", displayColor: SIMD3(0.043137, 0.043137, 0.043137), alpha: 1.000000, brightness: 0.149577),
            GoldenCell(character: "-", displayColor: SIMD3(0.172549, 0.172549, 0.172549), alpha: 1.000000, brightness: 0.293128),
            GoldenCell(character: "*", displayColor: SIMD3(0.303922, 0.303921, 0.303922), alpha: 1.000000, brightness: 0.422083),
            GoldenCell(character: "t", displayColor: SIMD3(0.433333, 0.433333, 0.433333), alpha: 1.000000, brightness: 0.539972),
            GoldenCell(character: "z", displayColor: SIMD3(0.566667, 0.566667, 0.566667), alpha: 1.000000, brightness: 0.655004),
            GoldenCell(character: "e", displayColor: SIMD3(0.696078, 0.696078, 0.696078), alpha: 1.000000, brightness: 0.761985),
            GoldenCell(character: "m", displayColor: SIMD3(0.829412, 0.829412, 0.829412), alpha: 1.000000, brightness: 0.868404),
            GoldenCell(character: "#", displayColor: SIMD3(0.956863, 0.956863, 0.956863), alpha: 1.000000, brightness: 0.967153),
        ],
    ]

    @Test func legacyPolicyMatchesPreA1Golden() {
        let image = TestImages.horizontalGradient(
            width: Self.goldenImageWidth,
            height: Self.goldenImageHeight
        )
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor,
            colorSampling: .encodedAverageLegacy
        )
        let grid = converter.convert(image, columns: Self.goldenColumns)

        #expect(grid.rows == Self.golden.count)
        #expect(grid.columns == Self.goldenColumns)

        for (rowIndex, expectedRow) in Self.golden.enumerated() {
            for (colIndex, expected) in expectedRow.enumerated() {
                let actual = grid.cells[rowIndex][colIndex]
                #expect(
                    actual.character == expected.character,
                    "char mismatch at [\(rowIndex)][\(colIndex)]")
                #expect(actual.displayColor.x.isApproximatelyEqual(to: expected.displayColor.x, absoluteTolerance: 1e-5))
                #expect(actual.displayColor.y.isApproximatelyEqual(to: expected.displayColor.y, absoluteTolerance: 1e-5))
                #expect(actual.displayColor.z.isApproximatelyEqual(to: expected.displayColor.z, absoluteTolerance: 1e-5))
                #expect(actual.alpha.isApproximatelyEqual(to: expected.alpha, absoluteTolerance: 1e-5))
                #expect(actual.brightness.isApproximatelyEqual(to: expected.brightness, absoluteTolerance: 1e-5))
            }
        }
    }
}
