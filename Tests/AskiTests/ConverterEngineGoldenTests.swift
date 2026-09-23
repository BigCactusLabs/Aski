import CoreGraphics
import Testing

@_spi(AskiResearch) @testable import Aski

/// ASKI-72: exact ordinary, ranked, and residual fingerprints captured before
/// the three converter loops were consolidated. These tests describe only the
/// converter's observable results and do not depend on the shared-engine shape.
@Suite(.serialized) struct ConverterEngineGoldenTests {
    @Test func ordinaryRankedAndResidualSurfacesMatchFrozenFingerprints() {
        let first = Self.fingerprints()
        let second = Self.fingerprints()

        #expect(first == second, "repeated conversions must be deterministic")
        #expect(first.count == 16)
        #expect(Set(first.keys) == Set(Self.expected.keys))

        for key in Self.expected.keys.sorted() {
            #expect(first[key] == Self.expected[key], "\(key) output moved")
        }
    }

    @Test func plainCaptureStoresOnlyItsConcreteKernel() {
        #expect(
            MemoryLayout<PlainCellCapture<LogPolarKernel>>.size
                == MemoryLayout<LogPolarKernel>.size
        )
        #expect(
            MemoryLayout<PlainCellCapture<DotMatrixKernel>>.size
                == MemoryLayout<DotMatrixKernel>.size
        )
    }

    private static func fingerprints() -> [String: UInt64] {
        let image = TestImages.structuredPortraitProxy(width: 160, height: 120)
        let mask = MaskOptions(
            image: TestImages.verticalSplitMask(width: 31, height: 17),
            fallback: .character(
                "?",
                color: CGColor(srgbRed: 0.8, green: 0.2, blue: 0.1, alpha: 0.7)
            ),
            groundColor: CGColor(srgbRed: 0.1, green: 0.3, blue: 0.6, alpha: 0.5),
            softEdges: false,
            invert: true
        )
        var result: [String: UInt64] = [:]

        let logSerial = makeConverter(algorithm: .logPolar, mode: .forcedSerial)
        let logParallel = makeConverter(algorithm: .logPolar, mode: .forcedParallel)
        let logPlainSerial = logSerial.convert(image, columns: 24)
        let logPlainParallel = logParallel.convert(image, columns: 24)
        #expect(digest(logPlainSerial) == digest(logPlainParallel))
        result["log/plain/serial"] = digest(logPlainSerial)
        result["log/plain/parallel"] = digest(logPlainParallel)
        let logMasked = logParallel.convert(image, columns: 24, mask: mask)
        assertMaskMetadata(logMasked, equals: mask)
        result["log/plain/parallel/masked"] = digest(logMasked)

        let logRankedOneSerial = logSerial.convertWithRankedCandidates(
            image, columns: 24, candidateStride: 1)
        let logRankedOneParallel = logParallel.convertWithRankedCandidates(
            image, columns: 24, candidateStride: 1)
        #expect(digest(logRankedOneSerial) == digest(logRankedOneParallel))
        result["log/ranked/stride1/serial"] = digest(logRankedOneSerial)

        let logRankedSixSerial = logSerial.convertWithRankedCandidates(
            image, columns: 24, candidateStride: 6, mask: mask)
        let logRankedSixParallel = logParallel.convertWithRankedCandidates(
            image, columns: 24, candidateStride: 6, mask: mask)
        #expect(digest(logRankedSixSerial) == digest(logRankedSixParallel))
        #expect(logRankedSixSerial.candidateCounts.contains { $0 > 1 })
        result["log/ranked/stride6/serial/masked"] = digest(logRankedSixSerial)
        result["log/ranked/stride6/parallel/masked"] = digest(logRankedSixParallel)

        let logResidualSerial = logSerial.convertWithResidual(image, columns: 24)
        let logResidualParallel = logParallel.convertWithResidual(image, columns: 24)
        #expect(digest(logResidualSerial) == digest(logResidualParallel))
        #expect(logResidualSerial.residual.allSatisfy { $0.isFinite })
        result["log/residual/serial"] = digest(logResidualSerial)
        result["log/residual/parallel"] = digest(logResidualParallel)

        let dotSerial = makeConverter(algorithm: .dotMatrix, mode: .forcedSerial)
        let dotForcedParallel = makeConverter(algorithm: .dotMatrix, mode: .forcedParallel)
        let dotPlainSerial = dotSerial.convert(image, columns: 24)
        let dotPlainForcedParallel = dotForcedParallel.convert(image, columns: 24)
        #expect(digest(dotPlainSerial) == digest(dotPlainForcedParallel))
        result["dot/plain/serial"] = digest(dotPlainSerial)
        result["dot/plain/forcedParallel"] = digest(dotPlainForcedParallel)
        let dotMasked = dotSerial.convert(image, columns: 24, mask: mask)
        assertMaskMetadata(dotMasked, equals: mask)
        result["dot/plain/serial/masked"] = digest(dotMasked)

        let dotRankedOne = dotSerial.convertWithRankedCandidates(
            image, columns: 24, candidateStride: 1)
        let dotRankedOneForcedParallel = dotForcedParallel.convertWithRankedCandidates(
            image, columns: 24, candidateStride: 1)
        #expect(digest(dotRankedOne) == digest(dotRankedOneForcedParallel))
        #expect(dotRankedOne.candidateCounts.allSatisfy { $0 == 1 })
        result["dot/ranked/stride1"] = digest(dotRankedOne)
        let dotRankedSix = dotSerial.convertWithRankedCandidates(
            image, columns: 24, candidateStride: 6)
        let dotRankedSixForcedParallel = dotForcedParallel.convertWithRankedCandidates(
            image, columns: 24, candidateStride: 6)
        #expect(digest(dotRankedSix) == digest(dotRankedSixForcedParallel))
        #expect(dotRankedSix.candidateCounts.allSatisfy { $0 == 1 })
        #expect(
            stride(from: 0, to: dotRankedSix.candidates.count, by: 6).allSatisfy { offset in
                dotRankedSix.candidates[(offset + 1)..<(offset + 6)].allSatisfy {
                    $0 == dotRankedSix.candidates[offset]
                }
            }
        )
        result["dot/ranked/stride6"] = digest(dotRankedSix)

        let dotResidual = dotSerial.convertWithResidual(image, columns: 24)
        let dotResidualForcedParallel = dotForcedParallel.convertWithResidual(image, columns: 24)
        #expect(digest(dotResidual) == digest(dotResidualForcedParallel))
        #expect(dotResidual.residual.allSatisfy { $0.isNaN })
        result["dot/residual/nan"] = digest(dotResidual)

        var invalidHasher = WordHasher()
        invalidHasher.mix(grid: logSerial.convert(image, columns: 0))
        invalidHasher.mix(ranked: logSerial.convertWithRankedCandidates(image, columns: 0, candidateStride: 6))
        invalidHasher.mix(residual: logSerial.convertWithResidual(image, columns: 0))
        result["branches/invalid-columns"] = invalidHasher.value

        var failedPreparationHasher = WordHasher()
        failedPreparationHasher.mix(grid: logSerial.convert(image, columns: .max))
        failedPreparationHasher.mix(
            ranked: logSerial.convertWithRankedCandidates(image, columns: .max, candidateStride: 6))
        failedPreparationHasher.mix(residual: logSerial.convertWithResidual(image, columns: .max))
        result["branches/failed-preparation"] = failedPreparationHasher.value

        return result
    }

    private static func makeConverter(
        algorithm: ASCIIAlgorithm,
        mode: GridRowWalk.Mode
    ) -> DefaultConverter {
        var converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor,
            algorithm: algorithm,
            colorSpace: .sRGB
        )
        converter.rowWalkMode = mode
        return converter
    }

    private static func assertMaskMetadata(_ grid: ASCIIGrid, equals mask: MaskOptions) {
        #expect(grid.maskUsesHardEdges == !mask.softEdges)
        assertSameColor(grid.maskGroundColor, mask.groundColor)
        if case .character(let character, let color) = grid.maskFallback,
            case .character(let expectedCharacter, let expectedColor) = mask.fallback
        {
            #expect(character == expectedCharacter)
            assertSameColor(color, expectedColor)
        } else {
            Issue.record("character fallback metadata was not preserved")
        }
    }

    private static func assertSameColor(_ actual: CGColor?, _ expected: CGColor?) {
        #expect(actual?.colorSpace?.name == expected?.colorSpace?.name)
        #expect(actual?.colorSpace?.model == expected?.colorSpace?.model)
        #expect(actual?.components == expected?.components)
    }

    private static let expected: [String: UInt64] = [
        "branches/failed-preparation": 8_282_888_707_755_408_745,
        "branches/invalid-columns": 8_282_888_707_755_408_745,
        "dot/plain/forcedParallel": 6_429_871_333_101_551_316,
        "dot/plain/serial": 6_429_871_333_101_551_316,
        "dot/plain/serial/masked": 16_272_798_101_133_468_325,
        "dot/ranked/stride1": 17_912_684_743_978_736_175,
        "dot/ranked/stride6": 1_821_696_342_168_807_990,
        "dot/residual/nan": 193_570_761_966_645_244,
        "log/plain/parallel": 3_698_835_258_009_606_004,
        "log/plain/parallel/masked": 12_519_869_327_797_796_533,
        "log/plain/serial": 3_698_835_258_009_606_004,
        "log/ranked/stride1/serial": 13_422_579_521_392_179_191,
        "log/ranked/stride6/parallel/masked": 11_547_507_569_938_779_841,
        "log/ranked/stride6/serial/masked": 11_547_507_569_938_779_841,
        "log/residual/parallel": 3_964_614_954_471_016_525,
        "log/residual/serial": 3_964_614_954_471_016_525,
    ]

    private static func digest(_ grid: ASCIIGrid) -> UInt64 {
        var hasher = WordHasher()
        hasher.mix(grid: grid)
        return hasher.value
    }

    private static func digest(_ ranked: RankedConversionResult) -> UInt64 {
        var hasher = WordHasher()
        hasher.mix(ranked: ranked)
        return hasher.value
    }

    private static func digest(_ residual: (grid: ASCIIGrid, residual: [Float])) -> UInt64 {
        var hasher = WordHasher()
        hasher.mix(residual: residual)
        return hasher.value
    }

    private struct WordHasher {
        private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func mix(_ word: UInt64) {
            value = (value ^ word) &* 0x0000_0100_0000_01B3
        }

        mutating func mix(character: Character) {
            for scalar in character.unicodeScalars { mix(UInt64(scalar.value)) }
            mix(0xFFFF_FFFF)
        }

        mutating func mix(grid: ASCIIGrid) {
            mix(UInt64(grid.rows))
            mix(UInt64(grid.columns))
            mix(grid.colorSpace == .sRGB ? 0 : 1)
            mix(grid.composition == .encodedDisplay8Bit ? 0 : 1)
            mix(grid.maskUsesHardEdges ? 1 : 0)
            mix(grid.maskGroundColor == nil ? 0 : 1)
            switch grid.maskFallback {
            case nil:
                mix(0)
            case .transparent:
                mix(1)
            case .solid:
                mix(2)
            case .originalImage(let image, let sizing):
                mix(3)
                mix(UInt64(image.width))
                mix(UInt64(image.height))
                switch sizing {
                case .fill: mix(0)
                case .fit: mix(1)
                case .stretch: mix(2)
                }
            case .character(let character, let color):
                mix(4)
                mix(character: character)
                mix(color == nil ? 0 : 1)
            }
            for row in grid.cells {
                mix(UInt64(row.count))
                for cell in row {
                    mix(character: cell.character)
                    mix(UInt64(cell.displayColor.x.bitPattern))
                    mix(UInt64(cell.displayColor.y.bitPattern))
                    mix(UInt64(cell.displayColor.z.bitPattern))
                    mix(UInt64(cell.alpha.bitPattern))
                    mix(UInt64(cell.brightness.bitPattern))
                    mix(UInt64(cell.coverage.bitPattern))
                }
            }
        }

        mutating func mix(ranked: RankedConversionResult) {
            mix(grid: ranked.grid)
            mix(UInt64(ranked.candidateStride))
            mix(UInt64(ranked.candidates.count))
            for candidate in ranked.candidates { mix(UInt64(candidate)) }
            mix(UInt64(ranked.candidateCounts.count))
            for count in ranked.candidateCounts { mix(UInt64(count)) }
        }

        mutating func mix(residual result: (grid: ASCIIGrid, residual: [Float])) {
            mix(grid: result.grid)
            mix(UInt64(result.residual.count))
            for residual in result.residual { mix(UInt64(residual.bitPattern)) }
        }
    }
}
