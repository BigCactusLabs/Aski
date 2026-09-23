import Aski
import AskiToolSupport
import CoreGraphics
import Foundation

public enum VideoLabCLI {
    public static let usage = """
        AskiVideoLab — stream an MP4 or animated GIF through the ASCII pipeline and re-encode the same format.

        Usage:
          swift run AskiVideoLab --input <video|gif> --output-dir <dir> [options]

        Required:
          --input <video|gif>     Source MP4/MOV or animated GIF to convert.
          --output-dir <dir>      Directory to write ascii.mp4 / ascii.gif, metrics.csv, result.yaml.

        Options:
          --columns <int>         ASCII columns. Default: 80.
          --codec <h264|hevc>     Output codec (MP4 path only; ignored for GIF). Default: h264.
          --font-scale <float>    Render scale multiplier. Default: 1.0.
          --max-frames <int>      Cap decoded frames. For GIF this is an explicit
                                  prefix cap; absent GIF inputs over 10,000 frames
                                  are rejected before delay scanning, decoding,
                                  or rendering.
          --target-fps <int>      Resample timing to N fps via drop/duplicate. MP4 is
                                  exact; GIF quantizes to centiseconds (achieved rate
                                  reported). Absent = preserve source timing.
          --charset <name>        Character set: standard | minimal | blocks | dots |
                                  lines | diagonal | cross | diamond | mixed | braille.
                                  Default: standard.
          --oversample <int>      Per-cell pixel-budget multiplier (1...8). 4+ enables
                                  the edge-emphasis Sobel path. Default: 2.
          --brightness <float>    OKLAB L additive offset (-1...1, clamps). Default: 0.
          --contrast <float>      OKLAB L scale-around-0.5 (-1...1, clamps). Default: 0.
          --density <float>       logPolar brightness-prefilter slack (0...1, clamps).
                                  Default: 0.
          --edge-emphasis <float> logPolar edge-emphasis weight (0...1, clamps; needs
                                  oversample 4+). Default: 0.
          --pattern <name>        Time-modulated overlay: none | wave | pulse.
                                  Phase advances with each frame's presentation
                                  time. Default: none (byte-identical to today).
          --pattern-amplitude <f> Wave alpha amplitude (0...0.5, clamps). Default: 0.5.
          --pattern-frequency <f> Wave cycles per second (finite, > 0). Default: 1.
          --pattern-period <f>    Pulse period in seconds (finite, > 0). Default: 1.
          --pattern-depth <f>     Pulse modulation depth (0...1, clamps). Default: 1.
          --bloom <float>         Cosmetic glow intensity (0...1, clamps; 0 = off).
                                  Post-render, time-invariant. Default: 0.
          --bloom-radius <f>      Bloom blur radius in px (finite, > 0). Default: 6.
          --scanlines <float>     Cosmetic scanline intensity (0...1, clamps; 0 = off).
                                  Post-render, time-invariant. Default: 0.
          --scanline-frequency <f> Scanline spacing divisor in px (finite, > 0; larger =
                                  wider, more visible lines). Default: 8.
          --vignette <float>      Cosmetic edge-darkening intensity (0...1, clamps; 0 =
                                  off). Post-render, time-invariant. Default: 0.
          --aski-git-sha <sha>    Override the git SHA recorded in result.yaml.
          --help, -h              Print this usage.
        """

    public static func run(
        arguments: VideoLabArguments,
        codecWasProvided: Bool = false,
        standardOutput: @Sendable (String) -> Void = { print($0, terminator: "") },
        standardError: @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = VideoLabCLI.todayUTC()
    ) async -> LabExitCode {
        let inputURL = URL(fileURLWithPath: arguments.inputPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            standardError("error: input not found '\(arguments.inputPath)'\n")
            return .ioError
        }
        let isGIF = inputURL.pathExtension.lowercased() == "gif"
        let gitSHA = GitSHA.resolve(override: arguments.gitShaOverride)
        do {
            try VideoLabResults.validateManifestMetadata(
                inputDescriptor: inputURL.lastPathComponent,
                gitSHA: gitSHA,
                command: commandLine(arguments, isGIF: isGIF)
            )
        } catch {
            standardError("error: \(error)\n\n\(usage)\n")
            return .usage
        }
        let outputURL = URL(fileURLWithPath: arguments.outputDirectory)
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }
        let asciiURL = outputURL.appendingPathComponent(isGIF ? "ascii.gif" : "ascii.mp4")
        if isGIF, codecWasProvided {
            standardOutput("note: --codec is ignored for GIF input\n")
        }

