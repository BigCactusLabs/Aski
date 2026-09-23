---
id: ASKI-8
title: >-
  Reject non-round-trippable GIF loop counts and report encoded metadata
  accurately
status: To Do
assignee: []
created_date: '2026-08-18 18:01'
updated_date: '2026-09-10 04:15'
labels:
  - video
  - gif
  - correctness
dependencies: []
priority: medium
type: bug
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASCIIGIFEncoder accepts any Int loopCount, passes it to ImageIO, and returns the original value in GIFEncodeReport even when the finalized GIF contains different loop metadata. Confirmed examples include negative values decoding as 1, 65535 decoding as 1, 65536 decoding as 0, and Int.max decoding as 1. Define a tested ImageIO round-trippable input contract and make the report describe the produced file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The supported GIF loop-count domain and its infinite, once, and finite-play semantics are documented from verified ImageIO round-trip behavior.
- [ ] #2 A loop count outside that domain throws a caller-matchable error before destination creation and leaves any pre-existing destination unchanged.
- [ ] #3 For every accepted loop count, GIFEncodeReport.loopCount equals the loop count decoded from the finalized output file.
- [ ] #4 Regression coverage includes negative values, 0, representative finite values, 65535, 65536, and Int.max.
- [ ] #5 convertGIF source-loop preservation and valid override behavior remain stable, and focused tests plus just check pass.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `ASCIIGIFEncoder.write` accepts any `Int` loop count, passes it directly in `kCGImagePropertyGIFLoopCount`, and returns the same input in `GIFEncodeReport.loopCount` without reading the finalized file. `ASCIIGIFDecoder.containerHeader` and `containerInfo` read the output property as an `Int`, defaulting to 1 when the Netscape extension is absent. The current documented reported semantics are 1 for play once, 0 for infinite, and N for finite plays. The test fixture also records a raw Netscape value N reading back as N+1 total plays. `convertGIF(loopCount: nil)` resolves to the source header value, while a non-nil override is passed through unchanged. The ASKI-8 task records observed mismatches for negative values, 65535, 65536, and `Int.max`; those examples are task evidence and were not re-run here.

Start here: Inspect `Sources/Aski/Video/ASCIIGIFEncoder.swift`, `ASCIIGIFTypes.swift`, `ASCIIGIFDecoder.swift`, and `ASCIIGIFConverter.swift`, then use `Tests/AskiTests/GIF89aFixture.swift` and `AskiGIFConverterTests.swift` to understand the raw-versus-reported loop convention. The existing converter test compares source report, output report, and a fresh `containerInfo` read, and is the right compatibility pattern for accepted values. `AskiGIFEncoderTests.swift` is currently delay-focused and has no loop-domain matrix.

Constraints and dependencies: Define the accepted input domain from verified ImageIO round trips, rather than assuming the raw 16-bit field or the task examples are already the contract. Invalid values must throw a caller-matchable `GIFEncodeError` before `CGImageDestinationCreateWithURL` and leave a pre-existing destination unchanged. For every accepted value, `GIFEncodeReport.loopCount` must describe the finalized output as decoded by the same metadata path. Keep absent-source semantics, `loopCount: nil` preservation, valid overrides, per-frame delay behavior, and the `maximumFrameCount` rejection stable. Do not silently normalize invalid loop counts or synthesize 0 for an absent loop extension.

Validation to run: Extend focused encoder and converter tests across negative, 0, 1, representative finite values, 65535, 65536, and `Int.max`. Assert the exact thrown case, a sentinel destination's bytes for pre-existing output, and report-to-decoded-output equality. Cover absent, infinite, once, and finite source loops with `GIF89aFixture`; keep the raw Netscape N-to-N+1 behavior visible in comments. Run the serial GIF/media selection from `just test-media`, then `just check`; no builds or tests were run during this extraction.

First step: build a small behavior table from the task's recorded cases plus actual ImageIO output reads, then place the typed preflight before destination creation and choose a report-construction rule that matches the verified finalized metadata. Recheck all `ASCIIGIFEncoder.write` callers, especially `Tools/AskiVideoLab/VideoLabCLI.swift` and MotionLab, for override semantics.

Source map: `Sources/Aski/Video/ASCIIGIFTypes.swift`, `Sources/Aski/Video/ASCIIGIFDecoder.swift`, `Sources/Aski/Video/ASCIIGIFConverter.swift`, `Tests/AskiTests/AskiGIFConverterTests.swift`, `docs/Research/Discoveries.md`.
<!-- SECTION:NOTES:END -->
