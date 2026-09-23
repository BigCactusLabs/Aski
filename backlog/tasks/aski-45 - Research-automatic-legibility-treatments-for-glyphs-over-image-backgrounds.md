---
id: ASKI-45
title: Research automatic legibility treatments for glyphs over image backgrounds
status: To Do
assignee: []
created_date: '2026-08-20 23:59'
updated_date: '2026-09-10 04:31'
labels:
  - research
  - masking
  - accessibility
  - color-science
  - motion
dependencies:
  - ASKI-43
references:
  - 'Source tracker issue #15 (not migrated)'
  - 'https://www.w3.org/WAI/WCAG22/Techniques/failures/F83'
  - 'https://pubmed.ncbi.nlm.nih.gov/12678636/'
  - 'https://pubmed.ncbi.nlm.nih.gov/12238520/'
  - 'https://doi.org/10.1177/1541931218621294'
  - >-
    https://openaccess.thecvf.com/content/CVPR2026/html/Guo_Seeing_is_Improving_Visual_Feedback_for_Iterative_Text_Layout_Refinement_CVPR_2026_paper.html
documentation:
  - docs/Research/
  - docs/Research/Discoveries.md
modified_files:
  - Tools/AskiAccessLab
  - docs/Research
priority: low
type: spike
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Parent research task for determining whether Aski should ever choose a legibility treatment automatically for source-colored glyphs over image backgrounds.

ASKI-43 remains the deterministic product answer: callers choose an active-region ground. This research may investigate automatic solid grounds, fogged/blurred source grounds, and scale-normalized halos, but it cannot add public API or change defaults.

The work is split deliberately:

- ASKI-45.1 builds the deterministic `AskiAccessLab legibility` harness, versioned corpus, exact metric definitions, candidate treatment set, development-set calibration, temporal hysteresis rule, and frozen protocol/gates.
- ASKI-45.2 runs the untouched frozen protocol on the held-out corpus and temporal subset, records human A/B review, publishes the final research note, and issues a KEEP or KILL verdict.

No held-out result may feed back into the protocol. Any metric, corpus, treatment, or threshold change after unblinding invalidates the run and requires a new protocol version and complete rerun. A product issue may be filed only after every preregistered KEEP gate passes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ASKI-45.1 delivers a deterministic legibility lab, versioned corpus, machine-readable draft protocol, development results, and a committed frozen protocol before any held-out fixture is evaluated.
- [ ] #2 ASKI-45.2 evaluates the frozen protocol without retuning, records static and temporal measurements plus human A/B adjudication, and publishes an explicit KEEP or KILL verdict.
- [ ] #3 No public API, default behavior, runtime model, network/OCR dependency, or accessibility-conformance claim is introduced by either subtask.
- [ ] #4 A product follow-up is filed only if every frozen KEEP gate passes; a failed gate yields a KILL verdict and ASKI-43 remains the product answer.
- [ ] #5 `docs/Research/Discoveries.md` is updated only when the result generalizes beyond this experiment, and the generated research index remains valid.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 ASKI-45.1 and ASKI-45.2 are complete with a recorded KEEP or KILL decision.
- [ ] #2 The final research note and generated research index are committed.
- [ ] #3 The task records either the evidence-backed product issue URL or the explicit no-issue decision.
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Complete ASKI-45.1 and review the committed protocol JSON/research note for exact corpus hashes, formulas, treatment candidates, selection policy, temporal hysteresis, performance budgets, and KEEP/KILL gates.
2. Treat the ASKI-45.1 protocol commit as immutable input. Do not begin ASKI-45.2 until the held-out split remains unopened and the protocol is marked `frozen: true`.
3. Complete ASKI-45.2 as a clean evaluation pass. Any defect that changes a metric or rendered candidate increments the protocol version and restarts the full held-out run.
4. Close this parent only after the final note, result artifacts, research index, and product-issue/no-product-issue decision are all recorded.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design pass completed 2026-08-20. Execution is decomposed into ASKI-45.1 and ASKI-45.2.

### Implementer context — 2026-09-10 (base 952529a)

Current state: ASKI-45 is a To Do parent spike. ASKI-43 is complete (PR #31, merge f761952 per its task record) and is the product answer: callers select an active-region ground. The current AskiAccessLab only exposes `audit`, which scores palette and rendered-grid CVD pairs and writes `accessibility.csv` plus `result.yaml`; no legibility harness, corpus, protocol, development result, or held-out note is present. Planned paths `Tools/AskiAccessLab/Legibility/`, `docs/Research/Corpus/glyph-legibility-v1/`, `docs/Research/2026-08-20-glyph-legibility-protocol.md`, `docs/Research/Corpus/glyph-legibility-v1/protocol-v1.json`, and `docs/Research/2026-08-20-glyph-legibility-held-out.md` are missing.

Start here: `Tools/AskiAccessLab/AskiAccessLabCommand.swift` and `AccessLabCLI.swift` show the existing command and provenance shape. The shipped ground contract is in `Sources/Aski/Masking/MaskOptions.swift`, `MaskRenderInput.swift`, `Effects/ASCIIGrid+Effects.swift`, and `Renderers/ImageRenderer.swift`: positive finite alpha selects grouped branches; inactive fallback and active ground are composed before one coverage blend; nil/zero/non-finite alpha keeps legacy behavior. `Sources/Aski/Aski.docc/Masking.md` documents the same-source disappearance use case and explicitly says this research does not make an accessibility-conformance claim.

Constraints and dependencies: do not add public API, defaults, runtime model, OCR/network dependency, or conformance claim. ASKI-45.1 must run development only, calibrate the frozen protocol, and commit `frozen: true` before ASKI-45.2. ASKI-45.2 then uses untouched held-out data. The human gate requires exactly three independent reviewers per fixture/render pair; missing reviews invalidate the denominator. A failed frozen gate means KILL and ASKI-43 remains the answer; only an all-gates KEEP can justify a separate product issue.

Validation to run: current `swift run aski lab accessibility audit --output-dir <dir> --columns <int>` is the current canonical audit command; `AskiAccessLab audit` remains a compatibility route. The planned `AskiAccessLab legibility ...` command is unavailable until 45.1 implements it. Future validation is the focused legibility suites, command-surface golden, `just research-check`, and `just check`; do not render or inspect held-out fixtures in the development phase.

First step: implement and freeze 45.1, then hand its immutable hashes and consumption marker to 45.2; do not fold held-out observations back into protocol design.

Source map: `Tools/AskiAccessLab/AccessLabCLI.swift`, `docs/Research/2026-06-04-access-lab.md`.
<!-- SECTION:NOTES:END -->
