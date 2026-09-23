import CoreGraphics
import CoreImage

internal enum CoverageImageBuilder {
    static func makeASCII(grid: ASCIIGrid, extent: CGRect, useHardEdges: Bool) -> CIImage {
        guard grid.columns > 0, grid.rows > 0, extent.width > 0, extent.height > 0 else {
            return CIImage(color: .white).cropped(to: extent)
        }

        var bytes = [UInt8](repeating: 255, count: grid.columns * grid.rows)
        for (rowIndex, row) in grid.cells.enumerated() {
            for (columnIndex, cell) in row.enumerated() where columnIndex < grid.columns {
                let value = max(0, min(1, cell.coverage))
                bytes[rowIndex * grid.columns + columnIndex] = UInt8((value * 255).rounded())
            }
        }

        // CoreGraphics owns the pixel buffer (see the pixel-buffer rule in
        // MaskSampler.swift); the coverage bytes are copied row by row into it.
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard
            let context = CGContext(
                data: nil,
                width: grid.columns,
                height: grid.rows,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let destination = context.data
        else {
            return CIImage(color: .white).cropped(to: extent)
        }

        let destinationRowBytes = context.bytesPerRow
        bytes.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            for row in 0..<grid.rows {
                destination.advanced(by: row * destinationRowBytes)
                    .copyMemory(
                        from: base.advanced(by: row * grid.columns),
                        byteCount: grid.columns
                    )
            }
        }

        guard let cgImage = context.makeImage() else {
            return CIImage(color: .white).cropped(to: extent)
        }

        let source = CIImage(cgImage: cgImage)
        let sampled = useHardEdges ? source.samplingNearest() : source.samplingLinear()
        let scale = CGAffineTransform(
            scaleX: extent.width / CGFloat(grid.columns),
            y: extent.height / CGFloat(grid.rows)
        )
        return
            sampled
            .transformed(by: scale)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    static func makeTile(
        grid: TileGrid,
        mode: TileGridMode,
        shape: TileCellShape,
        scale: CGFloat,
        extent: CGRect,
        useHardEdges: Bool
    ) -> CIImage {
        // ASKI-34. `extent` is measured from a CIImage by the caller, and
        // CoreImage reports `CGRectInfinite` for generator and tiled filters,
        // so it can legitimately be unbounded — which would trap in the
        // `Int(ceil(...))` conversions below. The rule (see
        // `RenderPixelBounds.finiteExtent`) is to CLAMP an unbounded extent to
        // the finite reference rect this call site already knows, which here
        // is the tile grid's own extent: the mask genuinely exists and is
        // merely unbounded, and the grid extent is the region this builder was
        // going to paint anyway. Only a grid that has no extent of its own
        // leaves no reference, and only then does the builder degrade to the
        // ASKI-17-style empty image.
        guard
            let extent = RenderPixelBounds.finiteExtent(
                extent,
                clampedTo: tileGridExtent(grid: grid, shape: shape, scale: scale)
            )
        else {
            return CIImage(color: .white).cropped(to: .zero)
        }

        guard extent.width > 0, extent.height > 0, scale > 0, scale.isFinite else {
            return CIImage(color: .white).cropped(to: extent)
        }

        let width = Int(ceil(extent.width))
        let height = Int(ceil(extent.height))
        guard width > 0, height > 0 else {
            return CIImage(color: .white).cropped(to: extent)
        }

        // CoreGraphics owns the pixel buffer (see the pixel-buffer rule in
        // MaskSampler.swift). Every pixel is painted by the fill below, so the
        // context's initial contents are never observed.
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            return CIImage(color: .white).cropped(to: extent)
        }

        let startsMaskedOut: Bool
        if case .mosaic = mode.representation {
            startsMaskedOut = true
        } else {
            startsMaskedOut = false
        }
        context.setFillColor(gray: startsMaskedOut ? 0 : 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (rowIndex, row) in grid.cells.enumerated() {
            for (columnIndex, cell) in row.enumerated() {
                let value = CGFloat(max(0, min(1, cell.coverage)))
                context.setFillColor(gray: value, alpha: 1)
                let rect = cellBounds(
                    column: columnIndex,
                    row: rowIndex,
                    shape: shape,
                    scale: scale
                )
                if case .mosaic = mode.representation {
                    context.fill(rect)
                } else {
                    context.addPath(cellPath(shape: shape, in: rect, column: columnIndex))
                    context.fillPath()
                }
            }
        }

        guard let cgImage = context.makeImage() else {
            return CIImage(color: .white).cropped(to: extent)
        }
        let image = CIImage(cgImage: cgImage).cropped(to: extent)
        return useHardEdges ? image.samplingNearest() : image.samplingLinear()
    }

    /// The rect the tile grid occupies on its own, in the same geometry the
    /// tile renderer uses (`TileGrid+Rendering` walks the last cell of every
    /// row the same way). Used only as the ASKI-34 clamp target; a grid with
    /// no rows, or a scale that is not usable, yields `.zero`, which
    /// `RenderPixelBounds.finiteExtent` rejects as "no reference".
    private static func tileGridExtent(
        grid: TileGrid,
        shape: TileCellShape,
        scale: CGFloat
    ) -> CGRect {
        guard scale > 0, scale.isFinite else { return .zero }
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for (rowIndex, row) in grid.cells.enumerated() where !row.isEmpty {
            let bounds = cellBounds(
                column: row.count - 1,
                row: rowIndex,
                shape: shape,
                scale: scale
            )
            maxX = max(maxX, bounds.maxX)
            maxY = max(maxY, bounds.maxY)
        }
        return CGRect(x: 0, y: 0, width: maxX, height: maxY)
    }
}
