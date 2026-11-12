@_spi(AskiResearch) import Aski
import Benchmark
import CoreGraphics
import CoreVideo
import Foundation
import VideoToolbox

/// ASKI-1 preparation instruments — measurement only, no thresholds (budgets are
/// ASKI-5's). Each input is measured twice: `prepare-*` runs only the converter's
/// preparation (grid resolution, target-size preparation, sampling lattice) through
/// the `samplingGeometry` research reflection, and `convert-*` runs the full
/// conversion, so a preparation-path change can be read alongside its end-to-end
/// effect in one run.
///
/// The still is a 12 MP RGBX image, the layout ImageIO decodes a JPEG photo into,
/// at the frozen preset's 76 columns. The frame is a 1080p 32BGRA `CVPixelBuffer`
/// wrapped by `VTCreateCGImageFromCVPixelBuffer` inside the measured loop, the
/// same per-frame `CGImage` the video decoder hands the converter.
func addPreparationBenchmarks() {
    let photoColumns = 76
    let frameColumns = 80

    Benchmark("prepare-photo-4032x3024-76cols", configuration: preparationConfiguration()) { benchmark in
        let image = makePhotoLikeImage(width: 4_032, height: 3_024)
        let converter = DefaultConverter()
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(converter.samplingGeometry(image, columns: photoColumns))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("convert-photo-4032x3024-76cols", configuration: preparationConfiguration()) { benchmark in
        let image = makePhotoLikeImage(width: 4_032, height: 3_024)
        let converter = DefaultConverter()
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(converter.convert(image, columns: photoColumns))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("prepare-frame-1920x1080-80cols", configuration: preparationConfiguration()) { benchmark in
        guard let buffer = makeFramePixelBuffer(width: 1_920, height: 1_080) else {
            benchmark.error("could not create the 32BGRA frame buffer")
            return
        }
        let converter = DefaultConverter()
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            guard let frame = frameImage(buffer) else {
                benchmark.error("VTCreateCGImageFromCVPixelBuffer failed")
                return
            }
            blackHole(converter.samplingGeometry(frame, columns: frameColumns))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("convert-frame-1920x1080-80cols", configuration: preparationConfiguration()) { benchmark in
        guard let buffer = makeFramePixelBuffer(width: 1_920, height: 1_080) else {
            benchmark.error("could not create the 32BGRA frame buffer")
            return
        }
        let converter = DefaultConverter()
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            guard let frame = frameImage(buffer) else {
                benchmark.error("VTCreateCGImageFromCVPixelBuffer failed")
                return
            }
            blackHole(converter.convert(frame, columns: frameColumns))
        }
        benchmark.stopMeasurement()
    }
}

private func preparationConfiguration() -> Benchmark.Configuration {
    .init(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResidentDelta],
        warmupIterations: 2,
        scalingFactor: .one,
        maxDuration: .seconds(3),
        maxIterations: 20
    )
}

/// Deterministic photo-like content: smooth color fields plus per-pixel noise, so
/// neither PNG compression nor a resampler sees a degenerate flat or periodic
/// input. Stored RGBX (`noneSkipLast`), the layout ImageIO decodes JPEGs into.
private func makePhotoLikeImage(width: Int, height: Int) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    for y in 0..<height {
        let fy = Float(y) / Float(height)
        for x in 0..<width {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Float((seed >> 33) & 0xFF) / 255 - 0.5
            let fx = Float(x) / Float(width)
            let red = 0.5 + 0.3 * sin(fx * 9) + 0.15 * noise
            let green = 0.5 + 0.3 * cos(fy * 7 + fx * 3) + 0.15 * noise
            let blue = 0.5 + 0.4 * sin((fx + fy) * 20) + 0.15 * noise
            let offset = (y * width + x) * 4
            bytes[offset] = UInt8(max(0, min(255, red * 255)))
            bytes[offset + 1] = UInt8(max(0, min(255, green * 255)))
            bytes[offset + 2] = UInt8(max(0, min(255, blue * 255)))
        }
    }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )!
}

/// A 32BGRA pixel buffer filled with a moving-gradient pattern, the format the
/// video decoder requests from `AVAssetReaderTrackOutput`.
private func makeFramePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
    guard
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &buffer
        ) == kCVReturnSuccess,
        let buffer
    else {
        return nil
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let pixels = base.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * rowBytes + x * 4
            pixels[offset] = UInt8((x * 255) / max(1, width - 1))  // blue
            pixels[offset + 1] = UInt8((y * 255) / max(1, height - 1))  // green
            pixels[offset + 2] = UInt8(((x ^ y) & 0x3F) * 4)  // red
            pixels[offset + 3] = 255
        }
    }
    return buffer
}

private func frameImage(_ buffer: CVPixelBuffer) -> CGImage? {
    var image: CGImage?
    guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image) == noErr else {
        return nil
    }
    return image
}
