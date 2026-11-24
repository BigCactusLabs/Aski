---
id: ASKI-108
title: >-
  Inspect occupancy gradients into white for a visible cliff at the luma 0.95
  zero-query threshold
status: Done
assignee: []
created_date: '2026-11-13T05:20:00Z'
updated_date: '2026-11-24T20:46:15Z'
labels:
  - research
  - matcher
  - preset
dependencies: []
priority: low
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Split from ASKI-84 on 2026-11-13. The owner kept near-white zero-query cells rendering as the dark ground on the frozen preset (PR #6 review, 2026-09-27), and NearWhiteGroundContractTests pins it. One item from that ruling remains: inspect occupancy fixtures whose gradients run into white for a visible cliff where cells cross the luma 0.95 threshold and switch to the blank. If a cliff is visible, the follow-up is a softer transition near the threshold, not rendering white as ink.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Gradient-into-white occupancy fixtures (for example rcs-function, spacecraft-attitude, james-lovell from nasa-occupancy-v1) are rendered on the frozen preset and inspected at the 0.95 boundary, with the render pairs committed under docs/Research/Results/
- [x] #2 A visible cliff is either recorded as absent, or a softer-transition treatment is proposed as a pre-registered lab arm; rendering near-white as ink is out of scope per the ASKI-84 ruling
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Freeze the inspection protocol before capture. Render the named NASA occupancy fixtures and a diagnostic gradient through the unchanged canonical preset, retain native source/render pairs and exact zero-query boundary evidence, inspect the images, and record scoped visible absence or propose an unexecuted softer-transition lab arm. Preserve the near-white dark-ground ruling; do not change the shipping matcher.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-14: Protocol and instrument frozen at bc0e31f before the release capture. The three named NASA source/canonical pairs are retained with exact zero-query boundary CSVs and masks. Positive diagnostic and all four independent grid/canonical byte comparisons pass. Lead AI visual inspection supports a cliff in the Lovell sky; diagram transitions follow hard source contours. A precise future lab-only cell-alpha taper is pre-registered, including normalization, near-white-ink veto, blinded held-out review and MAE/GMSD gates; no treatment or shipping change. Decision: docs/Research/2026-11-14-aski108-near-white-inspection.md.

Audit 2026-11-24: the pre-registered cell-alpha taper arm is filed as ASKI-111 (owner decision).
<!-- SECTION:NOTES:END -->
