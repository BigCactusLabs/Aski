import Aski
import Foundation

/// Temporal-stability metrics over a materialized frame sequence, mapped onto
/// the two axes the engine animates. Glyph-churn is the discrete flicker proxy;
/// alpha-churn is the continuous smoothness proxy. No color-churn: color is
/// invariant per frame.
public struct FlickerMetrics: Equatable, Sendable {
    public let meanGlyphChurn: Double
    public let maxGlyphChurn: Double
    public let meanAlphaChurn: Double
    public let maxAlphaChurn: Double

    public init(meanGlyphChurn: Double, maxGlyphChurn: Double, meanAlphaChurn: Double, maxAlphaChurn: Double) {
        self.meanGlyphChurn = meanGlyphChurn
        self.maxGlyphChurn = maxGlyphChurn
        self.meanAlphaChurn = meanAlphaChurn
        self.maxAlphaChurn = maxAlphaChurn
    }

    /// Returns all-zero metrics for fewer than two frames. Compares cells over
    /// the overlapping rectangle when frame dimensions differ.
    public static func compute(frames: [ASCIIGrid]) -> FlickerMetrics {
        guard frames.count >= 2 else {
            return FlickerMetrics(meanGlyphChurn: 0, maxGlyphChurn: 0, meanAlphaChurn: 0, maxAlphaChurn: 0)
        }
        var glyphChurns: [Double] = []
        var alphaChurns: [Double] = []
        for frameIndex in 1..<frames.count {
            let previous = frames[frameIndex - 1]
            let current = frames[frameIndex]
            var changed = 0
            var alphaDeltaSum = 0.0
            var count = 0
            for row in 0..<min(previous.rows, current.rows) {
                for column in 0..<min(previous.columns, current.columns) {
                    let before = previous.cells[row][column]
                    let after = current.cells[row][column]
                    if before.character != after.character { changed += 1 }
                    alphaDeltaSum += Double(abs(after.alpha - before.alpha))
                    count += 1
                }
            }
            let denominator = Double(max(1, count))
            glyphChurns.append(Double(changed) / denominator)
            alphaChurns.append(alphaDeltaSum / denominator)
        }
        return FlickerMetrics(
            meanGlyphChurn: mean(glyphChurns),
            maxGlyphChurn: glyphChurns.max() ?? 0,
            meanAlphaChurn: mean(alphaChurns),
            maxAlphaChurn: alphaChurns.max() ?? 0
        )
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}
