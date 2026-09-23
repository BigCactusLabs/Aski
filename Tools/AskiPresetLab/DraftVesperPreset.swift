import Aski
import AskiToolSupport
import CoreGraphics
import simd

/// Minimal fixed/duotone palette for the draft Vesper preset. A lab-local
/// `ASCIIPalette` so the tool can declare `PaletteContent.fixed(...)` colors
/// directly — `BuiltInPalette`'s memberwise init is not public.
public struct VesperPalette: ASCIIPalette {
    public let content: PaletteContent
    public init(content: PaletteContent) { self.content = content }
}

/// `#RRGGBB` → transfer-encoded RGB components in `0...1`.
public enum HexColor {
    public static func components(_ hex: String) -> SIMD3<Float>? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return SIMD3<Float>(
            Float((v >> 16) & 0xFF) / 255,
            Float((v >> 8) & 0xFF) / 255,
            Float(v & 0xFF) / 255
        )
    }
}

/// The locked-now knobs of the ASTSK-47 canonical Vesper render preset — the
/// one-way-door choices the frontier sweep already settled — holding the two
/// UNDECIDED knobs (charset, columns) open for the A/B to resolve.
///
/// Locked here (never swept): `tileShape=.wide` + render `preserveSourceAspect`
/// (true face proportions), Display P3 (gothic accent on P3 phones), Courier
/// Prime (bundled ⇒ deterministic byte-snapshot), a contrast bump (gothic
/// shadows), and every KILLed research knob pinned to 0. This is a LAB draft,
/// not the frozen `Sources/` preset: the A/B decides charset + columns first,
/// then ASTSK-47 bakes the real constant.
public struct DraftVesperPreset: Sendable {
    public var ink: PaletteColor
    public var accent: PaletteColor
    public var contrast: Float
    public var colorSpace: RenderColorSpace
    public var oversample: Int
    public var fontSize: CGFloat
    public var scale: CGFloat

    public init(
        ink: PaletteColor,
        accent: PaletteColor,
        contrast: Float = 0.15,
        colorSpace: RenderColorSpace = .displayP3,
        oversample: Int = 2,
        fontSize: CGFloat = 14,
        scale: CGFloat = 2
    ) {
        self.ink = ink
        self.accent = accent
        self.contrast = contrast
        self.colorSpace = colorSpace
        self.oversample = oversample
        self.fontSize = fontSize
        self.scale = scale
    }

    /// Contrast bump for gothic shadows; every KILLed research knob stays 0.
    public func renderingOptions() -> RenderingOptions {
        RenderingOptions(brightness: 0, contrast: contrast)
    }

    /// The locked converter recipe with the swept `charset` plugged in.
    public func makeConverter(charset: Charset) -> ASCIIConverter<StandardCharacterSet, VesperPalette> {
        ASCIIConverter(
            characterSet: charset.characterSet,
            palette: VesperPalette(content: .fixed([ink, accent])),
            algorithm: .logPolar,
            tileShape: .wide,
            options: renderingOptions(),
            colorSpace: colorSpace,
            oversample: oversample
        )
    }

    /// Bundled Courier Prime at the preset's point size — deterministic across
    /// devices, which the ASTSK-47 byte-snapshot requires.
    public var font: ASCIIFont { .courierPrime(size: fontSize) }
}
