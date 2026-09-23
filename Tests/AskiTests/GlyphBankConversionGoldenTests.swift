import Testing

@testable import Aski

/// ASKI-71: selection and rendered-cell bytes captured before glyph ownership
/// moves behind the internal bank. The fixture and matrix are deliberately
/// independent of the bank implementation.
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
        "blocks/dotMatrix": 17_880_057_928_480_335_288,
        "blocks/logPolar": 16_420_574_259_635_996_134,
        "braille/dotMatrix": 10_497_106_337_717_151_888,
        "braille/logPolar": 6_229_418_005_544_245_927,
        "cross/dotMatrix": 818_763_795_777_019_728,
        "cross/logPolar": 11_382_216_875_173_112_104,
        "diagonal/dotMatrix": 6_323_816_355_091_133_352,
        "diagonal/logPolar": 11_382_216_875_173_112_104,
        "diamond/dotMatrix": 8_685_068_120_567_966_428,
        "diamond/logPolar": 11_382_216_875_173_112_104,
        "dots/dotMatrix": 8_718_204_461_934_864_732,
        "dots/logPolar": 11_382_216_875_173_112_104,
        "lines/dotMatrix": 4_556_211_967_393_641_184,
        "lines/logPolar": 16_840_191_759_657_335_000,
        "minimal/dotMatrix": 623_767_257_914_818_696,
        "minimal/logPolar": 11_382_216_875_173_112_104,
        "mixed/dotMatrix": 3_227_114_315_477_771_464,
        "mixed/logPolar": 15_635_137_281_816_077_016,
        "standard/dotMatrix": 578_668_299_132_216_088,
        "standard/logPolar": 5_274_591_087_475_449_036,
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
