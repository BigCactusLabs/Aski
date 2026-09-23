import CoreGraphics
import Foundation

/// One-shot GIF -> ASCII-GIF convenience: decode (streaming) -> convert -> render
/// -> batch-encode. Generics are confined to this function — the GIF halves never
/// carry the converter's `<C, P>` parameters.
///
/// `loopCount: nil` PRESERVES the source's reported loop value (1 = once stays
/// once, 0 = infinite stays infinite, N = finite stays finite). It never
/// synthesizes a default of 0 (addendum §Timing & loop fidelity).
///
/// The one-shot rejects sources above `maximumFrameCount` before delay scanning,
/// decoding, or rendering frames. The default limit is 10,000 frames; pass a
/// larger explicit limit only for intentionally oversized inputs.
@discardableResult
public func convertGIF<C, P>(
    at source: URL,
    to output: URL,
    using converter: ASCIIConverter<C, P>,
    columns: Int,
    font: ASCIIFont,
    backgroundColor: CGColor,
    scale: CGFloat,
    loopCount: Int? = nil,
    targetFPS: Int? = nil,
    maximumFrameCount: Int = 10_000
) async throws -> GIFEncodeReport {
    let decoder = ASCIIGIFDecoder()
    let header = try decoder.containerHeader(ofGIFAt: source)
    if maximumFrameCount <= 0 || header.frameCount > maximumFrameCount {
        throw GIFDecodeError.frameCountExceedsLimit(
            count: header.frameCount,
            limit: maximumFrameCount
        )
    }
    let resolvedLoop = loopCount ?? header.loopCount

    let stream = decoder.grids(
        fromGIFAt: source,
        transform: { converter.convert($0, columns: columns) }
    )

    var rendered: [RenderedGIFFrame] = []
    var resampleReport: ResampleReport?
    if let targetFPS {
        let info = try decoder.containerInfo(ofGIFAt: source)
        let stats = ResampleStats()
        let resampled = try resampledGIFFrames(
            stream, targetFPS: targetFPS, sourceDuration: info.totalDuration, into: stats
        )
        for try await frame in resampled {
            rendered.append(renderGIFFrame(frame, font: font, backgroundColor: backgroundColor, scale: scale))
        }
        resampleReport = ResampleReport(
            requestedFPS: targetFPS,
            achievedFPS: gifAchievedFPS(targetFPS: targetFPS),
            sourceFrameCount: await stats.sourceFrameCount,
            outputFrameCount: await stats.outputFrameCount,
            droppedCount: await stats.droppedCount,
            duplicatedCount: await stats.duplicatedCount
        )
    } else {
        for try await frame in stream {
            rendered.append(renderGIFFrame(frame, font: font, backgroundColor: backgroundColor, scale: scale))
        }
    }

    let base = try ASCIIGIFEncoder().write(rendered, loopCount: resolvedLoop, to: output)
    return GIFEncodeReport(
        framesWritten: base.framesWritten,
        loopCount: base.loopCount,
        subFloorDelayCount: base.subFloorDelayCount,
        minDelay: base.minDelay,
        resample: resampleReport
    )
}

/// Synchronous render so overload resolution selects `ASCIIGrid`'s plain
/// `renderImage(font:backgroundColor:scale:) -> CGImage` rather than the
/// `async throws` effects overload (preferred in an async context). The
/// non-`Sendable` `CGColor` stays inside this nonisolated function — no `@Sendable`
/// closure captures it (the decode `transform` captures only `converter`/`columns`)
/// — so this is `Sendable`-clean WITHOUT an actor, because export is batch (not the
/// streaming encoder `convertVideo` feeds, which is why C2a needed `RenderPump`).
private func renderGIFFrame(
    _ frame: ASCIIGIFFrame,
    font: ASCIIFont,
    backgroundColor: CGColor,
    scale: CGFloat
) -> RenderedGIFFrame {
    let image = frame.grid.renderImage(font: font, backgroundColor: backgroundColor, scale: scale)
    return RenderedGIFFrame(image: image, delay: frame.delay)
}
