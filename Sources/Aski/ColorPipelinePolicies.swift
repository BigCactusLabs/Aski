public struct ColorSamplingPolicy: Sendable, Hashable {
    internal enum Kind: Sendable, Hashable {
        case encodedAverageLegacy
        case linearLightAverage
    }

    internal let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let encodedAverageLegacy = ColorSamplingPolicy(kind: .encodedAverageLegacy)
    public static let linearLightAverage = ColorSamplingPolicy(kind: .linearLightAverage)
}

public struct PaletteMatchingPolicy: Sendable, Hashable {
    internal enum Kind: Sendable, Hashable {
        case oklabEuclidean
        case oklabHyAB
        case helmlabEuclidean
        case helmlabCompressed
    }

    internal let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    /// Whether this policy matches in Helmlab MetricSpace and therefore needs
    /// `ResolvedPaletteColor.helmlab` populated at palette-resolution time.
    internal var needsHelmlab: Bool {
        kind == .helmlabEuclidean || kind == .helmlabCompressed
    }

    /// Resolved-OKLab Euclidean distance. Default.
    ///
    /// Mirrors CSS Color 4 `DeltaEOK` — a 3D Euclidean distance in resolved
    /// OKLab. Use this unless the experimental ``oklabHyAB`` is being
    /// benchmarked end-to-end.
    public static let oklabEuclidean = PaletteMatchingPolicy(kind: .oklabEuclidean)

    /// Experimental: HyAB-on-OKLab distance — city-block lightness plus
    /// Euclidean chroma. Formula: `|ΔL| + √(Δa² + Δb²)` on resolved OKLab.
    ///
    /// ## Experimental — read this before adopting
    ///
    /// HyAB has no peer-reviewed validation on OKLab specifically. The
    /// published HyAB validation
    /// ([Abasi et al. 2019](https://onlinelibrary.wiley.com/doi/10.1002/col.22451))
    /// was conducted on CIELab. Applying the same formula to OKLab is an Aski
    /// hypothesis.
    ///
    /// **Adjacent signals (not validation):**
    ///
    /// - [Helmlab (arxiv 2602.23010)](https://arxiv.org/abs/2602.23010) treats
    ///   OKLab as a known-weak ΔE space rather than retrofitting HyAB.
    ///   [Color.js PR #722](https://github.com/color-js/color.js/pull/722)
    ///   merged `deltaEHelmlab` into `main` on 2026-05-04; as of 2026-05-27
    ///   it is not yet in a published Color.js release (0.6.1 ships without
    ///   it). The standalone [`helmlab` npm/PyPI package](https://github.com/Grkmyldz148/helmlab)
    ///   is the reference implementation. Helmlab MetricSpace is now ported as
    ///   ``PaletteMatchingPolicy/helmlabEuclidean`` and
    ///   ``PaletteMatchingPolicy/helmlabCompressed`` — a separate matching space
    ///   (72-parameter XYZ→MetricSpace pipeline), not a distance on OKLab inputs.
    /// - [Color.js issue #581](https://github.com/color-js/color.js/issues/581)
    ///   tracks OK2 / `deltaEOK2` (Euclidean OKLab with a/b doubled) as an
    ///   OKLab-native ΔE candidate. Still open as of 2024-08-26; per svgeesus,
    ///   `deltaEOK2.js` exists for testing only.
    ///
    /// **90-day re-check anchors:** Color.js #581 (OK2 candidate) and any
    /// future HyAB-on-OKLab validation. As of 2026-05-27 neither anchor has
    /// fired with HyAB-specific evidence.
    ///
    /// **Decision basis.** Promotion of this case rests on Aski's internal
    /// `palette-match-ablation` CSV evidence, not external
    /// validation. The CSV shows 1 divergent selection out of 15 rows on
    /// synthetic fixtures with zero divergence on built-in `ansi16` and
    /// `monochrome` palettes — concentrated, synthetic-only divergence.
    ///
    /// **Default unchanged.** ``oklabEuclidean`` remains the default.
    public static let oklabHyAB = PaletteMatchingPolicy(kind: .oklabHyAB)

    /// Experimental: Helmlab **MetricSpace** with plain Euclidean distance over
    /// its Lab coordinates. Monotonic at all distances, so it keeps ranking
    /// *distant* palette candidates (unlike ``helmlabCompressed``). Opt-in;
    /// ``oklabEuclidean`` remains the default.
    ///
    /// ## Experimental — thin evidence
    ///
    /// MetricSpace (arxiv 2602.23010, v21, 72 params) beats OKLab on the
    /// COMBVD ΔE benchmark, but Aski's own evaluation found **no measured win
    /// for palette matching**: the perturbation-recovery oracle ties at 100%
    /// across `oklabEuclidean`, ``helmlabEuclidean``, and ``helmlabCompressed``
    /// (the small-ΔE regime is saturated on the built-in palettes, so the
    /// oracle does not discriminate). Shipped as an opt-in for completeness, not
    /// because it improves output. See the Helmlab MetricSpace eval research
    /// note for the recovery-oracle and large-ΔE visual-review record.
    public static let helmlabEuclidean = PaletteMatchingPolicy(kind: .helmlabEuclidean)

