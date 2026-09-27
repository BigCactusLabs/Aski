import AskiToolSupport
import CoreGraphics
import Foundation
import simd

@_spi(AskiResearch) import Aski

/// Measures how often the log-polar pick is decided by the candidate's own norm
/// rather than by the cell (ASKI-79 AC#1 mechanism, ASKI-80 AC#2).
///
/// The matcher scores `d(q, g) = |q − g|² = |q|² + |g|² − 2 q·g` over the
/// brightness pool. When `q·g == 0` for every non-blank pooled candidate, the
/// cell term `|q|²` is common to all of them and the pick reduces to the pooled
/// glyph with the smallest `|g|²` — the zero-norm blank whenever the pool admits
/// it. This readout counts those cells per fixture, charset and column count,
/// using the matcher's own query (`cellQueryDescriptors`) and its own pool
/// (`rankedCandidateIndices`), so nothing about the selector is re-derived.
///
/// **Why exact zero.** Descriptor and glyph bins are L1-normalized histogram
/// masses and never negative, so `q·g == 0` exactly when the two supports are
/// disjoint; a product of two admitted bin masses is far above `Float`'s
/// subnormal range and cannot round to zero. `minPositiveDot` records the
/// smallest non-zero `q·g` actually observed against a non-blank pooled
/// candidate, so the gap between "orthogonal" and "barely overlapping" is on
/// disk next to the share rather than assumed.
///
/// No oracle runs here, so the readout is cheap enough to cover every built-in
/// charset at wide column counts and on every corpus.
enum QueryOrthogonality {

    /// The label pooled rows carry in the `fixture` column.
    static let pooledLabel = "(pooled)"

    /// Every built-in character set, in `StandardCharacterSet+Builtins` order.
    static let allCharsets = [
        "standard", "minimal", "blocks", "dots", "lines", "diagonal", "cross", "diamond",
        "mixed", "braille",
    ]

    /// Reachable-glyph lists longer than this are reported as a count only.
    static let maxListedGlyphs = 16

    struct Row: Sendable {
        let corpus: String
        let fixture: String
        let charset: String
        let columns: Int
        let oversample: Int
        /// The resolved cell footprint, or `nil` on a pooled row whose fixtures
        /// resolved different footprints.
        let cellWidth: Int?
        let cellHeight: Int?
        let supportsShapeDescriptor: Bool
        let cells: Int
        let glyphs: Int
        let blankGlyphs: Int
        let queryBinsMedian: Double
        let queryBinsMax: Int
        /// Union of the bins any cell's query occupied — the reachable set.
        let reachableBins: [Int]
        let zeroQueryShare: Double
        /// Non-blank glyphs with any mass in `reachableBins`.
        let reachableGlyphs: [Character]
        /// Share of cells whose query is orthogonal to every non-blank pooled
        /// candidate: the pick is decided by `|g|²` alone.
        let orthogonalShare: Double
        /// Share of cells that are orthogonal AND rendered the blank.
        let orthogonalBlankShare: Double
        /// Among orthogonal cells, the share whose rendered pick is the pooled
        /// minimum-`|g|²` candidate under the matcher's tie order (brightness
        /// delta, then index). 1.0 confirms the mechanism; below 1.0 refutes it
        /// for the remainder.
        let minNormAgreement: Double
        /// Smallest non-zero `q·g` against a non-blank pooled candidate, or
        /// `nan` if every such product was zero.
        let minPositiveDot: Double
        let texture: PickTexture.Readout
        let gitSHA: String
        let shapeQueryPolarity: String
    }

    /// Per-scope counters. One for each fixture, one pooled per corpus.
    private struct Tally {
        var cells = 0
        var zeroQuery = 0
        var orthogonal = 0
        var orthogonalBlank = 0
        var minNormAgree = 0
        var binCounts: [Int: Int] = [:]
        var reachable = Set<Int>()
        var minPositiveDot = Float.infinity
        var texture = PickTexture.Accumulator()
        var footprints = Set<SIMD2<Int>>()
        var supportsShapeDescriptor = true
    }

