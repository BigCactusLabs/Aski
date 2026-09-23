import Testing
import simd
@_spi(AskiResearch) @testable import Aski

@Suite struct ShapeMatchingPoolIndicesTests {
    @Test func poolIndicesMatchBrightnessPrefilterUsedByFindBest() {
        let query = repeatedLane(SIMD4<Float>(1, 0, 0, 0))
        let lanes = [
            repeatedLane(SIMD4<Float>(0, 1, 0, 0)),
            repeatedLane(SIMD4<Float>(1, 0, 0, 0)),
            repeatedLane(SIMD4<Float>(0, 0, 1, 0)),
            repeatedLane(SIMD4<Float>(0, 0, 0, 1)),
        ].flatMap { $0 }
        let brightness: [Float] = [0.49, 0.51, 0.9, 0.1]

        let pool = ShapeMatching.poolIndices(
            queryBrightness: 0.5,
            candidateBrightness: brightness,
            topK: 2
        )
        let best = ShapeMatching.findBest(
            queryLanes: query,
            queryBrightness: 0.5,
            candidateBrightness: brightness,
            candidateLanes: lanes,
            topK: 2
        )

        #expect(pool == [0, 1])
        #expect(pool.contains(best))
    }

    @Test func poolIndicesTieBreaksByIndex() {
        let pool = ShapeMatching.poolIndices(
            queryBrightness: 0.5,
            candidateBrightness: [0.75, 0.25, 0.75, 0.5],
            topK: 4
        )

        #expect(pool == [3, 0, 1, 2])
    }

    private func repeatedLane(_ lane: SIMD4<Float>) -> [SIMD4<Float>] {
        Array(repeating: lane, count: StandardCharacterSet.lanesPerCharacter)
    }
}
