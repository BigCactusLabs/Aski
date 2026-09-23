import Aski
import ArgumentParser
import AskiToolSupport
import Foundation

/// Builds the delegation context for a subcommand from its shared option groups.
func labArguments(
    provenance: ProvenanceOptions,
    seed: UInt64,
    reviewCorpus: String? = nil
) -> LabArguments {
    LabArguments(
        outputDirectory: provenance.outputDirectory,
        seed: seed,
        gitShaOverride: provenance.gitShaOverride,
        reviewCorpusDirectory: reviewCorpus
    )
}

public struct AskiColorLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "AskiColorLab",
        abstract: "Internal research harness for Aski color pipeline candidates.",
        version: ToolVersion.current,
        subcommands: [
            SamplingAblationSubcommand.self,
            PaletteMatchAblationSubcommand.self,
            GamutSweepSubcommand.self,
            LinearCompositeSubcommand.self,
            CuberootAccuracySubcommand.self,
            CAM16HCTReferenceSubcommand.self,
            HelmlabReferenceSubcommand.self,
            ShapeResidualMapSubcommand.self,
            RenderMatcherChallengeSubcommand.self,
            InterCellSmoothingSubcommand.self,
            LatticeSupportSubcommand.self,
            LatticePhaseSubcommand.self,
            SelectionCeilingSubcommand.self,
            ReferenceRecoverySubcommand.self,
            ConventionAblationSubcommand.self,
            PolarityGateSubcommand.self,
            TargetWidthGateSubcommand.self,
            ArbiterSubcommand.self,
        ]
    )

    public init() {}

    // Preserve the legacy "missing command -> usage (exit 64)" contract. Without
    // an explicit root run(), `ParsableCommand`'s default run() prints help and
    // exits 0 on bare invocation — a silent behavior change. `ValidationError`
    // makes SAP print the message + usage and exit 64.
    public func run() throws {
        throw ValidationError("Missing command. See --help for the available subcommands.")
    }
}

public struct SamplingAblationSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: SamplingAblationCommand.commandName,
        abstract: "Compare encoded-average vs linear-light cell sampling."
    )
    @OptionGroup public var provenance: ProvenanceOptions
    @OptionGroup public var seedOption: SeedOption
    public init() {}

    public func execute(
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        SamplingAblationCommand.run(
            arguments: labArguments(provenance: provenance, seed: seedOption.seed),
            standardError: standardError
        )
    }
    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct PaletteMatchAblationSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: PaletteMatchAblationCommand.commandName,
        abstract: "Compare OKLab Euclidean vs HyAB-style nearest-palette decisions."
    )
    @OptionGroup public var provenance: ProvenanceOptions
    @OptionGroup public var seedOption: SeedOption
    public init() {}

    public func execute(
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        PaletteMatchAblationCommand.run(
            arguments: labArguments(provenance: provenance, seed: seedOption.seed),
            standardError: standardError
        )
    }
    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct GamutSweepSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: GamutSweepCommand.commandName,
        abstract: "Compare gamut-mapping strategies across sRGB and Display P3."
    )
    @OptionGroup public var provenance: ProvenanceOptions
    @OptionGroup public var seedOption: SeedOption
    public init() {}

    public func execute(
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        GamutSweepCommand.run(
            arguments: labArguments(provenance: provenance, seed: seedOption.seed),
            standardError: standardError
        )
    }
    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct LinearCompositeSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: LinearCompositeCommand.commandName,
        abstract: "Compare Porter-Duff source-over compositing spaces."
    )
    @OptionGroup public var provenance: ProvenanceOptions
    @OptionGroup public var seedOption: SeedOption
    public init() {}

    public func execute(
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        LinearCompositeCommand.run(
            arguments: labArguments(provenance: provenance, seed: seedOption.seed),
            standardError: standardError
        )
    }
    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct CuberootAccuracySubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: CuberootAccuracyCommand.commandName,
        abstract: "Compare cube-root implementations against a Float64 reference."
    )
    @OptionGroup public var provenance: ProvenanceOptions
    @OptionGroup public var seedOption: SeedOption
    public init() {}

    public func execute(
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        CuberootAccuracyCommand.run(
            arguments: labArguments(provenance: provenance, seed: seedOption.seed),
            standardError: standardError
        )
    }
    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

/// `--battery` accepts the raw values (`synthetic`/`real`/`all`); CaseIterable
/// supplies the valid-value list in `--help`.
extension BatterySelection: ExpressibleByArgument {}

