import ArgumentParser
import AskiToolSupport
import Foundation
import Testing
@testable import AskiColorLab

@Suite struct AskiColorLabCuberootAccuracyTests {

    private static let outputFileName = "cuberoot-accuracy.csv"
    private static let totalFixtures = 10_014  // 10_000 random + 7 near-zero + 6 landmarks + 1 negative-zero
    private static let policiesCount = 3  // legacy_sign_pow, darwin_cbrtf, accelerate_vvcbrtf
    private static let totalRowsIncludingHeader = totalFixtures * policiesCount + 1  // 30_043
    private static let totalColumnsExpected = 18  // 11 shared + 7 metric

    fileprivate func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiColorLabCuberootAccuracyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    fileprivate func runCommand(
        outputDirectory: URL,
        seed: String? = nil,
        gitSHA: String = "test-sha"
    ) throws -> (exit: LabExitCode, csvURL: URL) {
        var args: [String] = [
            "--output-dir", outputDirectory.path,
            "--aski-git-sha", gitSHA,
        ]
        if let seed { args.append(contentsOf: ["--seed", seed]) }
        let command = try CuberootAccuracySubcommand.parse(args)
        let exit = command.execute(standardError: { _ in })
        return (exit, outputDirectory.appendingPathComponent(Self.outputFileName))
    }

    fileprivate func readLines(_ url: URL) throws -> [String] {
        let data = try String(contentsOf: url, encoding: .utf8)
        // The writer terminates every row including the last with "\n", so the
        // raw split produces a trailing empty element. Drop it.
        var lines = data.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    // MARK: - Tests

    @Test func runWritesCSVAtExpectedPathWithExpectedHeader() throws {
        let tmp = try temporaryDirectory()
        let result = try runCommand(outputDirectory: tmp)
        #expect(result.exit == .success)
        #expect(FileManager.default.fileExists(atPath: result.csvURL.path))

        let lines = try readLines(result.csvURL)
        let expectedHeader = (CSVSchema.sharedPrefixColumns + CuberootAccuracyCommand.metricColumns)
            .joined(separator: ",")
        #expect(lines.first == expectedHeader)
        #expect(lines.first?.split(separator: ",").count == Self.totalColumnsExpected)
    }

    @Test func rowCountEqualsFixturesTimesThreePoliciesPlusOne() throws {
        let tmp = try temporaryDirectory()
        let result = try runCommand(outputDirectory: tmp)
        let lines = try readLines(result.csvURL)
        #expect(lines.count == Self.totalRowsIncludingHeader)
    }

    @Test func twoIdenticalRunsProduceByteIdenticalCSVs() throws {
        let a = try temporaryDirectory()
        let b = try temporaryDirectory()
        _ = try runCommand(outputDirectory: a)
        _ = try runCommand(outputDirectory: b)
        let dataA = try Data(contentsOf: a.appendingPathComponent(Self.outputFileName))
        let dataB = try Data(contentsOf: b.appendingPathComponent(Self.outputFileName))
        #expect(dataA == dataB)
    }

    @Test func firstThreeDataRowsArePoliciesInCanonicalOrderForSameFixture() throws {
        let tmp = try temporaryDirectory()
        let result = try runCommand(outputDirectory: tmp)
        let lines = try readLines(result.csvURL)
        // Indices 1-3 are the first fixture's three policy rows. Spec §"CSV
        // schema": canonical order is legacy_sign_pow, darwin_cbrtf,
        // accelerate_vvcbrtf — same sample_id, same fixture_id.
        let row1 = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let row2 = lines[2].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let row3 = lines[3].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        // Column indices: sample_id (4), fixture_id (5), policy (6).
        #expect(row1[4] == "0" && row2[4] == "0" && row3[4] == "0")
        #expect(row1[5] == row2[5] && row2[5] == row3[5])
        #expect(row1[6] == "legacy_sign_pow")
        #expect(row2[6] == "darwin_cbrtf")
        #expect(row3[6] == "accelerate_vvcbrtf")
    }

    @Test func negativeZeroFixtureShowsSignBitDivergenceBetweenLegacyAndCbrtf() throws {
        // Addendum §"Three deltas" Delta 2: the load-bearing assertion. The
        // legacy idiom collapses both signed zeros to +0.0f
        // (fabsf(-0.0f) = +0.0f, powf(+0.0f, …) = +0.0f, sign(-0.0f) = +1);
        // cbrtf preserves the sign per IEEE 754 odd-degree-root semantics.
        let tmp = try temporaryDirectory()
        let result = try runCommand(outputDirectory: tmp)
        let lines = try readLines(result.csvURL)

        let negativeZeroRows = lines.filter { line in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            return parts.count > 5 && parts[5] == "negative_zero"
        }
        #expect(negativeZeroRows.count == Self.policiesCount)

        // Column index: output_bits_hex = 13, reference_bits_hex = 14.
        let cells = negativeZeroRows.map { line -> (policy: String, outputBits: String, refBits: String) in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            return (parts[6], parts[13], parts[14])
        }
        let legacy = cells.first { $0.policy == "legacy_sign_pow" }
        let darwin = cells.first { $0.policy == "darwin_cbrtf" }
        let vForce = cells.first { $0.policy == "accelerate_vvcbrtf" }
        #expect(legacy?.outputBits == "0x00000000")
        #expect(darwin?.outputBits == "0x80000000")
        // Empirically observed on macOS 25.5: vForce's vvcbrtf preserves the
        // sign of -0.0f, matching cbrtf rather than the legacy idiom.
        #expect(vForce?.outputBits == "0x80000000")
        // The reference is `Float(Darwin.cbrt(Double(-0.0)))` which preserves
        // the sign through the double->float round trip.
        #expect(legacy?.refBits == "0x80000000")
    }

    @Test func darwinCbrtfReportsZeroULPOnPerfectCubeLandmarks() throws {
        // cbrtf(1.0) = 1.0f, cbrtf(0.125) = 0.5f, cbrtf(-1.0) = -1.0f,
        // cbrtf(-0.125) = -0.5f, cbrtf(8.0) = 2.0f — all bit-exact at Float.
        let tmp = try temporaryDirectory()
        let result = try runCommand(outputDirectory: tmp)
        let lines = try readLines(result.csvURL)

        let perfectCubeFixtures: Set<String> = [
            "landmark_neg_one", "landmark_neg_eighth",
            "landmark_pos_eighth", "landmark_pos_one", "landmark_pos_eight",
        ]
        let darwinPerfectCubeRows = lines.filter { line in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            return parts.count > 15 && perfectCubeFixtures.contains(String(parts[5])) && parts[6] == "darwin_cbrtf"
        }
        #expect(darwinPerfectCubeRows.count == perfectCubeFixtures.count)
        for line in darwinPerfectCubeRows {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            // Column index 15 = ulp_distance.
            #expect(parts[15] == "0", "expected 0 ULP at landmark \(parts[5]), got \(parts[15])")
        }
    }

    @Test func legacySignPowHasAtLeastOneNonZeroULPInNearZeroSweep() throws {
        // Confirms the lab is sensitive enough to capture the
        // `1.0f/3.0f` exponent-rounding error documented in Boost's cbrt
        // comparison.
        let tmp = try temporaryDirectory()
        let result = try runCommand(outputDirectory: tmp)
        let lines = try readLines(result.csvURL)

        let legacyNearZeroRows = lines.filter { line in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            return parts.count > 15
                && parts[5].hasPrefix("near_zero_")
                && parts[6] == "legacy_sign_pow"
        }
        #expect(legacyNearZeroRows.count == 7)

        let nonZeroULPCount = legacyNearZeroRows.filter { line in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            return (Int(parts[15]) ?? 0) != 0
        }.count
        #expect(
            nonZeroULPCount >= 1,
            "legacy_sign_pow must diverge from the Float64 reference by ≥1 ULP on at least one near-zero sample")
    }

