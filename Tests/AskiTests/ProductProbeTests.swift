import CoreGraphics
import CryptoKit
import Darwin
import Dispatch
import Foundation
import Testing
import Aski
@testable import AskiPresetLab
import AskiToolSupport

@Suite struct ProductProbeTests {
    @Test func sourceContractRejectsWrongJobQuota() throws {
        var sources = validSourceManifest().sources
        sources[3] = .init(
            id: sources[3].id,
            path: sources[3].path,
            role: .job,
            contentClass: .live,
            participantId: sources[3].participantId)
        let invalid = ProductProbeSourceManifest(probeOrdinal: 1, sources: sources)
        #expect(throws: (any Error).self) { try invalid.validated() }
    }

    @Test func blindedPlanIsDeterministicAndSeeded() throws {
        let manifest = validSourceManifest()
        let first = try ProductProbePlan.make(from: manifest, seed: 7301)
        let again = try ProductProbePlan.make(from: manifest, seed: 7301)
        let other = try ProductProbePlan.make(from: manifest, seed: 7302)

        #expect(first == again)
        #expect(first != other)
        #expect(Set(first.sources.flatMap { $0.options.map(\.token) }).count == 33)
        #expect(first.sources.allSatisfy { Set($0.options.map(\.arm)) == Set(ProductProbeArm.allCases) })
    }

    @Test func stillArmsUseMatchedGeometryAndExactCanonicalVesper() throws {
        let image = syntheticImage(width: 32, height: 44)
        let arms = ProductProbeCLI.renderStillArms(image)
        let sizes = Set(arms.values.map { "\($0.width)x\($0.height)" })
        #expect(sizes.count == 1)
        let vesper = try #require(arms[.vesper])
        #expect(try DemoImageIO.encodePNG(vesper) == DemoImageIO.encodePNG(VesperPreset.canonical.render(image)))
    }

    @Test func centerRevealUsesCanonicalCanvas() throws {
        let image = syntheticImage(width: 24, height: 32)
        let frames = ProductProbeCLI.renderCenterReveal(image, seed: 7301, fps: 2, duration: 1)
        let canonical = VesperPreset.canonical.render(image)
        #expect(!frames.isEmpty)
        #expect(frames.allSatisfy { $0.image.width == canonical.width && $0.image.height == canonical.height })
    }

    @Test func generatorKeepsArmAndParticipantDataOutOfPublicArtifacts() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var manifest = validSourceManifest()
        var materialized: [ProductProbeSourceManifest.Source] = []
        for (index, source) in manifest.sources.enumerated() {
            let imageURL = root.appendingPathComponent("private-input-\(index).png")
            try DemoImageIO.writePNG(syntheticImage(width: 12 + index, height: 18 + index), to: imageURL.path)
            materialized.append(
                .init(
                    id: source.id,
                    path: imageURL.path,
                    role: source.role,
                    contentClass: source.contentClass,
                    participantId: source.participantId))
        }
        manifest = .init(probeOrdinal: 1, sources: materialized)
        let sourceURL = root.appendingPathComponent("private-sources.json")
        try StableJSON.write(manifest, to: sourceURL)
        let outputURL = root.appendingPathComponent("public")
        let keyURL = root.appendingPathComponent("private/key.json")

