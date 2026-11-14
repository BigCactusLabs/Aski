import Aski
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let candidate = "0e897a39f1ee44b6d4b7235e694492006e7372f3"
private let sourceFixture = "aski4-changing-gradient-r1-640x360-25fps-loop0"
private let layoutFixture = "aski4-benchmark-deviceRGB-gradient-640x360-80cols-system10-scale1"

@main
struct GIFMemoryHarness {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let mode = args.first else { throw HarnessError.usage }
        switch mode {
        case "layout":
            guard args.count == 1 else { throw HarnessError.usage }
            try emit(layout())
        case "source":
            guard args.count == 3, let count = Int(args[1]), [240, 1200].contains(count) else {
                throw HarnessError.usage
            }
            let output = URL(fileURLWithPath: args[2])
            try generateSource(count: count, output: output)
            var result = try metadata(output)
            result["mode"] = "source"
            result["fixture_id"] = sourceFixture
            result["requested_frame_count"] = count
            try emit(result)
        case "convert":
            guard args.count == 4, ["native", "12"].contains(args[3]) else { throw HarnessError.usage }
            let input = URL(fileURLWithPath: args[1])
            let output = URL(fileURLWithPath: args[2])
            let fps = args[3] == "12" ? 12 : nil
            let source = try ASCIIGIFDecoder().containerInfo(ofGIFAt: input)
            try validateSource(source)
            let staging = try createStagingDirectory(for: output)
            defer { try? FileManager.default.removeItem(at: staging) }
            let temporary = staging.appendingPathComponent("converted.gif")
            let report = try await convertGIF(
                at: input, to: temporary, using: DefaultConverter(), columns: 80,
                font: .system(size: 10), backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                scale: 1, targetFPS: fps
            )
            let finalized = try ASCIIGIFDecoder().containerInfo(ofGIFAt: temporary)
            guard finalized.frameCount == report.framesWritten, finalized.loopCount == 0 else {
                throw HarnessError.validation("Finalized header disagrees with conversion report")
            }
            if let resample = report.resample {
                guard resample.outputFrameCount == report.framesWritten else {
                    throw HarnessError.validation("Resample count disagrees with encoded count")
                }
            } else if report.framesWritten != source.frameCount {
                throw HarnessError.validation("Unresampled conversion changed frame count")
            }
            // moveItem refuses an existing final output; generation/convert never
            // replace a caller's file, including one created after our preflight.
            try FileManager.default.moveItem(at: temporary, to: output)
            var result = try metadata(output)
            result["mode"] = "convert"
            result["fixture_id"] = sourceFixture
            result["render_fixture_id"] = layoutFixture
            result["target_fps"] = fps.map { $0 as Any } ?? NSNull()
            result["source_frame_count"] = source.frameCount
            result["source_duration_seconds"] = source.totalDuration
            result["encode_report"] = encodeReport(report)
            try emit(result)
        case "inspect":
            guard args.count == 2 else { throw HarnessError.usage }
            var result = try metadata(URL(fileURLWithPath: args[1]))
            result["mode"] = "inspect"
            try emit(result)
        default:
            throw HarnessError.usage
        }
    }
}

private enum HarnessError: Error, CustomStringConvertible {
    case usage
    case validation(String)

    var description: String {
        switch self {
        case .usage:
            "usage: gif-memory-harness layout | source <240|1200> <new.gif> | convert <source.gif> <new.gif> <native|12> | inspect <existing.gif>"
        case .validation(let message): message
        }
    }
}

