import Aski
import CoreGraphics
import CoreText
import Foundation

// MARK: - Typographic cell rasterizer (ASKI-32)

/// Rasterizes a single `Character` into a `width × height` grayscale luma buffer
/// in [0,1] (ink → 1, background → 0) using the renderer's **typographic**
/// convention: the glyph is positioned the way `ImageRenderer` draws it into a
/// cell — left edge at x = 0, baseline at `descent` above the cell bottom, font
/// point size derived from the cell height by the renderer's *default-tile*
/// rule (`glyphHeight = pointSize × 1.2`) — and braille codepoints route
/// through the same `BrailleRasterizer` dot geometry production uses instead of
/// a text face. The render happens at a supersampled resolution and is
/// area-resampled into the requested block (ASKI-32 AC#1), so the block sets
/// the information content without tying rasterizer hinting to the block size.
///
/// Scope, stated precisely: this models the **default-tile, Courier** branch of
/// `ImageRenderer.RenderGeometry.resolve`, which is the branch whose 1:2 cell
/// aspect the reference-recovery screen's resolved block has. It does NOT model
/// the shipped preset's variant — Courier Prime with `preserveSourceAspect:
/// true`, where `glyphHeight = pointSize × 0.6 × 2.2` — nor a caller-supplied
/// font. Claims built on this type are claims about the default-tile Courier
/// regime, not about every render the library can produce.
///
/// This is deliberately NOT `GlyphRaster.luma`, which bounds-centres the glyph
/// (`CTLineGetImageBounds`) exactly as the matcher's own
/// `RasterizedCharacterSet.rasterize` does. Bounds-centring erases position-only
/// distinctions (`▄` and `▀` become the same centred bar; single-dot braille
/// glyphs collapse), so a reference built with it cannot carry the positional
/// information the rendered output genuinely has. `GlyphRaster` stays untouched
/// so every archived screen reproduces; use this type when the reference must
/// look like what production *renders*, not like what the matcher *indexes*.
public enum GlyphCellRaster {

    /// The renderer's cell aspect: `glyphWidth = pointSize × 0.6`,
    /// `glyphHeight = pointSize × 1.2` for the default tile shape
    /// (`ImageRenderer.RenderGeometry.resolve`). The point size is derived from
    /// the raster height through the same constant.
    public static let widthRatio: CGFloat = 0.6
    public static let heightRatio: CGFloat = 1.2

    /// Rasterizes `character` into a `width × height` cell block.
    ///
    /// - High-resolution stage (ASKI-32 AC#1): the glyph is first rendered at
    ///   `supersample`× the requested block, then area-resampled INTO the
    ///   block, then the caller `LumaResample`s the block to the scoring
    ///   footprint. Rendering directly at block resolution would tie Core Text
    ///   hinting/antialiasing to the block size; the supersample stage sets the
    ///   source's information content by the block while keeping the
    ///   rasterization itself resolution-independent.
    /// - Font: "Courier", the family `BuildStandardVectors` rasterized the
    ///   bundled shape vectors from, sized so `pointSize × heightRatio` equals
    ///   the hi-res raster height — the inverse of the renderer's geometry rule.
    /// - Position: `textPosition = (0, descent)`, mirroring
    ///   `ImageRenderer.drawGlyphs` (left cell edge, shared row baseline).
    /// - Braille (U+2800–U+28FF): drawn by `BrailleRasterizer.draw` over the
    ///   full cell rect, as production does; no font is involved. Dispatch is on
    ///   the FIRST scalar, matching `ImageRenderer` (a braille scalar followed
    ///   by a combining scalar still takes the dot path there).
    /// - Parameter boundsCentred: when true, text glyphs are centred on their
    ///   `CTLine` image bounds (the *matcher's* rule) instead of drawn at the
    ///   typographic origin (the *renderer's* rule). Everything else — font,
    ///   point size, supersample, downsample — is identical, so two rasters that
    ///   differ only in this flag differ only in where the ink sits. Braille
    ///   ignores it: `BrailleRasterizer` covers the whole cell rect and has no
    ///   bounds-cropped form, which is what keeps the braille null control exact.
    public static func luma(
        character: Character, width: Int, height: Int, supersample: Int = 4,
        boundsCentred: Bool = false
    ) -> [Float] {
        let ss = max(1, supersample)
        let w = max(1, width) * ss
        let h = max(1, height) * ss
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

        if let scalar = character.unicodeScalars.first,
            (0x2800...0x28FF).contains(scalar.value)
        {
            BrailleRasterizer.draw(
                codepoint: scalar.value,
                foregroundColor: CGColor(gray: 1, alpha: 1),
                in: ctx,
                rect: CGRect(x: 0, y: 0, width: w, height: h)
            )
        } else {
            let pointSize = CGFloat(h) / heightRatio
            let font = CTFontCreateWithName("Courier" as CFString, pointSize, nil)
            let str = NSAttributedString(
                string: String(character),
                attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    kCTForegroundColorAttributeName as NSAttributedString.Key:
                        CGColor(gray: 1, alpha: 1),
                ]
            )
            let line = CTLineCreateWithAttributedString(str)
            if boundsCentred {
                // The matcher's centring rule (`RasterizedCharacterSet.rasterize`),
                // applied INSIDE this path so a caller comparing the two
                // placements changes the placement and nothing else. Centring
                // happens in the supersampled domain, so the offset lands on a
                // sub-output-pixel grid rather than snapping to whole cells.
                let bounds = CTLineGetImageBounds(line, ctx)
                ctx.textPosition = CGPoint(
                    x: (CGFloat(w) - bounds.width) / 2 - bounds.origin.x,
                    y: (CGFloat(h) - bounds.height) / 2 - bounds.origin.y)
            } else {
                ctx.textPosition = CGPoint(x: 0, y: CTFontGetDescent(font))
            }
            CTLineDraw(line, ctx)
        }

        guard let data = ctx.data else { return [Float](repeating: 0, count: w * h) }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let hiRes = (0..<(w * h)).map { Float(bytes[$0]) / 255.0 }
        if ss == 1 { return hiRes }
        return boxDownsample(hiRes, width: w, height: h, factor: ss)
    }

    /// Exact integer-factor area average: each destination pixel is the mean of
    /// its `factor × factor` source tile. This is the "anisotropically resampled
    /// INTO the resolved cell block" stage of ASKI-32 AC#1 — area-weighted per
    /// axis, matching `LumaResample`'s downscale behaviour at the integer-factor
    /// special case, with no cross-target dependency.
    static func boxDownsample(_ src: [Float], width: Int, height: Int, factor: Int) -> [Float] {
        let dw = width / factor
        let dh = height / factor
        let norm = Float(factor * factor)
        var dst = [Float](repeating: 0, count: dw * dh)
        for dy in 0..<dh {
            for dx in 0..<dw {
                var sum: Float = 0
                for sy in (dy * factor)..<((dy + 1) * factor) {
                    let rowBase = sy * width + dx * factor
                    for sx in 0..<factor {
                        sum += src[rowBase + sx]
                    }
                }
                dst[dy * dw + dx] = sum / norm
            }
        }
        return dst
    }
}
