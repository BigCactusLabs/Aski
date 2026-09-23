import CoreGraphics
import Testing

@_spi(AskiResearch) @testable import Aski

/// ASKI-60 Phase A. The shape-query polarity knob exists so the disagreement
/// between production's shape term (`1 − luma`) and its tone pre-filter /
/// renderer (ink-high) can be measured instead of assumed. Nothing here decides
/// the verdict — these tests only pin the two properties the measurement needs:
/// the default is byte-identical to the shipped behavior, and `.direct` is a
/// real treatment rather than a no-op.
@Suite struct ShapeQueryPolarityTests {

    private static func converter(
        _ polarity: ShapeQueryPolarity
    ) -> ASCIIConverter<StandardCharacterSet, BuiltInPalette> {
        var options = RenderingOptions.default
        options.shapeQueryPolarity = polarity
        return ASCIIConverter(
            characterSet: .blocks,
            palette: .monochrome,
            options: options,
            colorSpace: .sRGB,
            oversample: 2
        )
    }

    /// Bright ink on a dark ground — the polarity-sensitive case by construction.
    /// A left-lit vertical bar on near-black: under `.inverted` the descriptor
    /// mass sits on the dark surround, under `.direct` on the bar itself.
    private static func brightInkOnDarkGround(width: Int, height: Int) -> CGImage {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let inBar = x % 16 < 5 && y % 24 >= 6
                let value: UInt8 = inBar ? 235 : 12
                let offset = (y * width + x) * 4
                buffer[offset] = value
                buffer[offset + 1] = value
                buffer[offset + 2] = value
                buffer[offset + 3] = 255
            }
        }
        let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    @Test func defaultIsInverted() {
        #expect(RenderingOptions().shapeQueryPolarity == .inverted)
        #expect(RenderingOptions.default.shapeQueryPolarity == .inverted)
        #expect(
            ResolvedRenderingOptions(RenderingOptions()).shapeQueryPolarity == .inverted)
    }

    /// The knob's byte-identity contract: leaving it unset must produce exactly
    /// the grid `.inverted` produces, cell for cell, bit for bit. The committed
    /// goldens cover the unset path; this covers the equivalence.
    @Test func unsetDefaultMatchesExplicitInvertedCellForCell() {
        let image = Self.brightInkOnDarkGround(width: 96, height: 96)
        let unset = ASCIIConverter(
            characterSet: StandardCharacterSet.blocks,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB,
            oversample: 2
        ).convert(image, columns: 24)
        let explicit = Self.converter(.inverted).convert(image, columns: 24)

        #expect(unset.rows == explicit.rows)
        #expect(unset.columns == explicit.columns)
        for (lhs, rhs) in zip(unset.cells.flatMap { $0 }, explicit.cells.flatMap { $0 }) {
            #expect(lhs.character == rhs.character)
            #expect(lhs.displayColor.x.bitPattern == rhs.displayColor.x.bitPattern)
            #expect(lhs.displayColor.y.bitPattern == rhs.displayColor.y.bitPattern)
            #expect(lhs.displayColor.z.bitPattern == rhs.displayColor.z.bitPattern)
            #expect(lhs.alpha.bitPattern == rhs.alpha.bitPattern)
            #expect(lhs.brightness.bitPattern == rhs.brightness.bitPattern)
            #expect(lhs.coverage.bitPattern == rhs.coverage.bitPattern)
        }
    }

    /// `.direct` must actually reach the picks. If this ever passes trivially the
    /// knob has been unplumbed from some sub-term and the Phase B measurement is
    /// measuring nothing.
    @Test func directChangesAtLeastOnePickOnBrightInkOnDarkGround() {
        let image = Self.brightInkOnDarkGround(width: 96, height: 96)
        let inverted = Self.converter(.inverted).convert(image, columns: 24)
        let direct = Self.converter(.direct).convert(image, columns: 24)

        #expect(inverted.rows == direct.rows)
        #expect(inverted.columns == direct.columns)
        let invertedGlyphs = inverted.cells.flatMap { $0 }.map(\.character)
        let directGlyphs = direct.cells.flatMap { $0 }.map(\.character)
        #expect(invertedGlyphs != directGlyphs)
    }

    /// Display color is a tone/palette product and never a shape product, so the
    /// polarity must move glyphs only. A color delta would mean the knob leaked
    /// out of the shape query.
    @Test func directLeavesDisplayColorUntouched() {
        let image = Self.brightInkOnDarkGround(width: 96, height: 96)
        let inverted = Self.converter(.inverted).convert(image, columns: 24)
        let direct = Self.converter(.direct).convert(image, columns: 24)

        for (lhs, rhs) in zip(inverted.cells.flatMap { $0 }, direct.cells.flatMap { $0 }) {
            #expect(lhs.displayColor.x.bitPattern == rhs.displayColor.x.bitPattern)
            #expect(lhs.displayColor.y.bitPattern == rhs.displayColor.y.bitPattern)
            #expect(lhs.displayColor.z.bitPattern == rhs.displayColor.z.bitPattern)
            #expect(lhs.brightness.bitPattern == rhs.brightness.bitPattern)
        }
    }
}
