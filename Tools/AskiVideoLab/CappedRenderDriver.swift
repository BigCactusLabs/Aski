import Aski
import CoreGraphics
import CoreMedia
import Foundation

/// Drives the composable halves directly for the `--max-frames` path: pulls at
/// most `limit` frames from the decode stream, renders each, and counts what it
/// produced. Render params live as actor-isolated state (no `CGColor` Sendable
/// boundary). Peak memory is tracked separately by `PeakMemoryTracker` (a
/// per-frame sample here would miss the render/encode spike), so this driver
/// does no memory sampling.
actor CappedRenderDriver {
    private var iterator: AsyncThrowingStream<ASCIIVideoFrame, Error>.AsyncIterator
    private let font: ASCIIFont
    private let backgroundColor: CGColor
    private let scale: CGFloat
    private let pattern: OngoingPattern?
    private let effects: EffectChain
    private var remaining: Int
    private(set) var producedCount = 0

    init(
        stream: AsyncThrowingStream<ASCIIVideoFrame, Error>,
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        limit: Int,
        pattern: OngoingPattern? = nil,
        effects: EffectChain = .init()
    ) {
        self.iterator = stream.makeAsyncIterator()
        self.font = font
        self.backgroundColor = backgroundColor
        self.scale = scale
        self.pattern = pattern
        self.effects = effects
        self.remaining = limit
    }

    func next() async throws -> RenderedVideoFrame? {
        guard remaining > 0 else { return nil }
        // Copy/advance/write-back: Swift 6.3 rejects the mutating async `next()`
        // called directly on the actor-isolated stored `iterator`. The
        // `isolation: #isolation` argument keeps the non-Sendable iterator pinned
        // to this actor across the await (plain `next()` trips 'sending').
        var localIterator = iterator
        let frame = try await localIterator.next(isolation: #isolation)
        iterator = localIterator
        guard let frame else { return nil }
        remaining -= 1
        producedCount += 1
        return render(frame)
    }

    func count() -> Int { producedCount }

    /// Synchronous render. An empty chain calls the plain
    /// `renderImage(font:backgroundColor:scale:) -> CGImage` directly (byte-identical
    /// to before, no CIImage pipeline); a non-empty chain calls the synchronous
    /// `effects:` overload (the sync context rules out the async-throws variant).
    /// Effects are time-invariant — no per-frame time is threaded (unlike pattern).
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
