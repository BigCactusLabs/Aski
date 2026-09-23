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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "DemoOutputTransactionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
