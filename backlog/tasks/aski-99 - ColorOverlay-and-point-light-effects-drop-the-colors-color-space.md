---
id: ASKI-99
title: ColorOverlay and point-light effects drop the color's color space
status: To Do
assignee: []
created_date: '2026-11-06T17:46:00Z'
updated_date: '2026-11-10T02:35:00Z'
labels:
  - correctness
  - rendering
  - color
dependencies: []
references:
  - Sources/Aski/Effects/Internal/StockCIEffectKernel.swift
priority: medium
type: bug
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in the ASKI-3 review. `StockCIEffectKernel.applyColorOverlay` (Sources/Aski/Effects/Internal/StockCIEffectKernel.swift) rebuilds the overlay with `CIColor(red:green:blue:alpha:)` from the components of `CIColor(cgColor:)`, which discards the source CGColor's color space. A Display P3 overlay color (0.8, 0.2, 0.1) rendered as (204, 51, 25) in an sRGB output where (222, 24, 0) is expected; this was reproduced on macOS 27.0.1. Point-light colors likely follow the same pattern but were not reproduced. Apply the ASKI-3 rule: interpret effect colors in their declared space and let Core Image color-match them into the working space.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ColorOverlay preserves the color space of its CGColor: a P3 (0.8, 0.2, 0.1) overlay at full opacity renders within 1/255 of Core Graphics' own sRGB conversion in an sRGB output
- [x] #2 Opacity scaling still applies only to alpha, and blend-mode behavior is unchanged
- [x] #3 Point-light and any other effect that takes a CGColor are audited and fixed or explicitly ruled out, with evidence
- [ ] #4 Regression tests fail on the current code; affected goldens are re-recorded with a no-harm note; just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ASKI-99 r1 (branch work/aski-99-effect-color-space): overlay keeps CGColor space (copy(alpha: opacity) -> CIColor(cgColor:)); point lights convert to extended sRGB before the unchanged encoded-sRGB intensity scale. Base: P3 (0.8,0.2,0.1) overlay into sRGB = (204,51,25) vs CG reference (222,24,0); after: within 1/255. sRGB-tagged overlays are byte-identical to the legacy construction (8 blend modes x 4 opacities, sRGB+P3 outputs); sRGB lights are unchanged ((246,130,72) at 0.6, (255,226,130) at 1.0). Contract A: Generic RGB is color-matched too; 5 overlay-* composition goldens re-recorded in a separate last commit, and a legacy remap reproduces the old goldens byte for byte. Audit: Background.solid already honored the space; scanlines and other kernels use internal constants; mask fallback/ground is owned by ASKI-98. AC4: focused suites pass; the lead's just check is pending.
<!-- SECTION:NOTES:END -->
