---
id: ASKI-84
title: >-
  Near-white cells get an all-zero shape query and render as the blank, so pure
  white shows as dark ground on the frozen preset
status: To Do
assignee: []
created_date: '2026-09-27 18:56'
updated_date: '2026-09-27 20:57'
labels:
  - research
  - matcher
  - preset
dependencies: []
priority: medium
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by ASKI-79/80 phase 1 (docs/Research/Results/2026-09-27-aski-79-80-baseline/orthogonality.csv). Under the shipped inverted shape-query polarity, a cell whose pixels all have luma above 0.95 gets an all-zero query. Every candidate is then orthogonal, and in every set that holds a zero-norm glyph in its tone pool the blank wins. The matcher otherwise maps high L to high ink, so this is a tone inversion at the top of the range. On the frozen preset (blocks, 76) pure white renders as the dark ground. Share of such cells: 0% on nasa-steerable-v1, at most 0.02% on nasa-structure-v1, 13-15% on nasa-occupancy-v1, concentrated on white-background diagrams (rcs-function 84%, spacecraft-attitude 77%) and the james-lovell portrait (20%). The ASKI-79/80 arm 1 fallback changes these cells as a side effect; whether white should render as ink or ground on the preset is an owner product decision, taken in the ASKI-79/80 PR review. This task owns the question if arm 1 does not ship, or if the owner wants a different treatment than arm 1 gives.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The owner decides whether near-white cells render as ink or as ground on the frozen preset, from a before/after render of a white-ground fixture
- [ ] #2 The chosen behaviour is pinned by a test on a white-ground fixture
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-27 owner decision (PR #6 review): keep near-white zero-query cells rendering as the dark ground on the frozen preset; do not switch them to ink. Reason: blocks + logPolar puts nearly every cell on the same glyph, so the image lives in the palette and figure/ground separation is the main structure left. In the ASKI-79/80 render pairs (docs/Research/Results/2026-09-27-aski-79-80-decisive/render-pair/) ground keeps the james-lovell silhouette and the rcs-function diagram legible as a negative; ink merges the backdrop into the figure and reduces the diagram to scattered marks. GMSD agrees (fallback x1.167 worse on frozen-76-occ); the MAE gain (x0.865) is flat-white tone match only. Remaining work: (1) a test pinning ground for all-zero-query cells on the frozen preset, (2) one sentence in the preset docs stating it, (3) inspect occupancy fixtures with gradients running into white for a visible cliff at the luma 0.95 threshold; if found, the follow-up is a softer transition near the threshold, not ink.
<!-- SECTION:NOTES:END -->
