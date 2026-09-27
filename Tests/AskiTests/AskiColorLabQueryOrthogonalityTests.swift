import Testing
import simd

@testable import AskiColorLab

/// Guards the per-cell classification `query-orthogonality` reports (ASKI-79
/// AC#1 mechanism, ASKI-80 AC#2): whether the query is orthogonal to every
/// non-blank pooled candidate, and whether the rendered pick is then the
/// pooled minimum-`|g|²` candidate.
///
/// The fixtures are hand-built 60D vectors, so each expectation follows from
/// the dot products written in the test rather than from the implementation.
@Suite struct AskiColorLabQueryOrthogonalityTests {

    private static let lanesPerCharacter = 15

    /// A 60D vector with the given bin masses.
    private static func vector(_ bins: [Int: Float]) -> [SIMD4<Float>] {
        var lanes = [SIMD4<Float>](repeating: .zero, count: lanesPerCharacter)
        for (bin, mass) in bins { lanes[bin / 4][bin % 4] = mass }
        return lanes
    }

    /// Candidates: 0 blank; 1 inked in bin 0 (norm 0.25); 2 inked in bins 1
    /// and 2 (norm 0.5); 3 inked in bin 51 (the query's bin).
    private static let candidates: [[SIMD4<Float>]] = [
        vector([:]),
        vector([0: 0.5]),
        vector([1: 0.5, 2: 0.5]),
        vector([51: 1.0]),
    ]
    private static var candidateLanes: [SIMD4<Float>] { candidates.flatMap { $0 } }
    private static var norms: [Float] {
        candidates.map { lanes in lanes.reduce(0) { $0 + simd_dot($1, $1) } }
    }
    private static let brightness: [Float] = [0, 0.2, 0.4, 0.6]
    private static let query = vector([51: 0.5, 54: 0.25, 56: 0.25])

    private func classify(pool: [Int], pick: Int, tone: Float = 0.3)
        -> QueryOrthogonality.CellClass
    {
        QueryOrthogonality.classify(
            query: Self.query, tone: tone, pool: pool, pick: pick,
            candidateLanes: Self.candidateLanes, norms: Self.norms,
            brightness: Self.brightness, blank: [0])
    }

    @Test func occupiedBinsAreTheQuerysNonZeroBins() {
        #expect(classify(pool: [0, 1], pick: 0).occupiedBins == [51, 54, 56])
    }

    /// Pool {blank, 1, 2}: neither inked candidate touches bins 51/54/56, so the
    /// cell is orthogonal and the minimum-norm candidate is the blank.
    @Test func disjointPoolIsOrthogonalAndTheBlankIsTheMinimumNorm() {
        let cell = classify(pool: [0, 1, 2], pick: 0)
        #expect(cell.orthogonal)
        #expect(cell.pickIsMinNorm)
        #expect(cell.minPositiveDot == nil)
    }

    /// Without the blank in the pool the minimum-norm candidate is glyph 1
    /// (0.25 < 0.5). A pick of 2 disagrees with the `|g|²` rule.
    @Test func withoutTheBlankTheSmallestInkedNormIsTheMinimum() {
        #expect(classify(pool: [1, 2], pick: 1).pickIsMinNorm)
        #expect(!classify(pool: [1, 2], pick: 2).pickIsMinNorm)
    }

    /// One overlapping candidate is enough to make the cell non-orthogonal, and
    /// its dot product (0.5 × 1.0) is the smallest positive one recorded.
    @Test func oneOverlappingCandidateBreaksOrthogonality() {
        let cell = classify(pool: [0, 1, 3], pick: 3)
        #expect(!cell.orthogonal)
        #expect(cell.minPositiveDot == 0.5)
    }

    /// The blank is excluded from the orthogonality test itself: its dot
    /// product is zero against every query and says nothing about the cell.
    @Test func theBlankNeverCountsAgainstOrthogonality() {
        #expect(classify(pool: [0], pick: 0).orthogonal)
    }

    /// Equal norms fall back to the matcher's tie order: brightness delta, then
    /// index. Glyphs 1 and 4 share a norm; 4 is nearer the cell tone.
    @Test func equalNormsBreakTiesByBrightnessDeltaThenIndex() {
        let lanes = Self.candidateLanes + Self.vector([3: 0.5])
        let norms = Self.norms + [0.25]
        let brightness = Self.brightness + [0.31]
        let cell = QueryOrthogonality.classify(
            query: Self.query, tone: 0.3, pool: [1, 4], pick: 4,
            candidateLanes: lanes, norms: norms, brightness: brightness, blank: [0])
        #expect(cell.orthogonal)
        #expect(cell.pickIsMinNorm)
    }

    /// `glyphsWithMass` names the non-blank glyphs a reachable set can see.
    @Test func glyphsWithMassListsOnlyInkedGlyphsTouchingTheBins() {
        let reachable = QueryOrthogonality.glyphsWithMass(
            in: [51, 54, 56], candidateLanes: Self.candidateLanes,
            glyphCount: Self.candidates.count, blank: [0])
        #expect(reachable == [3])
        #expect(
            QueryOrthogonality.glyphsWithMass(
                in: [0], candidateLanes: Self.candidateLanes,
                glyphCount: Self.candidates.count, blank: [0]) == [1])
    }
}
