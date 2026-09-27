import CoreGraphics
import Testing
import simd

@_spi(AskiResearch) @testable import Aski
@testable import AskiColorLab

/// Guards the two ASKI-79/80 candidate selectors (`OrthogonalityFallback`) as
/// frozen in `docs/Research/2026-09-27-aski-79-80-orthogonality-fallback-rule.md`
/// §3. Every expected pick below is derived by hand from the vectors and tones
/// written in the test.
@Suite struct AskiColorLabOrthogonalityFallbackTests {

    private static let lanesPerCharacter = 15

    private static func vector(_ bins: [Int: Float]) -> [SIMD4<Float>] {
        var lanes = [SIMD4<Float>](repeating: .zero, count: lanesPerCharacter)
        for (bin, mass) in bins { lanes[bin / 4][bin % 4] = mass }
        return lanes
    }

    // MARK: - Arm 1

    /// 0 blank (tone 0); 1 inked in bin 0, norm 1 (tone 0.3); 2 inked in bins
    /// 1–2, norm 0.5 (tone 0.6); 3 inked in bin 51, the query's bin (tone 0.9).
    private static let candidates: [[SIMD4<Float>]] = [
        vector([:]), vector([0: 1]), vector([1: 0.5, 2: 0.5]), vector([51: 1]),
    ]
    private static var candidateLanes: [SIMD4<Float>] { candidates.flatMap { $0 } }
    private static let brightness: [Float] = [0, 0.3, 0.6, 0.9]
    private static let query = vector([51: 0.5, 54: 0.25, 56: 0.25])

    private func armOne(tone: Float, topK: Int) -> Int {
        OrthogonalityFallback.pick(
            queryLanes: Self.query, tone: tone, candidateLanes: Self.candidateLanes,
            brightnessValues: Self.brightness, blank: [0], topK: topK)
    }

    private func production(tone: Float, topK: Int) -> Int {
        ShapeMatching.findBestScored(
            queryLanes: Self.query, queryBrightness: tone,
            candidateBrightness: Self.brightness, candidateLanes: Self.candidateLanes,
            topK: topK
        ).index
    }

    /// Tone 0.35, pool {1, 2}: both orthogonal to the query. Production takes
    /// the smaller norm (glyph 2, 0.5 < 1); arm 1 takes the tone-nearest (1).
    @Test func orthogonalPoolTakesTheToneNearestGlyphNotTheSmallestNorm() {
        #expect(production(tone: 0.35, topK: 2) == 2)
        #expect(armOne(tone: 0.35, topK: 2) == 1)
    }

    /// The ASKI-79 case. Tone 0.25, pool {1, 0, 2}: production's blank wins on
    /// norm alone; arm 1 gives the cell glyph 1, which is nearer in tone.
    @Test func blankLosesWhenItIsNotToneNearest() {
        #expect(production(tone: 0.25, topK: 3) == 0)
        #expect(armOne(tone: 0.25, topK: 3) == 1)
    }

    /// Tone 0.1, pool {0, 1}: the blank is tone-nearest, so arm 1 keeps it.
    @Test func blankWinsWhenItIsToneNearest() {
        #expect(armOne(tone: 0.1, topK: 2) == 0)
    }

    /// Tone 0.8, pool {3, 2}: glyph 3 shares bin 51 with the query, so the cell
    /// is not orthogonal and arm 1 is production's shape argmin (glyph 3:
    /// 0.375 against 0.875).
    @Test func overlappingPoolKeepsProductionsShapeArgmin() {
        #expect(armOne(tone: 0.8, topK: 2) == 3)
        #expect(armOne(tone: 0.8, topK: 2) == production(tone: 0.8, topK: 2))
    }

