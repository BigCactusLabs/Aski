import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import Aski

/// ASKI-100 characterization of MP4 export color handling (phase 1, no fix yet).
///
/// Observed on macOS 27 with the current encoder:
/// - The written track carries no ColorPrimaries, TransferFunction or
///   YCbCrMatrix format-description extensions (H.264 and HEVC).
/// - VideoToolbox encodes RGB→YCbCr with the BT.709 matrix, but a decoder
///   reading the untagged track guesses by frame size: AVAssetReader attaches
///   SMPTE-C primaries and the BT.601 matrix up to at least 384 px tall, and
///   BT.709 from at least 768 px. Small exports therefore decode with a hue
///   shift even from an sRGB grid: (204, 51, 26) comes back as (189, 37, 29).
/// - The DeviceRGB draw into the 32BGRA buffer behaves as sRGB on this host:
///   a Display P3 frame is converted to sRGB and gamut-clipped before encoding,
///   so the P3 primaries never reach the file.
///
/// Tests asserting the intended behavior are wrapped in `withKnownIssue`; once
/// the fix lands they record "known issue not recorded" and the wrapper must go.
/// `p3ExportCurrentlyDecodesAsClippedSRGB` and `deviceRGBDrawConvertsP3ToClippedSRGB`
/// pin current behavior and are expected to be rewritten by the fix.
@Suite(.serialized) struct AskiVideoColorTaggingTests {
    /// Non-neutral discriminator: its Display P3 encoding lies outside sRGB
    /// (blue converts to about -0.044 in extended sRGB).
    static let discriminator = SIMD3<Float>(0.8, 0.2, 0.1)
    static let neutralGray = SIMD3<Float>(0.5, 0.5, 0.5)

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3], [VideoCodec.h264, .hevc])
    func exportTagsTrackColorProperties(space: RenderColorSpace, codec: VideoCodec) async throws {
        let image = solidGridFrame(space: space, rgb: Self.discriminator, columns: 4, rows: 4)
        let url = try await exportSingleFrame(image, codec: codec, name: "tags-\(space)-\(codec).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let extensions = try await trackColorExtensions(url)

        withKnownIssue("ASKI-100: the encoder writes no color extensions") {
            #expect(extensions.primaries != nil)
            #expect(extensions.transferFunction != nil)
            #expect(extensions.matrix != nil)
        }
    }

    @Test(arguments: [VideoCodec.h264, .hevc])
    func smallSRGBExportDecodesToSourceColor(codec: VideoCodec) async throws {
        // 4 × 4 blank cells render to 39 × 77 px, small enough that an untagged
        // track is decoded with BT.601 while VideoToolbox encoded with BT.709.
        let image = solidGridFrame(space: .sRGB, rgb: Self.discriminator, columns: 4, rows: 4)
        let source = encodedBytes(Self.discriminator)
        #expect(centerRGB(of: image) == source)
        let url = try await exportSingleFrame(image, codec: codec, name: "small-srgb-\(codec).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try await decodedCenterRGB(url)

        withKnownIssue("ASKI-100: untagged small frames decode with the BT.601 matrix") {
            #expect(maxDelta(decoded, source.map(Double.init)) <= 4, "decoded \(decoded) vs source \(source)")
        }
    }

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func neutralGrayRoundTripsInEitherSpace(space: RenderColorSpace) async throws {
        // Control: gray is invariant under the matrix and primaries mix-ups.
        let image = solidGridFrame(space: space, rgb: Self.neutralGray, columns: 4, rows: 4)
        let url = try await exportSingleFrame(image, codec: .h264, name: "gray-\(space).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try await decodedCenterRGB(url)
        #expect(maxDelta(decoded, [128, 128, 128]) <= 2, "decoded \(decoded)")
    }

    @Test func p3ExportCurrentlyDecodesAsClippedSRGB() async throws {
        // Current behavior, not the target. 80 × 40 cells render to 768 × 768 px,
        // where the untagged track decodes with BT.709 (matching the encoder),
        // isolating the draw step: the P3 frame arrives as its sRGB conversion
        // with blue clipped at 0, not as its P3 encoding (204, 51, 26).
        let image = solidGridFrame(space: .displayP3, rgb: Self.discriminator, columns: 80, rows: 40)
        #expect(centerRGB(of: image) == encodedBytes(Self.discriminator))
        let url = try await exportSingleFrame(image, codec: .h264, name: "hd-p3.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try await decodedCenterRGB(url)

        let clippedSRGB = try #require(
            convertedComponents(Self.discriminator, from: .displayP3, to: CGColorSpace.sRGB)
        ).map { $0 * 255 }
        #expect(maxDelta(decoded, clippedSRGB) <= 4, "decoded \(decoded) vs clipped sRGB \(clippedSRGB)")
        #expect(abs(decoded[1] - 51) > 15, "green should not survive as the raw P3 value")
    }

    @Test func deviceRGBDrawConvertsP3ToClippedSRGB() throws {
        // What the encoder's DeviceRGB context does to each source space on this host.
        for space in [RenderColorSpace.sRGB, .displayP3] {
            let image = solidGridFrame(space: space, rgb: Self.discriminator, columns: 4, rows: 4)
            let drawn = deviceRGBDrawnRGB(image).map(Double.init)
            let clippedSRGB = try #require(
                convertedComponents(Self.discriminator, from: space, to: CGColorSpace.sRGB)
            ).map { $0 * 255 }
            #expect(maxDelta(drawn, clippedSRGB) <= 1, "\(space): drawn \(drawn) vs sRGB \(clippedSRGB)")
        }
    }
}

// MARK: - Helpers

private struct TrackColorExtensions {
    var primaries: String?
    var transferFunction: String?
    var matrix: String?
}

/// A tagged frame from the real renderer: blank cells over a background given
/// in the grid's own space, so the bitmap holds the encoded components exactly.
private func solidGridFrame(space: RenderColorSpace, rgb: SIMD3<Float>, columns: Int, rows: Int) -> CGImage {
    let blank = ASCIICell(character: " ", displayColor: .init(0, 0, 0), alpha: 0, brightness: 0)
    let grid = ASCIIGrid(
        cells: Array(repeating: Array(repeating: blank, count: columns), count: rows),
        colorSpace: space
    )
    return grid.renderImage(font: .system(size: 16), backgroundColor: space.encodedColor(rgb, alpha: 1), scale: 1)
}

private func encodedBytes(_ rgb: SIMD3<Float>) -> [UInt8] {
    [rgb.x, rgb.y, rgb.z].map { UInt8(($0 * 255).rounded()) }
}

private func convertedComponents(
    _ rgb: SIMD3<Float>, from space: RenderColorSpace, to name: CFString
) -> [Double]? {
    guard let target = CGColorSpace(name: name),
        let converted = space.encodedColor(rgb, alpha: 1)
            .converted(to: target, intent: .relativeColorimetric, options: nil),
        let components = converted.components
    else { return nil }
    return components.prefix(3).map(Double.init)
}

private func maxDelta(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).map { abs($0 - $1) }.max() ?? .infinity
}

