import Aski
import Foundation

public enum ToolArgumentBounds {
    public static let maxColumns = 512
    public static let maxFontSize = 96.0
    public static let maxFontScale = 8.0
    public static let maxTileScale = 64.0
    public static let maxFPS = 120
    public static let maxDuration = 60.0
    public static let maxVideoFrames = 10_000
    // Mirrors the library contract so the labs reject an oversized request
    // before `materialize(frameRate:)` traps on the same bound.
    public static let maxMaterializedFrames = AnimatedASCIIGrid.maxMaterializedFrameCount
    public static let defaultOversample = 2
    public static let maxOversample = 8
    // Cosmetic post-render effect defaults (ASTSK-39 step b). Shared so the
    // `--bloom-radius`/`--scanline-frequency` flag defaults and the result.yaml
    // command reconstruction agree on what counts as "non-default".
    public static let defaultBloomRadius = 6.0
    public static let defaultScanlineFrequency = 8.0

    public static func thumbnailMaxPixelSize(
        imageWidth: Int,
        imageHeight: Int,
        columns: Int,
        tileShape: ASCIITileShape,
        oversample: Int = defaultOversample
    ) -> Int {
        guard imageWidth > 0, imageHeight > 0, columns > 0 else {
            return 1
        }
        let rows = gridRows(
            imageWidth: imageWidth, imageHeight: imageHeight,
            columns: columns, tileShape: tileShape)
        return max(columns, rows) * max(1, oversample)
    }

    /// Grid rows the converter resolves for this geometry — a mirror of
    /// `gridDimensions`, kept here so tools can size a fixture without the
    /// `@_spi` surface. Mirrors drift, so every lab that depends on the value
    /// also asserts it against the converter's own resolved grid.
    public static func gridRows(
        imageWidth: Int,
        imageHeight: Int,
        columns: Int,
        tileShape: ASCIITileShape
    ) -> Int {
        guard imageWidth > 0, imageHeight > 0, columns > 0 else {
            return 1
        }
        let aspectRatio = Float(imageHeight) / Float(imageWidth)
        return max(1, Int((Float(columns) * aspectRatio) / tileShape.sourceCellHeightOverWidth))
    }

    /// Whether a fixture of this size is an **exact sampling lattice** for the
    /// grid it resolves: both axes divide evenly, so the converter reads the
    /// fixture at native resolution instead of folding a remainder into a
    /// rescaled raster (ASKI-65). Research instruments that compare the
    /// converter's cells against native source blocks require this.
    public static func latticeIsExact(
        imageWidth: Int,
        imageHeight: Int,
        columns: Int,
        tileShape: ASCIITileShape
    ) -> Bool {
        guard imageWidth > 0, imageHeight > 0, columns > 0 else {
            return false
        }
        let rows = gridRows(
            imageWidth: imageWidth, imageHeight: imageHeight,
            columns: columns, tileShape: tileShape)
        return imageWidth % columns == 0 && imageHeight % rows == 0
    }

    /// The smallest height `>= minimumHeight` that makes `width × height` an
    /// exact lattice at `columns`, or `nil` if none is found within `slack`
    /// rows. Fixture authoring helper: the row count is itself a function of
    /// the height, so the height cannot be solved in closed form.
    public static func exactLatticeHeight(
        width: Int,
        columns: Int,
        tileShape: ASCIITileShape,
        minimumHeight: Int,
        slack: Int = 4096
    ) -> Int? {
        guard width > 0, columns > 0, minimumHeight > 0, width % columns == 0 else {
            return nil
        }
        for height in minimumHeight..<(minimumHeight + slack)
        where latticeIsExact(
            imageWidth: width, imageHeight: height, columns: columns, tileShape: tileShape)
        {
            return height
        }
        return nil
    }

    public static func materializedFrameCountIsValid(duration: Double, fps: Int) -> Bool {
        guard duration.isFinite, duration > 0, fps > 0 else {
            return false
        }
        let upperBound = duration * Double(fps)
        guard upperBound.isFinite else {
            return false
        }
        return ceil(upperBound) + 1 <= Double(maxMaterializedFrames)
    }
}
