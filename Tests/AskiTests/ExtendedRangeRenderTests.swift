import Testing
import CoreGraphics
import Foundation
@_spi(AskiResearch) import Aski
@testable import AskiHDRLab

/// Step 2 (ASTSK-10): the `@_spi(AskiResearch) renderExtendedRangeImage` path —
/// dimension parity with the SDR render, linear-domain emission that exceeds 1.0
/// only where it should, the monochrome no-bloom pathology, and the opaque/full-
/// coverage rejection contract. Float values are read straight from the produced
/// half-float image's data provider by `HDRArtifacts.floatStats` (the lab's own
/// G4 scanner — no re-implementation here), so the assertions see exactly what the
/// renderer wrote.
@Suite struct ExtendedRangeRenderTests {
    static let font = ASCIIFont.system(size: 12)
    static let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

    static func grid(_ cells: [[ASCIICell]]) -> ASCIIGrid {
        ASCIIGrid(cells: cells, colorSpace: .sRGB)
    }

    static func uniformGrid(displayColor: SIMD3<Float>, brightness: Float, char: Character = "#") -> ASCIIGrid {
        let cell = ASCIICell(character: char, displayColor: displayColor, alpha: 1, brightness: brightness)
        return grid(Array(repeating: Array(repeating: cell, count: 4), count: 3))
    }

    // MARK: - Dimension parity (G1/G2 alignment precondition)

