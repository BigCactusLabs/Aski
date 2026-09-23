---
id: ASKI-9
title: Sample integration proving photo → render → animated reveal
status: Done
assignee: []
created_date: '2026-08-18 18:02'
updated_date: '2026-08-27 12:33'
labels:
  - integration
dependencies: []
priority: medium
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Prove a host app can drive the full 'looks' beat through Aski's public API: photo → canonical duotone preset render (the frozen AskiPresetLab winner) → EntrancePattern animated reveal → CGImage frames suitable for a choreographed reveal. Per the no-SDK-ceremony rule, take the sample-integration path: build a minimal example (a small executable under Tools/ or an integration test) and promote API into Sources/ only where the sample proves a concrete gap. Non-goals: HDR tiers, joint glyph-color scoring, new recipes, any new color research.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A sample integration exercises the full beat end-to-end: image input → canonical preset render → EntrancePattern-based reveal → rendered CGImage frames
- [x] #2 The entire flow uses public (non-@_spi) API only; any API gap found is either promoted with a concrete justification or filed as a follow-up task
- [x] #3 The sample documents the intended host-app call sequence (the seam contract) in a brief doc or doc-comment an integrating app can follow
- [x] #4 No new public abstraction is added beyond what the sample proves necessary (no-SDK-ceremony rule upheld)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24 (deep pass): Tools/AskiDemo is no longer a demo site — it is the shipping aski CLI target (Package.swift:9). A sample needs a new target or an integration test. ASCIIConverter+Animation entry point is already public, so AC#2 likely passes without API promotion.

Shipped in the four-task mask batch, PR #31 (merge f761952, 2026-08-27). The reveal integration test suite (Tests/AskiTests, ASKI-9 suite) proves the full beat end-to-end on public API only (photo -> frozen duotone preset render -> EntrancePattern reveal -> CGImage frames); the host-app call sequence (seam contract) is documented in the suite's doc comments; no new public abstraction was needed, upholding the no-SDK-ceremony rule.
<!-- SECTION:NOTES:END -->
