import Foundation

/// Parsed lab invocation context handed to the seven subcommand bodies. (The
/// hand-rolled parser and `LabArgumentError` were removed in the SAP migration;
/// parsing now lives in `AskiColorLabCommand`.)
public struct LabArguments: Equatable, Sendable {
    public let outputDirectory: String
    public let seed: UInt64
    public let gitShaOverride: String?
    /// Optional directory of real images for the Helmlab large-deltaE visual
    /// corpus review (`--review-corpus`). Consumed by `helmlab-reference`;
    /// nil -> the corpus review is skipped.
    public let reviewCorpusDirectory: String?

    public init(
        outputDirectory: String,
        seed: UInt64 = 0,
        gitShaOverride: String? = nil,
        reviewCorpusDirectory: String? = nil
    ) {
        self.outputDirectory = outputDirectory
        self.seed = seed
        self.gitShaOverride = gitShaOverride
        self.reviewCorpusDirectory = reviewCorpusDirectory
    }
}