        let converter = makeConverter(from: arguments)
        let font = ASCIIFont.system(size: 10)
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let options = VideoExportOptions(codec: arguments.codec)
        let scale = CGFloat(arguments.fontScale)

        // Peak memory is tracked by a background poller spanning the whole
        // conversion (both paths), so it catches decode/render/encode spikes —
        // not a single post-hoc sample that may read memory after release.
        let memory = PeakMemoryTracker()
        await memory.start()

        let start = DispatchTime.now()
        let frameCount: Int
        let peakBytes: UInt64
        let media: LabMediaSummary
        var resampleReport: ResampleReport?
        do {
            if isGIF {
                let decoder = ASCIIGIFDecoder()
                let header = try decoder.containerHeader(ofGIFAt: inputURL)
                try validateGIFFrameBudget(frameCount: header.frameCount, maxFrames: arguments.maxFrames)
                let stream = decoder.grids(
                    fromGIFAt: inputURL,
                    transform: { converter.convert($0, columns: arguments.columns) }
                )
                var rendered: [RenderedGIFFrame] = []
                var delays: [TimeInterval] = []
                // Accumulated OUTPUT presentation time (running sum of emitted-frame
                // delays, AFTER any --target-fps resample). `ASCIIGIFFrame` carries no
                // PTS, so this is the global-phase clock for the overlay on the GIF
                // path — the analogue of `ASCIIVideoFrame.time` on the MP4 paths.
                var patternTime: TimeInterval = 0
                func collect(_ frame: ASCIIGIFFrame) {
                    rendered.append(
                        GIFRenderHelper.render(
                            frame, font: font, backgroundColor: background, scale: scale,
                            pattern: arguments.ongoingPattern, effects: arguments.effects, at: patternTime
                        ))
                    delays.append(frame.delay)
                    patternTime += frame.delay
                }
                // `.prefix(limit)` stops WITHOUT pulling the (limit+1)th element, so
                // exactly `limit` frames are decoded+converted — matching the MP4
                // CappedRenderDriver's "check remaining before next()" contract and
                // the addendum's literal `grids(...).prefix(N)`. A plain
                // `for-await ... { if count >= limit { break } }` would pull AND run
                // the converter on one extra frame before breaking.
                if let targetFPS = arguments.targetFPS {
                    // Collect the (optionally capped) source frames, then resample.
                    var sourceFrames: [ASCIIGIFFrame] = []
                    if let limit = arguments.maxFrames {
                        for try await frame in stream.prefix(limit) { sourceFrames.append(frame) }
                    } else {
                        for try await frame in stream { sourceFrames.append(frame) }
                    }
                    let sourceDuration = sourceFrames.reduce(0) { $0 + $1.delay }
                    let reStream = AsyncThrowingStream<ASCIIGIFFrame, Error> { continuation in
                        for frame in sourceFrames { continuation.yield(frame) }
                        continuation.finish()
                    }
                    let stats = ResampleStats()
                    let resampled = try resampledGIFFrames(
                        reStream, targetFPS: targetFPS, sourceDuration: sourceDuration, into: stats
                    )
                    for try await frame in resampled { collect(frame) }
                    resampleReport = ResampleReport(
                        requestedFPS: targetFPS,
                        achievedFPS: gifAchievedFPS(targetFPS: targetFPS),
                        sourceFrameCount: await stats.sourceFrameCount,
                        outputFrameCount: await stats.outputFrameCount,
                        droppedCount: await stats.droppedCount,
                        duplicatedCount: await stats.duplicatedCount
                    )
                } else if let limit = arguments.maxFrames {
                    for try await frame in stream.prefix(limit) { collect(frame) }
                } else {
                    for try await frame in stream { collect(frame) }
                }
                let report = try await writeReplacingMediaOutput(to: asciiURL) { tempURL in
                    try ASCIIGIFEncoder().write(rendered, loopCount: header.loopCount, to: tempURL)
                }
                peakBytes = await memory.finish()
                frameCount = rendered.count
                let delayMin = delays.min() ?? 0
                let delayMax = delays.max() ?? 0
                let first = delays.first ?? 0
                let delayUniform = delays.allSatisfy { abs($0 - first) < 1e-6 }
                media = GIFMediaSummary(
                    loopCount: report.loopCount,
                    delayMin: delayMin,
                    delayMax: delayMax,
                    delayUniform: delayUniform
                )
                if report.subFloorDelayCount > 0 {
                    standardOutput("note: \(report.subFloorDelayCount) frame(s) below the 0.02s browser-portability floor\n")
                }
            } else if let targetFPS = arguments.targetFPS {
                // Resample MP4 (handles the optional --max-frames source cap).
                let decoder = ASCIIVideoDecoder()
                let decode = decoder.grids(
                    fromVideoAt: inputURL,
                    transform: { converter.convert($0, columns: arguments.columns) }
                )
                let sourceStream: AsyncThrowingStream<ASCIIVideoFrame, Error>
                let sourceDuration: TimeInterval
                if let limit = arguments.maxFrames {
                    sourceStream = prefixedVideoStream(decode, limit: limit)
                    let duration = try await decoder.sourceDuration(ofVideoAt: inputURL)
                    let fps = try await decoder.nominalFrameRate(ofVideoAt: inputURL)
                    // Throws (caught by the do/catch -> .ioError) if the nominal frame
                    // rate is unavailable — never silently falls back to the FULL
                    // track duration, which would over-duplicate across the asset.
                    sourceDuration = try cappedVideoSourceSpan(
                        trackDuration: duration, nominalFrameRate: fps, limit: limit
                    )
                } else {
                    sourceStream = decode
                    sourceDuration = try await decoder.sourceDuration(ofVideoAt: inputURL)
                }
                let stats = ResampleStats()
                let resampled = try resampledVideoFrames(
                    sourceStream, targetFPS: targetFPS, sourceDuration: sourceDuration, into: stats
                )
                let driver = CappedRenderDriver(
                    stream: resampled, font: font, backgroundColor: background,
                    scale: scale, limit: maxResampledFrames, pattern: arguments.ongoingPattern,
                    effects: arguments.effects
                )
                let renderedStream = AsyncThrowingStream(unfolding: { try await driver.next() })
                var resampleOptions = options
                resampleOptions.expectedFrameRate = targetFPS  // CFR rate-control hint (Task 5b)
                try await writeReplacingMediaOutput(to: asciiURL) { tempURL in
                    try await ASCIIVideoEncoder().write(renderedStream, to: tempURL, options: resampleOptions)
                }
                frameCount = await driver.count()
                peakBytes = await memory.finish()
                media = MP4MediaSummary(codec: arguments.codec == .hevc ? "hevc" : "h264")
                resampleReport = ResampleReport(
                    requestedFPS: targetFPS,
                    achievedFPS: Double(targetFPS),
                    sourceFrameCount: await stats.sourceFrameCount,
                    outputFrameCount: await stats.outputFrameCount,
                    droppedCount: await stats.droppedCount,
                    duplicatedCount: await stats.duplicatedCount
                )
            } else if let limit = arguments.maxFrames {
                // Capped MP4 path: drive the halves directly.
                let stream = ASCIIVideoDecoder().grids(
                    fromVideoAt: inputURL,
                    transform: { converter.convert($0, columns: arguments.columns) }
                )
                let driver = CappedRenderDriver(
                    stream: stream,
                    font: font,
                    backgroundColor: background,
                    scale: scale,
                    limit: limit,
                    pattern: arguments.ongoingPattern,
                    effects: arguments.effects
                )
                let rendered = AsyncThrowingStream(unfolding: { try await driver.next() })
                try await writeReplacingMediaOutput(to: asciiURL) { tempURL in
                    try await ASCIIVideoEncoder().write(rendered, to: tempURL, options: options)
                }
                frameCount = await driver.count()
                peakBytes = await memory.finish()
                media = MP4MediaSummary(codec: arguments.codec == .hevc ? "hevc" : "h264")
            } else {
                // Uncapped MP4 path: the one-shot convenience.
                try await writeReplacingMediaOutput(to: asciiURL) { tempURL in
                    try await convertVideo(
                        at: inputURL,
                        to: tempURL,
                        using: converter,
                        columns: arguments.columns,
                        font: font,
                        backgroundColor: background,
                        scale: scale,
                        export: options,
                        pattern: arguments.ongoingPattern,
                        effects: arguments.effects
                    )
                }
                frameCount = (try? await Self.countOutputFrames(asciiURL)) ?? 0
                peakBytes = await memory.finish()
                media = MP4MediaSummary(codec: arguments.codec == .hevc ? "hevc" : "h264")
            }
        } catch {
            _ = await memory.finish()
            standardError("error: \(error)\n")
            return .ioError
        }
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        let metrics = LabRunMetrics(
            throughputFPS: elapsedSeconds > 0 ? Double(frameCount) / elapsedSeconds : 0,
            peakMemoryBytes: peakBytes,
            frameCount: frameCount,
            inputDescriptor: inputURL.lastPathComponent,
            maxFrames: arguments.maxFrames,
            resample: resampleReport
        )

