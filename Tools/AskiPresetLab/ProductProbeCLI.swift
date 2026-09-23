import Aski
import AskiToolSupport
import CoreGraphics
import CryptoKit
import Darwin
import Foundation

public struct ProductProbeStimuliArguments: Sendable {
    public let sourceManifestPath: String
    public let outputDirectory: String
    public let keyOutputPath: String
    public let seed: UInt64
    public let fps: Int
    public let duration: Double
    public let runKind: String
    public let gitShaOverride: String?

    public init(
        sourceManifestPath: String,
        outputDirectory: String,
        keyOutputPath: String,
        seed: UInt64 = 7301,
        fps: Int = 12,
        duration: Double = 2,
        runKind: String = "human-probe",
        gitShaOverride: String? = nil
    ) {
        self.sourceManifestPath = sourceManifestPath
        self.outputDirectory = outputDirectory
        self.keyOutputPath = keyOutputPath
        self.seed = seed
        self.fps = fps
        self.duration = duration
        self.runKind = runKind
        self.gitShaOverride = gitShaOverride
    }
}

public struct ProductProbeScoreArguments: Sendable {
    public let stimuliManifestPath: String
    public let keyPath: String
    public let sessionOnePath: String
    public let repeatLogPath: String
    public let outputDirectory: String
    public let gitShaOverride: String?

    public init(
        stimuliManifestPath: String,
        keyPath: String,
        sessionOnePath: String,
        repeatLogPath: String,
        outputDirectory: String,
        gitShaOverride: String? = nil
    ) {
        self.stimuliManifestPath = stimuliManifestPath
        self.keyPath = keyPath
        self.sessionOnePath = sessionOnePath
        self.repeatLogPath = repeatLogPath
        self.outputDirectory = outputDirectory
        self.gitShaOverride = gitShaOverride
    }
}

public enum ProductProbeRole: String, Codable, Hashable, Sendable {
    case identity
    case job
}

public enum ProductProbeContentClass: String, Codable, CaseIterable, Hashable, Sendable {
    case portrait
    case cover
    case live
}

public struct ProductProbeSourceManifest: Codable, Sendable {
    public let schemaVersion: String
    public let probeOrdinal: Int
    public let sources: [Source]

    public struct Source: Codable, Sendable {
        public let id: String
        public let path: String
        public let role: ProductProbeRole
        public let contentClass: ProductProbeContentClass
        public let participantId: String?

        public init(
            id: String,
            path: String,
            role: ProductProbeRole,
            contentClass: ProductProbeContentClass,
            participantId: String? = nil
        ) {
            self.id = id
            self.path = path
            self.role = role
            self.contentClass = contentClass
            self.participantId = participantId
        }
    }

    public init(schemaVersion: String = "1", probeOrdinal: Int, sources: [Source]) {
        self.schemaVersion = schemaVersion
        self.probeOrdinal = probeOrdinal
        self.sources = sources
    }

    public func validated() throws -> Self {
        guard schemaVersion == "1" else { throw ProductProbeError.invalid("source schemaVersion must be '1'") }
        guard probeOrdinal == 1 || probeOrdinal == 2 else {
            throw ProductProbeError.invalid("probeOrdinal must be 1 or 2")
        }
        guard sources.count == 11 else {
            throw ProductProbeError.invalid("source manifest must contain exactly 3 identity and 8 job sources")
        }
        let ids = sources.map(\.id)
        let paths = sources.map(\.path)
        guard Set(ids).count == ids.count, Set(paths).count == paths.count else {
            throw ProductProbeError.invalid("source ids and paths must be unique")
        }
        guard sources.allSatisfy({ !$0.id.isEmpty && !$0.path.isEmpty }) else {
            throw ProductProbeError.invalid("source ids and paths must not be empty")
        }

        let identity = sources.filter { $0.role == .identity }
        let jobs = sources.filter { $0.role == .job }
        guard identity.count == 3, jobs.count == 8 else {
            throw ProductProbeError.invalid("source manifest must contain exactly 3 identity and 8 job sources")
        }
        guard Set(identity.map(\.contentClass)) == Set(ProductProbeContentClass.allCases) else {
            throw ProductProbeError.invalid("identity sources must contain one portrait, one cover, and one live image")
        }
        guard identity.allSatisfy({ $0.participantId == nil }) else {
            throw ProductProbeError.invalid("identity sources must not contain participantId")
        }
        let participants = jobs.compactMap(\.participantId)
        guard participants.count == 8, Set(participants).count == 8,
            participants.allSatisfy({ !$0.isEmpty })
        else {
            throw ProductProbeError.invalid("job sources require eight unique, nonempty participantId values")
        }
        let quotas = Dictionary(grouping: jobs, by: \.contentClass).mapValues(\.count)
        guard quotas[.portrait] == 3, quotas[.cover] == 3, quotas[.live] == 2 else {
            throw ProductProbeError.invalid("job-source quotas must be portrait=3, cover=3, live=2")
        }
        return self
    }
}

public enum ProductProbeArm: String, Codable, CaseIterable, Hashable, Sendable {
    case vesper
    case genericFullColor
    case standardVesperPalette
}

public struct ProductProbePlan: Equatable, Sendable {
    public let sources: [Source]

    public struct Source: Equatable, Sendable {
        public let sourceCode: String
        public let sourceID: String
        public let inputPath: String
        public let role: ProductProbeRole
        public let contentClass: ProductProbeContentClass
        public let participantID: String?
        public let options: [Option]

        public struct Option: Equatable, Sendable {
            public let token: String
            public let arm: ProductProbeArm
        }
    }

