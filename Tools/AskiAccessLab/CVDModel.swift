import Aski
import Foundation
import simd

public enum ColorVisionDeficiency: String, CaseIterable, Sendable {
    case protanopia
    case deuteranopia
    case tritanopia
}

public enum CVDModel {
    public static let modelID = "brettel1997_dichromacy_srgb"
    public static let severity = "1.0"

    public static func simulateEncodedSRGB(
        _ encoded: SIMD3<Float>,
        deficiency: ColorVisionDeficiency
    ) -> SIMD3<Float> {
        let rgb = SIMD3<Float>(
            ColorConversion.sRGBDecode(clamp(encoded.x)),
            ColorConversion.sRGBDecode(clamp(encoded.y)),
            ColorConversion.sRGBDecode(clamp(encoded.z))
        )
        let params = BrettelParams.params(for: deficiency)
        let plane = simd_dot(rgb, params.separationPlaneNormalInRGB) >= 0 ? params.rgbCvdFromRGB1 : params.rgbCvdFromRGB2
        let simulatedLinear = plane * rgb
        return SIMD3<Float>(
            ColorConversion.sRGBEncode(clamp(simulatedLinear.x)),
            ColorConversion.sRGBEncode(clamp(simulatedLinear.y)),
            ColorConversion.sRGBEncode(clamp(simulatedLinear.z))
        )
    }

    public static func linearizeEncodedSRGB(_ encoded: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            ColorConversion.sRGBDecode(clamp(encoded.x)),
            ColorConversion.sRGBDecode(clamp(encoded.y)),
            ColorConversion.sRGBDecode(clamp(encoded.z))
        )
    }

    public static func clamp(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}

private struct BrettelParams: Sendable {
    var rgbCvdFromRGB1: simd_float3x3
    var rgbCvdFromRGB2: simd_float3x3
    var separationPlaneNormalInRGB: SIMD3<Float>

    static func params(for deficiency: ColorVisionDeficiency) -> BrettelParams {
        switch deficiency {
        case .protanopia:
            BrettelParams(
                rgbCvdFromRGB1: simd_float3x3(rows: [
                    SIMD3<Float>(0.14980, 1.19548, -0.34528),
                    SIMD3<Float>(0.10764, 0.84864, 0.04372),
                    SIMD3<Float>(0.00384, -0.00540, 1.00156),
                ]),
                rgbCvdFromRGB2: simd_float3x3(rows: [
                    SIMD3<Float>(0.14570, 1.16172, -0.30742),
                    SIMD3<Float>(0.10816, 0.85291, 0.03892),
                    SIMD3<Float>(0.00386, -0.00524, 1.00139),
                ]),
                separationPlaneNormalInRGB: SIMD3<Float>(0.00048, 0.00393, -0.00441)
            )
        case .deuteranopia:
            BrettelParams(
                rgbCvdFromRGB1: simd_float3x3(rows: [
                    SIMD3<Float>(0.36477, 0.86381, -0.22858),
                    SIMD3<Float>(0.26294, 0.64245, 0.09462),
                    SIMD3<Float>(-0.02006, 0.02728, 0.99278),
                ]),
                rgbCvdFromRGB2: simd_float3x3(rows: [
                    SIMD3<Float>(0.37298, 0.88166, -0.25464),
                    SIMD3<Float>(0.25954, 0.63506, 0.10540),
                    SIMD3<Float>(-0.01980, 0.02784, 0.99196),
                ]),
                separationPlaneNormalInRGB: SIMD3<Float>(-0.00281, -0.00611, 0.00892)
            )
        case .tritanopia:
            BrettelParams(
                rgbCvdFromRGB1: simd_float3x3(rows: [
                    SIMD3<Float>(1.01277, 0.13548, -0.14826),
                    SIMD3<Float>(-0.01243, 0.86812, 0.14431),
                    SIMD3<Float>(0.07589, 0.80500, 0.11911),
                ]),
                rgbCvdFromRGB2: simd_float3x3(rows: [
                    SIMD3<Float>(0.93678, 0.18979, -0.12657),
                    SIMD3<Float>(0.06154, 0.81526, 0.12320),
                    SIMD3<Float>(-0.37562, 1.12767, 0.24796),
                ]),
                separationPlaneNormalInRGB: SIMD3<Float>(0.03901, -0.02788, -0.01113)
            )
        }
    }
}
