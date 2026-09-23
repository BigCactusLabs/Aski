import AskiToolSupport

/// Resolved, SAP-independent arguments for a preset A/B run (mirrors the other
/// labs' `*Arguments` structs so `PresetLabCLI.run` is directly testable).
public struct PresetLabArguments: Sendable {
    public var inputPath: String
    public var outputDirectory: String
    public var charsets: [Charset]
    public var columnCounts: [Int]
    public var inkHex: String
    public var accentHex: String
    public var background: BackgroundColor
    public var contrast: Float
    public var fontSize: Double
    public var scale: Double
    public var gitShaOverride: String?

    public init(
        inputPath: String,
        outputDirectory: String,
        charsets: [Charset],
        columnCounts: [Int],
        inkHex: String,
        accentHex: String,
        background: BackgroundColor,
        contrast: Float,
        fontSize: Double,
        scale: Double,
        gitShaOverride: String?
    ) {
        self.inputPath = inputPath
        self.outputDirectory = outputDirectory
        self.charsets = charsets
        self.columnCounts = columnCounts
        self.inkHex = inkHex
        self.accentHex = accentHex
        self.background = background
        self.contrast = contrast
        self.fontSize = fontSize
        self.scale = scale
        self.gitShaOverride = gitShaOverride
    }
}