private func emit(_ object: [String: Any]) throws {
    var object = object
    object["schema_version"] = 1
    object["expected_candidate_revision"] = candidate
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

private func createStagingDirectory(for output: URL) throws -> URL {
    guard !FileManager.default.fileExists(atPath: output.path) else {
        throw HarnessError.validation("Output must not already exist")
    }
    let staging = output.deletingLastPathComponent().appendingPathComponent(".gif-harness-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
    return staging
}

private func metadata(_ url: URL) throws -> [String: Any] {
    let info = try ASCIIGIFDecoder().containerInfo(ofGIFAt: url)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let fileBytes = attributes[.size] as? NSNumber else {
        throw HarnessError.validation("Missing output file size")
    }
    return [
        "frame_count": info.frameCount,
        "loop_count": info.loopCount,
        "canvas_width": info.canvasSize.width,
        "canvas_height": info.canvasSize.height,
        "frame_delays_seconds": info.frameDelays,
        "total_duration_seconds": info.totalDuration,
        "file_bytes": fileBytes,
    ]
}

private func encodeReport(_ report: GIFEncodeReport) -> [String: Any] {
    var result: [String: Any] = [
        "frames_written": report.framesWritten, "loop_count": report.loopCount,
        "sub_floor_delay_count": report.subFloorDelayCount, "min_delay_seconds": report.minDelay,
    ]
    if let value = report.resample {
        result["resample"] = [
            "requested_fps": value.requestedFPS, "achieved_fps": value.achievedFPS,
            "source_frame_count": value.sourceFrameCount, "output_frame_count": value.outputFrameCount,
            "dropped_count": value.droppedCount, "duplicated_count": value.duplicatedCount,
        ]
    } else {
        result["resample"] = NSNull()
    }
    return result
}

private func validateSource(_ info: GIFContainerInfo) throws {
    guard [240, 1200].contains(info.frameCount), info.loopCount == 0,
        info.canvasSize == CGSize(width: 640, height: 360),
        info.frameDelays.count == info.frameCount,
        info.frameDelays.allSatisfy({ abs($0 - 0.04) < 1e-9 })
    else { throw HarnessError.validation("Input does not match the supplemental source metadata contract") }
}

private func layout() -> [String: Any] {
    let grid = DefaultConverter().convert(makeGradient(width: 640, height: 360), columns: 80)
    let image = grid.renderImage(font: .system(size: 10), backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), scale: 1)
    return [
        "mode": "layout", "fixture_id": layoutFixture,
        "width": image.width, "height": image.height, "bytes_per_row": image.bytesPerRow,
        "total_bytes": image.bytesPerRow * image.height,
        "bits_per_pixel": image.bitsPerPixel, "bits_per_component": image.bitsPerComponent,
    ]
}

// Exact owning fixture body copied from Benchmarks/AskiBenchmarks/Benchmarks.swift
// at the frozen candidate. Its source SHA256 is recorded in protocol.json.
private func makeGradient(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!

    for x in 0..<width {
        let t = CGFloat(x) / CGFloat(width - 1)
        context.setFillColor(red: t, green: t, blue: t, alpha: 1)
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }

    return context.makeImage()!
}

private func changingFrame(_ index: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 640 * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    for x in 0..<640 {
        let value = CGFloat((x + index) % 640) / 639
        context.setFillColor(red: value, green: 1 - value, blue: 0.25, alpha: 1)
        context.fill(CGRect(x: x, y: 0, width: 1, height: 360))
    }
    // Binary index strip makes all 1200 frames distinct, not a 640-frame loop.
    for bit in 0..<11 {
        let value: CGFloat = (index & (1 << bit)) == 0 ? 0 : 1
        context.setFillColor(red: value, green: value, blue: value, alpha: 1)
        context.fill(CGRect(x: bit * 16, y: 0, width: 16, height: 16))
    }
    return context.makeImage()!
}

private func generateSource(count: Int, output: URL) throws {
    let staging = try createStagingDirectory(for: output)
    defer { try? FileManager.default.removeItem(at: staging) }
    let temporary = staging.appendingPathComponent("source.gif")
    guard
        let destination = CGImageDestinationCreateWithURL(
            temporary as CFURL, UTType.gif.identifier as CFString, count, nil
        )
    else { throw HarnessError.validation("Cannot create source fixture destination") }
    CGImageDestinationSetProperties(
        destination,
        [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
    for index in 0..<count {
        autoreleasepool {
            CGImageDestinationAddImage(
                destination, changingFrame(index),
                [
                    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.04]
                ] as CFDictionary)
        }
    }
    guard CGImageDestinationFinalize(destination) else { throw HarnessError.validation("Source fixture finalization failed") }
    let info = try ASCIIGIFDecoder().containerInfo(ofGIFAt: temporary)
    try validateSource(info)
    guard info.frameCount == count else { throw HarnessError.validation("Generated source frame count mismatch") }
    try FileManager.default.moveItem(at: temporary, to: output)
}
