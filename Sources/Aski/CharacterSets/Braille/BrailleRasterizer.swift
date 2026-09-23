import CoreGraphics
import Foundation

package enum BrailleRasterizer {

    /// Bit index → (column, row). Row 0 = top.
    /// Per the Unicode Braille standard:
    ///   left column  = bits {0, 1, 2, 6}
    ///   right column = bits {3, 4, 5, 7}
    private static let dotPositions: [(column: Int, row: Int)] = [
        (0, 0),  // bit 0
        (0, 1),  // bit 1
        (0, 2),  // bit 2
        (1, 0),  // bit 3
        (1, 1),  // bit 4
        (1, 2),  // bit 5
        (0, 3),  // bit 6 (8-dot extension)
        (1, 3),  // bit 7 (8-dot extension)
    ]

    /// Returns a `size × size` grayscale raster (row-major, origin top-left).
    package static func rasterize(codepoint: UInt32, size: Int) -> [Float] {
        let cs = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        guard
            let ctx = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size,
                space: cs,
                bitmapInfo: bitmapInfo
            )
        else {
            return [Float](repeating: 0, count: size * size)
        }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(gray: 1, alpha: 1)
        drawRaw(codepoint: codepoint, in: ctx, rect: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = ctx.data else {
            return [Float](repeating: 0, count: size * size)
        }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var raster = [Float](repeating: 0, count: size * size)
        for i in 0..<(size * size) {
            raster[i] = Float(bytes[i]) / 255
        }
        return raster
    }

    package static func draw(
        codepoint: UInt32,
        foregroundColor: CGColor,
        in ctx: CGContext,
        rect: CGRect
    ) {
        ctx.saveGState()
        ctx.setFillColor(foregroundColor)
        drawRaw(codepoint: codepoint, in: ctx, rect: rect)
        ctx.restoreGState()
    }

    private static func drawRaw(codepoint: UInt32, in ctx: CGContext, rect: CGRect) {
        let cellWidth = rect.width / 2
        let cellHeight = rect.height / 4
        let dotDiameter = min(cellWidth, cellHeight) * 0.7
        let insetX = (cellWidth - dotDiameter) / 2
        let insetY = (cellHeight - dotDiameter) / 2

        for bit in 0..<8 {
            let mask = UInt32(1) << bit
            guard codepoint & mask != 0 else { continue }
            let pos = dotPositions[bit]
            let cgRow = 3 - pos.row
            let originX = rect.origin.x + CGFloat(pos.column) * cellWidth + insetX
            let originY = rect.origin.y + CGFloat(cgRow) * cellHeight + insetY
            ctx.fillEllipse(
                in: CGRect(
                    x: originX, y: originY,
                    width: dotDiameter, height: dotDiameter))
        }
    }
}
