import CoreGraphics
import Foundation
import Testing
@testable import AskiHDRLab

/// A1 (ASTSK-10): prove the G4 float scanner (`HDRArtifacts.floatStats`) actually
/// *fires*. The renderer pre-clamps to `maxHeadroom` and pre-guards NaN/Inf, so on
/// real output `floatStats` never observes a bad value — its only prior "test" was
/// a verbatim re-implementation in `ExtendedRangeRenderTests`, which proved nothing.
/// Here we hand-craft 16-bit half-float buffers (via `CGDataProvider`, using the
/// direct-buffer pattern from the image fixtures) with a known NaN, a known
/// over-ceiling value, and a clean control, and assert the detector classifies each
/// correctly. This makes G4 a *proven* clamp/finite-regression guard.
@Suite struct HDRArtifactsTests {
    static let maxHeadroom: Float = 4

    /// Build a 16-bit half-float RGBA image from a flat row-major sample buffer
    /// (little-endian Float16, the exact layout the renderer writes and `floatStats`
    /// reads). `mutate` lets a single test poison one sample.
    static func halfFloatImage(
        width: Int = 3,
        height: Int = 3,
        fill: Float16 = 0.5,
        mutate: ((inout [Float16]) -> Void)? = nil
    ) -> CGImage {
        var samples = [Float16](repeating: fill, count: width * height * 4)
        mutate?(&samples)
        var bytes = [UInt8]()
        bytes.reserveCapacity(samples.count * 2)
        for sample in samples {
            let bits = sample.bitPattern
            bytes.append(UInt8(bits & 0xFF))
            bytes.append(UInt8(bits >> 8))
        }
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            .floatComponents,
            .byteOrder16Little,
        ]
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: width * 8,
            space: space, bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    @Test func detectsCleanBuffer() {
        let image = Self.halfFloatImage(fill: 0.5)
        let stats = HDRArtifacts.floatStats(image, maxHeadroom: Self.maxHeadroom)
        #expect(!stats.hasNaNOrInf, "clean buffer has no NaN/Inf")
        #expect(!stats.exceedsCeiling, "clean buffer is within the ceiling")
        #expect(abs(stats.maxChannel - 0.5) < 1e-3, "peak channel is the fill value")
    }

    @Test func detectsNaN() {
        let image = Self.halfFloatImage(fill: 0.5) { samples in
            samples[0] = Float16.nan
        }
        let stats = HDRArtifacts.floatStats(image, maxHeadroom: Self.maxHeadroom)
        #expect(stats.hasNaNOrInf, "a planted NaN must be detected")
    }

    @Test func detectsInfinity() {
        let image = Self.halfFloatImage(fill: 0.5) { samples in
            samples[0] = Float16.infinity
        }
        let stats = HDRArtifacts.floatStats(image, maxHeadroom: Self.maxHeadroom)
        #expect(stats.hasNaNOrInf, "a planted Inf must be detected")
    }

    @Test func detectsOverCeiling() {
        // maxHeadroom = 4; plant a 5.0 (> ceiling 4 + 1e-3).
        let image = Self.halfFloatImage(fill: 0.5) { samples in
            samples[0] = 5.0
        }
        let stats = HDRArtifacts.floatStats(image, maxHeadroom: Self.maxHeadroom)
        #expect(stats.exceedsCeiling, "a value above maxHeadroom must be detected")
        #expect(stats.maxChannel >= 5.0 - 1e-2, "peak channel reflects the over-ceiling value")
    }

    @Test func ceilingIsInclusiveAtMaxHeadroom() {
        // A value exactly at the ceiling (within the 1e-3 slack) must NOT trip.
        let image = Self.halfFloatImage(fill: Float16(Self.maxHeadroom))
        let stats = HDRArtifacts.floatStats(image, maxHeadroom: Self.maxHeadroom)
        #expect(!stats.exceedsCeiling, "exactly-at-ceiling must not be flagged")
        #expect(!stats.hasNaNOrInf)
    }
}