    static func run(
        columns: [Int],
        oversamples: [Int],
        charsetNames: [String],
        corpora: [String?],
        gitSHA: String,
        shapeQueryPolarity: ShapeQueryPolarity = .inverted
    ) throws -> [Row] {
        var rows: [Row] = []
        let lanesPerCharacter = StandardCharacterSet.lanesPerCharacter
        for corpus in corpora {
            let fixtures = try SteerableBattery.naturals(corpusDirectory: corpus)
            let corpusName = SelectionCeiling.corpusLabel(corpus)
            for charsetName in charsetNames {
                let characterSet = try SelectionCeiling.characterSet(named: charsetName)
                let glyphs = characterSet.characters
                try SelectionCeiling.assertUniqueGlyphs(glyphs, charset: charsetName)
                let brightness = characterSet.brightnessValues
                let candidateLanes = characterSet.shapeVectorLanes
                let blank = PickTexture.zeroNormGlyphs(
                    candidateLanes: candidateLanes, lanesPerCharacter: lanesPerCharacter)
                let norms: [Float] = glyphs.indices.map { index in
                    var norm: Float = 0
                    for lane in 0..<lanesPerCharacter {
                        let value = candidateLanes[index * lanesPerCharacter + lane]
                        norm += simd_dot(value, value)
                    }
                    return norm
                }
                let indexOf = Dictionary(
                    uniqueKeysWithValues: glyphs.enumerated().map { ($0.element, $0.offset) })

                for columnCount in columns {
                    for oversample in oversamples {
                        var options = RenderingOptions.default
                        options.shapeQueryPolarity = shapeQueryPolarity
                        let converter = ASCIIConverter(
                            characterSet: characterSet,
                            palette: BuiltInPalette.monochrome,
                            options: options,
                            colorSpace: .sRGB,
                            oversample: oversample)
                        var pooled = Tally()

                        for fixture in fixtures {
                            guard
                                let queries = converter.cellQueryDescriptors(
                                    fixture.image, columns: columnCount),
                                let geometry = converter.samplingGeometry(
                                    fixture.image, columns: columnCount)
                            else { continue }
                            let pools = converter.rankedCandidateIndices(
                                fixture.image, columns: columnCount, limit: glyphs.count)
                            guard pools.count == queries.rows,
                                queries.grid.rows == queries.rows,
                                queries.grid.columns == queries.columns
                            else { continue }

                            var tally = Tally()
                            let footprint = SIMD2(geometry.cellWidth, geometry.cellHeight)
                            tally.footprints.insert(footprint)
                            pooled.footprints.insert(footprint)
                            tally.supportsShapeDescriptor = queries.supportsShapeDescriptor
                            pooled.supportsShapeDescriptor =
                                pooled.supportsShapeDescriptor && queries.supportsShapeDescriptor
                            var picks = [[Int?]](
                                repeating: [Int?](repeating: nil, count: queries.columns),
                                count: queries.rows)

                            for row in 0..<queries.rows {
                                guard pools[row].count == queries.columns else { continue }
                                for column in 0..<queries.columns {
                                    let pool = pools[row][column]
                                    guard
                                        let rendered = indexOf[
                                            queries.grid.cells[row][column].character],
                                        let first = pool.first, first == rendered
                                    else { continue }
                                    picks[row][column] = rendered
                                    let query = queries.lanes(row: row, column: column)
                                    let tone = queries.adjustedL(row: row, column: column)
                                    let cell = classify(
                                        query: query, tone: tone, pool: pool, pick: rendered,
                                        candidateLanes: candidateLanes, norms: norms,
                                        brightness: brightness, blank: blank)
                                    record(cell, pick: rendered, blank: blank, into: &tally)
                                    record(cell, pick: rendered, blank: blank, into: &pooled)
                                }
                            }
                            tally.texture.add(picks) { blank.contains($0) }
                            pooled.texture.add(picks) { blank.contains($0) }

                            rows.append(
                                makeRow(
                                    tally, corpus: corpusName, fixture: fixture.id,
                                    charset: charsetName, columns: columnCount,
                                    oversample: oversample, glyphs: glyphs, blank: blank,
                                    candidateLanes: candidateLanes, gitSHA: gitSHA,
                                    polarity: shapeQueryPolarity))
                        }
                        if fixtures.count > 1, pooled.cells > 0 {
                            rows.append(
                                makeRow(
                                    pooled, corpus: corpusName, fixture: pooledLabel,
                                    charset: charsetName, columns: columnCount,
                                    oversample: oversample, glyphs: glyphs, blank: blank,
                                    candidateLanes: candidateLanes, gitSHA: gitSHA,
                                    polarity: shapeQueryPolarity))
                        }
                    }
                }
            }
        }
        return rows
    }

    /// What one cell contributes, independent of which tally it lands in.
    struct CellClass: Sendable, Equatable {
        let occupiedBins: [Int]
        let orthogonal: Bool
        /// Only meaningful when `orthogonal`.
        let pickIsMinNorm: Bool
        /// Smallest non-zero `q·g` against a non-blank pooled candidate.
        let minPositiveDot: Float?
    }

