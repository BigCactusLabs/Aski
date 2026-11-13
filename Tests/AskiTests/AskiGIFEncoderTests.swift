import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Aski

@Suite struct AskiGIFEncoderTests {
    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, size: Int = 4, alpha: UInt8 = 255) -> CGImage {
        var buffer = [UInt8](repeating: 0, count: size * size * 4)
        for pixel in 0..<(size * size) {
            buffer[pixel * 4 + 0] = r
            buffer[pixel * 4 + 1] = g
            buffer[pixel * 4 + 2] = b
            buffer[pixel * 4 + 3] = alpha
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(buffer) as CFData)!
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private func tempGIF() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AskiGIFEncoderTests-\(UUID().uuidString).gif")
    }

    private func unclampedDelays(_ url: URL) throws -> [Double] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try (0..<CGImageSourceGetCount(source)).map { index in
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
            let gif = try #require(props[kCGImagePropertyGIFDictionary] as? [CFString: Any])
            return (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? -1
        }
    }

    @Test func emptyFramesThrowsNoFrames() {
        let url = tempGIF()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: GIFEncodeError.self) {
            try ASCIIGIFEncoder().write([], loopCount: 0, to: url)
        }
    }

    @Test(arguments: [0, 1, 2, 4, 32766, 32767], [1, 2])
    func supportedLoopCountsMatchFinalizedMetadata(loopCount: Int, frameCount: Int) throws {
        let url = tempGIF()
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = (0..<frameCount).map { index in
            RenderedGIFFrame(image: solid(UInt8(index * 255), 20, 30), delay: 0.1)
        }

        let report = try ASCIIGIFEncoder().write(frames, loopCount: loopCount, to: url)
        let header = try ASCIIGIFDecoder().containerHeader(ofGIFAt: url)
        #expect(header.frameCount == frameCount)
        #expect(header.loopCount == loopCount)
        #expect(report.loopCount == header.loopCount)
    }

    @Test(arguments: [Int.min, -1, 32768, 65534, 65535, 65536, Int.max], [false, true])
    func invalidLoopCountsLeaveDestinationUnchanged(loopCount: Int, existing: Bool) throws {
        let url = tempGIF()
        defer { try? FileManager.default.removeItem(at: url) }
        let sentinel = Data("existing destination".utf8)
        if existing { try sentinel.write(to: url) }
        let frames = [RenderedGIFFrame(image: solid(10, 20, 30), delay: 0.1)]

        #expect {
            try ASCIIGIFEncoder().write(frames, loopCount: loopCount, to: url)
        } throws: { error in
            guard case GIFEncodeError.invalidLoopCount(let rejected) = error else { return false }
            return rejected == loopCount
        }
        if existing {
            #expect(try Data(contentsOf: url) == sentinel)
        } else {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func nonFiniteAndNonPositiveDelaysNormalizeToDefault() throws {
        let url = tempGIF()
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = [Double.nan, -1, 0].map { RenderedGIFFrame(image: solid(10, 20, 30), delay: $0) }

        let report = try ASCIIGIFEncoder().write(frames, loopCount: 0, to: url)
        #expect(report.framesWritten == 3)
        #expect(report.subFloorDelayCount == 0)  // normalized 0.1s is not sub-floor
        #expect(abs(report.minDelay - 0.1) < 1e-6)

        let delays = try unclampedDelays(url)
        #expect(delays.allSatisfy { abs($0 - 0.1) < 0.005 })  // no written 0/neg/NaN
    }

    @Test func validSubFloorDelayIsWrittenRawAndCounted() throws {
        let url = tempGIF()
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = [
            RenderedGIFFrame(image: solid(255, 0, 0), delay: 0.01),  // valid but below 0.02 floor
            RenderedGIFFrame(image: solid(0, 255, 0), delay: 0.2),
        ]
        let report = try ASCIIGIFEncoder().write(frames, loopCount: 0, to: url)
        #expect(report.subFloorDelayCount == 1)
        #expect(abs(report.minDelay - 0.01) < 1e-6)

        let delays = try unclampedDelays(url)
        #expect(abs(delays[0] - 0.01) < 0.005)  // written RAW, not normalized
    }
    /// Independent retained control preserves the pre-streaming ImageIO calls.
    @Test(arguments: [0, 1, 4])
    func incrementalMatchesRetainedControl(loopCount: Int) throws {
        let control = tempGIF()
        let output = tempGIF()
        defer {
            try? FileManager.default.removeItem(at: control)
            try? FileManager.default.removeItem(at: output)
        }
        let frames = [
            RenderedGIFFrame(image: solid(255, 0, 0), delay: 0.01),
            RenderedGIFFrame(image: solid(0, 255, 0), delay: 0.2),
            RenderedGIFFrame(image: solid(0, 0, 255), delay: 0),
            RenderedGIFFrame(image: solid(0, 0, 0, alpha: 0), delay: 0.1),
        ]
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                control as CFURL, UTType.gif.identifier as CFString, frames.count, nil
            ))
        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]
            ] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(
                destination, frame.image,
                [
                    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: ASCIIGIFEncoder.normalizedDelay(frame.delay)]
                ] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        let session = try GIFEncodeSession(frameCount: frames.count, loopCount: loopCount, to: output)
        for frame in frames { try session.append(frame) }
        let report = try session.finish()
        // Byte equality covers frame order, palette, canvas and timing metadata.
        #expect(try Data(contentsOf: output) == Data(contentsOf: control))
        #expect(report.framesWritten == frames.count)
        #expect(report.loopCount == loopCount)
    }

    @Test(arguments: [false, true])
    func incompleteOrExcessFramesPreserveExistingOutput(excess: Bool) throws {
        let output = tempGIF()
        defer { try? FileManager.default.removeItem(at: output) }
        let sentinel = Data("existing output".utf8)
        try sentinel.write(to: output)
        let session = try GIFEncodeSession(frameCount: 2, loopCount: 0, to: output)
        let frame = RenderedGIFFrame(image: solid(1, 2, 3), delay: 0.1)
        try session.append(frame)
        if excess {
            try session.append(frame)
            #expect(throws: GIFEncodeError.self) { try session.append(frame) }
        }
        #expect(throws: GIFEncodeError.self) { try session.finish() }
        #expect(try Data(contentsOf: output) == sentinel)
    }

    @Test func abandonedProducerOrRendererFailureRemovesTemporaryOutput() throws {
        enum Failure: Error { case frame }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("output.gif")
        let sentinel = Data("existing output".utf8)
        try sentinel.write(to: output)
        #expect(throws: Failure.self) {
            let session = try GIFEncodeSession(frameCount: 3, loopCount: 0, to: output)
            try session.append(RenderedGIFFrame(image: solid(1, 2, 3), delay: 0.1))
            throw Failure.frame
        }
        #expect(try Data(contentsOf: output) == sentinel)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(remaining == ["output.gif"])
    }

    @Test func successfulReplacementPublishesCompleteGIFAndRemovesSiblingTemporary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("output.gif")
        let sentinel = Data("previous output".utf8)
        try sentinel.write(to: output)
        let session = try GIFEncodeSession(frameCount: 2, loopCount: 4, to: output)
        try session.append(RenderedGIFFrame(image: solid(255, 0, 0), delay: 0.04))
        #expect(try Data(contentsOf: output) == sentinel)
        try session.append(RenderedGIFFrame(image: solid(0, 255, 0), delay: 0.2))
        let report = try session.finish()
        let info = try ASCIIGIFDecoder().containerInfo(ofGIFAt: output)
        #expect(report.framesWritten == 2)
        #expect(info.frameCount == 2 && info.loopCount == 4)
        #expect(info.canvasSize == CGSize(width: 4, height: 4))
        #expect(info.frameDelays == [0.04, 0.2])
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let second = try #require(CGImageSourceCreateImageAtIndex(source, 1, nil))
        expectColor(first, x: 0, y: 0, 255, 0, 0)
        expectColor(second, x: 0, y: 0, 0, 255, 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["output.gif"])
    }

    /// Real decoder producer rejection, not a synthetic throw in
    /// the consumer. This does not claim a partially decoded LZW failure.
    @Test func malformedSourceProducerFailurePreservesExistingOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.gif")
        try Data([0xFF, 0x00, 0xFF]).write(to: source)
        let output = directory.appendingPathComponent("output.gif")
        let sentinel = Data("previous output".utf8)
        try sentinel.write(to: output)
        do {
            let session = try GIFEncodeSession(frameCount: 1, loopCount: 0, to: output)
            let stream = ASCIIGIFDecoder().grids(fromGIFAt: source) { _ in
                Issue.record("Malformed input unexpectedly reached transform")
                return ASCIIGrid(cells: [], colorSpace: .sRGB)
            }
            for try await _ in stream {
                Issue.record("Malformed input unexpectedly produced a frame")
            }
            _ = try session.finish()
            Issue.record("Malformed source unexpectedly succeeded")
        } catch GIFDecodeError.cannotOpenSource, GIFDecodeError.noFrames {
            #expect(try Data(contentsOf: output) == sentinel)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["output.gif", "source.gif"])
    }

    @Test func destinationDirectoryIsNotReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let child = directory.appendingPathComponent("sentinel")
        let sentinel = Data("keep directory".utf8)
        try sentinel.write(to: child)
        let session = try GIFEncodeSession(frameCount: 1, loopCount: 0, to: directory)
        try session.append(RenderedGIFFrame(image: solid(1, 2, 3), delay: 0.1))
        #expect(throws: GIFEncodeError.self) { try session.finish() }
        #expect(try Data(contentsOf: child) == sentinel)
    }

    @Test func missingParentFailsBeforeProduction() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = parent.appendingPathComponent("output.gif")
        #expect(throws: GIFEncodeError.self) {
            _ = try GIFEncodeSession(frameCount: 1, loopCount: 0, to: output)
        }
        #expect(!FileManager.default.fileExists(atPath: parent.path))
    }

    @Test func cancelledSessionDoesNotPublish() async throws {
        let output = tempGIF()
        defer { try? FileManager.default.removeItem(at: output) }
        let sentinel = Data("existing output".utf8)
        try sentinel.write(to: output)
        let frame = RenderedGIFFrame(image: solid(1, 2, 3), delay: 0.1)
        let task = Task {
            let session = try GIFEncodeSession(frameCount: 1, loopCount: 0, to: output)
            try session.append(frame)
            withUnsafeCurrentTask { $0?.cancel() }
            return try session.finish()
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled GIF encode succeeded")
        } catch is CancellationError {
            #expect(try Data(contentsOf: output) == sentinel)
        }
    }

}
