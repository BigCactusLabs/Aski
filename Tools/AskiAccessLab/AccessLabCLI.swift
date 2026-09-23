import AskiToolSupport
import Foundation

public enum AccessLabCLI {
    public static let usage = """
        AskiAccessLab - audit Aski palettes and rendered ASCII outputs for CVD distinguishability.

        Usage:
          swift run AskiAccessLab audit --output-dir <dir> [options]

        Required:
          --output-dir <dir>      Directory to write accessibility.csv and result.yaml.

        Options:
          --columns <int>         ASCII columns for rendered-grid fixtures. Default: 80.
          --aski-git-sha <sha>    Override the git SHA recorded in result.yaml.
          --help, -h              Print this usage.
        """

    public static func run(
        arguments: AccessLabArguments,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = AccessLabCLI.todayUTC()
    ) -> LabExitCode {
        let gitSHA = GitSHA.resolve(override: arguments.gitShaOverride)
        let command = commandLine(arguments)
        do {
            try AccessLabResults.validatedManifestMetadata(gitSHA: gitSHA, command: command)
        } catch {
            standardError("error: \(error)\n\n\(usage)\n")
            return .usage
        }

        let outputURL = URL(fileURLWithPath: arguments.outputDirectory)
        let samples: [AccessSample]
        do {
            samples = try AccessFixtures.allSamples(columns: arguments.columns)
        } catch {
            standardError("error: \(error)\n")
            return .failure
        }

        var rows: [AccessScoreRow] = []
        rows.reserveCapacity(samples.count * ColorVisionDeficiency.allCases.count)
        for sample in samples {
            for deficiency in ColorVisionDeficiency.allCases {
                var row = AccessScoring.score(sample: sample, deficiency: deficiency)
                row.command = command
                row.askiGitSHA = gitSHA
                rows.append(row)
            }
        }

        do {
            try AccessLabResults.writeCSV(rows: rows, outputDirectory: outputURL)
            try AccessLabResults.writeManifest(
                outputDirectory: outputURL,
                date: date,
                gitSHA: gitSHA,
                command: command,
                rows: rows
            )
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        standardOutput("wrote \(rows.count) accessibility rows to \(outputURL.path)\n")
        return .success
    }

    public static func todayUTC() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func commandLine(_ arguments: AccessLabArguments) -> String {
        var parts = [
            "swift run AskiAccessLab audit",
            "--output-dir \(arguments.outputDirectory)",
            "--columns \(arguments.columns)",
        ]
        if let gitShaOverride = arguments.gitShaOverride {
            parts.append("--aski-git-sha \(gitShaOverride)")
        }
        return parts.joined(separator: " ")
    }
}
