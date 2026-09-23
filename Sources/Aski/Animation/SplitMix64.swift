internal enum AnimationRandomSalt: UInt64, Sendable {
    case phase = 0x9E37_79B9_7F4A_7C15
    case period = 0xD1B5_4A32_D192_ED03
    case intensity = 0x94D0_49BB_1331_11EB
}

internal enum SplitMix64 {
    static func hash(seed: UInt64, row: Int, column: Int, salt: AnimationRandomSalt) -> UInt64 {
        var value = seed
        value &+= UInt64(truncatingIfNeeded: row) &* 0x9E37_79B9_7F4A_7C15
        value &+= UInt64(truncatingIfNeeded: column) &* 0xBF58_476D_1CE4_E5B9
        value &+= salt.rawValue
        return mix(value)
    }

    static func unitDouble(seed: UInt64, row: Int, column: Int, salt: AnimationRandomSalt) -> Double {
        let value = hash(seed: seed, row: row, column: column, salt: salt)
        return Double(value >> 11) * (1.0 / Double(UInt64(1) << 53))
    }

    private static func mix(_ input: UInt64) -> UInt64 {
        var z = input &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