/// The image's center pixel, read in the image's own color space (no conversion).
private func centerRGB(of image: CGImage) -> [UInt8] {
    renderCenterPixel(image, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bgra: false)
}

/// The image's center pixel after drawing into the same DeviceRGB 32BGRA
/// context configuration `ASCIIVideoEncoder` uses.
private func deviceRGBDrawnRGB(_ image: CGImage) -> [UInt8] {
    renderCenterPixel(image, space: CGColorSpaceCreateDeviceRGB(), bgra: true)
}

private func renderCenterPixel(_ image: CGImage, space: CGColorSpace, bgra: Bool) -> [UInt8] {
    var pixel = [UInt8](repeating: 0, count: 4)
    let info =
        bgra
        ? CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        : CGImageAlphaInfo.premultipliedLast.rawValue
    pixel.withUnsafeMutableBytes { raw in
        guard
            let context = CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: info
            )
        else { return }
        context.draw(
            image,
            in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height)
        )
    }
    return bgra ? [pixel[2], pixel[1], pixel[0]] : Array(pixel.prefix(3))
}

private func exportSingleFrame(_ image: CGImage, codec: VideoCodec, name: String) async throws -> URL {
    let url = tempVideoURL(name)
    try await ASCIIVideoEncoder().write(
        frameSequence([RenderedVideoFrame(image: image, time: .zero)]),
        to: url,
        options: VideoExportOptions(codec: codec)
    )
    return url
}

private func trackColorExtensions(_ url: URL) async throws -> TrackColorExtensions {
    let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
    let description = try #require(try await track.load(.formatDescriptions).first)
    func value(_ key: CFString) -> String? {
        CMFormatDescriptionGetExtension(description, extensionKey: key).map { "\($0)" }
    }
    return TrackColorExtensions(
        primaries: value(kCMFormatDescriptionExtension_ColorPrimaries),
        transferFunction: value(kCMFormatDescriptionExtension_TransferFunction),
        matrix: value(kCMFormatDescriptionExtension_YCbCrMatrix)
    )
}

/// Mean RGB over the central quarter of the first frame, decoded by AVAssetReader
/// to 32BGRA. No `AVVideoColorPropertiesKey` is requested, so the reader applies
/// only the YCbCr→RGB matrix it attaches to the buffer (from the track's tags, or
/// a size-based guess when untagged) and no primaries or transfer conversion:
/// the bytes are the encoded RGB values in whatever space the track declares.
private func decodedCenterRGB(_ url: URL) async throws -> [Double] {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    reader.add(output)
    #expect(reader.startReading())
    let sample = try #require(output.copyNextSampleBuffer())
    let buffer = try #require(CMSampleBufferGetImageBuffer(sample))
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    var sum = [0.0, 0.0, 0.0]
    var count = 0.0
    for y in (height / 4)..<(3 * height / 4) {
        for x in (width / 4)..<(3 * width / 4) {
            let pixel = base + y * bytesPerRow + x * 4
            sum[0] += Double(pixel[2])
            sum[1] += Double(pixel[1])
            sum[2] += Double(pixel[0])
            count += 1
        }
    }
    return sum.map { $0 / count }
}
