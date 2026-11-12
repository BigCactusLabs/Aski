---
id: ASKI-101
title: Soft mask coverage weights fallback and ground differently by render path
status: Done
assignee: []
created_date: '2026-11-10T02:41:00Z'
updated_date: '2026-11-10T19:09:00Z'
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
- [x] #1 Decide and document which coverage interpretation is correct (linear coverage weight vs encoded) with an independent reference
- [x] #2 Every render path, CGImage and CIImage outputs, applies the same weight at soft mask edges within 1/255
- [x] #3 softCoverageWeightCurrentlyDependsOnPath is replaced by a contract test; moved soft-edge mask goldens are re-recorded with a before/after note
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-10: the ASKI-98 color-space batch landed on main in PR #21 (merge f6f25cb), so MaskColorContractTests.softCoverageWeightCurrentlyDependsOnPath is on main and pins the current path split. A fix here should update that pin deliberately.

2026-11-10: root cause verified before the fix. Core Image reads a Device Gray CGImage with the exact sRGB transfer: bytes 64/128/192 become 0.0513/0.2159/0.5271 in a linear working space (gamma 2.2 would give 0.0478/0.2195/0.5356). A CIBlendWithMask over the 0.5 coverage image gives alpha 33 for paint alpha 0.6 in a linear working space and 77 in an sRGB working space, which is why renderCIImage weights depended on the consumer. Creating the coverage image with CIImageOption.colorSpace = NSNull (no color management, per the CIImage.h header) gives 77 in both.

Decision (AC 1): coverage is a linear weight, the fraction of the active branch, as the Core Graphics overlays and the cell rasters (alpha x coverage) already treated it. Independent references: CSS Masking Level 1, Mask processing (https://www.w3.org/TR/css-masking-1/#MaskValues): the mask value multiplies the element's alpha, and luminance masks take channel values in the mask's color-interpolation space, sRGB by default (SVG 2 color-interpolation initial value), which is how MaskSampler derives coverage; PNG 3rd edition section 4.3 (https://www.w3.org/TR/png-3/#4Concepts.ColourSpaces): alpha is a linear fraction of full opacity and gamma correction does not apply to it. Documented in the Masking guide (Coverage weight).

AC 2: CoverageImageBuilder.coverageImage creates both ASCII and tile coverage images without color management. MaskColorContractTests.softCoverageIsALinearWeightOnEveryPath checks all 18 paths x sRGB/Display P3 x coverage 0.25/0.5/0.75 x fallback/ground within 1 step of a Core Graphics reference, and reads every CIImage output through both an encoded and a linear CIContext working space. CoverageImageBuilderTests.softCoverageReadsBackUnchangedInAnyWorkingSpace checks the builder directly.

AC 3: softCoverageWeightCurrentlyDependsOnPath is replaced by that contract test. Re-recorded MaskSnapshotTests goldens (changed pixels, max channel delta, mean delta over changed pixels): ascii-circle-character 43.6% / 67 / 20.4; tile-mosaic-circle-solid 16.3% / 66 / 35.9; same-source-ground-080808 18.2% / 34 / 7.1; docc-mask-ground-after and the DocC asset mask-ground-after.png 11.3% / 54 / 10.7. All other goldens, including the frozen Vesper preset, are unchanged, so no selection-ceiling census applies.

Out of scope, filed as ASKI-103: with opaque branches on both sides of a soft edge, Core Graphics paths mix encoded values and Core Image paths mix linear light (white fallback over black at c = 0.5: 128 direct versus 187 effects).
<!-- SECTION:NOTES:END -->
