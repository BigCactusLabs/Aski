import CoreGraphics
import CoreText
import Foundation

// MARK: - Procedural line-art fixture (ASTSK-31 Phase 5)

/// A deterministic multi-size text sheet rendered from the bundled "Courier"
/// face via Core Text — the SAME family `GlyphRaster` rasterizes the matcher's
/// chosen glyph from. This circularity (rendered with the font the matcher
/// selects against) is **intentional**: glyphSheet is the best-case line-art
/// regime, and it is graded on the line-art axis, not pooled with the natural
/// photographs. Black ink on a white page so the fixture carries deep ink, bright
/// flat margins (exercising the flat-vs-flat oracle branch), and oriented stroke
/// structure. Pure function of `side` — no RNG.
enum GlyphSheetFixture {
    /// The deterministic line lay-out: text, font size, and origin all as
    /// fractions of the native side, so the sheet scales self-similarly. Core
    /// Text's origin is bottom-left, so larger `yFrac` is higher on the page.
    private static let lines: [(text: String, sizeFrac: Double, xFrac: Double, yFrac: Double)] = [
        ("ASKI ASCII ART LAB", 0.060, 0.07, 0.82),
        ("the quick brown fox", 0.050, 0.07, 0.66),
        ("jumps over 1234567890", 0.045, 0.07, 0.52),
        ("!@#$%^&*()_+-=[]{};:", 0.055, 0.07, 0.36),
        ("glyph sheet fixture", 0.070, 0.07, 0.18),
    ]

    static func make(side: Int = 2048) -> ResidualFixture {
        let n = max(1, side)
        // Degenerate fallback: an all-white page (still a valid fixture).
        func whitePage() -> ResidualFixture {
            ResidualFixture.fromGrayBytes(
                id: "glyphSheet", width: n, height: n, pool: .lineArt,
                gray: [UInt8](repeating: 255, count: n * n))
        }
        guard let ctx = ResidualFixture.makeGrayContext(width: n, height: n) else {
            return whitePage()
        }
        // White page, black ink.
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        for line in lines {
            let font = CTFontCreateWithName("Courier" as CFString, CGFloat(Double(n) * line.sizeFrac), nil)
            let attributed = NSAttributedString(
                string: line.text,
                attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1),
                ]
            )
            let ctLine = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(
                x: CGFloat(Double(n) * line.xFrac), y: CGFloat(Double(n) * line.yFrac))
            CTLineDraw(ctLine, ctx)
        }

        guard let gray = ResidualFixture.grayBytes(from: ctx, width: n, height: n) else {
            return whitePage()
        }
        return ResidualFixture.fromGrayBytes(id: "glyphSheet", width: n, height: n, pool: .lineArt, gray: gray)
    }
}
