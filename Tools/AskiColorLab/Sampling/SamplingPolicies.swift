import Aski
import simd

public struct SampledLinearRGB: Equatable, Sendable {
    public let linearRGB: SIMD3<Float>
    public let alpha: Float
}

/// Lab-local re-implementation of the two production sampling policies. Mirrors
/// the semantics from the v2 spec verbatim. A dedicated drift test pins these
/// to the library's `ConversionContext.cellStats` so they stay in sync.
public enum SamplingPolicies {
    public static func encodedAverageLegacy(
        pixels: [UInt8],
        width: Int,
        height: Int
    ) -> SampledLinearRGB {
        var redSum: Float = 0
        var greenSum: Float = 0
        var blueSum: Float = 0
        var alphaSum: Float = 0
        var count: Float = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let alpha = Float(pixels[offset + 3]) / 255
                let red = Float(pixels[offset]) / 255
                let green = Float(pixels[offset + 1]) / 255
                let blue = Float(pixels[offset + 2]) / 255
                if alpha > 0 {
                    redSum += min(red / alpha, 1)
                    greenSum += min(green / alpha, 1)
                    blueSum += min(blue / alpha, 1)
                }
                alphaSum += alpha
                count += 1
            }
        }

        let encodedRGB = SIMD3<Float>(redSum / count, greenSum / count, blueSum / count)
        let linearRGB = SIMD3<Float>(
            ColorConversion.sRGBDecode(encodedRGB.x),
            ColorConversion.sRGBDecode(encodedRGB.y),
            ColorConversion.sRGBDecode(encodedRGB.z)
        )
        return SampledLinearRGB(linearRGB: linearRGB, alpha: alphaSum / count)
    }

    public static func linearLightAverage(
        pixels: [UInt8],
        width: Int,
        height: Int
    ) -> SampledLinearRGB {
        var linearSum = SIMD3<Float>(0, 0, 0)
        var alphaSum: Float = 0
        var count: Float = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let alpha = Float(pixels[offset + 3]) / 255
                if alpha > 0 {
                    let encodedRGB = SIMD3<Float>(
                        min((Float(pixels[offset]) / 255) / alpha, 1),
                        min((Float(pixels[offset + 1]) / 255) / alpha, 1),
                        min((Float(pixels[offset + 2]) / 255) / alpha, 1)
                    )
                    let linearRGB = SIMD3<Float>(
                        ColorConversion.sRGBDecode(encodedRGB.x),
                        ColorConversion.sRGBDecode(encodedRGB.y),
                        ColorConversion.sRGBDecode(encodedRGB.z)
                    )
                    linearSum += linearRGB * alpha
                    alphaSum += alpha
                }
                count += 1
            }
        }

        let linearRGB = alphaSum > 0 ? linearSum / alphaSum : SIMD3<Float>(0, 0, 0)
        return SampledLinearRGB(linearRGB: linearRGB, alpha: alphaSum / count)
    }
}
