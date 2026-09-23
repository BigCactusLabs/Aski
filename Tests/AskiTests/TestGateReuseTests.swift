import Foundation
import Testing

@Suite struct TestGateReuseTests {
    private static let duplicatedRegistryMethods = [
        "everyNoteHasValidFrontMatter",
        "generatedArtifactsAreInSync",
        "everyCorpusAndResultHasValidManifest",
        "generatedMapIsInSync",
    ]

    @Test func fullGateBuildsTheTestGraphOnceBeforeEveryValidationPhase() throws {
        let text = try Self.justfile()
        let check = try #require(Self.recipeBody("check", in: text))

        let build = try #require(check.range(of: "xcrun swift build --build-tests"))
        let lifecycle = try #require(
            check.range(of: "ASKI_SKIP_BUILD=1 just lifecycle-check"))
        let repoMap = try #require(
            check.range(of: "ASKI_SKIP_BUILD=1 just repo-map-check"))
        let broadTests = try #require(
            check.range(
                of: "ASKI_SKIP_BUILD=1 ASKI_SKIP_REGISTRY_TESTS=1 "
                    + "ASKI_SKIP_MEDIA_TESTS=1 just test-without-video-deadlock"))
        let mediaTests = try #require(
            check.range(of: "ASKI_SKIP_BUILD=1 ASKI_SERIAL_MEDIA=1 just test-media"))
        let sentinels = try #require(
            check.range(of: "ASKI_SKIP_BUILD=1 just test-video-deadlock"))

        #expect(build.lowerBound < lifecycle.lowerBound)
        #expect(lifecycle.lowerBound < repoMap.lowerBound)
        #expect(repoMap.lowerBound < broadTests.lowerBound)
        #expect(broadTests.lowerBound < mediaTests.lowerBound)
        #expect(mediaTests.lowerBound < sentinels.lowerBound)
        #expect(check.components(separatedBy: "xcrun swift build").count - 1 == 1)
    }

    @Test func fastGateReusesTheFilteredTestBuildForDriftChecks() throws {
        let text = try Self.justfile()
        let checkFast = try #require(Self.recipeBody("check-fast", in: text))

        let tests = try #require(checkFast.range(of: "just test-fast"))
        let lifecycle = try #require(
            checkFast.range(of: "ASKI_SKIP_BUILD=1 just lifecycle-check"))
        let repoMap = try #require(
            checkFast.range(of: "ASKI_SKIP_BUILD=1 just repo-map-check"))

        #expect(tests.lowerBound < lifecycle.lowerBound)
        #expect(lifecycle.lowerBound < repoMap.lowerBound)
        #expect(!checkFast.contains("swift build"))
    }

    @Test func prebuiltRecipesUseSkipBuildButDirectCommandsRemainStandalone() throws {
        let text = try Self.justfile()
        let lifecycle = try #require(Self.recipeBody("lifecycle-check", in: text))
        let repoMap = try #require(Self.recipeBody("repo-map-check", in: text))
        let broadTests = try #require(
            Self.recipeBody("test-without-video-deadlock", in: text))
        let sentinels = try #require(Self.recipeBody("test-video-deadlock", in: text))

        #expect(lifecycle.contains("swift run --skip-build BuildResearchIndex --check"))
        #expect(lifecycle.contains("swift run BuildResearchIndex --check"))
        #expect(repoMap.contains("swift run --skip-build BuildRepoMap --check"))
        #expect(repoMap.contains("swift run BuildRepoMap --check"))

        #expect(broadTests.contains("swift test --skip-build --skip"))
        for method in Self.duplicatedRegistryMethods {
            #expect(broadTests.contains(method))
        }
        #expect(!broadTests.contains("ResearchRegistryTests"))
        #expect(!broadTests.contains("RepoMapRegistryTests"))
        #expect(!broadTests.contains("docsRootMatchesAllowlist"))
        #expect(
            broadTests.contains(
                "swift test --skip 'encoderCompletesWithSpacedAppendsAtScale|"
                    + "convertVideoChainCompletesAtScaleWithoutDeadlock'"))

        #expect(sentinels.contains("swift test --skip-build --no-parallel --filter"))
        #expect(
            sentinels.contains(
                "swift test --no-parallel --filter "
                    + "'encoderCompletesWithSpacedAppendsAtScale|"
                    + "convertVideoChainCompletesAtScaleWithoutDeadlock'"))
    }

    @Test func mediaTestsRunInACompleteSerialPartition() throws {
        let text = try Self.justfile()
        let broadTests = try #require(
            Self.recipeBody("test-without-video-deadlock", in: text))
        let mediaTests = try #require(Self.recipeBody("test-media", in: text))

        #expect(broadTests.contains("generatedMapIsInSync|GIF|Video|MotionLab"))
        #expect(
            mediaTests.contains(
                "swift test --skip-build --no-parallel --filter 'GIF|Video|MotionLab' "
                    + "--skip 'encoderCompletesWithSpacedAppendsAtScale|"
                    + "convertVideoChainCompletesAtScaleWithoutDeadlock'"))

        // Direct, ad-hoc `just test-media` keeps its existing parallel scope.
        #expect(
            mediaTests.contains(
                "swift test --filter "
                    + "'AskiGIF|AskiVideo|AskiMotionLab|AskiResampleGIF|"
                    + "AskiResampleVideo|GIF89aFixture'"))
    }

    private static func justfile() throws -> String {
        let root = try packageRoot()
        return try String(contentsOf: root.appending(path: "justfile"), encoding: .utf8)
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