    /// Classifies one cell. Pure, so the mechanism test can feed it by hand.
    ///
    /// `pool` is the matcher's brightness pool for the cell; `pick` is the glyph
    /// it rendered. The minimum-norm candidate is chosen under the matcher's own
    /// tie order after distance — brightness delta ascending, then index — so
    /// agreement is tested against the rule production would apply if `|g|²`
    /// were all that differed.
    static func classify(
        query: [SIMD4<Float>],
        tone: Float,
        pool: [Int],
        pick: Int,
        candidateLanes: [SIMD4<Float>],
        norms: [Float],
        brightness: [Float],
        blank: Set<Int>
    ) -> CellClass {
        let lanesPerCharacter = query.count
        var occupied: [Int] = []
        for lane in 0..<lanesPerCharacter {
            for component in 0..<4 where query[lane][component] > 0 {
                occupied.append(lane * 4 + component)
            }
        }
        var orthogonal = true
        var minPositive: Float?
        for candidate in pool where !blank.contains(candidate) {
            var dot: Float = 0
            for lane in 0..<lanesPerCharacter {
                dot += simd_dot(query[lane], candidateLanes[candidate * lanesPerCharacter + lane])
            }
            if dot != 0 {
                orthogonal = false
                minPositive = min(minPositive ?? .infinity, dot)
            }
        }
        var pickIsMinNorm = false
        if orthogonal, !pool.isEmpty {
            let best = pool.min { left, right in
                if norms[left] != norms[right] { return norms[left] < norms[right] }
                let leftDelta = abs(brightness[left] - tone)
                let rightDelta = abs(brightness[right] - tone)
                if leftDelta != rightDelta { return leftDelta < rightDelta }
                return left < right
            }
            pickIsMinNorm = best == pick
        }
        return CellClass(
            occupiedBins: occupied, orthogonal: orthogonal, pickIsMinNorm: pickIsMinNorm,
            minPositiveDot: minPositive)
    }

    private static func record(
        _ cell: CellClass, pick: Int, blank: Set<Int>, into tally: inout Tally
    ) {
        tally.cells += 1
        tally.binCounts[cell.occupiedBins.count, default: 0] += 1
        tally.reachable.formUnion(cell.occupiedBins)
        if cell.occupiedBins.isEmpty { tally.zeroQuery += 1 }
        if cell.orthogonal {
            tally.orthogonal += 1
            if blank.contains(pick) { tally.orthogonalBlank += 1 }
            if cell.pickIsMinNorm { tally.minNormAgree += 1 }
        }
        if let dot = cell.minPositiveDot { tally.minPositiveDot = min(tally.minPositiveDot, dot) }
    }

    /// Non-blank glyphs with any mass in `bins`.
    static func glyphsWithMass(
        in bins: Set<Int>,
        candidateLanes: [SIMD4<Float>],
        glyphCount: Int,
        blank: Set<Int>
    ) -> [Int] {
        let lanesPerCharacter = StandardCharacterSet.lanesPerCharacter
        return (0..<glyphCount).filter { index in
            guard !blank.contains(index) else { return false }
            return bins.contains { bin in
                candidateLanes[index * lanesPerCharacter + bin / 4][bin % 4] > 0
            }
        }
    }

    private static func makeRow(
        _ tally: Tally,
        corpus: String,
        fixture: String,
        charset: String,
        columns: Int,
        oversample: Int,
        glyphs: [Character],
        blank: Set<Int>,
        candidateLanes: [SIMD4<Float>],
        gitSHA: String,
        polarity: ShapeQueryPolarity
    ) -> Row {
        let cells = Double(tally.cells)
        func share(_ count: Int) -> Double { tally.cells > 0 ? Double(count) / cells : .nan }
        let footprint = tally.footprints.count == 1 ? tally.footprints.first : nil
        let reachableGlyphs = glyphsWithMass(
            in: tally.reachable, candidateLanes: candidateLanes, glyphCount: glyphs.count,
            blank: blank)
        return Row(
            corpus: corpus, fixture: fixture, charset: charset, columns: columns,
            oversample: oversample, cellWidth: footprint?.x, cellHeight: footprint?.y,
            supportsShapeDescriptor: tally.supportsShapeDescriptor,
            cells: tally.cells, glyphs: glyphs.count, blankGlyphs: blank.count,
            queryBinsMedian: PickTexture.nearestRankPercentile(tally.binCounts, percentile: 0.5),
            queryBinsMax: tally.binCounts.keys.max() ?? 0,
            reachableBins: tally.reachable.sorted(),
            zeroQueryShare: share(tally.zeroQuery),
            reachableGlyphs: reachableGlyphs.map { glyphs[$0] },
            orthogonalShare: share(tally.orthogonal),
            orthogonalBlankShare: share(tally.orthogonalBlank),
            minNormAgreement: tally.orthogonal > 0
                ? Double(tally.minNormAgree) / Double(tally.orthogonal) : .nan,
            minPositiveDot: tally.minPositiveDot.isFinite ? Double(tally.minPositiveDot) : .nan,
            texture: tally.texture.resolved(),
            gitSHA: gitSHA,
            shapeQueryPolarity: PolarityGate.label(polarity))
    }

