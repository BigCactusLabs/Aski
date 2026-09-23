import AskiToolSupport
import CoreGraphics
import Foundation

@_spi(AskiResearch) import Aski

extension Arbiter {

    /// The run engines behind the three subcommands. Kept out of the SAP command
    /// bodies so each is an injectable `execute(...) -> LabExitCode`, the house
    /// pattern.
    enum CLI {

        static func todayUTC() -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date())
        }

        /// The protocol's source set: the three `nasa-steerable-v1` and three
        /// `nasa-structure-v1` assets (§2.1).
        static let defaultCorpora = [
            "docs/Research/Corpus/nasa-steerable-v1/assets",
            "docs/Research/Corpus/nasa-structure-v1/assets",
        ]

        struct StimuliArguments: Sendable {
            var outputDirectory: String
            var seed: UInt64
            var gitShaOverride: String?
            var corpora: [String]
            var columns: Int
            var oversample: Int
            var footprint: Int
        }

        // MARK: - `arbiter stimuli`

        static func stimuli(
            arguments: StimuliArguments,
            standardOutput: (String) -> Void = { print($0, terminator: "") },
            standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
            date: String = todayUTC()
        ) -> LabExitCode {
            var plan = FamilyPlan()
            plan.columns = arguments.columns
            plan.oversample = arguments.oversample
            plan.footprint = arguments.footprint

            let outputURL = URL(fileURLWithPath: arguments.outputDirectory)
            do {
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: "sheet"), withIntermediateDirectories: true)
            } catch {
                standardError("error: cannot create output directory: \(error)\n")
                return .ioError
            }

            // Load the corpora, corpus-qualifying every source.
            var fixtures: [(source: SourceRef, fixture: ResidualFixture)] = []
            for corpus in arguments.corpora {
                let corpusName = SelectionCeiling.corpusLabel(corpus)
                do {
                    for fixture in try RealFixture.load(corpusDirectory: corpus) {
                        fixtures.append(
                            (SourceRef(corpus: corpusName, asset: "\(fixture.id).png"), fixture))
                    }
                } catch {
                    standardError("error: \(error)\n")
                    return .ioError
                }
            }
            guard !fixtures.isEmpty else {
                standardError("error: no source images found in \(arguments.corpora)\n")
                return .ioError
            }

            // One census per (source, charset) — never per pair.
            var censuses: [String: Census.Result] = [:]
            var scores: [ArmKey: [SelectionCeiling.Oracle: Double]] = [:]
            let required = plan.requiredArms()
            do {
                for entry in fixtures {
                    for (charset, arms) in required {
                        let result = try Census.run(
                            fixture: entry.fixture, charsetName: charset, arms: arms,
                            columns: plan.columns, oversample: plan.oversample,
                            footprint: plan.footprint)
                        censuses["\(entry.source.key)|\(charset)"] = result
                        for (ref, means) in result.means {
                            scores[ArmKey(source: entry.source, charset: charset, arm: ref)] = means
                        }
                    }
                    standardOutput("censused \(entry.source.key)\n")
                }
            } catch {
                standardError("error: \(error)\n")
                return .failure
            }

            let pairs: [Pair]
            do {
                pairs = try PairPlan.build(
                    sources: fixtures.map(\.source), scores: scores, plan: plan,
                    seed: arguments.seed)
            } catch {
                standardError("error: \(error)\n")
                return .failure
            }

            // Render each pair's triplet from its arm's census grid. Converter
            // arms own complete grids; selection arms share the inverted
            // production scaffold and differ only in glyph selection.
            let fixtureBySource = Dictionary(
                fixtures.map { ($0.source.key, $0.fixture) }, uniquingKeysWith: { first, _ in first })
            do {
                for pair in pairs {
                    guard
                        let census = censuses["\(pair.source.key)|\(pair.charset)"],
                        let fixture = fixtureBySource[pair.source.key],
                        let gridA = census.grids[pair.armA],
                        let gridB = census.grids[pair.armB]
                    else {
                        standardError("error: no census for \(pair.id)\n")
                        return .failure
                    }
                    let imageA = Stimuli.render(grid: gridA)
                    let imageB = Stimuli.render(grid: gridB)
                    let (left, right) = pair.leftIsArmA ? (imageA, imageB) : (imageB, imageA)
                    guard
                        let reference = Stimuli.reference(
                            fixture.image, width: left.width, height: left.height)
                    else {
                        standardError("error: could not scale the reference for \(pair.id)\n")
                        return .ioError
                    }

                    try DemoImageIO.writePNG(
                        reference, to: outputURL.appending(path: "\(pair.id)-ref.png").path)
                    try DemoImageIO.writePNG(
                        left, to: outputURL.appending(path: "\(pair.id)-left.png").path)
                    try DemoImageIO.writePNG(
                        right, to: outputURL.appending(path: "\(pair.id)-right.png").path)
                    if let sheet = Stimuli.sheet(
                        reference: reference, left: left, right: right,
                        label: Stimuli.sheetLabel(for: pair))
                    {
                        try DemoImageIO.writePNG(
                            sheet, to: outputURL.appending(path: "sheet/\(pair.id).png").path)
                    }
                }

                try Stimuli.answersTemplateCSV(pairs)
                    .write(
                        to: outputURL.appending(path: "answers-template.csv"), atomically: true,
                        encoding: .utf8)
                try StableJSON.write(
                    KeyFile(seed: arguments.seed, pairs: pairs),
                    to: outputURL.appending(path: "key.json"))

                let manifest = Stimuli.Manifest(
                    schemaVersion: "2",
                    protocolVersion: Arbiter.protocolVersion,
                    protocolNote: Arbiter.protocolNote,
                    runner: "AskiColorLab",
                    date: date,
                    askiGitSHA: GitSHA.resolve(override: arguments.gitShaOverride),
                    command: "AskiColorLab arbiter stimuli --output-dir \(arguments.outputDirectory)"
                        + " --seed \(arguments.seed) --columns \(plan.columns)"
                        + " --oversample \(plan.oversample) --footprint \(plan.footprint)",
                    seed: arguments.seed,
                    columns: plan.columns,
                    oversample: plan.oversample,
                    footprint: plan.footprint,
                    gatingCharset: plan.gatingCharset,
                    denseCharset: plan.denseCharset,
                    toneWeights: plan.toneWeights,
                    topKs: plan.topKs,
                    sources: fixtures.map(\.source),
                    pairCount: pairs.count,
                    calibrationLadderRule: Stimuli.calibrationLadderRule,
                    adversarialObjective: Stimuli.adversarialObjective)
                try StableJSON.write(manifest, to: outputURL.appending(path: "manifest.json"))
            } catch {
                standardError("error: \(error)\n")
                return .ioError
            }

            standardOutput(
                "wrote \(pairs.count) blinded triplets + sheet/ + answers-template.csv + key.json to \(outputURL.path)\n"
            )
            standardOutput(
                "BLINDING: rate the sheet in one sitting, same display, and submit answers BEFORE opening key.json.\n"
            )
            return .success
        }

        // MARK: - `arbiter judge`

        struct JudgeArguments: Sendable {
            var outputDirectory: String
            var stimuliDirectory: String
            var gitShaOverride: String?
            var runnerExecutable: String?
            var runnerArguments: [String]
            var includeCalibration: Bool
            var samplesPerOrder: Int
        }

        /// V2 §3 scope: V + D + X + M always; C only with
        /// `--include-calibration`.
        static func judgedFamilies(includeCalibration: Bool) -> Set<Family> {
            var families: Set<Family> = [
                .validation, .disagreement, .polarity, .adversarial,
            ]
            if includeCalibration { families.insert(.calibration) }
            return families
        }

        static func judge(
            arguments: JudgeArguments,
            runner injectedRunner: ArbiterJudgeRunner? = nil,
            standardOutput: (String) -> Void = { print($0, terminator: "") },
            standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
            date: String = todayUTC()
        ) -> LabExitCode {
            let stimuliURL = URL(fileURLWithPath: arguments.stimuliDirectory)
            let outputURL = URL(fileURLWithPath: arguments.outputDirectory)
            let pairs: [Pair]
            do {
                try FileManager.default.createDirectory(
                    at: outputURL, withIntermediateDirectories: true)
                let data = try Data(contentsOf: stimuliURL.appending(path: "key.json"))
                pairs = try JSONDecoder().decode(KeyFile.self, from: data).pairs()
            } catch {
                standardError("error: \(error)\n")
                return .ioError
            }

            var config: Judge.Config
            do {
                config =
                    try arguments.runnerExecutable.map {
                        try Judge.Config.validatedInjected(
                            executable: $0, arguments: arguments.runnerArguments)
                    } ?? Judge.Config.default
            } catch {
                standardError("error: \(error)\n")
                return .usage
            }
            if arguments.samplesPerOrder != config.samplesPerOrder {
                config = Judge.Config(
                    transport: config.transport, executable: config.executable,
                    argumentTemplate: config.argumentTemplate, modelID: config.modelID,
                    reasoningEffort: config.reasoningEffort, prompt: config.prompt,
                    promptSHA256: config.promptSHA256,
                    samplesPerOrder: arguments.samplesPerOrder, orderPolicy: config.orderPolicy)
            }
            let runner =
                injectedRunner
                ?? Judge.SubprocessRunner(
                    executable: config.executable, argumentTemplate: config.argumentTemplate)

            let families = judgedFamilies(includeCalibration: arguments.includeCalibration)
            let scoped = pairs.filter { families.contains($0.family) }
            var judgements: [Judge.PairJudgement] = []
            do {
                for pair in scoped {
                    judgements.append(
                        try Judge.judgePair(
                            pair: pair, directory: stimuliURL, runner: runner, config: config))
                    standardOutput("judged \(pair.id)\n")
                }
                try StableJSON.write(config, to: outputURL.appending(path: "judge.json"))
                try StableJSON.write(
                    judgements, to: outputURL.appending(path: "judge-results.json"))
            } catch {
                standardError("error: \(error)\n")
                return .ioError
            }
            _ = date
            standardOutput(
                "judged \(judgements.count) pairs (\(config.samplesPerOrder) samples x 2 orders each) -> judge-results.json\n"
            )
            standardOutput(
                "REMINDER: VLM verdicts count for nothing until the section 5.1 gate passes, and never alone on near-ties.\n"
            )
            return .success
        }

        // MARK: - `arbiter score`

        struct ScoreArguments: Sendable {
            var outputDirectory: String
            var stimuliDirectory: String
            var answersPath: String?
            var judgeResultsPath: String?
            var gitShaOverride: String?
        }

        static func score(
            arguments: ScoreArguments,
            standardOutput: (String) -> Void = { print($0, terminator: "") },
            standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
            date: String = todayUTC()
        ) -> LabExitCode {
            let stimuliURL = URL(fileURLWithPath: arguments.stimuliDirectory)
            let outputURL = URL(fileURLWithPath: arguments.outputDirectory)
            let key: KeyFile
            do {
                try FileManager.default.createDirectory(
                    at: outputURL, withIntermediateDirectories: true)
                let data = try Data(contentsOf: stimuliURL.appending(path: "key.json"))
                key = try JSONDecoder().decode(KeyFile.self, from: data)
            } catch {
                standardError("error: \(ArbiterError.keyUnreadable(stimuliURL.path)) (\(error))\n")
                return .ioError
            }

            var answers: [String: Choice] = [:]
            if let answersPath = arguments.answersPath {
                do {
                    let csv = try String(contentsOf: URL(fileURLWithPath: answersPath), encoding: .utf8)
                    answers = try Score.parseAnswers(
                        csv: csv, known: Set(key.entries.map(\.pairID)))
                } catch let error as ArbiterError {
                    standardError("error: \(error)\n")
                    return .usage
                } catch {
                    standardError("error: \(error)\n")
                    return .ioError
                }
            }

            var judgements: [Judge.PairJudgement] = []
            if let judgePath = arguments.judgeResultsPath {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: judgePath))
                    judgements = try JSONDecoder().decode([Judge.PairJudgement].self, from: data)
                } catch {
                    standardError("error: \(error)\n")
                    return .ioError
                }
            }

            let report: Score.Report
            do {
                report = try Score.score(
                    .init(key: key, humanAnswers: answers, judgements: judgements))
            } catch {
                standardError("error: \(error)\n")
                return .ioError
            }
            let readout = Score.readout(report, protocolVersion: key.protocolVersion)
            // The provenance command must replay to the same verdict, so the
            // input paths are part of it, not just the directories.
            var command =
                "AskiColorLab arbiter score --output-dir \(arguments.outputDirectory)"
                + " --stimuli-dir \(arguments.stimuliDirectory)"
            if let answersPath = arguments.answersPath {
                command += " --answers \(answersPath)"
            }
            if let judgePath = arguments.judgeResultsPath {
                command += " --judge-results \(judgePath)"
            }
            let yaml = Score.resultYAML(
                report: report, date: date,
                gitSHA: GitSHA.resolve(override: arguments.gitShaOverride),
                seed: key.seed,
                command: command,
                outputs: ["readout.md"],
                protocolVersion: key.protocolVersion)
            do {
                try readout.write(
                    to: outputURL.appending(path: "readout.md"), atomically: true, encoding: .utf8)
                try yaml.write(
                    to: outputURL.appending(path: "result.yaml"), atomically: true, encoding: .utf8)
            } catch {
                standardError("error: \(error)\n")
                return .ioError
            }

            standardOutput(readout)
            if report.exitCode == .failure {
                standardError(
                    "GATE FAILED (section 5.1): the human leg answered only \(report.humanValidationCorrect)/\(report.humanValidationTotal) validation pairs correctly. Nothing downstream of a failed gate means anything.\n"
                )
            }
            return report.exitCode
        }
    }
}
