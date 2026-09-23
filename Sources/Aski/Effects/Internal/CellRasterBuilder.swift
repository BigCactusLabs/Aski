import CoreGraphics
import CoreImage
import CoreText
import Foundation

internal struct CellRaster: Sendable {
    let image: CIImage
    let pixelWidth: Int
    let pixelHeight: Int
}

internal enum CellCoverageMode: Sendable {
    case multiplyCoverage
    case intrinsicAlpha
}

internal enum CellRasterBuilder {
    static func makeASCIIRaster(
        grid: ASCIIGrid,
        font: ASCIIFont,
        scale: CGFloat,
        coverageMode: CellCoverageMode = .multiplyCoverage
    ) -> CellRaster {
        guard scale > 0, scale.isFinite else {
            return emptyRaster()
        }

        let glyphWidth = font.pointSize * 0.6
        let glyphHeight = font.pointSize * 1.2
        guard
            let pixelWidth = RenderPixelBounds.pixelExtent(CGFloat(grid.columns) * glyphWidth * scale),
            let pixelHeight = RenderPixelBounds.pixelExtent(CGFloat(grid.rows) * glyphHeight * scale)
        else {
            return emptyRaster()
        }
        guard pixelWidth > 0, pixelHeight > 0 else {
            return emptyRaster()
        }

        let cgColorSpace = grid.composition.cgColorSpace(for: grid.colorSpace)

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
            return emptyRaster()
        }

        context.scaleBy(x: scale, y: scale)
        context.clear(
            CGRect(
                x: 0,
                y: 0,
                width: CGFloat(pixelWidth) / scale,
                height: CGFloat(pixelHeight) / scale
            ))
        context.textMatrix = .identity

        let fontAttribute = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorAttribute = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let baselineOffset = CTFontGetDescent(font.ctFont)

        for (rowIndex, row) in grid.cells.enumerated() {
            let y = CGFloat(grid.rows - rowIndex - 1) * glyphHeight + baselineOffset
            for (columnIndex, cell) in row.enumerated() {
                let rawAlpha =
                    switch coverageMode {
                    case .multiplyCoverage: cell.alpha * cell.coverage
                    case .intrinsicAlpha: cell.alpha
                    }
                let effectiveAlpha = max(0, min(1, rawAlpha))
                guard effectiveAlpha > 0 else { continue }
                let foregroundColor = CGColor(
                    red: CGFloat(cell.displayColor.x),
                    green: CGFloat(cell.displayColor.y),
                    blue: CGFloat(cell.displayColor.z),
                    alpha: CGFloat(effectiveAlpha)
                )

                let codepoint = cell.character.unicodeScalars.first?.value ?? 0
                if (0x2800...0x28FF).contains(codepoint) {
                    let cellRect = CGRect(
                        x: CGFloat(columnIndex) * glyphWidth,
                        y: CGFloat(grid.rows - rowIndex - 1) * glyphHeight,
                        width: glyphWidth,
                        height: glyphHeight
                    )
                    BrailleRasterizer.draw(
                        codepoint: codepoint,
                        foregroundColor: foregroundColor,
                        in: context,
                        rect: cellRect
                    )
                } else {
                    let attributed = NSAttributedString(
                        string: String(cell.character),
                        attributes: [
                            fontAttribute: font.ctFont,
                            colorAttribute: foregroundColor,
                        ]
                    )
                    let line = CTLineCreateWithAttributedString(attributed)
                    context.textPosition = CGPoint(x: CGFloat(columnIndex) * glyphWidth, y: y)
                    CTLineDraw(line, context)
                }
            }
        }

        guard let cgImage = context.makeImage() else {
            return emptyRaster()
        }
        return CellRaster(image: CIImage(cgImage: cgImage), pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    private static func emptyRaster() -> CellRaster {
        CellRaster(image: CIImage(color: .clear).cropped(to: .zero), pixelWidth: 0, pixelHeight: 0)
    }
}

extension CellRasterBuilder {
    static func makeTileRaster(
        grid: TileGrid,
        mode: TileGridMode,
        cellShape: TileCellShape,
        scale: CGFloat,
        coverageMode: CellCoverageMode = .multiplyCoverage
    ) -> CellRaster {
        guard scale > 0, scale.isFinite, !grid.cells.isEmpty, grid.columns > 0, grid.rows > 0 else {
            return emptyRaster()
        }

        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for (rowIndex, row) in grid.cells.enumerated() {
            guard !row.isEmpty else { continue }
            let bounds = cellBounds(
                column: row.count - 1,
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
        else {
            return emptyRaster()
        }
        guard pixelWidth > 0, pixelHeight > 0 else {
            return emptyRaster()
        }

        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: grid.cgColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return emptyRaster()
        }

        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: 1, y: -1)
        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        grid.renderCellsForRaster(
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            coverageMode: coverageMode,
            in: context
        )

        guard let cgImage = context.makeImage() else {
            return emptyRaster()
        }
        return CellRaster(image: CIImage(cgImage: cgImage), pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }
}
