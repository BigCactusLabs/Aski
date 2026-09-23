import CoreGraphics
import CoreText
import Foundation

// MARK: - Independent glyph rasterizer

/// Rasterizes a single `Character` to a `width × height` grayscale luma buffer in
/// [0,1] (ink → 1, background → 0), via Core Text. This mirrors the canonical
/// `RasterizedCharacterSet.rasterize`. **It is a pure function of the glyph and
/// the requested cell size — it does not read the residual, the shape distance,
/// or any 60D vector**, which is what keeps the SSIM oracle independent.
public enum GlyphRaster {
    /// The point size `BuildStandardVectors` rasterizes the shipped `.bin` shape
    /// vectors at, into a 64×64 canvas (`BuildStandardVectors.swift:55`, with
    /// `rasterSize = 64`). Bounds-centring re-centres ink but does NOT rescale it,
    /// so a caller that wants a raster comparable to a shipped candidate must pass
    /// this rather than let the point size default to the canvas height — at a
    /// 64-px canvas the default is 64pt, twice production's, which fills far more
    /// of the canvas and moves both the ink density and the log-polar radial
    /// distribution.
    public static let productionShapeVectorPointSize: CGFloat = 32

    /// - Parameter pointSize: Courier point size. Defaults to the raster height,
    ///   which is what every pre-existing caller used; pass
    ///   ``productionShapeVectorPointSize`` to match the shipped candidate vectors.
    public static func luma(
        character: Character, width: Int, height: Int, pointSize: CGFloat? = nil
    ) -> [Float] {
        let w = max(1, width)
        let h = max(1, height)
        let cs = CGColorSpaceCreateDeviceGray()
        guard
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            return [Float](repeating: 0, count: w * h)
        }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // "Courier" is the family BuildStandardVectors rasterized the bundled
        // `.standard` shape vectors from, so the glyph family matches what the
        // matcher selected. Sized to the cell so SSIM compares like-for-like.
        let font = CTFontCreateWithName("Courier" as CFString, pointSize ?? CGFloat(h), nil)
        let str = NSAttributedString(
            string: String(character),
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(str)
        let bounds = CTLineGetImageBounds(line, ctx)
        let x = (CGFloat(w) - bounds.width) / 2 - bounds.origin.x
        let y = (CGFloat(h) - bounds.height) / 2 - bounds.origin.y
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)

        guard let data = ctx.data else { return [Float](repeating: 0, count: w * h) }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return (0..<(w * h)).map { Float(bytes[$0]) / 255.0 }
    }
}
