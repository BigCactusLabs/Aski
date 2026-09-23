import CoreGraphics
import CoreImage
import os

internal enum BlendModeMapping {
    private static let log = OSLog(subsystem: "com.bigcactuslabs.aski", category: "Effects")

    static func kernel(for mode: CGBlendMode) -> CIBlendKernel? {
        switch mode {
        case .normal: return .sourceOver
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .darken: return .darken
        case .lighten: return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .difference: return .difference
        case .exclusion: return .exclusion
        case .hue: return .hue
        case .saturation: return .saturation
        case .color: return .color
        case .luminosity: return .luminosity

        case .copy: return .source
        case .clear: return .clear
        case .sourceIn: return .sourceIn
        case .sourceOut: return .sourceOut
        case .sourceAtop: return .sourceAtop
        case .destinationOver: return .destinationOver
        case .destinationIn: return .destinationIn
        case .destinationOut: return .destinationOut
        case .destinationAtop: return .destinationAtop
        case .xor: return .exclusiveOr

        case .plusLighter: return .componentAdd
        case .plusDarker: return .linearBurn

        @unknown default:
            os_log(
                "BlendModeMapping: unknown CGBlendMode rawValue=%d, falling back to .sourceOver",
                log: log,
                type: .info,
                mode.rawValue
            )
            return .sourceOver
        }
    }

    static func isKnown(_ mode: CGBlendMode) -> Bool {
        switch mode {
        case .normal, .multiply, .screen, .overlay, .darken, .lighten,
            .colorDodge, .colorBurn, .softLight, .hardLight,
            .difference, .exclusion, .hue, .saturation, .color, .luminosity,
            .copy, .clear, .sourceIn, .sourceOut, .sourceAtop,
            .destinationOver, .destinationIn, .destinationOut, .destinationAtop, .xor,
            .plusLighter, .plusDarker:
            return true
        @unknown default:
            return false
        }
    }
}
