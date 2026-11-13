import Testing
@testable import Aski

struct ShapeContextFootprintTests {
    @Test(arguments: [0, 1, 2, 3, 4, 7, 8, 12, 16, 17, 24, 33])
    func scalarParityAcrossWeightsAndFootprints(width: Int) {
        for height in [0, 1, 2, 3, 5, 8, 12, 16, 24, 31] {
            let footprint = ShapeContext.Footprint(width: width, height: height)
            let count = width * height
            #expect(footprint.width == width)
            #expect(footprint.height == height)
            #expect(footprint.storageByteCount == (min(width, height) > 1 ? count : 0))
            let boundary: [Float] = [0, -0.0, Float(0.05).nextDown, 0.05, Float(0.05).nextUp, 1]
            for weight in boundary {
                assertParity([Float](repeating: weight, count: count), footprint: footprint)
            }
            var state: UInt64 = 0x87
            for _ in 0..<64 {
                let pixels = (0..<count).map { _ -> Float in
                    state = state &* 6_364_136_223_846_793_005 &+ 1
                    return Float((state >> 32) & 0xffff) / 65535
                }
                assertParity(pixels, footprint: footprint)
                assertParity(pixels.map { 1 - $0 }, footprint: footprint)
                // Mix the inclusion boundary into nonuniform accumulation.
                assertParity(
                    pixels.enumerated().map { index, weight in
                        index.isMultiple(of: 3) ? boundary[index % boundary.count] : weight
                    },
                    footprint: footprint
                )
            }
        }
    }

    @Test(arguments: [2, 3, 4, 7, 8, 16, 17])
    func eachPixelHasTheSameBinAndAdmission(width: Int) {
        for height in [2, 3, 5, 8, 12, 17, 24] {
            let footprint = ShapeContext.Footprint(width: width, height: height)
            for index in 0..<(width * height) {
                var pixels = [Float](repeating: 0, count: width * height)
                pixels[index] = 1
                assertParity(pixels, footprint: footprint)
            }
        }
    }

    @Test func degenerateFootprintsNeedNoPixelsOrMapStorage() {
        for (width, height) in [(0, 0), (1, 1), (1, Int.max), (Int.max, 1), (-2, 8), (8, -2)] {
            let footprint = ShapeContext.Footprint(width: width, height: height)
            #expect(footprint.storageByteCount == 0)
            assertParity([], footprint: footprint)
        }
    }

    @Test func exceptionalWeightsKeepScalarSemantics() {
        let footprint = ShapeContext.Footprint(width: 8, height: 12)
        let values: [Float] = [-1, -.infinity, .infinity, .nan, Float(bitPattern: 0x7fc0_0087)]
        for value in values {
            for index in 0..<96 {
                var pixels = [Float](repeating: 0.1, count: 96)
                pixels[index] = value
                assertParity(pixels, footprint: footprint)
            }
        }
    }

    @Test func copiedFootprintsAndReturnedHistogramsAreIndependent() {
        let original = ShapeContext.Footprint(width: 16, height: 24)
        let copy = original
        let pixels = (0..<384).map { Float($0 % 101) / 100 }
        let expected = original.histogram60(pixels)
        var previous = copy.histogram60(pixels)
        previous[0] = -100
        #expect(previous[0] == -100)
        #expect(copy.histogram60(pixels).map(\.bitPattern) == expected.map(\.bitPattern))
        #expect(original.histogram60(pixels).map(\.bitPattern) == expected.map(\.bitPattern))
    }

    @Test func sharedFootprintSupportsConcurrentHistograms() async {
        let footprint = ShapeContext.Footprint(width: 16, height: 24)
        let passed = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for worker in 0..<64 {
                group.addTask {
                    for iteration in 0..<32 {
                        let pixels = (0..<384).map { Float(($0 + worker + iteration) % 257) / 256 }
                        let expected = ShapeContext.histogram60(pixels, width: 16, height: 24)
                        if footprint.histogram60(pixels).map(\.bitPattern) != expected.map(\.bitPattern) {
                            return false
                        }
                    }
                    return true
                }
            }
            var passed = true
            for await result in group { passed = passed && result }
            return passed
        }
        #expect(passed)
    }

    private func assertParity(_ pixels: [Float], footprint: ShapeContext.Footprint) {
        let control = ShapeContext.histogram60(pixels, width: footprint.width, height: footprint.height)
        let prepared = footprint.histogram60(pixels)
        #expect(prepared.count == ShapeContext.dimension)
        #expect(prepared.map(\.bitPattern) == control.map(\.bitPattern))
    }
}
