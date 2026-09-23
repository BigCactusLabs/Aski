import Aski
import simd

/// Deterministic fixtures for `helmlab-reference`. Order is significant for
/// CSV determinism.
enum HelmlabReferenceFixtures {
    static let materialPrimaries: [(id: String, rgb: SIMD3<Double>)] = [
        ("material_red", SIMD3(1, 0, 0)),
        ("material_green", SIMD3(0, 1, 0)),
        ("material_blue", SIMD3(0, 0, 1)),
        ("material_white", SIMD3(1, 1, 1)),
        ("material_black", SIMD3(0, 0, 0)),
    ]

    /// Strided sRGB gamut grid (step 0.25 → 125 points).
    static func grid() -> [SIMD3<Double>] {
        var out: [SIMD3<Double>] = []
        out.reserveCapacity(125)
        let steps = [0.0, 0.25, 0.5, 0.75, 1.0]
        for r in steps {
            for g in steps {
                for b in steps {
                    out.append(SIMD3(r, g, b))
                }
            }
        }
        return out
    }
}
