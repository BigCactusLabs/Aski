import AskiToolSupport
import CoreGraphics
import CryptoKit
import Dispatch
import Foundation

@_spi(AskiResearch) import Aski

/// ASKI-63's pre-registered comparison of direct target-width glyph rendering
/// against a linear-light supersample reduction. The rule lives in
/// `2026-09-01-aski63-target-width-rule.md`; this type records its fixed inputs
/// and applies its verdict without looking at a result-specific threshold.
enum TargetWidthGate {

    enum Fixture {
        case consumer(inputURL: URL)
        case corpus(pngURL: URL)

        var configuration: FixtureConfiguration {
            switch self {
            case .consumer:
                FixtureConfiguration(
                    id: "canyon-384",
                    source: "consumer",
                    columns: 384,
                    widths: [1166, 2332],
                    font: .system(size: 13.333333),
                    backgroundRGB: SIMD3<Float>(
                        Float(0x23) / 255,
                        Float(0x23) / 255,
                        Float(0x23) / 255
                    ),
                    backgroundHex: "#232323",
                    preserveSourceAspect: true
                )
            case .corpus:
                FixtureConfiguration(
                    id: "earth-limb-80",
                    source: "corpus",
                    columns: 80,
                    widths: [243, 600, 960],
                    font: .system(size: 12),
                    backgroundRGB: .zero,
                    backgroundHex: "#000000",
                    preserveSourceAspect: true
                )
            }
        }

        func makeGrid() throws -> ASCIIGrid {
            switch self {
            case .consumer(let inputURL):
                let image = try DemoImageIO.loadImage(at: inputURL.path)
                return DefaultConverter().animate(
                    image,
                    columns: configuration.columns,
                    options: AnimationOptions(
                        duration: 2,
                        seed: 0,
                        cycling: CyclingOptions(k: 4, speed: 1, intensity: 0.6, randomness: 0)
                    )
                ).baseGrid
            case .corpus(let pngURL):
                let image = try DemoImageIO.loadImage(at: pngURL.path)
                return DefaultConverter().convert(image, columns: configuration.columns)
            }
        }

        func consumerInputSHA256() throws -> String? {
            guard case .consumer(let inputURL) = self else { return nil }
            return try Self.sha256Hex(of: inputURL)
        }

        private static func sha256Hex(of url: URL) throws -> String {
            let digest = SHA256.hash(data: try Data(contentsOf: url))
            return digest.map { String(format: "%02x", $0) }.joined()
        }
    }

    struct FixtureConfiguration {
        let id: String
        let source: String
        let columns: Int
        let widths: [Int]
        let font: ASCIIFont
        let backgroundRGB: SIMD3<Float>
        let backgroundHex: String
        let preserveSourceAspect: Bool

        var backgroundColor: CGColor {
            CGColor(
                red: CGFloat(backgroundRGB.x),
                green: CGFloat(backgroundRGB.y),
                blue: CGFloat(backgroundRGB.z),
                alpha: 1
            )
        }
    }

    struct FixtureMetadata: Codable, Sendable, Equatable {
        let id: String
        let source: String
        let columns: Int
        let widths: [Int]
        let fontPointSize: Double
        let fontPostScriptName: String
        let backgroundHex: String
        let preserveSourceAspect: Bool

        init(configuration: FixtureConfiguration) {
            id = configuration.id
            source = configuration.source
            columns = configuration.columns
            widths = configuration.widths
            fontPointSize = Double(configuration.font.pointSize)
            fontPostScriptName = configuration.font.postScriptName
            backgroundHex = configuration.backgroundHex
            preserveSourceAspect = configuration.preserveSourceAspect
        }
    }

    enum Arm: String, Codable, Sendable, CaseIterable {
        case a = "A"
        case b = "B"

        var resample: TargetWidthResample {
            switch self {
            case .a: .direct
            case .b: .supersample(factor: 4)
            }
        }

        var filenameLabel: String { rawValue.lowercased() }
    }

    struct ArmRow: Codable, Sendable, Equatable {
        let fixtureID: String
        let arm: Arm
        let targetPixelWidth: Int
        let width: Int
        let height: Int
        let mae: Double?
        let gmsd: Double?
        let banding: Double?
        let bandingSwappedDelta: Double?
        let costMs: Double
        let dimensionsMatchReference: Bool
        let renderPNG: String?
        let probePNG: String?
    }

    struct ReferenceRow: Codable, Sendable, Equatable {
        let fixtureID: String
        let targetPixelWidth: Int
        let width: Int
        let height: Int
        let banding: Double?
        let costMs: Double
        let renderPNG: String?
        let probePNG: String?
    }

    struct FrozenBounds: Codable, Sendable, Equatable {
        let referenceBandingMaximum: Double
        let armBandingMaximum: Double
        let maeTie: Double
        let gmsdTie: Double
        let gmsdVeto: Double
        let cheapIfClose: Double
        let costRatio: Double
        let negativeControlTolerance: Double

