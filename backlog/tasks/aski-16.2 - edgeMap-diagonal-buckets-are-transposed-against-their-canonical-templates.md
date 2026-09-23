---
id: ASKI-16.2
title: edgeMap diagonal buckets are transposed against their canonical templates
status: Done
assignee: []
created_date: '2026-08-19 05:18'
updated_date: '2026-08-20 20:01'
labels:
  - correctness
  - algorithms
  - edge-map
dependencies: []
references:
  - Sources/Aski/Algorithms/EdgeMapKernel.swift
  - Sources/Aski/Algorithms/EdgeMap.swift
  - Sources/Aski/Algorithms/AlgorithmKernel.swift
parent_task_id: ASKI-16
priority: high
type: bug
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`EdgeMapKernel.classifyBucket` maps orientation bin 1 to `.diagAsc` and bin 3 to `.diagDesc`. The two are swapped relative to the shapes `CanonicalOrientationTemplates` actually draws, so every diagonal cell is matched against the MIRROR of its own orientation.

Verified against real rasters (48x48 three-pixel stroke, run through `EdgeMap.compute` and the exact 4-bin histogram from `pickScored`):
- source '\\' -> classified .diagAsc
- source '/'  -> classified .diagDesc
and against the templates themselves (squared L2 vs a freshly built 64x64 descriptor):
- templates[.diagAsc]  is EXACTLY '/'  (distance 0.0 to '/', 0.410 to '\\')
- templates[.diagDesc] is EXACTLY '\\' (distance 0.0 to '\\', 0.410 to '/')

Root cause is a convention mismatch in the code's own comment. `EdgeMap.compute` stores `folded = atan2(gy, gx) + pi/2` mod pi, which is the EDGE TANGENT orientation, not the gradient direction the `classifyBucket` comment claims ('Bins are indexed 0=0, 1=pi/4, 2=pi/2, 3=3pi/4 (gradient direction)'). Under the tangent reading the horizontal and vertical arms are right — confirmed empirically, horizontal -> .horizontal and vertical -> .vertical — so it is only the diagonal arm that is inconsistent, and bins 1 and 3 are the half to correct.

Independent of the blank-glyph defect in the sibling subtask: fixing only that one would make edgeMap emit confidently mirrored diagonals instead of blanks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A '\\' source stroke classifies as .diagDesc and a '/' source stroke classifies as .diagAsc, asserted from a rasterized fixture through EdgeMap.compute rather than hand-built bins
- [ ] #2 Horizontal, vertical and cross classification is unchanged, with the existing classifyBucket unit tests still passing
- [ ] #3 The classifyBucket comment states the real convention (folded edge-tangent orientation), and EdgeMap.edgeAngle documents the same
- [ ] #4 With the sibling blank-glyph subtask fixed, a diagonal fixture on the .diagonal character set emits the matching diagonal glyph rather than its mirror
<!-- AC:END -->
