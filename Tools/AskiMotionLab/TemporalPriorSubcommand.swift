import ArgumentParser
import AskiToolSupport
import Foundation

/// Selector for which stimulus to sweep.
public enum StimulusSelection: String, CaseIterable, ExpressibleByArgument {
    case all
    case s1
    case s2

    public var stimuli: [TemporalStimulus] {
        switch self {
        case .all:
            TemporalStimulus.allCases
        case .s1:
            [.s1]
        case .s2:
            [.s2]
        }
    }
}

/// Selector for which column counts to sweep.
public enum ColumnSelection: String, CaseIterable, ExpressibleByArgument {
    case all
    case c64 = "64"
    case c80 = "80"

    public var columns: [Int] {
        switch self {
        case .all:
            [64, 80]
        case .c64:
            [64]
        case .c80:
            [80]
        }
    }
}

public struct TemporalPriorSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "temporal-prior",
        abstract: "ASTSK-41 gate: EMA + hysteresis temporal prior vs per-frame baseline on synthetic motion."
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
            cells: [GateCell], verdict: TemporalVerdict?, sharedPoint: (alpha: Float, tau: Float)?
        ) = TemporalPriorExperiment.run,
        standardOutput: (String) -> Void = { print($0, terminator: "") }
    ) throws {
        let result = runExperiment(stimulus.stimuli, columns.columns)
        let report = TemporalPriorExperiment.format(
            cells: result.cells,
            verdict: result.verdict,
            sharedPoint: result.sharedPoint
        )
        standardOutput(report)

        let outputDirectory = URL(fileURLWithPath: provenance.outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try report.write(
            to: outputDirectory.appendingPathComponent("temporal-prior-report.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
