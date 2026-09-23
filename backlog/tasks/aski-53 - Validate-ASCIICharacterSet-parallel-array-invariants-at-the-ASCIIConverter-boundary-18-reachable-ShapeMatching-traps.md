---
id: ASKI-53
title: >-
  Validate ASCIICharacterSet parallel-array invariants at the ASCIIConverter
  boundary (18 reachable ShapeMatching traps)
status: Done
assignee: []
created_date: '2026-08-24 03:45'
updated_date: '2026-08-27 12:32'
labels:
  - correctness
  - robustness
  - algorithms
dependencies: []
priority: medium
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The ASKI-36 trap audit (docs/Research/2026-08-23-aski36-trap-audit.md, class-C table) found 18 latent public-input traps that all share one root cause: ASCIIConverter accepts any public ASCIICharacterSet conformance without checking the documented parallel-array invariant — characters, brightnessValues, rawDensityValues, shapeVectorLanes (15 lanes per glyph), steerableSignatures, and ShapeStructureChannels must agree in count — then LogPolarKernel forwards the arrays into ShapeMatching guards several calls deep (sites: ShapeMatching.swift 16, 54, 57, 112, 218, 222, 274, 276, 500, 503, 504, 575, 579, 580, 633, 636, 638, 639). A custom conformance with, e.g., characters=[x] and brightnessValues=[] traps inside the matcher instead of failing at the convert call. Fix is ONE boundary validation, not 18 patches: validate the conformance once where the converter first accepts it, per the Batch A convention (structural parameters rejected at the public boundary). The audit note's class-A/B tables record which entry point guarantees each internal invariant so the new check does not duplicate an existing one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The parallel-array invariant is validated once at the public boundary where ASCIIConverter accepts a character set, with a documented error/precondition message naming the mismatched arrays
- [x] #2 All 18 audited trigger paths fail at that boundary instead of inside ShapeMatching; regression covers at least the empty-brightness, lane-mismatch, signature-mismatch, and structure-channel-mismatch shapes through public convert and rankedCandidateIndices paths
- [x] #3 Built-in and RasterizedCharacterSet construction paths are unaffected and byte-identical; just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24 (deep pass): All 18 cited preconditions verified live; boundary still unguarded. Scoping caveat for AC#2: sites at ShapeMatching.swift:633-639 are on the default-off shapeStructureAssist path — reachable only with it enabled.

Shipped in the four-task mask batch, PR #31 (merge f761952, 2026-08-27). One boundary validation (validateParallelArrayInvariant) covers all 18 audited ShapeMatching traps; exit tests cover empty-brightness, lane-mismatch, signature-mismatch, and structure-channel shapes through convert and rankedCandidateIndices. Codex review added two hardenings in b6b7b66: the validator also runs in didSet on the public mutable characterSet (init-only was bypassable), and an all-empty conformance is rejected via characterCount > 0. Built-in and rasterized sets byte-identical at the boundary; just check green.
<!-- SECTION:NOTES:END -->
