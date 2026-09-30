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

    /// Index of the nearest fixed entry; first entry wins exact ties.
    /// ASKI-90 keeps the original distance arithmetic and visit order. Returning
    /// the index lets a conversion reuse its display-color table without a
    /// second lookup or re-encoding the winning OKLab value for every cell.
    static func nearestIndex(
        _ query: SIMD3<Float>,
        in palette: [ResolvedPaletteColor],
        policy: PaletteMatchingPolicy = .oklabEuclidean
    ) -> Int {
        precondition(!palette.isEmpty, "Fixed palette matching requires at least one color")
        switch policy.kind {
        case .oklabEuclidean:
            var nearest = 0
            var nearestDistance = Float.infinity
            for index in palette.indices {
                let color = palette[index]
                let distance = simd_length_squared(color.oklab - query)
                if distance < nearestDistance {
                    nearest = index
                    nearestDistance = distance
                }
            }
            return nearest
        case .oklabHyAB:
            // |ΔL| + √(Δa² + Δb²) — ported verbatim from Tools/AskiColorLab/
            // PaletteMatching/PaletteMatchPolicies.swift:16-19. Unlike Euclidean,
            // HyAB is not monotonic in its squared form, so the full distance is
            // computed each iteration.
            var nearest = 0
            var nearestDistance = Float.infinity
            for index in palette.indices {
                let color = palette[index]
                let delta = color.oklab - query
                let distance = abs(delta.x) + simd_length(SIMD2<Float>(delta.y, delta.z))
                if distance < nearestDistance {
                    nearest = index
                    nearestDistance = distance
                }
            }
            return nearest
        case .helmlabEuclidean, .helmlabCompressed:
            // Convert the query OKLab → linRGB → XYZ → MetricSpace once. The
            // OKLab→linRGB→XYZ composition is gamut-invariant, so the sRGB pair is
            // canonical regardless of the converter's target gamut. The index refers
            // to the original OKLab entry, not these matching coordinates.
            let queryLinRGB = ColorConversion.oklabToLinearSRGB(query)
            let queryXYZ = ColorConversion.linearSRGBToXYZ(SIMD3<Double>(queryLinRGB))
            let queryHelmlab = HelmlabMetric.xyzToHelmlabMetric(queryXYZ)

            var nearest = 0
            var nearestDistance = Double.infinity
            for index in palette.indices {
                let color = palette[index]
                guard let candidateHelmlab = color.helmlab else {
                    preconditionFailure("Helmlab policy requires ResolvedPaletteColor.helmlab to be populated; resolve the palette with needsHelmlab: true")
                }
                let distance =
                    policy.kind == .helmlabEuclidean
                    ? HelmlabMetric.euclideanDistance(queryHelmlab, candidateHelmlab)
                    : HelmlabMetric.compressedDeltaE(queryHelmlab, candidateHelmlab)
                if distance < nearestDistance {
                    nearest = index
                    nearestDistance = distance
                }
            }
            return nearest
        }
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
