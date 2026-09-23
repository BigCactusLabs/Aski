import CoreGraphics

/// Render-time visual mode for a `TileGrid`. Struct-with-static-factories so
/// adding new modes is purely additive (no exhaustive-switch breakage at
/// consumer sites).
public struct TileGridMode: Sendable {
    internal enum Representation: Sendable {
        case pixelArt
        case brick
        case mosaic(grout: CGColor, groutThickness: Double, cornerRadius: Double)
    }

    internal let representation: Representation

    private init(_ representation: Representation) {
        self.representation = representation
    }

    /// Flat color per cell.
    public static let pixelArt = TileGridMode(.pixelArt)

    /// Flat color plus circular stud overlay; see `TileCellShape` for stud placement.
    public static let brick = TileGridMode(.brick)

    /// Inset rounded cell with grout-colored gaps. `groutThickness` and
    /// `cornerRadius` are fractions of cell width, clamped to `0...0.5`. `0.5`
    /// is the geometric ceiling: past it the inset would invert through the
    /// centroid and rounding arcs would collide.
    public static func mosaic(
        grout: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        groutThickness: Double = 0.1,
        cornerRadius: Double = 0.15
    ) -> TileGridMode {
        let clampedThickness = max(0, min(0.5, groutThickness))
        let clampedRadius = max(0, min(0.5, cornerRadius))
        return TileGridMode(
            .mosaic(
                grout: grout,
                groutThickness: clampedThickness,
                cornerRadius: clampedRadius
            ))
    }

    /// Convenience: `.mosaic()` with default parameters.
    public static let mosaic = TileGridMode.mosaic()
}
