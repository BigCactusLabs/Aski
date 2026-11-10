import Darwin
import Foundation

enum DemoOutputTransactionError: Error, CustomStringConvertible {
    case cannotStage(String)
    case cannotReplace(String)
    case unsupportedDestination(String, String)
    case cannotWriteStream(String)
    case injectedFailure

    public var destinationPath: String? {
        switch self {
        case .cannotStage(let path), .cannotReplace(let path), .unsupportedDestination(let path, _),
            .cannotWriteStream(let path):
            path
        case .injectedFailure: nil
        }
    }

    public var description: String {
        switch self {
        case .cannotStage(let path):
            "could not stage output '\(path)'"
        case .cannotReplace(let path):
            "could not replace output '\(path)'"
        case .unsupportedDestination(let path, let reason):
            "unsupported output '\(path)': \(reason)"
        case .cannotWriteStream(let path):
            "could not write output stream '\(path)'"
        case .injectedFailure:
            "injected output transaction failure"
        }
    }
}

/// Stages regular outputs beside their destinations, then replaces each one
/// with rollback if any replacement fails. Cross-filesystem atomicity is not
/// promised; every stage, backup, and replacement remains in its destination
/// directory. Supported text streams are written last and cannot be rolled back.
struct DemoOutputTransaction {
    struct Artifact {
        let destination: URL
        let data: Data
        let allowsTextStream: Bool

        init(destination: URL, data: Data, allowsTextStream: Bool = false) {
            self.destination = destination
            self.data = data
            self.allowsTextStream = allowsTextStream
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
        // Classify the complete set before creating files or opening streams.
        let classified = try deduplicated(artifacts).map { ($0, try streamDestination(for: $0)) }
        var staged = try stage(classified.filter { $0.1 == nil }.map(\.0))
        do {
            try replace(&staged)
            for (artifact, stream) in classified {
                if let stream {
                    try write(artifact, to: stream)
                }
            }
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
            let resolvedPath = artifact.destination.resolvingSymlinksInPath().path
            let key =
                resolvedPath == "/dev/null" || resolvedPath == "/dev/fd/1"
                ? resolvedPath : artifact.destination.standardizedFileURL.path
            if destinations.insert(key).inserted {
                uniqueReversed.append(artifact)
            }
        }
        return uniqueReversed.reversed()
    }

    private enum StreamDestination {
        case null
        case standardOutput
    }

    private func streamDestination(for artifact: Artifact) throws -> StreamDestination? {
        let path = artifact.destination.path
        let resolved = artifact.destination.resolvingSymlinksInPath()
        let stream: StreamDestination?
        switch resolved.path {
        case "/dev/null": stream = .null
        case "/dev/fd/1": stream = .standardOutput
        default: stream = nil
        }
        if let stream {
            guard artifact.allowsTextStream else {
                throw DemoOutputTransactionError.unsupportedDestination(path, "device destinations support text output only")
            }
            return stream
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: resolved.path)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            throw DemoOutputTransactionError.unsupportedDestination(path, "could not inspect destination")
        }
        guard let type = attributes[.type] as? FileAttributeType, type != .typeRegular else { return nil }
        let reason: String
        switch type {
        case .typeDirectory: reason = "destination is a directory"
        default: reason = "special destinations require text output to /dev/null or /dev/stdout"
        }
        throw DemoOutputTransactionError.unsupportedDestination(path, reason)
    }

    private func write(_ artifact: Artifact, to stream: StreamDestination) throws {
        do {
            switch stream {
            case .null:
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
                defer { try? handle.close() }
                try handle.write(contentsOf: artifact.data)
            case .standardOutput:
                let handle = FileHandle.standardOutput
                let descriptor = handle.fileDescriptor
                let previous = fcntl(descriptor, F_GETNOSIGPIPE)
                guard previous != -1, fcntl(descriptor, F_SETNOSIGPIPE, 1) != -1 else {
                    throw DemoOutputTransactionError.cannotWriteStream(artifact.destination.path)
                }
                // A broken pipe must throw before SIGPIPE can terminate the
                // process, so commit can restore the regular-file outputs.
                defer { _ = fcntl(descriptor, F_SETNOSIGPIPE, previous) }
                try handle.write(contentsOf: artifact.data)
            }
        } catch {
            throw DemoOutputTransactionError.cannotWriteStream(artifact.destination.path)
        }
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

            // Recheck before moving an existing node into a backup.
            guard try streamDestination(for: staged[index].artifact) == nil else {
                throw DemoOutputTransactionError.unsupportedDestination(
                    staged[index].artifact.destination.path, "destination changed to a stream during output preparation")
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
