import Aski
import Foundation
import simd

/// One scored cell of the composited-cell perceptual oracle.
///
/// The thesis: the eye sees the *area-toned composite* of glyph ink over
/// background — `k·FG + (1−k)·BG` in linear light — not the raw cell average.
/// Each row recomposites a rendered `ASCIICell` and scores it against the
/// source-cell appearance. Fidelity metrics are **errors** (lower = better;
/// more colors → lower error).
public struct OracleRow: Sendable, Equatable {
    public var schemaVersion: String  // "1"
    public var command: String
    public var askiGitSHA: String
    public var fixtureID: String
    public var paletteID: String  // "monochrome" | "ansi16" | "fullColor"
    public var row: Int
    public var col: Int
    public var character: String  // single grapheme as String
    public var inkFraction: Float  // k in 0...1
    public var inkModel: String  // "relative_ramp" (first-cut)
    public var fgHex: String  // "#RRGGBB" encoded sRGB
    public var bgHex: String
    public var perceivedHex: String  // recomposited, re-encoded sRGB
    public var sourceHex: String  // source-cell aggregate, re-encoded sRGB
    public var deficiency: String  // "none" in Phase 0
    public var lFidelity: Double  // |perceived.L − source.L|  (error; lower=better)
    public var chromaFidelity: Double  // |chroma(perceived) − chroma(source)|
    public var oklabDelta: Double  // simd_length(perceivedOKLab − sourceOKLab)

    public init(
        schemaVersion: String,
        command: String,
        askiGitSHA: String,
        fixtureID: String,
        paletteID: String,
        row: Int,
        col: Int,
        character: String,
        inkFraction: Float,
        inkModel: String,
        fgHex: String,
        bgHex: String,
        perceivedHex: String,
        sourceHex: String,
        deficiency: String,
        lFidelity: Double,
        chromaFidelity: Double,
        oklabDelta: Double
    ) {
        self.schemaVersion = schemaVersion
        self.command = command
        self.askiGitSHA = askiGitSHA
        self.fixtureID = fixtureID
        self.paletteID = paletteID
        self.row = row
        self.col = col
        self.character = character
        self.inkFraction = inkFraction
        self.inkModel = inkModel
        self.fgHex = fgHex
        self.bgHex = bgHex
        self.perceivedHex = perceivedHex
        self.sourceHex = sourceHex
        self.deficiency = deficiency
        self.lFidelity = lFidelity
        self.chromaFidelity = chromaFidelity
        self.oklabDelta = oklabDelta
    }

    /// All-zero / empty row so later gate tests can construct rows cheaply.
    public static let zero = OracleRow(
        schemaVersion: "",
        command: "",
        askiGitSHA: "",
        fixtureID: "",
        paletteID: "",
        row: 0,
        col: 0,
        character: "",
        inkFraction: 0,
        inkModel: "",
        fgHex: "",
        bgHex: "",
        perceivedHex: "",
        sourceHex: "",
        deficiency: "",
        lFidelity: 0,
        chromaFidelity: 0,
        oklabDelta: 0
    )
}

/// The composited-cell oracle math.
///
/// All blending happens in **linear light**: encoded display colors are decoded
/// to linear via `ColorConversion.sRGBDecode`, mixed by ink fraction `k`, then
/// (for OKLab / hex) matrixed and re-encoded. ΔE is computed directly on OKLab
/// vectors — do not route through `AccessScoring.oklabDelta`, which expects
/// encoded sRGB and would double-convert.
public enum DecolorOracle {
    /// Area-tone composite: `k·linear(FG) + (1−k)·linear(BG)` in **linear light**.
    /// Inputs are encoded-sRGB display colors (the `ASCIICell.displayColor` space).
    public static func composite(
        fgEncoded: SIMD3<Float>,
        bgEncoded: SIMD3<Float>,
        inkFraction k: Float
    ) -> SIMD3<Float> {
        let linFG = decode(fgEncoded)
        let linBG = decode(bgEncoded)
        return k * linFG + (1 - k) * linBG
    }

    /// Linear sRGB → OKLab.
    public static func oklab(linearRGB: SIMD3<Float>) -> SIMD3<Float> {
        ColorConversion.linearSRGBToOKLAB(linearRGB)
    }

    /// OKLab chroma = hypot(a, b).
    public static func chroma(oklab: SIMD3<Float>) -> Float {
        Float(hypot(Double(oklab.y), Double(oklab.z)))
    }

    /// `#RRGGBB` from already-encoded sRGB components in `0…1`.
    public static func hex(encoded rgb: SIMD3<Float>) -> String {
        func byte(_ v: Float) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.x), byte(rgb.y), byte(rgb.z))
    }

    /// `#RRGGBB` from linear sRGB (encode the transfer function, then format).
    public static func hex(linear rgb: SIMD3<Float>) -> String {
        hex(encoded: encode(rgb))
    }

    /// The three fidelity metrics, all as `Double` errors (lower = better).
    public static func fidelity(
        perceivedOKLab: SIMD3<Float>,
        sourceOKLab: SIMD3<Float>
    ) -> (l: Double, chroma: Double, delta: Double) {
        let l = abs(Double(perceivedOKLab.x) - Double(sourceOKLab.x))
        let chromaError = abs(Double(chroma(oklab: perceivedOKLab)) - Double(chroma(oklab: sourceOKLab)))
        let delta = Double(simd_length(perceivedOKLab - sourceOKLab))
        return (l, chromaError, delta)
    }

    // MARK: - Channel transfer helpers

    private static func decode(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            ColorConversion.sRGBDecode(rgb.x),
            ColorConversion.sRGBDecode(rgb.y),
            ColorConversion.sRGBDecode(rgb.z)
        )
    }

    private static func encode(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            ColorConversion.sRGBEncode(rgb.x),
            ColorConversion.sRGBEncode(rgb.y),
            ColorConversion.sRGBEncode(rgb.z)
        )
    }
}
