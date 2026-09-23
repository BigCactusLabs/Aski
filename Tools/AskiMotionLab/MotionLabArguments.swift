import Foundation

public enum MotionLabPreset: String, CaseIterable, Equatable, Sendable {
    case reveal
    case cycle
}

/// Parsed MotionLab invocation context handed to `MotionLabCLI.run`. (The
/// hand-rolled parser and `MotionLabArgumentError` were removed in the SAP
/// migration.)
public struct MotionLabArguments: Equatable, Sendable {
    public let outputDirectory: String
    public let presets: [MotionLabPreset]
    public let imagePath: String?
    public let columns: Int
    public let fps: Int
    public let duration: Double
    public let seed: UInt64
    public let emitGIF: Bool
    public let gitShaOverride: String?

    public init(
        outputDirectory: String,
        presets: [MotionLabPreset] = MotionLabPreset.allCases,
        imagePath: String? = nil,
        columns: Int = 80,
        fps: Int = 12,
        duration: Double = 2.0,
        seed: UInt64 = 0,
        emitGIF: Bool = true,
        gitShaOverride: String? = nil
    ) {
        self.outputDirectory = outputDirectory
        self.presets = presets
        self.imagePath = imagePath
        self.columns = columns
        self.fps = fps
        self.duration = duration
        self.seed = seed
        self.emitGIF = emitGIF
        self.gitShaOverride = gitShaOverride
    }
}
