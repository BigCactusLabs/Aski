import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes rendered frames as an animated GIF via `CGImageDestination`,
/// with per-frame delays + an explicit loop count, returning a pure-data report.
/// The library NEVER prints — callers decide what to surface from the report.
public struct ASCIIGIFEncoder: Sendable {
    public init() {}

    /// `loopCount` is REQUIRED (no default) so callers consciously choose
    /// preserve-source vs infinite (0) vs once (1).
    ///
    /// Input contract:
    /// - empty `frames` -> throws `.noFrames` (ImageIO can't finalize 0 images).
    /// - `loopCount` must be in `0...32767`: 0 = infinite, 1 = once, and
    ///   2...32767 = total plays. Other values throw `.invalidLoopCount`
    ///   before creating the destination; ImageIO does not round-trip them.
    /// - delay that is non-finite (NaN/inf) or <= 0 -> normalized to 0.1s; 0 is
    ///   never written (a written 0/neg/NaN round-trips as UnclampedDelayTime 0).
    /// - valid sub-floor delays (0 < d < 0.02s) are written RAW and counted into
    ///   `subFloorDelayCount`.
    @discardableResult
    public func write(_ frames: [RenderedGIFFrame], loopCount: Int, to url: URL) throws -> GIFEncodeReport {
        let session = try GIFEncodeSession(frameCount: frames.count, loopCount: loopCount, to: url)
        for frame in frames { try session.append(frame) }
        return try session.finish()
    }

    /// Non-finite or non-positive delays normalize to the documented 0.1s default;
    /// valid sub-floor delays (0 < d < 0.02s) pass through RAW (intent preserved).
    static func normalizedDelay(_ delay: TimeInterval) -> TimeInterval {
        guard delay.isFinite, delay > 0 else { return 0.1 }
        return delay
    }
}

/// Caller-confined incremental destination. ImageIO requires the exact image count
/// at creation. No rendered images are retained by this session; ImageIO's own
/// memory use must be measured separately. A failed or abandoned session removes
/// its staging directory and leaves the requested output unchanged.
package final class GIFEncodeSession {
    private let output: URL
    private let temporaryDirectory: URL
    private let temporary: URL
    private let expectedCount: Int
    private var destination: CGImageDestination?
    private var framesWritten = 0
    private var subFloorDelayCount = 0
    private var minDelay = Double.greatestFiniteMagnitude

    package init(frameCount: Int, loopCount: Int, to output: URL) throws {
        guard frameCount > 0 else { throw GIFEncodeError.noFrames }
        guard (0...32767).contains(loopCount) else { throw GIFEncodeError.invalidLoopCount(loopCount) }
        self.output = output
        self.expectedCount = frameCount
        self.temporaryDirectory = output.deletingLastPathComponent()
            .appendingPathComponent(".aski-gif-\(UUID().uuidString)", isDirectory: true)
        self.temporary = temporaryDirectory.appendingPathComponent("output.gif")
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        } catch {
            throw GIFEncodeError.cannotCreateDestination(output.path)
        }
        guard
            let destination = CGImageDestinationCreateWithURL(
                temporary as CFURL, UTType.gif.identifier as CFString, frameCount, nil
            )
        else {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw GIFEncodeError.cannotCreateDestination(output.path)
        }
        self.destination = destination
        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]
            ] as CFDictionary)
    }

    deinit {
        // ImageIO can leave its own staging sidecar after an unfinalized write,
        // even after destination release. Own the whole private directory so
        // failure cleanup removes that sidecar without guessing its filename.
        destination = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    package func append(_ frame: RenderedGIFFrame) throws {
        try Task.checkCancellation()
        guard let destination, framesWritten < expectedCount else {
            self.destination = nil
            throw GIFEncodeError.cannotFinalize(output.path)
        }
        let delay = ASCIIGIFEncoder.normalizedDelay(frame.delay)
        if delay < 0.02 { subFloorDelayCount += 1 }
        minDelay = min(minDelay, delay)
        CGImageDestinationAddImage(
            destination, frame.image,
            [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
            ] as CFDictionary)
        framesWritten += 1
    }

    package func finish() throws -> GIFEncodeReport {
        try Task.checkCancellation()
        guard let destination, framesWritten == expectedCount else {
            self.destination = nil
            throw GIFEncodeError.cannotFinalize(output.path)
        }
        self.destination = nil
        guard CGImageDestinationFinalize(destination) else {
            throw GIFEncodeError.cannotFinalize(output.path)
        }
        let header = try ASCIIGIFDecoder().containerHeader(ofGIFAt: temporary)
        guard header.frameCount == expectedCount else { throw GIFEncodeError.cannotFinalize(output.path) }
        try Task.checkCancellation()
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: output.path, isDirectory: &isDirectory) {
            guard !isDirectory.boolValue else { throw GIFEncodeError.cannotCreateDestination(output.path) }
            _ = try manager.replaceItemAt(output, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: output)
        }
        try? manager.removeItem(at: temporaryDirectory)
        return GIFEncodeReport(
            framesWritten: framesWritten, loopCount: header.loopCount,
            subFloorDelayCount: subFloorDelayCount, minDelay: minDelay
        )
    }
}
