import ArgumentParser

@_spi(AskiResearch) import Aski

/// `--output-dir` + `--aski-git-sha`, shared by the four labs via `@OptionGroup`.
public struct ProvenanceOptions: ParsableArguments {
    @Option(name: .customLong("output-dir"), help: "Directory to write artifacts (created if missing).")
    public var outputDirectory: String

    @Option(name: .customLong("aski-git-sha"), help: "Override the git SHA recorded in result provenance.")
    public var gitShaOverride: String?

    public init() {}

    public func validate() throws {
        try ToolValidation.requireSafeGitSHA(gitShaOverride)
    }
}

/// `--shape-query-polarity`, the one seam a lab uses to re-run an archived
/// screen under the other ink convention (ASKI-60).
///
/// It exists because polarity is a property of the CONVERTER, not of any lab's
/// own sampling: a lab that wants the other arm has to hand the real
/// `ASCIIConverter` a different `RenderingOptions`, and every lab doing that by
/// hand is how two instruments end up disagreeing about what they measured.
/// Shared here so an archived verdict re-run says, in its own recorded command,
/// which convention produced it.
///
/// The default is `inverted` — the shipped behavior — so a lab invoked exactly
/// as its archived command records it produces byte-identical output.
public struct ShapeQueryPolarityOption: ParsableArguments {
    @Option(
        name: .customLong("shape-query-polarity"),
        help:
            "Ink convention for the logPolar shape query: 'inverted' (1 - luma, the shipped default and the convention every archived verdict was measured under) or 'direct' (raw luma, the axis the candidate rasters, the tone pre-filter and the renderer already use). Default: inverted."
    )
    public var shapeQueryPolarityName: String = "inverted"

    public init() {}

    /// The parsed knob value. Validated by ``validate()``, so a bad string
    /// fails argument parsing rather than silently resolving to the default.
    public var shapeQueryPolarity: ShapeQueryPolarity {
        Self.parse(shapeQueryPolarityName) ?? .inverted
    }

    /// Applies the knob to a fresh options value. One line at every call site,
    /// so no lab has to know the SPI spelling.
    public func applied(to options: RenderingOptions = .default) -> RenderingOptions {
        var resolved = options
        resolved.shapeQueryPolarity = shapeQueryPolarity
        return resolved
    }

    public static func parse(_ raw: String) -> ShapeQueryPolarity? {
        switch raw {
        case "inverted": return .inverted
        case "direct": return .direct
        default: return nil
        }
    }

    public static func label(_ polarity: ShapeQueryPolarity) -> String {
        switch polarity {
        case .inverted: return "inverted"
        case .direct: return "direct"
        }
    }

    public func validate() throws {
        guard Self.parse(shapeQueryPolarityName) != nil else {
            throw ValidationError("--shape-query-polarity must be one of: inverted, direct")
        }
    }
}

/// `--seed`, shared by AskiColorLab and AskiMotionLab only.
public struct SeedOption: ParsableArguments {
    @Option(help: "Deterministic seed for randomized fixtures.")
    public var seed: UInt64 = 0

    public init() {}
}

/// The version string surfaced by `--version`, resolved once per process (a
/// `static let`, so `git` is never spawned on every `CommandConfiguration`
/// access during parse/help). It runs `git rev-parse HEAD` in the **current
/// working directory** (see `GitSHA.resolve`), so it reports the repo checkout's
/// HEAD when a tool is run from inside the Aski repo (the normal `swift run`
/// path) and `"unknown"` when run outside any repo. This is independent of the
/// labs' `--aski-git-sha` provenance override (which only affects recorded
/// metadata). These are dev/research CLIs run from the repo, so a cwd-probed SHA
/// is acceptable; a build-time-embedded SHA is out of scope for this sweep.
public enum ToolVersion {
    public static let current: String = GitSHA.resolve(override: nil)
}
