import ArgumentParser
import AskiToolSupport
import Foundation
import Testing
@testable import AskiHDRLab
@testable import BuildResearchIndex

@Suite struct AskiHDRLabRunTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiHDRLabRunTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Small columns keep the per-test HEIC-encode cost bounded; the gates grade
    /// brightness/headroom, which is column-count independent.
    private func runEvaluate(_ outputDir: URL) throws -> LabExitCode {
        try HDREvaluateCommand.parse([
            "--output-dir", outputDir.path,
            "--columns", "16",
            "--background-hex", "#101010",
            "--aski-git-sha", "test-sha",
        ]).execute(standardOutput: { _ in }, standardError: { _ in }, date: "2026-06-16")
    }

    @Test func evaluateWritesCsvManifestAndHeics() throws {
        let dir = try temporaryDirectory()
        #expect(try runEvaluate(dir) == .success)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("hdr.csv").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("result.yaml").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("heic/bright-srgb-k4.heic").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("tiff/bright-srgb.tiff").path))
    }

    @Test func resultManifestParsesAndListsOnlyTopLevelOutput() throws {
        let dir = try temporaryDirectory()
        _ = try runEvaluate(dir)
        let text = try String(contentsOf: dir.appendingPathComponent("result.yaml"), encoding: .utf8)
        let manifest = try ResultManifest.from(try FrontMatterParser.parse(text))
        #expect(manifest.runner == "AskiHDRLab")
        #expect(manifest.schemaVersion == "1")
        #expect(Set(manifest.outputs) == ["hdr.csv"])
        #expect(manifest.askiGitSha == "test-sha")
        #expect(manifest.command?.contains("--aski-git-sha test-sha") == true)

        // Index-completeness self-consistency: the only top-level *files* are the
        // listed output + result.yaml (heic/ and tiff/ are subdirectories, which
        // the research-index check skips).
        let entries = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let topLevelFiles = try entries.filter {
            (try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
        }.map(\.lastPathComponent)
        #expect(Set(topLevelFiles) == ["hdr.csv", "result.yaml"])
    }

    @Test func hdrCsvHasHeaderAndOneRowPerSample() throws {
        let dir = try temporaryDirectory()
        _ = try runEvaluate(dir)
        let csv = try String(contentsOf: dir.appendingPathComponent("hdr.csv"), encoding: .utf8)
        var lines = csv.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        #expect(
            lines.first
                == "fixture,gamut,expectation,k,threshold,max_headroom,content_headroom,hdr_max_channel,g1_mean_diff,g2_mean_diff,float_clean,heic_bytes,display_edr_headroom")
        // 9 fixtures × 4 k-values = 36 sample rows + 1 header.
        #expect(lines.count == 37)
        #expect(csv.contains("authored-dark-emits"))
        #expect(csv.contains("authored-bright-flat"))
        #expect(csv.contains("authored-intensity-sweep"))
    }

    /// Smoke test on a *live* gain-map encode. Its absolute G1–G4 thresholds are
    /// SDK-coupled: Apple's gain-map encoder is not frozen across OS versions (iOS 18
    /// switched monochrome→RGB adaptive / ISO 21496-1; later releases add
    /// `calculateHDRStats*`), so `contentHeadroom` here is produced by a non-frozen
    /// system encoder. A break is a *signal*, not necessarily an Aski regression —
    /// acceptable since this runs locally with Actions off. Deterministic gate
    /// coverage lives in the synthetic unit tests (`HDRGatesTests`, `HDRArtifactsTests`);
    /// the encoder-survivable structural invariant is `bloomHeadroomExceedsControl`.
    @Test func checkPassesOnRealFixtures() throws {
        let dir = try temporaryDirectory()
        let status = try HDRCheckCommand.parse([
            "--output-dir", dir.path,
            "--columns", "16",
        ]).execute(standardOutput: { _ in }, standardError: { _ in })
        #expect(status == .success)
    }

    /// B3: the structural invariant that survives encoder changes — each *bloom*
    /// fixture's peak `content_headroom` strictly exceeds its own k=0 control by a
    /// margin. Unlike absolute G1–G4 thresholds this is a per-fixture *relative*
    /// claim (the gain map encodes more headroom under emission than at zero), so it
    /// holds across SDK gain-map encoder revisions. Parses the `hdr.csv` the lab
    /// already writes — no new plumbing.
    @Test func bloomHeadroomExceedsControl() throws {
        let dir = try temporaryDirectory()
        #expect(try runEvaluate(dir) == .success)
        let csv = try String(contentsOf: dir.appendingPathComponent("hdr.csv"), encoding: .utf8)
        var lines = csv.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let header = lines.removeFirst().components(separatedBy: ",")
        let fixtureCol = try #require(header.firstIndex(of: "fixture"))
        let expectationCol = try #require(header.firstIndex(of: "expectation"))
        let kCol = try #require(header.firstIndex(of: "k"))
        let headroomCol = try #require(header.firstIndex(of: "content_headroom"))

        struct Sample { let k: Float; let headroom: Float }
        var byBloomFixture: [String: [Sample]] = [:]
        for line in lines {
            let f = line.components(separatedBy: ",")
            guard f[expectationCol] == "blooms" else { continue }
            let k = try #require(Float(f[kCol]))
            let headroom = try #require(Float(f[headroomCol]))
            byBloomFixture[f[fixtureCol], default: []].append(Sample(k: k, headroom: headroom))
        }
        #expect(!byBloomFixture.isEmpty, "expected at least one bloom fixture")

        let margin: Float = 0.1
        for (fixture, samples) in byBloomFixture {
            let control = try #require(samples.first(where: { $0.k == 0 }), "\(fixture): missing k=0 control")
            let peak = try #require(samples.map(\.headroom).max())
            #expect(
                peak > control.headroom + margin,
                "\(fixture): peak headroom \(peak) must exceed k=0 control \(control.headroom) by > \(margin)")
        }
    }

    @Test func checkFailFastsOnForcedKill() throws {
        let dir = try temporaryDirectory()
        let status = try HDRCheckCommand.parse([
            "--output-dir", dir.path,
            "--columns", "16",
            "--selftest-force-kill",
        ]).execute(standardOutput: { _ in }, standardError: { _ in })
        #expect(status == .failure)
    }
}
