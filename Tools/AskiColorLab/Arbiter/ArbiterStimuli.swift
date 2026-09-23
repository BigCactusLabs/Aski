import AskiToolSupport
import CoreGraphics
import CoreText
import Foundation

@_spi(AskiResearch) import Aski

extension Arbiter {

    /// ASKI-56 §2.1, `arbiter stimuli`.
    ///
    /// Materializes each pair's blinded triplet from the real converter geometry
    /// and the real candidate pool, renders both sides through the SAME path
    /// production output takes — a whole grid through `ASCIIGrid.renderImage`,
    /// never per-glyph rasters, because `GlyphRaster`'s bounds-centering erases
    /// the position distinctions the eye is being asked about (decisive-rule §7)
    /// — and writes the identity to `key.json` and nowhere else.
    enum Stimuli {

        /// The rendering regime. Fixed, because a pair whose two sides were
        /// rendered at different sizes or backgrounds is not a comparison of
        /// glyph selection.
        static let renderScale: CGFloat = 1
        static let fontPointSize: CGFloat = 14
        /// Faithful aspect — the shipping default for `aski render`.
        static let preserveSourceAspect = true

        static func font() -> ASCIIFont { .courierPrime(size: fontPointSize) }

        static var backgroundColor: CGColor {
            CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        }

        static var labelColor: CGColor {
            CGColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1)
        }

        // MARK: - Rater-visible naming (§3)

        /// Everything the rater can open for one pair. Coded IDs only: no arm,
        /// no charset, no source, no metric.
        static func raterVisibleFilenames(for pair: Pair) -> [String] {
            [
                "\(pair.id)-ref.png", "\(pair.id)-left.png", "\(pair.id)-right.png",
                "sheet/\(pair.id).png",
            ]
        }

        /// The composite sheet's caption. The coded pair ID, full stop.
        static func sheetLabel(for pair: Pair) -> String { pair.id }

        /// The human leg's answer sheet: `pairID, choice ∈ {L, R, tie}`, with
        /// the choice cell blank. Carries no family letter — knowing a pair is a
        /// V pair tells the rater the margin is huge.
        static func answersTemplateCSV(_ pairs: [Pair]) -> String {
            (["pairID,choice"] + pairs.map { "\($0.id)," }).joined(separator: "\n") + "\n"
        }

        // MARK: - Rendering

        /// Render one arm's grid at the fixed regime.
        static func render(grid: ASCIIGrid) -> CGImage {
            grid.renderImage(
                font: font(), backgroundColor: backgroundColor, scale: renderScale,
                preserveSourceAspect: preserveSourceAspect)
        }

        /// §2.1 step 3: the reference is the source photo scaled to the same
        /// pixel size as the renders, so the three images in a triplet are
        /// directly comparable at a glance and no side is advantaged by size.
        static func reference(_ image: CGImage, width: Int, height: Int) -> CGImage? {
            guard width > 0, height > 0 else { return nil }
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.interpolationQuality = .high
            context.setFillColor(backgroundColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }

        /// The `sheet/` composite: reference above, the two renders below,
        /// captioned with the coded pair ID only.
        static func sheet(
            reference: CGImage, left: CGImage, right: CGImage, label: String
        ) -> CGImage? {
            let padding = 20
            let captionHeight = 26
            let panelWidth = max(left.width, right.width)
            let panelHeight = max(left.height, right.height)
            let referenceHeight = panelHeight
            let referenceWidth =
                max(
                    1,
                    Int(
                        (Double(reference.width) / Double(max(1, reference.height))
                            * Double(referenceHeight)).rounded()))

            let width = max(referenceWidth + 2 * padding, 2 * panelWidth + 3 * padding)
            let height = referenceHeight + panelHeight + captionHeight + 4 * padding
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.setFillColor(backgroundColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Origin is bottom-left; lay out top-down.
            let referenceY = height - padding - referenceHeight
            context.draw(
                reference,
                in: CGRect(
                    x: (width - referenceWidth) / 2, y: referenceY,
                    width: referenceWidth, height: referenceHeight))

            let panelY = referenceY - padding - panelHeight
            context.draw(
                left,
                in: CGRect(x: padding, y: panelY, width: panelWidth, height: panelHeight))
            context.draw(
                right,
                in: CGRect(
                    x: 2 * padding + panelWidth, y: panelY, width: panelWidth,
                    height: panelHeight))

            let font = CTFontCreateWithName("Menlo" as CFString, 15, nil)
            drawText(
                label, font: font, color: labelColor,
                at: CGPoint(x: CGFloat(padding), y: CGFloat(panelY - padding - 6)),
                in: context)
            return context.makeImage()
        }

        private static func drawText(
            _ text: String, font: CTFont, color: CGColor, at point: CGPoint, in context: CGContext
        ) {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: attributes))
            context.textMatrix = .identity
            context.textPosition = point
            CTLineDraw(line, context)
        }

        // MARK: - Manifest

        struct Manifest: Sendable, Codable {
            let schemaVersion: String
            let protocolVersion: String
            let protocolNote: String
            let runner: String
            let date: String
            let askiGitSHA: String
            let command: String
            let seed: UInt64
            let columns: Int
            let oversample: Int
            let footprint: Int
            let gatingCharset: String
            let denseCharset: String
            let toneWeights: [Float]
            let topKs: [Int]
            let sources: [SourceRef]
            /// NOTE: the family budget is deliberately NOT here. The manifest is
            /// rater-visible, and publishing "6 validation pairs" is most of the
            /// way to finding them. It lives in `key.json` instead.
            let pairCount: Int
            let calibrationLadderRule: String
            let adversarialObjective: String

            enum CodingKeys: String, CodingKey {
                case schemaVersion = "schema_version"
                case protocolVersion = "protocol_version"
                case protocolNote = "protocol_note"
                case runner
                case date
                case askiGitSHA = "aski_git_sha"
                case command
                case seed
                case columns
                case oversample
                case footprint
                case gatingCharset = "gating_charset"
                case denseCharset = "dense_charset"
                case toneWeights = "tone_weights"
                case topKs = "top_ks"
                case sources
                case pairCount = "pair_count"
                case calibrationLadderRule = "calibration_ladder_rule"
                case adversarialObjective = "adversarial_objective"
            }
        }

        /// How the two seeded families were actually selected. Recorded in the
        /// manifest because §2.1 states the objectives in prose ("roughly even
        /// steps", "minimize |ΔMAE| while maximizing |ΔSSIM|") and a reader has
        /// to be able to see which mechanical reading produced these pairs.
        static let calibrationLadderRule =
            "equal-width bins over |delta MAE| from 0 to the largest available margin, one seeded "
            + "draw per bin, empty bins filled by the nearest unused candidate to the bin centre; "
            + "the dense charset gets its own ladder so the 'at least 4 on standard' clause is structural"
        static let adversarialObjective =
            "rank sum of (ascending |delta MAE|) and (descending |delta SSIM|) over the unused "
            + "candidate pool; ranks rather than a ratio because the two quantities are in "
            + "incomparable units and any exchange rate between them would be an unregistered parameter"
    }
}
