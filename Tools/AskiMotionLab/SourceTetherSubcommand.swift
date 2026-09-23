import ArgumentParser
import AskiToolSupport
import Foundation

public struct SourceTetherSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "source-tether",
        abstract:
            "ASTSK-45 gate: source-tethered glyph hysteresis (rho sweep, EMA off) vs per-frame baseline on synthetic motion."
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(help: "Stimulus to run: all | s1 | s2. A full verdict requires all.")
    public var stimulus: StimulusSelection = .all

    @Option(help: "Columns to sweep: all | 64 | 80. A full verdict requires all.")
    public var columns: ColumnSelection = .all

    public init() {}

    public func run() throws {
        try execute()
    }

    func execute(
        runExperiment: ([TemporalStimulus], [Int]) -> (
            cells: [SourceTetherCell], verdict: SourceTetherVerdict?, sharedRho: Float?
        ) = SourceTetherExperiment.run,
        standardOutput: (String) -> Void = { print($0, terminator: "") }
    ) throws {
        let result = runExperiment(stimulus.stimuli, columns.columns)
        let report = SourceTetherExperiment.format(
            cells: result.cells,
            verdict: result.verdict,
            sharedRho: result.sharedRho
        )
        standardOutput(report)

        let outputDirectory = URL(fileURLWithPath: provenance.outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try report.write(
            to: outputDirectory.appendingPathComponent("source-tether-report.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
