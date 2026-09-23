import CoreGraphics
import Foundation

public extension TileGrid {

    private struct RasterColorCache {
        private struct Key: Hashable {
            let red: UInt32
            let green: UInt32
            let blue: UInt32
            let alpha: UInt32
        }

        private var colors: [Key: CGColor] = [:]

        mutating func color(red: Float, green: Float, blue: Float, alpha: Float) -> CGColor {
            let alpha = max(0, min(1, alpha))
            let key = Key(
                red: red.bitPattern,
                green: green.bitPattern,
                blue: blue.bitPattern,
                alpha: alpha.bitPattern
            )
            if let color = colors[key] {
                return color
            }

            let color = CGColor(
                red: CGFloat(red),
                green: CGFloat(green),
                blue: CGFloat(blue),
                alpha: CGFloat(alpha)
            )
            colors[key] = color
            return color
        }
    }

    /// Render this grid to a `CGImage`. `mode` and `cellShape` choose the visual
    /// style without re-running the converter.
    func renderImage(
        mode: TileGridMode = .pixelArt,
        cellShape: TileCellShape = .square,
        scale: CGFloat = 1,
        backgroundColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    ) -> CGImage {
        guard scale > 0, scale.isFinite else { return Self.emptyImage() }
        guard !cells.isEmpty, columns > 0, rows > 0 else { return Self.emptyImage() }

        if effectiveMaskGroundColor(maskGroundColor) != nil {
            let composition = resolveComposition(.init(), backgroundColor: backgroundColor)
            return EffectsRenderEngine.renderTileGridSync(
                self,
                mode: mode,
                cellShape: cellShape,
                scale: scale,
                composition: composition,
                lighting: nil,
                effects: .init()
            )
        }

        if case .mosaic = mode.representation, maskContainsCoverageBelowOne(self) {
            let composition = resolveComposition(.init(), backgroundColor: backgroundColor)
            return EffectsRenderEngine.renderTileGridSync(
                self,
                mode: mode,
                cellShape: cellShape,
                scale: scale,
                composition: composition,
                lighting: nil,
                effects: .init()
            )
        }

        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for (rowIndex, row) in cells.enumerated() {
            guard !row.isEmpty else { continue }
            let lastColumn = row.count - 1
            let bounds = cellBounds(
                column: lastColumn,
                row: rowIndex,
                shape: cellShape,
                scale: scale
            )
            maxX = max(maxX, bounds.maxX)
            maxY = max(maxY, bounds.maxY)
        }

        guard
            let pixelWidth = RenderPixelBounds.pixelExtent(maxX),
            let pixelHeight = RenderPixelBounds.pixelExtent(maxY)
        else { return Self.emptyImage() }
        guard pixelWidth > 0, pixelHeight > 0 else { return Self.emptyImage() }

        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: cgColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return Self.emptyImage()
        }

        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        if case .mosaic(let grout, _, _) = mode.representation {
            context.setFillColor(grout)
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }

        if let fallback = maskFallback,
            !fallback.isTransparentFallback,
            maskContainsCoverageBelowOne(self)
        {
            drawTileFallbackOverlay(
                fallback,
                mode: mode,
                cellShape: cellShape,
                scale: scale,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                in: context
            )
        }

        drawCells(mode: mode, cellShape: cellShape, scale: scale, in: context)

