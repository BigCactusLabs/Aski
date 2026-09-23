import CoreGraphics
import Foundation

/// Image-to-tile-grid converter. Holds palette, sampling-shape, brightness/
/// contrast options, color space, and oversample multiplier. Mode and
/// cell-shape are render-time parameters on `TileGrid.renderImage(...)`.
public struct TileGridConverter: Sendable {
    public var palette: TilePalette
    public var samplingShape: ASCIITileShape
    public var options: RenderingOptions
    public var colorSpace: RenderColorSpace
    public var oversample: Int

    public init(
        palette: TilePalette = .adaptive(maxColors: 16),
        samplingShape: ASCIITileShape = .square,
        options: RenderingOptions = .default,
        colorSpace: RenderColorSpace = .sRGB,
        oversample: Int = 2
    ) {
        self.palette = palette
        self.samplingShape = samplingShape
        self.options = options
        self.colorSpace = colorSpace
        self.oversample = oversample
    }

    /// Convert `image` to a `TileGrid` with the requested column count.
    /// Returns an empty grid (no rows, no cells) on degenerate input.
    public func convert(_ image: CGImage, columns: Int, mask: MaskOptions? = nil) -> TileGrid {
        guard columns > 0 else {
            return TileGrid(cells: [], colorSpace: colorSpace)
        }

        let resolvedOptions = ResolvedRenderingOptions(options)
        guard
            let (cols, rows) = gridDimensions(
                imageWidth: image.width,
                imageHeight: image.height,
                columns: columns,
                tileShape: samplingShape
            )
        else {
            return TileGrid(cells: [], colorSpace: colorSpace)
        }
        guard let maxPixelSize = thumbnailMaxPixelSize(columns: cols, rows: rows) else {
            return TileGrid(cells: [], colorSpace: colorSpace)
        }
        let sampledCoverage = mask.flatMap { options in
            MaskSampler.sample(options, columns: cols, rows: rows)
        }
        let maskFallback = sampledCoverage == nil ? nil : mask?.fallback
        let maskGroundColor = sampledCoverage == nil ? nil : mask?.groundColor
        let maskUsesHardEdges = sampledCoverage == nil ? false : !(mask?.softEdges ?? true)

        let thumbnail: CGImage
        do {
            thumbnail = try ImageIOThumbnail.decode(image: image, maxPixelSize: maxPixelSize)
        } catch {
            return TileGrid(cells: [], colorSpace: colorSpace)
        }

        // Same sampling lattice as `prepareConversion` — an exact multiple of
        // the grid, so no source row or column goes unread (ASKI-65). The
        // palette is quantized from the same lattice raster the cells sample.
        guard
            let lattice = samplingLattice(
                thumbnail: thumbnail,
                columns: cols,
                rows: rows,
                colorSpace: colorSpace
            )
        else {
            return TileGrid(cells: [], colorSpace: colorSpace)
        }

        let resolvedPalette = palette.resolved(
            pixels: lattice.pixels,
            pixelWidth: lattice.pixelWidth,
            pixelHeight: lattice.pixelHeight,
            colorSpace: colorSpace
        )

        let context = ConversionContext(
            pixels: lattice.pixels,
            pixelWidth: lattice.pixelWidth,
            pixelHeight: lattice.pixelHeight,
            cellWidth: lattice.cellWidth,
            cellHeight: lattice.cellHeight,
            columns: cols,
            rows: rows,
            palette: resolvedPalette,
            options: resolvedOptions,
            colorSpace: colorSpace,
            // TileGrid has no public gamut-policy knob yet, so keep its
            // conversion behavior independent of the ASCII default flip.
            gamutMapping: .adaptiveL0
        )

        var output: [[TileCell]] = []
        output.reserveCapacity(rows)
        for row in 0..<rows {
            var line: [TileCell] = []
            line.reserveCapacity(cols)
            for column in 0..<cols {
                let coord = CellCoord(column: column, row: row)
                let stats = context.cellStats(at: coord)
                let coverage = sampledCoverage?[row * cols + column] ?? 1.0
                line.append(
                    TileCell(
                        displayColor: stats.displayColor,
                        alpha: stats.alpha,
                        brightness: stats.adjustedL,
                        coverage: coverage
                    ))
            }
            output.append(line)
        }

        return TileGrid(
            cells: output,
            colorSpace: colorSpace,
            maskFallback: maskFallback,
            maskGroundColor: maskGroundColor,
            maskUsesHardEdges: maskUsesHardEdges
        )
    }

    private func thumbnailMaxPixelSize(columns: Int, rows: Int) -> Int? {
        let side = max(columns, rows)
        let effectiveOversample = max(1, oversample)
        let result = side.multipliedReportingOverflow(by: effectiveOversample)
        guard !result.overflow, result.partialValue > 0 else {
            return nil
        }
        return result.partialValue
    }
}
