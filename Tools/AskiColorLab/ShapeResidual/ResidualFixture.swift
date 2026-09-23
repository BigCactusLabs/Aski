import CoreGraphics
import Foundation

// MARK: - Shared per-fixture value + pool labels (ASTSK-31 Phase 5)

/// Which population a fixture contributes to when the verdict rule reads pooled
/// ρ. The synthetic pool is the procedural battery; `natural` is the NASA photo
/// corpus; `lineArt` is the procedural glyph sheet (real-glyph content, kept off
/// the natural pool and read on the line-art axis instead). The raw value is the
/// label used in the Spearman table and `spearman_summary.csv`.
public enum FixturePool: String, Sendable, CaseIterable {
    case synthetic
    case natural
    case lineArt = "line-art"
}

/// One member of the shape-residual battery: a deterministic grayscale image plus
/// its native luma and a per-cell source-block accessor. The instrument reads two
/// things from it — `image` (fed to the converter for the residual) and `luma`
/// (the oracle's source pixels). Both are built from the SAME gray bytes so the
/// residual and the oracle stay pixel-aligned. Sources: `StructuredFixture`
/// (synthetic), `GlyphSheetFixture` (line-art), `RealFixture` (natural).
public struct ResidualFixture: Sendable {
    /// Stable identifier (also the `fixture_id` CSV column value).
    public let id: String
    public let width: Int
    public let height: Int
    public let image: CGImage
    /// Native grayscale luma in [0,1], row-major, `width*height`.
    public let luma: [Float]
    /// The pool this fixture's cells are pooled into for the verdict rule.
    public let pool: FixturePool

    /// Extracts the source-pixel luma block covering grid cell `(cellRow,
    /// cellCol)` by partitioning the native pixel grid into `rows*cols` equal
    /// (integer-floor) blocks. Pure function of the fixture's own pixels — it
    /// never consults the residual.
    public func lumaBlock(cellRow: Int, cellCol: Int, rows: Int, cols: Int) -> (
        luma: [Float], width: Int, height: Int
    ) {
        let x0 = (cellCol * width) / cols
        let x1 = ((cellCol + 1) * width) / cols
        let y0 = (cellRow * height) / rows
        let y1 = ((cellRow + 1) * height) / rows
        let w = max(1, x1 - x0)
        let h = max(1, y1 - y0)
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                out[y * w + x] = luma[(y0 + y) * width + (x0 + x)]
            }
        }
        return (out, w, h)
    }

    /// Builds a fixture from a row-major `width*height` gray byte buffer (0...255).
    /// The CGImage is an sRGB RGBA image with the gray byte replicated across RGB
    /// (the exact construction `StructuredFixture` used), and `luma` is `byte/255`
    /// — so every fixture source (synthetic/line-art/natural) goes through one
    /// path and `image`↔`luma` are consistent by construction.
    static func fromGrayBytes(
        id: String, width: Int, height: Int, pool: FixturePool, gray: [UInt8]
    ) -> ResidualFixture {
        precondition(gray.count == width * height, "gray buffer must be width*height")
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var luma = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let v = gray[i]
            let o = i * 4
            rgba[o + 0] = v
            rgba[o + 1] = v
            rgba[o + 2] = v
            rgba[o + 3] = 255
            luma[i] = Float(v) / 255.0
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let image = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return ResidualFixture(id: id, width: width, height: height, image: image, luma: luma, pool: pool)
    }

    /// Creates the native-size 8-bit DeviceGray bitmap context (no alpha,
    /// `bytesPerRow == width`) that both the decoded (`RealFixture`) and procedural
    /// (`GlyphSheetFixture`) loaders rasterize into. Returns nil if CoreGraphics
    /// refuses the allocation; the caller decides whether that throws or falls back.
    static func makeGrayContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
    }

    /// Copies a gray context's pixels into a tight row-major `width*height` buffer,
    /// honoring `bytesPerRow` (CoreGraphics may pad each row past `width`). Returns
    /// nil if the context exposes no backing data. Shared so both loaders use one
    /// tested path for the easy-to-forget row-padding stride.
    static func grayBytes(from ctx: CGContext, width: Int, height: Int) -> [UInt8]? {
        guard let data = ctx.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = ctx.bytesPerRow  // may exceed width if CG padded the rows
        var gray = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                gray[y * width + x] = bytes[y * bytesPerRow + x]
            }
        }
        return gray
    }
}
