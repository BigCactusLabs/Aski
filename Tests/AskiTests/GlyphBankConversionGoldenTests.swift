import Testing

@testable import Aski

/// ASKI-71: selection and rendered-cell bytes captured before glyph ownership
/// moves behind the internal bank. The fixture and matrix are deliberately
/// independent of the bank implementation. Re-recorded for ASKI-1, when sources
/// larger than the conversion budget moved to direct resampling.
@Suite struct GlyphBankConversionGoldenTests {
    @Test func everyBuiltInAndAlgorithmMatchesThePreMigrationDigest() {
        let image = TestImages.structuredPortraitProxy(width: 240, height: 320)
        var actual: [String: UInt64] = [:]

        for (setName, characterSet) in Self.characterSets {
            for (algorithmName, algorithm) in Self.algorithms {
                let converter = ASCIIConverter(
                    characterSet: characterSet,
                    palette: BuiltInPalette.fullColor,
                    algorithm: algorithm,
                    colorSpace: .sRGB
                )
                let grid = converter.convert(image, columns: 24)
                actual["\(setName)/\(algorithmName)"] = Self.digest(grid)
            }
        }

        #expect(actual.count == 20)
        let dotMatrixDigests = actual.filter { $0.key.hasSuffix("/dotMatrix") }.map(\.value)
        let logPolarDigests = actual.filter { $0.key.hasSuffix("/logPolar") }.map(\.value)
        #expect(dotMatrixDigests.count == 10)
        #expect(Set(dotMatrixDigests).count == 10)
        #expect(logPolarDigests.count == 10)
        #expect(Set(logPolarDigests).count == 6)
        for key in Self.expected.keys.sorted() {
            #expect(actual[key] == Self.expected[key], "\(key) output moved")
        }
    }

    private static let characterSets: [(String, StandardCharacterSet)] = [
        ("standard", .standard),
        ("minimal", .minimal),
        ("blocks", .blocks),
        ("dots", .dots),
        ("lines", .lines),
        ("diagonal", .diagonal),
        ("cross", .cross),
        ("diamond", .diamond),
        ("mixed", .mixed),
        ("braille", .braille),
    ]

    private static let algorithms: [(String, ASCIIAlgorithm)] = [
        ("logPolar", .logPolar),
        ("dotMatrix", .dotMatrix),
    ]

    private static let expected: [String: UInt64] = [
        "blocks/dotMatrix": 6_155_001_706_851_922_987,
        "blocks/logPolar": 15_142_091_769_664_063_705,
        "braille/dotMatrix": 10_925_640_482_195_603_315,
        "braille/logPolar": 6_841_031_301_294_466_235,
        "cross/dotMatrix": 4_110_848_941_932_915_335,
        "cross/logPolar": 10_691_118_721_304_012_055,
        "diagonal/dotMatrix": 6_336_918_789_892_181_975,
        "diagonal/logPolar": 10_691_118_721_304_012_055,
        "diamond/dotMatrix": 8_289_470_158_390_172_331,
        "diamond/logPolar": 10_691_118_721_304_012_055,
        "dots/dotMatrix": 17_380_711_769_955_295_427,
        "dots/logPolar": 10_691_118_721_304_012_055,
        "lines/dotMatrix": 2_568_444_975_854_573_015,
        "lines/logPolar": 4_945_830_320_128_152_719,
        "minimal/dotMatrix": 6_725_532_002_683_423_747,
        "minimal/logPolar": 10_691_118_721_304_012_055,
        "mixed/dotMatrix": 15_833_333_427_314_417_451,
        "mixed/logPolar": 7_579_819_307_625_272_211,
        "standard/dotMatrix": 15_013_198_537_264_470_435,
        "standard/logPolar": 13_774_220_104_195_781_987,
    ]

    private static func digest(_ grid: ASCIIGrid) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ value: UInt64) {
            hash = (hash ^ value) &* 0x0000_0100_0000_01B3
        }

        mix(UInt64(grid.rows))
        mix(UInt64(grid.columns))
        for row in grid.cells {
            mix(UInt64(row.count))
            for cell in row {
                for scalar in cell.character.unicodeScalars { mix(UInt64(scalar.value)) }
                mix(0xFFFF_FFFF)
                mix(UInt64(cell.displayColor.x.bitPattern))
                mix(UInt64(cell.displayColor.y.bitPattern))
                mix(UInt64(cell.displayColor.z.bitPattern))
                mix(UInt64(cell.alpha.bitPattern))
                mix(UInt64(cell.brightness.bitPattern))
                mix(UInt64(cell.coverage.bitPattern))
            }
        }
        return hash
    }
}