        static let preRegistered = FrozenBounds(
            referenceBandingMaximum: 0.02,
            armBandingMaximum: 0.10,
            maeTie: 0.02,
            gmsdTie: 0.02,
            gmsdVeto: 0.05,
            cheapIfClose: 0.05,
            costRatio: 4,
            negativeControlTolerance: 0.02
        )
    }

    enum Verdict: Sendable, Equatable, Codable {
        case invalid(reason: String)
        case inconclusive(clause: String)
        case shipA(reason: String)
        case shipB(reason: String)

        private enum CodingKeys: String, CodingKey {
            case outcome
            case reason
        }

        private enum Outcome: String, Codable {
            case invalid = "INVALID"
            case inconclusive = "INCONCLUSIVE"
            case shipA = "SHIP-A"
            case shipB = "SHIP-B"
        }

        var outcome: String {
            switch self {
            case .invalid: Outcome.invalid.rawValue
            case .inconclusive: Outcome.inconclusive.rawValue
            case .shipA: Outcome.shipA.rawValue
            case .shipB: Outcome.shipB.rawValue
            }
        }

        var reason: String {
            switch self {
            case .invalid(let reason), .inconclusive(let reason), .shipA(let reason), .shipB(let reason):
                reason
            }
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let outcome = try container.decode(Outcome.self, forKey: .outcome)
            let reason = try container.decode(String.self, forKey: .reason)
            switch outcome {
            case .invalid: self = .invalid(reason: reason)
            case .inconclusive: self = .inconclusive(clause: reason)
            case .shipA: self = .shipA(reason: reason)
            case .shipB: self = .shipB(reason: reason)
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            let encodedOutcome: Outcome
            switch self {
            case .invalid: encodedOutcome = .invalid
            case .inconclusive: encodedOutcome = .inconclusive
            case .shipA: encodedOutcome = .shipA
            case .shipB: encodedOutcome = .shipB
            }
            try container.encode(encodedOutcome, forKey: .outcome)
            try container.encode(reason, forKey: .reason)
        }
    }

    struct Report: Codable, Sendable, Equatable {
        let schemaVersion: Int
        let gitSHA: String
        let partialFixtures: Bool
        let consumerInputSHA256: String?
        let fixtures: [FixtureMetadata]
        let armRows: [ArmRow]
        let referenceRows: [ReferenceRow]
        let frozenBounds: FrozenBounds
        /// The phase-1 test gate owns this byte-equivalence assertion. It is
        /// recorded here so the frozen section-6 ordering stays explicit in
        /// synthetic verdict tests and emitted reports.
        let equivalencePassed: Bool
        let invalidReasons: [String]
        var verdict: Verdict

        init(
            schemaVersion: Int = 1,
            gitSHA: String = "test",
            partialFixtures: Bool = false,
            consumerInputSHA256: String? = nil,
            fixtures: [FixtureMetadata],
            armRows: [ArmRow],
            referenceRows: [ReferenceRow],
            frozenBounds: FrozenBounds = .preRegistered,
            equivalencePassed: Bool = true,
            invalidReasons: [String] = [],
            verdict: Verdict = .inconclusive(clause: "not evaluated")
        ) {
            self.schemaVersion = schemaVersion
            self.gitSHA = gitSHA
            self.partialFixtures = partialFixtures
            self.consumerInputSHA256 = consumerInputSHA256
            self.fixtures = fixtures
            self.armRows = armRows
            self.referenceRows = referenceRows
            self.frozenBounds = frozenBounds
            self.equivalencePassed = equivalencePassed
            self.invalidReasons = invalidReasons
            self.verdict = verdict
        }
    }

    struct Evaluation {
        let armRows: [ArmRow]
        let referenceRows: [ReferenceRow]
        let invalidReasons: [String]
    }

    private struct TimedImage {
        let image: CGImage
        let costMs: Double
    }

    private struct CellKey: Hashable {
        let fixtureID: String
        let targetPixelWidth: Int

        var description: String { "\(fixtureID)@\(targetPixelWidth)" }
    }

