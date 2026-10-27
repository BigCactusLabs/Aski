import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Aski

/// ASKI-95: force the reduced-capability route even on a Metal-capable Mac.
/// These small deterministic fixtures are not fallback-frequency or perf data.
@Suite struct FallbackNoiseGroundworkTests {
    @Test(arguments: [0, 1, 2])
    func reducedRouteMatchesStockAndSurvivesSeedAndExtentChanges(mode: Int) throws {
        let renderer = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let extents = [
            CGRect(x: 0, y: 0, width: 32, height: 24),
            CGRect(x: -7, y: 3, width: 32, height: 24),
            CGRect(x: 3.25, y: -2.5, width: 31.25, height: 15.75),
        ]
        for extent in extents {
            for seed in [UInt64(0), 42, .max] {
                let first = try Self.render(mode: mode, seed: seed, extent: extent, routed: true, renderer: renderer)
                let direct = try Self.render(mode: mode, seed: seed, extent: extent, routed: false, renderer: renderer)
                #expect(first == direct)
                let changed = try Self.render(mode: mode, seed: seed &+ 1, extent: extent, routed: true, renderer: renderer)
                #expect(changed != first)
                _ = try Self.render(mode: mode, seed: seed, extent: CGRect(x: 1, y: 2, width: 19, height: 11), routed: true, renderer: renderer)
                #expect(try Self.render(mode: mode, seed: seed, extent: extent, routed: true, renderer: renderer) == first)
            }
        }
    }

    @Test func intermediateCachingDoesNotChangeForcedFallbackPixels() throws {
        let cold = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let warm = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: true])
        let extent = CGRect(x: 0, y: 0, width: 32, height: 24)
        for mode in 0..<3 {
            let expected = try Self.render(mode: mode, seed: 42, extent: extent, routed: true, renderer: cold)
            for _ in 0..<3 {
                #expect(try Self.render(mode: mode, seed: 42, extent: extent, routed: true, renderer: warm) == expected)
            }
        }
    }

    @Test func concurrentCallsDoNotMixSeeds() async throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 24)
        let renderer = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let expected = try (0..<16).map { try Self.render(mode: 2, seed: UInt64($0), extent: extent, routed: true, renderer: renderer) }
        try await withThrowingTaskGroup(of: (Int, [UInt8]).self) { group in
            for index in 0..<16 {
                group.addTask {
                    // Each task owns its context; a future shared raster cache
                    // still has to keep these simultaneous seeds independent.
                    let local = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
                    return (index, try Self.render(mode: 2, seed: UInt64(index), extent: extent, routed: true, renderer: local))
                }
            }
            for try await (index, bytes) in group { #expect(bytes == expected[index]) }
        }
    }

    private static func render(mode: Int, seed: UInt64, extent: CGRect, routed: Bool, renderer: CIContext) throws -> [UInt8] {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = EffectContext(
            workingColorSpace: space, outputExtent: extent, renderColorSpace: .sRGB,
            deviceCapability: .reducedQuality(.metallibUnsupported))
        var image = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.3)).cropped(to: extent)
        for effect in mode == 2 ? [0, 1] : [mode] {
            let stock = StockCIEffectKernel(kind: effect == 0 ? .filmDustApprox(intensity: 1, seed: seed) : .filmGrainApprox(intensity: 1, seed: seed))
            if routed {
                let kernel = MetallibEffectKernel(kind: effect == 0 ? .filmDust(intensity: 1, seed: seed) : .filmGrain(intensity: 1, seed: seed), fallback: stock)
                image = try kernel.apply(to: image, in: context)
            } else {
                image = try stock.apply(to: image, in: context)
            }
        }
        #expect(image.extent == extent)
        // Force evaluation. Merely black-holing a CIImage would leave the
        // filter recipe deferred. Integral bounds also include fractional edges.
        let bounds = extent.integral
        let width = Int(bounds.width), height = Int(bounds.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            renderer.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 4, bounds: bounds, format: .RGBA8, colorSpace: space)
        }
        return bytes
    }
}
