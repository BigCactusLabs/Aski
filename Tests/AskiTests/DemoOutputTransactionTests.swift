import Darwin
import Foundation
import Testing
@testable import AskiToolSupport

@Suite struct DemoOutputTransactionTests {
    @Test func replacesTwoRequestedArtifacts() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = directory.appending(path: "art.txt")
        let png = directory.appending(path: "art.png")

        try DemoOutputTransaction().commit([
            .init(destination: text, data: Data("new text\n".utf8)),
            .init(destination: png, data: Data([0x89, 0x50, 0x4E, 0x47])),
        ])

        #expect(try Data(contentsOf: text) == Data("new text\n".utf8))
        #expect(try Data(contentsOf: png) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func replacesExistingArtifactsWithoutChangingOpenFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "art.txt")
        let old = Data("old text\n".utf8)
        try old.write(to: destination)
        let oldHandle = try FileHandle(forReadingFrom: destination)
        defer { try? oldHandle.close() }

        try DemoOutputTransaction().commit([
            .init(destination: destination, data: Data("new text\n".utf8))
        ])

        #expect(try oldHandle.readToEnd() == old)
        #expect(try Data(contentsOf: destination) == Data("new text\n".utf8))
    }

    @Test func stagingFailureLeavesExistingDestinationsUntouched() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appending(path: "existing.txt")
        let missing = directory.appending(path: "missing-directory/new.txt")
        let old = Data("old text\n".utf8)
        try old.write(to: existing)

        do {
            try DemoOutputTransaction().commit([
                .init(destination: existing, data: Data("new text\n".utf8)),
                .init(destination: missing, data: Data("new file\n".utf8)),
            ])
            Issue.record("expected staging failure")
        } catch let error as DemoOutputTransactionError {
            #expect(error.description == "could not stage output '\(missing.path)'")
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(try Data(contentsOf: existing) == old)
        #expect(FileManager.default.fileExists(atPath: missing.path) == false)
    }

    @Test func replacementFailureRollsBackPriorDestinations() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "first.txt")
        let second = directory.appending(path: "second.txt")
        let oldFirst = Data("old first\n".utf8)
        let oldSecond = Data("old second\n".utf8)
        try oldFirst.write(to: first)
        try oldSecond.write(to: second)

        #expect(throws: DemoOutputTransactionError.self) {
            try DemoOutputTransaction(failAfterReplacementCount: 1).commit([
                .init(destination: first, data: Data("new first\n".utf8)),
                .init(destination: second, data: Data("new second\n".utf8)),
            ])
        }

        #expect(try Data(contentsOf: first) == oldFirst)
        #expect(try Data(contentsOf: second) == oldSecond)
    }

    @Test func nullOutputPreservesDeviceAndCommitsRegularFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "art.png")
        let null = URL(fileURLWithPath: "/dev/null")
        let before = try FileManager.default.attributesOfItem(atPath: null.path)

        try DemoOutputTransaction().commit([
            .init(destination: null, data: Data("discard me".utf8), allowsTextStream: true),
            .init(destination: destination, data: Data("png".utf8)),
        ])

        let after = try FileManager.default.attributesOfItem(atPath: null.path)
        #expect(after[.type] as? FileAttributeType == .typeCharacterSpecial)
        #expect(after[.systemFileNumber] as? NSNumber == before[.systemFileNumber] as? NSNumber)
        #expect(try Data(contentsOf: destination) == Data("png".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["art.png"])
    }

    @Test func symlinkToNullRemainsASymlink() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appending(path: "discard")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/dev/null")

        try DemoOutputTransaction().commit([
            .init(destination: link, data: Data("discard me".utf8), allowsTextStream: true)
        ])

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "/dev/null")
    }

    @Test func rejectsFIFOAndSymlinkBeforeChangingRegularFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fifo = directory.appending(path: "fifo")
        let link = directory.appending(path: "fifo-link")
        let existing = directory.appending(path: "existing.txt")
        let old = Data("sentinel".utf8)
        try old.write(to: existing)
        #expect(fifo.path.withCString { mkfifo($0, mode_t(0o600)) } == 0)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: fifo.path)

        for destination in [fifo, link] {
            do {
                try DemoOutputTransaction().commit([
                    .init(destination: existing, data: Data("replacement".utf8)),
                    .init(destination: destination, data: Data("blocked".utf8), allowsTextStream: true),
                ])
                Issue.record("expected FIFO rejection")
            } catch let error as DemoOutputTransactionError {
                #expect(error.description == "unsupported output '\(destination.path)': special destinations require text output to /dev/null or /dev/stdout")
            }
            #expect(try Data(contentsOf: existing) == old)
        }
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
                == ["existing.txt", "fifo", "fifo-link"])
    }

    @Test func rejectsOtherDevicesAndBinaryDeviceOutput() throws {
        for (path, allowsTextStream) in [("/dev/zero", true), ("/dev/null", false), ("/dev/stdout", false)] {
            do {
                try DemoOutputTransaction().commit([
                    .init(destination: URL(fileURLWithPath: path), data: Data(), allowsTextStream: allowsTextStream)
                ])
                Issue.record("expected special destination rejection")
            } catch let error as DemoOutputTransactionError {
                #expect(error.destinationPath == path)
                #expect(error.description.contains("unsupported output"))
            }
        }
    }

    @Test func nullOutputKeepsRegularFileRollback() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "first.txt")
        let second = directory.appending(path: "second.png")
        let old = Data("sentinel".utf8)
        try old.write(to: first)
        try old.write(to: second)

        #expect(throws: DemoOutputTransactionError.self) {
            try DemoOutputTransaction(failAfterReplacementCount: 1).commit([
                .init(destination: URL(fileURLWithPath: "/dev/null"), data: Data("discard".utf8), allowsTextStream: true),
                .init(destination: first, data: Data("new text".utf8)),
                .init(destination: second, data: Data("new png".utf8)),
            ])
        }
        #expect(try Data(contentsOf: first) == old)
        #expect(try Data(contentsOf: second) == old)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["first.txt", "second.png"])
    }

    @Test(arguments: [false, true], [Int32(0), Int32(1)])
    func stdoutPipeRestoresDescriptorAndFileState(closedReader: Bool, initialFlag: Int32) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "art.png")
        try Data("sentinel".utf8).write(to: destination)
        let path: String = destination.path

        await #expect(processExitsWith: .success) { [path = path as String, closedReader, initialFlag] in
            try DemoOutputTransactionTests.exerciseStdoutPipe(
                destination: URL(fileURLWithPath: path), closedReader: closedReader, initialFlag: initialFlag)
        }

        let expected = Data((closedReader ? "sentinel" : "replacement").utf8)
        #expect(try Data(contentsOf: destination) == expected)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["art.png"])
    }

    private static func exerciseStdoutPipe(destination: URL, closedReader: Bool, initialFlag: Int32) throws {
        let savedStdout = dup(STDOUT_FILENO)
        try #require(savedStdout >= 0)
        defer {
            _ = dup2(savedStdout, STDOUT_FILENO)
            close(savedStdout)
        }
        let pipe = Pipe()
        try #require(dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) == STDOUT_FILENO)
        try pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        if closedReader {
            try pipe.fileHandleForReading.close()
        }
        // Ensure this test would terminate without descriptor-scoped protection.
        signal(SIGPIPE, SIG_DFL)
        try #require(fcntl(STDOUT_FILENO, F_SETNOSIGPIPE, initialFlag) == 0)
        let payload = Data("stdout payload".utf8)
        do {
            try DemoOutputTransaction().commit([
                .init(destination: destination, data: Data("replacement".utf8)),
                .init(destination: URL(fileURLWithPath: "/dev/stdout"), data: payload, allowsTextStream: true),
            ])
            #expect(!closedReader)
        } catch let error as DemoOutputTransactionError {
            #expect(closedReader)
            guard case .cannotWriteStream(let path) = error else {
                Issue.record("unexpected transaction error: \(error)")
                return
            }
            #expect(path == "/dev/stdout")
        }
        #expect(fcntl(STDOUT_FILENO, F_GETNOSIGPIPE) == initialFlag)
        if !closedReader {
            #expect(try pipe.fileHandleForReading.read(upToCount: payload.count) == payload)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "DemoOutputTransactionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
