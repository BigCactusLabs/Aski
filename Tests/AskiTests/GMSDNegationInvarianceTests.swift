import Testing

@testable import AskiToolSupport

/// ASKI-60's gate leans on one property of GMSD: it is blind to a global
/// negation of BOTH inputs. That is what lets GMSD arbitrate a comparison whose
/// whole subject is the ink convention — an oracle that moved with the
/// convention would flatter whichever arm shares its polarity. The property is
/// structural (Prewitt kernels are zero-mean, so `∇(1−x) = −∇x` and the
/// magnitudes are unchanged), but it is asserted here rather than assumed: if a
/// future GMSD edit adds a luminance or mean term, the negative control in the
/// `polarity-gate` instrument becomes meaningless and this test is the tripwire.
///
/// MAE is asserted alongside it because the gate reports the pair together.
/// MAE's invariance is exact in real arithmetic (`|(1−a)−(1−b)| = |a−b|`, no
/// filtering in between), and the planes below are built from dyadic fractions
/// so `1 − x` is exact in `Float` too and the assertion can be bit-equality.
/// On corpus pixels `1 − x` rounds, so the instrument's own negative control
/// reports a max |ΔMAE| at float noise rather than a hard zero.
@Suite struct GMSDNegationInvarianceTests {

    private static let width = 12
    private static let height = 9

    /// Two deterministic, structurally different planes: a sawtooth ramp and a
    /// coarse checker. Different enough that GMSD is far from its degenerate 0,
    /// so an invariance failure would show up as a real difference. Every value
    /// is a dyadic fraction, so `1 − x` is exact in `Float` and the MAE check
    /// can assert bit-equality instead of a tolerance.
    private static func planes() -> (a: [Float], b: [Float]) {
        var a = [Float](repeating: 0, count: width * height)
        var b = a
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                a[i] = Float((x + y) % 16) / 16
                b[i] = ((x / 3) + (y / 2)) % 2 == 0 ? 0.125 : 0.875
            }
        }
        return (a, b)
    }

    private static func mae(_ x: [Float], _ y: [Float]) -> Double {
        var total = 0.0
        for i in x.indices { total += Double(abs(x[i] - y[i])) }
        return total / Double(x.count)
    }

    @Test func gmsdIsInvariantUnderNegatingBothPlanes() {
        let (a, b) = Self.planes()
        let negatedA = a.map { 1 - $0 }
        let negatedB = b.map { 1 - $0 }

        let direct = GMSD.gmsd(a, b, width: Self.width, height: Self.height)
        let negated = GMSD.gmsd(negatedA, negatedB, width: Self.width, height: Self.height)

        #expect(direct > 0.01, "degenerate GMSD (\(direct)) would make the check vacuous")
        #expect(
            abs(direct - negated) < 1e-6,
            "GMSD moved under a global negation: \(direct) vs \(negated)"
        )
    }

    @Test func maeIsExactlyInvariantUnderNegatingBothPlanes() {
        let (a, b) = Self.planes()
        let direct = Self.mae(a, b)
        let negated = Self.mae(a.map { 1 - $0 }, b.map { 1 - $0 })
        #expect(direct == negated, "MAE moved under a global negation: \(direct) vs \(negated)")
    }
}
