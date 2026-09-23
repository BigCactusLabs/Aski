import Aski
import ArgumentParser
import AskiToolSupport
import Foundation

/// CLI selector for `--codec` mapping to the library `VideoCodec`. `CaseIterable`
/// + `ExpressibleByArgument` makes SAP list `h264`/`hevc` and reject others.
public enum VideoCodecArgument: String, CaseIterable, ExpressibleByArgument {
    case h264
    case hevc

    public var codec: VideoCodec {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        }
    }
}

/// CLI selector for `--pattern`, mapping to the library `OngoingPattern`
/// (`.none` ⇒ no overlay). `CaseIterable` + `ExpressibleByArgument` makes SAP
/// list `none`/`wave`/`pulse` and reject anything else.
public enum PatternArgument: String, CaseIterable, ExpressibleByArgument {
    case none
    case wave
    case pulse
}

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct VideoLabCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "AskiVideoLab",
        abstract: "Stream an MP4 or animated GIF through the ASCII pipeline and re-encode the same format.",
        version: ToolVersion.current
    )

    @Option(name: .long, help: "Source MP4/MOV or animated GIF to convert.")
    public var input: String

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(help: "ASCII columns (1...\(ToolArgumentBounds.maxColumns)).")
    public var columns: Int = 80

    @Option(help: "Output codec (MP4 path only; ignored for GIF): h264 | hevc.")
    public var codec: VideoCodecArgument = .h264

    @Option(name: .customLong("font-scale"), help: "Render scale multiplier (0 < n <= \(ToolArgumentBounds.maxFontScale)).")
    public var fontScale: Double = 1.0

    @Option(
        name: .customLong("max-frames"),
        help:
            "Cap decoded frames (1...\(ToolArgumentBounds.maxVideoFrames)); uncapped GIFs over the limit fail before delay scanning."
    )
    public var maxFrames: Int?

    @Option(name: .customLong("target-fps"), help: "Resample timing to N fps (1...\(maxTargetFPS)).")
    public var targetFPS: Int?

    @Option(help: "Character set: \(Charset.allCases.map(\.rawValue).joined(separator: " | ")).")
    public var charset: Charset = .standard

    @Option(
        help:
            "Per-cell pixel-budget multiplier (1...\(ToolArgumentBounds.maxOversample)); 4+ enables the edge-emphasis Sobel path."
    )
    public var oversample: Int = ToolArgumentBounds.defaultOversample

    // `.unconditional` so a negative value (`--brightness -0.2`) is taken as the
    // option's value instead of being misread as another option flag.
    @Option(parsing: .unconditional, help: "OKLAB L additive offset (-1...1; out-of-range clamps).")
    public var brightness: Double = 0

    @Option(parsing: .unconditional, help: "OKLAB L scale-around-0.5 (-1...1; out-of-range clamps).")
    public var contrast: Double = 0

    @Option(help: "logPolar brightness-prefilter slack (0...1; out-of-range clamps).")
    public var density: Double = 0

    @Option(name: .customLong("edge-emphasis"), help: "logPolar edge-emphasis weight (0...1; needs oversample 4+).")
    public var edgeEmphasis: Double = 0

    @Option(help: "Time-modulated overlay: \(PatternArgument.allCases.map(\.rawValue).joined(separator: " | ")). Default: none.")
    public var pattern: PatternArgument = .none

    @Option(name: .customLong("pattern-amplitude"), help: "Wave alpha amplitude (0...0.5; out-of-range clamps).")
    public var patternAmplitude: Double = 0.5

    @Option(name: .customLong("pattern-frequency"), help: "Wave cycles per second (finite, > 0).")
    public var patternFrequency: Double = 1.0

    @Option(name: .customLong("pattern-period"), help: "Pulse period in seconds (finite, > 0).")
    public var patternPeriod: Double = 1.0

    @Option(name: .customLong("pattern-depth"), help: "Pulse modulation depth (0...1; out-of-range clamps).")
    public var patternDepth: Double = 1.0

    // Cosmetic post-render effects (ASTSK-39 step b). Each intensity defaults to
    // 0 (off) so omitting every flag is byte-identical to today. They are
    // time-invariant (constant every frame) — per the temporal-coherence
    // literature, that is what keeps them flicker-free, unlike the per-frame
    // stochastic effects (glitch/film grain), which are deliberately not exposed.
    @Option(help: "Cosmetic bloom/glow intensity (0...1; 0 = off). Post-render, time-invariant.")
    public var bloom: Double = 0

    @Option(name: .customLong("bloom-radius"), help: "Bloom blur radius in px (finite, > 0). Default: \(ToolArgumentBounds.defaultBloomRadius).")
    public var bloomRadius: Double = ToolArgumentBounds.defaultBloomRadius

    @Option(help: "Cosmetic scanline intensity (0...1; 0 = off). Post-render, time-invariant.")
    public var scanlines: Double = 0

    @Option(
        name: .customLong("scanline-frequency"),
        help: "Scanline spacing divisor in px (finite, > 0; larger = wider, more visible lines). Default: \(ToolArgumentBounds.defaultScanlineFrequency)."
    )
    public var scanlineFrequency: Double = ToolArgumentBounds.defaultScanlineFrequency

    @Option(help: "Cosmetic vignette intensity (0...1; 0 = off). Post-render, time-invariant.")
    public var vignette: Double = 0

    public init() {}

    /// The library `OngoingPattern` selected by `--pattern` (+ its knobs), or
    /// `nil` for `--pattern none` (no overlay → byte-identical to today).
    public var resolvedPattern: OngoingPattern? {
        switch pattern {
        case .none: nil
        case .wave: .wave(amplitude: patternAmplitude, frequency: patternFrequency, direction: .horizontal)
        case .pulse: .pulse(period: patternPeriod, depth: patternDepth)
        }
    }

    /// Cosmetic post-render chain from `--bloom`/`--scanlines`/`--vignette`. Each
    /// effect is appended only when its intensity is > 0, so an all-zero command
    /// yields an empty chain → the render paths stay on the plain renderer
    /// (byte-identical to today). Order is bloom → scanlines → vignette: bloom
    /// softens glyph edges first, then the CRT-style scanlines/vignette composite
    /// last (per the frontier-search on ASCII-video effect ordering). Intensities
    /// clamp to 0...1; non-finite radius/frequency are rejected in `validate()`.
    public var resolvedEffects: EffectChain {
        var effects: [Effect] = []
        let bloomIntensity = clampedUnit(bloom)
        if bloomIntensity > 0 { effects.append(.bloom(intensity: bloomIntensity, radius: bloomRadius)) }
        let scanlineIntensity = clampedUnit(scanlines)
        if scanlineIntensity > 0 { effects.append(.scanLines(intensity: scanlineIntensity, frequency: scanlineFrequency)) }
        let vignetteIntensity = clampedUnit(vignette)
        if vignetteIntensity > 0 { effects.append(.vignette(intensity: vignetteIntensity)) }
        return EffectChain(effects)
    }

    /// Clamp a cosmetic intensity to 0...1, treating non-finite/≤0 as off. `validate()`
    /// already rejects non-finite intensities, so this only bites if `resolvedEffects`
    /// is read on an unvalidated command (e.g. a unit test).
    private func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return min(value, 1)
    }

    public func validate() throws {
        try ToolValidation.requireColumns(columns)
        try ToolValidation.requireFontScale(fontScale)
        if let maxFrames {
            try ToolValidation.requirePositiveInt(maxFrames, max: ToolArgumentBounds.maxVideoFrames, name: "--max-frames")
        }
        if let targetFPS {
            try ToolValidation.requirePositiveInt(targetFPS, max: maxTargetFPS, name: "--target-fps")
        }
        try ToolValidation.requirePositiveInt(oversample, max: ToolArgumentBounds.maxOversample, name: "--oversample")
        try ToolValidation.requireFinite(brightness, name: "--brightness")
        try ToolValidation.requireFinite(contrast, name: "--contrast")
        try ToolValidation.requireFinite(density, name: "--density")
        try ToolValidation.requireFinite(edgeEmphasis, name: "--edge-emphasis")
        // Wave frequency and pulse period reach hard `precondition`s in
        // `PatternEvaluator.ongoingAlpha`; amplitude/depth are silently clamped
        // there, so only these two need rejecting before they can trap.
        try ToolValidation.requirePositiveFinite(patternFrequency, name: "--pattern-frequency")
        try ToolValidation.requirePositiveFinite(patternPeriod, name: "--pattern-period")
        // Effect intensities clamp to 0...1 (like the tonal levers) but must be
        // finite. Radius/frequency reach `CIBloom`/the scanlines kernel directly,
        // where a non-finite or non-positive value would misbehave, so reject them.
        try ToolValidation.requireFinite(bloom, name: "--bloom")
        try ToolValidation.requireFinite(scanlines, name: "--scanlines")
        try ToolValidation.requireFinite(vignette, name: "--vignette")
        try ToolValidation.requirePositiveFinite(bloomRadius, name: "--bloom-radius")
        try ToolValidation.requirePositiveFinite(scanlineFrequency, name: "--scanline-frequency")
    }

    public func executeAsync(
        codecWasProvided: Bool = false,
        standardOutput: @Sendable (String) -> Void = { print($0, terminator: "") },
        standardError: @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = VideoLabCLI.todayUTC()
    ) async -> LabExitCode {
        let arguments = VideoLabArguments(
            inputPath: input,
            outputDirectory: provenance.outputDirectory,
            columns: columns,
            codec: codec.codec,
            fontScale: fontScale,
            maxFrames: maxFrames,
            targetFPS: targetFPS,
            gitShaOverride: provenance.gitShaOverride,
            charset: charset,
            oversample: oversample,
            brightness: brightness,
            contrast: contrast,
            density: density,
            edgeEmphasis: edgeEmphasis,
            ongoingPattern: resolvedPattern,
            effects: resolvedEffects
        )
        return await VideoLabCLI.run(
            arguments: arguments,
            codecWasProvided: codecWasProvided,
            standardOutput: standardOutput,
            standardError: standardError,
            date: date
        )
    }

    public mutating func run() async throws {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let status = await executeAsync(codecWasProvided: rawArguments.contains("--codec"))
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}
