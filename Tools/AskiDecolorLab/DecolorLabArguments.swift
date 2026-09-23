import Foundation

public struct DecolorLabArguments: Equatable, Sendable {
    public let outputDirectory: String
    public let columns: Int
    public let backgroundHex: String
    public let gitShaOverride: String?
    public init(
        outputDirectory: String, columns: Int = 80,
        backgroundHex: String = "#101010", gitShaOverride: String? = nil
    ) {
        self.outputDirectory = outputDirectory
        self.columns = columns
        self.backgroundHex = backgroundHex
        self.gitShaOverride = gitShaOverride
    }
}
