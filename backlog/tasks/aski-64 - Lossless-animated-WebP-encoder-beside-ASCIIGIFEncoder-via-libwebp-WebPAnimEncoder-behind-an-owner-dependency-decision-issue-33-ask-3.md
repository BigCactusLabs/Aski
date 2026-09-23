---
id: ASKI-64
title: >-
  Lossless animated WebP encoder beside ASCIIGIFEncoder via libwebp
  WebPAnimEncoder, behind an owner dependency decision (issue #33, ask 3)
status: To Do
assignee: []
created_date: '2026-09-01 22:16'
updated_date: '2026-09-10 04:15'
labels:
  - video
  - animation
  - research
dependencies: []
priority: medium
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From GitHub issue #33 and the research note docs/Research/2026-09-01-issue33-target-size-render-and-lossless-webp.md. A web consumer measured lossless animated WebP at 18 to 71 percent fewer bytes than the ASCIIGIFEncoder GIF at identical pixels, with lossy WebP worse on glyph edges. The note establishes that ImageIO cannot write WebP on macOS 26.6.2 or the iOS 26.5 simulator (no destination UTI, CGImageDestinationCreateWithURL returns nil, the kCGImagePropertyWebP keys are decode-side only), cannot write multi-frame AVIF, and its APNG writer produced 14.3 MB where the consumer's libwebp WebP is 2.49 MB and the GIF 3.04 MB. The only route is libwebp itself, which would be the first third-party dependency of the Aski library. Recommended shape: a separate product (AskiWebP or similar) depending on SDWebImage/libwebp-Xcode 1.6.0 (SwiftPM, C target, ships mux.h, released 2026-07-31), exposing a thin encoder type that mirrors ASCIIGIFEncoder and drives WebPAnimEncoder, not WebPMux keyframes (measured about 40 percent larger). Core Aski stays dependency-free. Incidental: ImageIO GIF cannot store 1/12 s (writes 0.08 s), which the GIF encoder docs should state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Owner decision recorded in the task notes before any code: whether a libwebp C dependency is acceptable, and whether it lives in a separate product so the Aski library target stays dependency-free (recommended) or in the library itself. If refused, the task closes with APNG documented as the zero-dependency lossless fallback and its measured size penalty stated.
- [ ] #2 An encoder type mirroring ASCIIGIFEncoder (frames with per-frame delays, loop count, output URL, a report struct) writes lossless animated WebP through WebPAnimEncoder with lossless=1; strict Swift 6 concurrency, warning-free, builds for macOS, iOS simulator and visionOS simulator.
- [ ] #3 Losslessness proven by two oracles in tests: webpinfo (or the libwebp demux API) reports lossless for every frame, and ImageIO decode of the output is byte-identical to the input CGImages (max channel delta 0); frame delays round-trip to the millisecond.
- [ ] #4 Size gate on the consumer's real 17-frame 1166x777 canyon corpus: output within 5 percent of the img2webp -lossless -m 6 reference (2,493,752 bytes) and smaller than the GIF (3,035,750 bytes); numbers recorded in a verdict note with the results dir committed.
- [ ] #5 AskiMotionLab and AskiVideoLab gain a format switch (gif|webp) on their animated export so the labs can emit both; the aski product command is unchanged unless the owner asks.
- [ ] #6 ASCIIGIFEncoder DocC states the GIF centisecond delay quantization (1/12 s stored as 0.08 s) as a known limitation, and docs/architecture.md names the new product and its dependency boundary.
- [ ] #7 libwebp specifics carried as tests: WebPConfig.exact = 1 so RGB under alpha-zero pixels survives (Aski renders with --background clear), frames wider or taller than 16383 px are rejected with a typed error rather than passed to the encoder, and the dependency's manifest lacks a visionOS platform entry so the visionOS build in the previous criterion is the proof, not the manifest.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: There is no WebP encoder product or type in the current package. `ASCIIGIFEncoder` is the closest model: it consumes `RenderedGIFFrame` values with per-frame delays, loop count, URL, and a pure-data report. The `Aski` target currently has no third-party runtime dependencies; `Package.swift` lists external packages for tests, benchmarks, and tool targets. ASKI-63 is already Done and ships `ASCIIGrid.renderImage(... targetPixelWidth:)` through the 4x supersample, linear-light area-average arm. Its verdict records the consumer dimensions (1166 and 2332 px) and says future WebP byte comparisons must use frames from this path. Current DocC and architecture describe GIF and MP4 products only; the aski product command has no WebP export surface.

Start here: Read the ASKI-64 task, `docs/Research/2026-09-01-issue33-target-size-render-and-lossless-webp.md`, `docs/Research/2026-09-01-aski63-target-width-verdict.md`, `Package.swift`, `Sources/Aski/Video/ASCIIGIFTypes.swift`, `ASCIIGIFEncoder.swift`, and `Sources/Aski/Aski.docc/Video.md`. The research note names `WebPAnimEncoderNew/Add/Assemble`, explains why keyframe-only `WebPMux` is the wrong measured shape, and lists the alpha-zero requirement for `WebPConfig.exact = 1`.

Constraints and dependencies: AC#1 is a hard gate: the owner must record whether a libwebp C dependency is acceptable and whether it belongs in a separate product so the core `Aski` target stays dependency-free. If refused, the task closes with ImageIO APNG as the zero-dependency fallback and its measured size penalty. The dated 2026-09-01 note measured no ImageIO WebP destination on macOS 26.6.2 and the iOS 26.5 simulator; on the consumer's 17-frame 1166x777 corpus it recorded GIF 3,035,750 bytes, lossless WebP 2,493,752, and APNG 14,268,917. It also records `WebPAnimEncoder` beating a keyframe-only mux on a synthetic corpus. These are dated local findings, not current third-party guarantees. The candidate `libwebp-Xcode` version, manifest platforms, headers, and visionOS behavior were observed in that note but are unverified current capability and must be refreshed before implementation.

Validation to run: After the owner decision and dependency refresh, mirror the GIF report/frame-delay surface in a thin encoder, set lossless mode explicitly, set `exact = 1`, reject either dimension above 16383 with a typed error, and prove losslessness with both webpinfo or libwebp demux and ImageIO byte comparison (max channel delta 0). Check millisecond delay round trips, alpha-zero RGB, frame order/count, loop metadata, and macOS/iOS simulator/visionOS simulator builds. Add the requested `gif|webp` lab switch while leaving the aski product unchanged unless directed. Run focused tests, `just test-media`, `just check`, and the relevant benchmark/size gate; none were run here.

First step: lead records AC#1, then refresh the dependency/API/platform matrix and freeze the 17-frame corpus reference before choosing a target layout. Keep the core target's dependency boundary and the ASKI-63 render provenance visible in the implementation and verdict artifacts.

Source map: `docs/architecture.md`, `Sources/Aski/Video/ASCIIGIFEncoder.swift`.
<!-- SECTION:NOTES:END -->
