import simd

internal struct ResolvedPalette: Sendable {
    let colors: [ResolvedPaletteColor]
    let isPassThrough: Bool

    static let passThrough = ResolvedPalette(content: .passThrough)

    init(content: PaletteContent, needsHelmlab: Bool = false) {
        if content.isPassThrough {
            self.colors = []
            self.isPassThrough = true
            return
        }

        guard let paletteColors = content.colors else {
            preconditionFailure("PaletteContent fixed storage missing colors")
        }
        self.colors = paletteColors.map { color in
            ResolvedPaletteColor(
                source: color,
                oklab: PaletteColorSpaceConverters.oklab(for: color),
                helmlab: needsHelmlab ? PaletteColorSpaceConverters.helmlab(for: color) : nil
            )
        }
        self.isPassThrough = false
    }

    init(oklabColors: [SIMD3<Float>]) {
        precondition(!oklabColors.isEmpty, "ResolvedPalette(oklabColors:) requires at least one color")
        // TileGrid-only path: cannot reach a Helmlab policy under the current
        // API, so helmlab stays nil. See spec § Policy-aware palette resolution.
        self.colors = oklabColors.map {
            ResolvedPaletteColor(source: nil, oklab: $0, helmlab: nil)
        }
        self.isPassThrough = false
    }
}

internal struct ResolvedPaletteColor: Sendable {
    let source: PaletteColor?
    let oklab: SIMD3<Float>
    /// MetricSpace-Lab coordinates, populated only when a Helmlab matching
    /// policy is active (see `ResolvedPalette(content:needsHelmlab:)`).
    let helmlab: SIMD3<Double>?

    /// Custom init with `helmlab` defaulting to `nil`. REQUIRED: a third stored
    /// property without this default would change the synthesized memberwise
    /// init and break the existing `ResolvedPaletteColor(source:oklab:)` call
    /// sites (`PaletteMatchingPolicyTests.swift`, the `oklabColors:` init).
    init(source: PaletteColor?, oklab: SIMD3<Float>, helmlab: SIMD3<Double>? = nil) {
        self.source = source
        self.oklab = oklab
        self.helmlab = helmlab
    }
}

private enum PaletteColorSpaceConverters {
    static func oklab(for color: PaletteColor) -> SIMD3<Float> {
        let linear = SIMD3<Float>(
            ColorConversion.sRGBDecode(color.components.x),
            ColorConversion.sRGBDecode(color.components.y),
            ColorConversion.sRGBDecode(color.components.z)
        )
        if color.colorSpace == .sRGB {
            return ColorConversion.linearSRGBToOKLAB(linear)
        } else if color.colorSpace == .displayP3 {
            return ColorConversion.linearP3ToOKLAB(linear)
        } else {
            preconditionFailure("Unsupported PaletteColorSpace: \(color.colorSpace.rawValue)")
        }
    }

    static func helmlab(for color: PaletteColor) -> SIMD3<Double> {
        let linear = SIMD3<Double>(
            Double(ColorConversion.sRGBDecode(color.components.x)),
            Double(ColorConversion.sRGBDecode(color.components.y)),
            Double(ColorConversion.sRGBDecode(color.components.z))
        )
        let xyz: SIMD3<Double>
        if color.colorSpace == .sRGB {
            xyz = ColorConversion.linearSRGBToXYZ(linear)
        } else if color.colorSpace == .displayP3 {
            xyz = ColorConversion.linearP3ToXYZ(linear)
        } else {
            preconditionFailure("Unsupported PaletteColorSpace: \(color.colorSpace.rawValue)")
        }
        return HelmlabMetric.xyzToHelmlabMetric(xyz)
    }
}
