import AskiToolSupport
import Foundation
import Testing

@_spi(AskiResearch) @testable import Aski
@testable import AskiColorLab

/// Guards the ASKI-27 reference-recovery screen — the disqualifier that decides
/// which metric is allowed to define "optimal" for a per-cell glyph pick.
///
/// The demand is minimal by construction: the source cell IS a rendered glyph,
/// pushed through the production scoring path, and the oracle is asked to name
/// the glyph it was handed. An oracle that cannot do that is not measuring glyph
/// choice, and every ranking it has ever produced is a ranking of something else.
///
/// Scope: these tests run the `blocks` charset only, because the debug-build
/// scoring cost is quadratic in charset size and `braille` alone is a quarter of
/// a million comparisons per oracle. `blocks` is not a weak choice — it is the
/// ASTSK-47-frozen shipping preset, and it already reproduces the decisive
/// result. The full per-charset screen the note reports (blocks, standard,
/// braille) is the `reference-recovery` lab arm:
///
///     swift run -c release AskiColorLab reference-recovery
@Suite struct AskiColorLabReferenceRecoveryTests {

    /// Shipping regime, matching the selection-ceiling runs: 3072px corpus
    /// fixtures, `columns: 80`, `oversample: 2`, 24px scoring footprint.
    ///
    /// Computed once for the whole suite. Resolving the converter's native cell
    /// block pushes a 9.4-megapixel probe image through a full conversion, and
    /// every test here wants the same screen; Swift Testing builds a fresh suite
    /// instance per test, so the cache has to be static.
    private static let cachedScreen: [ReferenceRecovery.Row] =
        (try? ReferenceRecovery.run(
            columns: 80, oversample: 2, footprint: 24, nativeSide: 3072,
            charsetNames: ["blocks"])) ?? []

    private static func screen() throws -> [ReferenceRecovery.Row] {
        try #require(!cachedScreen.isEmpty, "the reference-recovery screen produced no rows")
        return cachedScreen
    }

    private static func row(
        _ rows: [ReferenceRecovery.Row], _ oracle: SelectionCeiling.Oracle,
        _ shape: ReferenceRecovery.SourceShape
    ) -> ReferenceRecovery.Row? {
        rows.first { $0.oracle == oracle.rawValue && $0.shape == shape.rawValue }
    }

