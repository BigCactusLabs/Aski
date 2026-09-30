---
id: ASKI-93
title: Select lower-rate video frames before ASCII conversion
status: To Do
assignee: []
created_date: '2026-09-30 00:20'
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
