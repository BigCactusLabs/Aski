import Foundation

/// A continuous, time-driven modulation applied to a grid's per-cell alpha.
///
/// ## Which knobs are rejected and which are clamped
///
/// `amplitude` and `depth` are *aesthetic*: every value has a sensible
/// projection into their range, so an out-of-domain one is clamped
/// (`0.7` → `0.5`, `NaN` → the default) and the call succeeds.
///
/// `frequency` and `period` are *structural* — they set the pattern's cadence —
/// and have no such projection. There is no defensible "nearest valid" period
/// to a `period` of `0`: any substitute silently animates something other than
/// what the caller asked for. So they are rejected at the boundary instead,
/// matching `CyclingOptions.speed` and `AnimationOptions.duration`.
///
/// That is the whole rule: **no sensible projection ⇒ structural ⇒ reject.**
public enum OngoingPattern: Sendable, Equatable {
    /// Traveling sine wave modulating per-cell alpha. Diagonal direction
    /// sweeps less than one full cycle to avoid endpoint aliasing.
    ///
    /// - Parameters:
    ///   - amplitude: Aesthetic. Any value is accepted and clamped to `0...0.5`;
    ///     a non-finite value falls back to `0.5`.
    ///   - frequency: Structural. Must be finite and positive; an out-of-domain
    ///     value is rejected, not sanitized.
    case wave(amplitude: Double = 0.5, frequency: Double = 1.0, direction: WaveDirection = .horizontal)

    /// Whole-grid brightness pulse.
    ///
    /// - Parameters:
    ///   - period: Structural. Must be finite and positive; an out-of-domain
    ///     value is rejected, not sanitized.
    ///   - depth: Aesthetic. Any value is accepted and clamped to `0...1`; a
    ///     non-finite value falls back to `1`.
    case pulse(period: TimeInterval = 1.0, depth: Double = 1.0)
}

internal extension OngoingPattern {
    /// Traps unless the pattern's structural knobs define an evaluable
    /// schedule.
    ///
    /// Enum cases cannot validate at construction, so instead *every* public
    /// entry point that accepts an `OngoingPattern` calls this before doing any
    /// work, which keeps the failure at the call the caller can see rather than
    /// inside the per-cell evaluation loop (ASKI-18). The complete set of
    /// accepting entry points:
    ///
    /// - `AnimationOptions.init(duration:seed:cycling:entrance:ongoing:)`
    /// - `ASCIIConverter.animate(_:columns:options:mask:)` and
    ///   `ScheduleBuilder.build`, because `AnimationOptions.ongoing` is a
    ///   settable `var` and can be mutated out of domain after construction
    /// - `ASCIIGrid.applyingOngoingPattern(_:at:)`
    /// - `ASCIIVideoFrame.applyingOngoingPattern(_:)`
    /// - `convertVideo(at:to:using:columns:font:backgroundColor:scale:...)`
    ///
    /// Adding a new entry point that accepts an `OngoingPattern` means adding a
    /// call here too; `PatternEvaluator.ongoingAlpha` keeps a matching
    /// precondition as the backstop if one is forgotten.
    func validate() {
        switch self {
        case .wave(_, let frequency, _):
            precondition(
                frequency.isFinite && frequency > 0,
                "OngoingPattern.wave frequency must be finite and positive")
        case .pulse(let period, _):
            precondition(
                period.isFinite && period > 0,
                "OngoingPattern.pulse period must be finite and positive")
        }
    }
}
