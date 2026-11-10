---
id: ASKI-101
title: Soft mask coverage weights fallback and ground differently by render path
status: To Do
assignee: []
created_date: '2026-11-10T02:41:00Z'
updated_date: '2026-11-10T03:03:00Z'
labels:
  - correctness
  - rendering
  - masking
dependencies: []
priority: medium
type: bug
ordinal: 102000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while characterizing ASKI-98. With paint alpha 0.6 and soft mask coverage 0.5, the Core Graphics overlay paths (direct ASCII, target width, direct tile pixelArt/brick fallback) composite the fallback at alpha byte 77 (0.6 x 0.5), but the Core Image mask compositor paths (effects, async, engine, direct ASCII ground, rerouted tile mosaic) give fallback 120 (0.6 x 0.786) and ground 33 (0.6 x 0.214). CIImage outputs depend on the consumer's CIContext working space. Likely cause: CoverageImageBuilder builds coverage as a Device Gray image (Sources/Aski/Masking/CoverageImageBuilder.swift), and CIBlendWithMask (MaskCompositor.swift) runs in a linear working space, so a 0.5 coverage value is linearized to about 0.214 before it weights the blend. Hard-edged masks are unaffected. The current split is pinned by MaskColorContractTests.softCoverageWeightCurrentlyDependsOnPath, which arrives with the ASKI-98 color-space batch PR.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decide and document which coverage interpretation is correct (linear coverage weight vs encoded) with an independent reference
- [ ] #2 Every render path, CGImage and CIImage outputs, applies the same weight at soft mask edges within 1/255
- [ ] #3 softCoverageWeightCurrentlyDependsOnPath is replaced by a contract test; moved soft-edge mask goldens are re-recorded with a before/after note
<!-- AC:END -->
