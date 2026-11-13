---
id: ASKI-93
title: Select lower-rate video frames before ASCII conversion
status: Done
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-11-13T05:22:00Z'
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
- [x] #1 A frozen fixture matrix covers 60-to-12, 30-to-12, variable frame rate, rotated input, rate increases/duplicates, and unchanged-rate exports, with conversion-call and selected-frame counts.
- [x] #2 Any adopted path preserves output frame identities/counts, CFR timestamps, dropped/duplicated report statistics, and rendered pixels against the control.
- [x] #3 Discarded source frames do not incur ASCII conversion and duplicate output slots reuse the selected conversion; patterns still evaluate at output timestamps.
- [x] #4 Cancellation, error propagation, public transform semantics, and bounded pipeline occupancy remain correct.
- [x] #5 Repeated release measurements report wall/CPU time, allocations and peak RSS, with a material rate-reduction gain and no material no-resampling regression; adopted code passes just check and video benchmarks without relaxed thresholds.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Groundwork 2026-10-27: freeze frame identities, CFR output timestamps, pulled-source/drop/duplicate counts for rate reduction, VFR, upsampling, offsets and boundary cases through the existing resampling adapter. Record the exact decode/transform/resample seam and native follow-up. Do not move conversion or change decoder callback semantics in this preparation pass.

Candidate continuation — 2026-10-27: stack a separate draft on the groundwork PR. Keep codec decode, CGImage materialization, and orientation unchanged; feed a Sendable image/PTS/source-identity carrier through the existing ResampleSession, then convert only selected identities and cache one grid for duplicates. Put the existing one-frame prefetch after selection/conversion and preserve the targetFPS-nil and public decoder transform paths. Add exact contract/call-count, cancellation/error/lifetime, rotated native parity, and output-time pattern tests; add a dedicated streaming-fixture benchmark matrix with identical frozen-control calls. Use native release results and full just check as adoption gates; Linux source/portable checks are partial evidence only.

Native closeout — 2026-11-12: integrate current main, retain all nine workloads/four metrics/five adjacent alternating pairs with a 20-minute series cap; independently review the instrument and unit-aware readout, publish complete evidence, run the final local gate and merge PR #12 if the unchanged rule passes.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Groundwork delivered — 2026-10-27

Added `Tests/AskiTests/VideoFrameSelectionContractTests.swift` with ten literal cases through the existing production resampling adapter: 60/30-to-12, VFR, upsampling, unchanged rate, origin offsets, half-slot ties, tails, single and empty sources. It checks identities, exact CFR times, source/drop/duplicate counts, and pull requests. At 60-to-12, the selector pulls 59 of 60 supplied frames: one is lookahead and one remains unread. Prefetch may pull farther, so these are not current conversion-call measurements.

`Scripts/research/video-frame-selection.md` maps the private implementation seam, public transform semantics, grid reuse versus output-time patterns, ownership and combined occupancy constraints, and primary references. No production flow changes. Fixture arithmetic was independently cross-checked, but Swift/CoreMedia tests were not compiled or run on the initial Linux host. Native evidence was required at that stage and is recorded below.

### Early-selection candidate — 2026-10-27

Implemented a separate candidate stacked on PR #11 (`bbe65fa7ac7942449ce3b40f5df26c06143b32ca`). `convertVideo(targetFPS:)` now uses the unchanged ResampleSession on immutable decoded-image identities, converts only a newly selected source, and caches one grid for duplicates. Prefetch follows selection/conversion. Public decoder callbacks still run for every yielded source; no-targetFPS export still uses pipelinedGrids. Codec decode, CGImage materialization, orientation, GIF behavior and output-time patterns are unchanged. Conversion stays on a dedicated serial executor; no unchecked Sendable conformance or public API was added.

Extracted the ten frozen fixtures without changing values. The actual Foundation-only selection code passed official Linux Swift 6.3.3 strict-concurrency/warnings-as-errors verification: 16 existing tests plus 12 fixture cases (17 Swift Testing functions / 28 concrete executions). The two extra cases confirm the 120-to-12 and ten-second benchmark report counts. Changed Swift files passed targeted format lint and syntax parsing; actual BuildRepoMap regenerated and checked the symbol index.

