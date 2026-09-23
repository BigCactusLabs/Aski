import CoreGraphics
import simd

/// Color quantization strategy for a `TileGridConverter`. Struct-with-static-
/// factories per spec: heterogeneous associated data (`Int` for adaptive,
/// nothing for brick, `[CGColor]` for fixed) precludes a clean enum.
public struct TilePalette: Sendable {
    internal enum Strategy: Sendable {
        case adaptive(maxColors: Int)
        /// Covers `.brick` (precomputed) and `.fixed(_:)` (converted at init).
        case fixedOKLAB([SIMD3<Float>])
    }

    internal let strategy: Strategy

    private init(strategy: Strategy) {
        self.strategy = strategy
    }

    /// Run Wu + k-means in OKLAB on the source pixels at convert time. Output
    /// has at most `maxColors` entries (clamped to `2...256`); fewer if the
    /// source has fewer distinct colors.
    public static func adaptive(maxColors: Int) -> TilePalette {
        .init(strategy: .adaptive(maxColors: max(2, min(256, maxColors))))
    }

    /// Approximated interlocking-brick-style palette (~30 colors, generic
    /// names; see `Tiles.md` DocC disclaimer for non-affiliation).
    public static let brick = TilePalette(strategy: .fixedOKLAB(BrickColors.oklab))

    /// Caller-supplied fixed palette. `CGColor`s are converted to OKLAB once
    /// at construction; CMYK/indexed inputs are routed through `converted(to:)`.
    ///
    /// - Precondition: `colors` must not be empty.
    public static func fixed(_ colors: [CGColor]) -> TilePalette {
        precondition(!colors.isEmpty, "TilePalette.fixed requires at least one color")

        let oklab = colors.map { ColorConversion.cgColorToOKLAB($0) }
        return .init(strategy: .fixedOKLAB(oklab))
    }
}