    /// Experimental: Helmlab **MetricSpace** with the trained Minkowski +
    /// monotonic-compression ΔE. Best STRESS on *small* color differences;
    /// saturates near ~0.15 for very dissimilar pairs, so it can rank distant
    /// candidates poorly on small palettes (e.g. ANSI16). Opt-in;
    /// ``oklabEuclidean`` remains the default.
    ///
    /// ## Experimental — thin evidence
    ///
    /// Same caveat as ``helmlabEuclidean``: the perturbation-recovery oracle
    /// ties at 100% with OKLab (no measured palette-matching win), and the
    /// cross-metric `palette-match-ablation` probe is a divergence/saturation
    /// signal, **not** a quality oracle (its distances are not comparable across
    /// color spaces). The compression is monotonic, so although dissimilar-pair
    /// distances bunch near ~0.15, the argmin selection is not collapsed.
    /// Evidence basis is the recovery oracle + visual review (see the Helmlab
    /// eval research note), not the divergence probe.
    public static let helmlabCompressed = PaletteMatchingPolicy(kind: .helmlabCompressed)
}

public struct GamutMappingPolicy: Sendable, Hashable {
    internal enum Kind: Sendable, Hashable {
        case adaptiveL0
        case rayTrace
        case clip
    }

    internal let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let adaptiveL0 = GamutMappingPolicy(kind: .adaptiveL0)
    public static let rayTrace = GamutMappingPolicy(kind: .rayTrace)
    public static let clip = GamutMappingPolicy(kind: .clip)
}

public struct RenderCompositionPolicy: Sendable, Hashable {
    internal enum Kind: Sendable, Hashable {
        case encodedDisplay8Bit
        case extendedLinearPerGamut
    }

    internal let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    /// Default. CGContext-native composite in the target gamut's encoded
    /// 8-bit space (sRGB or Display P3). Preserves v0.2.0 behavior exactly.
    public static let encodedDisplay8Bit = RenderCompositionPolicy(kind: .encodedDisplay8Bit)

    /// Opt-in: composite in the target gamut's own linear-light space —
    /// `CGColorSpace.linearSRGB` for ``RenderColorSpace/sRGB`` output, and
    /// `CGColorSpace.linearDisplayP3` for ``RenderColorSpace/displayP3``.
    /// **No cross-gamut conversion** — this is not the "extended-linear sRGB
    /// as universal working space" model.
    ///
    /// Validated against the lab `linear-composite-ab` fixtures: linear-light
    /// composite is closer to ground truth than the encoded 8-bit default on
    /// the `edge_gray50_over_white_alpha050` and
    /// `edge_p3_green_over_white_alpha050` discriminator fixtures.
    ///
    /// **Default unchanged.** ``encodedDisplay8Bit`` remains the default; this
    /// case is purely additive. See the deferred-work-review addendum §2 for
    /// the decision context.
    ///
    /// Implementation note: the underlying color spaces are
    /// `CGColorSpace.linearSRGB` / `.linearDisplayP3` — the non-extended
    /// linear variants, which support 8-bit RGBA bitmaps. The "extended-range"
    /// linear color spaces require float bitmaps and are deferred.
    public static let extendedLinearPerGamut = RenderCompositionPolicy(kind: .extendedLinearPerGamut)
}

import CoreGraphics

extension RenderCompositionPolicy {
    /// Returns the `CGColorSpace` to use when constructing a `CGBitmapContext`
    /// for `renderColorSpace` under this composition policy. Shared by
    /// `ImageRenderer.renderImage` (no-effects path) and
    /// `CellRasterBuilder.makeASCIIRaster` (effects path) so the policy
    /// dispatch lives in one place.
    internal func cgColorSpace(for renderColorSpace: RenderColorSpace) -> CGColorSpace {
        switch kind {
        case .encodedDisplay8Bit:
            switch renderColorSpace {
            case .sRGB:
                return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            case .displayP3:
                return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
            }
        case .extendedLinearPerGamut:
            switch renderColorSpace {
            case .sRGB:
                return CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
            case .displayP3:
                return CGColorSpace(name: CGColorSpace.linearDisplayP3) ?? CGColorSpaceCreateDeviceRGB()
            }
        }
    }
}
