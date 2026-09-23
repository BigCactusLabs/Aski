import simd

/// Approximated interlocking-brick-style colors, derived from publicly-referenced
/// values in the LDraw Colour Definition Reference and the BrickLink Color Guide.
/// Names are generic descriptors only — see DocC `Tiles.md` for the
/// non-affiliation disclaimer.
internal enum BrickColors {

    /// Generic-name → sRGB-hex mapping. The exhaustive list is computed once at
    /// module load (see `oklab` below).
    private static let sRGBHex: [(name: String, hex: UInt32)] = [
        ("white", 0xFFFFFF),
        ("black", 0x05131D),
        ("lightBluishGray", 0x9BA19D),
        ("darkBluishGray", 0x6D6E5C),
        ("lightGray", 0xA0A5A9),
        ("darkGray", 0x6C6E68),
        ("brightRed", 0xC91A09),
        ("darkRed", 0x720E0F),
        ("brightOrange", 0xFE8A18),
        ("mediumOrange", 0xFFA70B),
        ("brightYellow", 0xF2CD37),
        ("coolYellow", 0xFFF03A),
        ("tan", 0xE4CD9E),
        ("darkTan", 0x958A73),
        ("reddishBrown", 0x582A12),
        ("mediumBrown", 0x583927),
        ("brightGreen", 0x4B9F4A),
        ("darkGreen", 0x184632),
        ("limeGreen", 0xA5CA18),
        ("brightBlue", 0x0055BF),
        ("darkBlue", 0x0A3463),
        ("mediumBlue", 0x5A93DB),
        ("lightAqua", 0xADC3C0),
        ("brightTurquoise", 0x008F9B),
        ("brightPurple", 0x81007B),
        ("darkPurple", 0x3F3691),
        ("brightPink", 0xFC97AC),
        ("lightLavender", 0xE1D5ED),
        ("sandBlue", 0x5A7184),
        ("sandGreen", 0xA0BCAC),
    ]

    /// Brick palette in OKLAB. Computed once at module init.
    static let oklab: [SIMD3<Float>] = sRGBHex.map { entry in
        let r = Float((entry.hex >> 16) & 0xFF) / 255
        let g = Float((entry.hex >> 8) & 0xFF) / 255
        let b = Float(entry.hex & 0xFF) / 255
        let linear = SIMD3<Float>(
            ColorConversion.sRGBDecode(r),
            ColorConversion.sRGBDecode(g),
            ColorConversion.sRGBDecode(b)
        )
        return ColorConversion.linearSRGBToOKLAB(linear)
    }
}
