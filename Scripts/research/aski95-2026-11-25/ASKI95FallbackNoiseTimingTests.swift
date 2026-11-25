import CoreGraphics
import CoreImage
import CryptoKit
import Darwin
import Foundation
import Testing
@testable import Aski

/// ASKI-95 harness. It lives in Scripts/research/aski95-2026-11-25/ and is
/// copied into Tests/AskiTests only for a replay; see that README. Timing is
/// disabled unless ASKI95_TIMING_OUTPUT names a new absolute CSV path.
@Suite(.serialized) struct ASKI95FallbackNoiseTimingTests {
    private static let outputVariable = "ASKI95_TIMING_OUTPUT"
    private static let parityVariable = "ASKI95_PARITY_OUTPUT"
    private static let sizes: [(name: String, width: Int, height: Int)] = [("512x512", 512, 512), ("1920x1080", 1920, 1080)]
    private static let chains: [(name: String, effects: @Sendable (UInt64) -> [Effect])] = [
        ("dust", { [.filmDust(intensity: 1, seed: $0)] }),
        ("grain", { [.filmGrain(intensity: 1, seed: $0)] }),
        ("dust+grain", { [.filmDust(intensity: 1, seed: $0), .filmGrain(intensity: 1, seed: $0)] }),
    ]
    private static let warmups = 3
    private static let repetitions = 15
    private static let fixedSeed: UInt64 = 42

