---
id: ASKI-85
title: >-
  Arbiter sitting: is an all-blank or few-glyph logPolar render worse than a
  tone ramp of the same charset?
status: To Do
assignee: []
created_date: '2026-09-27T21:12:00Z'
updated_date: '2026-11-24T20:22:53Z'
labels:
  - research
  - arbiter
  - matcher
dependencies:
  - ASKI-62
priority: low
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-79/80 found that per-cell oracles cannot judge blank collapse. On the five blank-collapsed charsets (minimal, dots, diagonal, cross, diamond), logPolar renders every cell as a space. The ASKI-79 arm-1 tone fallback turns that into a tone ramp. Against the blank grid, the ramp's GMSD is x1.16-1.91 (GMSD prefers blank) and its MAE is x0.98-1.08 (barely separates them). The arm was KILLed on standard MAE, so the per-cell gate never tested the question that matters for the sparse sets: whether people find the blank grid worse. Only a perceptual instrument can settle it. Evidence: docs/Research/2026-09-27-aski-79-80-orthogonality-fallback.md section 6, docs/Research/Discoveries.md 2026-09-27 entry, and the methodology rule added to docs/agents/research-methodology.md. The arbiter is the ASKI-56 protocol; converter-level arms need ASKI-62 (arbiter v2).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Arms and fixtures are pre-registered before the sitting: production logPolar (blank) vs the ASKI-79 arm-1 orthogonality tone fallback (SelectionCeiling arm A1, the tone ramp) on at least minimal and dots at 80 columns on nasa-steerable-v1. dotMatrix is not a scored arm; it may appear only as an unscored visual reference
- [ ] #2 The sitting runs under the arbiter once ASKI-62's section 5.1 validation has passed, with arm A1 registered in the arbiter's arm encoding and census for this sitting without changing v2's frozen family pools, and with the decision rule and JND bar frozen in a committed rule note before any trial is scored
- [ ] #3 The verdict states whether the blank grid loses to the tone ramp, and whether that justifies re-registering an ASKI-79 fix gated on the arbiter instead of per-cell MAE (Discoveries 2026-09-27 'Revisit if')
- [ ] #4 The outcome is recorded as a research note whatever the sign
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit 2026-11-12: AC#2's 'converter-level arms per ASKI-62' does not fit: the ASKI-79 arm is a selection-ceiling arm and the dotMatrix reference is an algorithm arm, while v2's ConverterArm holds only productionInverted and productionDirect. This needs a protocol revision after ASKI-62 validates.

2026-11-13: added ASKI-62 as a dependency: the protocol revision this sitting needs follows v2's validation.

Audit 2026-11-24 (owner-approved): AC#1 and AC#2 rescoped. The dotMatrix reference was an algorithm arm that no arbiter version can express (`Arbiter.Arm` holds only selection-ceiling arms and the two converter polarity arms, Tools/AskiColorLab/Arbiter/ArbiterProtocol.swift), so it is no longer scored. The ASKI-79 arm is `SelectionCeiling.Arm.orthogonalToneFallback` (A1), which the arbiter census currently skips (Tools/AskiColorLab/Arbiter/ArbiterCensus.swift: "the arbiter protocol never registered them"). Registering A1 for this sitting is now part of this task rather than a separate protocol task. The dependency on ASKI-62 stays: the sitting needs a validated arbiter.
<!-- SECTION:NOTES:END -->
