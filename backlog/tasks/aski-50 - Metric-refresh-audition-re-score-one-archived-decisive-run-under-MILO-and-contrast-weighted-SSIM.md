---
id: ASKI-50
title: >-
  Metric refresh audition: re-score one archived decisive run under MILO and
  contrast-weighted SSIM
status: Done
assignee:
  - '@codex'
created_date: '2026-08-24 02:35'
updated_date: '2026-09-04 07:01'
labels:
  - research
  - oracle
dependencies: []
references:
  - docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md
  - >-
    docs/Research/Results/2026-09-04-aski29-50-steerable-metric-replay/result.yaml
documentation:
  - docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md
modified_files:
  - Scripts/research/score-milo.py
  - Tools/AskiColorLab/ShapeResidual/SteerableMetricReplay.swift
  - docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md
priority: medium
type: spike
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Lab-only, one-session audition proposed by the Discoveries entry of 2026-07-29, "Metric refresh audition: MILO + contrast-weighted SSIM as confidence check on the kill record" (docs/Research/Discoveries.md). That entry says: "MILO (arXiv 2509.01411, Sep 2025): lightweight full-reference metric with an explicit visual-masking model, usable as a differentiable loss. Cheap audition: re-run ONE archived decisive run (steerable channel, ASTSK-42) under MILO and contrast-weighted SSIM. If verdicts hold, confidence in the kill record rises for the cost of a re-score; if one flips, the oracle-agreement protocol fires (ASTSK-27 lesson: agreeing oracles or no verdict). Instrument only - never a shipping dependency."

Why now: ASKI-27 settled MAE as the house per-cell oracle and disqualified GMSD and HaarPSI from defining an optimum, and ASKI-32 is the open calibration task that buys back the one piece of evidence ASKI-27 claimed and did not have. The house-oracle argument currently rests on a five-metric panel that shares a structure-metric bias (GMSD and HaarPSI are not a disjoint pair) plus plain MAE and RMSE. MILO adds an explicitly masking-aware metric and contrast-weighted SSIM (arXiv 2304.12152, halftoning structure/tone split) adds a tone-aware structure metric, so the audition either strengthens the MAE choice by agreement or breaks it by disagreement. Either outcome is cheap: the archived ASTSK-42 steerable-channel run has stored artifacts, so this is a re-score, not a re-run of the experiment.

Scope guard: instrument only. No Sources change, no default change, no verdict is reversed by this task on its own - a flip fires the oracle-agreement protocol (ASKI-27) rather than settling anything.

Related: docs/Research/2026-08-19-house-oracle-audit.md, docs/Research/2026-06-27-astsk42-steerable-channel.md, Tools/AskiColorLab/ShapeResidual/ scoring battery, Tools/AskiToolSupport/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The archived ASTSK-42 steerable-channel decisive run is re-scored under MILO and contrast-weighted SSIM from its stored artifacts, with the corpus and sampling regime named
- [x] #2 The re-scored verdict is reported as held or flipped for each new metric, alongside the original GMSD and HaarPSI numbers and the MAE house-oracle number
- [x] #3 If any metric flips the verdict, the ASKI-27 oracle-agreement protocol is invoked and the disagreement is written up rather than adjudicated by the new metric alone
- [x] #4 Result is recorded as instrument evidence for or against MAE as house oracle, and cross-referenced from ASKI-32; no Sources/ change and no default change lands from this task
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Freeze and commit one shared current-path replay contract before measurement.
2. Add a lab-only exact-lattice ASTSK-42 replay with shipping and historical-support regimes, five independent pixel oracles, and a parity census.
3. Score MILO with the pinned official model outside SwiftPM, finalize the fixed rule once, and commit the artifacts.
4. Update research records, cross-references, generated indexes, task evidence, and repo map.
5. Run focused tests and the full local gate; commit locally without changing Sources or defaults.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24 (deep pass): AC#1 overstates: no ASTSK-42 run artifacts are committed (only the corpus PNGs; git-lfs empty), so arms must be regenerated via SteerableChannelCommand — cheaper than a new experiment but not a pure re-score. OVERLAP: one regeneration can also serve ASKI-29 AC#1.

ASKI-66 lattice audit (2026-09-04): the ASTSK-42 source artifacts are absent and its original 3072-square battery was non-exact at every frozen column. Any regeneration for the MILO and contrast-weighted SSIM audition must use a declared exact lattice and record descriptor support; do not reconstruct the old truncating cells. This can still overlap ASKI-29, but lattice validity and shipping-support transfer must be reported separately.

Executed 2026-09-04 from pre-registered rule commit bcc67b2 and clean runner commit 7f2f73c. The task record correctly warned that the June cell pairs were absent, so no unavailable artifact was fabricated: a current exact-lattice ASTSK-42-style comparison was regenerated and the June GMSD-only record stayed separate. Pinned official MILO raw error and exact equation-27 CSSIM both HELD the KILL at shipping 3/60 and at the separate 48/60 comparator. MAE, GMSD, and 1-HaarPSI also HELD; therefore the ASKI-27 disagreement protocol did not fire. The MILO runner and weight hashes are committed with the result. No Sources, default, or SwiftPM dependency changed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DONE. MILO and contrast-weighted SSIM corroborated the archived steerable-channel KILL in both declared exact-lattice regimes. All five metrics agreed, so there was no oracle split to adjudicate. The result supports the no-reversal record and leaves MAE as house oracle; MILO remains an external lab-only comparator.
<!-- SECTION:FINAL_SUMMARY:END -->
