import ArgumentParser
import Foundation

public enum InspectOutputFormat: String, CaseIterable, ExpressibleByArgument, Sendable {
    case text
    case json
}

/// Versioned machine contract emitted by `aski inspect --format json`.
///
/// Version 1 is additive: readers must ignore fields they do not understand.
/// Removing, renaming, or changing the meaning of a field requires a new schema
/// version.
public struct AskiInspectionReport: Codable, Equatable, Sendable {
    public struct Source: Codable, Equatable, Sendable {
        public let path: String
        public let normalizedPixelWidth: Int
        public let normalizedPixelHeight: Int

        public init(path: String, normalizedPixelWidth: Int, normalizedPixelHeight: Int) {
            self.path = path
            self.normalizedPixelWidth = normalizedPixelWidth
            self.normalizedPixelHeight = normalizedPixelHeight
        }
    }

    public struct Conversion: Codable, Equatable, Sendable {
        public let columns: Int
        public let rows: Int
        public let charset: String
        public let totalCells: Int
        public let nonWhitespaceCells: Int
        public let textUTF8Bytes: Int

        public init(
            columns: Int,
            rows: Int,
            charset: String,
            totalCells: Int,
            nonWhitespaceCells: Int,
            textUTF8Bytes: Int
        ) {
            self.columns = columns
            self.rows = rows
            self.charset = charset
            self.totalCells = totalCells
            self.nonWhitespaceCells = nonWhitespaceCells
            self.textUTF8Bytes = textUTF8Bytes
        }
    }

    public let schemaVersion: Int
    public let toolVersion: String
    public let source: Source
    public let conversion: Conversion

    public init(
        schemaVersion: Int = 1,
        toolVersion: String,
        source: Source,
        conversion: Conversion
    ) {
        self.schemaVersion = schemaVersion
        self.toolVersion = toolVersion
        self.source = source
        self.conversion = conversion
    }

    init(inputPath: String, charset: Charset, result: ToolImageConversion) {
        let nonWhitespace = result.grid.cells.reduce(into: 0) { total, row in
            total += row.lazy.filter { !$0.character.isWhitespace }.count
        }
        self.init(
            toolVersion: ToolVersion.current,
            source: Source(
                path: inputPath,
                normalizedPixelWidth: result.normalizedImage.width,
                normalizedPixelHeight: result.normalizedImage.height
            ),
            conversion: Conversion(
                columns: result.grid.columns,
                rows: result.grid.rows,
                charset: charset.rawValue,
                totalCells: result.grid.columns * result.grid.rows,
                nonWhitespaceCells: nonWhitespace,
                textUTF8Bytes: result.text.lengthOfBytes(using: .utf8)
            )
        )
    }

    public func renderText() -> String {
        """
        Aski inspection v\(schemaVersion)
        input: \(source.path)
        normalized pixels: \(source.normalizedPixelWidth) × \(source.normalizedPixelHeight)
        grid: \(conversion.columns) × \(conversion.rows) (\(conversion.totalCells) cells, \(conversion.nonWhitespaceCells) non-whitespace)
        charset: \(conversion.charset)
        plain text: \(conversion.textUTF8Bytes) UTF-8 bytes
        tool: \(toolVersion)
        """ + "\n"
    }
}

public struct AskiInspectCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect the resolved image-to-ASCII conversion without writing render artifacts.",
        version: ToolVersion.current
    )

    @Argument(help: "Path to the input image.")
    public var inputPath: String

    @Option(help: "Number of ASCII columns (1...\(ToolArgumentBounds.maxColumns)).")
    public var columns: Int = 80

    @Option(help: "Character set to use.")
    public var charset: Charset = .standard

    @Option(help: "Output representation: text or json.")
    public var format: InspectOutputFormat = .text

    @Option(name: .long, help: "Write the inspection to this file instead of stdout.")
    public var output: String?

    public init() {}

    public func validate() throws {
        try ToolValidation.requireColumns(columns)
    }

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> DemoExitCode {
        do {
            let result = try ToolImageConversion.load(
                inputPath: inputPath,
                columns: columns,
                charset: charset
            )
            let report = AskiInspectionReport(inputPath: inputPath, charset: charset, result: result)
            let data: Data
            switch format {
            case .text:
                data = Data(report.renderText().utf8)
            case .json:
                data = try StableJSON.data(for: report)
            }

            if let output {
                try data.write(to: URL(fileURLWithPath: output), options: .atomic)
            } else {
                standardOutput(String(decoding: data, as: UTF8.self))
            }
            return .success
        } catch DemoRuntimeError.inputUnavailable(let path) {
            standardError("error: could not open input image '\(path)'\n")
            return .inputUnavailable
        } catch {
            standardError("error: \(error)\n")
            return .failure
        }
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}