    static let csvHeader =
        "corpus,fixture,charset,columns,oversample,cellWidth,cellHeight,supportsShapeDescriptor,"
        + "cells,glyphs,blankGlyphs,queryBinsMedian,queryBinsMax,reachableBins,zeroQueryShare,"
        + "reachableGlyphs,reachableGlyphList,orthogonalShare,orthogonalBlankShare,"
        + "minNormAgreement,minPositiveDot,glyphsUsed,blankShare,runMean,runP95,runMax,"
        + "run5Share,gitSHA,shapeQueryPolarity"

    static func csv(_ rows: [Row]) -> String {
        let trimmed = SelectionCeiling.trimmed
        var lines = [csvHeader]
        for row in rows {
            let listed =
                row.reachableGlyphs.count <= maxListedGlyphs
                ? String(row.reachableGlyphs) : ""
            let fields: [String] = [
                row.corpus, row.fixture, row.charset, String(row.columns),
                String(row.oversample),
                row.cellWidth.map(String.init) ?? "", row.cellHeight.map(String.init) ?? "",
                String(row.supportsShapeDescriptor), String(row.cells), String(row.glyphs),
                String(row.blankGlyphs), trimmed(row.queryBinsMedian), String(row.queryBinsMax),
                row.reachableBins.map(String.init).joined(separator: ";"),
                trimmed(row.zeroQueryShare), String(row.reachableGlyphs.count), listed,
                trimmed(row.orthogonalShare), trimmed(row.orthogonalBlankShare),
                trimmed(row.minNormAgreement), trimmed(row.minPositiveDot),
                String(row.texture.glyphsUsed), trimmed(row.texture.blankShare),
                trimmed(row.texture.runMean), trimmed(row.texture.runP95),
                String(row.texture.runMax), trimmed(row.texture.run5Share),
                row.gitSHA, row.shapeQueryPolarity,
            ]
            lines.append(fields.map(SelectionCeiling.escaped).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func format(_ rows: [Row]) -> String {
        var lines = [
            "# Query orthogonality (picks decided by |g|² alone)",
            "corpus | fixture | charset | cols | os | cell | cells | bins med/max | reachable | "
                + "reachGlyphs | orth% | orthBlank% | minNormAgree% | minPosDot | used | blank% | "
                + "runMean | runP95 | run5%",
        ]
        func percent(_ value: Double) -> String {
            value.isFinite ? String(format: "%.1f", value * 100) : "nan"
        }
        func number(_ value: Double) -> String {
            value.isFinite ? String(format: "%.2f", value) : "nan"
        }
        for row in rows {
            let cell = row.cellWidth.flatMap { w in row.cellHeight.map { "\(w)x\($0)" } } ?? "mixed"
            let listed =
                row.reachableGlyphs.count <= maxListedGlyphs
                ? "\(row.reachableGlyphs.count) \(String(row.reachableGlyphs))"
                : "\(row.reachableGlyphs.count)"
            lines.append(
                [
                    row.corpus, row.fixture, row.charset, String(row.columns),
                    String(row.oversample), cell, String(row.cells),
                    "\(number(row.queryBinsMedian))/\(row.queryBinsMax)",
                    row.reachableBins.map(String.init).joined(separator: ";"), listed,
                    percent(row.orthogonalShare), percent(row.orthogonalBlankShare),
                    percent(row.minNormAgreement),
                    row.minPositiveDot.isFinite
                        ? String(format: "%.4g", row.minPositiveDot) : "nan",
                    String(row.texture.glyphsUsed), percent(row.texture.blankShare),
                    number(row.texture.runMean), number(row.texture.runP95),
                    percent(row.texture.run5Share),
                ].joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }
}