        do {
            try VideoLabResults.writeMetricsCSV(metrics, media: media, outputDirectory: outputURL)
            try VideoLabResults.writeManifest(
                outputDirectory: outputURL,
                date: date,
                gitSHA: gitSHA,
                command: commandLine(arguments, isGIF: isGIF),
                metrics: metrics,
                media: media,
                outputFiles: [media.outputFileName, "metrics.csv"]
            )
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        standardOutput("wrote \(asciiURL.path) (\(frameCount) frames)\n")
        return .success
    }

    /// Builds the converter from the quality / fidelity levers (ASTSK-39). With
    /// every lever at its default this is exactly `DefaultConverter()` (charset
    /// `.standard`, oversample 2, `RenderingOptions.default`), so the historical
    /// zero-flag output is unchanged. Out-of-range tonal values clamp silently in
    /// `ResolvedRenderingOptions`; `--oversample` is range-checked at parse time.
    static func makeConverter(from arguments: VideoLabArguments) -> DefaultConverter {
        let options = RenderingOptions(
            density: Float(arguments.density),
            edgeEmphasis: Float(arguments.edgeEmphasis),
            brightness: Float(arguments.brightness),
            contrast: Float(arguments.contrast)
        )
        return ASCIIConverter(
            characterSet: arguments.charset.characterSet,
            palette: BuiltInPalette.fullColor,
            options: options,
            oversample: arguments.oversample
        )
    }