    public static func make(from manifest: ProductProbeSourceManifest, seed: UInt64) throws -> Self {
        let valid = try manifest.validated()
        let ordered = valid.sources.sorted {
            if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
            return $0.id < $1.id
        }
        var generator = ProductProbeGenerator(seed: seed)
        var result: [Source] = []
        for (index, source) in ordered.enumerated() {
            var arms = ProductProbeArm.allCases
            arms.shuffle(using: &generator)
            let sourceCode = String(format: "SRC-%03d", index + 1)
            let options = arms.enumerated().map {
                Source.Option(token: "\(sourceCode)-OPT-\($0.offset + 1)", arm: $0.element)
            }
            result.append(
                Source(
                    sourceCode: sourceCode,
                    sourceID: source.id,
                    inputPath: source.path,
                    role: source.role,
                    contentClass: source.contentClass,
                    participantID: source.participantId,
                    options: options
                ))
        }
        return Self(sources: result)
    }
}

public enum ProductProbeDisposition: String, Codable, Sendable {
    case proceed = "PROCEED"
    case refine = "REFINE"
    case stop = "STOP"
}

public struct ProductProbeScore: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let cohortSize: Int
    public let counts: Counts
    public let thresholds: Counts
    public let passes: Passes
    public let disposition: ProductProbeDisposition
    public let motionRetained: Bool
    public let paidGatePassed: Bool
    public let consumerExpansionEligible: Bool

    public struct Counts: Codable, Equatable, Sendable {
        public let identity: Int
        public let preferenceAndExport: Int
        public let repeatUse: Int
        public let motion: Int
        public let paidCommitment: Int
    }

    public struct Passes: Codable, Equatable, Sendable {
        public let identity: Bool
        public let preferenceAndExport: Bool
        public let repeatUse: Bool
        public let motion: Bool
        public let paidCommitment: Bool
    }

    public static func evaluate(counts: Counts) -> Self {
        let thresholds = Counts(
            identity: 6, preferenceAndExport: 5, repeatUse: 3, motion: 5, paidCommitment: 2)
        let passes = Passes(
            identity: counts.identity >= thresholds.identity,
            preferenceAndExport: counts.preferenceAndExport >= thresholds.preferenceAndExport,
            repeatUse: counts.repeatUse >= thresholds.repeatUse,
            motion: counts.motion >= thresholds.motion,
            paidCommitment: counts.paidCommitment >= thresholds.paidCommitment
        )
        let core = [
            (counts.identity, thresholds.identity, passes.identity),
            (counts.preferenceAndExport, thresholds.preferenceAndExport, passes.preferenceAndExport),
            (counts.repeatUse, thresholds.repeatUse, passes.repeatUse),
        ]
        let disposition: ProductProbeDisposition
        if core.allSatisfy(\.2) {
            disposition = .proceed
        } else if core.filter({ !$0.2 }).count == 1,
            let failed = core.first(where: { !$0.2 }), failed.0 == failed.1 - 1
        {
            disposition = .refine
        } else {
            disposition = .stop
        }
        return Self(
            schemaVersion: "1",
            cohortSize: 8,
            counts: counts,
            thresholds: thresholds,
            passes: passes,
            disposition: disposition,
            motionRetained: passes.motion,
            paidGatePassed: passes.paidCommitment,
            consumerExpansionEligible: disposition == .proceed && passes.paidCommitment
        )
    }
}

public enum ProductProbeCLI {
    public static let sessionOneHeader =
        "participant_id,identity_tokens,job_source_code,preference_token,motion_choice,first_exported,first_source_token,first_session_utc"
    public static let repeatHeader =
        "participant_id,second_source_token,second_exported,second_session_utc,paid_design_partner_cents"

