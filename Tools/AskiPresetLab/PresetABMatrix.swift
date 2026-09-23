import AskiToolSupport

/// One A/B cell: a (charset, columns) pair to render through the draft preset.
public struct PresetCandidate: Equatable, Sendable {
    public let charset: Charset
    public let columns: Int

    public init(charset: Charset, columns: Int) {
        self.charset = charset
        self.columns = columns
    }

    /// Filesystem-safe identifier, e.g. `standard_cols-80`.
    public var slug: String { "\(charset.rawValue)_cols-\(columns)" }
}

/// Expands the two undecided one-way-door knobs (charset, columns) into an
/// ordered candidate list. Everything else in the render is locked by
/// `DraftVesperPreset`; only these two are swept for the ASTSK-47 A/B.
public enum PresetABMatrix {
    /// Charset-major cartesian product, deduplicated on `(charset, columns)`
    /// while preserving first-seen order.
    public static func expand(charsets: [Charset], columnCounts: [Int]) -> [PresetCandidate] {
        var seen = Set<String>()
        var candidates: [PresetCandidate] = []
        for charset in charsets {
            for columns in columnCounts {
                let candidate = PresetCandidate(charset: charset, columns: columns)
                if seen.insert(candidate.slug).inserted {
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }
}
