import Aski
import AskiToolSupport
import CoreGraphics
import Foundation

public enum MotionLabCLI {
    public static let usage = """
        AskiMotionLab — materialize deterministic ASCII motion frames and a GIF spike.

        Usage:
          swift run AskiMotionLab --output-dir <dir> [options]

        Required:
          --output-dir <dir>      Directory to write frames/, <preset>.gif, flicker.csv, result.yaml.

        Options:
          --preset <name>         reveal | cycle | all. Default: all.
          --image <path>          Input image. Default: a deterministic synthetic image.
          --columns <int>         ASCII columns. Default: 80.
          --fps <int>             Frames per second for materialization + GIF. Default: 12.
          --duration <seconds>    Animation duration. Default: 2.0.
          --seed <int>            Deterministic seed. Default: 0.
          --gif <true|false>      Emit per-preset GIF. Default: true.
          --aski-git-sha <sha>    Override the git SHA recorded in result.yaml.
          --help, -h              Print this usage.
        """

    public static func run(
        arguments: MotionLabArguments,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = MotionLabCLI.todayUTC()
    ) -> LabExitCode {
        let converter = DefaultConverter()
        let image: CGImage
        if let imagePath = arguments.imagePath {
            do {
                image = try DemoImageIO.loadThumbnailForConversion(
                    at: imagePath,
                    columns: arguments.columns,
                    tileShape: converter.tileShape,
                    oversample: converter.oversample
                )
            } catch {
                standardError("error: \(error)\n")
                return .ioError
            }
        } else {
            image = SyntheticImage.make()
        }

        let gitSHA = GitSHA.resolve(override: arguments.gitShaOverride)
        let outputURL = URL(fileURLWithPath: arguments.outputDirectory)
        let font = ASCIIFont.system(size: 10)
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        var runs: [PresetRun] = []
        var outputFiles: [String] = []

        for preset in arguments.presets {
            let options = MotionPresets.options(for: preset, duration: arguments.duration, seed: arguments.seed)
            let grids = converter.animate(image, columns: arguments.columns, options: options).materialize(frameRate: arguments.fps)
            let frames = grids.map(FrameTextRenderer.render)

            do {
                try ResultsWriter.writeFrames(frames, preset: preset, outputDirectory: outputURL)
            } catch {
                standardError("error: \(error)\n")
                return .ioError
            }

            var gifBytes: Int?
            if arguments.emitGIF {
                let delay = 1.0 / Double(arguments.fps)
                let frames = grids.map {
                    RenderedGIFFrame(
                        image: $0.renderImage(font: font, backgroundColor: background, scale: 1),
                        delay: delay
                    )
                }
                let gifURL = outputURL.appendingPathComponent("\(preset.rawValue).gif")
                do {
                    try ASCIIGIFEncoder().write(frames, loopCount: 0, to: gifURL)
                } catch {
                    standardError("error: \(error)\n")
                    return .ioError
                }
                let attributes = try? FileManager.default.attributesOfItem(atPath: gifURL.path)
                gifBytes = (attributes?[.size] as? NSNumber)?.intValue
                outputFiles.append("\(preset.rawValue).gif")
            }

            runs.append(
                PresetRun(
                    preset: preset,
                    frameCount: grids.count,
                    frameRate: arguments.fps,
                    metrics: FlickerMetrics.compute(frames: grids),
                    gifBytes: gifBytes
                ))
        }

        do {
            try ResultsWriter.writeFlickerCSV(runs: runs, outputDirectory: outputURL)
            outputFiles.append("flicker.csv")
            try ResultsWriter.writeManifest(
                outputDirectory: outputURL,
                date: date,
                gitSHA: gitSHA,
                command: commandLine(arguments),
                seed: arguments.seed,
                outputFiles: outputFiles
            )
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        return .success
    }

    public static func todayUTC() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func commandLine(_ arguments: MotionLabArguments) -> String {
        let presetToken =
            arguments.presets == MotionLabPreset.allCases
            ? "all"
            : arguments.presets.map(\.rawValue).joined(separator: "+")
        var parts = [
            "swift run AskiMotionLab",
            "--output-dir \(arguments.outputDirectory)",
            "--preset \(presetToken)",
            "--columns \(arguments.columns)",
            "--fps \(arguments.fps)",
            "--duration \(arguments.duration)",
            "--seed \(arguments.seed)",
            "--gif \(arguments.emitGIF)",
        ]
        if let imagePath = arguments.imagePath {
            parts.append("--image \(imagePath)")
        }
        if let gitShaOverride = arguments.gitShaOverride {
            parts.append("--aski-git-sha \(gitShaOverride)")
        }
        return parts.joined(separator: " ")
    }
}