    public static func generate(
        arguments: ProductProbeStimuliArguments,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = PresetLabCLI.todayUTC()
    ) -> LabExitCode {
        do {
            guard (1...60).contains(arguments.fps), arguments.duration.isFinite,
                arguments.duration > 0, arguments.duration <= 10,
                arguments.runKind == "human-probe" || arguments.runKind == "instrument-smoke"
            else {
                throw ProductProbeError.invalid(
                    "fps, duration, or run-kind is outside the probe-stimuli command contract")
            }
            let decoder = JSONDecoder()
            let manifest = try decoder.decode(
                ProductProbeSourceManifest.self,
                from: Data(contentsOf: URL(fileURLWithPath: arguments.sourceManifestPath)))
            let plan = try ProductProbePlan.make(from: manifest, seed: arguments.seed)
            let outputURL = URL(fileURLWithPath: arguments.outputDirectory).standardizedFileURL
            let keyURL = URL(fileURLWithPath: arguments.keyOutputPath).standardizedFileURL
            try requireFreshOutputDirectory(outputURL)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let outputDirectoryFD = try openDirectory(at: outputURL, createIfMissing: false)
            defer { close(outputDirectoryFD) }
            let keyParentFD = try openKeyParentDirectory(keyURL)
            defer { close(keyParentFD) }
            try requirePrivateKeyOutside(
                keyParentFD: keyParentFD,
                keyFilename: keyURL.lastPathComponent,
                outputDirectoryFD: outputDirectoryFD)

            var publicSources: [PublicManifest.Source] = []
            for source in plan.sources {
                let image = try DemoImageIO.loadImage(at: source.inputPath)
                let rendered = renderStillArms(image)
                let phase = source.role == .identity ? "identity" : "job"
                let phaseURL = outputURL.appendingPathComponent(phase, isDirectory: true)
                try FileManager.default.createDirectory(at: phaseURL, withIntermediateDirectories: true)
                var options: [PublicManifest.Option] = []
                for option in source.options {
                    guard let still = rendered[option.arm] else {
                        throw ProductProbeError.invalid("missing rendered arm")
                    }
                    let file = "\(phase)/\(option.token).png"
                    try DemoImageIO.writePNG(still, to: outputURL.appendingPathComponent(file).path)
                    options.append(.init(token: option.token, file: file))
                }
                let dimensions = Set(rendered.values.map { "\($0.width)x\($0.height)" })
                guard dimensions.count == 1 else {
                    throw ProductProbeError.invalid("still arms did not produce matched geometry")
                }

                var motionFile: String?
                if source.role == .job {
                    let motionURL = outputURL.appendingPathComponent("motion", isDirectory: true)
                    try FileManager.default.createDirectory(at: motionURL, withIntermediateDirectories: true)
                    let file = "motion/\(source.sourceCode)-CENTER.gif"
                    let frames = renderCenterReveal(
                        image, seed: arguments.seed, fps: arguments.fps, duration: arguments.duration)
                    try ASCIIGIFEncoder().write(frames, loopCount: 1, to: outputURL.appendingPathComponent(file))
                    motionFile = file
                }
                publicSources.append(
                    .init(
                        sourceCode: source.sourceCode,
                        role: source.role,
                        contentClass: source.contentClass,
                        options: options,
                        motionFile: motionFile,
                        pixelSize: dimensions.first!
                    ))
            }

            let probeID = "aski-73-probe-\(manifest.probeOrdinal)-seed-\(arguments.seed)"
            let publicManifest = PublicManifest(
                schemaVersion: "2",
                probeID: probeID,
                label: arguments.runKind,
                date: date,
                askiGitSHA: GitSHA.resolve(override: arguments.gitShaOverride),
                seed: arguments.seed,
                fps: arguments.fps,
                duration: arguments.duration,
                sources: publicSources
            )
            let publicManifestData = try StableJSON.data(for: publicManifest)
            let mediaDigests = try referencedMediaPaths(in: publicManifest).map { path in
                PrivateKey.MediaDigest(
                    path: path,
                    sha256: try sha256Hex(ofRelativePath: path, rootDirectoryFD: outputDirectoryFD)
                )
            }
            let key = PrivateKey(
                schemaVersion: "2",
                probeID: probeID,
                runKind: arguments.runKind,
                publicManifestSHA256: sha256Hex(of: publicManifestData),
                mediaDigests: mediaDigests,
                sourceManifestPath: arguments.sourceManifestPath,
                sources: plan.sources.map(PrivateKey.Source.init),
                thresholds: ProductProbeScore.evaluate(
                    counts: .init(identity: 0, preferenceAndExport: 0, repeatUse: 0, motion: 0, paidCommitment: 0)
                ).thresholds
            )
            try publicManifestData.write(
                to: outputURL.appendingPathComponent("manifest.json"), options: .atomic)
            try writePrivateKey(
                try StableJSON.data(for: key),
                filename: keyURL.lastPathComponent,
                parentDirectoryFD: keyParentFD,
                outputDirectoryFD: outputDirectoryFD)
            try (sessionOneHeader + "\n").write(
                to: outputURL.appendingPathComponent("session-one-template.csv"), atomically: true, encoding: .utf8)
            try (repeatHeader + "\n").write(
                to: outputURL.appendingPathComponent("repeat-template.csv"), atomically: true, encoding: .utf8)
            standardOutput("wrote blinded stimuli and empty response templates to \(outputURL.path)\n")
            standardOutput("wrote private arm/source key to \(keyURL.path); keep it from raters\n")
            standardOutput("no product verdict exists until genuine first- and later-session responses are scored\n")
            return .success
        } catch let error as ProductProbeError {
            standardError("error: \(error.description)\n")
            return .usage
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }
    }

    public static func score(
        arguments: ProductProbeScoreArguments,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = PresetLabCLI.todayUTC()
    ) -> LabExitCode {
        do {
            let decoder = JSONDecoder()
            let publicManifestURL = URL(fileURLWithPath: arguments.stimuliManifestPath).standardizedFileURL
            let keyURL = URL(fileURLWithPath: arguments.keyPath).standardizedFileURL
            let publicManifestData = try readControlArtifact(
                at: publicManifestURL, artifact: "stimuli manifest")
            let keyData = try readControlArtifact(at: keyURL, artifact: "private key")
            try requireSchemaV2(publicManifestData, artifact: "stimuli manifest")
            try requireSchemaV2(keyData, artifact: "private key")
            let publicManifest = try decoder.decode(
                PublicManifest.self,
                from: publicManifestData)
            let key = try decoder.decode(
                PrivateKey.self,
                from: keyData)
            try validatePair(
                publicManifest,
                manifestData: publicManifestData,
                manifestURL: publicManifestURL,
                key: key)
            let sessionRows = try parseCSV(
                at: arguments.sessionOnePath, expectedHeader: sessionOneHeader, fields: 8)
            let repeatRows = try parseCSV(
                at: arguments.repeatLogPath, expectedHeader: repeatHeader, fields: 5)
            let score = try scoreResponses(sessionRows: sessionRows, repeatRows: repeatRows, key: key)
            let outputURL = URL(fileURLWithPath: arguments.outputDirectory)
            try requireFreshOutputDirectory(outputURL)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try StableJSON.write(score, to: outputURL.appendingPathComponent("score.json"))
            let readout = readoutMarkdown(score, probeID: key.probeID)
            try readout.write(to: outputURL.appendingPathComponent("readout.md"), atomically: true, encoding: .utf8)
            let yaml = resultYAML(
                score, date: date, gitSHA: GitSHA.resolve(override: arguments.gitShaOverride))
            try yaml.write(to: outputURL.appendingPathComponent("result.yaml"), atomically: true, encoding: .utf8)
            standardOutput("\(score.disposition.rawValue): wrote validated score to \(outputURL.path)\n")
            return .success
        } catch let error as ProductProbeError {
            standardError("error: \(error.description)\n")
            return .usage
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }
    }

    public static func renderStillArms(_ image: CGImage) -> [ProductProbeArm: CGImage] {
        let preset = VesperPreset.canonical
        let vesper = preset.render(image)
        let generic = DefaultConverter().convert(image, columns: preset.columns).renderImage(
            font: preset.font,
            backgroundColor: preset.backgroundColor,
            scale: preset.scale,
            preserveSourceAspect: true
        )
        let different = DraftVesperPreset(
            ink: preset.ink,
            accent: preset.accent,
            contrast: preset.contrast,
            colorSpace: preset.colorSpace,
            oversample: preset.oversample,
            fontSize: preset.fontSize,
            scale: preset.scale
        ).makeConverter(charset: .standard).convert(image, columns: preset.columns).renderImage(
            font: preset.font,
            backgroundColor: preset.backgroundColor,
            scale: preset.scale,
            preserveSourceAspect: true
        )
        return [.vesper: vesper, .genericFullColor: generic, .standardVesperPalette: different]
    }

