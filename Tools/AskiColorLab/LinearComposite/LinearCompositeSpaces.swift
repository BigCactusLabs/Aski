import Aski
import Foundation
import simd

/// Target gamut a fixture is declared in. Spec §Target Gamuts: fixtures are
/// declared in a single color space and the target gamut equals the
/// declaration — no cross-gamut conversion in this lab's scope.
public enum LinearCompositeSpaces {

    public enum TargetGamut: String, CaseIterable, Sendable {
        case sRGB
        case displayP3

        /// `target_gamut` / `fg_color_space` column value.
        public var csvLabel: String { rawValue }

        /// `policy_working_space` value for `encoded8bit` rows.
        public var encodedWorkingSpaceLabel: String { "encoded_\(rawValue)" }

        /// `policy_working_space` value for `linear8bit` / `linearFloat` rows.
        public var linearWorkingSpaceLabel: String { "linear_\(rawValue)" }

        /// `input_space` column value: `<fg_color_space>_encoded`.
        public var inputSpaceLabel: String { "\(rawValue)_encoded" }

        /// `output_space` column value: `<target_gamut>_encoded`.
        public var outputSpaceLabel: String { "\(rawValue)_encoded" }

        /// Linear-target-RGB → OKLab. Used by metrics to compute ΔEOK on the
        /// unpremultiplied `mapped_linear_rgb` triple.
        public var linearRGBToOKLab: (SIMD3<Float>) -> SIMD3<Float> {
            switch self {
            case .sRGB: return ColorConversion.linearSRGBToOKLAB
            case .displayP3: return ColorConversion.linearP3ToOKLAB
            }
        }
    }

    /// Encoded unit float → linear unit float. Spec §Target Gamuts: both sRGB
    /// and Display P3 share the sRGB-style transfer function.
    public static func transferDecode(_ value: Float) -> Float {
        ColorConversion.sRGBDecode(value)
    }

    /// Linear unit float → encoded unit float. Same shared transfer.
    public static func transferEncode(_ value: Float) -> Float {
        ColorConversion.sRGBEncode(value)
    }

    /// Channelwise `transferDecode`. Convenience for policy code.
    public static func transferDecode(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(transferDecode(rgb.x), transferDecode(rgb.y), transferDecode(rgb.z))
    }

    /// Channelwise `transferEncode`. Convenience for policy code.
    public static func transferEncode(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(transferEncode(rgb.x), transferEncode(rgb.y), transferEncode(rgb.z))
    }
}