    /// Every arm of the screen has to actually resolve, including the two that
    /// depend on the converter's own cell geometry — a `nil` block there would
    /// silently drop half the screen and turn a failure into a pass.
    @Test func screenResolvesEveryOracleAndSourceShape() throws {
        let rows = try Self.screen()
        let expected =
            SelectionCeiling.Oracle.allCases.count * ReferenceRecovery.SourceShape.allCases.count
        #expect(rows.count == expected)
        for shape in ReferenceRecovery.SourceShape.allCases {
            #expect(
                rows.contains { $0.shape == shape.rawValue }, "no rows for the \(shape) arm")
        }
        // The cell-derived arms must be on the converter's resolved footprint,
        // not on a square fallback.
        let cell = Self.row(rows, .mae, .cell)
        #expect(cell?.sourceWidth != cell?.sourceHeight, "the cell arm lost its anisotropy")
    }

    /// AC#2, identity arm. With the resample an identity, nothing is lost by
    /// geometry, so a failure here would be an oracle unable to tell two
    /// different pictures apart. No candidate oracle fails this — which is why
    /// the screen's verdict rests on the geometry arm below rather than here.
    @Test func everyOracleRecoversTheReferenceAtTheFootprintItself() throws {
        let rows = try Self.screen()
        for oracle in SelectionCeiling.Oracle.allCases {
            let row = try #require(Self.row(rows, oracle, .footprint))
            #expect(row.strictMisses == 0, "\(oracle.rawValue) preferred a wrong glyph at identity")
            #expect(row.tiedRecoveries == 0, "\(oracle.rawValue) could not separate at identity")
            #expect(row.meanReferenceRank == 1.0)
        }
    }

    /// AC#2, blur-tolerance control. `roundTrip` holds the rasterizer fixed and
    /// adds only an anisotropic resample round trip through the converter's cell
    /// block. It is NOT the production downscale — the source is built from the
    /// footprint raster, so it never carries more information than the footprint
    /// did — which makes a failure here evidence of blur/luminance blindness and
    /// nothing more. The luminance-aware oracles come back clean; GMSD does not.
    @Test func luminanceAwareOraclesSurviveTheBlurControlAndGMSDDoesNot() throws {
        let rows = try Self.screen()
        for oracle in [SelectionCeiling.Oracle.mae, .rmse, .ssim] {
            let row = try #require(Self.row(rows, oracle, .roundTrip))
            #expect(
                row.strictMisses == 0 && row.tiedRecoveries == 0,
                "\(oracle.rawValue) lost the reference through the blur control: \(row.worstConfusion)"
            )
            // Unscoreable rows are neither a recovery nor a miss, so a clean
            // MISS count alone must not read as a pass.
            #expect(
                row.invalidReferences == 0,
                "\(oracle.rawValue) could not score \(row.invalidReferences) reference(s)")
        }
        // The house oracle's own row, stated separately so the reason this
        // suite exists survives a future edit to the loop above.
        let house = try #require(Self.row(rows, .mae, .roundTrip))
        #expect(house.uniqueRecoveries == house.glyphs, "the house oracle must recover every glyph")

        // GMSD confuses the half-blocks through the same round trip — a pure
        // position swap with identical ink, which is the luminance-blindness
        // the IJCV 2021 ranking diagnoses, reproduced on the shipping charset.
        let gmsd = try #require(Self.row(rows, .gmsd, .roundTrip))
        #expect(
            gmsd.strictMisses > 0 || gmsd.tiedRecoveries > 0,
            "GMSD recovered every reference through the blur control — the ASKI-27 disqualification no longer reproduces"
        )
    }

    /// ASKI-32 AC#6: the typographic cell rasterizer must PRESERVE the
    /// position-only distinctions that bounds-centring erases. `▄` and `▀`
    /// carry identical ink at opposite ends of the cell; if the two rasters
    /// coincide, the calibrated arm is scoring the same collapsed bar the
    /// legacy arms scored and the whole instrument is moot.
    @Test func typographicRasterizerKeepsHalfBlocksApart() {
        let w = 24, h = 48
        let lower = GlyphCellRaster.luma(character: "▄", width: w, height: h)
        let upper = GlyphCellRaster.luma(character: "▀", width: w, height: h)
        #expect(lower != upper, "bounds-centring collapse: ▄ and ▀ rasterized identically")
        // Memory row 0 is the TOP of the raster. The lower half block's ink
        // belongs in the bottom rows, the upper's in the top rows.
        func halfMeans(_ raster: [Float]) -> (top: Float, bottom: Float) {
            let half = (h / 2) * w
            let top = raster[..<half].reduce(0, +) / Float(half)
            let bottom = raster[half...].reduce(0, +) / Float(raster.count - half)
            return (top, bottom)
        }
        let lowerMeans = halfMeans(lower)
        let upperMeans = halfMeans(upper)
        #expect(lowerMeans.bottom > lowerMeans.top, "▄ landed its ink in the top half")
        #expect(upperMeans.top > upperMeans.bottom, "▀ landed its ink in the bottom half")
    }

    /// ASKI-32 AC#6, braille leg: production renders braille through
    /// `BrailleRasterizer` dot geometry, not a text face, so the calibrated
    /// reference must too. Single-dot glyphs at opposite corners have to stay
    /// distinct and land their ink in the right quadrant.
    @Test func typographicRasterizerRoutesBrailleThroughProductionDots() {
        let w = 24, h = 48
        let topLeft = GlyphCellRaster.luma(character: "⠁", width: w, height: h)  // dot 1
        let bottomRight = GlyphCellRaster.luma(character: "⢀", width: w, height: h)  // dot 8
        #expect(topLeft != bottomRight, "single-dot braille glyphs rasterized identically")
        func quadrantMean(_ raster: [Float], right: Bool, bottom: Bool) -> Float {
            var sum: Float = 0
            var count = 0
            for y in (bottom ? h / 2 : 0)..<(bottom ? h : h / 2) {
                for x in (right ? w / 2 : 0)..<(right ? w : w / 2) {
                    sum += raster[y * w + x]
                    count += 1
                }
            }
            return sum / Float(max(1, count))
        }
        #expect(
            quadrantMean(topLeft, right: false, bottom: false)
                > quadrantMean(topLeft, right: true, bottom: true),
            "⠁ did not land in the top-left quadrant")
        #expect(
            quadrantMean(bottomRight, right: true, bottom: true)
                > quadrantMean(bottomRight, right: false, bottom: false),
            "⢀ did not land in the bottom-right quadrant")
    }

    /// ASKI-32 AC#1, hi-res stage: the reference must be rendered at high
    /// resolution and area-resampled INTO the resolved cell block, not drawn
    /// directly at block resolution (which would tie Core Text hinting and
    /// antialiasing to the block size). A supersampled render differs from the
    /// direct one on a text glyph — if they coincide, the stage is gone — while
    /// carrying the same ink to within antialiasing tolerance.
    @Test func typographicRasterizerRendersHighResolutionThenResamples() {
        let w = 24, h = 48
        let supersampled = GlyphCellRaster.luma(character: "A", width: w, height: h)
        let direct = GlyphCellRaster.luma(character: "A", width: w, height: h, supersample: 1)
        #expect(
            supersampled != direct,
            "supersampled and direct renders coincide — the AC#1 hi-res stage is inert")
        let inkDelta =
            abs(
                supersampled.reduce(0, +) - direct.reduce(0, +)) / Float(w * h)
        #expect(
            inkDelta < 0.05,
            "hi-res stage moved the ink fraction by \(inkDelta) — that is bigger than a hinting/antialiasing difference, so the resample is not area-preserving")
    }

    /// ASKI-32 AC#2: the same-path arm is the one whose two sides share a
    /// drawing convention, so its ink fractions must actually agree — that
    /// agreement is what "calibrated" means, and it is measured, not assumed.
    /// The matcher-candidate arm (`calibratedCell`) carries whatever ink
    /// mismatch the matcher's candidate convention costs; the screen reports
    /// it, and this test only requires it to be recorded on the real geometry.
    @Test func calibratedArmsReportInkCalibration() throws {
        let rows = try Self.screen()
        let samePath = try #require(Self.row(rows, .mae, .calibratedSamePath))
        #expect(
            samePath.meanInkDelta < 0.05,
            "same-path arm is not ink-calibrated: meanInkΔ \(samePath.meanInkDelta)")
        let production = try #require(Self.row(rows, .mae, .calibratedCell))
        #expect(
            production.sourceWidth != production.sourceHeight,
            "the calibrated arm lost its anisotropy")
    }

    /// ASKI-32 AC#3/#4 — the decisive result, pinned. With the AC#1 hi-res
    /// stage in place (rasterizer hinting decoupled from the block size), the
    /// MAE-vs-GMSD inversion DISAPPEARS: every oracle recovers every glyph
    /// through the calibrated same-path gate, so the gate is a validity check
    /// that the instrument is clean, not a discriminator. The house oracle is
    /// reaffirmed because it passes this gate while GMSD keeps failing the
    /// blur control (pinned separately in
    /// `luminanceAwareOraclesSurviveTheBlurControlAndGMSDDoesNot`). A
    /// regression here means the calibrated instrument broke — it must fail
    /// loudly, not surface as a silent number change in a lab report.
    @Test func everyOracleRecoversThroughTheCalibratedSamePathGate() throws {
        let rows = try Self.screen()
        for oracle in SelectionCeiling.Oracle.allCases {
            let row = try #require(Self.row(rows, oracle, .calibratedSamePath))
            #expect(
                row.uniqueRecoveries == row.glyphs,
                "\(oracle.rawValue) lost the calibrated gate: \(row.worstConfusion)")
            #expect(
                row.invalidReferences == 0,
                "\(oracle.rawValue) could not score \(row.invalidReferences) reference(s)")
        }
        // The gate's worst ink mismatch stays bounded too, so a drifting
        // rasterizer cannot quietly turn the arm into the confounded one.
        let house = try #require(Self.row(rows, .mae, .calibratedSamePath))
        #expect(house.maxInkDelta < 0.1, "gate arm ink calibration drifted: maxInkΔ \(house.maxInkDelta)")
    }

    /// The four outcome buckets partition the charset. Without the `invalid`
    /// bucket an oracle that scored nothing would have shown zero misses and a
    /// mean rank of zero — better than perfect recovery — because the unscoreable
    /// rows were dropped from the numerator while the mean still divided by the
    /// full charset.
    @Test func everyReferenceLandsInExactlyOneBucketAndTheMeanRankIsBounded() throws {
        let rows = try Self.screen()
        for row in rows {
            #expect(
                row.uniqueRecoveries + row.tiedRecoveries + row.strictMisses
                    + row.invalidReferences == row.glyphs,
                "\(row.oracle)/\(row.shape) does not account for every reference")
            #expect(row.meanReferenceRank >= 1.0, "\(row.oracle)/\(row.shape) beat perfect recovery")
            #expect(row.meanReferenceRank <= Double(row.glyphs))
        }
    }
}