Added native tests for conversion identities/counts, duplicate reuse, output-time pattern evaluation, errors/cancellation, public transform callbacks, cells/CFR/stats/rendered RGBA parity for rate changes/VFR/rotation/mirroring, encoder failure, and lazy image-provider lifetime/cleanup. Those Apple-facing assertions were not executed on the initial Linux host; they passed in the later native gate below.

Added nine 720p/80-column benchmark workloads with lazy source generation, shared SHA-256-verified MP4 caches, exact source/report/output checks, and wall/CPU/total-malloc/absolute-peak-RSS metrics. The candidate may retain more memory because the selector now holds two full-resolution images and their backing storage. Scripts/research/video-frame-selection.md records ownership, fair control/harness preparation, cache warmup, at least five alternating pairs, and predeclared 5% benefit / 3% regression bars. No benchmark threshold was relaxed; no performance result was available at that initial stage.

The initial Linux attempt could not start `just check` (`just: command not found`) and had no Apple frameworks. The native validation and adoption below supersede that pending status.

### Native validation and adoption — 2026-11-12

Measured candidate d16896e5746f69a4d3ef86f29098cb2b134d8e0a integrates current main c81861c. Control 46024d6e28eb8f1ac019b2965d1a3cf5c6dc7993 adds only the identical benchmark instrument/registration and protocol to that main. Both retain the merged preparation/orientation fixes. All benchmark, validator and lockfile hashes matched before capture.

Full native just check passed: 1,529 core tests, 177 media tests (including the exact parity, conversion-count, public-callback and lifetime suites), both deadlock sentinels, drift checks and DocC. All nine existing video- benchmarks passed without threshold changes. These establish AC 1–4 and the native part of AC 5.

All nine ASKI-93 workloads and four metrics ran in five adjacent alternating release pairs, in 763.344 seconds. Every capture was valid and complete, with created=false and matching hashes for all seven source MP4s. Primary 30/60/120-to-12 wall-time medians improved by 29.98%, 55.87% and 73.01%, each improving in all five pairs. No guarded metric reached the predeclared four-of-five >3% regression rule. Controls were noisy; this does not claim a speedup or strict noninferiority in every pair.

The generic comparator remains invalid at the long-clip allocation M/K mismatch. An independent Opus review accepted the decimal-unit, export-rounding-aware supplement; all 180 paired rows and 360 raw exports are committed under Scripts/research/aski93-2026-11-12/. The portable reproducer checks every unit, hash, sample count and median. Original rule outcomes survive +/-0.25 percentage-point sensitivity for histogram quantization. RSS is the sampled process maximum during the measured loop, including output inspection, not setup/warmup peaks or an isolated conversion-stage bound.

ADOPT under the unchanged frozen rule. Scope is the synthetic 720p/80-column matrix on one Mac; the desktop was not idle. Scripts/research/video-frame-selection.md records outliers, units, source/instrument hashes and all limits. No executable source or benchmark-setting change followed the measured candidate; only documentation/evidence and the benchmark RSS comment were corrected. No public API, golden or threshold changed.

Audit 2026-11-12: merged as public PR #12 (2c3d1bd); groundwork in public PR #11 (00e5b1b). The paired control commit 46024d6 is reachable only from cdx/pr12-short-control-20261112; keep that branch or tag the commit before any cleanup.

2026-11-13: control commit 46024d6 is preserved by the annotated tag evidence/aski93-control (pushed), so the cdx/pr12-short-control branch can be cleaned up safely.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Select before ASCII conversion for explicit targetFPS and reuse grids for duplicates. Native parity/lifetime/callback gates and existing video benchmarks passed. Five complete paired release runs meet the frozen benefit and regression rules; all raw exports, paired CSV, rounding-aware reproducer and limitations are committed. Synthetic one-Mac evidence; see Scripts/research/video-frame-selection.md.
<!-- SECTION:FINAL_SUMMARY:END -->
