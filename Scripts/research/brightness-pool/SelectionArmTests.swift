import Testing
@_spi(AskiResearch) @testable import Aski

@Suite struct SelectionArmTests {
    @Test(arguments: [8, 95, 256])
    func finiteArmsMatchTheActualExtractedControl(count: Int) {
        for seed in UInt64(0)..<128 {
            let values = BrightnessPoolFixtures.values(count: count, seed: seed)
            for query in [Float(0), 0.5, values[Int(seed) % count], 1] {
                for limit in [1, 12, 24, 36, count, count + 1] {
                    let expected = ShapeMatching.poolIndices(queryBrightness: query, candidateBrightness: values, topK: limit)
                    #expect(PoolSelectionArms.insertion(query: query, values: values, limit: limit) == expected)
                    #expect(PoolSelectionArms.heap(query: query, values: values, limit: limit) == expected)
                }
            }
        }
    }

    @Test func allLimitsHandleEqualRoundedDistancesSignedZeroAndOverflow() {
        let largest = Float.greatestFiniteMagnitude
        let tiny = Float(1) / Float(1 << 26)
        let cases: [(Float, [Float])] = [
            (1, [0, tiny, 0, tiny]),
            (-0.0, [-0.0, 0, -0.0, Float.leastNonzeroMagnitude]),
            (largest, [-largest, largest / 2, 0, -largest / 2]),
            (0.5, Array(repeating: 0.5, count: 256)),
            (0.5, [0.75, 0.25, 0.5, 1, 0]),
        ]
        for (query, values) in cases {
            for limit in 1...(values.count + 1) {
                let expected = ShapeMatching.poolIndices(queryBrightness: query, candidateBrightness: values, topK: limit)
                #expect(PoolSelectionArms.insertion(query: query, values: values, limit: limit) == expected)
                #expect(PoolSelectionArms.heap(query: query, values: values, limit: limit) == expected)
            }
        }
    }

    @Test func nonfiniteInputsDelegateToControlWithoutDefiningANewOrder() {
        // Same-host compatibility only. NaN violates the old sort's strict weak
        // ordering requirement; no literal NaN ordering is made a new contract.
        for query in [Float.nan, .infinity, -.infinity, 0.5] {
            for values: [Float] in [[.nan, 0.25, 0.75], [.infinity, 0, -.infinity], [0, 0.5, 1]] {
                let expected = ShapeMatching.poolIndices(queryBrightness: query, candidateBrightness: values, topK: 2)
                #expect(PoolSelectionArms.insertion(query: query, values: values, limit: 2) == expected)
                #expect(PoolSelectionArms.heap(query: query, values: values, limit: 2) == expected)
            }
        }
    }

    @Test func sharedInputsHaveNoCrossCallScratch() async {
        let values = BrightnessPoolFixtures.values(count: 256, seed: 97)
        await withTaskGroup(of: Bool.self) { group in
            for index in 0..<64 {
                group.addTask {
                    let query = Float(index) / 64
                    let expected = ShapeMatching.poolIndices(queryBrightness: query, candidateBrightness: values, topK: 24)
                    return PoolSelectionArms.insertion(query: query, values: values, limit: 24) == expected
                        && PoolSelectionArms.heap(query: query, values: values, limit: 24) == expected
                }
            }
            for await equal in group { #expect(equal) }
        }
    }
}