    public static func renderCenterReveal(
        _ image: CGImage, seed: UInt64, fps: Int, duration: Double
    ) -> [RenderedGIFFrame] {
        let preset = VesperPreset.canonical
        let options = AnimationOptions(
            duration: duration,
            seed: seed,
            cycling: nil,
            entrance: .reveal(origin: .center),
            ongoing: nil
        )
        let grids = preset.makeConverter().animate(
            image, columns: preset.columns, options: options
        ).materialize(frameRate: fps)
        let delay = 1.0 / Double(fps)
        return grids.map {
            RenderedGIFFrame(
                image: $0.renderImage(
                    font: preset.font,
                    backgroundColor: preset.backgroundColor,
                    scale: preset.scale,
                    preserveSourceAspect: true),
                delay: delay)
        }
    }

    static func scoreResponses(
        sessionRows: [[String]], repeatRows: [[String]], key: PrivateKey
    ) throws -> ProductProbeScore {
        let jobs = key.sources.filter { $0.role == .job }
        let routedParticipants = jobs.compactMap(\.participantID)
        guard routedParticipants.count == 8, Set(routedParticipants).count == 8 else {
            throw ProductProbeError.invalid("private key must contain eight unique job participants")
        }
        let participants = Dictionary(
            uniqueKeysWithValues: jobs.compactMap {
                source -> (String, PrivateKey.Source)? in
                guard let participant = source.participantID else { return nil }
                return (participant, source)
            })
        guard sessionRows.count == 8 else {
            throw ProductProbeError.invalid("session-one CSV must contain exactly 8 participant rows")
        }
        guard Set(sessionRows.map { $0[0] }).count == 8,
            Set(sessionRows.map { $0[0] }) == Set(participants.keys)
        else {
            throw ProductProbeError.invalid("session-one participants must match the private key exactly once")
        }
        guard Set(repeatRows.map { $0[0] }).count == repeatRows.count,
            repeatRows.allSatisfy({ participants[$0[0]] != nil })
        else {
            throw ProductProbeError.invalid("repeat-log participants must be unique and present in the private key")
        }

        let identitySources = key.sources.filter { $0.role == .identity }
        let expectedIdentityTokens = Set(
            identitySources.compactMap { source in
                source.options.first(where: { $0.arm == .vesper })?.token
            })
        guard expectedIdentityTokens.count == 3 else {
            throw ProductProbeError.invalid("private key must contain three Vesper identity tokens")
        }
        let formatter = ISO8601DateFormatter()
        var firstByParticipant: [String: (date: Date, source: String)] = [:]
        var identityCount = 0
        var preferenceCount = 0
        var motionCount = 0
        for row in sessionRows {
            let participant = row[0]
            let selected = Set(row[1].split(separator: ";").map(String.init))
            guard selected.count == 3 else {
                throw ProductProbeError.invalid("\(participant): identity_tokens must contain three unique semicolon-separated tokens")
            }
            let allIdentityTokens = Set(identitySources.flatMap { $0.options.map(\.token) })
            guard selected.isSubset(of: allIdentityTokens) else {
                throw ProductProbeError.invalid("\(participant): identity_tokens contains an unknown token")
            }
            if selected == expectedIdentityTokens { identityCount += 1 }
            guard let job = participants[participant], row[2] == job.sourceCode else {
                throw ProductProbeError.invalid("\(participant): job_source_code does not match the private key")
            }
            let jobTokens = Set(job.options.map(\.token))
            guard row[3] == "none" || jobTokens.contains(row[3]) else {
                throw ProductProbeError.invalid("\(participant): preference_token must be 'none' or a token for the assigned job source")
            }
            guard row[4] == "still" || row[4] == "motion" || row[4] == "none" else {
                throw ProductProbeError.invalid("\(participant): motion_choice must be still, motion, or none")
            }
            guard let exported = parseBool(row[5]) else {
                throw ProductProbeError.invalid("\(participant): first_exported must be true or false")
            }
            guard !row[6].isEmpty, let firstDate = formatter.date(from: row[7]) else {
                throw ProductProbeError.invalid("\(participant): first source token and RFC3339 timestamp are required")
            }
            firstByParticipant[participant] = (firstDate, row[6])
            if let vesper = job.options.first(where: { $0.arm == .vesper })?.token,
                row[3] == vesper, exported
            {
                preferenceCount += 1
            }
            if row[4] == "motion" { motionCount += 1 }
        }

        var repeatCount = 0
        var paidCount = 0
        for row in repeatRows {
            let participant = row[0]
            guard let exported = parseBool(row[2]) else {
                throw ProductProbeError.invalid("\(participant): second_exported must be true or false")
            }
            guard let cents = Int(row[4]), cents >= 0 else {
                throw ProductProbeError.invalid("\(participant): paid_design_partner_cents must be a nonnegative integer")
            }
            if cents > 0 { paidCount += 1 }
            if exported {
                guard let first = firstByParticipant[participant],
                    !row[1].isEmpty, row[1] != first.source,
                    let secondDate = formatter.date(from: row[3])
                else {
                    throw ProductProbeError.invalid("\(participant): an exported repeat requires a distinct source and RFC3339 timestamp")
                }
                let interval = secondDate.timeIntervalSince(first.date)
                guard interval >= 48 * 3600, interval <= 14 * 24 * 3600 else {
                    throw ProductProbeError.invalid("\(participant): repeat export must occur 48 hours through 14 days after session one")
                }
                repeatCount += 1
            } else if !row[1].isEmpty || !row[3].isEmpty {
                throw ProductProbeError.invalid("\(participant): leave repeat source/time empty when second_exported=false")
            }
        }
        return ProductProbeScore.evaluate(
            counts: .init(
                identity: identityCount,
                preferenceAndExport: preferenceCount,
                repeatUse: repeatCount,
                motion: motionCount,
                paidCommitment: paidCount
            ))
    }

