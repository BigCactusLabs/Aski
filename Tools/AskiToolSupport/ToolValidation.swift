import ArgumentParser
import Aski

/// Throwing bounds validators shared across the CLI tools. Each throws a SAP
/// `ValidationError` (printed + exit 64) when the value is out of range. These
/// wrap the numeric ceilings in `ToolArgumentBounds`.
public enum ToolValidation {
    public static func requireColumns(_ value: Int) throws {
        guard value > 0, value <= ToolArgumentBounds.maxColumns else {
            throw ValidationError("columns must be in 1...\(ToolArgumentBounds.maxColumns), got \(value)")
        }
    }

    public static func requireTargetPixelWidth(_ value: Int) throws {
        // The public exact-width renderer supersamples at 4x, so its ceiling is
        // a quarter of the raw pixel-extent bound; a wider request would only
        // ever produce the renderer's 1x1 fallback image.
        let limit = ASCIIGrid.maxTargetPixelWidth
        guard value > 0, value <= limit else {
            throw ValidationError("width must be in 1...\(limit), got \(value)")
        }
    }

    public static func requireFontSize(_ value: Double) throws {
        guard value.isFinite, value > 0, value <= ToolArgumentBounds.maxFontSize else {
            throw ValidationError("font size must be finite and in 0 < n <= \(ToolArgumentBounds.maxFontSize), got \(value)")
        }
    }

    public static func requireFontScale(_ value: Double) throws {
        guard value.isFinite, value > 0, value <= ToolArgumentBounds.maxFontScale else {
            throw ValidationError("font scale must be finite and in 0 < n <= \(ToolArgumentBounds.maxFontScale), got \(value)")
        }
    }

    public static func requireTileScale(_ value: Double) throws {
        guard value.isFinite, value > 0, value <= ToolArgumentBounds.maxTileScale else {
            throw ValidationError("scale must be finite and in 0 < n <= \(ToolArgumentBounds.maxTileScale), got \(value)")
        }
    }

    public static func requireFPS(_ value: Int) throws {
        guard value > 0, value <= ToolArgumentBounds.maxFPS else {
            throw ValidationError("fps must be in 1...\(ToolArgumentBounds.maxFPS), got \(value)")
        }
    }

    public static func requireDuration(_ value: Double) throws {
        guard value.isFinite, value > 0, value <= ToolArgumentBounds.maxDuration else {
            throw ValidationError("duration must be finite and in 0 < n <= \(ToolArgumentBounds.maxDuration), got \(value)")
        }
    }

    public static func requireMaterializedFrameCount(duration: Double, fps: Int) throws {
        guard ToolArgumentBounds.materializedFrameCountIsValid(duration: duration, fps: fps) else {
            throw ValidationError("duration x fps would materialize too many frames (cap \(ToolArgumentBounds.maxMaterializedFrames))")
        }
    }

    public static func requirePositiveInt(_ value: Int, max: Int, name: String) throws {
        guard value > 0, value <= max else {
            throw ValidationError("\(name) must be in 1...\(max), got \(value)")
        }
    }

    /// Reject NaN/±inf for a tonal lever whose range is otherwise clamped
    /// silently by `RenderingOptions`. A non-finite value would poison the
    /// downstream `simd_clamp`, so it is the one input worth rejecting up front.
    public static func requireFinite(_ value: Double, name: String) throws {
        guard value.isFinite else {
            throw ValidationError("\(name) must be a finite number, got \(value)")
        }
    }

    /// Reject non-finite or non-positive values for a knob that hits a hard
    /// `precondition` downstream (wave frequency, pulse period). Unlike the
    /// tonal levers these are NOT silently clamped, so a bad value would trap at
    /// render time instead of returning a usage error.
    public static func requirePositiveFinite(_ value: Double, name: String) throws {
        guard value.isFinite, value > 0 else {
            throw ValidationError("\(name) must be a finite positive number, got \(value)")
        }
    }

    /// Mirrors the legacy `ASTSK-14` provenance sanitizer: reject commas,
    /// double-quotes, and line breaks so the value is safe to record in CSV/YAML.
    public static func requireSafeGitSHA(_ value: String?) throws {
        guard let value else { return }
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            throw ValidationError("--aski-git-sha must not contain ',', '\"', or line breaks")
        }
    }
}
