import Aski

public struct SamplingFixture: Sendable {
    public let id: String
    public let width: Int
    public let height: Int
    public let colorSpace: RenderColorSpace
    public let pixels: [UInt8]
}

public enum SamplingFixtures {
    /// Hand-coded RGBA8 cells covering the categories the spec calls out for
    /// sampling-ablation: opaque primaries, black/white ramps, half-transparent
    /// saturated samples, one-opaque-rest-transparent, alpha gradients, and a
    /// Display P3 saturated fixture. Order is fixed for CSV determinism.
    public static let all: [SamplingFixture] = [
        SamplingFixture(
            id: "2x2_opaque_primaries",
            width: 2, height: 2,
            colorSpace: .sRGB,
            pixels: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255,
            ]
        ),
        SamplingFixture(
            id: "2x2_black_white_diagonal",
            width: 2, height: 2,
            colorSpace: .sRGB,
            pixels: [
                0, 0, 0, 255, 255, 255, 255, 255,
                255, 255, 255, 255, 0, 0, 0, 255,
            ]
        ),
        SamplingFixture(
            id: "2x2_half_transparent_saturated_red",
            width: 2, height: 2,
            colorSpace: .sRGB,
            // Premultiplied-last with alpha=128: encoded RGB are already scaled
            // by alpha. 255*128/255 = 128.
            pixels: [
                128, 0, 0, 128, 128, 0, 0, 128,
                128, 0, 0, 128, 128, 0, 0, 128,
            ]
        ),
        SamplingFixture(
            id: "2x2_one_opaque_rest_transparent",
            width: 2, height: 2,
            colorSpace: .sRGB,
            pixels: [
                255, 255, 255, 255, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0,
            ]
        ),
        SamplingFixture(
            id: "4x4_horizontal_alpha_gradient",
            width: 4, height: 4,
            colorSpace: .sRGB,
            pixels: alphaGradient(rows: 4, columns: 4, baseRGB: (255, 0, 0))
        ),
        SamplingFixture(
            id: "4x4_neutral_brightness_ramp",
            width: 4, height: 4,
            colorSpace: .sRGB,
            pixels: brightnessRamp(rows: 4, columns: 4)
        ),
        SamplingFixture(
            id: "2x2_displayp3_saturated_red",
            width: 2, height: 2,
            colorSpace: .displayP3,
            pixels: [
                255, 0, 0, 255, 255, 0, 0, 255,
                255, 0, 0, 255, 255, 0, 0, 255,
            ]
        ),
        SamplingFixture(
            id: "8x8_mixed_chroma_alpha",
            width: 8, height: 8,
            colorSpace: .sRGB,
            pixels: mixedChromaAlpha8x8()
        ),
    ]

    private static func alphaGradient(
        rows: Int,
        columns: Int,
        baseRGB: (UInt8, UInt8, UInt8)
    ) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(rows * columns * 4)
        for _ in 0..<rows {
            for column in 0..<columns {
                let alpha = UInt8((column * 255) / max(1, columns - 1))
                let r = UInt8((Int(baseRGB.0) * Int(alpha)) / 255)
                let g = UInt8((Int(baseRGB.1) * Int(alpha)) / 255)
                let b = UInt8((Int(baseRGB.2) * Int(alpha)) / 255)
                out.append(contentsOf: [r, g, b, alpha])
            }
        }
        return out
    }

    private static func brightnessRamp(rows: Int, columns: Int) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(rows * columns * 4)
        let totalCells = rows * columns
        for index in 0..<totalCells {
            let level = UInt8((index * 255) / max(1, totalCells - 1))
            out.append(contentsOf: [level, level, level, 255])
        }
        return out
    }

    private static func mixedChromaAlpha8x8() -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(8 * 8 * 4)
        let alphas: [UInt8] = [0, 64, 128, 192, 255, 255, 128, 0]
        for row in 0..<8 {
            let alpha = alphas[row]
            for column in 0..<8 {
                let (baseR, baseG, baseB): (UInt8, UInt8, UInt8)
                switch (row / 4, column / 4) {
                case (0, 0): (baseR, baseG, baseB) = (255, 0, 0)
                case (0, 1): (baseR, baseG, baseB) = (0, 255, 0)
                case (1, 0): (baseR, baseG, baseB) = (0, 0, 255)
                default: (baseR, baseG, baseB) = (128, 128, 128)
                }
                let r = UInt8((Int(baseR) * Int(alpha)) / 255)
                let g = UInt8((Int(baseG) * Int(alpha)) / 255)
                let b = UInt8((Int(baseB) * Int(alpha)) / 255)
                out.append(contentsOf: [r, g, b, alpha])
            }
        }
        return out
    }
}
