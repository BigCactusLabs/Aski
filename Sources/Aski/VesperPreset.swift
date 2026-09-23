import CoreGraphics
import simd

/// The frozen canonical Vesper render preset (ASTSK-47).
///
/// This is the **single** share look the Vesper app renders — one recipe, not a
/// preset *system* (per the no-SDK-ceremony rule). It bundles the converter
/// recipe *and* the render parameters (font, ground, scale) in one place so the
/// app has a single drift-proof source of truth; `render(_:)` is the one entry
/// point it calls.
///
/// Every knob is a settled one-way-door choice, resolved on rendered evidence
/// (the `AskiPresetLab` A/B) and frontier research. The `///` line on each field
/// is its one-line rationale (AC#3). Adding this type is purely additive — it
/// touches no existing default, so all existing API stays byte-identical (AC#4).
public struct VesperPreset: Sendable {
    /// 76 columns reads best at 9:16 thumbnail scale (the 72–80 band; 60 is coarse, 96 muddies).
    public let columns: Int

    /// Bone figure ink (sRGB) — high-L, near-neutral; owns the mids and highlights of the duotone.
    public let ink: PaletteColor

    /// Oxblood ground (Display P3) — darkened so its OKLAB basin retreats to the shadows,
    /// making red the figure/ground field rather than a mid-tone-grabbing crimson.
    public let accent: PaletteColor

    /// +0.15 OKLAB-L contrast bump for gothic shadows; every KILLed research knob stays 0.
    public let contrast: Float

    /// Display P3 — the gothic red sits outside sRGB gamut on P3 phones.
    public let colorSpace: RenderColorSpace

    /// 2× coverage-sampling supersample — the shipping default; balances fidelity and cost.
    public let oversample: Int

    /// Bundled Courier Prime point size — a bundled font makes the byte-snapshot deterministic
    /// across devices (AC#2).
    public let fontSize: CGFloat

    /// @2x output density.
    public let scale: CGFloat

    /// Charcoal ground — never pure black, which would halate around bright glyphs on OLED.
    public let backgroundColor: CGColor

    /// The one frozen configuration. There is exactly one canonical preset.
    public static let canonical = VesperPreset(
        columns: 76,
        ink: PaletteColor(
            SIMD3<Float>(Float(0xE8) / 255, Float(0xE2) / 255, Float(0xD2) / 255),  // #E8E2D2 bone
            colorSpace: .sRGB),
        accent: PaletteColor(
            SIMD3<Float>(Float(0x5E) / 255, Float(0x1B) / 255, Float(0x18) / 255),  // #5E1B18 oxblood
            colorSpace: .displayP3),
        contrast: 0.15,
        colorSpace: .displayP3,
        oversample: 2,
        fontSize: 14,
        scale: 2,
        backgroundColor: CGColor(
            srgbRed: CGFloat(0x16) / 255, green: CGFloat(0x16) / 255, blue: CGFloat(0x16) / 255,  // #161616
            alpha: 1)
    )

    /// `fontSize` and `scale` are stored unvalidated (ASKI-35 classification:
    /// intentionally permissive, downstream bound named). Both reach the
    /// renderer only through `render(_:)` → `ASCIIGrid.renderImage(font:
    /// backgroundColor:scale:)`, which applies the ASKI-17 rule: `scale` must
    /// be finite and positive, and the product of columns, glyph size and scale
    /// is bounded by `RenderPixelBounds.pixelExtent`, so out-of-range values
    /// take the documented empty-image fallback instead of trapping. No second
    /// check belongs here.
    public init(
        columns: Int,
        ink: PaletteColor,
        accent: PaletteColor,
        contrast: Float,
        colorSpace: RenderColorSpace,
        oversample: Int,
        fontSize: CGFloat,
        scale: CGFloat,
        backgroundColor: CGColor
    ) {
        self.columns = columns
        self.ink = ink
        self.accent = accent
        self.contrast = contrast
        self.colorSpace = colorSpace
        self.oversample = oversample
        self.fontSize = fontSize
        self.scale = scale
        self.backgroundColor = backgroundColor
    }

    /// Bundled Courier Prime at the preset's point size.
    public var font: ASCIIFont { .courierPrime(size: fontSize) }

    /// The frozen converter recipe: `.blocks` bold duotone under `.logPolar` + `.wide`,
    /// a fixed bone→oxblood palette, and the gothic contrast bump.
    public func makeConverter() -> ASCIIConverter<StandardCharacterSet, BuiltInPalette> {
        ASCIIConverter(
            characterSet: .blocks,
            palette: BuiltInPalette(content: .fixed([ink, accent])),
            algorithm: .logPolar,
            tileShape: .wide,
            options: RenderingOptions(brightness: 0, contrast: contrast),
            colorSpace: colorSpace,
            oversample: oversample
        )
    }

    /// Convert then render `image` through the frozen recipe — the app's single entry point.
    public func render(_ image: CGImage) -> CGImage {
        makeConverter()
            .convert(image, columns: columns)
            .renderImage(
                font: font,
                backgroundColor: backgroundColor,
                scale: scale,
                preserveSourceAspect: true
            )
    }
}
