---
id: ASKI-85
title: >-
  Arbiter sitting: is an all-blank or few-glyph logPolar render worse than a
  tone ramp of the same charset?
status: To Do
assignee: []
created_date: '2026-09-27 21:12'
labels:
  - research
  - arbiter
  - matcher
dependencies: []
priority: low
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-79/80 found that per-cell oracles cannot judge blank collapse. On the five blank-collapsed charsets (minimal, dots, diagonal, cross, diamond), logPolar renders every cell as a space. The ASKI-79 arm-1 tone fallback turns that into a tone ramp. Against the blank grid, the ramp's GMSD is x1.16-1.91 (GMSD prefers blank) and its MAE is x0.98-1.08 (barely separates them). The arm was KILLed on standard MAE, so the per-cell gate never tested the question that matters for the sparse sets: whether people find the blank grid worse. Only a perceptual instrument can settle it. Evidence: docs/Research/2026-09-27-aski-79-80-orthogonality-fallback.md section 6, docs/Research/Discoveries.md 2026-09-27 entry, and the methodology rule added to docs/agents/research-methodology.md. The arbiter is the ASKI-56 protocol; converter-level arms need ASKI-62 (arbiter v2).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Arms and fixtures are pre-registered before the sitting: production logPolar (blank) vs the ASKI-79 arm-1 fallback (tone ramp) on at least minimal and dots at 80 columns on nasa-steerable-v1, with dotMatrix on the same charset as a reference arm
- [ ] #2 The sitting runs under the arbiter protocol (ASKI-56, converter-level arms per ASKI-62), with the decision rule and JND bar frozen in a committed rule note before any trial is scored
- [ ] #3 The verdict states whether the blank grid loses to the tone ramp, and whether that justifies re-registering an ASKI-79 fix gated on the arbiter instead of per-cell MAE (Discoveries 2026-09-27 'Revisit if')
- [ ] #4 The outcome is recorded as a research note whatever the sign
<!-- AC:END -->