    static func run(
        fixtures: [Fixture],
        gitSHA: String,
        repeats: Int,
        rendersDirectory: URL?
    ) throws -> Report {
        guard repeats > 0 else { throw GateError.invalidRepeats(repeats) }
        if let rendersDirectory {
            try FileManager.default.createDirectory(
                at: rendersDirectory,
                withIntermediateDirectories: true
            )
        }

        var metadata: [FixtureMetadata] = []
        var armRows: [ArmRow] = []
        var referenceRows: [ReferenceRow] = []
        var invalidReasons: [String] = []
        var consumerInputSHA256: String?

        for fixture in fixtures {
            let configuration = fixture.configuration
            let grid = try fixture.makeGrid()
            guard grid.columns == configuration.columns, grid.rows > 0 else {
                throw GateError.gridDoesNotMatchFixture(
                    id: configuration.id,
                    expectedColumns: configuration.columns,
                    actualColumns: grid.columns,
                    rows: grid.rows
                )
            }
            metadata.append(FixtureMetadata(configuration: configuration))
            if consumerInputSHA256 == nil {
                consumerInputSHA256 = try fixture.consumerInputSHA256()
            }
            let evaluation = try evaluate(
                grid: grid,
                configuration: configuration,
                repeats: repeats,
                rendersDirectory: rendersDirectory
            )
            armRows += evaluation.armRows
            referenceRows += evaluation.referenceRows
            invalidReasons += evaluation.invalidReasons
        }

        let partialFixtures = !fixtures.contains { fixture in
            if case .consumer = fixture { return true }
            return false
        }
        var report = Report(
            gitSHA: gitSHA,
            partialFixtures: partialFixtures,
            consumerInputSHA256: consumerInputSHA256,
            fixtures: metadata,
            armRows: armRows,
            referenceRows: referenceRows,
            invalidReasons: invalidReasons
        )
        report.verdict = verdict(report)
        return report
    }