public struct ShapeResidualMapSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: ShapeResidualCommand.commandName,
        abstract: "Map the per-cell logPolar shape residual + an independent SSIM structure oracle."
    )
    @OptionGroup public var provenance: ProvenanceOptions
    @OptionGroup public var seedOption: SeedOption
    @Option(
        name: .customLong("columns"),
        help: "ASCII columns for the residual map (1...\(ToolArgumentBounds.maxColumns)); repeatable to sweep, e.g. --columns 44 --columns 80. Default 80.")
    public var columns: [Int] = [80]
    @Option(
        name: .customLong("fixture-size"),
        help: "Native fixture side in px (default 256; e.g. 512/1024/2048 so each source block is >= the 24px oracle footprint at canonical columns).")
    public var fixtureSize: Int = ShapeResidualCommand.defaultFixtureSize
    @Flag(
        name: .customLong("allow-upsampled-oracle-blocks"),
        help: "EXPLORATORY escape hatch: bypass the oracle-native validity guard (source blocks may be upsampled below the 24px footprint) and stamp the manifest as non-decisive.")
    public var allowUpsampledOracleBlocks: Bool = false
    @Option(
        name: .customLong("battery"),
        help: "Fixture battery: synthetic (5 procedural), real (glyphSheet + NASA photos), or all. Default synthetic.")
    public var battery: BatterySelection = .synthetic
    @Option(
        name: .customLong("corpus-dir"),
        help: "Override the natural-pool corpus assets directory (default: the committed nasa-structure-v1 corpus).")
    public var corpusDir: String?
    public init() {}

    public func execute(
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        ShapeResidualCommand.run(
            arguments: ShapeResidualArguments(
                outputDirectory: provenance.outputDirectory,
                columns: columns,
                fixtureSize: fixtureSize,
                allowUpsampledOracleBlocks: allowUpsampledOracleBlocks,
                battery: battery,
                corpusDirectory: corpusDir,
                gitShaOverride: provenance.gitShaOverride
            ),
            standardError: standardError
        )
    }
    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct RenderMatcherChallengeSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: RenderMatcherChallenge.commandName,
        abstract: "Run the frozen ASKI-69 render-space matcher challenge once."
    )
    @OptionGroup public var provenance: ProvenanceOptions
    public init() {}

    public func execute(
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        RenderMatcherChallenge.run(
            outputDirectory: provenance.outputDirectory,
            gitSHAOverride: provenance.gitShaOverride,
            standardError: standardError
        )
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct InterCellSmoothingSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "inter-cell-smoothing",
        abstract: "ASTSK-43 screen: raw vs guided-filter-smoothed input, dual-oracle PASS/KILL gate."
    )
    @Option(name: .customLong("columns"), help: "ASCII columns for the A/B render (1...\(ToolArgumentBounds.maxColumns)).")
    public var columns: Int = 64
    @Option(name: .customLong("corpus"), help: "Optional naturals corpus dir (default: committed NASA corpus).")
    public var corpus: String?
    public init() {}

    public func run() throws {
        let report = try InterCellSmoothingScreen.run(columns: columns, corpusDirectory: corpus)
        print(InterCellSmoothingScreen.format(report, columns: columns))
    }
}

public struct CAM16HCTReferenceSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: CAM16HCTReferenceCommand.commandName,
        abstract: "Generate pinned CAM16/HCT reference + CAM16-UCS palette CSVs."
    )
    @OptionGroup public var provenance: ProvenanceOptions
    @OptionGroup public var seedOption: SeedOption
    public init() {}

    public func execute(
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        CAM16HCTReferenceCommand.run(
            arguments: labArguments(provenance: provenance, seed: seedOption.seed),
            standardError: standardError
        )
    }
    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct HelmlabReferenceSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: HelmlabReferenceCommand.commandName,
        abstract: "Generate pinned Helmlab MetricSpace reference + round-trip CSV."
    )
    @OptionGroup public var provenance: ProvenanceOptions
    @OptionGroup public var seedOption: SeedOption
    @Option(name: .customLong("review-corpus"), help: "Directory of real images for the large-deltaE corpus review.")
    public var reviewCorpus: String?
    public init() {}

    public func execute(
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        HelmlabReferenceCommand.run(
            arguments: labArguments(provenance: provenance, seed: seedOption.seed, reviewCorpus: reviewCorpus),
            standardError: standardError
        )
    }
    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct LatticeSupportSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "lattice-support",
        abstract:
            "Census of how much of the 60D log-polar descriptor is reachable at the sampling footprint the converter actually resolves."
    )
    @Option(name: .customLong("columns"), help: "Column count (default 80).")
    public var columns: Int = 80
    @Option(
        name: .customLong("oversample"),
        help: "Comma-separated oversample sweep (default: 2,4,8,16).")
    public var oversample: String = "2,4,8,16"
    @Option(name: .customLong("corpus"), help: "Optional naturals corpus dir.")
    public var corpus: String?
    public init() {}

    public func run() throws {
        let report = try LatticeSupport.run(
            columns: columns,
            oversamples: try parseIntList(oversample, flag: "--oversample"),
            corpus: corpus)
        print(LatticeSupport.format(report))
    }
}

