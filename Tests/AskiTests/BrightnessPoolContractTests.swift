import Testing
@_spi(AskiResearch) @testable import Aski

/// ASKI-88: characterize the existing pool, not a new brightness policy.
/// The portable probe compiles only the exact extracted poolIndices method.
@Suite struct BrightnessPoolContractTests {
    @Test func shuffledCandidatesUseDistanceThenOriginalIndex() {
        let values: [Float] = [0.75, 0.25, 0.5, 1, 0]
        #expect(ShapeMatching.poolIndices(queryBrightness: 0.5, candidateBrightness: values, topK: 5) == [2, 0, 1, 3, 4])
    }

    @Test func distinctBrightnessValuesCanHaveEqualRoundedFloatDistances() {
        let tiny = Float(1) / Float(1 << 26)
        #expect(abs(Float(0) - 1) == abs(tiny - 1))
        #expect(abs(Double(0) - 1) > abs(Double(tiny) - 1))
        // Widening the subtraction to Double would reverse these two entries.
        #expect(ShapeMatching.poolIndices(queryBrightness: 1, candidateBrightness: [0, tiny], topK: 2) == [0, 1])
    }

    @Test func exactMidpointAndItsNeighborsKeepDifferentOrders() {
        let values: [Float] = [0.75, 0.25]
        #expect(ShapeMatching.poolIndices(queryBrightness: Float(0.5).nextDown, candidateBrightness: values, topK: 2) == [1, 0])
        #expect(ShapeMatching.poolIndices(queryBrightness: 0.5, candidateBrightness: values, topK: 2) == [0, 1])
        #expect(ShapeMatching.poolIndices(queryBrightness: Float(0.5).nextUp, candidateBrightness: values, topK: 2) == [0, 1])
    }

    @Test func signedZeroAndDuplicateValuesKeepOriginalIndices() {
        let values: [Float] = [-0.0, 0.0, -0.0, 0.0]
        #expect(ShapeMatching.poolIndices(queryBrightness: -0.0, candidateBrightness: values, topK: 8) == [0, 1, 2, 3])
        #expect(ShapeMatching.poolIndices(queryBrightness: 0.5, candidateBrightness: Array(repeating: 0.25, count: 95), topK: 12) == Array(0..<12))
    }

    @Test func finiteInputsWhoseSubtractionOverflowsStillHaveIndexTies() {
        let largest = Float.greatestFiniteMagnitude
        let values: [Float] = [-largest, largest / 2, 0, -largest / 2]
        #expect(abs(values[0] - largest) == .infinity)
        #expect(abs(values[3] - largest) == .infinity)
        #expect(ShapeMatching.poolIndices(queryBrightness: largest, candidateBrightness: values, topK: 4) == [1, 2, 0, 3])
    }

    @Test(arguments: [8, 95, 256])
    func everyLimitIsAnExactPrefixAndInputIsUnchanged(count: Int) {
        let values = BrightnessPoolFixtures.values(count: count, seed: 17)
        let before = values.map(\.bitPattern)
        let expected = BrightnessPoolFixtures.rankOrder(query: 0.5, values: values)
        for limit in 1...(count + 1) {
            #expect(ShapeMatching.poolIndices(queryBrightness: 0.5, candidateBrightness: values, topK: limit) == Array(expected.prefix(limit)))
        }
        #expect(values.map(\.bitPattern) == before)
    }

    @Test(arguments: [8, 95, 256])
    func seededCasesMatchIndependentRankCounting(count: Int) {
        for seed in UInt64(0)..<64 {
            let values = BrightnessPoolFixtures.values(count: count, seed: seed)
            for query in [Float(0), 0.5, values[Int(seed) % count], 1] {
                let expected = BrightnessPoolFixtures.rankOrder(query: query, values: values)
                for limit in [1, 12, 24, 36, count, count + 1] {
                    #expect(ShapeMatching.poolIndices(queryBrightness: query, candidateBrightness: values, topK: limit) == Array(expected.prefix(limit)))
                }
            }
        }
    }

    @Test func immutableInputsAreSafeToShareAcrossConcurrentCalls() async {
        let values = BrightnessPoolFixtures.values(count: 256, seed: 999)
        let expected = BrightnessPoolFixtures.rankOrder(query: 0.5, values: values)
        await withTaskGroup(of: [Int].self) { group in
            for _ in 0..<64 {
                group.addTask { ShapeMatching.poolIndices(queryBrightness: 0.5, candidateBrightness: values, topK: 24) }
            }
            for await result in group { #expect(result == Array(expected.prefix(24))) }
        }
    }
}

/// Rank counting is independent of a sort/heap implementation. Restricted to
/// finite inputs; computed distances may overflow to infinity, but never NaN.
enum BrightnessPoolFixtures {
    static func rankOrder(query: Float, values: [Float]) -> [Int] {
        let distances = values.map { abs($0 - query) }
        var order = Array(repeating: -1, count: values.count)
        for index in values.indices {
            var rank = 0
            for other in values.indices {
                if distances[other] < distances[index] || (distances[other] == distances[index] && other < index) {
                    rank += 1
                }
            }
            order[rank] = index
        }
        return order
    }

    static func values(count: Int, seed: UInt64) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            // A small, exactly representable alphabet intentionally creates ties.
            return Float((state >> 32) % 129) / 128
        }
    }
}
