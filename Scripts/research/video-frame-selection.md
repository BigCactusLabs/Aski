# ASKI-93: select frames before paying for conversion

Groundwork against `4c675957547cb0dffdcce886a073bd2f340a5d26`, 2026-10-27.
This freezes the existing selection contract. It does not implement early
selection, measure a speedup, or establish native pixel parity.

## The boundary to preserve

[`convertVideo`](../../Sources/Aski/Video/ASCIIVideoConverter.swift) currently asks
`pipelinedGrids` to convert each source image, then applies
[`resampledVideoFrames`](../../Sources/Aski/Video/FrameResampler.swift). The generic
[`ResampleSession`](../../Sources/Aski/Video/ResampleSession.swift) chooses the last
frame assigned to each output slot, holds a frame across gaps, and retimes video
output to `CMTime(value: slot, timescale: targetFPS)`. Move the expensive conversion
after selection while retaining this policy; do not add a competing selector.

[`VideoFrameSelectionContractTests`](../../Tests/AskiTests/VideoFrameSelectionContractTests.swift)
feeds single-cell identity markers through the real public video operator and its
generic session. Its pull-based source records reads as well as returned frames.
The fixture expectations are literals, not outputs from a second selector.

| Fixture | Source frames supplied | Frames pulled by selector | Output | Dropped | Duplicated |
| --- | ---: | ---: | ---: | ---: | ---: |
| 60 → 12 fps, one second | 60 | 59 | 12 | 46 | 0 |
| 30 → 12 fps, one second | 30 | 30 | 12 | 17 | 0 |
| Variable rate: 0, 10, 60, 400, 410, 900 ms | 6 | 6 | 12 | 2 | 8 |
| 2 → 4 fps, 1.5 seconds | 3 | 3 | 6 | 0 | 3 |
| 12 → 12 fps, half a second | 6 | 6 | 6 | 0 | 0 |
| 20-second source origin, 30 → 12 fps | 6 | 6 | 3 | 3 | 0 |
| Exact half-slot ties | 5 | 5 | 4 | 0 | 0 |
| Last frame held to declared duration | 2 | 2 | 3 | 0 | 1 |
| One frame, declared duration zero | 1 | 1 | 1 | 0 | 0 |
| Empty source, declared duration one second | 0 | 0 | 0 | 0 | 0 |

These are expected contract values awaiting native execution. At 60 → 12, output
identities are `2, 7, 12, 17, 22, 27, 32, 37, 42, 47, 52, 57`. Identity 58 is pulled
as lookahead but never selected; identity 59 is never pulled by this session.
Consequently, `sourceFrameCount` is not the file's frame count, and
`droppedCount + distinct selected frames` need not equal it. The existing
[`VideoFramePrefetchPump`](../../Sources/Aski/Video/ASCIIVideoDecoder.swift) can also
pull one frame beyond the selector's requests. Instrument decoder, converter, and
selector counts separately; do not call this table a measurement of conversion
calls in the current export pipeline.

## First implementation slice

1. Add a private decode/selection seam for the one-shot `convertVideo` path with
   `targetFPS` set. Keep the existing no-resampling path as the control. Preserve
   the public `grids` and `pipelinedGrids` transform contract: arbitrary caller
   transforms still run on every frame those APIs yield.
2. Keep source identity separate from output time. Convert each newly selected
   source once, reuse its grid for duplicates, and continue to apply patterns in
   `RenderPump` at the retimed output timestamp. Cache only the held identity's
   grid, not a dictionary spanning the clip.
3. Resolve sample-buffer ownership explicitly before exposing a raw-frame
   carrier across actors. The current private `DecodeSession` confines
   `AVAssetReader` and `CVPixelBuffer` to its serial executor. Reuse the generic
   selection policy without asserting unchecked sendability to silence warnings.
4. Extend the existing native media fixtures with conversion-call counters and
   rotated/mirrored inputs. Compare selected identities, all four report counts,
   exact CFR timestamps, cells, and decoded/rendered pixels against the retained
   pipeline. The synthetic matrix contains no orientation or pixel evidence.
5. Retain cancellation and producer-error propagation plus the bounded prefetch
   checks in [`VideoPipelineTests`](../../Tests/AskiTests/VideoPipelineTests.swift).
   Count held source, lookahead, in-flight decode, and cached grid together;
   separate two-frame stages do not prove a two-frame total.

Use the existing serial media lane for native verification and paired release
measurements for adoption. Include 60/120 → 12, 30 → 12, VFR, unchanged rate,
upsampling, and rotated input; report wall time, CPU, allocations, and peak RSS.
Keep preparation/orientation changes from ASKI-1/2 out of the first comparison so
they do not obscure the effect of selection order. ASKI-93 remains open.

## Research constraints

- Apple's [`copyNextSampleBuffer`](https://developer.apple.com/documentation/avfoundation/avassetreaderoutput/copynextsamplebuffer())
  distinguishes decoded output from compressed sample output. Dropping ASCII
  work does not establish that interdependent codec frames can be skipped.
- The newer [`outputProvider(for:)`](https://developer.apple.com/documentation/avfoundation/avassetreader/outputprovider(for:))
  requires iOS/macOS 26. ASKI targets iOS 18/macOS 15; adopting that API is a
  separate availability and ownership decision, not required for early selection.
- [FFmpeg's `fps` filter](https://ffmpeg.org/ffmpeg-filters.html#fps) documents
  nearest-slot rounding and separately configurable end-of-file behavior. It is
  background for the existing policy, not a substitute oracle: ASKI's declared
  duration uses a ceiling and a one-slot floor, which these fixtures preserve.

## Verification status

The fixtures were reviewed against the current selector and their arithmetic was
cross-checked with a separate offline calculation. This environment has no Swift,
Xcode, or CoreMedia; the new Swift tests have **not** been compiled or executed.
On the recorded Mac toolchain, after the normal build:

```bash
xcrun swift test --skip-build --filter VideoFrameSelectionContractTests
```

Then run `just check` before accepting the change. A passing synthetic matrix
will establish the selection boundary only; it will not satisfy ASKI-93's native
integration or performance acceptance criteria.