    public static func todayUTC() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Counts frames in the lab's own output (uncapped path only) using
    /// `ASCIIVideoDecoder`. A no-op transform keeps it cheap.
    private static func countOutputFrames(_ url: URL) async throws -> Int {
        var count = 0
        for try await _ in ASCIIVideoDecoder().grids(
            fromVideoAt: url,
            transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
        ) {
            count += 1
        }
        return count
    }

    static func validateGIFFrameBudget(frameCount: Int, maxFrames: Int?) throws {
        guard maxFrames == nil, frameCount > ToolArgumentBounds.maxVideoFrames else { return }
        throw VideoLabRunError.uncappedGIFFrameCountExceedsLimit(
            count: frameCount,
            limit: ToolArgumentBounds.maxVideoFrames
        )
    }

    @discardableResult
    private static func writeReplacingMediaOutput<T>(
        to finalURL: URL,
        write: (URL) async throws -> T
    ) async throws -> T {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: finalURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw VideoLabOutputError.outputPathIsDirectory(finalURL.path)
        }

        let tempURL = temporaryMediaURL(for: finalURL)
        do {
            let result = try await write(tempURL)
            try replaceMediaOutput(tempURL, withFinalURL: finalURL)
            return result
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    private static func temporaryMediaURL(for finalURL: URL) -> URL {
        let directory = finalURL.deletingLastPathComponent()
        let baseName = finalURL.deletingPathExtension().lastPathComponent
        let ext = finalURL.pathExtension
        let tempName =
            ext.isEmpty
            ? ".\(baseName)-\(UUID().uuidString)"
            : ".\(baseName)-\(UUID().uuidString).\(ext)"
        return directory.appendingPathComponent(tempName)
    }

    private static func replaceMediaOutput(_ tempURL: URL, withFinalURL finalURL: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: finalURL.path, isDirectory: &isDirectory) {
            guard !isDirectory.boolValue else {
                throw VideoLabOutputError.outputPathIsDirectory(finalURL.path)
            }
            _ = try fileManager.replaceItemAt(finalURL, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: finalURL)
        }
    }

