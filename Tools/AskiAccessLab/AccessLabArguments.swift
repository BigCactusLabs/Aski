import Foundation

/// Parsed AccessLab invocation context handed to `AccessLabCLI.run`. (The
/// hand-rolled parser and `AccessLabArgumentError` were removed in the SAP
/// migration.)
public struct AccessLabArguments: Equatable, Sendable {
    public let outputDirectory: String
    public let columns: Int
    public let gitShaOverride: String?

    public init(outputDirectory: String, columns: Int = 80, gitShaOverride: String? = nil) {
        self.outputDirectory = outputDirectory
        self.columns = columns
        self.gitShaOverride = gitShaOverride
    }
}
