@_spi(AskiResearch) import Aski
import AskiToolSupport
import CoreGraphics
import CoreImage
import Foundation

/// Arguments shared by the `evaluate` and `check` subcommands.
struct HDRLabArguments: Sendable {
    var outputDirectory: String
    var columns: Int
    var backgroundHex: String
    var gitShaOverride: String?
    var selftestForceKill: Bool = false
}

/// Drives the HDR-emissive spike: render each fixture SDR + HDR-emissive across a
/// `k` sweep, author a gain-map HEIC per sample, measure G1–G4, and emit a
/// decisive verdict.
public enum HDRLabCLI {
    // Frozen render + sweep configuration.
    static let fontSize: CGFloat = 12
    static let kSweep: [Float] = [0, 1, 2, 4]
    static let emissionThreshold: Float = 0.5
    static let emissionMaxHeadroom: Float = 8

    static let usage = """
        AskiHDRLab - HDR/EDR emissive render spike (gain-map Adaptive HDR HEIC).

        Usage:
          swift run AskiHDRLab evaluate --output-dir <dir> [--columns N] [--background-hex #RRGGBB]
          swift run AskiHDRLab check    [--columns N] [--background-hex #RRGGBB]

        evaluate writes heic/, tiff/, hdr.csv, result.yaml and prints the verdict (always exits 0).
        check is the fail-fast gate: nonzero exit on KILL.
        """

    // MARK: - evaluate (reporter)

    static func evaluate(
        arguments: HDRLabArguments,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = todayUTC()
    ) -> LabExitCode {
        guard let background = cgColor(fromHex: arguments.backgroundHex) else {
            standardError("error: invalid --background-hex '\(arguments.backgroundHex)'; expected #RRGGBB\n\n\(usage)\n")
            return .usage
        }
        let gitSHA = GitSHA.resolve(override: arguments.gitShaOverride)
        let command = commandLine(arguments, verb: "evaluate")
        do {
            try HDRResultsWriter.validatedManifestMetadata(gitSHA: gitSHA, command: command)
        } catch {
            standardError("error: \(error)\n\n\(usage)\n")
            return .usage
        }

        let outputURL = URL(fileURLWithPath: arguments.outputDirectory)
        let heicDir = outputURL.appendingPathComponent("heic")
        let tiffDir = outputURL.appendingPathComponent("tiff")
        do {
            try FileManager.default.createDirectory(at: heicDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: tiffDir, withIntermediateDirectories: true)
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        guard
            let gathered = gather(
                arguments: arguments, background: background,
                heicDir: heicDir, tiffDir: tiffDir, standardError: standardError
            )
        else {
            return .failure
        }

        let verdict = HDRGates.evaluate(gathered.rows)
        let summary = summarySentence(verdict: verdict, displayEDR: gathered.displayEDR, rowCount: gathered.rows.count)

        do {
            try HDRResultsWriter.writeCSV(rows: gathered.rows, displayEDRHeadroom: gathered.displayEDR, outputDirectory: outputURL)
            try HDRResultsWriter.writeManifest(outputDirectory: outputURL, date: date, gitSHA: gitSHA, command: command, summary: summary)
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        let edrText = gathered.displayEDR.map { String(format: "%.3f", $0) } ?? "n/a (headless or off-main-thread)"
        standardOutput("\(verdict.detail)\ndisplay EDR headroom: \(edrText)\nwrote \(gathered.rows.count) rows + HEICs/TIFFs to \(outputURL.path)\n")
        return .success
    }

    // MARK: - check (gate)

    static func check(
        arguments: HDRLabArguments,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        guard let background = cgColor(fromHex: arguments.backgroundHex) else {
            standardError("error: invalid --background-hex '\(arguments.backgroundHex)'; expected #RRGGBB\n\n\(usage)\n")
            return .usage
        }
        let heicDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AskiHDRLab-check-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: heicDir, withIntermediateDirectories: true)
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }
        defer { try? FileManager.default.removeItem(at: heicDir) }

        guard
            var gathered = gather(
                arguments: arguments, background: background,
                heicDir: heicDir, tiffDir: nil, standardError: standardError
            ).map({ $0.rows })
        else {
            return .failure
        }

        if arguments.selftestForceKill {
            // Inject an impossible measurement so the fail-fast path can be tested.
            gathered.append(
                HDRMeasurement(
                    fixtureID: "selftest", gamut: "sRGB", expectation: "blooms",
                    k: 1, threshold: emissionThreshold, maxHeadroom: emissionMaxHeadroom,
                    contentHeadroom: 1.0, hdrMaxChannel: 1.0, g1MeanDiff: 1.0, g2MeanDiff: 1.0,
                    floatClean: false, heicBytes: 0
                ))
        }

        let verdict = HDRGates.evaluate(gathered)
        standardOutput("\(verdict.detail)\n")
        return verdict.passed ? .success : .failure
    }

    // MARK: - Shared gather

