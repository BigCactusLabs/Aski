import CoreGraphics

/// Errors thrown by the **async** overloads of `renderImage` / `renderCIImage`
/// and by `AskiRenderEngine`'s async render entry points. The **sync** overloads
/// never throw; they absorb these conditions via the documented fallback path
/// (metallib unavailable -> stock-CI fallback; degenerate output -> 1x1 transparent
/// image; unknown blend mode -> `CIBlendKernel.sourceOver`) and log via `os_log`.
public enum EffectError: Error, Sendable {
    case metallibUnavailable
    case unsupportedOnDevice(Effect)
    case degenerateOutput
    case unsupportedBlendMode(CGBlendMode)
}
