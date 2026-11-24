---
id: ASKI-113
title: >-
  Arbiter sitting: does the ASKI-30 tone-weighted blocks pick T(w=2) beat the
  tone-only floor perceptually?
status: To Do
assignee: []
created_date: '2026-11-24T20:58:27Z'
labels:
  - research
  - arbiter
  - matcher
dependencies:
  - ASKI-62
references:
  - docs/Research/2026-08-24-aski-30-28-battery-verdict.md
  - docs/Research/2026-08-27-aski56-arbiter-verdict.md
priority: low
ordinal: 114000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-30 ended INCONCLUSIVE (docs/Research/2026-08-24-aski-30-28-battery-verdict.md). At the calibrated w*=2 on blocks, the tone-weighted selector T cleared every MAE gate decisively (0.4186 of production, 0.8935 of the tone-only floor F, no-harm passed, RMSE agreeing), but single-scale SSIM inverted against F by 0.00026 raw (-0.09%), and the frozen rule's demotion clause had no epsilon. Its final summary names the reopening path: a perceptual discriminator, not another reconstruction run.

The ASKI-56 v1 arbiter showed T(w=2) versus F to the blinded owner once per source (family D): T won 1 of 4 decided trials with 2 ties, and the VLM's order-inconsistency was 0.50 (docs/Research/2026-08-27-aski56-arbiter-verdict.md). That is weak evidence for F, far below the standing 30 decided non-repeat trials for a verdict. Arbiter v2's D family again holds only six such pairs and is recorded, not gated. No task owned this reopen until now (ASKI-57 covers only the exploratory lift; see the ASKI-30 and ASKI-107 audit notes).

This task runs a dedicated sitting large enough for a verdict on T versus F. It does not change any default; a winning T becomes a promotion candidate in its own task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A committed rule note, frozen before any trial is scored, pre-registers T(w=2) versus F on blocks at 80 columns (the ASKI-30 operating point), the sources and crops, a trial budget sized to reach at least 30 decided non-repeat trials, side randomization and delayed repeats, and the outcome when fewer than 30 trials are decided
- [ ] #2 The sitting runs under the arbiter once ASKI-62's section 5.1 validation has passed, with the decision rule and JND bar frozen in the rule note and the VLM leg under the pinned judge
- [ ] #3 The verdict states whether T beats F perceptually, and so whether ASKI-30's INCONCLUSIVE demotion stands or T becomes a promotion candidate; a candidate goes to its own task carrying the frozen-reference no-harm census and golden evidence
- [ ] #4 The outcome is recorded as a research note whatever the sign, linked from ASKI-30 and the ASKI-56 verdict
<!-- AC:END -->
