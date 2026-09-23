import Foundation
import Testing

@testable import AskiColorLab

/// A tiny synthetic corpus + score table for the ASKI-56 arbiter tests.
///
/// The pair-family construction (§2.1) is a pure function of the per-(source,
/// charset, arm) oracle means, so it can be exercised on a fabricated score
/// table with no images at all — which is the point: the family sizes and the
/// ladder geometry are the contract, not the pixels.
enum ArbiterTestSupport {

    /// Six sources, matching the protocol's "3 nasa-steerable-v1 + 3
    /// nasa-structure-v1" shape. The two repeated asset names across corpora are
    /// deliberate — the real corpora share two filenames, and a source identity
    /// that is not corpus-qualified would collapse them.
    static func sources() -> [Arbiter.SourceRef] {
        [
            .init(corpus: "nasa-steerable-v1", asset: "earth-limb-sunrise.png"),
            .init(corpus: "nasa-steerable-v1", asset: "sahara-dunes.png"),
            .init(corpus: "nasa-steerable-v1", asset: "vavilov-crater.png"),
            .init(corpus: "nasa-structure-v1", asset: "earth-limb-sunrise.png"),
            .init(corpus: "nasa-structure-v1", asset: "phoenix-night-grid.png"),
            .init(corpus: "nasa-structure-v1", asset: "vavilov-crater.png"),
        ]
    }

    /// A deterministic, spread-out score table: every candidate arm on every
    /// charset gets a distinct MAE and a SSIM that is deliberately NOT a
    /// monotone function of MAE, so the adversarial family has somewhere to
    /// find MAE-blind pairs.
    static func scoreTable(
        sources: [Arbiter.SourceRef],
        plan: Arbiter.FamilyPlan
    ) -> [Arbiter.ArmKey: [SelectionCeiling.Oracle: Double]] {
        var table: [Arbiter.ArmKey: [SelectionCeiling.Oracle: Double]] = [:]
        for (sourceIndex, source) in sources.enumerated() {
            for charset in [plan.gatingCharset, plan.denseCharset] {
                let arms = plan.candidateArms(charset: charset)
                for (armIndex, arm) in arms.enumerated() {
                    let base = 0.20 + 0.010 * Double(armIndex) + 0.001 * Double(sourceIndex)
                    // SSIM moves on a different, coprime cadence so |ΔSSIM| and
                    // |ΔMAE| do not co-vary.
                    let ssim =
                        0.30 + 0.011 * Double((armIndex * 7) % 13)
                        - 0.002 * Double(sourceIndex)
                    table[Arbiter.ArmKey(source: source, charset: charset, arm: .init(arm))] = [
                        .mae: base,
                        .rmse: base * 1.06,
                        .ssim: ssim,
                        .gmsd: 0.19 + 0.003 * Double((armIndex * 5) % 11),
                        .haarPSI: 0.38 - 0.002 * Double(armIndex),
                    ]
                }
            }
        }
        // Arm F is the huge-margin validation baseline: the protocol's V family
        // expects F to beat production/inverted by a MAE ratio of roughly 0.47,
        // so the synthetic table has to reproduce that separation or the
        // ladder's top rung is fiction.
        for source in sources {
            for charset in [plan.gatingCharset, plan.denseCharset] {
                let floorKey = Arbiter.ArmKey(
                    source: source, charset: charset, arm: .init(.floor))
                let productionKey = Arbiter.ArmKey(
                    source: source, charset: charset,
                    arm: .init(Arbiter.ConverterArm.productionInverted))
                if let production = table[productionKey]?[.mae] {
                    table[floorKey]?[.mae] = production * 0.47
                }
            }
        }
        return table
    }

    /// Fails if `text` mentions anything the rater must not see for `pair`.
    /// The single-letter arm labels (`P`, `F`, `T`, `K`) are excluded from the
    /// substring sweep — `pair-001` contains a `p`, so a one-character needle
    /// would fire on the coded ID itself. The coded-form equality assertions in
    /// the blinding suite are what pin those; this sweep catches the leaks a
    /// substring CAN detect: charset, corpus, asset stem, and the multi-letter
    /// arm labels.
    static func expectNoIdentity(_ text: String, pair: Arbiter.Pair) {
        var forbidden = [
            pair.charset,
            pair.source.corpus,
            pair.source.asset,
            String(pair.source.asset.split(separator: ".").first ?? ""),
        ]
        forbidden += [pair.armA.name, pair.armB.name].filter { $0.count >= 3 }
        let haystack = text.lowercased()
        for needle in forbidden where needle.count >= 3 {
            #expect(
                !haystack.contains(needle.lowercased()),
                "rater-visible text leaked '\(needle)': \(text)"
            )
        }
    }
}
