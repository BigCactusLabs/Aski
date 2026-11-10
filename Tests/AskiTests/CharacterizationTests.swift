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
/// Re-recorded for ASKI-1, when sources larger than the conversion budget moved
/// from the ImageIO thumbnail to direct resampling.
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
            GoldenCell(character: ".", displayColor: SIMD3(0.054902, 0.054902, 0.054902), alpha: 1.000000, brightness: 0.163758),
            GoldenCell(character: "-", displayColor: SIMD3(0.182353, 0.182353, 0.182353), alpha: 1.000000, brightness: 0.303189),
            GoldenCell(character: "*", displayColor: SIMD3(0.309804, 0.309804, 0.309804), alpha: 1.000000, brightness: 0.427608),
            GoldenCell(character: "t", displayColor: SIMD3(0.435294, 0.435294, 0.435294), alpha: 1.000000, brightness: 0.541706),
            GoldenCell(character: "z", displayColor: SIMD3(0.564706, 0.564706, 0.564706), alpha: 1.000000, brightness: 0.653351),
            GoldenCell(character: "e", displayColor: SIMD3(0.690196, 0.690196, 0.690196), alpha: 1.000000, brightness: 0.757207),
            GoldenCell(character: "m", displayColor: SIMD3(0.817647, 0.817647, 0.817647), alpha: 1.000000, brightness: 0.859150),
            GoldenCell(character: "#", displayColor: SIMD3(0.945098, 0.945098, 0.945098), alpha: 1.000000, brightness: 0.958147),
        ],
        // row 1
        [
            GoldenCell(character: ".", displayColor: SIMD3(0.054902, 0.054902, 0.054902), alpha: 1.000000, brightness: 0.163758),
            GoldenCell(character: "-", displayColor: SIMD3(0.182353, 0.182353, 0.182353), alpha: 1.000000, brightness: 0.303189),
            GoldenCell(character: "*", displayColor: SIMD3(0.309804, 0.309804, 0.309804), alpha: 1.000000, brightness: 0.427608),
            GoldenCell(character: "t", displayColor: SIMD3(0.435294, 0.435294, 0.435294), alpha: 1.000000, brightness: 0.541706),
            GoldenCell(character: "z", displayColor: SIMD3(0.564706, 0.564706, 0.564706), alpha: 1.000000, brightness: 0.653351),
            GoldenCell(character: "e", displayColor: SIMD3(0.690196, 0.690196, 0.690196), alpha: 1.000000, brightness: 0.757207),
            GoldenCell(character: "m", displayColor: SIMD3(0.817647, 0.817647, 0.817647), alpha: 1.000000, brightness: 0.859150),
            GoldenCell(character: "#", displayColor: SIMD3(0.945098, 0.945098, 0.945098), alpha: 1.000000, brightness: 0.958147),
        ],
        // row 2
        [
            GoldenCell(character: ".", displayColor: SIMD3(0.054902, 0.054902, 0.054902), alpha: 1.000000, brightness: 0.163758),
            GoldenCell(character: "-", displayColor: SIMD3(0.182353, 0.182353, 0.182353), alpha: 1.000000, brightness: 0.303189),
            GoldenCell(character: "*", displayColor: SIMD3(0.309804, 0.309804, 0.309804), alpha: 1.000000, brightness: 0.427608),
            GoldenCell(character: "t", displayColor: SIMD3(0.435294, 0.435294, 0.435294), alpha: 1.000000, brightness: 0.541706),
            GoldenCell(character: "z", displayColor: SIMD3(0.564706, 0.564706, 0.564706), alpha: 1.000000, brightness: 0.653351),
            GoldenCell(character: "e", displayColor: SIMD3(0.690196, 0.690196, 0.690196), alpha: 1.000000, brightness: 0.757207),
            GoldenCell(character: "m", displayColor: SIMD3(0.817647, 0.817647, 0.817647), alpha: 1.000000, brightness: 0.859150),
            GoldenCell(character: "#", displayColor: SIMD3(0.945098, 0.945098, 0.945098), alpha: 1.000000, brightness: 0.958147),
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
