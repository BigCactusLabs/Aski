import Testing
@testable import Aski

@Suite struct TileColorSampleStorageTests {
    @Test func packedStoragePreservesEveryLaneBit() {
        let special: [UInt32] = [0, 0x8000_0000, 1, 0x007F_FFFF, 0x3F80_0000, 0x7F7F_FFFF, 0x7F80_0000, 0xFF80_0000, 0x7FC0_1234]
        var state: UInt32 = 92
        for index in 0..<10_000 {
            var bits: [UInt32] = []
            for lane in 0..<4 {
                state = state &* 1_664_525 &+ 1_013_904_223
                bits.append(index < special.count ? special[(index + lane) % special.count] : state)
            }
            let sample = TilePalette.ColorSample(
                oklab: SIMD3(Float(bitPattern: bits[0]), Float(bitPattern: bits[1]), Float(bitPattern: bits[2])),
                alpha: Float(bitPattern: bits[3])
            )
            #expect(sample.oklab.x.bitPattern == bits[0])
            #expect(sample.oklab.y.bitPattern == bits[1])
            #expect(sample.oklab.z.bitPattern == bits[2])
            #expect(sample.alpha.bitPattern == bits[3])
        }
    }

    @Test func packedArrayUsesFourFloatStride() {
        struct PreviousSample {
            let oklab: SIMD3<Float>
            let alpha: Float
        }
        #expect(MemoryLayout<TilePalette.ColorSample>.stride == 4 * MemoryLayout<Float>.stride)
        #expect(MemoryLayout<TilePalette.ColorSample>.stride < MemoryLayout<PreviousSample>.stride)
    }

    @Test func samplesSupportIndependentCopiesAndConcurrentReads() async {
        let samples = (0..<64).map { index in
            TilePalette.ColorSample(oklab: SIMD3(Float(index), -Float(index), Float(index) / 64), alpha: 0.5)
        }
        var copy = samples
        copy.removeLast()
        #expect(samples.count == 64)
        #expect(copy.count == 63)
        let valid = await withTaskGroup(of: Bool.self) { group in
            for index in samples.indices {
                group.addTask {
                    let sample = samples[index]
                    return sample.oklab.x.bitPattern == Float(index).bitPattern && sample.alpha.bitPattern == Float(0.5).bitPattern
                }
            }
            var valid = true
            for await result in group { valid = valid && result }
            return valid
        }
        #expect(valid)
    }
}
