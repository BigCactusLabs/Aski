import Aski
import Foundation
import simd

public enum AccessSurface: String, Sendable {
    case palette
    case renderedGrid = "rendered_grid"
}

public enum AccessComparisonRole: String, Sendable {
    case colorOnBlack = "color_on_black"
    case colorOnWhite = "color_on_white"
    case palettePair = "palette_pair"
    case renderedAdjacentCells = "rendered_adjacent_cells"
}

public struct AccessSample: Sendable {
    public var sampleID: String
    public var comparisonRole: AccessComparisonRole
    public var surface: AccessSurface
    public var paletteID: String
    public var candidateID: String
    public var fixtureID: String
    public var sampleA: String
    public var sampleB: String
    public var encodedA: SIMD3<Float>
    public var encodedB: SIMD3<Float>
    public var brightnessDelta: Double

    public init(
        sampleID: String,
        comparisonRole: AccessComparisonRole,
        surface: AccessSurface,
        paletteID: String,
        candidateID: String,
        fixtureID: String,
        sampleA: String,
        sampleB: String,
        encodedA: SIMD3<Float>,
        encodedB: SIMD3<Float>,
        brightnessDelta: Double
    ) {
        self.sampleID = sampleID
        self.comparisonRole = comparisonRole
        self.surface = surface
        self.paletteID = paletteID
        self.candidateID = candidateID
        self.fixtureID = fixtureID
        self.sampleA = sampleA
        self.sampleB = sampleB
        self.encodedA = encodedA
        self.encodedB = encodedB
        self.brightnessDelta = brightnessDelta
    }
}

public struct AccessScoreRow: Sendable {
    public var schemaVersion: String
    public var command: String
    public var askiGitSHA: String
    public var sampleID: String
    public var comparisonRole: String
    public var surface: String
    public var paletteID: String
    public var candidateID: String
    public var fixtureID: String
    public var deficiency: String
    public var severity: String
    public var modelID: String
    public var sampleA: String
    public var sampleB: String
    public var sourceAHex: String
    public var sourceBHex: String
    public var simulatedAHex: String
    public var simulatedBHex: String
    public var wcagContrast: Double
    public var oklabDelta: Double
    public var brightnessDelta: Double
    public var confusionFlag: Bool
    public var luminanceThresholdMet: Bool

    public static var example: AccessScoreRow {
        AccessScoreRow(
            schemaVersion: "1",
            command: "swift run AskiAccessLab audit --output-dir /tmp/aski-access",
            askiGitSHA: "example-sha",
            sampleID: "palette-ansi16-red-black",
            comparisonRole: AccessComparisonRole.colorOnBlack.rawValue,
            surface: AccessSurface.palette.rawValue,
            paletteID: "ansi16",
            candidateID: "default",
            fixtureID: "palette",
            deficiency: ColorVisionDeficiency.deuteranopia.rawValue,
            severity: CVDModel.severity,
            modelID: CVDModel.modelID,
            sampleA: "red",
            sampleB: "black",
            sourceAHex: "#FF0000",
            sourceBHex: "#000000",
            simulatedAHex: "#9D8700",
            simulatedBHex: "#000000",
            wcagContrast: 6.000000,
            oklabDelta: 0.500000,
            brightnessDelta: 1.000000,
            confusionFlag: false,
            luminanceThresholdMet: true
        )
    }
}

public enum AccessScoring {
    public static let minimumOKLabDelta = 0.02
    public static let minimumWCAGContrast = 3.0

    public static func score(
        sample: AccessSample,
        deficiency: ColorVisionDeficiency
    ) -> AccessScoreRow {
        let simulatedA = CVDModel.simulateEncodedSRGB(sample.encodedA, deficiency: deficiency)
        let simulatedB = CVDModel.simulateEncodedSRGB(sample.encodedB, deficiency: deficiency)
        let contrast = wcagContrast(encodedA: simulatedA, encodedB: simulatedB)
        let delta = oklabDelta(encodedA: simulatedA, encodedB: simulatedB)

        return AccessScoreRow(
            schemaVersion: "1",
            command: "",
            askiGitSHA: "",
            sampleID: sample.sampleID,
            comparisonRole: sample.comparisonRole.rawValue,
            surface: sample.surface.rawValue,
            paletteID: sample.paletteID,
            candidateID: sample.candidateID,
            fixtureID: sample.fixtureID,
            deficiency: deficiency.rawValue,
            severity: CVDModel.severity,
            modelID: CVDModel.modelID,
            sampleA: sample.sampleA,
            sampleB: sample.sampleB,
            sourceAHex: hex(sample.encodedA),
            sourceBHex: hex(sample.encodedB),
            simulatedAHex: hex(simulatedA),
            simulatedBHex: hex(simulatedB),
            wcagContrast: contrast,
            oklabDelta: delta,
            brightnessDelta: sample.brightnessDelta,
            confusionFlag: delta < minimumOKLabDelta,
            luminanceThresholdMet: contrast >= minimumWCAGContrast
        )
    }

    public static func wcagContrast(
        encodedA: SIMD3<Float>,
        encodedB: SIMD3<Float>
    ) -> Double {
        let luminanceA = relativeLuminance(encodedSRGB: encodedA)
        let luminanceB = relativeLuminance(encodedSRGB: encodedB)
        let lighter = max(luminanceA, luminanceB)
        let darker = min(luminanceA, luminanceB)
        return Double((lighter + 0.05) / (darker + 0.05))
    }

    public static func oklabDelta(
        encodedA: SIMD3<Float>,
        encodedB: SIMD3<Float>
    ) -> Double {
        let labA = ColorConversion.linearSRGBToOKLAB(CVDModel.linearizeEncodedSRGB(encodedA))
        let labB = ColorConversion.linearSRGBToOKLAB(CVDModel.linearizeEncodedSRGB(encodedB))
        return Double(simd_length(labA - labB))
    }

    public static func relativeLuminance(encodedSRGB: SIMD3<Float>) -> Float {
        let linear = CVDModel.linearizeEncodedSRGB(encodedSRGB)
        return 0.2126 * linear.x + 0.7152 * linear.y + 0.0722 * linear.z
    }

    public static func hex(_ encoded: SIMD3<Float>) -> String {
        let red = byte(encoded.x)
        let green = byte(encoded.y)
        let blue = byte(encoded.z)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func byte(_ component: Float) -> Int {
        Int(round(CVDModel.clamp(component) * 255))
    }
}
