import CoreText
import Foundation

enum VectorDriftAuditError: Error, CustomStringConvertible {
    case invalidBinary(String)
    case glyphSetChanged(set: String)

    var description: String {
        switch self {
        case .invalidBinary(let detail): "invalid ShapeData binary: \(detail)"
        case .glyphSetChanged(let set): "fresh and committed glyph sets differ for \(set)"
        }
    }
}

struct VectorBinGlyph: Equatable {
    let scalar: UInt32
    let brightness: Float
    let shape: [Float]
    let rawDensity: Float
    let orientationHistogram: [Float]
    let radialPeak: Float
}

struct VectorBin: Equatable {
    let name: String
    let glyphs: [VectorBinGlyph]

    static func decode(_ data: Data) throws -> VectorBin {
        var cursor = BinaryCursor(data: data)
        guard try cursor.u32() == 0xA5C1_1E01 else {
            throw VectorDriftAuditError.invalidBinary("wrong magic")
        }
        guard try cursor.u32() == 3 else {
            throw VectorDriftAuditError.invalidBinary("audit requires format v3")
        }
        guard try cursor.u32() == 1 else {
            throw VectorDriftAuditError.invalidBinary("audit requires one set per file")
        }
        let nameLength = Int(try cursor.u32())
        guard let name = String(data: try cursor.bytes(count: nameLength), encoding: .utf8) else {
            throw VectorDriftAuditError.invalidBinary("set name is not UTF-8")
        }
        let count = Int(try cursor.u32())
        let dimension = Int(try cursor.u32())
        guard dimension == 60 else {
            throw VectorDriftAuditError.invalidBinary("expected 60 shape values, got \(dimension)")
        }
        let scalars = try (0..<count).map { _ in try cursor.u32() }
        let brightness = try (0..<count).map { _ in try cursor.f32() }
        var shapes: [[Float]] = []
        shapes.reserveCapacity(count)
        for _ in 0..<count {
            shapes.append(try (0..<dimension).map { _ in try cursor.f32() })
        }
        let rawDensity = try (0..<count).map { _ in try cursor.f32() }
        var histograms: [[Float]] = []
        histograms.reserveCapacity(count)
        for _ in 0..<count {
            histograms.append(try (0..<8).map { _ in try cursor.f32() })
        }
        let radialPeaks = try (0..<count).map { _ in try cursor.f32() }
        guard cursor.isAtEnd else {
            throw VectorDriftAuditError.invalidBinary("trailing bytes")
        }
        for index in 0..<count {
            let channels: [(String, [Float])] = [
                ("brightness", [brightness[index]]),
                ("shape", shapes[index]),
                ("raw density", [rawDensity[index]]),
                ("orientation histogram", histograms[index]),
                ("radial peak", [radialPeaks[index]]),
            ]
            guard channels.allSatisfy({ $0.1.allSatisfy(\.isFinite) }) else {
                let channel = channels.first { !$0.1.allSatisfy(\.isFinite) }!.0
                throw VectorDriftAuditError.invalidBinary(
                    "non-finite \(channel) for scalar U+\(String(scalars[index], radix: 16, uppercase: true))")
            }
        }
        let glyphs = (0..<count).map { index in
            VectorBinGlyph(
                scalar: scalars[index],
                brightness: brightness[index],
                shape: shapes[index],
                rawDensity: rawDensity[index],
                orientationHistogram: histograms[index],
                radialPeak: radialPeaks[index])
        }
        return VectorBin(name: name, glyphs: glyphs)
    }
}

private struct BinaryCursor {
    let data: Data
    private(set) var offset = 0

    var isAtEnd: Bool { offset == data.count }

