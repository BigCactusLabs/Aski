---
id: ASKI-2
title: Fuse video orientation into target-size frame preparation
status: To Do
assignee: []
created_date: '2026-08-18 18:01'
updated_date: '2026-09-10 04:15'
labels:
  - performance
  - video
  - conversion
dependencies:
  - ASKI-1
priority: high
type: enhancement
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rotated and mirrored video frames are currently materialized as full-resolution oriented CGImages before conversion prepares a smaller working image. Eliminate that full-resolution intermediate by applying orientation as part of target-size preparation, using the direct decoded-image path established by ASKI-1. This targets the large rotated-video CPU gap while keeping the fidelity requirement that rejected an earlier Core Image prototype.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Identity, rotated, and mirrored video frames are oriented and scaled for conversion without materializing a separate full-resolution oriented CGImage.
- [ ] #2 Cell output and rendered output for every supported orientation match the retained path exactly or satisfy explicit color and geometry tolerances established from current fixtures.
- [ ] #3 Video frame order, presentation timestamps, cancellation, and the bounded pipeline occupancy remain unchanged.
- [ ] #4 Representative identity and rotated 720p benchmarks record before and after wall time, CPU time, and peak resident memory and show no regression for identity clips.
- [ ] #5 just check and just bench pass without loosening an existing benchmark threshold.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `ASCIIVideoDecoder.DecodeSession.next()` reads one sample, captures its presentation timestamp, converts the pixel buffer to a `CGImage`, calls `reorient(image)`, and only then invokes the caller's conversion transform. `start()` loads the track's `preferredTransform` once. Identity returns the decoded image directly; any other transform computes a display extent, builds a CIImage affine transform with Y-flips, renders a full-resolution oriented `CGImage` through a lazily cached actor-local `CIContext`, and passes that image to `ASCIIConverter`. `convertVideo` uses `pipelinedGrids`, which has one ordered prefetch slot; the plain `grids` sequence remains one-pull/one-decode.

Start here: read `ASCIIVideoDecoder.DecodeSession.next`, `start`, and `reorient`, then the ASKI-1 preparation boundary in `ASCIIConverter.prepareConversion` and `ImageIOThumbnail`. The retained orientation oracle is in `AskiVideoOrientationTests`: 90-degree, 270-degree, and front-camera mirror transforms are compared against `AVAssetImageGenerator` with `appliesPreferredTrackTransform`. `VideoPipelineTests` separately checks that pipelining preserves converted grids and timestamps.

Constraints and dependencies: ASKI-2 depends on ASKI-1's direct target-size decoded-image path. The new path must orient and scale in one preparation operation, without a full-resolution oriented intermediate, while preserving cell output and rendered output for identity, rotation, and mirror cases. Keep PTS order, cancellation, failure propagation, and the two-frame bounded pipeline occupancy unchanged. Identity must retain its current no-reorientation fast path. The task explicitly calls out fidelity: the earlier Core Image prototype was rejected, so any transform math and color handling need an evidence-backed comparison.

Validation to run: use the existing orientation oracle tests plus a conversion/render parity fixture for every supported preferred transform; run the serialized media phase and deadlock sentinels through `just check`. `just bench` already registers identity and rotated 720p decode, conversion, and end-to-end cases with wall, CPU, peak resident-memory, and allocation metrics. Record before/after identity and rotated results and show no identity regression.

First step: map the preferred-transform coordinate math to the target lattice dimensions and profile the current full-resolution reorientation versus a fused preparation arm, keeping the transform closure and streaming ownership unchanged.

Source map: `Sources/Aski/Video/ASCIIVideoDecoder.swift`, `Tests/AskiTests/AskiVideoLoopTests.swift`, `Tests/AskiTests/VideoPipelineTests.swift`, `Benchmarks/AskiBenchmarks/VideoPipelineBenchmarks.swift`, `docs/architecture.md`.
<!-- SECTION:NOTES:END -->
