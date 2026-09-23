import CoreText
import CoreGraphics
import Foundation
import simd

/// A character set computed at runtime by rasterizing each glyph via Core Text.
/// Shape vectors are font-dependent — pass the exact font you'll render with.
public struct RasterizedCharacterSet: ASCIICharacterSet, GlyphBankProviding {
    internal let glyphBank: GlyphBank

    public var characters: [Character] { glyphBank.characters }
    public var brightnessValues: [Float] { glyphBank.brightnessValues }
    public var rawDensityValues: [Float] { glyphBank.rawDensityValues }
    public var shapeVectorLanes: [SIMD4<Float>] { glyphBank.shapeVectorLanes }

    /// - Parameters:
    ///   - characters: Glyphs to rasterize into the character set.
    ///   - font: The Core Text font used to rasterize each glyph.
    public init(
        characters: [Character],
        font: CTFont
    ) {
        precondition(!characters.isEmpty, "RasterizedCharacterSet requires at least one character")

        let rasterSize = GlyphBank.rasterSize
        let cellW = Self.cellWidth(font: font)
        let cellH = Self.cellHeight(font: font)
        var rawBrightness: [Float] = []
        var lanes: [SIMD4<Float>] = []
        for char in characters {
            let pixels = Self.rasterize(char, font: font, size: rasterSize)
            rawBrightness.append(
                Self.cellDensity(
                    pixels, canvasSize: rasterSize, cellWidth: cellW, cellHeight: cellH
                ))
            let desc = ShapeContext.histogram60(pixels, width: rasterSize, height: rasterSize)
            // Pack 60 floats into 15 SIMD4 lanes
            for i in stride(from: 0, to: 60, by: 4) {
                lanes.append(SIMD4<Float>(desc[i], desc[i + 1], desc[i + 2], desc[i + 3]))
            }
        }

        // Cross-character normalization. Densest glyph lands at exactly 1.0,
        // values span [0, 1] cleanly. Matches Harri (2024) and the 2011
        // tone-based convention; the raw cell-density numbers otherwise
        // occupy a narrow sub-interval (e.g. [0, ~0.5] for Courier) that
        // wastes dynamic range at the first-pass matching filter.
        let maxRaw = rawBrightness.max() ?? 1
        let brightness = maxRaw > 0 ? rawBrightness.map { $0 / maxRaw } : rawBrightness
        let transform = CTFontGetMatrix(font)
        var transformFingerprint: UInt64 = 0xcbf2_9ce4_8422_2325
        func mixTransformComponent(_ value: CGFloat) {
            transformFingerprint =
                (transformFingerprint ^ Double(value).bitPattern) &* 0x0000_0100_0000_01B3
        }
        mixTransformComponent(transform.a)
        mixTransformComponent(transform.b)
        mixTransformComponent(transform.c)
        mixTransformComponent(transform.d)
        mixTransformComponent(transform.tx)
        mixTransformComponent(transform.ty)
        let fontObservation = GlyphBank.FontObservation(
            postScriptName: CTFontCopyPostScriptName(font) as String,
            pointSize: Double(CTFontGetSize(font)),
            transformFingerprint: transformFingerprint
        )
        self.glyphBank = GlyphBank(
            characters: characters,
            brightnessValues: brightness,
            rawDensityValues: rawBrightness,
            shapeVectorLanes: lanes,
            provenance: .runtimeCoreText(
                GlyphBank.Rasterization(
                    densityCellWidth: min(cellW, rasterSize),
                    densityCellHeight: min(cellH, rasterSize),
                    font: fontObservation
                )
            )
        )
    }

    private static func rasterize(_ character: Character, font: CTFont, size: Int) -> [Float] {
        let cs = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        guard
            let ctx = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size, space: cs, bitmapInfo: bitmapInfo
            )
        else { return [Float](repeating: 0, count: size * size) }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let str = NSAttributedString(
            string: String(character),
            attributes: [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1),
            ] as [NSAttributedString.Key: Any]
        )
        let line = CTLineCreateWithAttributedString(str)
        let bounds = CTLineGetImageBounds(line, ctx)
        let x = (CGFloat(size) - bounds.width) / 2 - bounds.origin.x
        let y = (CGFloat(size) - bounds.height) / 2 - bounds.origin.y
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)

        guard let data = ctx.data else {
            return [Float](repeating: 0, count: size * size)
        }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return (0..<(size * size)).map { Float(bytes[$0]) / 255.0 }
    }

    /// Advance width of 'M' — a stable cell-width proxy for monospace fonts.
    /// For non-monospace fonts it's an approximation; RasterizedCharacterSet
    /// is intended for monospace use.
    private static func cellWidth(font: CTFont) -> Int {
        var glyph: CGGlyph = 0
        var ch: UniChar = 0x4D  // 'M'
        CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, [glyph], &advance, 1)
        return boundedCellMetric(advance.width)
    }

    private static func cellHeight(font: CTFont) -> Int {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        return boundedCellMetric(ascent + descent)
    }

    private static func boundedCellMetric(_ metric: CGFloat) -> Int {
        let rounded = Swift.max(1, Double(metric.rounded(.up)))
        // CTFont accepts non-finite and huge point sizes, then can report
        // non-representable metrics. Bound its external Double against Int.max
        // before conversion; an invalid metric degrades to a one-pixel cell.
        guard rounded.isFinite, rounded < Double(Int.max) else { return 1 }
        return Int(rounded)
    }

    /// Ink density computed over the font's character-cell rectangle,
    /// centered in the raster canvas. The cell rect (not the full canvas)
    /// is the area an image tile will occupy in the downstream pipeline,
    /// so this is what image tile brightness is comparable to.
    private static func cellDensity(
        _ pixels: [Float], canvasSize: Int, cellWidth: Int, cellHeight: Int
    ) -> Float {
        let w = min(cellWidth, canvasSize)
        let h = min(cellHeight, canvasSize)
        guard w > 0, h > 0 else { return 0 }
        let x0 = (canvasSize - w) / 2
        let y0 = (canvasSize - h) / 2
        var sum: Float = 0
        for y in y0..<(y0 + h) {
            for x in x0..<(x0 + w) {
                sum += pixels[y * canvasSize + x]
            }
        }
        return sum / Float(w * h)
    }

}
