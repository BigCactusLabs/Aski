import Testing
import simd
@testable import Aski

@Suite struct ShapeMatchingTopKTests {
    @Test func rankedLimitRespectsBrightnessLimitAndResultLimit() {
        let query = repeatedLane(SIMD4<Float>(1, 0, 0, 0))
        let lanes = [
            repeatedLane(SIMD4<Float>(1, 0, 0, 0)),
            repeatedLane(SIMD4<Float>(0, 1, 0, 0)),
            repeatedLane(SIMD4<Float>(0, 0, 1, 0)),
            repeatedLane(SIMD4<Float>(0, 0, 0, 1)),
        ].flatMap { $0 }
        let ranked = ShapeMatching.findRanked(
            queryLanes: query,
            queryBrightness: 0.5,
            candidateBrightness: [0.49, 0.51, 0.9, 0.1],
            candidateLanes: lanes,
            brightnessLimit: 2,
            resultLimit: 3
        )

        #expect(ranked.count == 2)
        #expect(Set(ranked) == Set([0, 1]))
    }

    @Test func rankedOrderUsesShapeThenBrightnessThenIndex() {
        let query = repeatedLane(SIMD4<Float>(1, 0, 0, 0))
        let lanes = [
            repeatedLane(SIMD4<Float>(0, 1, 0, 0)),
            repeatedLane(SIMD4<Float>(0, 1, 0, 0)),
            repeatedLane(SIMD4<Float>(1, 0, 0, 0)),
            repeatedLane(SIMD4<Float>(0, 1, 0, 0)),
        ].flatMap { $0 }

        let ranked = ShapeMatching.findRanked(
            queryLanes: query,
            queryBrightness: 0.5,
            candidateBrightness: [0.125, 0.75, 1.0, 0.75],
            candidateLanes: lanes,
            brightnessLimit: 4,
            resultLimit: 4
        )

        #expect(ranked == [2, 1, 3, 0])
    }

    @Test func findBestMatchesRankedFirstElement() {
        let query = repeatedLane(SIMD4<Float>(0.25, 0.5, 0.75, 1.0))
        let lanes = [
            repeatedLane(SIMD4<Float>(1, 0, 0, 0)),
            repeatedLane(SIMD4<Float>(0.25, 0.5, 0.75, 1.0)),
            repeatedLane(SIMD4<Float>(0.25, 0.5, 0.70, 1.0)),
        ].flatMap { $0 }
        let brightness: [Float] = [0.1, 0.45, 0.47]

        let best = ShapeMatching.findBest(
            queryLanes: query,
            queryBrightness: 0.46,
            candidateBrightness: brightness,
            candidateLanes: lanes,
            topK: 3
        )
        let ranked = ShapeMatching.findRanked(
            queryLanes: query,
            queryBrightness: 0.46,
            candidateBrightness: brightness,
            candidateLanes: lanes,
            brightnessLimit: 3,
            resultLimit: 1
        )

        #expect(best == ranked.first)
    }

    @Test func findBestPreservesBrightnessThenIndexTieBreak() {
        let query = repeatedLane(SIMD4<Float>(1, 0, 0, 0))
        let lanes = [
            repeatedLane(SIMD4<Float>(0, 1, 0, 0)),
            repeatedLane(SIMD4<Float>(0, 1, 0, 0)),
            repeatedLane(SIMD4<Float>(0, 1, 0, 0)),
        ].flatMap { $0 }

        let best = ShapeMatching.findBest(
            queryLanes: query,
            queryBrightness: 0.5,
            candidateBrightness: [0.125, 0.75, 0.75],
            candidateLanes: lanes,
            topK: 3
        )

        #expect(best == 1)
    }

    private func repeatedLane(_ lane: SIMD4<Float>) -> [SIMD4<Float>] {
        Array(repeating: lane, count: StandardCharacterSet.lanesPerCharacter)
    }
}