    mutating func bytes(count: Int) throws -> Data {
        guard count >= 0, offset <= data.count - count else {
            throw VectorDriftAuditError.invalidBinary("truncated at byte \(offset)")
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func u32() throws -> UInt32 {
        let chunk = try bytes(count: 4)
        return chunk.withUnsafeBytes { raw in
            UInt32(littleEndian: raw.loadUnaligned(as: UInt32.self))
        }
    }

    mutating func f32() throws -> Float {
        Float(bitPattern: try u32())
    }
}

struct GlyphDrift: Equatable {
    let set: String
    let scalar: UInt32
    let brightness: Float
    let rawDensity: Float
    let shape: Float
    let orientation: Float
    let radialPeak: Float

    var maximum: Float {
        max(brightness, rawDensity, shape, orientation, radialPeak)
    }
}

struct SetDrift: Equatable {
    let name: String
    let byteIdentical: Bool
    let sortPermutationChanged: Bool
    let glyphs: [GlyphDrift]

    var changedGlyphCount: Int { glyphs.count { $0.maximum > 0 } }
    var maximum: Float { glyphs.map(\.maximum).max() ?? 0 }
}

struct VectorDriftAuditResult {
    static let tolerance: Float = 0.001

    let sets: [SetDrift]

    var sortPermutationChanged: Bool { sets.contains { $0.sortPermutationChanged } }
    var maximum: Float { sets.map(\.maximum).max() ?? 0 }
    var thresholdExceeded: Bool { maximum > Self.tolerance }
    var triggerFired: Bool { thresholdExceeded || sortPermutationChanged }
    var consoleSummary: String {
        "Vector drift audit: \(sets.count) sets; max delta \(formatFloat(maximum)); "
            + "sort permutation changed: \(sortPermutationChanged ? "yes" : "no"); "
            + "trigger: \(triggerFired ? "FIRED" : "not fired")"
    }
}

enum VectorDriftAudit {
    static func compare(name: String, committedData: Data, freshData: Data) throws -> SetDrift {
        let committed = try VectorBin.decode(committedData)
        let fresh = try VectorBin.decode(freshData)
        guard committed.name == name, fresh.name == name else {
            throw VectorDriftAuditError.invalidBinary("file/set name mismatch for \(name)")
        }
        let committedByScalar = Dictionary(uniqueKeysWithValues: committed.glyphs.map { ($0.scalar, $0) })
        let freshByScalar = Dictionary(uniqueKeysWithValues: fresh.glyphs.map { ($0.scalar, $0) })
        guard committedByScalar.keys == freshByScalar.keys else {
            throw VectorDriftAuditError.glyphSetChanged(set: name)
        }

        let drift = committedByScalar.keys.sorted().map { scalar in
            let old = committedByScalar[scalar]!
            let new = freshByScalar[scalar]!
            return GlyphDrift(
                set: name,
                scalar: scalar,
                brightness: abs(old.brightness - new.brightness),
                rawDensity: abs(old.rawDensity - new.rawDensity),
                shape: maximumAbsoluteDifference(old.shape, new.shape),
                orientation: maximumAbsoluteDifference(old.orientationHistogram, new.orientationHistogram),
                radialPeak: abs(old.radialPeak - new.radialPeak))
        }
        return SetDrift(
            name: name,
            byteIdentical: committedData == freshData,
            sortPermutationChanged: committed.glyphs.map(\.scalar) != fresh.glyphs.map(\.scalar),
            glyphs: drift)
    }

    static func run(
        root: URL,
        outputDirectory: URL,
        specs: [BuildStandardVectors.BuiltInSetSpec],
        font: CTFont
    ) throws -> VectorDriftAuditResult {
        var sets: [SetDrift] = []
        for spec in specs {
            let committedURL = root.appending(path: "Sources/Aski/Resources/ShapeData/\(spec.name).bin")
            let committedData = try Data(contentsOf: committedURL)
            let freshData = BuildStandardVectors.generateSingleCharsetBin(spec: spec, font: font)
            sets.append(try compare(name: spec.name, committedData: committedData, freshData: freshData))
        }
        let result = VectorDriftAuditResult(sets: sets)
        try write(result: result, root: root, outputDirectory: outputDirectory, specs: specs)
        return result
    }

    private static func write(
        result: VectorDriftAuditResult,
        root: URL,
        outputDirectory: URL,
        specs: [BuildStandardVectors.BuiltInSetSpec]
    ) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let glyphCSV =
            (["set,unicode_scalar,brightness_delta,raw_density_delta,shape_max_delta,orientation_max_delta,radial_peak_delta,overall_max_delta"]
            + result.sets.flatMap { set in
                set.glyphs.map { glyph in
                    [
                        glyph.set,
                        String(format: "U+%04X", glyph.scalar),
                        formatFloat(glyph.brightness),
                        formatFloat(glyph.rawDensity),
                        formatFloat(glyph.shape),
                        formatFloat(glyph.orientation),
                        formatFloat(glyph.radialPeak),
                        formatFloat(glyph.maximum),
                    ].joined(separator: ",")
                }
            }).joined(separator: "\n") + "\n"
        try glyphCSV.write(to: outputDirectory.appending(path: "glyph-drift.csv"), atomically: true, encoding: .utf8)

        let setCSV =
            (["set,glyph_count,byte_identical,changed_glyph_count,max_delta,sort_permutation_changed,threshold_exceeded"]
            + result.sets.map { set in
                [
                    set.name,
                    String(set.glyphs.count),
                    set.byteIdentical ? "true" : "false",
                    String(set.changedGlyphCount),
                    formatFloat(set.maximum),
                    set.sortPermutationChanged ? "true" : "false",
                    set.maximum > VectorDriftAuditResult.tolerance ? "true" : "false",
                ].joined(separator: ",")
            }).joined(separator: "\n") + "\n"
        try setCSV.write(to: outputDirectory.appending(path: "set-summary.csv"), atomically: true, encoding: .utf8)

        let gitSHA = command("/usr/bin/git", ["rev-parse", "HEAD"], at: root)
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString
        let xcode = command("/usr/bin/xcodebuild", ["-version"], at: root).replacingOccurrences(of: "\n", with: "; ")
        let swift = command("/usr/bin/xcrun", ["swift", "--version"], at: root).replacingOccurrences(of: "\n", with: "; ")
        let commandLine =
            "BuildStandardVectors --audit --output-dir \(relativePath(outputDirectory, root: root))"
            + (specs.count == 1 ? " --charset \(specs[0].name)" : "")
        let disposition = result.triggerFired ? "TRIGGERED" : "NO_TRIGGER"
        let changedSets = result.sets.filter { !$0.byteIdentical }.map(\.name)
        let summary = """
            # Core Text vector drift audit

            - Disposition: **\(disposition)**
            - Tolerance: `\(formatFloat(VectorDriftAuditResult.tolerance))` (strictly greater fires)
            - Maximum observed component delta: `\(formatFloat(result.maximum))`
            - Brightness sort permutation changed: **\(result.sortPermutationChanged ? "yes" : "no")**
            - Byte-identical sets: \(result.sets.count - changedSets.count) of \(result.sets.count)
            - Sets with byte drift: \(changedSets.isEmpty ? "none" : changedSets.joined(separator: ", "))

            The audit generated every selected v3 binary in memory. It did not write to `Sources/Aski/Resources/ShapeData/`.
            A trigger fires if any recorded component delta is greater than `0.001` or if the brightness-sorted scalar order changes.
            A snapshot or selection-golden change during an authorized regeneration is a separate trigger.

            ## Toolchain provenance

            - Aski commit: `\(gitSHA)`
            - macOS: `\(macOS)`
            - Xcode: `\(xcode)`
            - Swift: `\(swift)`
            - Command: `\(commandLine)`

            ## Files

            - `set-summary.csv`: per-set byte identity, maximum delta, and order result.
            - `glyph-drift.csv`: per-glyph deltas for all stored v3 channels.
            """ + "\n"
        try summary.write(to: outputDirectory.appending(path: "summary.md"), atomically: true, encoding: .utf8)

        let manifest = """
            ---
            schema_version: "1"
            date: 2026-09-04
            aski_git_sha: "\(gitSHA)"
            provenance: ["Read-only Core Text drift audit on \(yamlEscape(macOS))", "\(yamlEscape(xcode))", "\(yamlEscape(swift))"]
            outputs: ["glyph-drift.csv", "set-summary.csv", "summary.md"]
            runner: "BuildStandardVectors"
            command: "\(yamlEscape(commandLine))"
            summary: "ASKI-51 measured all selected committed v3 ShapeData binaries against fresh in-memory generation. Result: \(disposition); max component delta \(formatFloat(result.maximum)); sort change \(result.sortPermutationChanged ? "yes" : "no")."
            ---
            """ + "\n"
        try manifest.write(to: outputDirectory.appending(path: "result.yaml"), atomically: true, encoding: .utf8)
    }
}

private func maximumAbsoluteDifference(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count else { return .infinity }
    return zip(lhs, rhs).map { abs($0 - $1) }.max() ?? 0
}

private func formatFloat(_ value: Float) -> String {
    String(format: "%.9g", locale: Locale(identifier: "en_US_POSIX"), value)
}

private func relativePath(_ url: URL, root: URL) -> String {
    let prefix = root.standardizedFileURL.path + "/"
    let path = url.standardizedFileURL.path
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
}

private func command(_ executable: String, _ arguments: [String], at root: URL) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = root
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? "unavailable" : output
    } catch {
        return "unavailable"
    }
}

private func yamlEscape(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}
