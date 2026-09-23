import Aski
import ArgumentParser
import CoreGraphics
import Foundation

public struct TileMatrixCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "AskiTileMatrix",
        abstract: "Render an image across a matrix of tile modes and cell shapes.",
        version: ToolVersion.current
    )

    @Argument(help: "Path to the input image.")
    public var inputPath: String

    @Argument(help: "Output directory (created if missing).")
    public var outputDirectory: String

    @Option(help: "Number of tile columns (1...\(ToolArgumentBounds.maxColumns)).")
    public var columns: Int = 64

    @Option(help: "Render scale in pixels per cell width (0 < n <= \(Int(ToolArgumentBounds.maxTileScale))).")
    public var scale: Double = 12

    public init() {}

    public func validate() throws {
        try ToolValidation.requireColumns(columns)
        try ToolValidation.requireTileScale(scale)
    }

    static let modes: [(name: String, mode: TileGridMode)] = [
        ("pixelArt", .pixelArt),
        ("brick", .brick),
        ("mosaic", .mosaic),
    ]

    static let shapes: [(name: String, shape: TileCellShape)] = [
        ("square", .square),
        ("hex", .hex),
        ("triangle", .triangle),
        ("diamond", .diamond),
        ("circle", .circle),
    ]

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> DemoExitCode {
        do {
            let outputURL = URL(fileURLWithPath: outputDirectory)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            let converter = TileGridConverter(palette: .adaptive(maxColors: 16))
            let image = try DemoImageIO.loadThumbnailForConversion(
                at: inputPath,
                columns: columns,
                tileShape: converter.samplingShape,
                oversample: converter.oversample
            )
            let grid = converter.convert(image, columns: columns)

            for (modeName, mode) in Self.modes {
                for (shapeName, shape) in Self.shapes {
                    let rendered = grid.renderImage(
                        mode: mode,
                        cellShape: shape,
                        scale: CGFloat(scale),
                        backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
                    )
                    let path =
                        outputURL
                        .appendingPathComponent("\(modeName)-\(shapeName).png")
                        .path
                    try DemoImageIO.writePNG(rendered, to: path)
                    standardOutput(path + "\n")
                }
            }
            return .success
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