    static func evaluate(
        grid: ASCIIGrid,
        configuration: FixtureConfiguration,
        repeats: Int,
        rendersDirectory: URL? = nil
    ) throws -> Evaluation {
        guard repeats > 0 else { throw GateError.invalidRepeats(repeats) }
        guard grid.columns == configuration.columns, grid.rows > 0 else {
            throw GateError.gridDoesNotMatchFixture(
                id: configuration.id,
                expectedColumns: configuration.columns,
                actualColumns: grid.columns,
                rows: grid.rows
            )
        }
        if let rendersDirectory {
            try FileManager.default.createDirectory(
                at: rendersDirectory,
                withIntermediateDirectories: true
            )
        }

        let probeGrid = makeProbeGrid(
            columns: grid.columns,
            rows: grid.rows,
            foreground: SIMD3<Float>(repeating: 1),
            colorSpace: grid.colorSpace,
            composition: grid.composition
        )
        let swappedProbeGrid = makeProbeGrid(
            columns: grid.columns,
            rows: grid.rows,
            foreground: configuration.backgroundRGB,
            colorSpace: grid.colorSpace,
            composition: grid.composition
        )
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

        var armRows: [ArmRow] = []
        var referenceRows: [ReferenceRow] = []
        var invalidReasons: [String] = []

        for targetPixelWidth in configuration.widths {
            let direct = renderAndMeasure(
                grid: grid,
                configuration: configuration,
                targetPixelWidth: targetPixelWidth,
                resample: .direct,
                repeats: repeats
            )
            let supersample = renderAndMeasure(
                grid: grid,
                configuration: configuration,
                targetPixelWidth: targetPixelWidth,
                resample: .supersample(factor: 4),
                repeats: repeats
            )
            let reference = renderAndMeasure(
                grid: grid,
                configuration: configuration,
                targetPixelWidth: targetPixelWidth,
                resample: .supersample(factor: 8),
                repeats: repeats
            )

            let directLuma = PolarityGate.luma(of: direct.image)
            let supersampleLuma = PolarityGate.luma(of: supersample.image)
            let referenceLuma = PolarityGate.luma(of: reference.image)
            let directMatches = dimensionsMatch(direct.image, reference.image)
            let supersampleMatches = dimensionsMatch(supersample.image, reference.image)
            if !directMatches {
                invalidReasons.append("\(configuration.id)@\(targetPixelWidth): A dimensions differ from reference")
            }
            if !supersampleMatches {
                invalidReasons.append("\(configuration.id)@\(targetPixelWidth): B dimensions differ from reference")
            }

            let directScores = scores(
                candidate: directLuma,
                reference: referenceLuma,
                dimensionsMatch: directMatches,
                invalidReasons: &invalidReasons,
                label: "\(configuration.id)@\(targetPixelWidth): A"
            )
            let supersampleScores = scores(
                candidate: supersampleLuma,
                reference: referenceLuma,
                dimensionsMatch: supersampleMatches,
                invalidReasons: &invalidReasons,
                label: "\(configuration.id)@\(targetPixelWidth): B"
            )

            let directProbe = render(
                grid: probeGrid,
                configuration: configuration,
                targetPixelWidth: targetPixelWidth,
                resample: .direct
            )
            let supersampleProbe = render(
                grid: probeGrid,
                configuration: configuration,
                targetPixelWidth: targetPixelWidth,
                resample: .supersample(factor: 4)
            )
            let referenceProbe = render(
                grid: probeGrid,
                configuration: configuration,
                targetPixelWidth: targetPixelWidth,
                resample: .supersample(factor: 8)
            )
            let directSwappedProbe = gridRender(
                swappedProbeGrid,
                font: configuration.font,
                backgroundColor: white,
                targetPixelWidth: targetPixelWidth,
                preserveSourceAspect: configuration.preserveSourceAspect,
                resample: .direct
            )
            let supersampleSwappedProbe = gridRender(
                swappedProbeGrid,
                font: configuration.font,
                backgroundColor: white,
                targetPixelWidth: targetPixelWidth,
                preserveSourceAspect: configuration.preserveSourceAspect,
                resample: .supersample(factor: 4)
            )

            let directBanding = banding(
                image: directProbe,
                columns: configuration.columns,
                useInkMass: true,
                invalidReasons: &invalidReasons,
                label: "\(configuration.id)@\(targetPixelWidth): A probe"
            )
            let supersampleBanding = banding(
                image: supersampleProbe,
                columns: configuration.columns,
                useInkMass: true,
                invalidReasons: &invalidReasons,
                label: "\(configuration.id)@\(targetPixelWidth): B probe"
            )
            let referenceBanding = banding(
                image: referenceProbe,
                columns: configuration.columns,
                useInkMass: true,
                invalidReasons: &invalidReasons,
                label: "\(configuration.id)@\(targetPixelWidth): reference probe"
            )
            let directSwappedBanding = banding(
                image: directSwappedProbe,
                columns: configuration.columns,
                useInkMass: false,
                invalidReasons: &invalidReasons,
                label: "\(configuration.id)@\(targetPixelWidth): A swapped probe"
            )
            let supersampleSwappedBanding = banding(
                image: supersampleSwappedProbe,
                columns: configuration.columns,
                useInkMass: false,
                invalidReasons: &invalidReasons,
                label: "\(configuration.id)@\(targetPixelWidth): B swapped probe"
            )

            let directPaths = try writeRenders(
                directory: rendersDirectory,
                fixtureID: configuration.id,
                targetPixelWidth: targetPixelWidth,
                label: Arm.a.filenameLabel,
                render: direct.image,
                probe: directProbe
            )
            let supersamplePaths = try writeRenders(
                directory: rendersDirectory,
                fixtureID: configuration.id,
                targetPixelWidth: targetPixelWidth,
                label: Arm.b.filenameLabel,
                render: supersample.image,
                probe: supersampleProbe
            )
            let referencePaths = try writeRenders(
                directory: rendersDirectory,
                fixtureID: configuration.id,
                targetPixelWidth: targetPixelWidth,
                label: "reference",
                render: reference.image,
                probe: referenceProbe
            )

            armRows.append(
                ArmRow(
                    fixtureID: configuration.id,
                    arm: .a,
                    targetPixelWidth: targetPixelWidth,
                    width: direct.image.width,
                    height: direct.image.height,
                    mae: directScores.mae,
                    gmsd: directScores.gmsd,
                    banding: directBanding,
                    bandingSwappedDelta: delta(directBanding, directSwappedBanding),
                    costMs: direct.costMs,
                    dimensionsMatchReference: directMatches,
                    renderPNG: directPaths.render,
                    probePNG: directPaths.probe
                )
            )
            armRows.append(
                ArmRow(
                    fixtureID: configuration.id,
                    arm: .b,
                    targetPixelWidth: targetPixelWidth,
                    width: supersample.image.width,
                    height: supersample.image.height,
                    mae: supersampleScores.mae,
                    gmsd: supersampleScores.gmsd,
                    banding: supersampleBanding,
                    bandingSwappedDelta: delta(supersampleBanding, supersampleSwappedBanding),
                    costMs: supersample.costMs,
                    dimensionsMatchReference: supersampleMatches,
                    renderPNG: supersamplePaths.render,
                    probePNG: supersamplePaths.probe
                )
            )
            referenceRows.append(
                ReferenceRow(
                    fixtureID: configuration.id,
                    targetPixelWidth: targetPixelWidth,
                    width: reference.image.width,
                    height: reference.image.height,
                    banding: referenceBanding,
                    costMs: reference.costMs,
                    renderPNG: referencePaths.render,
                    probePNG: referencePaths.probe
                )
            )
        }

        return Evaluation(
            armRows: armRows,
            referenceRows: referenceRows,
            invalidReasons: invalidReasons
        )
    }

