@_spi(AskiResearch) import Aski
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
#if canImport(AppKit)
    import AppKit
#endif

enum HDRArtifactError: Error, CustomStringConvertible {
    case heicEncodeFailed
    var description: String {
        switch self {
        case .heicEncodeFailed: "Core Image heifRepresentation(options: [.hdrImage:]) returned nil"
        }
    }
}

/// Core Image / ImageIO work for the gain-map Adaptive HDR HEIC round-trip and
/// the float-integrity scan. Every method is synchronous and runs on the caller's
/// thread. The two Core Image entry points (`writeGainMapHEIC`, `toneMappedMeanDiff`)
/// take a `CIContext` from the caller — `HDRLabCLI.gather` builds **one** for the
/// whole run instead of one per sample — so the non-`Sendable` `CIContext` and
/// `@MainActor` `NSScreen` stay confined to that single synchronous call tree.
enum HDRArtifacts {
    /// G4 — scan a 16-bit half-float image: peak channel, any NaN/Inf, any value
    /// above the headroom ceiling. Reads the data provider directly (little-endian
    /// Float16; honours row padding).
    ///
    /// This is a *regression* guard on the renderer's headroom-clamp + finite
    /// contract (which pre-clamps and pre-guards), **not** an independent oracle:
    /// on faithful output it never observes a bad value. `HDRArtifactsTests` proves
    /// the detector actually fires by feeding it crafted NaN / over-ceiling buffers.
    static func floatStats(_ image: CGImage, maxHeadroom: Float) -> (maxChannel: Float, hasNaNOrInf: Bool, exceedsCeiling: Bool) {
        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        guard image.bitsPerComponent == 16,
            let data = image.dataProvider?.data,
            let base = CFDataGetBytePtr(data)
        else {
            return (.nan, true, true)
        }
        var maxChannel: Float = 0
        var hasNaNOrInf = false
        var exceedsCeiling = false
        let ceiling = maxHeadroom + 1e-3
        for y in 0..<height {
            let row = base + y * bytesPerRow
            for sample in 0..<(width * 4) {
                let offset = sample * 2
                let bits = UInt16(row[offset]) | (UInt16(row[offset + 1]) << 8)
                let value = Float(Float16(bitPattern: bits))
                if value.isNaN || value.isInfinite { hasNaNOrInf = true; continue }
                if value > maxChannel { maxChannel = value }
                if value > ceiling { exceedsCeiling = true }
            }
        }
        return (maxChannel, hasNaNOrInf, exceedsCeiling)
    }

    /// Writes a gain-map Adaptive HDR HEIC: Core Image derives the gain map from
    /// the SDR base + HDR variant and embeds it as an auxiliary image. `format:
    /// .RGBA8` is the SDR+gain-map standard; `gamutSpace` is the grid's own CG
    /// space (never a hardcoded P3).
    static func writeGainMapHEIC(sdr: CGImage, hdr: CGImage, gamutSpace: CGColorSpace, ciContext: CIContext, to url: URL) throws {
        let sdrCI = CIImage(cgImage: sdr)
        let hdrCI = CIImage(cgImage: hdr)
        guard
            let data = ciContext.heifRepresentation(
                of: sdrCI,
                format: .RGBA8,
                colorSpace: gamutSpace,
                options: [.hdrImage: hdrCI]
            )
        else {
            throw HDRArtifactError.heicEncodeFailed
        }
        try data.write(to: url)
    }

    /// G3 — content headroom of the HEIC's HDR (gain map applied). Loads with
    /// `.expandToHDR` so the gain map is reconstructed; `1.0` means no HDR.
    static func contentHeadroom(ofHEIC url: URL) -> Float {
        guard let ci = CIImage(contentsOf: url, options: [.expandToHDR: true]) else { return 1 }
        return ci.contentHeadroom
    }

    /// G1 — mean per-channel difference (0...1) between the HEIC's embedded SDR
    /// base and the SDR render. The base is the plain (non-expanded) decode.
    static func sdrBaseMeanDiff(heic url: URL, vs sdr: CGImage) -> Float {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let base = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return .infinity }
        return meanChannelDiff(base, sdr)
    }

    /// G2 — mean per-channel difference between the HEIC's HDR tone-mapped down to
    /// headroom 1 and the SDR render. Confirms the system's automatic SDR fallback.
    static func toneMappedMeanDiff(heic url: URL, gamutSpace: CGColorSpace, ciContext: CIContext, vs sdr: CGImage) -> Float {
        guard let hdrCI = CIImage(contentsOf: url, options: [.expandToHDR: true]) else { return .infinity }
        let mapped = hdrCI.applyingFilter("CIToneMapHeadroom", parameters: ["inputTargetHeadroom": 1.0])
        guard let cg = ciContext.createCGImage(mapped, from: mapped.extent, format: .RGBA8, colorSpace: gamutSpace) else {
            return .infinity
        }
        return meanChannelDiff(cg, sdr)
    }

    /// Best-effort 16-bit reference TIFF for visual inspection (not a gate).
    @discardableResult
    static func writeTIFF(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// Best-effort EDR headroom of the dev display. `nil` when off the main thread
    /// or headless (no window-server session) — recorded as `n/a`, never a gate.
    static func displayEDRHeadroom() -> Double? {
        #if canImport(AppKit)
            guard Thread.isMainThread else { return nil }
            return MainActor.assumeIsolated {
                NSScreen.main.map { Double($0.maximumPotentialExtendedDynamicRangeColorComponentValue) }
            }
        #else
            return nil
        #endif
    }

    // MARK: - Helpers

    private static func meanChannelDiff(_ a: CGImage, _ b: CGImage) -> Float {
        // Fidelity gate: a size mismatch means the HEIC round-trip changed dimensions
        // (truncated/scaled decode). Cropping to the smaller side would mask that and
        // let G1/G2 pass on a tiny diff, so fail hard instead.
        guard a.width == b.width, a.height == b.height else { return .infinity }
        let width = a.width
        let height = a.height
        guard width > 0, height > 0 else { return .infinity }
        let bytesA = raster8(a, width, height)
        let bytesB = raster8(b, width, height)
        var sum: Double = 0
        for i in 0..<(width * height * 4) {
            sum += abs(Double(bytesA[i]) - Double(bytesB[i]))
        }
        return Float(sum / Double(width * height * 4) / 255.0)
    }

    /// Rasterize into a common device-RGB 8-bit buffer so the comparison is
    /// independent of each image's tagged colour space.
    private static func raster8(_ image: CGImage, _ width: Int, _ height: Int) -> [UInt8] {
        // The buffer must stay owned for the whole context lifetime; see the
        // pixel-buffer rule in Sources/Aski/Masking/MaskSampler.swift.
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { rawBuffer in
            let ctx = CGContext(
                data: rawBuffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }
}
