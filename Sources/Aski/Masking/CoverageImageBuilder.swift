import CoreGraphics
import CoreImage

/// Builds the Core Image mask that `MaskCompositor.blendWithMask` reads.
///
/// ASKI-101: coverage is a linear weight, the fraction of the active branch in
/// the result, so a cell with coverage `c` mixes `c` of the active branch with
/// `1 - c` of the inactive one. This is the alpha rule the Core Graphics
/// overlay paths and the cell rasters (`alpha * coverage`) already follow, and
/// the one CSS Masking Level 1 gives for mask values ("Mask processing": the
/// mask value multiplies the element's alpha). The coverage bytes are data, not
/// color, so the image is created without color management. A Device Gray
/// image that Core Image color-manages is read through the sRGB transfer in a
/// linear working space, which turned coverage 0.5 into a weight of about 0.216,
/// and made `renderCIImage` weights depend on the consumer's working space.
internal enum CoverageImageBuilder {
    /// The coverage bytes as an image Core Image does not color-manage, so every
    /// working space reads the stored value as the blend weight.
    static func coverageImage(_ cgImage: CGImage) -> CIImage {
        CIImage(cgImage: cgImage, options: [.colorSpace: NSNull()])
    }

    static func makeASCII(grid: ASCIIGrid, extent: CGRect, useHardEdges: Bool) -> CIImage {
        guard grid.columns > 0, grid.rows > 0, extent.width > 0, extent.height > 0 else {
            return CIImage(color: .white).cropped(to: extent)
        }

        var bytes = [UInt8](repeating: 255, count: grid.columns * grid.rows)
        for (rowIndex, row) in grid.cells.enumerated() {
            for (columnIndex, cell) in row.enumerated() {
                let value = max(0, min(1, cell.coverage))
                bytes[rowIndex * grid.columns + columnIndex] = UInt8((value * 255).rounded())
            }
        }

        guard let source = makeASCIIByteImage(bytes, columns: grid.columns, rows: grid.rows) else {
            return CIImage(color: .white).cropped(to: extent)
        }
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

    /// Hard presence gates mask composition at the glyph boundaries, even when
    /// the bitmap dimensions were rounded up from the grid's nominal size.
    static func makeASCIIPresence(grid: ASCIIGrid, cellSize: CGSize, extent: CGRect) -> CIImage? {
        guard grid.cells.contains(where: { $0.count < grid.columns }) else { return nil }

        var bytes = [UInt8](repeating: 0, count: grid.columns * grid.rows)
        for (rowIndex, row) in grid.cells.enumerated() {
            for columnIndex in row.indices {
                bytes[rowIndex * grid.columns + columnIndex] = 255
            }
        }

        return makeASCIIByteImage(bytes, columns: grid.columns, rows: grid.rows)?
            .samplingNearest()
            .clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: cellSize.width, y: cellSize.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    private static func makeASCIIByteImage(_ bytes: [UInt8], columns: Int, rows: Int) -> CIImage? {
        // CoreGraphics owns the pixel buffer (see the pixel-buffer rule in
        // MaskSampler.swift); the bytes are copied row by row into it.
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard
            let context = CGContext(
                data: nil,
                width: columns,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let destination = context.data
        else {
            return nil
        }

        let destinationRowBytes = context.bytesPerRow
        bytes.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            for row in 0..<rows {
                destination.advanced(by: row * destinationRowBytes)
                    .copyMemory(
                        from: base.advanced(by: row * columns),
                        byteCount: columns
                    )
            }
        }

        return context.makeImage().map(coverageImage)
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
        let image = coverageImage(cgImage).cropped(to: extent)
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