    /// Applies section 6 of the frozen target-width rule. It uses report rows
    /// only, so tests can exercise every branch without running any fixture.
    static func verdict(_ report: Report) -> Verdict {
        let bounds = report.frozenBounds
        guard report.schemaVersion == 1 else {
            return .invalid(reason: "unsupported schema version \(report.schemaVersion)")
        }
        guard report.equivalencePassed else {
            return .invalid(reason: "section 1 exact-scale equivalence failed")
        }
        guard report.invalidReasons.isEmpty else {
            return .invalid(reason: report.invalidReasons.sorted().joined(separator: "; "))
        }

        let expected = expectedCells(report.fixtures)
        guard !expected.isEmpty else {
            return .invalid(reason: "no fixture-width cells were recorded")
        }

        let rows = rowsByCell(report.armRows, expected: expected)
        let references = referencesByCell(report.referenceRows, expected: expected)
        if let invalid = rows.invalidReason ?? references.invalidReason {
            return .invalid(reason: invalid)
        }
        guard let aRows = rows.rows[.a], let bRows = rows.rows[.b] else {
            return .invalid(reason: "both arm row sets are required")
        }

        for key in expected {
            guard let reference = references.rows[key] else {
                return .invalid(reason: "missing reference row for \(key.description)")
            }
            guard let referenceBanding = reference.banding, referenceBanding.isFinite else {
                return .invalid(reason: "missing reference banding for \(key.description)")
            }
            if referenceBanding > bounds.referenceBandingMaximum {
                return .invalid(
                    reason: "reference banding \(format(referenceBanding)) exceeds B_ref at \(key.description)"
                )
            }
            for (arm, row) in [(Arm.a, aRows[key]), (Arm.b, bRows[key])] {
                guard let row else {
                    return .invalid(reason: "missing \(arm.rawValue) row for \(key.description)")
                }
                guard
                    row.dimensionsMatchReference,
                    row.width == reference.width,
                    row.height == reference.height
                else {
                    return .invalid(reason: "\(arm.rawValue) dimensions differ from reference at \(key.description)")
                }
                guard
                    let mae = row.mae,
                    let gmsd = row.gmsd,
                    let banding = row.banding,
                    let swappedDelta = row.bandingSwappedDelta,
                    mae.isFinite,
                    gmsd.isFinite,
                    banding.isFinite,
                    swappedDelta.isFinite,
                    row.costMs.isFinite
                else {
                    return .invalid(reason: "incomplete or non-finite \(arm.rawValue) row at \(key.description)")
                }
                if swappedDelta > bounds.negativeControlTolerance {
                    return .invalid(
                        reason: "\(arm.rawValue) negative-control drift \(format(swappedDelta)) exceeds 0.02 at \(key.description)"
                    )
                }
            }
        }

        let aEligible = expected.allSatisfy { aRows[$0]!.banding! <= bounds.armBandingMaximum }
        let bEligible = expected.allSatisfy { bRows[$0]!.banding! <= bounds.armBandingMaximum }
        if !aEligible && !bEligible {
            let aOffenders = expected.filter { aRows[$0]!.banding! > bounds.armBandingMaximum }
            let bOffenders = expected.filter { bRows[$0]!.banding! > bounds.armBandingMaximum }
            let aDetail = aOffenders.map(\.description).joined(separator: ", ")
            let bDetail = bOffenders.map(\.description).joined(separator: ", ")
            return .inconclusive(clause: "banding: A fails at \(aDetail); B fails at \(bDetail)")
        }
        if aEligible && !bEligible {
            return .shipA(reason: "only A clears B_max at every fixture-width cell")
        }
        if bEligible && !aEligible {
            return .shipB(reason: "only B clears B_max at every fixture-width cell")
        }

        let aMAE = mean(expected.compactMap { aRows[$0]?.mae })
        let bMAE = mean(expected.compactMap { bRows[$0]?.mae })
        let aGMSD = mean(expected.compactMap { aRows[$0]?.gmsd })
        let bGMSD = mean(expected.compactMap { bRows[$0]?.gmsd })
        guard aMAE.isFinite, bMAE.isFinite, aGMSD.isFinite, bGMSD.isFinite else {
            return .invalid(reason: "mean MAE or GMSD is non-finite")
        }

        let winner: Arm
        let reason: String
        let maeMargin: Double
        if aMAE == bMAE {
            maeMargin = 0
        } else if aMAE < bMAE {
            maeMargin = relativeMargin(winner: aMAE, loser: bMAE)
        } else {
            maeMargin = relativeMargin(winner: bMAE, loser: aMAE)
        }

        if maeMargin >= bounds.maeTie {
            winner = aMAE <= bMAE ? .a : .b
            let winnerGMSD = winner == .a ? aGMSD : bGMSD
            let otherGMSD = winner == .a ? bGMSD : aGMSD
            if winnerGMSD > otherGMSD,
                relativeMargin(winner: otherGMSD, loser: winnerGMSD) > bounds.gmsdVeto
            {
                return .inconclusive(
                    clause: "GMSD veto: MAE winner \(winner.rawValue) is worse by more than G_veto"
                )
            }
            reason = "MAE decides: \(winner.rawValue) wins by \(percent(maeMargin))"
        } else {
            let gmsdMargin: Double
            if aGMSD == bGMSD {
                gmsdMargin = 0
            } else if aGMSD < bGMSD {
                gmsdMargin = relativeMargin(winner: aGMSD, loser: bGMSD)
            } else {
                gmsdMargin = relativeMargin(winner: bGMSD, loser: aGMSD)
            }
            if gmsdMargin >= bounds.gmsdTie {
                winner = aGMSD <= bGMSD ? .a : .b
                reason = "MAE tie; GMSD decides: \(winner.rawValue) wins by \(percent(gmsdMargin))"
            } else {
                winner = .a
                reason = "MAE and GMSD margins are below their tie thresholds"
            }
        }

        if winner == .b,
            bMAE < aMAE,
            let bMAEMargin = finiteRelativeMargin(winner: bMAE, loser: aMAE),
            bMAEMargin <= bounds.cheapIfClose,
            let aCost = aRows[CellKey(fixtureID: "canyon-384", targetPixelWidth: 2332)]?.costMs,
            let bCost = bRows[CellKey(fixtureID: "canyon-384", targetPixelWidth: 2332)]?.costMs,
            bCost > bounds.costRatio * aCost
        {
            return .shipA(
                reason: "cheap-if-close: B MAE lead \(percent(bMAEMargin)) is within C_close and B costs more than C_ratio × A at canyon-384@2332"
            )
        }

        switch winner {
        case .a: return .shipA(reason: reason)
        case .b: return .shipB(reason: reason)
        }
    }

