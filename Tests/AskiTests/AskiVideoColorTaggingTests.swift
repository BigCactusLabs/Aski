import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import Aski

/// MP4 export color contract (ASKI-100). Frames are drawn in the grid's encoded
/// gamut and tagged with a per-gamut triple: primaries BT.709 (sRGB) or P3 D65,
/// the IEC sRGB transfer function, and the BT.709 Y'CbCr matrix.
///
/// Before the fix the track was untagged: decoders guessed the Y'CbCr matrix by
/// frame size (AVAssetReader used BT.601 up to at least 384 px tall, so a small
/// sRGB export decoded (204, 51, 26) as (189, 37, 29)), and the DeviceRGB draw
/// converted P3 frames to clipped sRGB, (204, 51, 26) P3 → (222, 24, 0).
@Suite(.serialized) struct AskiVideoColorTaggingTests {
    /// Non-neutral discriminator: its Display P3 encoding lies outside sRGB
    /// (blue converts to about -0.044 in extended sRGB, green to about 0.094).
    static let discriminator = SIMD3<Float>(0.8, 0.2, 0.1)
    static let neutralGray = SIMD3<Float>(0.5, 0.5, 0.5)

    /// Per-channel decode tolerance in 8-bit code values. A flat field at video
    /// range quantizes Y' in steps of 1/219 and Cb/Cr in steps of 1/224; the
    /// BT.709 inverse scales one chroma step by up to 1.8556 × 255/224 ≈ 2.1 code
    /// values, so a round trip with no color error stays within 3. The untagged
    /// failures this guards against miss by 15 (matrix) and 27 (gamut).
    static let tolerance = 3.0

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3], [VideoCodec.h264, .hevc])
    func exportTagsTrackColorProperties(space: RenderColorSpace, codec: VideoCodec) async throws {
        let image = solidGridFrame(space: space, rgb: Self.discriminator, columns: 4, rows: 4)
        let url = try await exportSingleFrame(image, codec: codec, name: "tags-\(space)-\(codec).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let extensions = try await trackColorExtensions(url)

        let expectedPrimaries =
            space == .displayP3 ? kCVImageBufferColorPrimaries_P3_D65 : kCVImageBufferColorPrimaries_ITU_R_709_2
        #expect(extensions.primaries == expectedPrimaries as String)
        #expect(extensions.transferFunction == kCVImageBufferTransferFunction_sRGB as String)
        #expect(extensions.matrix == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String)
    }

    @Test(arguments: [(4, 4), (80, 40)], [VideoCodec.h264, .hevc])
    func sRGBExportDecodesToSourceColor(dims: (Int, Int), codec: VideoCodec) async throws {
        // 4 × 4 cells render to 39 × 77 px, 80 × 40 to 768 × 768 px: either side
        // of the size at which decoders switch their untagged-matrix guess.
        let image = solidGridFrame(space: .sRGB, rgb: Self.discriminator, columns: dims.0, rows: dims.1)
        let source = encodedBytes(Self.discriminator)
        #expect(centerRGB(of: image) == source)
        let url = try await exportSingleFrame(image, codec: codec, name: "srgb-\(dims.0)-\(codec).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try await decodedCenterRGB(url, readingIn: .sRGB)

        #expect(
            maxDelta(decoded, source.map(Double.init)) <= Self.tolerance,
            "\(image.width)x\(image.height): decoded \(decoded) vs source \(source)"
        )
    }

    @Test(arguments: [VideoCodec.h264, .hevc])
    func displayP3ExportPreservesP3(codec: VideoCodec) async throws {
        let image = solidGridFrame(space: .displayP3, rgb: Self.discriminator, columns: 4, rows: 4)
        let source = encodedBytes(Self.discriminator)
        #expect(centerRGB(of: image) == source)
        let url = try await exportSingleFrame(image, codec: codec, name: "p3-\(codec).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try await decodedCenterRGB(url, readingIn: .displayP3)

        #expect(
            maxDelta(decoded, source.map(Double.init)) <= Self.tolerance,
            "decoded \(decoded) vs P3 source \(source)"
        )
        // The pre-fix result was the clipped sRGB conversion, (222, 24, 0).
        #expect(abs(decoded[1] - 24) > 15, "green collapsed to the clipped sRGB value")
    }

    @Test func linearCompositionExportsInEncodedP3() async throws {
        // `extendedLinearPerGamut` renders into linear Display P3; the encoder
        // must draw and tag the encoded P3 gamut, not the linear space.
        let image = solidGridFrame(
            space: .displayP3, rgb: Self.discriminator, columns: 4, rows: 4, composition: .extendedLinearPerGamut
        )
        #expect(image.colorSpace?.name == CGColorSpace.linearDisplayP3)
        let expected = renderCenterPixel(image, space: CGColorSpace(name: CGColorSpace.displayP3)!).map(Double.init)
        let url = try await exportSingleFrame(image, codec: .h264, name: "linear-p3.mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let extensions = try await trackColorExtensions(url)
        #expect(extensions.primaries == kCVImageBufferColorPrimaries_P3_D65 as String)
        #expect(extensions.transferFunction == kCVImageBufferTransferFunction_sRGB as String)
        let decoded = try await decodedCenterRGB(url, readingIn: .displayP3)
        #expect(maxDelta(decoded, expected) <= Self.tolerance, "decoded \(decoded) vs encoded P3 \(expected)")
    }

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3], [VideoCodec.h264, .hevc])
    func neutralGrayRoundTripsExactly(space: RenderColorSpace, codec: VideoCodec) async throws {
        let image = solidGridFrame(space: space, rgb: Self.neutralGray, columns: 4, rows: 4)
        let url = try await exportSingleFrame(image, codec: codec, name: "gray-\(space)-\(codec).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try await decodedCenterRGB(url, readingIn: space)
        #expect(decoded == [128, 128, 128], "decoded \(decoded)")
    }

    @Test func outputGamutMapsColorSpacesByName() {
        func gamut(_ name: CFString) -> VideoOutputGamut {
            VideoOutputGamut(imageColorSpace: CGColorSpace(name: name))
        }
        #expect(gamut(CGColorSpace.displayP3) == .displayP3)
        #expect(gamut(CGColorSpace.linearDisplayP3) == .displayP3)
        #expect(gamut(CGColorSpace.extendedLinearDisplayP3) == .displayP3)
        #expect(gamut(CGColorSpace.sRGB) == .sRGB)
        #expect(gamut(CGColorSpace.linearSRGB) == .sRGB)
        #expect(gamut(CGColorSpace.adobeRGB1998) == .sRGB)
        #expect(VideoOutputGamut(imageColorSpace: CGColorSpaceCreateDeviceRGB()) == .sRGB)
        #expect(VideoOutputGamut(imageColorSpace: nil) == .sRGB)
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
private func solidGridFrame(
    space: RenderColorSpace,
    rgb: SIMD3<Float>,
    columns: Int,
    rows: Int,
    composition: RenderCompositionPolicy = .encodedDisplay8Bit
) -> CGImage {
    let blank = ASCIICell(character: " ", displayColor: .init(0, 0, 0), alpha: 0, brightness: 0)
    let grid = ASCIIGrid(
        cells: Array(repeating: Array(repeating: blank, count: columns), count: rows),
        colorSpace: space,
        composition: composition
    )
    return grid.renderImage(font: .system(size: 16), backgroundColor: space.encodedColor(rgb, alpha: 1), scale: 1)
}

private func encodedBytes(_ rgb: SIMD3<Float>) -> [UInt8] {
    [rgb.x, rgb.y, rgb.z].map { UInt8(($0 * 255).rounded()) }
}

private func maxDelta(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).map { abs($0 - $1) }.max() ?? .infinity
}

/// The image's center pixel, read in the image's own color space (no conversion).
private func centerRGB(of image: CGImage) -> [UInt8] {
    renderCenterPixel(image, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB())
}

private func renderCenterPixel(_ image: CGImage, space: CGColorSpace) -> [UInt8] {
    var pixel = [UInt8](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { raw in
        guard
            let context = CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return }
        context.draw(
            image,
            in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height)
        )
    }
    return Array(pixel.prefix(3))
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
/// to 32BGRA with explicit output color properties for `space` (the same triple
/// the encoder writes for that gamut). When those equal the track's tags the
/// reader applies only the BT.709 Y'CbCr→RGB matrix, so the bytes are the
/// encoded RGB values in `space`; a mis-tagged track would be converted and show
/// up as a color error.
private func decodedCenterRGB(_ url: URL, readingIn space: RenderColorSpace) async throws -> [Double] {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let primaries = space == .displayP3 ? AVVideoColorPrimaries_P3_D65 : AVVideoColorPrimaries_ITU_R_709_2
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: primaries,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
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
