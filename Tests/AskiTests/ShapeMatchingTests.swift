import Testing
import simd
@testable import Aski

@Suite struct ShapeMatchingTests {
    @Test func exactMatchWinsOverSimilar() {
        var lanes: [SIMD4<Float>] = []
        lanes.append(contentsOf: repeatedLane(SIMD4(1, 0, 0, 0)))
        lanes.append(contentsOf: repeatedLane(SIMD4(0, 1, 0, 0)))
        let brightness: [Float] = [0.5, 0.5]
        let query = repeatedLane(SIMD4(1, 0, 0, 0))

        let best = ShapeMatching.findBest(
            queryLanes: query,
            queryBrightness: 0.5,
            candidateBrightness: brightness,
            candidateLanes: lanes,
            topK: 2
        )

        #expect(best == 0)
    }

    @Test func brightnessFilterReducesCandidates() {
        let lanes = Array(repeating: SIMD4<Float>.zero, count: StandardCharacterSet.lanesPerCharacter * 3)
        let brightness: [Float] = [0.1, 0.5, 0.9]
        let query = repeatedLane(.zero)

        let best = ShapeMatching.findBest(
            queryLanes: query,
            queryBrightness: 0.52,
            candidateBrightness: brightness,
            candidateLanes: lanes,
            topK: 1
        )

        #expect(best == 1)
    }

    @Test func brightnessPrefilterCanExcludeDistantExactShape() {
        var lanes: [SIMD4<Float>] = []
        lanes.append(contentsOf: repeatedLane(SIMD4(1, 0, 0, 0)))
        lanes.append(contentsOf: repeatedLane(SIMD4(0, 1, 0, 0)))
        let brightness: [Float] = [0.2, 0.8]
        let query = repeatedLane(SIMD4(1, 0, 0, 0))

        let best = ShapeMatching.findBest(
            queryLanes: query,
            queryBrightness: 0.79,
            candidateBrightness: brightness,
            candidateLanes: lanes,
            topK: 1
        )

        #expect(best == 1)
    }

    private func repeatedLane(_ lane: SIMD4<Float>) -> [SIMD4<Float>] {
        Array(repeating: lane, count: StandardCharacterSet.lanesPerCharacter)
    }
}