    static func bandingMasses(
        luma: [Float],
        width: Int,
        height: Int,
        columns: Int,
        useInkMass: Bool
    ) -> [Double]? {
        guard
            width > 0,
            height > 0,
            columns > 4,
            luma.count == width * height
        else { return nil }

        let advance = Double(width) / Double(columns)
        guard advance.isFinite, advance >= 1 else { return nil }

        var columnSums = [Double](repeating: 0, count: width)
        for y in 0..<height {
            let rowOffset = y * width
            for x in 0..<width {
                let sample = min(max(Double(luma[rowOffset + x]), 0), 1)
                columnSums[x] += useInkMass ? 1 - sample : sample
            }
        }

        var masses = [Double](repeating: 0, count: columns)
        for x in 0..<width {
            let columnStart = Double(x)
            let columnEnd = columnStart + 1
            let firstCell = min(columns - 1, Int(floor(columnStart / advance)))
            let firstCellEnd = Double(firstCell + 1) * advance
            let firstOverlap = max(0, min(columnEnd, firstCellEnd) - columnStart)
            masses[firstCell] += firstOverlap * columnSums[x]

            if firstOverlap < 1 {
                let secondCell = firstCell + 1
                guard secondCell < columns else { return nil }
                let secondOverlap = 1 - firstOverlap
                masses[secondCell] += secondOverlap * columnSums[x]
            }
        }

        return masses
    }

    static func bandingCoefficient(
        luma: [Float],
        width: Int,
        height: Int,
        columns: Int,
        useInkMass: Bool
    ) -> Double? {
        guard
            let masses = bandingMasses(
                luma: luma,
                width: width,
                height: height,
                columns: columns,
                useInkMass: useInkMass
            )
        else { return nil }

        let interior = masses.dropFirst(2).dropLast(2)
        guard !interior.isEmpty else { return nil }
        let meanMass = interior.reduce(0, +) / Double(interior.count)
        guard meanMass > 0, meanMass.isFinite else { return 0 }
        guard let maximum = interior.max(), let minimum = interior.min() else { return nil }
        return (maximum - minimum) / meanMass
    }