    private static func validatePair(
        _ manifest: PublicManifest,
        manifestData: Data,
        manifestURL: URL,
        key: PrivateKey
    ) throws {
        guard manifest.schemaVersion == "2", key.schemaVersion == "2", manifest.probeID == key.probeID else {
            throw ProductProbeError.invalid("stimuli manifest and private key are not a matching schema-v2 pair")
        }
        let canonicalManifestData = try StableJSON.data(for: manifest)
        guard manifestData == canonicalManifestData else {
            throw ProductProbeError.invalid("stimuli manifest is not canonical schema-v2 JSON")
        }
        guard sha256Hex(of: canonicalManifestData) == key.publicManifestSHA256 else {
            throw ProductProbeError.invalid("stimuli manifest digest does not match the private key")
        }
        guard key.runKind == "human-probe", manifest.label == key.runKind else {
            throw ProductProbeError.invalid(
                "instrument-smoke manifests and keys cannot produce a product disposition")
        }
        guard manifest.sources.count == 11, key.sources.count == 11 else {
            throw ProductProbeError.invalid("schema-v2 pairs require exactly eleven sources")
        }
        let publicIdentity = manifest.sources.filter { $0.role == .identity }
        let publicJobs = manifest.sources.filter { $0.role == .job }
        let privateIdentity = key.sources.filter { $0.role == .identity }
        let privateJobs = key.sources.filter { $0.role == .job }
        guard publicIdentity.count == 3, publicJobs.count == 8,
            privateIdentity.count == 3, privateJobs.count == 8
        else {
            throw ProductProbeError.invalid("schema-v2 pairs require exactly three identity and eight job sources")
        }
        guard Set(publicIdentity.map(\.contentClass)) == Set(ProductProbeContentClass.allCases),
            Set(privateIdentity.map(\.contentClass)) == Set(ProductProbeContentClass.allCases)
        else {
            throw ProductProbeError.invalid("schema-v2 identity sources must cover portrait, cover, and live")
        }
        let publicJobQuotas = Dictionary(grouping: publicJobs, by: \.contentClass).mapValues(\.count)
        let privateJobQuotas = Dictionary(grouping: privateJobs, by: \.contentClass).mapValues(\.count)
        guard publicJobQuotas[.portrait] == 3, publicJobQuotas[.cover] == 3,
            publicJobQuotas[.live] == 2, privateJobQuotas == publicJobQuotas
        else {
            throw ProductProbeError.invalid("schema-v2 job-source quotas must be portrait=3, cover=3, live=2")
        }
        let participants = privateJobs.compactMap(\.participantID)
        guard privateIdentity.allSatisfy({ $0.participantID == nil }), participants.count == 8,
            Set(participants).count == 8, participants.allSatisfy({ !$0.isEmpty })
        else {
            throw ProductProbeError.invalid(
                "schema-v2 keys require eight unique job participants and no identity participant")
        }
        guard Set(key.sources.map(\.sourceID)).count == 11,
            Set(key.sources.map(\.inputPath)).count == 11
        else {
            throw ProductProbeError.invalid("private key source IDs and input paths must be unique")
        }
        let frozenThresholds = ProductProbeScore.evaluate(
            counts: .init(
                identity: 0,
                preferenceAndExport: 0,
                repeatUse: 0,
                motion: 0,
                paidCommitment: 0)
        ).thresholds
        guard key.thresholds == frozenThresholds else {
            throw ProductProbeError.invalid("private key thresholds do not match the frozen product gates")
        }

        let publicSourceCodes = manifest.sources.map(\.sourceCode)
        let privateSourceCodes = key.sources.map(\.sourceCode)
        guard Set(publicSourceCodes).count == publicSourceCodes.count,
            Set(privateSourceCodes).count == privateSourceCodes.count,
            Set(publicSourceCodes) == Set(privateSourceCodes)
        else {
            throw ProductProbeError.invalid("stimuli manifest source codes do not match the private key")
        }
        let privateSources = Dictionary(uniqueKeysWithValues: key.sources.map { ($0.sourceCode, $0) })
        let allPublicTokens = manifest.sources.flatMap { $0.options.map(\.token) }
        let allPrivateTokens = key.sources.flatMap { $0.options.map(\.token) }
        guard allPublicTokens.count == 33, Set(allPublicTokens).count == 33,
            allPrivateTokens.count == 33, Set(allPrivateTokens).count == 33
        else {
            throw ProductProbeError.invalid("schema-v2 option tokens must be globally unique")
        }
        for publicSource in manifest.sources {
            guard let privateSource = privateSources[publicSource.sourceCode],
                publicSource.role == privateSource.role,
                publicSource.contentClass == privateSource.contentClass,
                publicSource.options.count == 3,
                privateSource.options.count == 3,
                (publicSource.motionFile != nil) == (publicSource.role == .job),
                Set(privateSource.options.map(\.arm)) == Set(ProductProbeArm.allCases)
            else {
                throw ProductProbeError.invalid("stimuli manifest source mapping does not match the private key")
            }
            let publicTokens = publicSource.options.map(\.token)
            let privateTokens = privateSource.options.map(\.token)
            guard Set(publicTokens).count == publicTokens.count,
                Set(privateTokens).count == privateTokens.count,
                Set(publicTokens) == Set(privateTokens)
            else {
                throw ProductProbeError.invalid("stimuli manifest token mapping does not match the private key")
            }
        }

        let referencedPaths = try referencedMediaPaths(in: manifest)
        let boundPaths = key.mediaDigests.map(\.path)
        guard boundPaths == boundPaths.sorted(), Set(boundPaths).count == boundPaths.count,
            boundPaths == referencedPaths
        else {
            throw ProductProbeError.invalid("stimuli media paths do not match the private key")
        }
        let mediaRoot = manifestURL.deletingLastPathComponent()
        let mediaRootFD = try openDirectory(at: mediaRoot, createIfMissing: false)
        defer { close(mediaRootFD) }
        for digest in key.mediaDigests {
            guard try sha256Hex(ofRelativePath: digest.path, rootDirectoryFD: mediaRootFD) == digest.sha256 else {
                throw ProductProbeError.invalid("stimuli media digest mismatch: \(digest.path)")
            }
        }
        let recheckedMediaRootFD = try openDirectory(at: mediaRoot, createIfMissing: false)
        defer { close(recheckedMediaRootFD) }
        guard sameOpenFile(mediaRootFD, recheckedMediaRootFD) else {
            throw ProductProbeError.invalid("stimuli media root changed while the pair was verified")
        }
    }