public struct LatticePhaseSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "lattice-phase",
        abstract:
            "Sub-cell lattice-phase sweep with a full-pitch null arm, measuring whether grid placement is a quality lever."
    )
    @Option(name: .customLong("columns"), help: "Column count (default 80).")
    public var columns: Int = 80
    @Option(name: .customLong("oversample"), help: "Comma-separated oversample sweep (default: 2,8).")
    public var oversample: String = "2,8"
    @Option(name: .customLong("footprint"), help: "Scoring footprint in px (default 24).")
    public var footprint: Int = 24
    @Option(name: .customLong("corpus"), help: "Optional naturals corpus dir.")
    public var corpus: String?
    public init() {}

    public func run() throws {
        let rows = try LatticePhase.run(
            columns: columns,
            oversamples: try parseIntList(oversample, flag: "--oversample"),
            footprint: footprint, corpus: corpus)
        print(LatticePhase.format(rows))
    }
}

public struct SelectionCeilingSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "selection-ceiling",
        abstract:
            "Optimality gap between the production glyph pick and the loss-optimal pick, split into pool-exclusion and ranking terms under every screened oracle."
    )
    @Option(name: .customLong("columns"), help: "Column count (default 80).")
    public var columns: Int = 80
    @Option(name: .customLong("oversample"), help: "Comma-separated oversample sweep (default: 2).")
    public var oversample: String = "2"
    @Option(
        name: .customLong("charset"),
        help: "Comma-separated character sets (default: standard,blocks).")
    public var charset: String = "standard,blocks"
    @Option(name: .customLong("footprint"), help: "Scoring footprint in px (default 24).")
    public var footprint: Int = 24
    @Option(
        name: .customLong("stride"),
        help:
            "Cell subsample stride for quick exploration (default 1 = exhaustive census). Values above 1 keep only cells whose row and column are 0 mod stride, so the result is a FIXED-PHASE sample statistic, not a population mean — it can alias with periodic content and with cell-position effects. Reported runs use 1."
    )
    public var stride: Int = 1
    @Option(
        name: .customLong("corpus"),
        help:
            "Naturals corpus dir. Defaults to the 3072px docs/Research/Corpus/nasa-steerable-v1/assets — the corpus the 2026-08-19 notes report, and the same native side the reference-recovery screen resolves its cell block from. Pass docs/Research/Corpus/nasa-structure-v1/assets for the 2048px corpus the ShapeResidual battery defaults to; the two disagree by up to 10 gap points."
    )
    public var corpus: String?
    @Option(
        name: .customLong("topk"),
        help:
            "Arm K (ASKI-28): comma-separated pool widths for the brightness pre-filter, each run as its own arm. Unclamped by the shipped `density` knob, whose reachable range is topK 12...36 — pass 95 / 256 to sweep to the full pool. Repeatable, and each entry may be scoped to one charset as '<charset>=12,18,95'; the frozen grids differ between standard and braille, so an unscoped list would run points outside a charset's registered grid. A single unscoped list applies to every charset without its own entry. Widths above the glyph count are clamped to it and de-duplicated, and the CSV records the EFFECTIVE width. Absent = arm K off."
    )
    public var topk: [String] = []
    @Option(
        name: .customLong("tone-weight"),
        help:
            "Arm T (ASKI-30): comma-separated tone weights w for `distance + w * toneDelta²`, scored over the full pool and deliberately decoupled from --topk. Absent = arm T off."
    )
    public var toneWeight: String?
    @Option(
        name: .customLong("lex-shape-k"),
        help:
            "Exploratory arm (rule §6.1), non-gating: comma-separated shapeK values. Prunes to the shapeK shape-nearest candidates then ranks survivors by tone — the inverse of production's order. shapeK=1 is the shape argmin, shapeK=glyphCount is the tone-only floor."
    )
    public var lexShapeK: String?
    @Flag(
        name: .customLong("z-normalized"),
        help:
            "Exploratory arm (rule §6.2), non-gating: also run a z-normalized combination at every --tone-weight point, normalizing both loss distributions on the charset's own pooled moments instead of the fixed toneErrorWeight = 50 scale."
    )
    public var zNormalized = false
    @Flag(
        name: .customLong("legacy-floor"),
        help:
            "Also emit the tone-only floor as it was built before the ASKI-30 floor-quantity fix (rawDensityValues vs mean block luma) so the before/after re-definition audit is runnable. The reported floor is the fixed one either way."
    )
    public var legacyFloor = false
    @Option(
        name: .customLong("output"),
        help:
            "Write the machine-readable arm census to this CSV path. The frozen ASKI-28/30 rule is applied to this file and to nothing else; the stdout table is unaffected."
    )
    public var output: String?
    @Option(
        name: .customLong("aski-git-sha"),
        help: "Override the git SHA recorded in the CSV's provenance column.")
    public var gitShaOverride: String?
    @OptionGroup public var shapeQueryPolarityOption: ShapeQueryPolarityOption
    public init() {}

    public func validate() throws {
        try ToolValidation.requireSafeGitSHA(gitShaOverride)
    }

    public func run() throws {
        guard stride > 0 else { throw ValidationError("--stride must be positive") }
        let names = charset.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !names.isEmpty else { throw ValidationError("--charset must not be empty") }

        var sweeps = SelectionCeiling.Sweeps()
        sweeps.includeLegacyFloor = legacyFloor
        if !topk.isEmpty {
            let grids = try parseScopedIntLists(topk, flag: "--topk")
            sweeps.topKs = grids.global
            sweeps.topKsByCharset = grids.scoped
            for scopedName in grids.scoped.keys where !names.contains(scopedName) {
                throw ValidationError(
                    "--topk scopes '\(scopedName)', which is not in --charset")
            }
        }
        if let lexShapeK {
            sweeps.lexShapeKs = try parseIntList(lexShapeK, flag: "--lex-shape-k")
        }
        if let toneWeight {
            sweeps.toneWeights = try parseFloatList(toneWeight, flag: "--tone-weight")
            if zNormalized { sweeps.zNormWeights = sweeps.toneWeights }
        } else if zNormalized {
            throw ValidationError("--z-normalized needs a --tone-weight grid to run at")
        }

        let census = try SelectionCeiling.census(
            columns: columns,
            oversamples: try parseIntList(oversample, flag: "--oversample"),
            charsetNames: names, footprint: footprint, stride: stride, corpus: corpus,
            sweeps: sweeps, gitSHA: GitSHA.resolve(override: gitShaOverride),
            shapeQueryPolarity: shapeQueryPolarityOption.shapeQueryPolarity)
        print(SelectionCeiling.format(census.rows, stride: stride))

        if let output {
            let url = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (SelectionCeiling.csv(census.armRows) + "\n")
                .write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

public struct ReferenceRecoverySubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "reference-recovery",
        abstract:
            "Reference-recovery screen: renders each glyph as its own source cell and reports whether each oracle makes that glyph the unique argmin at the scoring footprint."
    )
    @Option(name: .customLong("columns"), help: "Column count (default 80).")
    public var columns: Int = 80
    @Option(name: .customLong("oversample"), help: "Converter oversample (default 2).")
    public var oversample: Int = 2
    @Option(name: .customLong("footprint"), help: "Scoring footprint in px (default 24).")
    public var footprint: Int = 24
    @Option(
        name: .customLong("native-side"),
        help: "Native source side the cell block is resolved from (default 3072, the side of the nasa-steerable-v1 corpus selection-ceiling defaults to).")
    public var nativeSide: Int = 3072
    @Option(
        name: .customLong("charset"),
        help: "Comma-separated character sets (default: blocks,standard,braille).")
    public var charset: String = "blocks,standard,braille"
    public init() {}

    public func run() throws {
        guard columns > 0, oversample > 0, footprint > 1, nativeSide > 0 else {
            throw ValidationError("--columns/--oversample/--footprint/--native-side must be positive")
        }
        let names = charset.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !names.isEmpty else { throw ValidationError("--charset must not be empty") }
        let rows = try ReferenceRecovery.run(
            columns: columns, oversample: oversample, footprint: footprint,
            nativeSide: nativeSide, charsetNames: names)
        print(ReferenceRecovery.format(rows))
    }
}

