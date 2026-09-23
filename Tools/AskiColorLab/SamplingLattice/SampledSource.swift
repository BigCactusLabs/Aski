import Foundation

@_spi(AskiResearch) import Aski

/// Maps a converter grid cell back to the **native** source pixels the converter
/// actually read for it.
///
/// Since ASKI-65 the converter draws its decoded thumbnail into a sampling
/// lattice of exactly `columns*cellWidth × rows*cellHeight`, so the sampled
/// raster is an exact multiple of the grid, covers the whole source, and
/// `SamplingGeometry.droppedX`/`droppedY` are zero. Cell `(row, col)` therefore
/// covers native rows `[row*H/rows, (row+1)*H/rows)` and columns
/// `[col*W/columns, (col+1)*W/columns)` — the same partition
/// `ResidualFixture.lumaBlock` takes over the whole native image.
///
/// This accessor still exists, and instruments should still prefer it, because
/// the agreement is a property of the converter's geometry rather than an
/// assumption an instrument may make on its own. It was introduced when the two
/// partitions disagreed: the pitch was floored against the thumbnail's own size
/// and the bottom/right remainder went unread — at the shipping arm (3072px
/// square source, `columns: 80`, `oversample: 2`) 16 of 160 thumbnail rows, 10%
/// of image height, so every glyph under the equal partition was scored against
/// a source patch displaced downward by up to four cell heights, and the
/// displacement differed per `oversample` arm. Deriving the mapping from
/// `SamplingGeometry` means an instrument tracks whatever the converter does
/// rather than re-deriving it, and the `droppedX`/`droppedY` assertions in
/// `AskiColorLabSamplingLatticeTests` fail loudly if that stops being true.
///
/// The mapping is floor-rounded on both edges, matching the converter's own
/// integer cell pitch, and the returned block is at native resolution so the
/// no-downscale invariant the residual instruments rely on still holds.
enum SampledSource {

    /// The native luma block for cell `(cellRow, cellCol)` under `geometry`, or
    /// `nil` when the cell is out of range or degenerates to under one pixel.
    static func lumaBlock(
        _ fixture: ResidualFixture,
        cellRow: Int,
        cellCol: Int,
        geometry: SamplingGeometry
    ) -> (luma: [Float], width: Int, height: Int)? {
        guard
            geometry.thumbnailWidth > 0, geometry.thumbnailHeight > 0,
            geometry.cellWidth > 0, geometry.cellHeight > 0,
            cellRow >= 0, cellRow < geometry.rows,
            cellCol >= 0, cellCol < geometry.columns,
            fixture.width > 0, fixture.height > 0
        else { return nil }

        // Lattice rect the converter reads for this cell, scaled into native
        // pixels. `(cellCol + 1) * cellWidth <= thumbnailWidth` by construction
        // (with equality on the last cell), so the scaled edges never leave the
        // fixture.
        let x0 = (cellCol * geometry.cellWidth * fixture.width) / geometry.thumbnailWidth
        let x1 = ((cellCol + 1) * geometry.cellWidth * fixture.width) / geometry.thumbnailWidth
        let y0 = (cellRow * geometry.cellHeight * fixture.height) / geometry.thumbnailHeight
        let y1 = ((cellRow + 1) * geometry.cellHeight * fixture.height) / geometry.thumbnailHeight

        let width = min(x1, fixture.width) - x0
        let height = min(y1, fixture.height) - y0
        guard width > 0, height > 0, x0 >= 0, y0 >= 0 else { return nil }

        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let sourceRow = (y0 + y) * fixture.width + x0
            for x in 0..<width {
                out[y * width + x] = fixture.luma[sourceRow + x]
            }
        }
        return (out, width, height)
    }
}
