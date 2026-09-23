import Foundation

public enum CSVWriterError: Error, Equatable, CustomStringConvertible {
    case fileCreateFailed(String)
    case outputPathIsDirectory(String)
    case columnCountMismatch(expected: Int, got: Int)
    case invalidValue(column: Int, value: String)

    public var description: String {
        switch self {
        case .fileCreateFailed(let path):
            "failed to create CSV file at \(path)"
        case .outputPathIsDirectory(let path):
            "CSV output path is a directory: \(path)"
        case .columnCountMismatch(let expected, let got):
            "CSV row has \(got) columns, expected \(expected)"
        case .invalidValue(let column, let value):
            "CSV column \(column) contains a forbidden character (',', '\"', or newline): \(value.debugDescription)"
        }
    }
}

public final class CSVWriter {
    public static let forbiddenCharacters: Set<Character> = [",", "\"", "\n", "\r"]

    private let handle: FileHandle
    private let columnCount: Int

    public init(url: URL, columns: [String]) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                throw CSVWriterError.outputPathIsDirectory(url.path)
            }
            try fileManager.removeItem(at: url)
        }
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw CSVWriterError.fileCreateFailed(url.path)
        }
        self.handle = try FileHandle(forWritingTo: url)
        self.columnCount = columns.count

        for (index, value) in columns.enumerated() {
            try Self.validate(value, column: index)
        }
        let headerLine = columns.joined(separator: ",") + "\n"
        try handle.write(contentsOf: Data(headerLine.utf8))
    }

    public func writeRow(_ values: [String]) throws {
        guard values.count == columnCount else {
            throw CSVWriterError.columnCountMismatch(expected: columnCount, got: values.count)
        }
        for (index, value) in values.enumerated() {
            try Self.validate(value, column: index)
        }
        let line = values.joined(separator: ",") + "\n"
        try handle.write(contentsOf: Data(line.utf8))
    }

    public func close() throws {
        try handle.close()
    }

    private static func validate(_ value: String, column: Int) throws {
        if value.contains(where: forbiddenCharacters.contains) {
            throw CSVWriterError.invalidValue(column: column, value: value)
        }
    }
}