    static func oracleMeansCSV(_ report: Report) -> String {
        var lines = ["fixture,width,arm,height,mae,gmsd,banding,banding_swapped_delta,cost_ms,dimensions_match_reference"]
        for row in report.armRows {
            lines.append(
                [
                    row.fixtureID,
                    String(row.width),
                    row.arm.rawValue,
                    String(row.height),
                    csv(row.mae),
                    csv(row.gmsd),
                    csv(row.banding),
                    csv(row.bandingSwappedDelta),
                    csv(row.costMs),
                    String(row.dimensionsMatchReference),
                ].joined(separator: ",")
            )
        }
        for row in report.referenceRows {
            lines.append(
                [
                    row.fixtureID,
                    String(row.width),
                    "reference",
                    String(row.height),
                    "",
                    "",
                    csv(row.banding),
                    "",
                    csv(row.costMs),
                    "true",
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n")
    }

    static func format(_ report: Report, reproduce: String) -> String {
        var lines = ["# Target-width render gate (ASKI-63)"]
        lines.append("")
        lines.append("Provenance: `\(report.gitSHA)`.")
        if report.partialFixtures {
            lines.append(
                "**PARTIAL FIXTURES.** The consumer input was absent; this verdict uses the corpus cells only."
            )
        }
        if let hash = report.consumerInputSHA256 {
            lines.append("Consumer input SHA-256: `\(hash)`.")
        }
        lines.append("")
        lines.append("## Reproduce")
        lines.append("")
        lines.append("```")
        lines.append(reproduce)
        lines.append("```")
        lines.append("")
        lines.append("## Arm rows")
        lines.append("")
        lines.append("fixture | target width | arm | width × height | MAE | GMSD | banding | swapped Δ | cost ms")
        for row in report.armRows {
            lines.append(
                "\(row.fixtureID) | \(row.targetPixelWidth) | \(row.arm.rawValue) | \(row.width) × \(row.height) | "
                    + "\(format(row.mae)) | \(format(row.gmsd)) | \(format(row.banding)) | "
                    + "\(format(row.bandingSwappedDelta)) | \(format(row.costMs))"
            )
        }
        lines.append("")
        lines.append("## Reference rows")
        lines.append("")
        lines.append("fixture | target width | width × height | banding | cost ms")
        for row in report.referenceRows {
            lines.append(
                "\(row.fixtureID) | \(row.targetPixelWidth) | \(row.width) × \(row.height) | "
                    + "\(format(row.banding)) | \(format(row.costMs))"
            )
        }
        lines.append("")
        lines.append("## Frozen bounds")
        lines.append("")
        lines.append("B_ref | B_max | M_tie | G_tie | G_veto | C_close | C_ratio")
        lines.append(
            "\(format(report.frozenBounds.referenceBandingMaximum)) | "
                + "\(format(report.frozenBounds.armBandingMaximum)) | "
                + "\(percent(report.frozenBounds.maeTie)) | \(percent(report.frozenBounds.gmsdTie)) | "
                + "\(percent(report.frozenBounds.gmsdVeto)) | \(percent(report.frozenBounds.cheapIfClose)) | "
                + "\(format(report.frozenBounds.costRatio))"
        )
        lines.append("")
        lines.append("## Verdict")
        lines.append("")
        lines.append("**\(report.verdict.outcome):** \(report.verdict.reason)")
        return lines.joined(separator: "\n")
    }

    private static func makeProbeGrid(
        columns: Int,
        rows: Int,
        foreground: SIMD3<Float>,
        colorSpace: RenderColorSpace,
        composition: RenderCompositionPolicy
    ) -> ASCIIGrid {
        let cell = ASCIICell(
            character: "#",
            displayColor: foreground,
            alpha: 1,
            brightness: 1
        )
        return ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: columns), count: rows),
            colorSpace: colorSpace,
            composition: composition
        )
    }

    private static func renderAndMeasure(
        grid: ASCIIGrid,
        configuration: FixtureConfiguration,
        targetPixelWidth: Int,
        resample: TargetWidthResample,
        repeats: Int
    ) -> TimedImage {
        var times: [Double] = []
        times.reserveCapacity(repeats)
        var first: CGImage?
        for index in 0..<repeats {
            let start = DispatchTime.now().uptimeNanoseconds
            let image = render(
                grid: grid,
                configuration: configuration,
                targetPixelWidth: targetPixelWidth,
                resample: resample
            )
            let finish = DispatchTime.now().uptimeNanoseconds
            times.append(Double(finish - start) / 1_000_000)
            if index == 0 { first = image }
        }
        return TimedImage(image: first!, costMs: median(times))
    }

    private static func render(
        grid: ASCIIGrid,
        configuration: FixtureConfiguration,
        targetPixelWidth: Int,
        resample: TargetWidthResample
    ) -> CGImage {
        gridRender(
            grid,
            font: configuration.font,
            backgroundColor: configuration.backgroundColor,
            targetPixelWidth: targetPixelWidth,
            preserveSourceAspect: configuration.preserveSourceAspect,
            resample: resample
        )
    }

    private static func gridRender(
        _ grid: ASCIIGrid,
        font: ASCIIFont,
        backgroundColor: CGColor,
        targetPixelWidth: Int,
        preserveSourceAspect: Bool,
        resample: TargetWidthResample
    ) -> CGImage {
        grid.renderImage(
            font: font,
            backgroundColor: backgroundColor,
            targetPixelWidth: targetPixelWidth,
            preserveSourceAspect: preserveSourceAspect,
            resample: resample
        )
    }

    private static func scores(
        candidate: (values: [Float], width: Int, height: Int)?,
        reference: (values: [Float], width: Int, height: Int)?,
        dimensionsMatch: Bool,
        invalidReasons: inout [String],
        label: String
    ) -> (mae: Double?, gmsd: Double?) {
        guard dimensionsMatch else { return (nil, nil) }
        guard let candidate, let reference else {
            invalidReasons.append("\(label): could not read Rec.601 luma")
            return (nil, nil)
        }
        guard candidate.width == reference.width, candidate.height == reference.height else {
            invalidReasons.append("\(label): luma dimensions differ from reference")
            return (nil, nil)
        }
        return (
            mae(candidate.values, reference.values),
            GMSD.gmsd(candidate.values, reference.values, width: reference.width, height: reference.height)
        )
    }