    @Test func differentSeedsChangeRandomRowsButNotLiteralFixtures() throws {
        // Seed isolation: random_lms rows must depend on --seed, but
        // near_zero / landmark / negative_zero rows are seed-independent
        // literals and must be byte-identical across seeds.
        let a = try temporaryDirectory()
        let b = try temporaryDirectory()
        _ = try runCommand(outputDirectory: a, seed: "0")
        _ = try runCommand(outputDirectory: b, seed: "1")
        let linesA = try readLines(a.appendingPathComponent(Self.outputFileName))
        let linesB = try readLines(b.appendingPathComponent(Self.outputFileName))

        // Compare across run_seed field — exclude column 3 (run_seed) from
        // line-equality to test the underlying output rather than the seed
        // echo.
        func dropSeedColumn(_ line: String) -> String {
            var parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if parts.count > 3 { parts[3] = "" }
            return parts.joined(separator: ",")
        }

        let randomA = linesA.filter { $0.contains(",random_lms,") }
        let randomB = linesB.filter { $0.contains(",random_lms,") }
        #expect(randomA.count == randomB.count)
        // At least one random_lms row must differ between seeds.
        var anyDiffer = false
        for (la, lb) in zip(randomA, randomB) {
            if dropSeedColumn(la) != dropSeedColumn(lb) { anyDiffer = true; break }
        }
        #expect(anyDiffer, "expected at least one random_lms row to differ between --seed 0 and --seed 1")

        // Every literal-group row (near_zero, landmark, negative_zero) must be
        // identical between seeds modulo the run_seed column echo.
        let literalA = linesA.filter {
            $0.contains(",near_zero,") || $0.contains(",landmark,") || $0.contains(",negative_zero,")
        }
        let literalB = linesB.filter {
            $0.contains(",near_zero,") || $0.contains(",landmark,") || $0.contains(",negative_zero,")
        }
        #expect(literalA.count == literalB.count)
        for (la, lb) in zip(literalA, literalB) {
            #expect(
                dropSeedColumn(la) == dropSeedColumn(lb),
                "literal-fixture row must not depend on --seed: \(la) vs \(lb)")
        }
    }

    @Test func policyIdentifierCanonicalOrderMatchesCSVContract() {
        // Pin canonical CSV order at the policies layer too. If this drifts,
        // every other ordering assertion above silently changes meaning.
        #expect(
            CuberootAccuracyPolicies.canonicalOrder.map(\.csvLabel)
                == ["legacy_sign_pow", "darwin_cbrtf", "accelerate_vvcbrtf"])
    }
}
