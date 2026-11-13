---
id: ASKI-108
title: >-
  Inspect occupancy gradients into white for a visible cliff at the luma 0.95
  zero-query threshold
status: To Do
assignee: []
created_date: '2026-11-13T05:20:00Z'
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
- [ ] #1 Gradient-into-white occupancy fixtures (for example rcs-function, spacecraft-attitude, james-lovell from nasa-occupancy-v1) are rendered on the frozen preset and inspected at the 0.95 boundary, with the render pairs committed under docs/Research/Results/
- [ ] #2 A visible cliff is either recorded as absent, or a softer-transition treatment is proposed as a pre-registered lab arm; rendering near-white as ink is out of scope per the ASKI-84 ruling
<!-- AC:END -->
