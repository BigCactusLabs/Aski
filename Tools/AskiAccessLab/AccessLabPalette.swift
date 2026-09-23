import Aski
import Foundation
import simd

public struct AccessLabPalette: ASCIIPalette, Sendable {
    public var id: String
    public var candidateID: String
    public var content: PaletteContent

    public var colors: [PaletteColor] {
        content.colors ?? []
    }

    public static let ansi16 = AccessLabPalette(
        id: "ansi16",
        candidateID: "default",
        content: BuiltInPalette.ansi16.content
    )

    public static let monochrome = AccessLabPalette(
        id: "monochrome",
        candidateID: "default",
        content: BuiltInPalette.monochrome.content
    )

    public static let accessibleANSI16V1 = AccessLabPalette(
        id: "accessible-ansi16-v1",
        candidateID: "generated",
        content: .fixed([
            PaletteColor(SIMD3<Float>(0.00, 0.00, 0.00), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.72, 0.11, 0.11), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.00, 0.48, 0.24), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.66, 0.45, 0.00), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.10, 0.23, 0.72), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.53, 0.18, 0.66), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.00, 0.47, 0.58), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.77, 0.77, 0.77), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.43, 0.43, 0.43), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.93, 0.31, 0.24), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.22, 0.68, 0.38), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.91, 0.69, 0.16), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.30, 0.51, 0.92), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.74, 0.35, 0.86), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.28, 0.72, 0.78), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(1.00, 1.00, 1.00), colorSpace: .sRGB),
        ])
    )

    public static let all: [AccessLabPalette] = [
        .ansi16,
        .monochrome,
        .accessibleANSI16V1,
    ]
}
