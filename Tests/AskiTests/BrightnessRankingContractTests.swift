import Testing
@_spi(AskiResearch) @testable import Aski

/// ASKI-88: exercise the actual SIMD matcher on Apple platforms. Distances in
/// these fixtures are exact small integers, so a scalar oracle introduces no
/// tolerance or alternate floating-point reduction policy.
@Suite struct BrightnessRankingContractTests {
    @Test func allWrappersPreservePoolMembershipRankingTiesAndResiduals() {
        let brightness: [Float] = [0.75, 0.25, 0.5, 1, 0, 0.5, 0.75, 0.25]
        let zero = Array(repeating: Float(0), count: 60)
        var x = zero
        var y = zero
        var negativeX = zero
        x[0] = 1
        y[1] = 1
        negativeX[0] = -1
        let vectors = [y, y, zero, x, x, negativeX, zero, y]
        let lanes = vectors.flatMap(Self.lanes)

        for query in [zero, x, y] {
            for queryBrightness in [Float(0), 0.5, 1] {
                let pool = BrightnessPoolFixtures.rankOrder(query: queryBrightness, values: brightness)
                let distances: [Float] = vectors.map { vector in
                    zip(query, vector).reduce(Float(0)) { sum, pair in
                        let delta = pair.0 - pair.1
                        return sum + delta * delta
                    }
                }
                for limit in [1, 2, 4, 8, 12] {
                    let expected = Array(pool.prefix(limit)).sorted { left, right in
                        if distances[left] != distances[right] { return distances[left] < distances[right] }
                        let a = abs(brightness[left] - queryBrightness)
                        let b = abs(brightness[right] - queryBrightness)
                        return a == b ? left < right : a < b
                    }
                    let best = ShapeMatching.findBestScored(
                        queryLanes: Self.lanes(query), queryBrightness: queryBrightness,
                        candidateBrightness: brightness, candidateLanes: lanes, topK: limit)
                    #expect(best.index == expected[0])
                    #expect(best.distance.bitPattern == distances[expected[0]].bitPattern)
                    #expect(
                        ShapeMatching.findBest(
                            queryLanes: Self.lanes(query), queryBrightness: queryBrightness,
                            candidateBrightness: brightness, candidateLanes: lanes, topK: limit) == best.index)
                    for resultLimit in [1, 2, 6, 12] {
                        let ranked = ShapeMatching.findRanked(
                            queryLanes: Self.lanes(query), queryBrightness: queryBrightness,
                            candidateBrightness: brightness, candidateLanes: lanes,
                            brightnessLimit: limit, resultLimit: resultLimit)
                        let scored = ShapeMatching.findRankedScored(
                            queryLanes: Self.lanes(query), queryBrightness: queryBrightness,
                            candidateBrightness: brightness, candidateLanes: lanes,
                            brightnessLimit: limit, resultLimit: resultLimit)
                        #expect(ranked == Array(expected.prefix(resultLimit)))
                        #expect(scored.map(\.index) == ranked)
                        #expect(scored.map { $0.distance.bitPattern } == ranked.map { distances[$0].bitPattern })
                    }
                }
            }
        }
    }

    @Test func betterShapeOutsideTheBrightnessPoolMustRemainExcluded() {
        let zero = Array(repeating: SIMD4<Float>.zero, count: 15)
        var distant = zero
        distant[0] = SIMD4<Float>(1, 0, 0, 0)
        let result = ShapeMatching.findBestScored(
            queryLanes: zero, queryBrightness: 0,
            candidateBrightness: [0, 1], candidateLanes: distant + zero, topK: 1)
        #expect(result.index == 0)
        #expect(result.distance == 1)
    }

    private static func lanes(_ vector: [Float]) -> [SIMD4<Float>] {
        stride(from: 0, to: vector.count, by: 4).map { index in
            SIMD4<Float>(vector[index], vector[index + 1], vector[index + 2], vector[index + 3])
        }
    }
}
