---
id: ASKI-102
title: >-
  Point lights over-brighten: the light field's alpha exceeds 1 before the
  multiply
status: To Do
assignee: []
created_date: '2026-11-10T02:41:00Z'
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
- [ ] #1 Document the intended meaning of PointLight.intensity and ambient (what a light of intensity 1 over white should produce) with an independent reference
- [ ] #2 The lighting composite matches that meaning within 1/255 at the light center, for sRGB and Display P3 outputs
- [ ] #3 Moved lighting goldens are re-recorded with a before/after note and the CHANGELOG explains the brightness change
<!-- AC:END -->
