---
id: ASKI-102
title: >-
  Point lights over-brighten: the light field's alpha exceeds 1 before the
  multiply
status: Done
assignee: []
created_date: '2026-11-10T02:41:00Z'
updated_date: '2026-11-13T22:12:00Z'
labels:
  - correctness
  - rendering
  - effects
dependencies: []
priority: low
type: bug
ordinal: 103000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while fixing ASKI-99. An sRGB (0.8, 0.2, 0.1) PointLight at intensity 1, ambient 0, over a white image renders about (255, 81, 33) at the light center instead of the light color (204, 51, 25). Likely cause by inspection: LightingApplicator sums an opaque black seed field, the radial light field and the opaque ambient field with CIAdditionCompositing, which also adds alpha, so the light field's alpha exceeds 1 before CIMultiplyCompositing applies it to the image. This is a lighting-model scale question, separate from color space; ASKI-99 left the intensity model unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Document the intended meaning of PointLight.intensity and ambient (what a light of intensity 1 over white should produce) with an independent reference
- [x] #2 The lighting composite matches that meaning within 1/255 at the light center, for sRGB and Display P3 outputs
- [x] #3 Moved lighting goldens are re-recorded with a before/after note and the CHANGELOG explains the brightness change
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Batch follow-up (2026-11-09, ruling R6): LightingApplicator now converts the light to extended sRGB, scales by intensity, and clamps each component to [min(0, c), max(1, c)]. sRGB lights match the pre-ASKI-99 0...1 saturation at every intensity; a Display P3 light outside sRGB keeps its extended components at intensity <= 1 and saturates at them above 1. Pinned by EffectColorSpaceTests (sRGBTaggedPointLightMatchesLegacyConstruction, outOfGamutP3PointLight*). A redesign of the intensity model here should revisit that clamp together with the alpha accumulation.

Root cause (2026-11-13): CIAdditionCompositing sums alpha along with color, so the light field (opaque black seed + each light + ambient) reached alpha 3 with one light, one more per added light. CIMultiplyCompositing kept that alpha, and converting to the output color space divided the premultiplied color by it, encoded the result and multiplied the alpha back in; that arithmetic reproduces the reported (255, 81, 33) exactly. The same excess alpha made semi-transparent inputs opaque. Fix: settingAlphaOne(in:) on the summed field, which keeps its premultiplied RGB. A probe ruled out CIColorClamp with a maximum alpha of 1: it unpremultiplies first and gave (124, 27, 11).

Intended meaning (AC#1): lit = albedo × (ambient + Σ light color × intensity × falloff), summed in linear light; the image keeps its alpha. Over white, a light of intensity 1 with ambient 0 gives the light color at its center, and ambient alone gives the ambient gray. Independent references, both owner source: Godot 4's 2D canvas shader multiplies the albedo by CanvasModulate (ambient) and adds albedo × light color × energy, RGB only, in BLEND_MODE_ADD (https://raw.githubusercontent.com/godotengine/godot/master/servers/rendering/renderer_rd/shaders/canvas.glsl); Unity URP 2D sets each light to intensity × color with alpha 1 (https://raw.githubusercontent.com/Unity-Technologies/Graphics/master/Packages/com.unity.render-pipelines.universal/Runtime/2D/Passes/Utility/RendererLighting.cs) and computes color × summed light, then restores the surface alpha (https://raw.githubusercontent.com/Unity-Technologies/Graphics/master/Packages/com.unity.render-pipelines.universal/Shaders/2D/Include/CombinedShapeLightShared.hlsl). Apple documents no formula for CIAdditionCompositing or CIMultiplyCompositing; W3C Compositing and Blending Level 1 defines plus with αo = αs + αb and limits values to [0, 1] (https://www.w3.org/TR/compositing-1/). The intensity model from ruling R6 (encoded extended-sRGB scaling and its clamp) is unchanged, so the clamp needed no revisit.

Before/after (AC#2, AC#3), sRGB (0.8, 0.2, 0.1) light, intensity 1, over white: ambient 0, sRGB output (255, 81, 33) → (204, 51, 25), Display P3 output (255, 107, 62) → (188, 65, 41) (expected P3 light color); ambient 0.5 (255, 243, 232) → (233, 136, 130); half-alpha white input, alpha 255 → 128. A Display P3-tagged light matches its own color within 1/255 in both outputs. No golden or snapshot uses lighting and the frozen preset does not light, so no golden moved; CHANGELOG and the Effects guide state the brightness change and the model.

Tests (EffectColorSpaceTests): pointLightOnWhiteMatchesItsOwnColor (sRGB and P3 lights × sRGB and P3 output), ambientOnWhiteMatchesEncodedSRGBGray, pointLightAndAmbientAddInLinearSpace, twoPointLightsAddInLinearSpace, pointLightingPreservesInputAlpha. On unchanged production every light case failed with the bug's values (8 issues); the ambient-only and fully transparent cases passed, as expected. legacyLightCenter keeps pinning the pre-ASKI-99 light-color construction with an opaque field. Implemented by a Codex worker (gpt-6.1-sol); render tests ran outside its sandbox because Core Image renders return zeros inside it. Follow-up with the same alpha accumulation: ASKI-110 (chromatic aberration and the RGB-split fallback).

Verified 2026-11-13 with Xcode 27.0 (27A266a), Apple Swift 6.4, macOS 27.0.1: the focused lighting and effects suites passed 33 tests; just check passed 1542 core, 177 serialized media and 2 deadlock tests, plus drift checks and DocC, on the tree of this change before this note was added. No exact golden moved.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Made the summed point-light field opaque (settingAlphaOne) before it multiplies the image, so a light of intensity 1 over white renders its own color, lights and ambient add in linear light, and lighting keeps the image's alpha. Pinned the meaning with independent-oracle tests in sRGB and Display P3, documented it in the Effects guide and the PointLight/LightingOptions symbols, and recorded the brightness change in the CHANGELOG. Filed ASKI-110 for the same alpha accumulation in chromatic aberration.
<!-- SECTION:FINAL_SUMMARY:END -->
