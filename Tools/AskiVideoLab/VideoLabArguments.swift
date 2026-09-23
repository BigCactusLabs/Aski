import Aski
import AskiToolSupport
import Foundation

/// Parsed VideoLab invocation context handed to `VideoLabCLI.run`. (The
/// hand-rolled parser and `VideoLabArgumentError` were removed in the SAP
/// migration.) Must be `public`: the public `VideoLabCLI.run` exposes it in its
/// signature, and Swift forbids a public API surfacing an internal type. Stored
/// properties stay internal (only constructed in-module by `VideoLabCommand`).
///
/// Explicit `Sendable`: making the struct `public` drops the implicit `Sendable`
/// conformance the previous internal struct had, and `VideoLabCLI.run` captures
/// it in `@Sendable` closures. All stored properties are already `Sendable`.
public struct VideoLabArguments: Sendable {
    var inputPath: String
    var outputDirectory: String
    var columns: Int
    var codec: VideoCodec
    var fontScale: Double
    var maxFrames: Int?
    var targetFPS: Int?
    var gitShaOverride: String?
    // Quality / fidelity levers (ASTSK-39). Defaults reproduce `DefaultConverter()`.
    var charset: Charset = .standard
    var oversample: Int = ToolArgumentBounds.defaultOversample
    var brightness: Double = 0
    var contrast: Double = 0
    var density: Double = 0
    var edgeEmphasis: Double = 0
    // Time-modulated overlay (ASTSK-39 AC#2). `nil` ⇒ no overlay, byte-identical
    // to the historical zero-flag output.
    var ongoingPattern: OngoingPattern?
    // Cosmetic post-render effects (ASTSK-39 step b). Empty ⇒ no effects,
    // byte-identical to the historical zero-flag output. Time-invariant, so unlike
    // `ongoingPattern` they carry no per-frame phase.
    var effects: EffectChain = .init()
}
