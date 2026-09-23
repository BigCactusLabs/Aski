import Dispatch
import Testing
import simd
@testable import Aski

@Suite struct WuQuantizationTests {

    /// Build a deterministic image with many more source colors than a small cap.
    private static func manyDistinctColors(width: Int, height: Int) -> [UInt8] {
        precondition(width > 0 && height > 0)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let off = (y * width + x) * 4
                pixels[off + 0] = UInt8((x % 32) * 8)
                pixels[off + 1] = UInt8((y % 32) * 8)
                pixels[off + 2] = UInt8(((x + y) % 32) * 8)
                pixels[off + 3] = 255
            }
        }
        return pixels
    }

    private static func oklabForSRGB(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> SIMD3<Float> {
        ColorConversion.linearSRGBToOKLAB(
            SIMD3(
                ColorConversion.sRGBDecode(Float(r) / 255),
                ColorConversion.sRGBDecode(Float(g) / 255),
                ColorConversion.sRGBDecode(Float(b) / 255)
            ))
    }

    @Test func deterministic() {
        let pixels = WuQuantizationTestsFixture.fourQuadrants(width: 64, height: 64)
        let q1 = WuQuantizer(pixels: pixels, width: 64, height: 64, colorSpace: .sRGB)
        let q2 = WuQuantizer(pixels: pixels, width: 64, height: 64, colorSpace: .sRGB)
        let p1 = q1.palette(maxColors: 4)
        let p2 = q2.palette(maxColors: 4)
        #expect(p1.count == p2.count)
        for (a, b) in zip(p1, p2) {
            #expect(simd_length(a - b) < 1e-6)
        }
    }

    @Test func outputCountAtMostMaxColors() {
        let width = 32, height = 32
        let maxColors = 8
        let pixels = Self.manyDistinctColors(width: width, height: height)
        let palette = WuQuantizer(pixels: pixels, width: width, height: height, colorSpace: .sRGB)
            .palette(maxColors: maxColors)
        #expect(palette.count <= maxColors)
    }

    @Test func fourQuadrantsYieldsFourClusters() {
        let pixels = WuQuantizationTestsFixture.fourQuadrants(width: 64, height: 64)
        let palette = WuQuantizer(pixels: pixels, width: 64, height: 64, colorSpace: .sRGB)
            .palette(maxColors: 4)
        // We expect 4 distinct centroids - one near each input quadrant color.
        #expect(palette.count == 4)
        let distinctThreshold: Float = 0.05
        for i in palette.indices {
            for j in palette.indices where j > i {
                #expect(simd_length(palette[i] - palette[j]) > distinctThreshold)
            }
        }
        let expected = [
            Self.oklabForSRGB(255, 0, 0),
            Self.oklabForSRGB(0, 255, 0),
            Self.oklabForSRGB(0, 0, 255),
            Self.oklabForSRGB(255, 255, 255),
        ]
        let matchThreshold: Float = 0.05
        for color in expected {
            let nearestDistance = palette.reduce(Float.infinity) { nearest, centroid in
                min(nearest, simd_length(centroid - color))
            }
            #expect(nearestDistance < matchThreshold)
        }
    }

    @Test func fullyTransparentReturnsEmptyPalette() {
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        // All RGBA zero == fully transparent, all-black premul. alpha == 0 -> skipped.
        for i in 0..<(16 * 16) {
            pixels[i * 4 + 3] = 0
        }
        let palette = WuQuantizer(pixels: pixels, width: 16, height: 16, colorSpace: .sRGB)
            .palette(maxColors: 4)
        #expect(palette.isEmpty)
    }

    @Test func singleSolidColorReturnsOneOrTwoCentroids() {
        // A near-monochrome input cannot manufacture 16 distinct palette entries.
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        for i in 0..<(32 * 32) {
            pixels[i * 4 + 0] = 128
            pixels[i * 4 + 1] = 128
            pixels[i * 4 + 2] = 128
            pixels[i * 4 + 3] = 255
        }
        let palette = WuQuantizer(pixels: pixels, width: 32, height: 32, colorSpace: .sRGB)
            .palette(maxColors: 16)
        // All pixels land in one bin; the algorithm marks the box terminal and
        // emits its centroid. Output is 1 (or up to 2 if a different bin sees a
        // rounding-edge pixel).
        #expect(palette.count >= 1)
        #expect(palette.count <= 2)
    }

    @Test func centroidsLieWithinSourceBoundingBox() {
        // Spec §8 calls for "palette colors within source image's OKLAB convex
        // hull." A bounding-box check (axis-aligned min/max in OKLAB) is a
        // weaker proxy that catches cluster-out-of-input regressions without
        // implementing 3D convex-hull math.
        let pixels = WuQuantizationTestsFixture.fourQuadrants(width: 64, height: 64)
        let palette = WuQuantizer(pixels: pixels, width: 64, height: 64, colorSpace: .sRGB)
            .palette(maxColors: 16)

        // Compute axis-aligned bounding box of input OKLAB.
        var loL: Float = .infinity, hiL: Float = -.infinity
        var loA: Float = .infinity, hiA: Float = -.infinity
        var loB: Float = .infinity, hiB: Float = -.infinity
        for i in 0..<(64 * 64) {
            let off = i * 4
            let alpha = Float(pixels[off + 3]) / 255
            if alpha == 0 { continue }
            let r = Float(pixels[off]) / 255 / alpha
            let g = Float(pixels[off + 1]) / 255 / alpha
            let b = Float(pixels[off + 2]) / 255 / alpha
            let lab = ColorConversion.linearSRGBToOKLAB(
                SIMD3(
                    ColorConversion.sRGBDecode(min(r, 1)),
                    ColorConversion.sRGBDecode(min(g, 1)),
                    ColorConversion.sRGBDecode(min(b, 1))
                ))
            loL = min(loL, lab.x); hiL = max(hiL, lab.x)
            loA = min(loA, lab.y); hiA = max(hiA, lab.y)
            loB = min(loB, lab.z); hiB = max(hiB, lab.z)
        }
        // Allow a small slack for binning + alpha-weighted centroid arithmetic.
        let slack: Float = 0.02
        for c in palette {
            #expect(c.x >= loL - slack && c.x <= hiL + slack)
            #expect(c.y >= loA - slack && c.y <= hiA + slack)
            #expect(c.z >= loB - slack && c.z <= hiB + slack)
        }
    }

    @Test func performanceSanity1MP64Colors() {
        // Spec §8 calls for "1MP + 64 colors < 100ms" on M-series. Wall-clock
        // assertions in unit tests are flaky in debug builds and on slower CI,
        // so this is a *catastrophic-regression* sanity check (5s ceiling)
        // rather than the 100ms target - it catches infinite loops, runaway
        // allocation, or O(n^2) regressions, but not micro-regressions. The
        // tighter 100ms target is monitored by `tile-converter-256cols-adaptive16`
        // in the benchmarks target (Task 30), which is the canonical perf
        // tracker.
        let width = 1024, height = 1024
        let pixels = WuQuantizationTestsFixture.fourQuadrants(width: width, height: height)
        let start = DispatchTime.now().uptimeNanoseconds
        _ = WuQuantizer(pixels: pixels, width: width, height: height, colorSpace: .sRGB)
            .palette(maxColors: 64)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        #expect(elapsed < 5.0, "Wu quantization at 1MPx64 took \(elapsed)s; expected <5s catastrophic ceiling")
    }
}
