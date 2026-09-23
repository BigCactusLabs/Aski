import Foundation

public struct CuberootAccuracyFixture: Sendable, Hashable {
    public let id: String
    public let input: Float
    public let group: Group

    public init(id: String, input: Float, group: Group) {
        self.id = id
        self.input = input
        self.group = group
    }

    public enum Group: Sendable, Hashable {
        case randomLMS
        case nearZero
        case landmark
        case negativeZero

        /// CSV label per addendum §"CSV schema (full)" — snake-cased.
        public var csvLabel: String {
            switch self {
            case .randomLMS: return "random_lms"
            case .nearZero: return "near_zero"
            case .landmark: return "landmark"
            case .negativeZero: return "negative_zero"
            }
        }
    }
}

public enum CuberootAccuracyFixtures {

    /// All 10,014 fixtures in canonical CSV order:
    /// `random_lms (10,000) → near_zero (7) → landmark (6) → negative_zero (1)`.
    public static func all(seed: UInt64) -> [CuberootAccuracyFixture] {
        randomLMS(seed: seed) + nearZero + landmarks + [negativeZero]
    }

    public static let nearZero: [CuberootAccuracyFixture] = {
        let values: [Float] = [-1e-6, -1e-7, -1e-8, 0.0, 1e-8, 1e-7, 1e-6]
        return values.enumerated().map { index, value in
            CuberootAccuracyFixture(
                id: "near_zero_" + String(format: "%03d", index),
                input: value,
                group: .nearZero
            )
        }
    }()

    public static let landmarks: [CuberootAccuracyFixture] = [
        CuberootAccuracyFixture(id: "landmark_neg_one", input: -1.0, group: .landmark),
        CuberootAccuracyFixture(id: "landmark_neg_eighth", input: -0.125, group: .landmark),
        CuberootAccuracyFixture(id: "landmark_zero", input: 0.0, group: .landmark),
        CuberootAccuracyFixture(id: "landmark_pos_eighth", input: 0.125, group: .landmark),
        CuberootAccuracyFixture(id: "landmark_pos_one", input: 1.0, group: .landmark),
        CuberootAccuracyFixture(id: "landmark_pos_eight", input: 8.0, group: .landmark),
    ]

    /// Distinct from `landmark_zero` via the bit pattern, not the value.
    /// `Float(bitPattern: 0x80000000)` is `-0.0f`; this is unambiguous in source
    /// even when the compiler is asked to fold a `-0.0` literal back to `+0.0`.
    public static let negativeZero = CuberootAccuracyFixture(
        id: "negative_zero",
        input: Float(bitPattern: 0x80000000),
        group: .negativeZero
    )

    /// 10,000 seeded `Float` samples drawn uniformly from `[-0.25, 2.0]`. The
    /// RNG is a private xoshiro256** seeded from `seed` via splitmix64 (the
    /// canonical pattern from <https://prng.di.unimi.it/>) so output is stable
    /// across Swift versions and platforms.
    public static func randomLMS(seed: UInt64) -> [CuberootAccuracyFixture] {
        var rng = Xoshiro256StarStar(seed: seed)
        var fixtures: [CuberootAccuracyFixture] = []
        fixtures.reserveCapacity(10_000)
        for index in 0..<10_000 {
            let unit = rng.nextUnitDouble()  // [0, 1)
            let value = Float(-0.25 + unit * (2.0 - (-0.25)))  // [-0.25, 2.0)
            fixtures.append(
                CuberootAccuracyFixture(
                    id: "random_lms_" + String(format: "%05d", index),
                    input: value,
                    group: .randomLMS
                ))
        }
        return fixtures
    }
}

/// xoshiro256** — 64-bit state generator. Public-domain reference at
/// <https://prng.di.unimi.it/xoshiro256starstar.c>. State is initialized by
/// splitmix64 expansion of the seed.
private struct Xoshiro256StarStar {
    private var s: (UInt64, UInt64, UInt64, UInt64)

    init(seed: UInt64) {
        var splitmix = seed
        s.0 = Xoshiro256StarStar.splitmix64(&splitmix)
        s.1 = Xoshiro256StarStar.splitmix64(&splitmix)
        s.2 = Xoshiro256StarStar.splitmix64(&splitmix)
        s.3 = Xoshiro256StarStar.splitmix64(&splitmix)
    }

    mutating func next() -> UInt64 {
        let result = rotl(s.1 &* 5, 7) &* 9
        let t = s.1 &<< 17

        s.2 ^= s.0
        s.3 ^= s.1
        s.1 ^= s.2
        s.0 ^= s.3

        s.2 ^= t
        s.3 = rotl(s.3, 45)

        return result
    }

    /// Top 53 bits → `[0, 1)` Double (the canonical xoshiro mapping).
    mutating func nextUnitDouble() -> Double {
        let bits = next() >> 11
        return Double(bits) * (1.0 / Double(1 << 53))
    }

    @inline(__always)
    private func rotl(_ x: UInt64, _ k: Int) -> UInt64 {
        (x &<< UInt64(k)) | (x &>> UInt64(64 - k))
    }

    private static func splitmix64(_ state: inout UInt64) -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
        return z ^ (z &>> 31)
    }
}
