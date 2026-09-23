import Aski
import AskiToolSupport
import Foundation
import simd

public enum DecolorLabCLI {
    public static let usage = """
        AskiDecolorLab - research harness for composited-cell perceptual oracle and color-theory gate.

        Usage:
          swift run AskiDecolorLab evaluate --output-dir <dir> [options]
          swift run AskiDecolorLab check [options]

        Required for evaluate:
          --output-dir <dir>          Directory to write perceived_fidelity.csv and result.yaml.

        Options:
          --columns <int>             ASCII columns for rendered-grid fixtures. Default: 80.
          --background-hex <color>    Background hex color (#RRGGBB). Default: #101010.
          --aski-git-sha <sha>        Override the git SHA recorded in result.yaml.
          --help, -h                  Print this usage.
        """

    public static func run(
        arguments: DecolorLabArguments,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = DecolorLabCLI.todayUTC()
    ) -> LabExitCode {
        // Decode backgroundHex → encoded SIMD3<Float>
        guard let backgroundEncoded = hexToEncoded(arguments.backgroundHex) else {
            standardError("error: invalid --background-hex '\(arguments.backgroundHex)'; expected #RRGGBB\n\n\(usage)\n")
            return .usage
        }

        let gitSHA = GitSHA.resolve(override: arguments.gitShaOverride)
        let command = commandLine(arguments, verb: "evaluate")

        // Validate manifest metadata (reject control chars)
        do {
            try DecolorLabResults.validatedManifestMetadata(gitSHA: gitSHA, command: command)
        } catch {
            standardError("error: \(error)\n\n\(usage)\n")
            return .usage
        }

        let outputURL = URL(fileURLWithPath: arguments.outputDirectory)

        // Gather oracle rows for all palettes
        guard
            let rows = gatherRows(
                arguments: arguments,
                backgroundEncoded: backgroundEncoded,
                gitSHA: gitSHA,
                command: command,
                standardError: standardError
            )
        else {
            return .failure
        }

        // Gate verdict for summary
        let gateResult = DecolorGate.evaluate(rows: rows)
        let verdict = gateResult.passed ? "PASS" : "KILL"
        let summary = DecolorLabResults.summarySentence(rows: rows, gateVerdict: verdict)

        // Write artifacts
        do {
            try DecolorLabResults.writeCSV(rows: rows, outputDirectory: outputURL)
            try DecolorLabResults.writeManifest(
                outputDirectory: outputURL,
                date: date,
                gitSHA: gitSHA,
                command: command,
                summary: summary
            )
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        standardOutput("wrote \(rows.count) rows to \(outputURL.path)\n")
        return .success
    }

    public static func check(
        arguments: DecolorLabArguments,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        // Decode backgroundHex → encoded SIMD3<Float>
        guard let backgroundEncoded = hexToEncoded(arguments.backgroundHex) else {
            standardError("error: invalid --background-hex '\(arguments.backgroundHex)'; expected #RRGGBB\n\n\(usage)\n")
            return .usage
        }

        let gitSHA = GitSHA.resolve(override: arguments.gitShaOverride)
        let command = commandLine(arguments, verb: "check")

        // Gather oracle rows for all palettes (no file writes)
        guard
            let rows = gatherRows(
                arguments: arguments,
                backgroundEncoded: backgroundEncoded,
                gitSHA: gitSHA,
                command: command,
                standardError: standardError
            )
        else {
            return .failure
        }

        let result = DecolorGate.evaluate(rows: rows)
        standardOutput("\(result.detail)\n")
        return result.passed ? .success : .failure
    }

    public static func todayUTC() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Helpers

    /// Parse `#RRGGBB` hex string to an encoded-sRGB SIMD3<Float>. Returns nil on malformed input.
    public static func hexToEncoded(_ hex: String) -> SIMD3<Float>? {
        var s = hex
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, s.allSatisfy(\.isHexDigit) else { return nil }
        guard
            let r = UInt8(s.prefix(2), radix: 16),
            let g = UInt8(s.dropFirst(2).prefix(2), radix: 16),
            let b = UInt8(s.dropFirst(4).prefix(2), radix: 16)
        else { return nil }
        return SIMD3<Float>(Float(r) / 255, Float(g) / 255, Float(b) / 255)
    }

    /// Gather oracle rows for every palette. Returns `nil` (after writing to `standardError`)
    /// on any sample error, preserving the same `.failure` exit-code mapping as the original
    /// per-subcommand loops.
    private static func gatherRows(
        arguments: DecolorLabArguments,
        backgroundEncoded: SIMD3<Float>,
        gitSHA: String,
        command: String,
        options: RenderingOptions = .default,
        inkModel: DecolorInkModel = .relativeRamp,
        standardError: (String) -> Void
    ) -> [OracleRow]? {
        var rows: [OracleRow] = []
        for palette in DecolorPalettes.all {
            do {
                let paletteRows = try DecolorFixtures.samples(
                    palette: palette,
                    columns: arguments.columns,
                    backgroundEncoded: backgroundEncoded,
                    gitSHA: gitSHA,
                    command: command,
                    options: options,
                    inkModel: inkModel
                )
                rows.append(contentsOf: paletteRows)
            } catch {
                standardError("error: \(error)\n")
                return nil
            }
        }
        return rows
    }

    private static func commandLine(_ arguments: DecolorLabArguments, verb: String) -> String {
        var parts = [
            "swift run AskiDecolorLab \(verb)",
            "--output-dir \(arguments.outputDirectory)",
            "--columns \(arguments.columns)",
            "--background-hex \(arguments.backgroundHex)",
        ]
        if let gitShaOverride = arguments.gitShaOverride {
            parts.append("--aski-git-sha \(gitShaOverride)")
        }
        return parts.joined(separator: " ")
    }
}
