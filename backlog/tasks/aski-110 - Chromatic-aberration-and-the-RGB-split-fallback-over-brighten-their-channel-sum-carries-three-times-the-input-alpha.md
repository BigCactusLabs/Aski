---
id: ASKI-110
title: >-
  Chromatic aberration and the RGB-split fallback over-brighten: their channel
  sum carries three times the input alpha
status: Done
assignee: []
created_date: '2026-11-13T22:09:00Z'
updated_date: '2026-11-14T20:39:00Z'
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
- [x] #1 Confirm the brightening end to end through renderImage with chromaticAberration and through the rgbSplit fallback, away from the shifted edges
- [x] #2 Away from shifted edges, an opaque uniform image keeps its color within 1/255 in sRGB and Display P3 output, and a semi-transparent input keeps its alpha
- [x] #3 Moved snapshots are re-recorded with a before/after note, and the CHANGELOG explains the brightness change
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Confirm the real chromatic aberration, per-character aberration and reduced-quality RGB-split render paths on opaque/translucent sRGB and Display P3 inputs. Preserve the failing pixels, apply a narrow alpha-correct recomposition, run targeted regressions, re-record only affected non-frozen snapshots with a before/after note, then run the combined full gate and record the brightness change.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-14: Confirmed native brightening/alpha loss and corrected the shared stock channel split. Opaque and half-alpha assertions pass within one RGBA8 count in sRGB/P3, including per-character glyph interiors. Signed shifts preserve local coverage. Exactly three effect snapshots re-recorded with retained before/after PNGs; CHANGELOG updated. Full just check passed at base 4f4e6b1 plus source/test hashes in docs/Research/Results/2026-11-14-aski110-channel-alpha/validation.json. No frozen-preset change.
<!-- SECTION:NOTES:END -->