    private static func referencedMediaPaths(in manifest: PublicManifest) throws -> [String] {
        let paths = manifest.sources.flatMap { source in
            source.options.map(\.file) + [source.motionFile].compactMap { $0 }
        }
        guard !paths.isEmpty, Set(paths).count == paths.count,
            paths.allSatisfy(isSafeRelativeMediaPath)
        else {
            throw ProductProbeError.invalid("stimuli manifest media paths must be unique safe relative paths")
        }
        return paths.sorted()
    }

    private static func isSafeRelativeMediaPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func requireSchemaV2(_ data: Data, artifact: String) throws {
        let version: SchemaVersionEnvelope
        do {
            version = try JSONDecoder().decode(SchemaVersionEnvelope.self, from: data)
        } catch {
            throw ProductProbeError.invalid(
                "\(artifact) has no readable schemaVersion; regenerate probe stimuli with schema v2")
        }
        guard version.schemaVersion == "2" else {
            throw ProductProbeError.invalid(
                "\(artifact) schema \(version.schemaVersion) is unsupported; regenerate probe stimuli with schema v2")
        }
    }

    private static let maximumMediaBytes: off_t = 256 * 1024 * 1024
    private static let maximumControlArtifactBytes: off_t = 16 * 1024 * 1024

    private static func readControlArtifact(at url: URL, artifact: String) throws -> Data {
        let filename = url.lastPathComponent
        guard !filename.isEmpty, filename != ".", filename != "..",
            !filename.contains("/"), !filename.contains("\0")
        else {
            throw ProductProbeError.invalid("\(artifact) path must name a file")
        }
        let parentURL = url.deletingLastPathComponent()
        let parentFD = try openDirectory(at: parentURL, createIfMissing: false)
        defer { close(parentFD) }
        let fileFD = filename.withCString {
            openat(parentFD, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard fileFD >= 0 else {
            throw ProductProbeError.invalid("cannot securely open \(artifact)")
        }
        defer { close(fileFD) }

        var initial = stat()
        guard fstat(fileFD, &initial) == 0,
            initial.st_mode & S_IFMT == S_IFREG,
            initial.st_size >= 0, initial.st_size <= maximumControlArtifactBytes
        else {
            throw ProductProbeError.invalid("\(artifact) must be a bounded regular file")
        }
        var result = Data()
        result.reserveCapacity(Int(initial.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(fileFD, bytes.baseAddress, bytes.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw ProductProbeError.invalid("cannot read \(artifact)")
            }
            if count == 0 { break }
            guard off_t(result.count) + off_t(count) <= maximumControlArtifactBytes else {
                throw ProductProbeError.invalid("\(artifact) exceeds the size limit")
            }
            result.append(contentsOf: buffer.prefix(count))
        }
        var final = stat()
        guard fstat(fileFD, &final) == 0, result.count == Int(initial.st_size),
            metadataIsUnchanged(initial, final)
        else {
            throw ProductProbeError.invalid("\(artifact) changed while it was read")
        }

        let recheckedFD = filename.withCString {
            openat(parentFD, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard recheckedFD >= 0 else {
            throw ProductProbeError.invalid("\(artifact) changed at its declared path")
        }
        defer { close(recheckedFD) }
        var rechecked = stat()
        guard fstat(recheckedFD, &rechecked) == 0, sameFile(initial, rechecked) else {
            throw ProductProbeError.invalid("\(artifact) changed at its declared path")
        }
        let recheckedParentFD = try openDirectory(at: parentURL, createIfMissing: false)
        defer { close(recheckedParentFD) }
        guard sameOpenFile(parentFD, recheckedParentFD) else {
            throw ProductProbeError.invalid("\(artifact) parent changed while it was read")
        }
        return result
    }

    private static func sha256Hex(ofRelativePath path: String, rootDirectoryFD: Int32) throws -> String {
        let mediaFD = try openRelativeMedia(path, rootDirectoryFD: rootDirectoryFD)
        defer { close(mediaFD) }

        var initial = stat()
        guard fstat(mediaFD, &initial) == 0,
            initial.st_mode & S_IFMT == S_IFREG,
            initial.st_size >= 0, initial.st_size <= maximumMediaBytes
        else {
            throw ProductProbeError.invalid("stimuli media must be a bounded regular file: \(path)")
        }

        var hasher = SHA256()
        var total: off_t = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(mediaFD, bytes.baseAddress, bytes.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw ProductProbeError.invalid("cannot read stimuli media: \(path)")
            }
            if count == 0 { break }
            total += off_t(count)
            guard total <= maximumMediaBytes else {
                throw ProductProbeError.invalid("stimuli media exceeds the size limit: \(path)")
            }
            hasher.update(data: Data(buffer.prefix(count)))
        }

        var final = stat()
        guard fstat(mediaFD, &final) == 0, total == initial.st_size,
            metadataIsUnchanged(initial, final)
        else {
            throw ProductProbeError.invalid("stimuli media changed while it was verified: \(path)")
        }
        let recheckedFD = try openRelativeMedia(path, rootDirectoryFD: rootDirectoryFD)
        defer { close(recheckedFD) }
        var rechecked = stat()
        guard fstat(recheckedFD, &rechecked) == 0, sameFile(initial, rechecked) else {
            throw ProductProbeError.invalid("stimuli media changed at its declared path: \(path)")
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func openRelativeMedia(_ path: String, rootDirectoryFD: Int32) throws -> Int32 {
        guard isSafeRelativeMediaPath(path) else {
            throw ProductProbeError.invalid("stimuli manifest media paths must be unique safe relative paths")
        }
        let components = path.split(separator: "/").map(String.init)
        var directoryFD = dup(rootDirectoryFD)
        guard directoryFD >= 0 else {
            throw ProductProbeError.invalid("cannot securely open stimuli media root")
        }
        for component in components.dropLast() {
            let nextFD = component.withCString {
                openat(directoryFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard nextFD >= 0 else {
                let failure = errno
                close(directoryFD)
                if failure == ENOENT {
                    throw ProductProbeError.invalid("stimuli media is missing: \(path)")
                }
                throw ProductProbeError.invalid("cannot securely open stimuli media: \(path)")
            }
            close(directoryFD)
            directoryFD = nextFD
        }
        let mediaFD = components.last!.withCString {
            openat(directoryFD, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        let failure = errno
        close(directoryFD)
        guard mediaFD >= 0 else {
            if failure == ENOENT {
                throw ProductProbeError.invalid("stimuli media is missing: \(path)")
            }
            throw ProductProbeError.invalid("cannot securely open stimuli media: \(path)")
        }
        return mediaFD
    }

    private static func metadataIsUnchanged(_ initial: stat, _ final: stat) -> Bool {
        sameFile(initial, final)
            && initial.st_size == final.st_size
            && initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec
            && initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec
            && initial.st_ctimespec.tv_sec == final.st_ctimespec.tv_sec
            && initial.st_ctimespec.tv_nsec == final.st_ctimespec.tv_nsec
    }

    private static func parseCSV(at path: String, expectedHeader: String, fields: Int) throws -> [[String]] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let lines = text.split(whereSeparator: \Character.isNewline).map(String.init)
        guard lines.first == expectedHeader else {
            throw ProductProbeError.invalid("\(path): CSV header does not match schema v1")
        }
        return try lines.dropFirst().map { line in
            guard !line.contains("\"") else {
                throw ProductProbeError.invalid("\(path): quoted or comma-containing values are not supported")
            }
            let values = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard values.count == fields else {
                throw ProductProbeError.invalid("\(path): each row must contain \(fields) fields")
            }
            return values
        }
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value {
        case "true": true
        case "false": false
        default: nil
        }
    }

    private static func openKeyParentDirectory(_ keyURL: URL) throws -> Int32 {
        let filename = keyURL.lastPathComponent
        guard !filename.isEmpty, filename != ".", filename != "..",
            !filename.contains("/"), !filename.contains("\0")
        else {
            throw ProductProbeError.invalid("--key-output must name a file")
        }
        let resolvedParent = keyURL.deletingLastPathComponent().resolvingSymlinksInPath()
        return try openDirectory(at: resolvedParent, createIfMissing: true)
    }

    private static func openDirectory(at url: URL, createIfMissing: Bool) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw ProductProbeError.invalid("probe paths must be absolute filesystem paths")
        }
        let resolvedPath = try resolvedPathAllowingMissingTail(url.path)
        var directoryFD = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directoryFD >= 0 else {
            throw ProductProbeError.invalid("cannot securely open the filesystem root")
        }
        for component in resolvedPath.split(separator: "/").map(String.init) {
            var nextFD = component.withCString {
                openat(directoryFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            if nextFD < 0, errno == ENOENT, createIfMissing {
                let created = component.withCString { mkdirat(directoryFD, $0, mode_t(0o700)) }
                guard created == 0 || errno == EEXIST else {
                    close(directoryFD)
                    throw ProductProbeError.invalid("cannot securely create private-key directory")
                }
                nextFD = component.withCString {
                    openat(directoryFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
            }
            guard nextFD >= 0 else {
                let failure = errno
                close(directoryFD)
                throw ProductProbeError.invalid(
                    "cannot securely open probe directory component \(component) (errno \(failure))")
            }
            close(directoryFD)
            directoryFD = nextFD
        }
        return directoryFD
    }

    private static func resolvedPathAllowingMissingTail(_ path: String) throws -> String {
        var existingPath = path
        var missingComponents: [String] = []
        while true {
            let resolvedPointer = existingPath.withCString { realpath($0, nil) }
            if let resolvedPointer {
                defer { free(resolvedPointer) }
                return ([String(cString: resolvedPointer)] + missingComponents).joined(separator: "/")
            }
            guard errno == ENOENT else {
                throw ProductProbeError.invalid("cannot securely resolve probe directory")
            }
            let existingURL = URL(fileURLWithPath: existingPath).standardizedFileURL
            guard existingURL.path != "/" else {
                throw ProductProbeError.invalid("cannot securely resolve probe directory")
            }
            missingComponents.insert(existingURL.lastPathComponent, at: 0)
            existingPath = existingURL.deletingLastPathComponent().path
        }
    }

    private static func requirePrivateKeyOutside(
        keyParentFD: Int32,
        keyFilename: String,
        outputDirectoryFD: Int32
    ) throws {
        guard
            !directoryIsDescendant(
                directoryFD: keyParentFD, ofDirectoryFD: outputDirectoryFD)
        else {
            throw ProductProbeError.invalid("--key-output must be outside the rater-visible --output-dir")
        }
        var existing = stat()
        let result = keyFilename.withCString {
            fstatat(keyParentFD, $0, &existing, AT_SYMLINK_NOFOLLOW)
        }
        guard result != 0 else {
            throw ProductProbeError.invalid("--key-output already exists; refusing to overwrite a private key")
        }
        guard errno == ENOENT else {
            throw ProductProbeError.invalid("cannot securely inspect --key-output")
        }
    }

    private static func directoryIsDescendant(
        directoryFD: Int32,
        ofDirectoryFD ancestorFD: Int32
    ) -> Bool {
        var ancestor = stat()
        guard fstat(ancestorFD, &ancestor) == 0 else { return true }
        var currentFD = dup(directoryFD)
        guard currentFD >= 0 else { return true }
        defer { close(currentFD) }
        for _ in 0..<1024 {
            var current = stat()
            guard fstat(currentFD, &current) == 0 else { return true }
            if sameFile(current, ancestor) { return true }
            let parentFD = openat(currentFD, "..", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            guard parentFD >= 0 else { return true }
            var parent = stat()
            guard fstat(parentFD, &parent) == 0 else {
                close(parentFD)
                return true
            }
            if sameFile(current, parent) {
                close(parentFD)
                return false
            }
            close(currentFD)
            currentFD = parentFD
        }
        return true
    }

    private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    private static func sameOpenFile(_ lhsFD: Int32, _ rhsFD: Int32) -> Bool {
        var lhs = stat()
        var rhs = stat()
        return fstat(lhsFD, &lhs) == 0 && fstat(rhsFD, &rhs) == 0 && sameFile(lhs, rhs)
    }

    private static func writePrivateKey(
        _ data: Data,
        filename: String,
        parentDirectoryFD: Int32,
        outputDirectoryFD: Int32
    ) throws {
        guard
            !directoryIsDescendant(
                directoryFD: parentDirectoryFD, ofDirectoryFD: outputDirectoryFD)
        else {
            throw ProductProbeError.invalid("--key-output moved inside the rater-visible --output-dir")
        }
        let fileFD = filename.withCString {
            openat(
                parentDirectoryFD,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o600))
        }
        guard fileFD >= 0 else {
            if errno == EEXIST {
                throw ProductProbeError.invalid("--key-output already exists; refusing to overwrite a private key")
            }
            throw ProductProbeError.invalid("cannot securely create --key-output")
        }
        var complete = false
        defer {
            close(fileFD)
            if !complete {
                filename.withCString { _ = unlinkat(parentDirectoryFD, $0, 0) }
            }
        }
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(
                    fileFD,
                    bytes.baseAddress?.advanced(by: written),
                    bytes.count - written)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw ProductProbeError.invalid("cannot securely write --key-output")
                }
                written += count
            }
        }
        guard fsync(fileFD) == 0 else {
            throw ProductProbeError.invalid("cannot durably write --key-output")
        }
        complete = true
    }

    private static func requireFreshOutputDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ProductProbeError.invalid("output path exists and is not a directory")
            }
            let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
            guard contents.isEmpty else {
                throw ProductProbeError.invalid("output directory must be absent or empty")
            }
        }
    }

    private static func readoutMarkdown(_ score: ProductProbeScore, probeID: String) -> String {
        """
        # ASKI-73 product-probe readout

        Probe: `\(probeID)`

        Disposition: **\(score.disposition.rawValue)**

        - Identity: \(score.counts.identity)/8 (gate ≥ \(score.thresholds.identity))
        - Vesper preference + first export: \(score.counts.preferenceAndExport)/8 (gate ≥ \(score.thresholds.preferenceAndExport))
        - Repeat export with a distinct source after 48 hours–14 days: \(score.counts.repeatUse)/8 (gate ≥ \(score.thresholds.repeatUse))
        - Motion selected: \(score.counts.motion)/8 (keep gate ≥ \(score.thresholds.motion))
        - Paid design-partner commitments: \(score.counts.paidCommitment)/8 (expansion gate ≥ \(score.thresholds.paidCommitment))

        The scorer validates structure, timing, participant routing, blinding tokens, and frozen thresholds. It cannot verify that a person used the product, exported an asset, or paid; retain source evidence outside the repository.
        """ + "\n"
    }

    private static func resultYAML(_ score: ProductProbeScore, date: String, gitSHA: String) -> String {
        """
        ---
        schema_version: "1"
        date: "\(date)"
        aski_git_sha: "\(gitSHA)"
        provenance: ["private human response logs; withheld"]
        outputs: ["readout.md", "score.json"]
        runner: "AskiPresetLab"
        command: "probe-score"
        summary: "identity=\(score.counts.identity)/8 preference_export=\(score.counts.preferenceAndExport)/8 repeat=\(score.counts.repeatUse)/8 motion=\(score.counts.motion)/8 paid=\(score.counts.paidCommitment)/8"
        ---
        """ + "\n"
    }
}

struct PublicManifest: Codable {
    let schemaVersion: String
    let probeID: String
    let label: String
    let date: String
    let askiGitSHA: String
    let seed: UInt64
    let fps: Int
    let duration: Double
    let sources: [Source]

    struct Source: Codable {
        let sourceCode: String
        let role: ProductProbeRole
        let contentClass: ProductProbeContentClass
        let options: [Option]
        let motionFile: String?
        let pixelSize: String
    }

    struct Option: Codable {
        let token: String
        let file: String
    }
}

struct PrivateKey: Codable {
    let schemaVersion: String
    let probeID: String
    let runKind: String
    let publicManifestSHA256: String
    let mediaDigests: [MediaDigest]
    let sourceManifestPath: String
    let sources: [Source]
    let thresholds: ProductProbeScore.Counts

    struct MediaDigest: Codable, Equatable {
        let path: String
        let sha256: String
    }

    struct Source: Codable {
        let sourceCode: String
        let sourceID: String
        let inputPath: String
        let role: ProductProbeRole
        let contentClass: ProductProbeContentClass
        let participantID: String?
        let options: [Option]

        init(_ source: ProductProbePlan.Source) {
            sourceCode = source.sourceCode
            sourceID = source.sourceID
            inputPath = source.inputPath
            role = source.role
            contentClass = source.contentClass
            participantID = source.participantID
            options = source.options.map { Option(token: $0.token, arm: $0.arm) }
        }
    }

    struct Option: Codable {
        let token: String
        let arm: ProductProbeArm
    }
}

private struct SchemaVersionEnvelope: Decodable {
    let schemaVersion: String
}

enum ProductProbeError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self {
        case .invalid(let message): message
        }
    }
}

private struct ProductProbeGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
