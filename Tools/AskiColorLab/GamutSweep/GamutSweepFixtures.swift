import Aski
import Foundation
import simd

/// Target gamut the command sweeps each fixture against. Order defines CSV
/// per-fixture inner ordering: every (policy, sRGB) row precedes its
/// (policy, displayP3) sibling.
public enum GamutSweepTarget: String, CaseIterable, Sendable {
    case sRGB
    case displayP3

    /// `target_gamut` column value.
    public var csvLabel: String { rawValue }

    /// OKLab → target linear RGB.
    public var oklabToLinearRGB: (SIMD3<Float>) -> SIMD3<Float> {
        switch self {
        case .sRGB: return ColorConversion.oklabToLinearSRGB
        case .displayP3: return ColorConversion.oklabToLinearP3
        }
    }

    /// Target linear RGB → OKLab.
    public var linearRGBToOKLab: (SIMD3<Float>) -> SIMD3<Float> {
        switch self {
        case .sRGB: return ColorConversion.linearSRGBToOKLAB
        case .displayP3: return ColorConversion.linearP3ToOKLAB
        }
    }
}

/// One OkLCh-defined fixture row. `sourceOKLab` is derived from OkLCh once at
/// construction so the rest of the pipeline never re-computes it.
public struct GamutSweepFixture: Sendable, Hashable {
    public let id: String
    public let okLChL: Float
    public let okLChC: Float
    public let okLChHueDegrees: Float
    public let sourceOKLab: SIMD3<Float>

    public init(id: String, okLChL: Float, okLChC: Float, okLChHueDegrees: Float) {
        self.id = id
        self.okLChL = okLChL
        self.okLChC = okLChC
        self.okLChHueDegrees = okLChHueDegrees
        // Spec §Fixtures: a = C·cos(h_radians), b = C·sin(h_radians).
        let hueRadians = okLChHueDegrees * .pi / 180
        self.sourceOKLab = SIMD3<Float>(
            okLChL,
            okLChC * cos(hueRadians),
            okLChC * sin(hueRadians)
        )
    }
}

/// Deterministic fixture set for `gamut-sweep`.
///
/// Grid fixtures come first, boundary fixtures second; this order is the CSV
/// order and tests on `firstFixtureRows...` depend on it. `--seed` does not
/// alter this set — fixtures are pure data so randomization cannot silently
/// change provenance semantics.
public enum GamutSweepFixtures {
    /// All 682 fixtures, in CSV order.
    public static let all: [GamutSweepFixture] = grid + boundary

    /// 672 grid fixtures (populated in Task 3).
    public static let grid: [GamutSweepFixture] = makeGrid()

    /// 10 hand-picked boundary fixtures.
    public static let boundary: [GamutSweepFixture] = [
        GamutSweepFixture(id: "mid_gray", okLChL: 0.5, okLChC: 0, okLChHueDegrees: 0),
        GamutSweepFixture(id: "p3_only_green", okLChL: 0.87, okLChC: 0.295, okLChHueDegrees: 142),
        GamutSweepFixture(id: "cyan_peak", okLChL: 0.75, okLChC: 0.4, okLChHueDegrees: 195),
        GamutSweepFixture(id: "yellow_peak", okLChL: 0.85, okLChC: 0.35, okLChHueDegrees: 105),
        GamutSweepFixture(id: "blue_corner", okLChL: 0.5, okLChC: 0.4, okLChHueDegrees: 270),
        GamutSweepFixture(id: "deep_magenta", okLChL: 0.5, okLChC: 0.8, okLChHueDegrees: 315),
        GamutSweepFixture(id: "deep_red", okLChL: 0.5, okLChC: 0.8, okLChHueDegrees: 30),
        GamutSweepFixture(id: "lightness_floor", okLChL: 0, okLChC: 0.1, okLChHueDegrees: 0),
        GamutSweepFixture(id: "lightness_ceiling", okLChL: 1, okLChC: 0.1, okLChHueDegrees: 0),
        GamutSweepFixture(id: "superwhite_csswg6999", okLChL: 1.044, okLChC: 0, okLChHueDegrees: 336),
    ]

    private static func makeGrid() -> [GamutSweepFixture] {
        let lightnesses: [Float] = [0, 0.05, 0.25, 0.5, 0.75, 0.95, 1]
        let chromas: [Float] = [0.1, 0.2, 0.4, 0.8]
        let hueDegrees: [Float] = stride(from: 0, through: 345, by: 15).map(Float.init)

        var fixtures: [GamutSweepFixture] = []
        fixtures.reserveCapacity(lightnesses.count * chromas.count * hueDegrees.count)
        for L in lightnesses {
            for C in chromas {
                for h in hueDegrees {
                    let id = gridID(L: L, C: C, hueDegrees: h)
                    fixtures.append(
                        GamutSweepFixture(
                            id: id,
                            okLChL: L,
                            okLChC: C,
                            okLChHueDegrees: h
                        ))
                }
            }
        }
        return fixtures
    }

    private static func gridID(L: Float, C: Float, hueDegrees: Float) -> String {
        let lPart = String(format: "L%03d", Int((L * 100).rounded()))
        let cPart = String(format: "C%03d", Int((C * 100).rounded()))
        let hPart = String(format: "H%03d", Int(hueDegrees.rounded()))
        return "grid_\(lPart)_\(cPart)_\(hPart)"
    }
}
