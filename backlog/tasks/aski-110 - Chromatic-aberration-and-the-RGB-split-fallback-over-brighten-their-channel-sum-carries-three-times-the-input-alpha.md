---
id: ASKI-110
title: >-
  Chromatic aberration and the RGB-split fallback over-brighten: their channel
  sum carries three times the input alpha
status: To Do
assignee: []
created_date: '2026-11-13T22:09:00Z'
labels:
  - correctness
  - rendering
  - effects
dependencies: []
priority: low
type: bug
ordinal: 111000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while fixing ASKI-102. StockCIEffectKernel.applyChromaticAberration (the .chromaticAberration effect and per-character AberrationOptions) and applyRGBSplitApprox (the .rgbSplit fallback) rebuild the image by adding three single-channel copies with CIAdditionCompositing. Each copy keeps the input alpha, so the sum has alpha 3 times the input's. As in ASKI-102, converting to the output color space then divides the color by that alpha, encodes it and multiplies the alpha back in. A standalone Core Image probe of the channel sum on a uniform 64x64 image (no shift) gave: opaque sRGB (153, 102, 51) rendered as (255, 178, 81); half-alpha (77, 51, 25, 128) rendered opaque as (137, 89, 41, 255). The end-to-end effect has not been confirmed through a full render yet. Existing snapshots (EffectKernelTests chromaticAberration-default and chromaticAberration-extreme, CompositionSnapshotTests perCharacter-aberration-on) were recorded with this output, so a fix moves them. The frozen preset uses neither effect. The ASKI-102 fix (settingAlphaOne on an opaque field) does not carry over directly, because the effect must keep the input's own alpha.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Confirm the brightening end to end through renderImage with chromaticAberration and through the rgbSplit fallback, away from the shifted edges
- [ ] #2 Away from shifted edges, an opaque uniform image keeps its color within 1/255 in sRGB and Display P3 output, and a semi-transparent input keeps its alpha
- [ ] #3 Moved snapshots are re-recorded with a before/after note, and the CHANGELOG explains the brightness change
<!-- AC:END -->