        let status = ProductProbeCLI.generate(
            arguments: .init(
                sourceManifestPath: sourceURL.path,
                outputDirectory: outputURL.path,
                keyOutputPath: keyURL.path,
                seed: 7301,
                fps: 1,
                duration: 1,
                runKind: "instrument-smoke",
                gitShaOverride: "deadbeef"),
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-09-04")
        #expect(status == .success)

        let publicJSON = try String(contentsOf: outputURL.appendingPathComponent("manifest.json"), encoding: .utf8)
        let privateJSON = try String(contentsOf: keyURL, encoding: .utf8)
        #expect(!publicJSON.contains("vesper"))
        #expect(!publicJSON.contains("genericFullColor"))
        #expect(!publicJSON.contains("participant"))
        #expect(!publicJSON.contains("private-input"))
        #expect(publicJSON.contains("instrument-smoke"))
        #expect(privateJSON.contains("vesper"))
        #expect(privateJSON.contains("participantID"))
        #expect(privateJSON.contains("publicManifestSHA256"))
        let key = try JSONDecoder().decode(PrivateKey.self, from: Data(contentsOf: keyURL))
        #expect(key.schemaVersion == "2")
        #expect(key.runKind == "instrument-smoke")
        #expect(key.mediaDigests.count == 41)
        #expect(key.mediaDigests.map(\.path) == key.mediaDigests.map(\.path).sorted())
        #expect(
            key.publicManifestSHA256
                == sha256Hex(try Data(contentsOf: outputURL.appendingPathComponent("manifest.json"))))
        #expect(
            try String(contentsOf: outputURL.appendingPathComponent("session-one-template.csv"), encoding: .utf8)
                == ProductProbeCLI.sessionOneHeader + "\n")
        #expect(
            try String(contentsOf: outputURL.appendingPathComponent("repeat-template.csv"), encoding: .utf8)
                == ProductProbeCLI.repeatHeader + "\n")

        let repeatOutputURL = root.appendingPathComponent("public-repeat")
        let repeatKeyURL = root.appendingPathComponent("private/key-repeat.json")
        let repeatStatus = ProductProbeCLI.generate(
            arguments: .init(
                sourceManifestPath: sourceURL.path,
                outputDirectory: repeatOutputURL.path,
                keyOutputPath: repeatKeyURL.path,
                seed: 7301,
                fps: 1,
                duration: 1,
                runKind: "instrument-smoke",
                gitShaOverride: "deadbeef"),
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-09-04")
        #expect(repeatStatus == .success)
        #expect(
            try Data(contentsOf: outputURL.appendingPathComponent("manifest.json"))
                == Data(contentsOf: repeatOutputURL.appendingPathComponent("manifest.json")))
        #expect(try Data(contentsOf: keyURL) == Data(contentsOf: repeatKeyURL))
        for digest in key.mediaDigests {
            #expect(
                try Data(contentsOf: outputURL.appendingPathComponent(digest.path))
                    == Data(contentsOf: repeatOutputURL.appendingPathComponent(digest.path)))
        }
    }

    @Test func gateBoundariesAreFrozen() {
        let proceed = ProductProbeScore.evaluate(
            counts: .init(identity: 6, preferenceAndExport: 5, repeatUse: 3, motion: 5, paidCommitment: 2))
        #expect(proceed.disposition == .proceed)
        #expect(proceed.motionRetained)
        #expect(proceed.consumerExpansionEligible)

        let refine = ProductProbeScore.evaluate(
            counts: .init(identity: 5, preferenceAndExport: 5, repeatUse: 3, motion: 4, paidCommitment: 1))
        #expect(refine.disposition == .refine)
        #expect(!refine.motionRetained)
        #expect(!refine.consumerExpansionEligible)

        let stop = ProductProbeScore.evaluate(
            counts: .init(identity: 4, preferenceAndExport: 5, repeatUse: 3, motion: 8, paidCommitment: 8))
        #expect(stop.disposition == .stop)
    }

    @Test func scorerCountsOnlyRoutedVesperExportAndQualifyingRepeat() throws {
        let key = try privateKey()
        let input = responseRows(key: key, identity: 6, preference: 5, repeatUse: 3, motion: 5, paid: 2)
        let score = try ProductProbeCLI.scoreResponses(
            sessionRows: input.session, repeatRows: input.repeats, key: key)
        #expect(
            score.counts
                == .init(
                    identity: 6, preferenceAndExport: 5, repeatUse: 3, motion: 5, paidCommitment: 2))
        #expect(score.disposition == .proceed)
    }

    @Test func scoreCommandWritesOnlyAggregateArtifacts() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        let key = pair.key
        let input = responseRows(key: key, identity: 6, preference: 5, repeatUse: 3, motion: 5, paid: 2)
        let sessionURL = root.appendingPathComponent("session.csv")
        let repeatURL = root.appendingPathComponent("repeats.csv")
        try ([ProductProbeCLI.sessionOneHeader] + input.session.map { $0.joined(separator: ",") })
            .joined(separator: "\n").appending("\n")
            .write(to: sessionURL, atomically: true, encoding: .utf8)
        try ([ProductProbeCLI.repeatHeader] + input.repeats.map { $0.joined(separator: ",") })
            .joined(separator: "\n").appending("\n")
            .write(to: repeatURL, atomically: true, encoding: .utf8)
        let outputURL = root.appendingPathComponent("aggregate")

        let status = ProductProbeCLI.score(
            arguments: .init(
                stimuliManifestPath: pair.manifestURL.path,
                keyPath: pair.keyURL.path,
                sessionOnePath: sessionURL.path,
                repeatLogPath: repeatURL.path,
                outputDirectory: outputURL.path,
                gitShaOverride: "deadbeef"),
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-09-04")

        #expect(status == .success)
        let written = try Set(FileManager.default.contentsOfDirectory(atPath: outputURL.path))
        #expect(written == ["readout.md", "result.yaml", "score.json"])
        let score = try JSONDecoder().decode(
            ProductProbeScore.self,
            from: Data(contentsOf: outputURL.appendingPathComponent("score.json")))
        #expect(score.disposition == .proceed)
        let result = try String(contentsOf: outputURL.appendingPathComponent("result.yaml"), encoding: .utf8)
        #expect(result.contains("outputs: [\"readout.md\", \"score.json\"]"))
        #expect(!result.contains("participant-"))
    }

    @Test func scoreCommandRejectsInstrumentSmokeAsProductEvidence() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "instrument-smoke")
        let sessionURL = root.appendingPathComponent("session.csv")
        let repeatURL = root.appendingPathComponent("repeats.csv")
        try (ProductProbeCLI.sessionOneHeader + "\n").write(
            to: sessionURL, atomically: true, encoding: .utf8)
        try (ProductProbeCLI.repeatHeader + "\n").write(
            to: repeatURL, atomically: true, encoding: .utf8)

        var error = ""
        let status = ProductProbeCLI.score(
            arguments: .init(
                stimuliManifestPath: pair.manifestURL.path,
                keyPath: pair.keyURL.path,
                sessionOnePath: sessionURL.path,
                repeatLogPath: repeatURL.path,
                outputDirectory: root.appendingPathComponent("aggregate").path,
                gitShaOverride: "deadbeef"),
            standardOutput: { _ in },
            standardError: { error += $0 },
            date: "2026-09-04")

        #expect(status == .usage)
        #expect(error.contains("instrument-smoke manifests and keys cannot produce"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsCanonicalSmokeManifestRelabeledAsHuman() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "instrument-smoke")
        try StableJSON.write(replacingLabel(in: pair.manifest, with: "human-probe"), to: pair.manifestURL)

        let result = scorePair(pair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("manifest digest does not match"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsSameSeedCrossPairWithDifferentMedia() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try boundPair(
            at: root.appendingPathComponent("first"), runKind: "human-probe", mediaMarker: "first")
        let second = try boundPair(
            at: root.appendingPathComponent("second"), runKind: "human-probe", mediaMarker: "second")
        let crossed = BoundPair(
            manifest: first.manifest,
            key: second.key,
            manifestURL: first.manifestURL,
            keyURL: second.keyURL)

        let result = scorePair(crossed, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("media digest mismatch"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsTamperedMedia() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        let mediaURL = pair.manifestURL.deletingLastPathComponent()
            .appendingPathComponent(pair.key.mediaDigests[0].path)
        var bytes = try Data(contentsOf: mediaURL)
        bytes.append(0)
        try bytes.write(to: mediaURL, options: .atomic)

        let result = scorePair(pair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("media digest mismatch"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsNoncanonicalManifestBytes() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        var bytes = try Data(contentsOf: pair.manifestURL)
        bytes.append(contentsOf: Data(" ".utf8))
        try bytes.write(to: pair.manifestURL, options: .atomic)

        let result = scorePair(pair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("manifest is not canonical"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsMissingReferencedMedia() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        try FileManager.default.removeItem(
            at: pair.manifestURL.deletingLastPathComponent()
                .appendingPathComponent(pair.key.mediaDigests[0].path))

        let result = scorePair(pair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("stimuli media is missing"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsExtraPrivateMediaBinding() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        let extra = PrivateKey.MediaDigest(path: "job/EXTRA.png", sha256: String(repeating: "0", count: 64))
        let changedKey = replacingMediaDigests(
            in: pair.key,
            with: (pair.key.mediaDigests + [extra]).sorted { $0.path < $1.path })
        try StableJSON.write(changedKey, to: pair.keyURL)
        let changedPair = BoundPair(
            manifest: pair.manifest,
            key: changedKey,
            manifestURL: pair.manifestURL,
            keyURL: pair.keyURL)

        let result = scorePair(changedPair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("media paths do not match"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsMissingPrivateMediaBinding() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        let changedKey = replacingMediaDigests(
            in: pair.key,
            with: Array(pair.key.mediaDigests.dropFirst()))
        try StableJSON.write(changedKey, to: pair.keyURL)
        let changedPair = pair.replacing(key: changedKey)

        let result = scorePair(changedPair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("media paths do not match"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsSourceMappingMismatch() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        let portraitIndex = try #require(
            pair.manifest.sources.firstIndex { $0.role == .job && $0.contentClass == .portrait })
        let coverIndex = try #require(
            pair.manifest.sources.firstIndex { $0.role == .job && $0.contentClass == .cover })
        var sources = pair.manifest.sources
        sources[portraitIndex] = replacingContentClass(in: sources[portraitIndex], with: .cover)
        sources[coverIndex] = replacingContentClass(in: sources[coverIndex], with: .portrait)
        let changedPair = try writeReboundManifest(replacingSources(in: pair.manifest, with: sources), pair: pair)

        let result = scorePair(changedPair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("source mapping does not match"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsPerSourceTokenMappingMismatch() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        var sources = pair.manifest.sources
        let firstToken = sources[0].options[0].token
        let secondToken = sources[1].options[0].token
        sources[0] = replacingOptionToken(in: sources[0], optionIndex: 0, with: secondToken)
        sources[1] = replacingOptionToken(in: sources[1], optionIndex: 0, with: firstToken)
        let changedPair = try writeReboundManifest(replacingSources(in: pair.manifest, with: sources), pair: pair)

        let result = scorePair(changedPair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("token mapping does not match"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsV1PairWithRegenerationGuidance() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        let v1Manifest = replacingSchemaVersion(in: pair.manifest, with: "1")
        try StableJSON.write(v1Manifest, to: pair.manifestURL)
        var keyObject = try #require(
            JSONSerialization.jsonObject(with: StableJSON.data(for: pair.key)) as? [String: Any])
        keyObject["schemaVersion"] = "1"
        keyObject.removeValue(forKey: "runKind")
        keyObject.removeValue(forKey: "publicManifestSHA256")
        keyObject.removeValue(forKey: "mediaDigests")
        try JSONSerialization.data(withJSONObject: keyObject, options: [.sortedKeys])
            .write(to: pair.keyURL, options: .atomic)

        let result = scorePair(pair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("regenerate probe stimuli with schema v2"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))

        try StableJSON.write(pair.manifest, to: pair.manifestURL)
        let keyResult = scorePair(pair, outputDirectory: root.appendingPathComponent("key-aggregate"))
        #expect(keyResult.status == .usage)
        #expect(keyResult.error.contains("private key schema 1 is unsupported"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("key-aggregate").path))
    }

    @Test func scoreCommandRejectsRunKindMismatchAfterValidManifestBinding() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "instrument-smoke")
        let changedPair = try writeReboundManifest(
            replacingLabel(in: pair.manifest, with: "human-probe"), pair: pair)

        let result = scorePair(changedPair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("instrument-smoke manifests and keys cannot produce"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsSymlinkedMedia() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        let mediaURL = pair.manifestURL.deletingLastPathComponent()
            .appendingPathComponent(pair.key.mediaDigests[0].path)
        let externalURL = root.appendingPathComponent("external-media")
        try Data(contentsOf: mediaURL).write(to: externalURL)
        try FileManager.default.removeItem(at: mediaURL)
        try FileManager.default.createSymbolicLink(at: mediaURL, withDestinationURL: externalURL)

        let result = scorePair(pair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("cannot securely open stimuli media"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsNonregularMediaWithoutBlocking() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        let mediaURL = pair.manifestURL.deletingLastPathComponent()
            .appendingPathComponent(pair.key.mediaDigests[0].path)
        try FileManager.default.removeItem(at: mediaURL)
        let status = mediaURL.path.withCString { Darwin.mkfifo($0, mode_t(0o600)) }
        #expect(status == 0)

        let result = scorePair(pair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("bounded regular file"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsEmbeddedNULMediaAlias() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        var sources = pair.manifest.sources
        let originalPath = sources[0].options[0].file
        let nulPath = originalPath + "\0ignored"
        sources[0] = replacingOptionFile(in: sources[0], optionIndex: 0, with: nulPath)
        let manifest = replacingSources(in: pair.manifest, with: sources)
        let manifestData = try StableJSON.data(for: manifest)
        let mediaDigests = pair.key.mediaDigests.map { digest in
            digest.path == originalPath
                ? PrivateKey.MediaDigest(path: nulPath, sha256: digest.sha256)
                : digest
        }.sorted { $0.path < $1.path }
        let key = replacingManifestDigest(
            in: replacingMediaDigests(in: pair.key, with: mediaDigests),
            with: sha256Hex(manifestData))
        try manifestData.write(to: pair.manifestURL, options: .atomic)
        try StableJSON.write(key, to: pair.keyURL)
        let changedPair = pair.replacing(manifest: manifest, key: key)

        let result = scorePair(changedPair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("safe relative paths"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsSymlinkedManifest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        let realManifestURL = root.appendingPathComponent("manifest-real.json")
        try FileManager.default.moveItem(at: pair.manifestURL, to: realManifestURL)
        try FileManager.default.createSymbolicLink(
            at: pair.manifestURL, withDestinationURL: realManifestURL)

        let result = scorePair(pair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("cannot securely open stimuli manifest"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsFIFOPrivateKeyWithoutBlocking() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        try FileManager.default.removeItem(at: pair.keyURL)
        let status = pair.keyURL.path.withCString { Darwin.mkfifo($0, mode_t(0o600)) }
        #expect(status == 0)

        let result = scorePair(pair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(result.status == .usage)
        #expect(result.error.contains("private key must be a bounded regular file"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func scoreCommandRejectsMediaReplacedDuringHash() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try boundPair(at: root, runKind: "human-probe")
        let digest = pair.key.mediaDigests[0]
        let mediaURL = pair.manifestURL.deletingLastPathComponent()
            .appendingPathComponent(digest.path)
        let original = Data(repeating: 0x5A, count: 64 * 1024 * 1024)
        try original.write(to: mediaURL, options: .atomic)
        let mediaDirectory = mediaURL.deletingLastPathComponent()
        let replacementDirectory = mediaDirectory.deletingLastPathComponent()
            .appendingPathComponent("identity-replacement")
        try FileManager.default.createDirectory(
            at: replacementDirectory, withIntermediateDirectories: true)
        let replacementURL = replacementDirectory.appendingPathComponent(mediaURL.lastPathComponent)
        try Data("replacement".utf8).write(to: replacementURL, options: .atomic)
        let mediaDigests = pair.key.mediaDigests.map {
            $0.path == digest.path
                ? PrivateKey.MediaDigest(path: $0.path, sha256: sha256Hex(original))
                : $0
        }
        let key = replacingMediaDigests(in: pair.key, with: mediaDigests)
        try StableJSON.write(key, to: pair.keyURL)
        let changedPair = pair.replacing(key: key)

        var targetInfo = stat()
        let statStatus = mediaURL.path.withCString { lstat($0, &targetInfo) }
        #expect(statStatus == 0)
        let targetDevice = targetInfo.st_dev
        let targetInode = targetInfo.st_ino
        let replaced = DispatchSemaphore(value: 0)
        let replacementPath = replacementDirectory.path
        let mediaDirectoryPath = mediaDirectory.path
        let movedDirectoryPath = mediaDirectory.deletingLastPathComponent()
            .appendingPathComponent("identity-original").path
        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                for fileDescriptor in 0..<1024 {
                    var info = stat()
                    if fstat(Int32(fileDescriptor), &info) == 0,
                        info.st_dev == targetDevice, info.st_ino == targetInode
                    {
                        _ = mediaDirectoryPath.withCString { current in
                            movedDirectoryPath.withCString { moved in Darwin.rename(current, moved) }
                        }
                        _ = replacementPath.withCString { replacement in
                            mediaDirectoryPath.withCString { current in Darwin.rename(replacement, current) }
                        }
                        replaced.signal()
                        return
                    }
                }
                usleep(100)
            }
            replaced.signal()
        }

        let result = scorePair(changedPair, outputDirectory: root.appendingPathComponent("aggregate"))

        #expect(replaced.wait(timeout: .now() + 2) == .success)
        #expect(result.status == .usage)
        #expect(result.error.contains("changed at its declared path"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("aggregate").path))
    }

    @Test func generatorRejectsKeyDirectoryAliasedInsidePublicOutput() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("private-sources.json")
        try StableJSON.write(validSourceManifest(), to: sourceURL)
        let outputURL = root.appendingPathComponent("public")
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let aliasURL = root.appendingPathComponent("private-alias")
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: outputURL)
        var error = ""

        let status = ProductProbeCLI.generate(
            arguments: .init(
                sourceManifestPath: sourceURL.path,
                outputDirectory: outputURL.path,
                keyOutputPath: aliasURL.appendingPathComponent("key.json").path,
                runKind: "instrument-smoke",
                gitShaOverride: "deadbeef"),
            standardOutput: { _ in },
            standardError: { error += $0 },
            date: "2026-09-04")

        #expect(status == .usage)
        #expect(error.contains("--key-output must be outside"))
        #expect(!FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("key.json").path))
    }

    @Test func scorerRejectsDuplicateParticipantAndPrematureRepeat() throws {
        let key = try privateKey()
        var duplicate = responseRows(key: key, identity: 6, preference: 5, repeatUse: 3, motion: 5, paid: 2)
        duplicate.session[1][0] = duplicate.session[0][0]
        #expect(throws: (any Error).self) {
            try ProductProbeCLI.scoreResponses(
                sessionRows: duplicate.session, repeatRows: duplicate.repeats, key: key)
        }

        var early = responseRows(key: key, identity: 6, preference: 5, repeatUse: 3, motion: 5, paid: 2)
        early.repeats[0][3] = "2026-09-02T23:59:59Z"
        #expect(throws: (any Error).self) {
            try ProductProbeCLI.scoreResponses(
                sessionRows: early.session, repeatRows: early.repeats, key: key)
        }
    }

    @Test func committedSchemasFreezeVersionsAndScoreFields() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for filename in [
            "aski-product-probe-source-v1.schema.json",
            "aski-product-probe-score-v1.schema.json",
        ] {
            let data = try Data(contentsOf: root.appendingPathComponent("docs/assets/schemas/\(filename)"))
            let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(schema["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
            let properties = try #require(schema["properties"] as? [String: Any])
            let version = try #require(properties["schemaVersion"] as? [String: Any])
            #expect(version["const"] as? String == "1")
        }
        for filename in [
            "aski-product-probe-public-v2.schema.json",
            "aski-product-probe-key-v2.schema.json",
        ] {
            let data = try Data(contentsOf: root.appendingPathComponent("docs/assets/schemas/\(filename)"))
            let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(schema["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
            let properties = try #require(schema["properties"] as? [String: Any])
            let version = try #require(properties["schemaVersion"] as? [String: Any])
            #expect(version["const"] as? String == "2")

            let definitions = try #require(schema["$defs"] as? [String: Any])
            let source = try #require(definitions["source"] as? [String: Any])
            let constraints = try #require(source["allOf"] as? [[String: Any]])
            let roleConstraint = try #require(constraints.first)
            let thenClause = try #require(roleConstraint["then"] as? [String: Any])
            let elseClause = try #require(roleConstraint["else"] as? [String: Any])
            if filename.contains("public") {
                #expect(thenClause["required"] as? [String] == ["motionFile"])
                let notClause = try #require(elseClause["not"] as? [String: Any])
                #expect(notClause["required"] as? [String] == ["motionFile"])
            } else {
                #expect(thenClause["required"] as? [String] == ["participantID"])
                let notClause = try #require(elseClause["not"] as? [String: Any])
                #expect(notClause["required"] as? [String] == ["participantID"])
            }
        }
    }

    private func validSourceManifest() -> ProductProbeSourceManifest {
        var sources: [ProductProbeSourceManifest.Source] = [
            .init(id: "identity-portrait", path: "/private/identity-portrait.png", role: .identity, contentClass: .portrait),
            .init(id: "identity-cover", path: "/private/identity-cover.png", role: .identity, contentClass: .cover),
            .init(id: "identity-live", path: "/private/identity-live.png", role: .identity, contentClass: .live),
        ]
        let classes: [ProductProbeContentClass] = [.portrait, .portrait, .portrait, .cover, .cover, .cover, .live, .live]
        for index in 0..<8 {
            sources.append(
                .init(
                    id: "job-\(index + 1)",
                    path: "/private/job-\(index + 1).png",
                    role: .job,
                    contentClass: classes[index],
                    participantId: "participant-\(index + 1)"))
        }
        return .init(probeOrdinal: 1, sources: sources)
    }

    private func privateKey() throws -> PrivateKey {
        let plan = try ProductProbePlan.make(from: validSourceManifest(), seed: 7301)
        return PrivateKey(
            schemaVersion: "2",
            probeID: "test-probe",
            runKind: "human-probe",
            publicManifestSHA256: String(repeating: "0", count: 64),
            mediaDigests: [],
            sourceManifestPath: "/private/sources.json",
            sources: plan.sources.map(PrivateKey.Source.init),
            thresholds: ProductProbeScore.evaluate(
                counts: .init(identity: 0, preferenceAndExport: 0, repeatUse: 0, motion: 0, paidCommitment: 0)
            ).thresholds)
    }

    private struct BoundPair {
        let manifest: PublicManifest
        let key: PrivateKey
        let manifestURL: URL
        let keyURL: URL

        func replacing(
            manifest: PublicManifest? = nil,
            key: PrivateKey? = nil
        ) -> Self {
            Self(
                manifest: manifest ?? self.manifest,
                key: key ?? self.key,
                manifestURL: manifestURL,
                keyURL: keyURL)
        }
    }

    private func boundPair(
        at root: URL,
        runKind: String,
        mediaMarker: String = "baseline"
    ) throws -> BoundPair {
        let plan = try ProductProbePlan.make(from: validSourceManifest(), seed: 7301)
        let publicRoot = root.appendingPathComponent("stimuli")
        let keyURL = root.appendingPathComponent("private/key.json")
        try FileManager.default.createDirectory(at: publicRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let publicSources = plan.sources.map { source in
            let phase = source.role == .identity ? "identity" : "job"
            return PublicManifest.Source(
                sourceCode: source.sourceCode,
                role: source.role,
                contentClass: source.contentClass,
                options: source.options.map {
                    PublicManifest.Option(token: $0.token, file: "\(phase)/\($0.token).png")
                },
                motionFile: source.role == .job ? "motion/\(source.sourceCode)-CENTER.gif" : nil,
                pixelSize: "100x100")
        }
        let manifest = PublicManifest(
            schemaVersion: "2",
            probeID: "test-probe-seed-7301",
            label: runKind,
            date: "2026-09-04",
            askiGitSHA: "deadbeef",
            seed: 7301,
            fps: 12,
            duration: 2,
            sources: publicSources)
        let mediaPaths = publicSources.flatMap { source in
            source.options.map(\.file) + [source.motionFile].compactMap { $0 }
        }.sorted()
        var mediaDigests: [PrivateKey.MediaDigest] = []
        for path in mediaPaths {
            let url = publicRoot.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data("\(mediaMarker):\(path)".utf8)
            try data.write(to: url, options: .atomic)
            mediaDigests.append(.init(path: path, sha256: sha256Hex(data)))
        }
        let manifestData = try StableJSON.data(for: manifest)
        let key = PrivateKey(
            schemaVersion: "2",
            probeID: manifest.probeID,
            runKind: runKind,
            publicManifestSHA256: sha256Hex(manifestData),
            mediaDigests: mediaDigests,
            sourceManifestPath: "/private/sources.json",
            sources: plan.sources.map(PrivateKey.Source.init),
            thresholds: ProductProbeScore.evaluate(
                counts: .init(
                    identity: 0,
                    preferenceAndExport: 0,
                    repeatUse: 0,
                    motion: 0,
                    paidCommitment: 0)
            ).thresholds)
        let manifestURL = publicRoot.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)
        try StableJSON.write(key, to: keyURL)
        return BoundPair(
            manifest: manifest,
            key: key,
            manifestURL: manifestURL,
            keyURL: keyURL)
    }

    private func scorePair(
        _ pair: BoundPair,
        outputDirectory: URL
    ) -> (status: LabExitCode, error: String) {
        let missingRoot = pair.manifestURL.deletingLastPathComponent()
        var error = ""
        let status = ProductProbeCLI.score(
            arguments: .init(
                stimuliManifestPath: pair.manifestURL.path,
                keyPath: pair.keyURL.path,
                sessionOnePath: missingRoot.appendingPathComponent("missing-session.csv").path,
                repeatLogPath: missingRoot.appendingPathComponent("missing-repeat.csv").path,
                outputDirectory: outputDirectory.path,
                gitShaOverride: "deadbeef"),
            standardOutput: { _ in },
            standardError: { error += $0 },
            date: "2026-09-04")
        return (status, error)
    }

    private func replacingLabel(in manifest: PublicManifest, with label: String) -> PublicManifest {
        PublicManifest(
            schemaVersion: manifest.schemaVersion,
            probeID: manifest.probeID,
            label: label,
            date: manifest.date,
            askiGitSHA: manifest.askiGitSHA,
            seed: manifest.seed,
            fps: manifest.fps,
            duration: manifest.duration,
            sources: manifest.sources)
    }

    private func replacingSchemaVersion(
        in manifest: PublicManifest,
        with schemaVersion: String
    ) -> PublicManifest {
        PublicManifest(
            schemaVersion: schemaVersion,
            probeID: manifest.probeID,
            label: manifest.label,
            date: manifest.date,
            askiGitSHA: manifest.askiGitSHA,
            seed: manifest.seed,
            fps: manifest.fps,
            duration: manifest.duration,
            sources: manifest.sources)
    }

    private func replacingSources(
        in manifest: PublicManifest,
        with sources: [PublicManifest.Source]
    ) -> PublicManifest {
        PublicManifest(
            schemaVersion: manifest.schemaVersion,
            probeID: manifest.probeID,
            label: manifest.label,
            date: manifest.date,
            askiGitSHA: manifest.askiGitSHA,
            seed: manifest.seed,
            fps: manifest.fps,
            duration: manifest.duration,
            sources: sources)
    }

    private func replacingContentClass(
        in source: PublicManifest.Source,
        with contentClass: ProductProbeContentClass
    ) -> PublicManifest.Source {
        PublicManifest.Source(
            sourceCode: source.sourceCode,
            role: source.role,
            contentClass: contentClass,
            options: source.options,
            motionFile: source.motionFile,
            pixelSize: source.pixelSize)
    }

    private func replacingOptionToken(
        in source: PublicManifest.Source,
        optionIndex: Int,
        with token: String
    ) -> PublicManifest.Source {
        var options = source.options
        options[optionIndex] = PublicManifest.Option(
            token: token,
            file: options[optionIndex].file)
        return PublicManifest.Source(
            sourceCode: source.sourceCode,
            role: source.role,
            contentClass: source.contentClass,
            options: options,
            motionFile: source.motionFile,
            pixelSize: source.pixelSize)
    }

    private func replacingOptionFile(
        in source: PublicManifest.Source,
        optionIndex: Int,
        with file: String
    ) -> PublicManifest.Source {
        var options = source.options
        options[optionIndex] = PublicManifest.Option(
            token: options[optionIndex].token,
            file: file)
        return PublicManifest.Source(
            sourceCode: source.sourceCode,
            role: source.role,
            contentClass: source.contentClass,
            options: options,
            motionFile: source.motionFile,
            pixelSize: source.pixelSize)
    }

    private func writeReboundManifest(
        _ manifest: PublicManifest,
        pair: BoundPair
    ) throws -> BoundPair {
        let manifestData = try StableJSON.data(for: manifest)
        let key = replacingManifestDigest(in: pair.key, with: sha256Hex(manifestData))
        try manifestData.write(to: pair.manifestURL, options: .atomic)
        try StableJSON.write(key, to: pair.keyURL)
        return pair.replacing(manifest: manifest, key: key)
    }

    private func replacingMediaDigests(
        in key: PrivateKey,
        with mediaDigests: [PrivateKey.MediaDigest]
    ) -> PrivateKey {
        PrivateKey(
            schemaVersion: key.schemaVersion,
            probeID: key.probeID,
            runKind: key.runKind,
            publicManifestSHA256: key.publicManifestSHA256,
            mediaDigests: mediaDigests,
            sourceManifestPath: key.sourceManifestPath,
            sources: key.sources,
            thresholds: key.thresholds)
    }

    private func replacingManifestDigest(in key: PrivateKey, with digest: String) -> PrivateKey {
        PrivateKey(
            schemaVersion: key.schemaVersion,
            probeID: key.probeID,
            runKind: key.runKind,
            publicManifestSHA256: digest,
            mediaDigests: key.mediaDigests,
            sourceManifestPath: key.sourceManifestPath,
            sources: key.sources,
            thresholds: key.thresholds)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func responseRows(
        key: PrivateKey,
        identity: Int,
        preference: Int,
        repeatUse: Int,
        motion: Int,
        paid: Int
    ) -> (session: [[String]], repeats: [[String]]) {
        let identitySources = key.sources.filter { $0.role == .identity }
        let vesperIdentity = identitySources.compactMap { $0.options.first(where: { $0.arm == .vesper })?.token }
        let nonVesperIdentity = identitySources.compactMap { $0.options.first(where: { $0.arm != .vesper })?.token }
        let jobs = key.sources.filter { $0.role == .job }.sorted { $0.participantID! < $1.participantID! }
        var sessions: [[String]] = []
        for (index, job) in jobs.enumerated() {
            let participant = job.participantID!
            let identities = index < identity ? vesperIdentity : nonVesperIdentity
            let preferred = index < preference ? job.options.first(where: { $0.arm == .vesper })!.token : "none"
            sessions.append([
                participant,
                identities.joined(separator: ";"),
                job.sourceCode,
                preferred,
                index < motion ? "motion" : "still",
                index < preference ? "true" : "false",
                "first-source-\(index)",
                "2026-09-01T00:00:00Z",
            ])
        }
        var repeats: [[String]] = []
        for index in 0..<max(repeatUse, paid) {
            let didRepeat = index < repeatUse
            repeats.append([
                jobs[index].participantID!,
                didRepeat ? "second-source-\(index)" : "",
                didRepeat ? "true" : "false",
                didRepeat ? "2026-09-03T00:00:00Z" : "",
                index < paid ? "100" : "0",
            ])
        }
        return (sessions, repeats)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AskiProductProbeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func syntheticImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.15, green: 0.08, blue: 0.04, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.7, blue: 0.3, alpha: 1))
        context.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        return context.makeImage()!
    }
}