        return context.makeImage() ?? Self.emptyImage()
    }

    private func drawTileFallbackOverlay(
        _ fallback: MaskFallback,
        mode: TileGridMode,
        cellShape: TileCellShape,
        scale: CGFloat,
        pixelWidth: Int,
        pixelHeight: Int,
        in context: CGContext
    ) {
        switch mode.representation {
        case .mosaic:
            return
        case .pixelArt, .brick:
            // Overlay paints before the tile loop. Brick studs are drawn later by
            // `renderCell`, so they intentionally sit on top of the fallback.
            drawTileFallbackOverlayForShapedCells(
                fallback,
                cellShape: cellShape,
                scale: scale,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                in: context
            )
        }
    }

    private func drawTileFallbackOverlayForShapedCells(
        _ fallback: MaskFallback,
        cellShape: TileCellShape,
        scale: CGFloat,
        pixelWidth: Int,
        pixelHeight: Int,
        in context: CGContext
    ) {
        for (rowIndex, row) in cells.enumerated() {
            for (columnIndex, cell) in row.enumerated() {
                let inverse = max(0, min(1, 1 - cell.coverage))
                guard inverse > 0 else { continue }
                let rect = cellBounds(column: columnIndex, row: rowIndex, shape: cellShape, scale: scale)
                let path = cellPath(shape: cellShape, in: rect, column: columnIndex)
                context.saveGState()
                context.addPath(path)
                context.clip()
                switch fallback {
                case .transparent:
                    break
                case .solid(let color):
                    context.setFillColor(color.copy(alpha: color.alpha * CGFloat(inverse)) ?? color)
                    context.fill(rect)
                case .originalImage(let image, let sizing):
                    context.setAlpha(CGFloat(inverse))
                    let drawRect = ASCIIGrid.fallbackImageRect(
                        image: image,
                        sizing: sizing,
                        canvas: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
                    )
                    context.saveGState()
                    context.translateBy(x: 0, y: drawRect.maxY + drawRect.minY)
                    context.scaleBy(x: 1, y: -1)
                    context.draw(image, in: drawRect)
                    context.restoreGState()
                case .character:
                    MaskLogger.warnOnceTileCharacterFallbackIgnored()
                }
                context.restoreGState()
            }
        }
    }

    private func renderCell(
        cell: TileCell,
        effectiveAlpha: Float,
        rect: CGRect,
        column: Int,
        shape: TileCellShape,
        mode: TileGridMode,
        scale: CGFloat,
        cache: inout MosaicPathCache,
        colorCache: inout RasterColorCache,
        in context: CGContext
    ) {
        let displayColor = colorCache.color(
            red: cell.displayColor.x,
            green: cell.displayColor.y,
            blue: cell.displayColor.z,
            alpha: effectiveAlpha
        )

        switch mode.representation {
        case .pixelArt:
            fillCell(shape: shape, rect: rect, column: column, color: displayColor, in: context)

        case .brick:
            fillCell(shape: shape, rect: rect, column: column, color: displayColor, in: context)

            let centroid = cellCentroid(shape: shape, in: rect, column: column)
            let studDiameter = min(rect.width, rect.height) * 0.6
            TileShading.drawStud(
                center: centroid,
                diameter: studDiameter,
                baseColor: displayColor,
                in: context,
                colorSpace: cgColorSpace
            )

        case .mosaic(_, let groutThickness, let cornerRadius):
            let cacheKey = MosaicPathCache.key(
                shape: shape,
                column: column,
                thickness: groutThickness,
                cornerRadius: cornerRadius
            )
            let unitPath = cache.unitPath(for: cacheKey)
            var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: scale, y: scale)
            let path = unitPath.copy(using: &transform) ?? unitPath
            context.addPath(path)
            context.setFillColor(displayColor)
            context.fillPath()
            TileShading.drawBevel(path: path, bounds: rect, in: context)
        }
    }

    private func fillCell(
        shape: TileCellShape,
        rect: CGRect,
        column: Int,
        color: CGColor,
        in context: CGContext
    ) {
        context.setFillColor(color)
        switch shape {
        case .square:
            context.fill(rect)
        case .circle, .hex, .triangle, .diamond:
            context.addPath(cellPath(shape: shape, in: rect, column: column))
            context.fillPath()
        }
    }

    private func drawCells(
        mode: TileGridMode,
        cellShape: TileCellShape,
        scale: CGFloat,
        coverageMode: CellCoverageMode = .multiplyCoverage,
        in context: CGContext
    ) {
        let appliesCoverageInRaster =
            switch mode.representation {
            case .pixelArt, .brick: true
            case .mosaic: false
            }
        var mosaicCache = MosaicPathCache()
        var colorCache = RasterColorCache()
        for (rowIndex, row) in cells.enumerated() {
            for (columnIndex, cell) in row.enumerated() {
                let effectiveAlpha =
                    switch coverageMode {
                    case .multiplyCoverage:
                        appliesCoverageInRaster ? cell.alpha * cell.coverage : cell.alpha
                    case .intrinsicAlpha:
                        cell.alpha
                    }
                guard effectiveAlpha > 0 else { continue }
                let rect = cellBounds(
                    column: columnIndex,
                    row: rowIndex,
                    shape: cellShape,
                    scale: scale
                )
                renderCell(
                    cell: cell,
                    effectiveAlpha: effectiveAlpha,
                    rect: rect,
                    column: columnIndex,
                    shape: cellShape,
                    mode: mode,
                    scale: scale,
                    cache: &mosaicCache,
                    colorCache: &colorCache,
                    in: context
                )
            }
        }
    }
}

internal extension TileGrid {
    func renderCellsForRaster(
        mode: TileGridMode,
        cellShape: TileCellShape,
        scale: CGFloat,
        coverageMode: CellCoverageMode = .multiplyCoverage,
        in context: CGContext
    ) {
        if case .mosaic(let grout, _, _) = mode.representation {
            context.setFillColor(grout)
            context.fill(
                CGRect(
                    x: 0,
                    y: 0,
                    width: CGFloat(context.width),
                    height: CGFloat(context.height)
                ))
        }

        drawCells(
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            coverageMode: coverageMode,
            in: context
        )
    }
}
