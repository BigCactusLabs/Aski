---
id: ASKI-111
title: >-
  Lab arm: taper cell ink alpha toward ground at the near-white zero-query
  cutoff (ASKI-108)
status: To Do
assignee: []
created_date: '2026-11-24T20:45:57Z'
labels:
  - research
  - matcher
dependencies: []
references:
  - docs/Research/2026-11-14-aski108-near-white-inspection.md
  - docs/Research/Results/2026-11-14-aski108-near-white/README.md
  - Tools/AskiToolSupport/FrozenRenderReference.swift
priority: low
ordinal: 112000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Filed 2026-11-24 by owner decision from the ASKI-108 inspection (docs/Research/2026-11-14-aski108-near-white-inspection.md). That inspection found a visible cutoff in the Lovell portrait sky, where cells cross the admitted-weight cutoff of 0.05 and switch abruptly to the blank, and it pre-registered one lab-only treatment in its section "Pre-registered future lab arm: taper existing ink toward ground". This task implements and evaluates exactly that arm.

The arm keeps the descriptor and the selected glyph unchanged and varies only the existing cell ink alpha after matching. For each cell with a nonzero control query, let m be the maximum pre-rejection inverted Rec.601 sample weight over the query's sample indices; gain = t*t*(3 - 2*t) with t = clamp((m - 0.05) / 0.03, 0, 1); multiply the control cell alpha by gain. Zero-query cells stay spaces. No neighbor mixing, glyph replacement, threshold change, alternative width or parameter sweep is allowed.

The note fixed the control as bc0e31f's canonical preset. PR #30 retired that preset; the package-only FrozenRenderReference preserves its recipe and is the control here. Near-white regions stay ground (ASKI-84 ruling). No production option, public API or shipping change is authorized by this task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The arm is implemented lab-only (a lab command or @_spi(AskiResearch), with no new public API or production option) exactly as the ASKI-108 note specifies it, with no parameter sweep
- [ ] #2 Before any treatment result is read, FrozenRenderReference control renders of the three ASKI-108 fixtures byte-match the committed canonical renders in docs/Research/Results/2026-11-14-aski108-near-white/, or the deviation is recorded in a dated addendum to the ASKI-108 note
- [ ] #3 The note's pre-result checks pass at the committed implementation: gains 0, 0.5 and 1 at m = 0.05, 0.065 and 0.08; distinct pixels at half gain; a changed gray-ramp transition band with the white end still ground; existing near-white ground tests pass; no control zero-query cell gains ink and every cell with m >= 0.08 keeps its control state. Any violation is recorded as KILL before fixture scoring
- [ ] #4 Blinded review runs as registered: the treatment must be chosen as less abrupt at all four portrait sky sites, with randomized sides and the key saved before review (a tie or disagreement is inconclusive), and the 21 held-out nasa-occupancy-v1 assets show no new loss of legibility and no distracting halo (any confirmed regression kills the arm)
- [ ] #5 The verdict is recorded as a research note whatever the sign, with per-fixture assessments and the unblinded key. A KILL removes the implementation and keeps the protocol and artifacts; a PASS opens a separate shipping-decision task that carries the selection-ceiling MAE/GMSD no-harm census and golden evidence
<!-- AC:END -->
