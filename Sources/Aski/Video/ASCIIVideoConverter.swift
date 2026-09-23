import CoreGraphics
import CoreMedia
import Foundation

/// One-shot clip → ASCII-video convenience: decode → convert → render → encode,
/// every stage streaming. Generics are confined to this function — the Video
/// halves never carry the converter's `<C, P>` parameters.
@discardableResult
public func convertVideo<C, P>(
    at source: URL,
    to output: URL,
    using converter: ASCIIConverter<C, P>,
    columns: Int,
    font: ASCIIFont,
    backgroundColor: CGColor,
    scale: CGFloat,
    export: VideoExportOptions = VideoExportOptions(),
    targetFPS: Int? = nil,
    pattern: OngoingPattern? = nil,
    effects: EffectChain = .init()
) async throws -> ResampleReport? {
    // One caller pattern is threaded into every frame, so an unevaluable one is
    // rejected here rather than part-way through an export (ASKI-18).
    pattern?.validate()
    let decoder = ASCIIVideoDecoder()
    let decodeStream = decoder.pipelinedGrids(
        fromVideoAt: source,
        transform: { converter.convert($0, columns: columns) }
    )

    let framesToRender: AsyncThrowingStream<ASCIIVideoFrame, Error>
    let stats: ResampleStats?
    var exportOptions = export
    if let targetFPS {
        let sourceDuration = try await decoder.sourceDuration(ofVideoAt: source)
        let resampleStats = ResampleStats()
        framesToRender = try resampledVideoFrames(
            decodeStream, targetFPS: targetFPS, sourceDuration: sourceDuration, into: resampleStats
        )
        stats = resampleStats
        exportOptions.expectedFrameRate = targetFPS  // CFR rate-control hint (Task 5b)
    } else {
        framesToRender = decodeStream
        stats = nil
    }

    let pump = RenderPump(
        stream: framesToRender,
        font: font,
        backgroundColor: backgroundColor,
        scale: scale,
        pattern: pattern,
        effects: effects
    )
    let renderedStream = AsyncThrowingStream(unfolding: {
        try await pump.next()
    })
    try await ASCIIVideoEncoder().write(renderedStream, to: output, options: exportOptions)

    guard let targetFPS, let stats else { return nil }
    return ResampleReport(
        requestedFPS: targetFPS,
        achievedFPS: Double(targetFPS),
        sourceFrameCount: await stats.sourceFrameCount,
        outputFrameCount: await stats.outputFrameCount,
        droppedCount: await stats.droppedCount,
        duplicatedCount: await stats.duplicatedCount
    )
}

/// Bridges decode → render. The render parameters (`CGColor`, `ASCIIFont`,
/// `CGFloat`) live as actor-isolated state, so the non-Sendable `CGColor` never
/// crosses a `Sendable` boundary — the only `@Sendable` closure that captures
/// the pump captures the actor reference alone. Pull-based: one render per call.
private actor RenderPump {
    private var iterator: AsyncThrowingStream<ASCIIVideoFrame, Error>.AsyncIterator
    private let font: ASCIIFont
    private let backgroundColor: CGColor
    private let scale: CGFloat
    private let pattern: OngoingPattern?
    private let effects: EffectChain

    init(
        stream: AsyncThrowingStream<ASCIIVideoFrame, Error>,
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        pattern: OngoingPattern? = nil,
        effects: EffectChain = .init()
    ) {
        self.iterator = stream.makeAsyncIterator()
        self.font = font
        self.backgroundColor = backgroundColor
        self.scale = scale
        self.pattern = pattern
        self.effects = effects
    }

    func next() async throws -> RenderedVideoFrame? {
        // Swift 6.3 rejects calling the mutating async `next()` directly on the
        // actor-isolated stored `iterator` ("cannot call mutating async function
        // on actor-isolated property"). Copy to a local, advance it, write back.
        // The advance uses `next(isolation: #isolation)` so the non-Sendable
        // iterator stays pinned to this actor across the suspension — without it,
        // the plain `next()` trips `sending 'localIterator' risks data races`.
        // The actor serializes calls and the unfolding consumer pulls one at a
        // time, so no concurrent pull races the copy.
        var localIterator = iterator
        let frame = try await localIterator.next(isolation: #isolation)
        iterator = localIterator
        guard let frame else { return nil }
        return render(frame)
    }

    /// Synchronous render. With an empty chain it calls the plain
    /// `renderImage(font:backgroundColor:scale:) -> CGImage` directly — staying off
    /// the CIImage effects pipeline so a no-effects run is byte-identical to before
    /// and carries no overhead. With a non-empty chain it calls the synchronous
    /// `effects:` overload (the sync context rules out the `async throws` variant).
    /// Effects are time-invariant, so no per-frame time is threaded (unlike pattern).
    private func render(_ frame: ASCIIVideoFrame) -> RenderedVideoFrame {
        let patterned = frame.applyingOngoingPattern(pattern)
        let grid = patterned.grid
        let image: CGImage
        if effects.effects.isEmpty {
            image = grid.renderImage(font: font, backgroundColor: backgroundColor, scale: scale)
        } else {
            image = grid.renderImage(font: font, backgroundColor: backgroundColor, scale: scale, effects: effects)
        }
        return RenderedVideoFrame(image: image, time: patterned.time)
    }
}
