import Aski
import Foundation

/// Preconfigured `AnimationOptions` bundles, one per animated axis. No new
/// motion code - these drive the existing engine.
public enum MotionPresets {
    /// Visibility axis. `cycling: nil` is mandatory and explicit (the
    /// `AnimationOptions.init` default is `.default`, which would also cycle
    /// glyphs). Motion is pure alpha: cells fade/scan in from the top-leading
    /// origin. Churn signature: alpha-churn > 0, glyph-churn = 0.
    public static func reveal(duration: TimeInterval, seed: UInt64) -> AnimationOptions {
        AnimationOptions(
            duration: duration,
            seed: seed,
            cycling: nil,
            entrance: .reveal(origin: .topLeading, easing: .easeInOut),
            ongoing: nil
        )
    }

    /// Glyph axis. Each cell loops through its top-`k` ranked glyph candidates
    /// (color stays fixed). `randomness: 0.0` keeps it deterministic; no
    /// entrance/ongoing keeps alpha constant.
    public static func cycle(duration: TimeInterval, seed: UInt64) -> AnimationOptions {
        AnimationOptions(
            duration: duration,
            seed: seed,
            cycling: CyclingOptions(k: 4, speed: 1.0, intensity: 0.6, randomness: 0.0),
            entrance: nil,
            ongoing: nil
        )
    }

    public static func options(for preset: MotionLabPreset, duration: TimeInterval, seed: UInt64) -> AnimationOptions {
        switch preset {
        case .reveal: reveal(duration: duration, seed: seed)
        case .cycle: cycle(duration: duration, seed: seed)
        }
    }
}
