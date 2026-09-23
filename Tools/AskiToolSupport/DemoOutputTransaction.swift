import Foundation

enum DemoOutputTransactionError: Error, CustomStringConvertible {
    case cannotStage(String)
    case cannotReplace(String)
    case injectedFailure

    public var destinationPath: String? {
        switch self {
        case .cannotStage(let path), .cannotReplace(let path): path
        case .injectedFailure: nil
        }
    }

    public var description: String {
        switch self {
        case .cannotStage(let path):
            "could not stage output '\(path)'"
        case .cannotReplace(let path):
            "could not replace output '\(path)'"
        case .injectedFailure:
            "injected output transaction failure"
        }
    }
}

/// Stages requested outputs beside their destinations, then replaces each one
/// with rollback if any replacement fails. Cross-filesystem atomicity is not
/// promised; every stage, backup, and replacement remains in its destination
/// directory.
struct DemoOutputTransaction {
    struct Artifact {
        let destination: URL
        let data: Data

        init(destination: URL, data: Data) {
            self.destination = destination
            self.data = data
        }
    }

    private let failAfterReplacementCount: Int?

    init() {
        self.failAfterReplacementCount = nil
    }

    init(failAfterReplacementCount: Int?) {
        self.failAfterReplacementCount = failAfterReplacementCount
    }

    func commit(_ artifacts: [Artifact]) throws {
        var staged = try stage(deduplicated(artifacts))
        do {
            try replace(&staged)
        } catch {
            rollback(staged)
            throw error
        }
        cleanup(staged)
    }

    private func deduplicated(_ artifacts: [Artifact]) -> [Artifact] {
        var destinations = Set<String>()
        var uniqueReversed: [Artifact] = []
        for artifact in artifacts.reversed() {
            let key = artifact.destination.standardizedFileURL.path
            if destinations.insert(key).inserted {
                uniqueReversed.append(artifact)
            }
        }
        return uniqueReversed.reversed()
    }

    private func stage(_ artifacts: [Artifact]) throws -> [StagedArtifact] {
        var staged: [StagedArtifact] = []
        do {
            for artifact in artifacts {
                let stageURL = siblingURL(for: artifact.destination, role: "stage")
                let stagedArtifact = StagedArtifact(
                    artifact: artifact,
                    stageURL: stageURL,
                    backupURL: siblingURL(for: artifact.destination, role: "backup")
                )
                // Track the path before writing so a failed write that leaves a
                // partial file is cleaned by the enclosing error path.
                staged.append(stagedArtifact)
                do {
                    try artifact.data.write(to: stageURL, options: .withoutOverwriting)
                } catch {
                    throw DemoOutputTransactionError.cannotStage(artifact.destination.path)
                }
            }
            return staged
        } catch {
            cleanup(staged)
            throw error
        }
    }

    private func replace(_ staged: inout [StagedArtifact]) throws {
        let fileManager = FileManager.default
        var replacementCount = 0

        for index in staged.indices {
            if failAfterReplacementCount == replacementCount {
                throw DemoOutputTransactionError.injectedFailure
            }

            let destination = staged[index].artifact.destination
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
                guard !isDirectory.boolValue else {
                    throw DemoOutputTransactionError.cannotReplace(destination.path)
                }
                do {
                    try fileManager.moveItem(at: destination, to: staged[index].backupURL)
                    staged[index].hadExistingDestination = true
                } catch {
                    throw DemoOutputTransactionError.cannotReplace(destination.path)
                }
            }

            do {
                try fileManager.moveItem(at: staged[index].stageURL, to: destination)
                staged[index].replacedDestination = true
                replacementCount += 1
            } catch {
                throw DemoOutputTransactionError.cannotReplace(destination.path)
            }
        }
    }

    private func rollback(_ staged: [StagedArtifact]) {
        let fileManager = FileManager.default
        for artifact in staged.reversed() {
            if artifact.replacedDestination,
                fileManager.fileExists(atPath: artifact.artifact.destination.path)
            {
                try? fileManager.removeItem(at: artifact.artifact.destination)
            }
            if artifact.hadExistingDestination,
                !fileManager.fileExists(atPath: artifact.artifact.destination.path),
                fileManager.fileExists(atPath: artifact.backupURL.path)
            {
                try? fileManager.moveItem(at: artifact.backupURL, to: artifact.artifact.destination)
            }
            if fileManager.fileExists(atPath: artifact.stageURL.path) {
                try? fileManager.removeItem(at: artifact.stageURL)
            }
        }
    }

    private func cleanup(_ staged: [StagedArtifact]) {
        let fileManager = FileManager.default
        for artifact in staged {
            if fileManager.fileExists(atPath: artifact.stageURL.path) {
                try? fileManager.removeItem(at: artifact.stageURL)
            }
            if fileManager.fileExists(atPath: artifact.backupURL.path) {
                try? fileManager.removeItem(at: artifact.backupURL)
            }
        }
    }

    private func siblingURL(for destination: URL, role: String) -> URL {
        destination.deletingLastPathComponent().appending(path: ".aski-\(role)-\(UUID().uuidString)")
    }

    private struct StagedArtifact {
        let artifact: Artifact
        let stageURL: URL
        let backupURL: URL
        var hadExistingDestination = false
        var replacedDestination = false
    }
}
