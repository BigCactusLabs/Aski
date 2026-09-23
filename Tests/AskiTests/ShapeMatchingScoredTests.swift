import Testing
import simd
@testable import Aski

@Suite struct ShapeMatchingScoredTests {
    /// `findBestScored` must return the same index as `findBest` and the
    /// correct squared-L2 distance of the winning lane set.
    @Test func findBestScoredMatchesFindBestAndComputesL2() {
        let lanes = StandardCharacterSet.lanesPerCharacter
        let query = (0..<lanes).map { SIMD4<Float>(repeating: Float($0)) }
        let cand0 = (0..<lanes).map { _ in SIMD4<Float>(repeating: 9) }
        // cand1 = query shifted +1 in every component: each of the 15 lanes
        // contributes |(-1,-1,-1,-1)|^2 = 4, so squared-L2 = 15 * 4 = 60.
        // cand0 (all 9s) is far (~1360), so index 1 still wins — and the
        // distance assertion pins a non-trivial value, not just 0.
        let cand1 = (0..<lanes).map { SIMD4<Float>(repeating: Float($0) + 1) }
        let candLanes = cand0 + cand1
        let bright: [Float] = [0.2, 0.8]

        let idx = ShapeMatching.findBest(
            queryLanes: query,
            queryBrightness: 0.8,
            candidateBrightness: bright,
            candidateLanes: candLanes,
            topK: 2
        )
        let scored = ShapeMatching.findBestScored(
            queryLanes: query,
            queryBrightness: 0.8,
            candidateBrightness: bright,
            candidateLanes: candLanes,
            topK: 2
        )

        #expect(scored.index == idx)
        #expect(scored.index == 1)
        #expect(abs(scored.distance - 60) < 1e-4)  // 15 lanes * |(-1,-1,-1,-1)|^2
    }

    /// `findRankedScored` must return the same indices (in order) as
    /// `findRanked`, each paired with a finite distance.
    @Test func findRankedScoredMatchesFindRankedIndicesAndDistancesAreFinite() {
        let query = repeatedLane(SIMD4<Float>(0.25, 0.5, 0.75, 1.0))
        let lanes = [
            repeatedLane(SIMD4<Float>(1, 0, 0, 0)),
            repeatedLane(SIMD4<Float>(0.25, 0.5, 0.75, 1.0)),
            repeatedLane(SIMD4<Float>(0.25, 0.5, 0.70, 1.0)),
        ].flatMap { $0 }
        let brightness: [Float] = [0.1, 0.45, 0.47]

        let ranked = ShapeMatching.findRanked(
            queryLanes: query,
            queryBrightness: 0.46,
            candidateBrightness: brightness,
            candidateLanes: lanes,
            brightnessLimit: 3,
            resultLimit: 3
        )
        let rankedScored = ShapeMatching.findRankedScored(
            queryLanes: query,
            queryBrightness: 0.46,
            candidateBrightness: brightness,
            candidateLanes: lanes,
            brightnessLimit: 3,
            resultLimit: 3
        )

        #expect(rankedScored.map(\.index) == ranked)
        for entry in rankedScored {
            #expect(entry.distance.isFinite)
            #expect(entry.distance >= 0)
        }
    }

    /// `findRankedScored` must honor the documented tie-break (shape distance,
    /// then brightness delta, then index). Two candidates at *equal* shape
    /// distance but different brightness delta, arranged so the correct order
    /// differs from naive index order — a buggy or missing tie-break fails.
    @Test func findRankedScoredHonorsBrightnessTieBreak() {
        let query = repeatedLane(SIMD4<Float>(0, 0, 0, 0))
        let lanes = [
            repeatedLane(SIMD4<Float>(1, 0, 0, 0)),  // index 0: distance 15, brightness delta 0.4
            repeatedLane(SIMD4<Float>(0, 1, 0, 0)),  // index 1: distance 15, brightness delta 0.0
        ].flatMap { $0 }
        let brightness: [Float] = [0.9, 0.5]

        let ranked = ShapeMatching.findRanked(
            queryLanes: query,
            queryBrightness: 0.5,
            candidateBrightness: brightness,
            candidateLanes: lanes,
            brightnessLimit: 2,
            resultLimit: 2
        )
        let rankedScored = ShapeMatching.findRankedScored(
            queryLanes: query,
            queryBrightness: 0.5,
            candidateBrightness: brightness,
            candidateLanes: lanes,
            brightnessLimit: 2,
            resultLimit: 2
        )

        // Equal shape distance -> brightness-delta tie-break decides: index 1
        // (delta 0) before index 0 (delta 0.4). Differs from index order [0, 1].
        #expect(rankedScored.map(\.index) == [1, 0])
        #expect(rankedScored.map(\.index) == ranked)
        #expect(abs(rankedScored[0].distance - 15) < 1e-4)
        #expect(abs(rankedScored[1].distance - 15) < 1e-4)
    }

    private func repeatedLane(_ lane: SIMD4<Float>) -> [SIMD4<Float>] {
        Array(repeating: lane, count: StandardCharacterSet.lanesPerCharacter)
    }
}

/// Covers the log-polar scored primitive used by the residual capture.
@Suite struct LogPolarScoreScoredTests {
    /// logPolar surfaces the real 60D squared-L2 distance; the character must
    /// match `score` exactly (same winning index → same glyph) and the
    /// distance must be finite.
    @Test func scoreScoredAgreesWithScoreOnLogPolar() {
        let cellWidth = 16
        let cellHeight = 16
        let context = ConversionContext(
            pixels: [UInt8](repeating: 128, count: cellWidth * cellHeight * 4),
            pixelWidth: cellWidth,
            pixelHeight: cellHeight,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            columns: 1,
            rows: 1,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB
        )
        let kernel = LogPolarKernel(characterSet: StandardCharacterSet.standard)
        let cell = CellCoord(column: 0, row: 0)
        let stats = CellStats(displayColor: .one, alpha: 1, adjustedL: 0.5, rawL: 0.5)

        let scored = kernel.scoreScored(cell: cell, stats: stats, in: context)
        let plain = kernel.score(cell: cell, stats: stats, in: context)

        #expect(scored.character == plain)
        #expect(scored.distance.isFinite)
        #expect(scored.distance >= 0)
    }

}
