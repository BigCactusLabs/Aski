---
id: ASKI-4
title: Stream rendered GIF frames into ImageIO encoding
status: In Progress
assignee: []
created_date: 2026-08-18 18:01
updated_date: '2026-11-13T09:27:00Z'
labels:
  - performance
  - video
  - gif
  - memory
dependencies: []
documentation:
  - Scripts/research/aski4-2026-11-13/README.md
priority: medium
type: enhancement
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASCIIGIFConverter currently retains all rendered frames before ASCIIGIFEncoder writes them. Change the conversion and encoding contract so completed frames can be added to the ImageIO destination incrementally, reducing peak memory for long or high-resolution animations while preserving deterministic output metadata and order.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GIF conversion can render and add frames to the destination incrementally without retaining the full rendered-frame sequence in memory.
- [x] #2 Frame count, frame order, per-frame delay, loop count, canvas size, alpha handling, and color behavior match the current encoder for representative fixtures.
- [x] #3 Producer, renderer, and destination failures stop the operation cleanly and do not report a successful finalized GIF.
- [ ] #4 A long-animation benchmark or test demonstrates that peak resident memory is bounded by a small number of frames rather than increasing linearly with total frame count.
- [x] #5 Existing public GIF conversion behavior remains source compatible unless a deliberate source-breaking change is documented as materially simpler for consumers.
- [x] #6 just check and just bench pass without loosening an existing benchmark threshold.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `ASCIIGIFDecoder.grids(fromGIFAt:transform:)` is already pull based: `GIFDecodeSession.next()` opens one `CGImageSource` frame, reads its unclamped delay, transforms it, and yields one `ASCIIGIFFrame`. ImageIO is currently relied on for composed full-canvas placement and disposal, and the decoder tests are the regression sentinel for that behavior. The encode seam is the opposite shape. `ASCIIGIFEncoder.write` accepts `[RenderedGIFFrame]`, creates an ImageIO destination with the array count, adds every image, finalizes once, and returns `GIFEncodeReport`. `convertGIF` appends every rendered image to `rendered` before calling it. The GIF branch of `AskiVideoLab` also accumulates rendered frames and delays; target-FPS mode additionally accumulates source frames before resampling. The dated 2026-06-03 research note records about 34.5 MB peak footprint for a 13-frame batch run and explicitly says batch memory scales with frame count times rendered size.

Start here: Read `Sources/Aski/Video/ASCIIGIFEncoder.swift`, `ASCIIGIFConverter.swift`, `ASCIIGIFTypes.swift`, and `ASCIIGIFDecoder.swift` together. Use `ASCIIVideoEncoder.write<S: AsyncSequence & Sendable>` and its actor-confined `EncodeSession` as an existing streaming/backpressure reference. Then inspect `Tests/AskiTests/AskiGIFConverterTests.swift`, `AskiGIFEncoderTests.swift`, `AskiGIFDecoderTests.swift`, `AskiResampleGIFTests.swift`, and the GIF branch of `Tools/AskiVideoLab/VideoLabCLI.swift`.

Constraints and dependencies: Preserve the public `convertGIF` behavior and source compatibility unless a deliberate breaking change is justified. The streaming path must retain frame order, canvas dimensions, alpha/color behavior, unclamped per-frame delays, loop metadata, and the existing maximum-frame guard. Target-FPS mode has a separate `containerInfo` delay scan and resampler; it must not accidentally reintroduce a whole rendered-frame collection. Producer, renderer, destination, cancellation, and finalize failures must stop cleanly without reporting success or exposing a finalized partial result. The lab already writes through a temporary URL and replaces the final output only after success; `convertGIF` currently passes its final URL directly, so failure and output-atomicity behavior needs explicit review. Do not add a dependency or weaken the strict Swift 6 contract.

Validation to run: Add focused regression coverage for one-at-a-time production, metadata/order/delay preservation, alpha and color fixtures, producer or render failure, destination/finalize failure, cancellation, and a long animation whose measured footprint is bounded by a small frame window. Use the existing `GIF89aFixture` and `ImageSink` helpers where applicable. Run the serial media gate from `justfile` (`ASKI_SKIP_BUILD=1 ASKI_SERIAL_MEDIA=1 just test-media` after the normal build), then `just check` and `just bench`; these checks were not run during this extraction.

First step: enumerate every `ASCIIGIFEncoder.write` call site and decide how the streaming contract coexists with the current batch API under AC#5. Trace the output transaction and failure paths before changing the producer/encoder seam.

Source map: `Sources/Aski/Video/ASCIIGIFConverter.swift`, `Sources/Aski/Video/ASCIIGIFDecoder.swift`, `Sources/Aski/Video/ASCIIVideoEncoder.swift`, `docs/Research/2026-06-03-gif-lab-roundtrip-fidelity.md`.

2026-11-13: a source-compatible incremental-append candidate passes the full correctness gate, but its independent provider fixture shows ImageIO retaining all original bitmaps until finalize at 24, 240 and 1200 frames. This fails the frozen bounded-lifetime requirement; removing application arrays is insufficient. Registered process-RSS and real-pipeline measurements remain in progress. No candidate source is adopted. The experiment and evidence are retained under Scripts/research/aski4-2026-11-13.

All 30 registered primary captures now completed validly with no replacement or retry. Incremental median sampled RSS grows from 332,136,447 bytes at 240 frames to 1,560,281,087 at 1200: a 1,228,144,640-byte increase versus the frozen 16,777,216-byte allowance. The retained control also grows strongly. Together with N live original providers before finalize, this rejects the candidate under both independent memory requirements. Portable raw evidence and reproduction are saved; no treatment is integrated.

Verification complete for the rejected candidate: 65 affected tests and full just check passed (1537 core, 186 media, 2 sentinels, DocC); all 10 actual pipeline cases passed metadata checks; just bench produced valid evidence for all 239 workloads. The corrected canonical absolute check passed all 11 unchanged configured budgets after preserving one setup failure. AC 2/3/5/6 record these candidate contracts and gates, not adoption. AC 1/4 remain unmet. ImageIO finalize-false was inspected, not fault-injected. The full portable primary packet, supplemental source/data and native provenance are retained in the linked README; no GIF production code is integrated.
<!-- SECTION:NOTES:END -->
