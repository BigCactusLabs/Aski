---
id: ASKI-93
title: Select lower-rate video frames before ASCII conversion
status: In Progress
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-10-27T16:21:00Z'
labels:
  - performance
  - video
  - resampling
dependencies: []
references:
  - Sources/Aski/Video/ASCIIVideoConverter.swift
  - Sources/Aski/Video/ASCIIVideoDecoder.swift
  - Sources/Aski/Video/ResampleSession.swift
  - Benchmarks/AskiBenchmarks/VideoPipelineBenchmarks.swift
  - Sources/Aski/Video/VideoFrameSelectionPump.swift
  - Scripts/research/video-frame-selection.md
priority: medium
type: spike
ordinal: 94000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
convertVideo (Sources/Aski/Video/ASCIIVideoConverter.swift:26-38) constructs a pipelined stream that converts every decoded image to ASCII, then feeds converted grids into the temporal resampler. ResampleSession.swift:105-112 drops superseded frames after that conversion. Lower-rate exports such as 60/120 fps to 12 fps therefore perform image preparation and matching for source frames that cannot appear in the output. Codec decode can still be required for inter-frame dependencies; this task does not promise to skip it.

The 2026-09-29 sweep verified the ordering at c49bbd; no lower-rate performance run was made. A host-enabled existing 12-frame 720p one-shot benchmark measured p50 327 ms, but does not exercise rate reduction. ASKI-1/2 cover preparation/orientation. Preserve existing caller-supplied decoder transform behavior; keep GIF disposal/compositing outside this task unless separately proven.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A frozen fixture matrix covers 60-to-12, 30-to-12, variable frame rate, rotated input, rate increases/duplicates, and unchanged-rate exports, with conversion-call and selected-frame counts.
- [ ] #2 Any adopted path preserves output frame identities/counts, CFR timestamps, dropped/duplicated report statistics, and rendered pixels against the control.
- [ ] #3 Discarded source frames do not incur ASCII conversion and duplicate output slots reuse the selected conversion; patterns still evaluate at output timestamps.
- [ ] #4 Cancellation, error propagation, public transform semantics, and bounded pipeline occupancy remain correct.
- [ ] #5 Repeated release measurements report wall/CPU time, allocations and peak RSS, with a material rate-reduction gain and no material no-resampling regression; adopted code passes just check and video benchmarks without relaxed thresholds.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Groundwork 2026-10-27: freeze frame identities, CFR output timestamps, pulled-source/drop/duplicate counts for rate reduction, VFR, upsampling, offsets and boundary cases through the existing resampling adapter. Record the exact decode/transform/resample seam and native follow-up. Do not move conversion or change decoder callback semantics in this preparation pass.

Candidate continuation — 2026-10-27: stack a separate draft on the groundwork PR. Keep codec decode, CGImage materialization, and orientation unchanged; feed a Sendable image/PTS/source-identity carrier through the existing ResampleSession, then convert only selected identities and cache one grid for duplicates. Put the existing one-frame prefetch after selection/conversion and preserve the targetFPS-nil and public decoder transform paths. Add exact contract/call-count, cancellation/error/lifetime, rotated native parity, and output-time pattern tests; add a dedicated streaming-fixture benchmark matrix with identical frozen-control calls. Use native release results and full just check as adoption gates; Linux source/portable checks are partial evidence only.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Groundwork delivered — 2026-10-27

Added `Tests/AskiTests/VideoFrameSelectionContractTests.swift` with ten literal cases through the existing production resampling adapter: 60/30-to-12, VFR, upsampling, unchanged rate, origin offsets, half-slot ties, tails, single and empty sources. It checks identities, exact CFR times, source/drop/duplicate counts, and pull requests. At 60-to-12, the selector pulls 59 of 60 supplied frames: one is lookahead and one remains unread. Prefetch may pull farther, so these are not current conversion-call measurements.

`Scripts/research/video-frame-selection.md` maps the private implementation seam, public transform semantics, grid reuse versus output-time patterns, ownership and combined occupancy constraints, and primary references. No production flow changes. Fixture arithmetic was independently cross-checked, but Swift/CoreMedia tests have not been compiled or run on this Linux host. Native rotation/pixels/cancellation/errors and performance evidence remain required.

### Early-selection candidate — 2026-10-27

Implemented a separate candidate stacked on PR #11 (`bbe65fa7ac7942449ce3b40f5df26c06143b32ca`). `convertVideo(targetFPS:)` now uses the unchanged ResampleSession on immutable decoded-image identities, converts only a newly selected source, and caches one grid for duplicates. Prefetch follows selection/conversion. Public decoder callbacks still run for every yielded source; no-targetFPS export still uses pipelinedGrids. Codec decode, CGImage materialization, orientation, GIF behavior and output-time patterns are unchanged. Conversion stays on a dedicated serial executor; no unchecked Sendable conformance or public API was added.

Extracted the ten frozen fixtures without changing values. The actual Foundation-only selection code passed official Linux Swift 6.3.3 strict-concurrency/warnings-as-errors verification: 16 existing tests plus 12 fixture cases (17 Swift Testing functions / 28 concrete executions). The two extra cases confirm the 120-to-12 and ten-second benchmark report counts. Changed Swift files passed targeted format lint and syntax parsing; actual BuildRepoMap regenerated and checked the symbol index.

Added native tests for conversion identities/counts, duplicate reuse, output-time pattern evaluation, errors/cancellation, public transform callbacks, cells/CFR/stats/rendered RGBA parity for rate changes/VFR/rotation/mirroring, encoder failure, and lazy image-provider lifetime/cleanup. Those Apple-facing assertions are NOT executed evidence on this Linux host.

Added nine 720p/80-column benchmark workloads with lazy source generation, shared SHA-256-verified MP4 caches, exact source/report/output checks, and wall/CPU/total-malloc/absolute-peak-RSS metrics. The candidate may retain more memory because the selector now holds two full-resolution images and their backing storage. Scripts/research/video-frame-selection.md records ownership, fair control/harness preparation, cache warmup, at least five alternating pairs, and predeclared 5% benefit / 3% regression bars. No benchmark threshold was relaxed and no performance result is claimed.

`just check` was attempted but could not start (`just: command not found`); Xcode/Apple frameworks remain unavailable. Native compilation, media/lifetime checks, complete capture validation and repeated release measurements are still required. No acceptance criterion is marked complete and ASKI-93 stays In Progress.
<!-- SECTION:NOTES:END -->
