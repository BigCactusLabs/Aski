import Accelerate
import Darwin
import Foundation

/// Lab-local cube-root candidates. None are promoted to public Aski API;
/// cross-comparison against a Float64 reference is this lab's purpose, and any
/// production flip in `Sources/Aski/ColorConversion.swift` is a Slice 2
/// decision driven by the CSV this command emits.
public enum CuberootAccuracyPolicies {

    /// Canonical CSV order — addendum §"Three deltas" Delta 1.
    public static let canonicalOrder: [Identifier] = [
        .legacySignPow,
        .darwinCbrtf,
        .accelerateVvcbrtf,
    ]

    public enum Identifier: CaseIterable, Sendable {
        case legacySignPow
        case darwinCbrtf
        case accelerateVvcbrtf

        /// CSV label per addendum §"Three deltas" Delta 1 table — snake-cased,
        /// not the Swift identifier.
        public var csvLabel: String {
            switch self {
            case .legacySignPow: return "legacy_sign_pow"
            case .darwinCbrtf: return "darwin_cbrtf"
            case .accelerateVvcbrtf: return "accelerate_vvcbrtf"
            }
        }
    }

    /// Bit-exact mirror of `Sources/Aski/ColorConversion.swift:54-78`. The
    /// `sign` helper returns ±1 (never 0); `abs` collapses both signed zeros to
    /// `+0.0f`. The whole point of the lab CSV is to measure the deviation
    /// between this and `cbrtf`; do not "improve" this implementation.
    public static func legacySignPow(_ x: Float) -> Float {
        productionSign(x) * powf(fabsf(x), 1.0 / 3.0)
    }

    /// IEEE 754 / C Annex F cube root. Sign-preserving on odd-degree roots
    /// (so `cbrtf(-0.0f) = -0.0f`).
    public static func darwinCbrtf(_ x: Float) -> Float {
        Darwin.cbrtf(x)
    }

    /// Accelerate vForce single-precision cube root, invoked on a length-1
    /// buffer. `vvcbrtf` is element-wise per Accelerate's contract, so the
    /// numerical result is identical whether called per-scalar (here) or in a
    /// batched call (the deferred AskiMotionLab codepath).
    public static func accelerateVvcbrtf(_ x: Float) -> Float {
        var input: Float = x
        var output: Float = 0
        var count: Int32 = 1
        vvcbrtf(&output, &input, &count)
        return output
    }

    public static func apply(policy: Identifier, input x: Float) -> Float {
        switch policy {
        case .legacySignPow: return legacySignPow(x)
        case .darwinCbrtf: return darwinCbrtf(x)
        case .accelerateVvcbrtf: return accelerateVvcbrtf(x)
        }
    }

    // Matches the `sign(_:)` helper at `Sources/Aski/ColorConversion.swift:160`.
    // Returns ±1 (never 0). The `x = 0` case is immaterial because
    // `fabsf(±0.0) * pow(...) = 0.0` regardless of the multiplier, so the
    // returned bit pattern carries the sign of the multiplier — which is what
    // makes `legacy_sign_pow(-0.0f)` an interesting empirical question rather
    // than a trivial one.
    @inline(__always)
    private static func productionSign(_ x: Float) -> Float {
        x < 0 ? -1 : 1
    }
}