    private static func banding(
        image: CGImage,
        columns: Int,
        useInkMass: Bool,
        invalidReasons: inout [String],
        label: String
    ) -> Double? {
        guard let plane = PolarityGate.luma(of: image) else {
            invalidReasons.append("\(label): could not read Rec.601 luma")
            return nil
        }
        guard
            let result = bandingCoefficient(
                luma: plane.values,
                width: plane.width,
                height: plane.height,
                columns: columns,
                useInkMass: useInkMass
            ),
            result.isFinite
        else {
            invalidReasons.append("\(label): banding coefficient is unavailable")
            return nil
        }
        return result
    }

    private static func writeRenders(
        directory: URL?,
        fixtureID: String,
        targetPixelWidth: Int,
        label: String,
        render: CGImage,
        probe: CGImage
    ) throws -> (render: String?, probe: String?) {
        guard let directory else { return (nil, nil) }
        let stem = "\(fixtureID)-\(targetPixelWidth)-\(label)"
        let renderName = "\(stem).png"
        let probeName = "\(stem)-probe.png"
        try DemoImageIO.writePNG(render, to: directory.appendingPathComponent(renderName).path)
        try DemoImageIO.writePNG(probe, to: directory.appendingPathComponent(probeName).path)
        return ("renders/\(renderName)", "renders/\(probeName)")
    }

    private static func dimensionsMatch(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
    }

    private static func mae(_ lhs: [Float], _ rhs: [Float]) -> Double? {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return nil }
        var total = 0.0
        for index in lhs.indices {
            total += Double(abs(lhs[index] - rhs[index]))
        }
        return total / Double(lhs.count)
    }

    private static func delta(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return abs(lhs - rhs)
    }

    private static func expectedCells(_ fixtures: [FixtureMetadata]) -> [CellKey] {
        var cells: [CellKey] = []
        for fixture in fixtures {
            for width in fixture.widths {
                cells.append(CellKey(fixtureID: fixture.id, targetPixelWidth: width))
            }
        }
        return cells.sorted { lhs, rhs in
            lhs.fixtureID == rhs.fixtureID
                ? lhs.targetPixelWidth < rhs.targetPixelWidth
                : lhs.fixtureID < rhs.fixtureID
        }
    }

    private static func rowsByCell(
        _ rows: [ArmRow],
        expected: [CellKey]
    ) -> (rows: [Arm: [CellKey: ArmRow]], invalidReason: String?) {
        let expectedSet = Set(expected)
        var result: [Arm: [CellKey: ArmRow]] = [.a: [:], .b: [:]]
        for row in rows {
            let key = CellKey(fixtureID: row.fixtureID, targetPixelWidth: row.targetPixelWidth)
            guard expectedSet.contains(key) else {
                return (result, "unexpected \(row.arm.rawValue) row for \(key.description)")
            }
            if result[row.arm]![key] != nil {
                return (result, "duplicate \(row.arm.rawValue) row for \(key.description)")
            }
            result[row.arm]![key] = row
        }
        return (result, nil)
    }

    private static func referencesByCell(
        _ rows: [ReferenceRow],
        expected: [CellKey]
    ) -> (rows: [CellKey: ReferenceRow], invalidReason: String?) {
        let expectedSet = Set(expected)
        var result: [CellKey: ReferenceRow] = [:]
        for row in rows {
            let key = CellKey(fixtureID: row.fixtureID, targetPixelWidth: row.targetPixelWidth)
            guard expectedSet.contains(key) else {
                return (result, "unexpected reference row for \(key.description)")
            }
            if result[key] != nil {
                return (result, "duplicate reference row for \(key.description)")
            }
            result[key] = row
        }
        return (result, nil)
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .nan }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func relativeMargin(winner: Double, loser: Double) -> Double {
        finiteRelativeMargin(winner: winner, loser: loser) ?? 0
    }

    private static func finiteRelativeMargin(winner: Double, loser: Double) -> Double? {
        guard winner.isFinite, loser.isFinite, winner >= 0, loser > 0 else { return nil }
        return (loser - winner) / loser
    }

    private static func median(_ values: [Double]) -> Double {
        let ordered = values.sorted()
        guard !ordered.isEmpty else { return 0 }
        let middle = ordered.count / 2
        if ordered.count.isMultiple(of: 2) {
            return (ordered[middle - 1] + ordered[middle]) / 2
        }
        return ordered[middle]
    }

    private static func csv(_ value: Double?) -> String {
        guard let value else { return "" }
        return format(value)
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return format(value)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }
}

private extension TargetWidthGate {
    enum GateError: Error, CustomStringConvertible {
        case invalidRepeats(Int)
        case gridDoesNotMatchFixture(id: String, expectedColumns: Int, actualColumns: Int, rows: Int)

        var description: String {
            switch self {
            case .invalidRepeats(let repeats):
                "--repeats must be positive, got \(repeats)"
            case .gridDoesNotMatchFixture(let id, let expectedColumns, let actualColumns, let rows):
                "fixture \(id) produced \(actualColumns) columns and \(rows) rows; expected \(expectedColumns) non-empty columns"
            }
        }
    }
}
