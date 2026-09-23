import Foundation
import simd

/// One fixture row. `fgColorSpace` and `targetGamut` always match (spec
/// §Target Gamuts).
public struct LinearCompositeFixture: Sendable, Hashable {
    public let id: String
    public let fgByte: SIMD3<Float>
    public let fgAlphaByte: Int
    public let bgByte: SIMD3<Float>
    public let bgAlphaByte: Int
    public let targetGamut: LinearCompositeSpaces.TargetGamut

    public init(
        id: String,
        fgByte: SIMD3<Float>,
        fgAlphaByte: Int,
        bgByte: SIMD3<Float>,
        bgAlphaByte: Int,
        targetGamut: LinearCompositeSpaces.TargetGamut
    ) {
        self.id = id
        self.fgByte = fgByte
        self.fgAlphaByte = fgAlphaByte
        self.bgByte = bgByte
        self.bgAlphaByte = bgAlphaByte
        self.targetGamut = targetGamut
    }

    /// Convenience for the `fg_color_space` column.
    public var fgColorSpace: LinearCompositeSpaces.TargetGamut { targetGamut }
}

/// Deterministic fixture set for `linear-composite-ab`.
///
/// Group A (sRGB grid) → Group B (P3 grid) → Group C (hand-picked edges).
/// `--seed` does not alter this set — fixtures are pure data so randomization
/// cannot silently change provenance semantics.
public enum LinearCompositeFixtures {

    /// All 389 fixtures, in CSV order. `edges` populated in Task 8.
    public static let all: [LinearCompositeFixture] = sRGBGrid + p3Grid + edges

    /// Group A — 192 sRGB combinatorial grid fixtures.
    public static let sRGBGrid: [LinearCompositeFixture] = makeGrid(target: .sRGB)

    /// Group B — 192 Display P3 combinatorial grid fixtures.
    public static let p3Grid: [LinearCompositeFixture] = makeGrid(target: .displayP3)

    /// Group C — 5 hand-picked edge fixtures. Order is the spec's order and
    /// defines CSV order. Each addresses a phenomenon not covered (or covered
    /// too weakly) by the combinatorial grid; see spec §Fixtures Group C.
    public static let edges: [LinearCompositeFixture] = [
        // Algorithmic discriminator: dark gray fg over white bg in sRGB.
        // encoded8bit ≈ byte 191; linear8bit ≈ byte 204. Per-channel divergence ≈ 13 bytes.
        LinearCompositeFixture(
            id: "edge_gray50_over_white_alpha050",
            fgByte: SIMD3<Float>(128, 128, 128),
            fgAlphaByte: 128,
            bgByte: SIMD3<Float>(255, 255, 255),
            bgAlphaByte: 255,
            targetGamut: .sRGB
        ),
        // P3 analog of the sRGB discriminator. Saturated P3 green over P3 white.
        LinearCompositeFixture(
            id: "edge_p3_green_over_white_alpha050",
            fgByte: SIMD3<Float>(0, 255, 0),
            fgAlphaByte: 128,
            bgByte: SIMD3<Float>(255, 255, 255),
            bgAlphaByte: 255,
            targetGamut: .displayP3
        ),
        // Canonical motivation for linearFloat: low-α low-luminance contribution
        // quantizes to zero in 8-bit but survives in float.
        LinearCompositeFixture(
            id: "edge_shadow_quantization",
            fgByte: SIMD3<Float>(3, 0, 0),
            fgAlphaByte: 13,
            bgByte: SIMD3<Float>(0, 0, 0),
            bgAlphaByte: 255,
            targetGamut: .sRGB
        ),
        // α=0 source must not leak color into the output.
        LinearCompositeFixture(
            id: "edge_zero_alpha_bleed_red_over_white",
            fgByte: SIMD3<Float>(255, 0, 0),
            fgAlphaByte: 0,
            bgByte: SIMD3<Float>(255, 255, 255),
            bgAlphaByte: 255,
            targetGamut: .sRGB
        ),
        // Same-color sanity: when fg_byte == bg_byte, encoded8bit and linear8bit
        // must produce byte-identical output.
        LinearCompositeFixture(
            id: "edge_gray50_over_gray50_alpha050",
            fgByte: SIMD3<Float>(128, 128, 128),
            fgAlphaByte: 128,
            bgByte: SIMD3<Float>(128, 128, 128),
            bgAlphaByte: 255,
            targetGamut: .sRGB
        ),
    ]

    /// Foreground saturated primaries. Spec §Fixtures Group A: R, G, B, C, M, Y.
    private static let foregrounds: [(label: String, bytes: SIMD3<Float>)] = [
        ("R", SIMD3<Float>(255, 0, 0)),
        ("G", SIMD3<Float>(0, 255, 0)),
        ("B", SIMD3<Float>(0, 0, 255)),
        ("C", SIMD3<Float>(0, 255, 255)),
        ("M", SIMD3<Float>(255, 0, 255)),
        ("Y", SIMD3<Float>(255, 255, 0)),
    ]

    /// Backgrounds. Spec §Fixtures Group A: K, W, G50, T.
    /// Transparent (`T`) carries `bgAlphaByte = 0`; the others are opaque.
    private static let backgrounds: [(label: String, bytes: SIMD3<Float>, alpha: Int)] = [
        ("K", SIMD3<Float>(0, 0, 0), 255),
        ("W", SIMD3<Float>(255, 255, 255), 255),
        ("G50", SIMD3<Float>(128, 128, 128), 255),
        ("T", SIMD3<Float>(0, 0, 0), 0),
    ]

    /// Source alpha bytes. Spec §Fixtures Group A: 0, 1, 13, 64, 128, 191, 242, 255.
    private static let alphaBytes: [Int] = [0, 1, 13, 64, 128, 191, 242, 255]

    private static func makeGrid(
        target: LinearCompositeSpaces.TargetGamut
    ) -> [LinearCompositeFixture] {
        let prefix: String
        switch target {
        case .sRGB: prefix = "grid_sRGB"
        case .displayP3: prefix = "grid_P3"
        }

        var fixtures: [LinearCompositeFixture] = []
        fixtures.reserveCapacity(foregrounds.count * backgrounds.count * alphaBytes.count)
        for fg in foregrounds {
            for bg in backgrounds {
                for alpha in alphaBytes {
                    let id = "\(prefix)_\(fg.label)_\(bg.label)_\(String(format: "%03d", alpha))"
                    fixtures.append(
                        LinearCompositeFixture(
                            id: id,
                            fgByte: fg.bytes,
                            fgAlphaByte: alpha,
                            bgByte: bg.bytes,
                            bgAlphaByte: bg.alpha,
                            targetGamut: target
                        ))
                }
            }
        }
        return fixtures
    }
}