    private static func commandLine(_ arguments: VideoLabArguments, isGIF: Bool) -> String {
        var parts = [
            "swift run AskiVideoLab",
            "--input \(arguments.inputPath)",
            "--output-dir \(arguments.outputDirectory)",
            "--columns \(arguments.columns)",
        ]
        if !isGIF {
            parts.append("--codec \(arguments.codec == .hevc ? "hevc" : "h264")")
        }
        parts.append("--font-scale \(arguments.fontScale)")
        if let maxFrames = arguments.maxFrames {
            parts.append("--max-frames \(maxFrames)")
        }
        if let targetFPS = arguments.targetFPS {
            parts.append("--target-fps \(targetFPS)")
        }
        // Quality levers are recorded only when non-default, so existing
        // zero-flag runs keep their historical command string in result.yaml.
        if arguments.charset != .standard {
            parts.append("--charset \(arguments.charset.rawValue)")
        }
        if arguments.oversample != ToolArgumentBounds.defaultOversample {
            parts.append("--oversample \(arguments.oversample)")
        }
        if arguments.brightness != 0 {
            parts.append("--brightness \(arguments.brightness)")
        }
        if arguments.contrast != 0 {
            parts.append("--contrast \(arguments.contrast)")
        }
        if arguments.density != 0 {
            parts.append("--density \(arguments.density)")
        }
        if arguments.edgeEmphasis != 0 {
            parts.append("--edge-emphasis \(arguments.edgeEmphasis)")
        }
        // Pattern flags are recorded only when an overlay is active (and each knob
        // only when non-default), so historical zero-flag runs keep their command
        // string. `direction` has no CLI flag, so it never round-trips here.
        switch arguments.ongoingPattern {
        case .wave(let amplitude, let frequency, _):
            parts.append("--pattern wave")
            if amplitude != 0.5 { parts.append("--pattern-amplitude \(amplitude)") }
            if frequency != 1.0 { parts.append("--pattern-frequency \(frequency)") }
        case .pulse(let period, let depth):
            parts.append("--pattern pulse")
            if period != 1.0 { parts.append("--pattern-period \(period)") }
            if depth != 1.0 { parts.append("--pattern-depth \(depth)") }
        case nil:
            break
        }
        // Cosmetic effects are recorded only when active (intensity > 0), and each
        // radius/frequency knob only when non-default, so zero-flag runs keep their
        // historical command string. Reconstructed from the resolved chain; only the
        // three video-exposed cases (bloom/scanLines/vignette) can appear here.
        for effect in arguments.effects.effects {
            switch effect {
            case .bloom(let intensity, let radius):
                parts.append("--bloom \(intensity)")
                if radius != ToolArgumentBounds.defaultBloomRadius { parts.append("--bloom-radius \(radius)") }
            case .scanLines(let intensity, let frequency):
                parts.append("--scanlines \(intensity)")
                if frequency != ToolArgumentBounds.defaultScanlineFrequency { parts.append("--scanline-frequency \(frequency)") }
            case .vignette(let intensity):
                parts.append("--vignette \(intensity)")
            default:
                break
            }
        }
        if let gitShaOverride = arguments.gitShaOverride {
            parts.append("--aski-git-sha \(gitShaOverride)")
        }
        return parts.joined(separator: " ")
    }
}

enum VideoLabOutputError: Error, CustomStringConvertible {
    case outputPathIsDirectory(String)

    var description: String {
        switch self {
        case .outputPathIsDirectory(let path):
            "output media path is a directory, expected a file: \(path)"
        }
    }
}

/// Synchronous render so overload resolution selects `ASCIIGrid`'s plain
/// `renderImage(font:backgroundColor:scale:) -> CGImage` over the async-throws
/// effects overload. The non-`Sendable` `CGColor` stays in this sync call. An
/// empty effect chain keeps the plain renderer (byte-identical to before); a
/// non-empty chain routes through the synchronous `effects:` overload. Effects
/// are time-invariant, so only the pattern uses the per-frame `time`.
enum GIFRenderHelper {
    static func render(
        _ frame: ASCIIGIFFrame,
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        pattern: OngoingPattern? = nil,
        effects: EffectChain = .init(),
        at time: TimeInterval = 0
    ) -> RenderedGIFFrame {
        let grid = pattern.map { frame.grid.applyingOngoingPattern($0, at: time) } ?? frame.grid
        let image: CGImage
        if effects.effects.isEmpty {
            image = grid.renderImage(font: font, backgroundColor: backgroundColor, scale: scale)
        } else {
            image = grid.renderImage(font: font, backgroundColor: backgroundColor, scale: scale, effects: effects)
        }
        return RenderedGIFFrame(image: image, delay: frame.delay)
    }
}