public struct ConventionAblationSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "convention-ablation",
        abstract:
            "ASKI-52/26: what the matcher's bounds-centred square candidate convention and its single-disc sampling support cost on the photographic corpora, gated on pick quality (MAE-first) rather than descriptor distance."
    )
    @Option(name: .customLong("columns"), help: "Column count (default 80).")
    public var columns: Int = 80
    @Option(name: .customLong("oversample"), help: "Converter oversample (default 2).")
    public var oversample: Int = 2
    @Option(name: .customLong("footprint"), help: "Scoring footprint in px (default 24).")
    public var footprint: Int = 24
    @Option(
        name: .customLong("cell-width"),
        help:
            "Width of the sampling cell both sides are compared at (default 12). With --cell-height 24 this is the source paper's own worked example — 72 windows, 4320-D — at the shipping regime's 1:2 cell aspect. The query is the converter's resolved NATIVE block, resampled here; the geometry table reports the thumbnail cell the shipped kernel actually samples."
    )
    public var cellWidth: Int = 12
    @Option(name: .customLong("cell-height"), help: "Height of the sampling cell (default 24).")
    public var cellHeight: Int = 24
    @Option(
        name: .customLong("stride"),
        help:
            "Cell subsample stride (default 1 = exhaustive census). Above 1 keeps only cells whose row and column are 0 mod stride, so the result is a FIXED-PHASE sample statistic, not a population mean."
    )
    public var stride: Int = 1
    @Option(
        name: .customLong("charset"),
        help: "Comma-separated character sets (default: blocks,standard,braille).")
    public var charset: String = "blocks,standard,braille"
    @Option(
        name: .customLong("corpus"),
        help:
            "Comma-separated naturals corpus dirs (default: the two photographic corpora, docs/Research/Corpus/nasa-steerable-v1/assets and docs/Research/Corpus/nasa-occupancy-v1/assets)."
    )
    public var corpus: String =
        "docs/Research/Corpus/nasa-steerable-v1/assets,docs/Research/Corpus/nasa-occupancy-v1/assets"
    @Option(
        name: .customLong("query-polarity"),
        help:
            "How the descriptor query field is oriented: 'inverted' (1 - luma, reproducing LogPolarKernel.baseInkField, which is production's shape term) or 'direct' (raw luma, matching the ink-high candidates and the scoring path). Production's shape term and its tone pre-filter disagree about which end of the source is ink, so both are measured. Default: inverted."
    )
    public var queryPolarity: String = "inverted"
    @Option(
        name: .customLong("output-dir"),
        help:
            "Write geometry.csv, convention-delta.csv, ablation-ladder.csv and summary.md here. The stdout table is unaffected."
    )
    public var outputDirectory: String?
    public init() {}

    public func run() throws {
        guard let polarity = ConventionAblation.QueryPolarity(rawValue: queryPolarity) else {
            let allowed = ConventionAblation.QueryPolarity.allCases.map(\.rawValue)
            throw ValidationError(
                "--query-polarity must be one of: " + allowed.joined(separator: ", "))
        }
        guard columns > 0, oversample > 0, footprint > 1, stride > 0 else {
            throw ValidationError("--columns/--oversample/--footprint/--stride must be positive")
        }
        guard cellWidth > 1, cellHeight > 1 else {
            throw ValidationError("--cell-width/--cell-height must be at least 2")
        }
        let names = charset.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !names.isEmpty else { throw ValidationError("--charset must not be empty") }
        let corpora = corpus.split(separator: ",").map {
            String($0.trimmingCharacters(in: .whitespaces))
        }
        guard !corpora.isEmpty else { throw ValidationError("--corpus must not be empty") }

        let report = try ConventionAblation.run(
            columns: columns, oversample: oversample, footprint: footprint,
            cellWidth: cellWidth, cellHeight: cellHeight, stride: stride,
            charsetNames: names, corpora: corpora, queryPolarity: polarity)
        // The exact invocation, rebuilt from the resolved values rather than from
        // the argv the shell happened to pass, so a run driven by defaults still
        // records a command a later reader can paste.
        let reproduce = """
            swift run -c release AskiColorLab convention-ablation \\
              --columns \(columns) --oversample \(oversample) --footprint \(footprint) \\
              --cell-width \(cellWidth) --cell-height \(cellHeight) --stride \(stride) \\
              --charset \(charset) \\
              --query-polarity \(polarity.rawValue) \\
              --corpus \(corpus) \\
              --output-dir \(outputDirectory ?? "<dir>")
            """
        let table = ConventionAblation.format(
            report, stride: stride, reproduce: reproduce, queryPolarity: polarity)
        print(table)

        if let outputDirectory {
            let directory = URL(fileURLWithPath: outputDirectory)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try (ConventionAblation.geometryCSV(report.geometry) + "\n").write(
                to: directory.appendingPathComponent("geometry.csv"), atomically: true,
                encoding: .utf8)
            try (ConventionAblation.deltaCSV(report.delta, queryPolarity: polarity) + "\n").write(
                to: directory.appendingPathComponent("convention-delta.csv"), atomically: true,
                encoding: .utf8)
            try (ConventionAblation.ladderCSV(report.ladder, queryPolarity: polarity) + "\n").write(
                to: directory.appendingPathComponent("ablation-ladder.csv"), atomically: true,
                encoding: .utf8)
            try (table + "\n").write(
                to: directory.appendingPathComponent("summary.md"), atomically: true,
                encoding: .utf8)
        }
    }
}

