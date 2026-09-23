/// Output video codec. `.h264` is the default for broad compatibility; `.hevc`
/// is an opt-in (no HEVC-specific bitrate/profile tuning in C2a).
public enum VideoCodec: Sendable {
    case h264
    case hevc
}

/// Options for `ASCIIVideoEncoder` / `convertVideo`. Output pixel dimensions are
/// derived from the first rendered frame and normalized to even values inside
/// the encoder (see `ASCIIVideoEncoder`), so they are not configured here.
public struct VideoExportOptions: Sendable {
    public var codec: VideoCodec
    /// fps rate-control HINT for the encoder when resampling to CFR. `nil` (the
    /// default) leaves encoder settings byte-identical to the non-resampled path.
    /// The actual output timing comes from the per-frame `CMTime` PTS stamps; this
    /// only helps the encoder's rate control.
    public var expectedFrameRate: Int?

    public init(codec: VideoCodec = .h264, expectedFrameRate: Int? = nil) {
        self.codec = codec
        self.expectedFrameRate = expectedFrameRate
    }
}
