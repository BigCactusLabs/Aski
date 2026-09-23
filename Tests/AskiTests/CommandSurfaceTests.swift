import Foundation
import Testing

@Suite struct CommandSurfaceTests {
    @Test func justfileExposesCanonicalCommands() throws {
        let root = try Self.packageRoot()
        let text = try String(contentsOf: root.appending(path: "justfile"), encoding: .utf8)

        for recipe in [
            "check",
            "check-fast",
            "test",
            "test-without-video-deadlock",
            "test-video-deadlock",
            "test-fast",
            "test-snapshots",
            "test-media",
            "test-research",
            "test-artifacts",
            "docc",
            "research-check",
            "lifecycle-check",
            "bench",
            "format-check",
            "regen-kernels",
            "regen-vectors",
            "audit-vectors",
            "regen-repo-map",
            "repo-map-check",
            "release-preflight",
        ] {
            #expect(Self.containsRecipe(recipe, in: text), "missing just recipe: \(recipe)")
        }

        let checkBody = try #require(Self.recipeBody("check", in: text))
        #expect(checkBody.contains("xcrun swift build"))
        #expect(checkBody.contains("./Scripts/swift-format-check.sh"))
        #expect(checkBody.contains("just test-without-video-deadlock"))
        #expect(checkBody.contains("just test-video-deadlock"))
        #expect(checkBody.contains("just lifecycle-check"))
        #expect(checkBody.contains("just repo-map-check"))
        #expect(checkBody.contains("./Scripts/validate-docc.sh"))
        #expect(!checkBody.contains("just test-fast"))
        #expect(!checkBody.contains("xcrun swift test"))

        let checkFastBody = try #require(Self.recipeBody("check-fast", in: text))
        #expect(checkFastBody.contains("just test-fast"))
        #expect(checkFastBody.contains("just lifecycle-check"))
        #expect(checkFastBody.contains("just repo-map-check"))
        #expect(!checkFastBody.contains("validate-docc.sh"))
        #expect(!checkFastBody.contains("xcrun swift test"))
        #expect(!checkFastBody.contains("swift build"))

        #expect(text.contains("swift test"))
        #expect(
            text.contains(
                "--skip 'encoderCompletesWithSpacedAppendsAtScale|convertVideoChainCompletesAtScaleWithoutDeadlock'"))
        #expect(
            text.contains(
                "--filter 'encoderCompletesWithSpacedAppendsAtScale|convertVideoChainCompletesAtScaleWithoutDeadlock'"))
        #expect(
            text.contains(
                "--skip 'Snapshot|GIF|Video|MotionLab|AccessLab|DecolorLab|ColorLab|Research|RepoMap|"
                    + "DocumentationLinkTests|CommandSurfaceTests|CommandSurfaceGoldenTests|"
                    + "KnobDocumentationTests|Metallib|Artifact'"))
        #expect(
            text.contains(
                "--filter 'SnapshotTests|BuiltInPaletteSnapshotTests|MaskSnapshotTests|TileGridRenderingSnapshotTests|CompositionSnapshotTests|EffectKernelSnapshotTests'"))
        #expect(text.contains("--filter 'AskiGIF|AskiVideo|AskiMotionLab|AskiResampleGIF|AskiResampleVideo|GIF89aFixture'"))
        #expect(text.contains("--filter 'Research|Manifest|AskiColorLab|AskiAccessLab|AskiDecolorLab|AskiMotionLab'"))
        #expect(
            text.contains(
                "--filter 'CommandSurfaceTests|CommandSurfaceGoldenTests|KnobDocumentationTests|DocumentationLinkTests|ResearchRegistryTests|ResearchManifestTests|"
                    + "RepoMapRegistryTests|MetallibArtifactTests|MetallibFallbackTests'"))
        #expect(text.contains("./Scripts/validate-docc.sh"))
        #expect(text.contains("swift run BuildResearchIndex --check"))
        #expect(text.contains("swift run BuildRepoMap"))
        #expect(text.contains("swift package --disable-sandbox benchmark --target AskiBenchmarks"))
        #expect(text.contains("./Scripts/swift-format-check.sh"))
        #expect(text.contains("swift run BuildKernelLibrary"))
        #expect(text.contains("swift run BuildStandardVectors"))
        #expect(text.contains("swift run BuildStandardVectors --audit"))
        #expect(text.contains("./Scripts/repo-doctor.sh"))
    }

    @Test func makefileForwardsCanonicalTargetsToJust() throws {
        let root = try Self.packageRoot()
        let text = try String(contentsOf: root.appending(path: "Makefile"), encoding: .utf8)

        for target in [
            "check",
            "check-fast",
            "test",
            "test-without-video-deadlock",
            "test-video-deadlock",
            "test-fast",
            "test-snapshots",
            "test-media",
            "test-research",
            "test-artifacts",
            "docc",
            "research-check",
            "lifecycle-check",
            "bench",
            "format-check",
            "regen-kernels",
            "regen-vectors",
            "audit-vectors",
            "regen-repo-map",
            "repo-map-check",
            "release-preflight",
        ] {
            #expect(text.contains("\(target):"))
            #expect(text.contains("just \(target)"))
        }
    }

    @Test func repoDoctorRejectsMutableRemoteWorkflowRefs() throws {
        let root = try Self.packageRoot()
        let fixture = try Self.makeTempDirectory(named: "workflow-refs")
        defer { try? FileManager.default.removeItem(at: fixture) }

        try """
        name: fixture
        jobs:
          test:
            steps:
              - uses: actions/checkout@v4
              - uses: ./local-action
              - uses: owner/action@0123456789abcdef0123456789abcdef01234567
        """.write(to: fixture.appending(path: "ci.yml"), atomically: true, encoding: .utf8)

        let result = try Self.run(
            "/bin/bash",
            arguments: [
                root.appending(path: "Scripts/repo-doctor.sh").path,
                "--check", "workflow-refs",
                "--workflow-dir", fixture.path,
            ],
            currentDirectory: root
        )

        #expect(result.status != 0)
        #expect(result.output.contains("actions/checkout@v4"))
        #expect(result.output.contains("full-length commit SHA"))
        #expect(!result.output.contains("./local-action"))
    }

    @Test func swiftFormatCheckScriptEnforcesFullTreeLintByDefault() throws {
        let root = try Self.packageRoot()
        let script = root.appending(path: "Scripts/swift-format-check.sh")
        let text = try String(contentsOf: script, encoding: .utf8)

        #expect(text.contains("Package.swift"))
        #expect(text.contains("Sources"))
        #expect(text.contains("Tools"))
        #expect(text.contains("Benchmarks"))
        #expect(text.contains("Tests"))
        #expect(text.contains("swift format lint"))
        #expect(text.contains(".swift-format"))
        #expect(text.contains("--recursive"))
        #expect(!text.contains("ASKI_FORMAT_BASE"))
        #expect(!text.contains("--base"))
        #expect(!text.contains("--all"))
        #expect(!text.contains("git diff"))
    }

    @Test func repoDoctorCoversReleaseToolchainAndSwiftFormat() throws {
        let root = try Self.packageRoot()
        let text = try String(contentsOf: root.appending(path: "Scripts/repo-doctor.sh"), encoding: .utf8)

        #expect(text.contains("ASKI_REQUIRED_SWIFT_VERSION"))
        #expect(text.contains("swift-tools-version"))
        #expect(!text.contains("ASKI_REQUIRED_XCODE_VERSION"))
        #expect(text.contains("swift-format"))
        #expect(text.contains("swift-format full-tree lint passes"))
        #expect(text.contains("swift-format full-tree lint failed"))
        #expect(text.contains("xcrun --find metal"))
        #expect(text.contains("xcrun --find metallib"))
    }

    @Test func buildKernelLibraryFailureDiagnosticsNameToolchainCommands() throws {
        let root = try Self.packageRoot()
        let text = try String(
            contentsOf: root.appending(path: "Tools/BuildKernelLibrary/BuildKernelLibrary.swift"),
            encoding: .utf8
        )

        #expect(text.contains("xcodebuild -version"))
        #expect(text.contains("swift --version"))
        #expect(text.contains("xcrun --find metal"))
        #expect(text.contains("xcrun --find metallib"))
        #expect(text.contains("xcodebuild -downloadComponent MetalToolchain"))
    }

    private static func containsRecipe(_ recipe: String, in text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .contains { $0 == "\(recipe):" || $0.hasPrefix("\(recipe) ") && $0.hasSuffix(":") }
    }

    private static func recipeBody(_ recipe: String, in text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard
            let headerIndex = lines.firstIndex(where: {
                $0 == "\(recipe):" || $0.hasPrefix("\(recipe) ") && $0.hasSuffix(":")
            })
        else {
            return nil
        }

        var body: [String] = []
        for line in lines.dropFirst(headerIndex + 1) {
            if line.isEmpty || line.first?.isWhitespace != true {
                break
            }
            body.append(line)
        }
        return body.joined(separator: "\n")
    }

    private static func makeTempDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "aski-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: URL
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private static func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