    /// The replica below must stay a verbatim copy of production's private
    /// `seededNoise` and `nextSeededByte`; otherwise its timing is not evidence.
    @Test func replicaMatchesProductionSource() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let production = try String(contentsOf: root.appendingPathComponent("Sources/Aski/Effects/Internal/StockCIEffectKernel.swift"), encoding: .utf8)
        let harness = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        let begin = "    private func seededNoise(extent: CGRect, seed: UInt64) -> CIImage {"
        let productionSlice = try Self.slice(production, from: begin, to: "    private func opaqueChannel")
        let replicaStart = try #require(harness.range(of: "private struct ReplicaKernel {\n"))
        let replicaSlice = try Self.slice(String(harness[replicaStart.upperBound...]), from: begin, to: "    // END ASKI-95 REPLICA")
        #expect(productionSlice == replicaSlice)
    }

    /// Byte equivalence: production's dust and grain fallbacks over a clear
    /// input, rendered in float, must equal the same operations fed the replica
    /// raster. The replica's byte-to-float map is checked to be injective, so
    /// equal float output implies production fed the chain the same raster bytes.
    @Test func replicaRasterMatchesProductionFeed() throws {
        let linear = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let renderer = CIContext(options: [.workingColorSpace: linear, .workingFormat: CIFormat.RGBAf, .cacheIntermediates: false])
        let replica = ReplicaKernel()
        let extents = Self.sizes.map { CGRect(x: 0, y: 0, width: $0.width, height: $0.height) } + [CGRect(x: -7, y: 3, width: 97.5, height: 41.25)]
        for extent in extents {
            for seed in [Self.fixedSeed, Self.fixedSeed &+ 1, Self.fixedSeed &+ 18, 0, .max] {
                for dust in [true, false] {
                    let context = EffectContext(
                        workingColorSpace: linear, outputExtent: extent, renderColorSpace: .sRGB,
                        deviceCapability: .reducedQuality(.metallibUnsupported))
                    let clear = CIImage(color: .clear).cropped(to: extent)
                    let effect: Effect = dust ? .filmDust(intensity: 1, seed: seed) : .filmGrain(intensity: 1, seed: seed)
                    let production = EffectsRenderEngine.runEffectChainSync(clear, effects: EffectChain([effect]), in: context)
                    let noise = replica.noise(extent: extent, seed: seed)
                    let replicated = Self.compose(noise: noise, over: clear, extent: extent, dust: dust)
                    let productionFloats = Self.renderFloats(production, extent: extent, renderer: renderer)
                    let replicaFloats = Self.renderFloats(replicated, extent: extent, renderer: renderer)
                    #expect(productionFloats == replicaFloats, "extent \(extent) seed \(seed) dust \(dust)")
                    // Injectivity of byte -> rendered value on the replica raster,
                    // checked where every rendered pixel is fully covered.
                    guard extent == extent.integral else { continue }
                    let bytes = replica.rasterValues(width: Int(extent.width), height: Int(extent.height), seed: seed)
                    var map: [UInt8: SIMD4<Float>] = [:]
                    var seen: [SIMD4<Float>: UInt8] = [:]
                    for pixel in 0..<(replicaFloats.count / 4) {
                        let value = SIMD4(replicaFloats[pixel * 4], replicaFloats[pixel * 4 + 1], replicaFloats[pixel * 4 + 2], replicaFloats[pixel * 4 + 3])
                        let byte = bytes[pixel]
                        if let previous = map[byte] { #expect(previous == value) } else { map[byte] = value }
                        if let previous = seen[value] { #expect(previous == byte) } else { seen[value] = byte }
                    }
                }
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment[ASKI95FallbackNoiseTimingTests.outputVariable] != nil))
    func exportTimings() throws {
        let path = try #require(ProcessInfo.processInfo.environment[Self.outputVariable])
        try #require(path.hasPrefix("/"), "Timing needs an absolute output path")
        try #require(!FileManager.default.fileExists(atPath: path), "Timing needs a new output file")
        #if DEBUG
            let configuration = "debug"
        #else
            let configuration = "release"
        #endif
        var rows = ["configuration,arm,size,chain,seedMode,repetition,ns"]
        let replica = ReplicaKernel()
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var sink = 0.0

        // Cases run round-robin so drift spreads across all of them.
        typealias Case = (arm: String, size: String, chain: String, seedMode: String, run: (UInt64) -> Void)
        var cases: [Case] = []
        for size in Self.sizes {
            let extent = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            for seedMode in ["same", "changing"] {
                cases.append(("raster", size.name, "single", seedMode, { seed in
                    sink += replica.noise(extent: extent, seed: seed).extent.width
                }))
            }
            let input = try Self.makeInput(width: size.width, height: size.height, space: space)
            for chain in Self.chains {
                for arm in ["fallback", "metal"] {
                    for seedMode in ["same", "changing"] {
                        let capability: DeviceCapability = arm == "fallback" ? .reducedQuality(.metallibUnsupported) : .full
                        let context = EffectContext(
                            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
                            outputExtent: extent,
                            renderColorSpace: .sRGB,
                            deviceCapability: capability
                        )
                        cases.append((arm, size.name, chain.name, seedMode, { seed in
                            let final = EffectsRenderEngine.runEffectChainSync(input, effects: EffectChain(chain.effects(seed)), in: context)
                            let image = EffectsRenderEngine.shared.context.createCGImage(final, from: extent, format: .RGBA8, colorSpace: space)
                            sink += Double(image?.width ?? 0)
                        }))
                    }
                }
            }
        }
        try #require(MetalSupport.supportsStitchableKernels(), "The metal control arm needs a stitchable-kernel device")

        var calls = [Int](repeating: 0, count: cases.count)
        for repetition in -Self.warmups..<Self.repetitions {
            for (index, item) in cases.enumerated() {
                let seed = item.seedMode == "same" ? Self.fixedSeed : Self.fixedSeed &+ 1 &+ UInt64(calls[index])
                calls[index] += 1
                let begin = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                item.run(seed)
                let elapsed = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - begin
                if repetition >= 0 {
                    rows.append("\(configuration),\(item.arm),\(item.size),\(item.chain),\(item.seedMode),\(repetition),\(elapsed)")
                }
            }
        }
        #expect(sink > 0)
        try (rows.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Exact-output inventory for the control/candidate comparison: every timed
    /// configuration, three same-seed renders then five changing seeds, in order.
    @Test(.enabled(if: ProcessInfo.processInfo.environment[ASKI95FallbackNoiseTimingTests.parityVariable] != nil))
    func exportParityHashes() throws {
        let path = try #require(ProcessInfo.processInfo.environment[Self.parityVariable])
        try #require(path.hasPrefix("/"), "Parity needs an absolute output path")
        try #require(!FileManager.default.fileExists(atPath: path), "Parity needs a new output file")
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try #require(MetalSupport.supportsStitchableKernels(), "The metal arm needs a stitchable-kernel device")
        var rows = ["arm,size,chain,step,seed,width,height,sha256"]
        for size in Self.sizes {
            let extent = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            let input = try Self.makeInput(width: size.width, height: size.height, space: space)
            for chain in Self.chains {
                for arm in ["fallback", "metal"] {
                    let context = EffectContext(
                        workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
                        outputExtent: extent,
                        renderColorSpace: .sRGB,
                        deviceCapability: arm == "fallback" ? .reducedQuality(.metallibUnsupported) : .full
                    )
                    let seeds = [Self.fixedSeed, Self.fixedSeed, Self.fixedSeed] + (1...5).map { Self.fixedSeed &+ UInt64($0) }
                    for (step, seed) in seeds.enumerated() {
                        let final = EffectsRenderEngine.runEffectChainSync(input, effects: EffectChain(chain.effects(seed)), in: context)
                        let image = try #require(EffectsRenderEngine.shared.context.createCGImage(final, from: extent, format: .RGBA8, colorSpace: space))
                        let data = try #require(image.dataProvider?.data) as Data
                        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                        rows.append("\(arm),\(size.name),\(chain.name),\(step),\(seed),\(image.width),\(image.height),\(digest)")
                    }
                }
            }
        }
        try (rows.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// The production dust/grain operations, applied to a given noise image.
    private static func compose(noise: CIImage, over image: CIImage, extent: CGRect, dust: Bool) -> CIImage {
        let opacity = CGFloat(dust ? 0.2 : 0.15)
        let matrix = CIFilter(name: "CIColorMatrix")!
        matrix.setValue(noise, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: opacity), forKey: "inputAVector")
        let layer = (matrix.outputImage ?? noise).cropped(to: extent)
        let blend = CIFilter(name: dust ? "CISourceOverCompositing" : "CIScreenBlendMode")!
        blend.setValue(layer, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    private static func renderFloats(_ image: CIImage, extent: CGRect, renderer: CIContext) -> [Float] {
        let bounds = extent.integral
        let width = Int(bounds.width), height = Int(bounds.height)
        var values = [Float](repeating: .nan, count: width * height * 4)
        values.withUnsafeMutableBytes { buffer in
            renderer.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: bounds, format: .RGBAf, colorSpace: nil)
        }
        return values
    }

    private static func makeInput(width: Int, height: Int, space: CGColorSpace) throws -> CIImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let colors = [CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1), CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1)]
        let gradient = try #require(CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]))
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        return CIImage(cgImage: try #require(context.makeImage()))
    }

    private static func slice(_ text: String, from begin: String, to end: String) throws -> String {
        let start = try #require(text.range(of: begin))
        let stop = try #require(text.range(of: end, range: start.upperBound..<text.endIndex))
        return String(text[start.lowerBound..<stop.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ReplicaKernel {
    private func seededNoise(extent: CGRect, seed: UInt64) -> CIImage {
        let width = max(1, Int(ceil(extent.width)))
        let height = max(1, Int(ceil(extent.height)))
        var state = seed
        let byteCount = width * height * 4
        guard let data = CFDataCreateMutable(nil, byteCount) else {
            return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        }
        CFDataSetLength(data, byteCount)
        guard let bytes = CFDataGetMutableBytePtr(data) else {
            return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        }
        for offset in stride(from: 0, to: byteCount, by: 4) {
            let value = nextSeededByte(&state)
            bytes[offset] = value
            bytes[offset + 1] = value
            bytes[offset + 2] = value
            bytes[offset + 3] = 255
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard
            let provider = CGDataProvider(data: data),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        }

        return CIImage(cgImage: image)
            .transformed(by: .init(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    private func nextSeededByte(_ state: inout UInt64) -> UInt8 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return UInt8(truncatingIfNeeded: value >> 56)
    }

    // END ASKI-95 REPLICA
}

extension ReplicaKernel {
    func noise(extent: CGRect, seed: UInt64) -> CIImage { seededNoise(extent: extent, seed: seed) }

    /// The grey value of each replica pixel in CGImage row order.
    func rasterValues(width: Int, height: Int, seed: UInt64) -> [UInt8] {
        var state = seed
        return (0..<(width * height)).map { _ in nextSeededByte(&state) }
    }
}