    private static func gather(
        arguments: HDRLabArguments,
        background: CGColor,
        heicDir: URL,
        tiffDir: URL?,
        standardError: (String) -> Void
    ) -> (rows: [HDRMeasurement], displayEDR: Double?)? {
        let font = ASCIIFont.system(size: fontSize)
        var rows: [HDRMeasurement] = []
        // One CIContext for the whole run (~2 Core Image methods × 24 samples would
        // otherwise build ~48). Confined to this synchronous call tree, so the
        // non-Sendable context stays thread-safe. (`contentHeadroom` builds none.)
        let ciContext = CIContext()

        for fixture in HDRFixtures.all(columns: arguments.columns) {
            let sdr = fixture.grid.renderImage(font: font, backgroundColor: background, scale: 1)
            let gamutSpace = cgColorSpace(for: fixture.gamut)
            var lastHDR: CGImage?

            for k in kSweep {
                let emission = EmissionOptions(
                    k: k,
                    threshold: emissionThreshold,
                    maxHeadroom: emissionMaxHeadroom,
                    source: fixture.emissionSource
                )
                let rendered = fixture.grid.renderExtendedRangeImage(
                    font: font, backgroundColor: background, scale: 1, emission: emission
                )
                guard let hdr = rendered else {
                    standardError("error: fixture \(fixture.id) unexpectedly rejected by renderExtendedRangeImage (opaque fixtures should always render)\n")
                    return nil
                }
                // Secondary assertion: parity with the SDR base is the gain-map precondition.
                guard hdr.width == sdr.width, hdr.height == sdr.height else {
                    standardError("error: fixture \(fixture.id) HDR/SDR dimension mismatch\n")
                    return nil
                }
                lastHDR = hdr

                let floatStats = HDRArtifacts.floatStats(hdr, maxHeadroom: emissionMaxHeadroom)
                let heicURL = heicDir.appendingPathComponent("\(fixture.id)-k\(fmtK(k)).heic")
                do {
                    try HDRArtifacts.writeGainMapHEIC(sdr: sdr, hdr: hdr, gamutSpace: gamutSpace, ciContext: ciContext, to: heicURL)
                } catch {
                    standardError("error: \(fixture.id) k=\(fmtK(k)): \(error)\n")
                    return nil
                }
                let headroom = HDRArtifacts.contentHeadroom(ofHEIC: heicURL)
                let g1 = HDRArtifacts.sdrBaseMeanDiff(heic: heicURL, vs: sdr)
                let g2 = HDRArtifacts.toneMappedMeanDiff(heic: heicURL, gamutSpace: gamutSpace, ciContext: ciContext, vs: sdr)
                let bytes = (try? Data(contentsOf: heicURL).count) ?? 0

                rows.append(
                    HDRMeasurement(
                        fixtureID: fixture.id,
                        gamut: gamutLabel(fixture.gamut),
                        expectation: fixture.expectation.rawValue,
                        k: k,
                        threshold: emissionThreshold,
                        maxHeadroom: emissionMaxHeadroom,
                        contentHeadroom: headroom,
                        hdrMaxChannel: floatStats.maxChannel,
                        g1MeanDiff: g1,
                        g2MeanDiff: g2,
                        floatClean: !floatStats.hasNaNOrInf && !floatStats.exceedsCeiling,
                        heicBytes: bytes
                    ))
            }

            if let tiffDir, let lastHDR {
                HDRArtifacts.writeTIFF(lastHDR, to: tiffDir.appendingPathComponent("\(fixture.id).tiff"))
            }
        }

        return (rows, HDRArtifacts.displayEDRHeadroom())
    }

    // MARK: - Helpers

    public static func todayUTC() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func summarySentence(verdict: HDRGates.Verdict, displayEDR: Double?, rowCount: Int) -> String {
        let edr = displayEDR.map { String(format: "%.2f", $0) } ?? "n/a"
        return
            "AskiHDRLab authored gain-map Adaptive HDR HEICs from \(rowCount) (fixture, k) samples and graded G1 fallback fidelity, G2 tone-map round-trip, G3 content headroom, and G4 float integrity — verdict \(verdict.passed ? "PASS" : "KILL"); dev-display EDR headroom \(edr)."
    }

    private static func commandLine(_ arguments: HDRLabArguments, verb: String) -> String {
        var parts = [
            "swift run AskiHDRLab \(verb)",
            "--output-dir \(arguments.outputDirectory)",
            "--columns \(arguments.columns)",
            "--background-hex \(arguments.backgroundHex)",
        ]
        if let override = arguments.gitShaOverride {
            parts.append("--aski-git-sha \(override)")
        }
        return parts.joined(separator: " ")
    }

    private static func gamutLabel(_ space: RenderColorSpace) -> String {
        switch space {
        case .sRGB: "sRGB"
        case .displayP3: "displayP3"
        }
    }

    private static func cgColorSpace(for space: RenderColorSpace) -> CGColorSpace {
        switch space {
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        }
    }

    private static func fmtK(_ k: Float) -> String {
        String(format: "%.0f", k)
    }

    private static func cgColor(fromHex hex: String) -> CGColor? {
        var string = hex
        if string.hasPrefix("#") { string = String(string.dropFirst()) }
        guard string.count == 6, string.allSatisfy(\.isHexDigit),
            let r = UInt8(string.prefix(2), radix: 16),
            let g = UInt8(string.dropFirst(2).prefix(2), radix: 16),
            let b = UInt8(string.dropFirst(4).prefix(2), radix: 16)
        else { return nil }
        return CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}
