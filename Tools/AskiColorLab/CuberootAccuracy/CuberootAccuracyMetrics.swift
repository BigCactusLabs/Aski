import Foundation

/// Pure measurement functions. No Aski dependency; consumed by
/// `CuberootAccuracyCommand` for the per-row metric columns.
public enum CuberootAccuracyMetrics {

    public struct Result: Sendable, Equatable {
        public let ulpDistance: Int
        public let absError: Float
        /// `nil` when the reference is `±0.0f`. The command serializes `nil`
        /// as the literal string `n/a`.
        public let relError: Float?
    }

    /// Signed ULP distance between two `Float`s, computed via the canonical
    /// "monotonic float ordering" trick:
    ///
    ///   key(b) = (b & 0x7FFFFFFF) ^ ((b >> 31) ? 0x7FFFFFFF : 0)
    ///
    /// rewrites each bit pattern as a signed magnitude so positives stay
    /// positive and negatives flip into a monotonically ordered range below
    /// zero. The subtraction then yields a signed ULP distance whose sign
    /// matches `output > reference`.
    ///
    /// `+0.0` and `-0.0` are deliberately **not** merged — the negative-zero
    /// fixture exists precisely to measure their separation in policy outputs.
    public static func ulpDistance(output: Float, reference: Float) -> Int {
        Int(orderedKey(output)) - Int(orderedKey(reference))
    }

    public static func absError(output: Float, reference: Float) -> Float {
        abs(output - reference)
    }

    public static func compute(output: Float, reference: Float) -> Result {
        let abs = absError(output: output, reference: reference)
        let rel: Float?
        if reference == 0 {
            rel = nil
        } else {
            rel = abs / Swift.abs(reference)
        }
        return Result(
            ulpDistance: ulpDistance(output: output, reference: reference),
            absError: abs,
            relError: rel
        )
    }

    @inline(__always)
    private static func orderedKey(_ x: Float) -> Int32 {
        let bits = Int32(bitPattern: x.bitPattern)
        // Negative floats have the sign bit set. Mirror them into the
        // negative half of the signed-int line by XOR'ing with 0x7FFFFFFF
        // (preserving the sign bit, flipping the rest).
        return bits < 0 ? (bits ^ 0x7FFFFFFF) : bits
    }
}