    @Test func sdrAndHdrSharePixelDimensions() throws {
        let cell = ASCIICell(character: "@", displayColor: SIMD3<Float>(0.8, 0.4, 0.2), alpha: 1, brightness: 0.9)
        let grid = Self.grid(Array(repeating: Array(repeating: cell, count: 7), count: 5))
        let emission = EmissionOptions(k: 2, threshold: 0.4, maxHeadroom: 4)
        for preserve in [false, true] {
            for scale in [CGFloat(1), CGFloat(2)] {
                let sdr = grid.renderImage(
                    font: Self.font, backgroundColor: Self.background, scale: scale, preserveSourceAspect: preserve
                )
                let hdr = try #require(
                    grid.renderExtendedRangeImage(
                        font: Self.font, backgroundColor: Self.background, scale: scale,
                        preserveSourceAspect: preserve, emission: emission
                    ), "opaque grid must render (preserve=\(preserve), scale=\(scale))")
                #expect(sdr.width == hdr.width, "width parity (preserve=\(preserve), scale=\(scale))")
                #expect(sdr.height == hdr.height, "height parity (preserve=\(preserve), scale=\(scale))")
            }
        }
    }

    // MARK: - Float-context emission

    @Test func brightCellEmitsAboveOneWithinHeadroom() throws {
        let grid = Self.uniformGrid(displayColor: SIMD3<Float>(1, 1, 1), brightness: 1.0)
        let emission = EmissionOptions(k: 3, threshold: 0.2, maxHeadroom: 4)
        let image = try #require(
            grid.renderExtendedRangeImage(
                font: Self.font, backgroundColor: Self.background, scale: 1,
                preserveSourceAspect: false, emission: emission
            ))
        let stats = HDRArtifacts.floatStats(image, maxHeadroom: 4)
        #expect(stats.maxChannel > 1.0, "bright cell should bloom above paper-white")
        #expect(!stats.exceedsCeiling, "boost must stay within maxHeadroom")
        #expect(!stats.hasNaNOrInf, "no NaN/Inf in the float buffer")
    }

    @Test func lowBrightnessCellStaysAtOrBelowOne() throws {
        let grid = Self.uniformGrid(displayColor: SIMD3<Float>(1, 1, 1), brightness: 0.1)
        let emission = EmissionOptions(k: 3, threshold: 0.5, maxHeadroom: 4)
        let image = try #require(
            grid.renderExtendedRangeImage(
                font: Self.font, backgroundColor: Self.background, scale: 1,
                preserveSourceAspect: false, emission: emission
            ))
        let stats = HDRArtifacts.floatStats(image, maxHeadroom: 4)
        #expect(stats.maxChannel <= 1.0 + 1e-3, "below-threshold brightness must not emit")
        #expect(!stats.hasNaNOrInf)
    }

    @Test func authoredDarkGlyphEmitsIndependentOfBrightness() throws {
        let spec = GlyphEmissionSpec(["*": 4])
        let grid = Self.uniformGrid(displayColor: SIMD3<Float>(1, 1, 1), brightness: 0.05, char: "*")
        let emission = EmissionOptions(k: 1, threshold: 0.95, maxHeadroom: 8, source: .authored(spec))
        let image = try #require(
            grid.renderExtendedRangeImage(
                font: Self.font, backgroundColor: Self.background, scale: 1,
                preserveSourceAspect: false, emission: emission
            ))
        let stats = HDRArtifacts.floatStats(image, maxHeadroom: 8)
        #expect(stats.maxChannel > 1.0, "authored glyph boost must emit even for dark source brightness")
        #expect(!stats.exceedsCeiling)
        #expect(!stats.hasNaNOrInf)
    }

    @Test func authoredBrightMissingGlyphStaysFlat() throws {
        let spec = GlyphEmissionSpec(["*": 4])
        let grid = Self.uniformGrid(displayColor: SIMD3<Float>(1, 1, 1), brightness: 1.0, char: "#")
        let emission = EmissionOptions(k: 1, threshold: 0.0, maxHeadroom: 8, source: .authored(spec))
        let image = try #require(
            grid.renderExtendedRangeImage(
                font: Self.font, backgroundColor: Self.background, scale: 1,
                preserveSourceAspect: false, emission: emission
            ))
        let stats = HDRArtifacts.floatStats(image, maxHeadroom: 8)
        #expect(stats.maxChannel <= 1.0 + 1e-3, "missing authored glyph must not inherit brightness-keyed emission")
        #expect(!stats.hasNaNOrInf)
    }

    @Test func defaultEmissionSourceMatchesExplicitBrightnessSourceByteForByte() throws {
        let grid = Self.uniformGrid(displayColor: SIMD3<Float>(1, 1, 1), brightness: 0.85)
        let implicit = try #require(
            grid.renderExtendedRangeImage(
                font: Self.font, backgroundColor: Self.background, scale: 1,
                emission: EmissionOptions(k: 2, threshold: 0.4, maxHeadroom: 4)
            ))
        let explicit = try #require(
            grid.renderExtendedRangeImage(
                font: Self.font, backgroundColor: Self.background, scale: 1,
                emission: EmissionOptions(k: 2, threshold: 0.4, maxHeadroom: 4, source: .brightnessCurve)
            ))
        #expect(Self.bytes(implicit) == Self.bytes(explicit), "default SPI HDR path must stay byte-identical")
    }

    @Test func headroomClampIsRespected() throws {
        // k high enough to drive well past the ceiling; clamp must hold.
        let grid = Self.uniformGrid(displayColor: SIMD3<Float>(1, 1, 1), brightness: 1.0)
        let emission = EmissionOptions(k: 50, threshold: 0.0, maxHeadroom: 2.5)
        let image = try #require(
            grid.renderExtendedRangeImage(
                font: Self.font, backgroundColor: Self.background, scale: 1,
                preserveSourceAspect: false, emission: emission
            ))
        let stats = HDRArtifacts.floatStats(image, maxHeadroom: 2.5)
        #expect(!stats.exceedsCeiling, "values must never exceed maxHeadroom")
        #expect(stats.maxChannel > 1.0, "still emits")
        #expect(!stats.hasNaNOrInf)
    }

    // MARK: - Monochrome no-bloom (the #1 pathology)

    @Test func monochromeKeysOnBrightnessNotDisplayColor() throws {
        // Under monochrome every displayColor is white. A *dark* (low-brightness)
        // monochrome grid must NOT bloom; a *bright* one must. Same display colour,
        // opposite outcome -> proves the gain keys on brightness.
        let emission = EmissionOptions(k: 3, threshold: 0.5, maxHeadroom: 4)
        let darkMono = Self.uniformGrid(displayColor: SIMD3<Float>(1, 1, 1), brightness: 0.15)
        let brightMono = Self.uniformGrid(displayColor: SIMD3<Float>(1, 1, 1), brightness: 0.95)

        let darkImage = try #require(
            darkMono.renderExtendedRangeImage(
                font: Self.font, backgroundColor: Self.background, scale: 1, emission: emission
            ))
        let brightImage = try #require(
            brightMono.renderExtendedRangeImage(
                font: Self.font, backgroundColor: Self.background, scale: 1, emission: emission
            ))
        let darkStats = HDRArtifacts.floatStats(darkImage, maxHeadroom: 4)
        let brightStats = HDRArtifacts.floatStats(brightImage, maxHeadroom: 4)

        #expect(darkStats.maxChannel <= 1.0 + 1e-3, "dark monochrome must not bloom")
        #expect(brightStats.maxChannel > 1.0, "bright monochrome must bloom")
    }

    // MARK: - Opaque / full-coverage rejection contract (returns nil)

    @Test func subCoverageGridIsRejected() {
        let covered = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 1, coverage: 0.5)
        let grid = Self.grid([[covered]])
        let image = grid.renderExtendedRangeImage(
            font: Self.font, backgroundColor: Self.background, scale: 1,
            emission: EmissionOptions(k: 2, threshold: 0.3, maxHeadroom: 4)
        )
        #expect(image == nil, "masked/sub-coverage grid must be rejected (nil)")
    }

    @Test func nonTransparentFallbackGridIsRejected() {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 1, coverage: 1)
        let solid = CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        let grid = ASCIIGrid(
            cells: [[cell]],
            colorSpace: .sRGB,
            maskFallback: .solid(solid)
        )
        let image = grid.renderExtendedRangeImage(
            font: Self.font, backgroundColor: Self.background, scale: 1,
            emission: EmissionOptions(k: 2, threshold: 0.3, maxHeadroom: 4)
        )
        #expect(image == nil, "non-transparent mask fallback must be rejected (nil)")
    }

    @Test func positiveAlphaGroundIsRejectedEvenAtFullCoverage() {
        let cell = ASCIICell(
            character: "#",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 1,
            brightness: 1,
            coverage: 1
        )
        let grid = ASCIIGrid(
            cells: [[cell]],
            colorSpace: .sRGB,
            maskGroundColor: CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        )

        #expect(
            grid.renderExtendedRangeImage(
                font: Self.font,
                backgroundColor: Self.background,
                scale: 1,
                emission: EmissionOptions(k: 2, threshold: 0.3, maxHeadroom: 4)
            ) == nil
        )
    }

    @Test func zeroAndNonFiniteAlphaGroundsKeepTheExistingHDRPath() {
        let cell = ASCIICell(
            character: "#",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 1,
            brightness: 1,
            coverage: 1
        )
        for ground in [
            CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0),
            CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: .nan),
        ] {
            let grid = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB, maskGroundColor: ground)
            #expect(
                grid.renderExtendedRangeImage(
                    font: Self.font,
                    backgroundColor: Self.background,
                    scale: 1,
                    emission: EmissionOptions(k: 2, threshold: 0.3, maxHeadroom: 4)
                ) != nil
            )
        }
    }

    @Test func translucentCellGridIsRejected() {
        // A1/A4: HDR/SDR pixel-alignment only holds for opaque cells — a translucent
        // cell composites differently in extended-linear vs 8-bit sRGB-gamma, so the
        // gain map would encode that as spurious gain. Must be rejected (nil).
        let translucent = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 0.5, brightness: 1, coverage: 1)
        let grid = Self.grid([[translucent]])
        let image = grid.renderExtendedRangeImage(
            font: Self.font, backgroundColor: Self.background, scale: 1,
            emission: EmissionOptions(k: 2, threshold: 0.3, maxHeadroom: 4)
        )
        #expect(image == nil, "translucent (alpha < 1) cell must be rejected (nil)")
    }

    @Test func anyCoverageFallbackOrAlphaMismatchIsRejected() {
        let opaque = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 1, coverage: 1)
        let mismatches: [ASCIIGrid] = [
            Self.grid([[ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 1, coverage: 0.5)]]),
            ASCIIGrid(
                cells: [[opaque]],
                colorSpace: .sRGB,
                maskFallback: .solid(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
            ),
            Self.grid([[ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 0.5, brightness: 1, coverage: 1)]]),
        ]

        for grid in mismatches {
            #expect(
                grid.renderExtendedRangeImage(
                    font: Self.font,
                    backgroundColor: Self.background,
                    scale: 1,
                    emission: EmissionOptions(k: 2, threshold: 0.3, maxHeadroom: 4)
                ) == nil
            )
        }
    }

    private static func bytes(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data, let pointer = CFDataGetBytePtr(data) else {
            return []
        }
        return Array(UnsafeBufferPointer(start: pointer, count: CFDataGetLength(data)))
    }
}
