# Video & GIF

Convert MP4 clips and animated GIFs to ASCII and re-encode them, streaming every stage.

## Overview

Aski's video layer decodes a clip frame by frame, converts each frame to an ``ASCIIGrid`` with an ``ASCIIConverter``, renders the grid to an image, and encodes the result — all as a streaming pipeline, so memory stays bounded regardless of clip length. Two one-shot carriers wrap the whole round-trip; the decoder and encoder halves are also exposed for custom pipelines.

The converter's generic parameters (`<C, P>`) are confined to the one-shot functions — the decode and encode halves never carry them.

## One-shot round-trips

``convertVideo(at:to:using:columns:font:backgroundColor:scale:export:targetFPS:pattern:effects:)`` decodes an MP4, converts and renders each frame, and encodes a new MP4. ``convertGIF(at:to:using:columns:font:backgroundColor:scale:loopCount:targetFPS:maximumFrameCount:)`` does the same for animated GIFs.

```swift
import Aski

let report = try await convertVideo(
    at: sourceURL,
    to: outputURL,
    using: DefaultConverter(),
    columns: 80,
    font: bundledFont,           // an ASCIIFont
    backgroundColor: .black,
    scale: 12
)
```

`targetFPS` resamples to a constant frame rate; omit it to preserve the source cadence. For GIFs, `loopCount: nil` preserves the source's reported loop value (once stays once, infinite stays infinite), and `maximumFrameCount` (default 10,000) rejects oversized inputs before any decode work.

## Streaming building blocks

For finer control, compose the halves directly:

- ``ASCIIVideoDecoder`` / ``ASCIIGIFDecoder`` — stream source frames as ``ASCIIGrid`` values through a `transform` closure; also report duration, frame rate, and GIF container metadata (``GIFContainerInfo``).
- ``ASCIIVideoEncoder`` / ``ASCIIGIFEncoder`` — encode rendered frames back to MP4/GIF; the GIF encoder returns a ``GIFEncodeReport``.
- Frame payloads — ``ASCIIVideoFrame`` / ``ASCIIGIFFrame`` carry a grid plus timing; ``RenderedVideoFrame`` / ``RenderedGIFFrame`` carry the rendered image plus timing.
- Configuration and reports — ``VideoExportOptions`` / ``VideoCodec`` configure the MP4 encode; ``ResampleReport`` describes frame-rate resampling.

``ASCIIVideoDecoder/grids(fromVideoAt:transform:)`` remains strictly pull-based:
each consumer request decodes one frame. For a custom streaming export that can
benefit from bounded overlap, use
``ASCIIVideoDecoder/pipelinedGrids(fromVideoAt:transform:)``. It prefetches exactly
one ordered frame while the consumer handles the current frame. The one-shot
`convertVideo` carrier uses this sibling path automatically.

## Per-frame effects and overlays

`convertVideo` accepts two optional animation inputs:

- `pattern:` — an ``OngoingPattern`` whose phase is driven by each frame's presentation time and applied via ``ASCIIGrid/applyingOngoingPattern(_:at:)``. Use it to animate brightness or coverage coherently across frames. See <doc:Animation>.
- `effects:` — a **time-invariant** ``EffectChain`` (e.g. `bloom`, `scanLines`, `vignette`) applied to every rendered frame. Per-frame stochastic effects are deliberately omitted because reseeding each frame flickers. See *Applying effects per frame (video)* in <doc:Effects>.

Both default to no-ops, so omitting them leaves output byte-identical to the plain decode → convert → encode path.