public struct PolarityGateSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "polarity-gate",
        abstract:
            "ASKI-60: what the logPolar shape query's ink convention costs, measured on the REAL converter through the RenderingOptions.shapeQueryPolarity knob. MAE decides, GMSD guards, and every scored pair is re-scored with both planes negated as a mandatory negative control."
    )
    @Option(name: .customLong("columns"), help: "Column count (default 80).")
    public var columns: Int = 80
    @Option(name: .customLong("oversample"), help: "Converter oversample (default 2).")
    public var oversample: Int = 2
    @Option(name: .customLong("footprint"), help: "Scoring footprint in px (default 24).")
    public var footprint: Int = 24
    @Option(
        name: .customLong("cell-width"),
        help:
            "Width of the sampling cell the scoring rasters are drawn at (default 12), matching convention-ablation so the two instruments' numbers are comparable."
    )
    public var cellWidth: Int = 12
    @Option(name: .customLong("cell-height"), help: "Height of the sampling cell (default 24).")
    public var cellHeight: Int = 24
    @Option(
        name: .customLong("charset"),
        help: "Comma-separated character sets (default: blocks,standard,braille).")
    public var charset: String = "blocks,standard,braille"
    @Option(
        name: .customLong("corpus"),
        help:
            "Comma-separated naturals corpus dirs (default: the two photographic corpora, docs/Research/Corpus/nasa-steerable-v1/assets and docs/Research/Corpus/nasa-occupancy-v1/assets)."
    )
    public var corpus: String =
        "docs/Research/Corpus/nasa-steerable-v1/assets,docs/Research/Corpus/nasa-occupancy-v1/assets"
    @Option(
        name: .customLong("polarity"),
        help:
            "Comma-separated arms to measure: 'inverted' (production's shape term, 1 - luma) and/or 'direct' (raw luma, the ink axis the candidates, the tone pre-filter and the renderer already use). Default: both. A single-arm run reports means but cannot reach a verdict."
    )
    public var polarity: String = "inverted,direct"
    @Option(
        name: .customLong("fixture-limit"),
        help:
            "Keep only the first N fixtures of each corpus, in the loader's deterministic filename order. Smoke runs only — a limited run is NOT the pre-registered regime and its verdict is not quotable."
    )
    public var fixtureLimit: Int?
    @Flag(
        name: .customLong("render-arm"),
        help:
            "Addendum item 5, the real-renderer existence proof: render one fixture per corpus per polarity through the shipped ImageRenderer (blocks, 76 columns, white ink on black), resample the rendered luma down to the source geometry and score MAE + GMSD against the source. Checks that the lab's cell-wise scoring path and the shipped renderer agree in SIGN. Writes PNGs into <output-dir>/render-arm/, so it needs --output-dir."
    )
    public var renderArm: Bool = false
    @Option(
        name: .customLong("output-dir"),
        help:
            "Write polarity-gate.json, oracle-means.csv and summary.md here. The stdout table is unaffected."
    )
    public var outputDirectory: String?
    // `ProvenanceOptions` is not used here because its `--output-dir` is
    // REQUIRED; `convention-ablation`, the instrument this one is read beside,
    // makes the directory optional so a run can print to stdout alone.
    @Option(
        name: .customLong("aski-git-sha"),
        help: "Override the git SHA recorded in result provenance.")
    public var gitShaOverride: String?
    public init() {}

    public func validate() throws {
        try ToolValidation.requireSafeGitSHA(gitShaOverride)
    }

    public func run() throws {
        guard columns > 0, oversample > 0, footprint > 1 else {
            throw ValidationError("--columns/--oversample/--footprint must be positive")
        }
        guard cellWidth > 1, cellHeight > 1 else {
            throw ValidationError("--cell-width/--cell-height must be at least 2")
        }
        if let fixtureLimit, fixtureLimit < 1 {
            throw ValidationError("--fixture-limit must be at least 1")
        }
        let names = charset.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !names.isEmpty else { throw ValidationError("--charset must not be empty") }
        let corpora = corpus.split(separator: ",").map {
            String($0.trimmingCharacters(in: .whitespaces))
        }
        guard !corpora.isEmpty else { throw ValidationError("--corpus must not be empty") }
        var polarities: [ShapeQueryPolarity] = []
        for raw in polarity.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard let parsed = PolarityGate.parse(raw) else {
                throw ValidationError("--polarity must be one of: inverted, direct")
            }
            if !polarities.contains(where: { PolarityGate.label($0) == raw }) {
                polarities.append(parsed)
            }
        }
        guard !polarities.isEmpty else { throw ValidationError("--polarity must not be empty") }

        // The render arm's evidence is the PNGs it writes, so it needs somewhere
        // to write them. Refused up front rather than silently degraded.
        if renderArm, outputDirectory == nil {
            throw ValidationError("--render-arm requires --output-dir (it writes PNGs)")
        }

        let gitSHA = GitSHA.resolve(override: gitShaOverride)
        let report = try PolarityGate.run(
            columns: columns, oversample: oversample, footprint: footprint,
            cellWidth: cellWidth, cellHeight: cellHeight, charsetNames: names,
            corpora: corpora, polarities: polarities, fixtureLimit: fixtureLimit,
            gitSHA: gitSHA, renderArm: renderArm,
            renderArmDirectory: outputDirectory.map { URL(fileURLWithPath: $0) })

        var reproduceLines = [
            "xcrun swift run -c release AskiColorLab polarity-gate",
            "  --columns \(columns) --oversample \(oversample) --footprint \(footprint)",
            "  --cell-width \(cellWidth) --cell-height \(cellHeight)",
            "  --charset \(charset)",
            "  --polarity \(polarities.map(PolarityGate.label).joined(separator: ","))",
            "  --corpus \(corpus)",
        ]
        if let fixtureLimit { reproduceLines.append("  --fixture-limit \(fixtureLimit)") }
        if renderArm { reproduceLines.append("  --render-arm") }
        reproduceLines.append("  --output-dir \(outputDirectory ?? "<dir>")")
        let reproduce = reproduceLines.joined(separator: " \\\n")

        let table = PolarityGate.format(report, reproduce: reproduce)
        print(table)

        if let outputDirectory {
            let directory = URL(fileURLWithPath: outputDirectory)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try StableJSON.write(
                report, to: directory.appendingPathComponent("polarity-gate.json"))
            try (PolarityGate.scoresCSV(report.scores) + "\n").write(
                to: directory.appendingPathComponent("oracle-means.csv"), atomically: true,
                encoding: .utf8)
            try (table + "\n").write(
                to: directory.appendingPathComponent("summary.md"), atomically: true,
                encoding: .utf8)
        }
    }
}

