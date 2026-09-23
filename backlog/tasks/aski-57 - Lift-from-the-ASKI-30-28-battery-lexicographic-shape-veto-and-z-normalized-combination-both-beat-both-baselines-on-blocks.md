---
id: ASKI-57
title: >-
  Lift from the ASKI-30/28 battery: lexicographic shape-veto and z-normalized
  combination both beat both baselines on blocks
status: To Do
assignee: []
created_date: '2026-08-24 17:54'
updated_date: '2026-09-10 04:29'
labels:
  - research
dependencies: []
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Both pre-registered exploratory arms cleared the frozen rule's PASS-equivalent MAE margin (<=0.97 vs production AND vs the tone-only floor) on blocks on the held-out nasa-steerable-v1 corpus, per rule section 9 (lift, not a verdict): lexicographic inversion at shapeK=6 (prune to the 6 shape-nearest of 8, rank survivors by tone) reached MAE 0.24690 — 0.4383 of production, 0.9355 of the floor; the z-normalized combination at w=10 (pooled per-charset moments) reached 0.23602 — 0.4190 of production, 0.8943 of the floor, 0.00022 behind the battery's best arm (tone-weighted T at w*=2, 0.23580). The structural finding: vetoing the two shape-worst glyphs and then ranking purely by tone already recovers most of the tone-weighted win, supporting the external precedent (Painting with Paintings, SIGGRAPH Asia 2025) that lexicographic selection beats a fragile weighted sum when tone dominates. Evidence: docs/Research/2026-08-24-aski-30-28-battery-verdict.md (lift section + R7) and docs/Research/Results/2026-08-24-aski-30-28-battery/. Any decisive run needs its own frozen rule; note ASKI-30's INCONCLUSIVE blocker (a 0.09 percent SSIM inversion vs the floor) likely applies to these arms too — resolve the perceptual discriminator (ASKI-56) first or the same demotion will fire. Instrument to-do inherited from readout R4: the census CSV does not emit meanRank for non-production arms.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A frozen decisive rule for the lexicographic and/or z-normalized arm exists before any decisive run, reusing the battery's corpus-split and baseline-pair design
- [ ] #2 The perceptual discriminator question (SSIM knife-edge inversions on blocks) is resolved or explicitly waived by the owner before a verdict is read
- [ ] #3 The census instrument emits meanRank for every arm, closing the R4 gap
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

**Current state.** `SelectionCeiling` currently contains production, floor, legacy-floor, pool-width, tone-weighted, lexicographic, and z-normalized arms. The production arm is checked against the converter's own pick. The lexicographic and z-normalized arms are present as research selectors, but their ASKI-30/28 lift was exploratory: the dated battery reports lexicographic shapeK=6 at 0.9355 of the tone-only floor and z-normalized w=10 at 0.8943, with no promoted verdict. The instrument has an explicit gap: `ArmRow` carries no per-arm `meanRank`, while the stdout summary has a `Row.meanRank`; the CSV header also has no mean-rank column. The arm-T readout is therefore still unmeasured.

**Start here.** Read `SelectionCeiling.census`, `lexicographicPick`, `zNormalizedPick`, and the production-arm parity guard. Then read the CSV and arm tests, the frozen ASKI-30/28 rule, and the battery verdict. The current tool inventory routes new runs through `swift run aski lab color selection-ceiling`; the result artifact contains the older compatibility invocation, so confirm `--help` before a decisive run and preserve the exact flags in the dated result.

**Constraints and dependencies.** Reuse the calibration/held-out corpus split and the production/floor baseline pair from the frozen rule. MAE is the house oracle; RMSE and SSIM are cross-checks that can demote, while GMSD and HaarPSI are comparators. Resolve the SSIM knife-edge or record the explicit owner waiver permitted by AC #2 before reading a verdict; an implementer cannot grant that waiver. ASKI-56's v1 arbiter sample was below its planned n, and ASKI-62 v2 now supplies the current human/default gate; no default or public API change follows from this task alone. Do not restore branches removed by ASKI-68.

**Validation to run.** Extend the research output so every arm emits mean rank without changing the production parity guard. Add independent CSV and selector tests for production, floor, lexicographic, and z-normalized arms. Run the exact-lattice, stride-1 battery over the required charsets and both corpus arms only after the rule is frozen; report MAE, cross-checks, mean rank, and failure reasons separately. Any candidate promotion must pass the applicable arbiter gate.

**First step.** Close the mean-rank instrumentation gap and write the SSIM decision into a new preregistration. Then rerun calibration and held-out measurement; treat any improvement as exploratory until the frozen rule and arbiter accept it.

Source map: `Tools/AskiColorLab/SamplingLattice/SelectionCeiling.swift`, `Tests/AskiTests/AskiColorLabSelectionCeilingArmsTests.swift`, `Tests/AskiTests/AskiColorLabSelectionCeilingCSVTests.swift`, `docs/Research/2026-08-24-aski-30-28-battery-verdict.md`.
<!-- SECTION:NOTES:END -->