    /// On real query descriptors: where some non-blank pooled candidate
    /// overlaps the query, arm 1 reproduces the glyph the converter rendered;
    /// where none does, it is the tone-only floor's pick (rule §3.1).
    @Test func onRealQueriesArmOneIsProductionOrTheFloor() throws {
        let side = 192
        let context = try #require(
            CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        for y in 0..<side {
            for x in 0..<side {
                let dx = Double(x - side / 2), dy = Double(y - side / 2)
                let rings = (sin((dx * dx + dy * dy).squareRoot() * .pi / 7) + 1) / 2
                let value = 0.55 * rings + 0.45 * Double(x + y) / Double(2 * side)
                context.setFillColor(CGColor(gray: value, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let image = try #require(context.makeImage())
        let set = StandardCharacterSet.standard
        let converter = ASCIIConverter(
            characterSet: set, palette: BuiltInPalette.monochrome, colorSpace: .sRGB,
            oversample: 2)
        let queries = try #require(converter.cellQueryDescriptors(image, columns: 24))
        let blank = PickTexture.zeroNormGlyphs(
            candidateLanes: set.shapeVectorLanes, lanesPerCharacter: Self.lanesPerCharacter)
        var orthogonal = 0, overlapping = 0
        for row in 0..<queries.rows {
            for column in 0..<queries.columns {
                let lanes = queries.lanes(row: row, column: column)
                let tone = queries.adjustedL(row: row, column: column)
                let pool = ShapeMatching.poolIndices(
                    queryBrightness: tone, candidateBrightness: set.brightnessValues, topK: 12)
                let picked = OrthogonalityFallback.pick(
                    queryLanes: lanes, tone: tone, candidateLanes: set.shapeVectorLanes,
                    brightnessValues: set.brightnessValues, blank: blank, topK: 12)
                if OrthogonalityFallback.isOrthogonal(
                    queryLanes: lanes, pool: pool, candidateLanes: set.shapeVectorLanes,
                    blank: blank)
                {
                    orthogonal += 1
                    #expect(
                        picked
                            == SelectionCeiling.floorPick(
                                adjustedL: tone, brightnessValues: set.brightnessValues))
                } else {
                    overlapping += 1
                    #expect(
                        set.characters[picked] == queries.grid.cells[row][column].character)
                }
            }
        }
        #expect(orthogonal > 0 && overlapping > 0, "fixture must exercise both branches")
    }

    // MARK: - Arm 2

    /// 0 blank (tone 0), 1 (tone 0.5), 2 (tone 1.0); every query is the zero
    /// vector, so every cell is orthogonal and only tone decides.
    private static let toneLanes: [SIMD4<Float>] = [
        vector([:]), vector([0: 1]), vector([1: 1]),
    ].flatMap { $0 }
    private static let toneBrightness: [Float] = [0, 0.5, 1]

    private func diffused(rows: Int, columns: Int, tone: Float, strength: Float) -> [[Int]] {
        OrthogonalityFallback.errorDiffusedPicks(
            rows: rows, columns: columns,
            queryLanes: Array(repeating: Self.vector([:]), count: rows * columns),
            tones: Array(repeating: tone, count: rows * columns),
            candidateLanes: Self.toneLanes, brightnessValues: Self.toneBrightness,
            blank: [0], topK: 3, strength: strength)
    }

    /// One row at tone 0.3. Targets: 0.3 → glyph 1 (residual −0.2, +7/16 right);
    /// 0.2125 → blank (residual +0.2125); 0.39297 → glyph 1 (residual −0.10703);
    /// 0.25317 → glyph 1 (0.2468 from 0.5 against 0.2532 from 0).
    @Test func errorDiffusionCarriesTheResidualRight() {
        #expect(diffused(rows: 1, columns: 4, tone: 0.3, strength: 1) == [[1, 0, 1, 1]])
    }

    /// Two rows at tone 0.3, exercising below-left, below and below-right.
    /// (0,0) 0.3 → 1; (0,1) 0.2125 → 0; (1,0) 0.3 − 0.0625 + 0.03984 = 0.27734
    /// → 1; (1,1) 0.3 − 0.0125 + 0.06641 − 0.09741 = 0.25649 → 1.
    @Test func errorDiffusionUsesTheFloydSteinbergWeights() {
        #expect(diffused(rows: 2, columns: 2, tone: 0.3, strength: 1) == [[1, 0], [1, 1]])
    }

    /// At strength 0 nothing diffuses and arm 2 is arm 1 cell for cell.
    @Test func zeroStrengthIsArmOne() {
        #expect(diffused(rows: 2, columns: 3, tone: 0.3, strength: 0) == [[1, 1, 1], [1, 1, 1]])
    }
}
