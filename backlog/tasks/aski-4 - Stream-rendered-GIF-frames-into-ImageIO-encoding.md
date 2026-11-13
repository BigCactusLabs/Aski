---
id: ASKI-4
title: Stream rendered GIF frames into ImageIO encoding
status: In Progress
assignee: []
created_date: 2026-08-18 18:01
updated_date: '2026-11-13T07:15:00Z'
labels:
  - performance
  - video
  - gif
  - memory
dependencies: []
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
- [ ] #6 just check and just bench pass without loosening an existing benchmark threshold.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Preserve batch API and metadata while introducing a package-confined transactional incremental GIF session with an exact expected count. 2. Feed converter and lab rendering directly from pull-based decode/resample streams; derive capped duration from metadata and share existing preflight count. 3. Add parity, bounded-pull, failure and cancellation regression coverage and a frozen RSS measurement protocol. 4. Run portable checks now; defer all native builds, media tests, full gates and memory/time captures until lead assigns the host.

Source refinement r2: add successful replacement and actual decoder-open failure coverage; freeze base-unit memory exports and numeric protocol; add opt-in immutable bitmap provider-release observations without asserting a memory bound. Native execution remains deferred.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `ASCIIGIFDecoder.grids(fromGIFAt:transform:)` is already pull based: `GIFDecodeSession.next()` opens one `CGImageSource` frame, reads its unclamped delay, transforms it, and yields one `ASCIIGIFFrame`. ImageIO is currently relied on for composed full-canvas placement and disposal, and the decoder tests are the regression sentinel for that behavior. The encode seam is the opposite shape. `ASCIIGIFEncoder.write` accepts `[RenderedGIFFrame]`, creates an ImageIO destination with the array count, adds every image, finalizes once, and returns `GIFEncodeReport`. `convertGIF` appends every rendered image to `rendered` before calling it. The GIF branch of `AskiVideoLab` also accumulates rendered frames and delays; target-FPS mode additionally accumulates source frames before resampling. The dated 2026-06-03 research note records about 34.5 MB peak footprint for a 13-frame batch run and explicitly says batch memory scales with frame count times rendered size.

Start here: Read `Sources/Aski/Video/ASCIIGIFEncoder.swift`, `ASCIIGIFConverter.swift`, `ASCIIGIFTypes.swift`, and `ASCIIGIFDecoder.swift` together. Use `ASCIIVideoEncoder.write<S: AsyncSequence & Sendable>` and its actor-confined `EncodeSession` as an existing streaming/backpressure reference. Then inspect `Tests/AskiTests/AskiGIFConverterTests.swift`, `AskiGIFEncoderTests.swift`, `AskiGIFDecoderTests.swift`, `AskiResampleGIFTests.swift`, and the GIF branch of `Tools/AskiVideoLab/VideoLabCLI.swift`.

Constraints and dependencies: Preserve the public `convertGIF` behavior and source compatibility unless a deliberate breaking change is justified. The streaming path must retain frame order, canvas dimensions, alpha/color behavior, unclamped per-frame delays, loop metadata, and the existing maximum-frame guard. Target-FPS mode has a separate `containerInfo` delay scan and resampler; it must not accidentally reintroduce a whole rendered-frame collection. Producer, renderer, destination, cancellation, and finalize failures must stop cleanly without reporting success or exposing a finalized partial result. The lab already writes through a temporary URL and replaces the final output only after success; `convertGIF` currently passes its final URL directly, so failure and output-atomicity behavior needs explicit review. Do not add a dependency or weaken the strict Swift 6 contract.

Validation to run: Add focused regression coverage for one-at-a-time production, metadata/order/delay preservation, alpha and color fixtures, producer or render failure, destination/finalize failure, cancellation, and a long animation whose measured footprint is bounded by a small frame window. Use the existing `GIF89aFixture` and `ImageSink` helpers where applicable. Run the serial media gate from `justfile` (`ASKI_SKIP_BUILD=1 ASKI_SERIAL_MEDIA=1 just test-media` after the normal build), then `just check` and `just bench`; these checks were not run during this extraction.

First step: enumerate every `ASCIIGIFEncoder.write` call site and decide how the streaming contract coexists with the current batch API under AC#5. Trace the output transaction and failure paths before changing the producer/encoder seam.

Source map: `Sources/Aski/Video/ASCIIGIFConverter.swift`, `Sources/Aski/Video/ASCIIGIFDecoder.swift`, `Sources/Aski/Video/ASCIIVideoEncoder.swift`, `docs/Research/2026-06-03-gif-lab-roundtrip-fidelity.md`.

Source checkpoint prepared: package-confined incremental session, exact shared resample count, transactional output and package decoder cap; public signatures unchanged. Added retained-control byte parity, incomplete/excess count, abandonment cleanup, cancellation, destination failure and decoder-cap coverage, plus an isolated render/encode RSS benchmark matrix. Formatting and diff checks pass. Native compilation, media tests, full gates, and retained-image/RSS evidence are explicitly pending host assignment; no acceptance criteria checked.

Source refinement r2 adds successful existing-output replacement with content/metadata/temp cleanup checks and a real malformed-source decoder-open failure. Added opt-in provider-release JSON fixture for 24/240/1200 fresh immutable bitmap payloads in retained/incremental modes; no bounded-memory assertion. Benchmark units explicitly use the pinned API count scale for allocation counts and resident bytes. Numeric protocol frozen under Scripts/research/aski4-2026-11-13. Native execution still deferred. ImageIO finalize-false and mid-stream corrupt-LZW branches are not claimed as reproduced.

Native repair r3: reproduced owned ImageIO sidecar leak with actual directory listings; explicit destination release did not remove it. A unique owned staging directory now contains output and ImageIO sidecars, is cleaned on abandonment and before successful finish returns, and stays on the destination filesystem. No prefix scan or production injection seam. Malformed producer test accepts cannotOpenSource or noFrames; this native ImageIO reports noFrames. All 65 affected tests passed, then canonical just check passed: 1537 core, 186 media, 2 sentinels plus drift/DocC. Full-gate source snapshot unchanged. Provider/RSS/performance captures remain deferred; no completion or AC4 claim.

Lead accepted the focused repair after native reproduction showed ImageIO-owned sidecars survive deletion of the requested temp URL. Each encode now owns one sibling staging directory; public signatures remain unchanged. All 65 affected tests and full just check passed (1537 core, 186 media, two sentinels, DocC). Byte/metadata parity, producer rejection, cancellation and output replacement/cleanup regressions pass. The exact ImageIO-finalize-false branch was inspected but not fault-injected. AC4 and full benchmark acceptance remain open; no bounded-memory or speed claim is made before the committed protocol runs.
<!-- SECTION:NOTES:END -->
