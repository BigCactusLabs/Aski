import Aski
import ArgumentParser
import CoreGraphics
import Foundation

public enum DemoExitCode: Int32, Equatable, Sendable {
    case success = 0
    case usage = 64
    case inputUnavailable = 66
    case failure = 70
}

/// Shared arguments and execution path for the first-class `aski render`
/// command and the source-compatible `AskiDemoCommand` wrapper.
public struct RenderArguments: ParsableArguments {
    @Argument(help: "Path to the input image.")
    public var inputPath: String

    @Option(help: "Number of ASCII columns (1...\(ToolArgumentBounds.maxColumns)).")
    public var columns: Int = 80

    @Option(name: .long, help: "Write ASCII text to this file instead of stdout.")
    public var output: String?

    @Option(name: .customLong("render-png"), help: "Render the ASCII grid to this PNG path.")
    public var renderPng: String?

    @Option(
        name: .customLong("width"),
        help: "Exact output pixel width for --render-png. The render scale is derived from this width and the grid, so the pixel size no longer depends on --font-size."
    )
    public var width: Int?

    @Option(
        name: .customLong("font-size"),
        help: "Font size for --render-png (0 < n <= \(Int(ToolArgumentBounds.maxFontSize)))."
    )
    public var fontSize: Double = 10

    @Option(help: "Character set to use.")
    public var charset: Charset = .standard

    @Option(
        help: "Background color for --render-png: #RRGGBB, a named color, or clear/transparent for an alpha-zero ground."
    )
    public var background: BackgroundColor = .black

    @Flag(inversion: .prefixedNo, help: "Reproduce the source image aspect ratio in --render-png output.")
    public var preserveAspect: Bool = true

    @OptionGroup public var mask: DemoMaskArguments

    public init() {}

    public func validate() throws {
        try ToolValidation.requireColumns(columns)
        try ToolValidation.requireFontSize(fontSize)
        if let width {
            guard renderPng != nil else {
                throw ValidationError("--width requires --render-png")
            }
            try ToolValidation.requireTargetPixelWidth(width)
        }
        try mask.validate(renderPNGPath: renderPng)
    }

    public func execute(
        writeManifest: String? = nil,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> DemoExitCode {
        do {
            let result = try ToolImageConversion.load(
                inputPath: inputPath,
                columns: columns,
                charset: charset,
                mask: mask
            )

            let textDestination: String
            let textUTF8Bytes: Int
            let standardOutputText: String?
            let textData: Data
            if let output {
                textDestination = output
                standardOutputText = nil
                textData = Data(result.text.utf8)
                textUTF8Bytes = textData.count
            } else {
                let text = result.text.hasSuffix("\n") ? result.text : result.text + "\n"
                textDestination = "stdout"
                standardOutputText = text
                textData = Data(text.utf8)
                textUTF8Bytes = textData.count
            }

            var renderedImage: CGImage?
            var pngData: Data?
            if renderPng != nil {
                let rendered: CGImage
                if let width {
                    rendered = result.grid.renderImage(
                        font: .system(size: CGFloat(fontSize)),
                        backgroundColor: background.cgColor,
                        targetPixelWidth: width,
                        preserveSourceAspect: preserveAspect
                    )
                    // The renderer answers out-of-range geometry (a derived
                    // height past the 4x ceiling) with a 1x1 fallback. That
                    // is not an exact-width render; refuse to write it or a
                    // manifest that claims it is.
                    guard rendered.width == width else {
                        standardError(
                            "error: --width \(width) is not renderable for this grid: the derived height exceeds \(ASCIIGrid.maxTargetPixelWidth) pixels\n"
                        )
                        return .failure
                    }
                } else {
                    rendered = result.grid.renderImage(
                        font: .system(size: CGFloat(fontSize)),
                        backgroundColor: background.cgColor,
                        scale: 1,
                        preserveSourceAspect: preserveAspect
                    )
                }
                renderedImage = rendered
                pngData = try DemoImageIO.encodePNG(rendered)
            }

            var artifacts: [DemoOutputTransaction.Artifact] = []
            if let output {
                artifacts.append(.init(destination: URL(fileURLWithPath: output), data: textData))
            }
            if let renderPng, let pngData {
                artifacts.append(.init(destination: URL(fileURLWithPath: renderPng), data: pngData))
            }

            if let writeManifest {
                let manifest = AskiRenderManifest(
                    inputPath: inputPath,
                    arguments: self,
                    result: result,
                    textDestination: textDestination,
                    textUTF8Bytes: textUTF8Bytes,
                    renderedImage: renderedImage
                )
                do {
                    artifacts.append(
                        .init(destination: URL(fileURLWithPath: writeManifest), data: try StableJSON.data(for: manifest))
                    )
                } catch {
                    standardError("error: could not write render manifest '\(writeManifest)': \(error)\n")
                    return .failure
                }
            }

            do {
                try DemoOutputTransaction().commit(artifacts)
            } catch let error as DemoOutputTransactionError {
                if let writeManifest,
                    let destinationPath = error.destinationPath,
                    URL(fileURLWithPath: destinationPath).standardizedFileURL.path
                        == URL(fileURLWithPath: writeManifest).standardizedFileURL.path
                {
                    standardError("error: could not write render manifest '\(writeManifest)': \(error)\n")
                } else {
                    standardError("error: \(error)\n")
                }
                return .failure
            }

            if let standardOutputText {
                standardOutput(standardOutputText)
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
}

/// Compatibility entry point for callers and tests that invoke the historical
/// `AskiDemo` command directly. New command-line usage should go through
/// `AskiCommand`, whose default `render` subcommand shares these arguments.
public struct AskiDemoCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "AskiDemo",
        abstract: "Convert an image to ASCII art and optionally render it to a PNG.",
        version: ToolVersion.current
    )

    @OptionGroup public var arguments: RenderArguments

    public init() {}

    // Preserve the existing programmatic surface while the parser storage moves
    // into the shared option group.
    public var inputPath: String { arguments.inputPath }
    public var columns: Int { arguments.columns }
    public var output: String? { arguments.output }
    public var renderPng: String? { arguments.renderPng }
    public var width: Int? { arguments.width }
    public var fontSize: Double { arguments.fontSize }
    public var charset: Charset { arguments.charset }
    public var background: BackgroundColor { arguments.background }
    public var preserveAspect: Bool { arguments.preserveAspect }
    public var mask: DemoMaskArguments { arguments.mask }

    public func validate() throws {
        try arguments.validate()
    }

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> DemoExitCode {
        arguments.execute(standardOutput: standardOutput, standardError: standardError)
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

/// The primary image conversion command under the public `aski` executable.
public struct AskiRenderCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Convert an image to ASCII art and optionally render it to a PNG.",
        version: ToolVersion.current
    )

    @OptionGroup public var arguments: RenderArguments

    @Option(name: .customLong("write-manifest"), help: "Write a deterministic render manifest to this path.")
    public var writeManifest: String?

    public init() {}

    public func validate() throws {
        try arguments.validate()
        // A manifest written over --output or --render-png would replace the
        // artifact it just described while still reporting it as valid.
        if let writeManifest {
            let manifestPath = URL(fileURLWithPath: writeManifest).standardizedFileURL.path
            let artifacts = [("--output", arguments.output), ("--render-png", arguments.renderPng)]
            for (option, path) in artifacts {
                if let path, URL(fileURLWithPath: path).standardizedFileURL.path == manifestPath {
                    throw ValidationError("--write-manifest must not target the same file as \(option) ('\(path)').")
                }
            }
        }
    }

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> DemoExitCode {
        arguments.execute(
            writeManifest: writeManifest,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}
