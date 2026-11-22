# Video & GIF

Convert MP4 clips and animated GIFs to ASCII, preserving timing and choosing an export path.

## Overview

Aski decodes source frames, converts them to ``ASCIIGrid`` values, renders them, and
encodes the result. The MP4 path streams through bounded frame queues. GIF decoding
is frame-by-frame, but ``convertGIF(at:to:using:columns:font:backgroundColor:scale:loopCount:targetFPS:maximumFrameCount:)``
collects rendered images before batch encoding; its memory use grows with output
frame count and image size. The decoder and encoder halves are also exposed for
custom pipelines.

The converter's generic parameters (`<C, P>`) are confined to the one-shot functions — the decode and encode halves never carry them.

## One-shot round-trips

``convertVideo(at:to:using:columns:font:backgroundColor:scale:export:targetFPS:pattern:effects:)``
exports MP4 through the streaming path. The GIF counterpart returns a
``GIFEncodeReport`` after its batch write.

```swift
import Aski
import CoreGraphics

// sourceURL and outputURL are file URLs supplied by the caller.
let report = try await convertVideo(
    at: sourceURL,
    to: outputURL,
    using: DefaultConverter(),
    columns: 80,
    font: .courierPrime(size: 12),
    backgroundColor: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
    scale: 2
)
```

`targetFPS` resamples to a constant frame rate; omit it to preserve source cadence.
For MP4, resampling selects decoded source identities before ASCII conversion and
reuses a converted grid for duplicate output slots. Source decoding still occurs.
Without `targetFPS`, each decoded source frame is converted through the original
prefetch path. A video export returns a ``ResampleReport`` only when resampling is
requested.

For GIFs, `loopCount: nil` preserves the source's reported loop value (once stays once,
infinite stays infinite). `maximumFrameCount` defaults to 10,000 and rejects larger
source frame counts before delay scanning, frame decoding, or rendering. The limit
counts input frames; upsampling can produce more output frames. GIF resampling still
operates after source-frame conversion, and its report is attached to
``GIFEncodeReport``.

The GIF encoder accepts `loopCount` in `0...32767`: `0` means infinite playback,
`1` means play once, and `2...32767` gives the total number of plays. These values
round-trip through ImageIO for both one-frame and multi-frame GIFs on the recorded
toolchain. The raw Netscape extension stores one fewer repeat for finite playback;
an absent extension means play once. Values outside the supported range throw
``GIFEncodeError/invalidLoopCount(_:)`` before the encoder creates or changes the
destination. There is no clamping. ``GIFEncodeReport/loopCount`` reports the value
decoded from the finalized output. A source loop count outside this encoding
range also needs a valid explicit override when using `convertGIF`.
The video lab preserves source loops and rejects an out-of-range source; it does
not offer a loop-count override.

## MP4 color

The MP4 encoder keeps the grid's gamut and tags the track to match. The first
frame's color space picks the gamut: Display P3 (including the linear variant
rendered under ``RenderCompositionPolicy/extendedLinearPerGamut``) encodes as P3;
sRGB, any other color space, and untagged images encode as sRGB. Frames are drawn
in that gamut's encoded, non-linear space, and both the pixel buffers and the
H.264 or HEVC track carry this triple:

| Gamut | Color primaries | Transfer function | Y'CbCr matrix |
|---|---|---|---|
| sRGB | ITU-R BT.709 | IEC 61966-2-1 (sRGB) | ITU-R BT.709 |
| Display P3 | P3 D65 | IEC 61966-2-1 (sRGB) | ITU-R BT.709 |

The encoder writes video (limited) range. A decoder that honors the tags
reproduces the rendered colors; a P3 export is not clipped to sRGB.

## Streaming building blocks

For finer control, compose the halves directly:

- ``ASCIIVideoDecoder`` / ``ASCIIGIFDecoder`` — stream source frames as ``ASCIIGrid`` values through a `transform` closure; also report duration, frame rate, and GIF container metadata (``GIFContainerInfo``).
- ``ASCIIVideoEncoder`` streams rendered MP4 frames; ``ASCIIGIFEncoder`` accepts an array of rendered GIF frames and returns a ``GIFEncodeReport``.
- Frame payloads — ``ASCIIVideoFrame`` / ``ASCIIGIFFrame`` carry a grid plus timing; ``RenderedVideoFrame`` / ``RenderedGIFFrame`` carry the rendered image plus timing.
- Configuration and reports — ``VideoExportOptions`` / ``VideoCodec`` configure the MP4 encode; ``ResampleReport`` describes frame-rate resampling.

``ASCIIVideoDecoder/grids(fromVideoAt:transform:)`` remains strictly pull-based:
each consumer request decodes one frame. For a custom streaming export that can
benefit from bounded overlap, use
``ASCIIVideoDecoder/pipelinedGrids(fromVideoAt:transform:)``. It prefetches exactly
one ordered frame while the consumer handles the current frame. The one-shot
`convertVideo` carrier uses this path when `targetFPS` is omitted. Its internal
resampling path selects frames first and then uses the same bounded prefetch; the
public decoder callback contracts remain unchanged.

## Per-frame effects and overlays

`convertVideo` accepts two optional animation inputs:

- `pattern:` — an ``OngoingPattern`` whose phase is driven by each frame's presentation time and applied via ``ASCIIGrid/applyingOngoingPattern(_:at:)``. It modulates cell alpha while preserving glyphs, colors, brightness, and mask coverage. See <doc:Animation>.
- `effects:` — the same ``EffectChain`` applied to every rendered frame. The library accepts the full chain; the `aski lab video` CLI exposes only `bloom`, `scanLines`, and `vignette`. No per-frame time or seed is generated for the chain. See *Applying effects per frame (video)* in <doc:Effects>.

Both default to no-ops, so omitting them leaves output byte-identical to the plain decode → convert → encode path.