public struct TargetWidthGateSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "target-width-gate",
        abstract: "ASKI-63: compare direct and linear-light supersampled target-width rendering."
    )

    @Option(
        name: .customLong("input"),
        help: "Optional consumer canyon JPEG. Its SHA-256 is recorded; the file is not copied."
    )
    public var input: String?

    @Option(
        name: .customLong("corpus-fixture"),
        help: "In-repository earth-limb PNG fixture."
    )
    public var corpusFixture: String =
        "docs/Research/Corpus/nasa-steerable-v1/assets/earth-limb-sunrise.png"

    @Option(
        name: .customLong("output-dir"),
        help: "Directory for target-width-gate.json, oracle-means.csv, summary.md, and renders/."
    )
    public var outputDirectory: String

    @Option(
        name: .customLong("aski-git-sha"),
        help: "Override the git SHA recorded in result provenance."
    )
    public var gitShaOverride: String?

    @Option(name: .customLong("repeats"), help: "Renders per arm and width for the median cost (default 5).")
    public var repeats: Int = 5

    public init() {}

    public func validate() throws {
        try ToolValidation.requireSafeGitSHA(gitShaOverride)
        guard repeats > 0 else {
            throw ValidationError("--repeats must be positive")
        }
    }

    public func run() throws {
        let directory = URL(fileURLWithPath: outputDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var fixtures: [TargetWidthGate.Fixture] = []
        if let input {
            fixtures.append(.consumer(inputURL: URL(fileURLWithPath: input)))
        }
        fixtures.append(.corpus(pngURL: URL(fileURLWithPath: corpusFixture)))

        let report = try TargetWidthGate.run(
            fixtures: fixtures,
            gitSHA: GitSHA.resolve(override: gitShaOverride),
            repeats: repeats,
            rendersDirectory: directory.appendingPathComponent("renders")
        )

        var reproduceLines = ["xcrun swift run -c release AskiColorLab target-width-gate"]
        if let input { reproduceLines.append("  --input \(input)") }
        reproduceLines.append("  --corpus-fixture \(corpusFixture)")
        reproduceLines.append("  --repeats \(repeats)")
        if let gitShaOverride { reproduceLines.append("  --aski-git-sha \(gitShaOverride)") }
        reproduceLines.append("  --output-dir \(outputDirectory)")
        let reproduce = reproduceLines.joined(separator: " \\\n")
        let summary = TargetWidthGate.format(report, reproduce: reproduce)
        print(summary)

        try StableJSON.write(report, to: directory.appendingPathComponent("target-width-gate.json"))
        try (TargetWidthGate.oracleMeansCSV(report) + "\n").write(
            to: directory.appendingPathComponent("oracle-means.csv"),
            atomically: true,
            encoding: .utf8
        )
        try (summary + "\n").write(
            to: directory.appendingPathComponent("summary.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}

/// Comma-separated positive-integer lists that may be scoped to one charset.
///
/// Each entry is either a bare list (`12,18,24`) applying to every charset
/// without its own entry, or a scoped list (`standard=12,18,95`). Scoping exists
/// because the frozen arm-K grids are asymmetric across charsets (rule §2.5) and
/// a single global list cannot express them without running points that are not
/// in a charset's registered grid.
///
/// Two bare lists, or the same charset scoped twice, are rejected rather than
/// silently resolved — either would corrupt a sweep in a way the CSV could not
/// show.
func parseScopedIntLists(
    _ raw: [String], flag: String
) throws -> (global: [Int], scoped: [String: [Int]]) {
    var global: [Int]?
    var scoped: [String: [Int]] = [:]
    for entry in raw {
        guard let separator = entry.firstIndex(of: "=") else {
            guard global == nil else {
                throw ValidationError(
                    "\(flag): two unscoped lists were given; scope one as '<charset>=\(entry)'")
            }
            global = try parseIntList(entry, flag: flag)
            continue
        }
        let name = String(entry[entry.startIndex..<separator]).trimmingCharacters(
            in: .whitespaces)
        let values = String(entry[entry.index(after: separator)...])
        guard !name.isEmpty else { throw ValidationError("\(flag): missing charset before '='") }
        guard scoped[name] == nil else {
            throw ValidationError("\(flag): charset '\(name)' was given more than one list")
        }
        scoped[name] = try parseIntList(values, flag: "\(flag) (\(name))")
    }
    return (global ?? [], scoped)
}

/// Comma-separated non-negative floats for the tone-weight sweep. Zero is
/// admitted deliberately: `w = 0` is the rule's built-in sanity anchor, where
/// arm T must reduce to a full-pool shape argmin.
func parseFloatList(_ raw: String, flag: String) throws -> [Float] {
    let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let values = parts.compactMap { Float($0) }
    guard values.count == parts.count, !values.isEmpty,
        values.allSatisfy({ $0.isFinite && $0 >= 0 })
    else {
        throw ValidationError("\(flag) must be comma-separated non-negative numbers")
    }
    return values
}

/// Shared comma-separated positive-integer parsing for the sampling-lattice
/// subcommands, matching the existing `--columns` parsing contract.
func parseIntList(_ raw: String, flag: String) throws -> [Int] {
    let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let values = parts.compactMap { Int($0) }
    guard values.count == parts.count, !values.isEmpty, values.allSatisfy({ $0 > 0 }) else {
        throw ValidationError("\(flag) must be comma-separated positive integers")
    }
    return values
}
