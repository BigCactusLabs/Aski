---
id: ASKI-91
title: Remove repeated frame-wide animation pattern work
status: Done
assignee: []
created_date: 2026-09-30 00:20
updated_date: '2026-11-13T10:56:00Z'
labels:
  - performance
  - animation
dependencies: []
references:
  - Sources/Aski/Animation/PatternEvaluator.swift
  - Sources/Aski/Animation/ASCIIGrid+OngoingPattern.swift
  - Sources/Aski/Animation/AnimatedASCIIGrid.swift
  - Benchmarks/AskiBenchmarks/AnimationBenchmarks.swift
  - Scripts/research/aski91-2026-11-13/README.md
priority: medium
type: spike
ordinal: 92000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PatternEvaluator.ongoingAlpha recomputes pulse parameter sanitization and sine for each cell although pulse alpha only depends on pattern/time. entranceAlpha calculates spatial start before its completed-reveal exit, and radialDistance repeats anchor normalization and four corner distances per cell. ASCIIGrid.applyingOngoingPattern maps/rebuilds every cell even for valid zero-depth or zero-amplitude overlays that leave the grid unchanged.

The 2026-09-29 sweep verified these paths at c49bbd. Existing animation grid benchmarks exercise cycling without entrance/ongoing patterns, so their roughly 20 microsecond p50 does not measure this workload. ASKI-11 is motion-conditioned selection; ASKI-18 fixed public validation and its validation-before-empty behavior must remain.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pattern-specific release benchmarks cover pulse, directional wave, radial reveal, completed reveal, and neutral overlays at 80/192/288 columns, reporting time and allocations.
- [x] #2 Any adopted optimization preserves exact characters, alpha, color, coverage, composition/mask metadata, time boundaries, and behavior for nonfinite time and off-grid anchors.
- [x] #3 Invalid pattern parameters are still rejected at the same public boundaries, including empty grids; valid neutral overlays preserve the current cell-value semantics.
- [x] #4 Frame-wide work no longer scales with cell count where equivalence is proven, with bounded storage and a measured benefit rather than an assumed cache win.
- [x] #5 The task records adopt/reject against a stated end-to-end bar; adopted code passes just check and animation/media benchmarks without relaxed thresholds.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit 2026-11-12: public PR #13 (f59926b) landed groundwork: PatternFrameWorkContractTests, PatternGridGroundworkTests, 24 aski91-* workloads and docs/agents/rendering-groundwork.md. No captures have run.

2026-11-13: adopt the bounded pulse-only arm. Compute the sanitized pulse multiplier once per invocation, retaining Double through the animated entrance product and Float at the overlay's existing boundary. Storage is local and fixed in size. Validation-before-empty, per-cell multiplication, wave/reveal evaluation and all public signatures remain intact. The other inspected optimization ideas were not combined into this arm.

Both exact candidate and scalar pass full local gates (1539 core/177 media/two sentinels plus DocC) and 39 targeted release tests. Coverage includes exact cell/metadata bits, ragged grids, concurrent calls, time/default edge cases, off-grid reveal, public invalid-parameter boundaries and a precision witness against early Float conversion. Initial optimized tests failed the same signaling-NaN expected-value calculation in both arms; an identical test-only unoptimized scalar primitive fixed the oracle without weakening exact comparisons or changing production optimization. Failed and corrected evidence is retained.

The complete five-pair release study covers all 24 registered identities/four required metrics. All three pulse-overlay primaries improve in 5/5 pairs: median wall changes are -34.563746% (80 columns), -43.647962% (192) and -47.773532% (288). All 93 guards pass; no undefined ratio, retry or replacement. Six observations per raw export are within-capture distributions, not independent runs. All 16 shared animation/GIF/video compatibility captures and four unchanged animation absolute budgets pass. Two ASKI-4-only names were excluded from the reference inventory before invocation because neither91 arm registers them.

Scripts/research/aski91-2026-11-13 retains 960 raw histogram exports, 480 paired rows, compact summaries, the frozen rule, source patches, original oracle diagnostic and native evidence. Independent rational rule/table checks and the copied portable replay agree. Results apply to these synthetic overlays on one Mac with disclosed desktop activity; animated pulse has parity but no direct timing result in this matrix. Per-capture executable hashes were not recorded; post-study on-disk hashes do not attest earlier loaded bytes. The spike closes for this measured pulse arm; no blanket frame-wide or additive speedup is claimed.
<!-- SECTION:NOTES:END -->
