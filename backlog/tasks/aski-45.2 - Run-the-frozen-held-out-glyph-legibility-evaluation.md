---
id: ASKI-45.2
title: Run the frozen held-out glyph-legibility evaluation
status: To Do
assignee: []
created_date: '2026-08-21 00:42'
updated_date: '2026-09-10 04:31'
labels:
  - research
  - accessibility
  - color-science
  - masking
  - motion
dependencies:
  - ASKI-45.1
references:
  - 'Source tracker issue #15 (not migrated)'
documentation:
  - docs/Research/
modified_files:
  - docs/Research/2026-08-20-glyph-legibility-held-out.md
  - docs/Research/index.json
  - docs/Research/README.md
  - docs/Research/Discoveries.md
parent_task_id: ASKI-45
priority: low
type: spike
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Execute the frozen glyph-over-image legibility protocol from ASKI-45.1 on the held-out static and temporal corpus, without changing candidate treatments, formulas, thresholds, tie order, hysteresis, or gates.

The evaluator must verify the committed corpus and protocol hashes before rendering and write outputs to a fresh directory. Held-out results are considered unblinded once the first row is emitted. Any defect that changes rendering or a metric invalidates all held-out outputs; fix the defect under a new protocol version, reset the consumption record, and rerun every held-out fixture from the beginning.

Human A/B sheets compare the automatic choice against the per-render-combination better opaque fixed control, with deterministic seeded left/right ordering and labels hidden from reviewers. Exactly three independent reviewers complete every pair and record `automatic`, `fixed`, or `no_preference`, confidence `1...5`, and artifact flags in a separate adjudication CSV. A pair counts as automatic only with at least two automatic votes; missing reviews invalidate the human gate. Reviewers do not see automated metrics before completing the sheet.

The final note reports every preregistered gate independently. There is no weighted score and no discretionary override. One failed quality, temporal, human, runtime, or memory gate produces KILL. KEEP permits filing a separate product issue; it does not change Aski API or defaults in this task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The held-out command refuses to start unless protocol v1 is frozen and the corpus/protocol hashes exactly match ASKI-45.1 outputs.
- [ ] #2 The complete held-out static split and all four temporal sequences run once into a fresh output directory with deterministic row ordering and provenance.
- [ ] #3 Candidate treatments, metric formulas, thresholds, stable order, selector, temporal hysteresis, and performance budgets are byte-for-byte/configuration-identical to the frozen protocol.
- [ ] #4 Human A/B contact sheets hide candidate identity, use deterministic seeded left/right placement, receive exactly three independent reviews per fixture/render combination, and are completed before reviewers can inspect automated metrics.
- [ ] #5 The adjudication CSV records reviewer ID, fixture/render ID, `automatic|fixed|no_preference`, confidence `1...5`, and artifact flags; 2-of-3 majority defines each pair verdict and missing reviews fail the gate instead of shrinking its denominator.
- [ ] #6 Summary JSON reports every frozen static, human, temporal, runtime, and memory gate separately with numerator/denominator and pass/fail evidence.
- [ ] #7 Any post-unblinding defect that changes a candidate pixel or metric invalidates the run, increments the protocol version, and reruns the entire held-out split; no partial result is patched in place.
- [ ] #8 The final research note records sources, exact commands/hashes, held-out results, contact sheets, limitations, and an explicit KEEP or KILL verdict with no weighted override.
- [ ] #9 KEEP files a separate product issue linking the evidence and leaves implementation out of this task; KILL records that ASKI-43 remains the product answer and files no product API issue.
- [ ] #10 `docs/Research/Discoveries.md` is updated only for a generalizable finding, `BuildResearchIndex` refreshes the generated index, and `just research-check` plus `just check` pass.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The complete frozen held-out run and blinded adjudication are recorded without retuning.
- [ ] #2 `just research-check` and `just check` pass on the final research tree.
- [ ] #3 The final note, generated index, KEEP/KILL verdict, and product-issue/no-issue decision are committed.
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Fetch the ASKI-45.1 protocol task and verify its final note, `frozen: true`, corpus hash, protocol hash, and held-out-unconsumed marker.
2. Run a dry validation command that parses and hashes inputs but does not render; archive its provenance JSON.
3. Run the full held-out command once into a new output directory. Do not open summary metrics until all static and temporal rows, contact sheets, and provenance files are complete.
4. Distribute deterministically blinded contact sheets to exactly three independent reviewers per fixture/render combination. Collect `automatic|fixed|no_preference`, confidence `1...5`, and artifact flags with no automated results visible; validate all three rows exist before computing a 2-of-3 pair verdict.
5. Run the frozen gate evaluator. Inspect each gate independently; do not alter thresholds or drop outliers after viewing results.
6. If an implementation defect is found, mark the run invalid in the note, create protocol v2 under ASKI-45.1 scope, and restart from step 1. Statistical disappointment is not a defect and does not permit retuning.
7. Write `docs/Research/2026-08-20-glyph-legibility-held-out.md`, refresh `docs/Research/index.json`/README through `BuildResearchIndex`, and update `Discoveries.md` only when warranted.
8. On KEEP, file one product issue with the frozen evidence; on KILL, file none. Record the issue URL or the explicit no-issue decision in the task notes.

Verification commands:

```bash
swift run AskiAccessLab legibility --corpus docs/Research/Corpus/glyph-legibility-v1 --protocol docs/Research/Corpus/glyph-legibility-v1/protocol-v1.json --split held-out --output-dir /tmp/aski-legibility-held-out
xcrun swift test --filter 'LegibilityResultsTests|LegibilitySelectionTests'
swift run BuildResearchIndex
just research-check
just check
```
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design pass completed 2026-08-20. Held-out execution must not start before ASKI-45.1 freezes protocol v1.

### Implementer context — 2026-09-10 (base 952529a)

Current state: ASKI-45.2 is To Do and depends on 45.1. No frozen protocol, held-out corpus result, adjudication CSV, final note, or held-out result artifact exists. The current tree has only the older `AskiAccessLab audit` command and audit tests. Do not view, render, score, or inspect private responses or held-out fixtures while collecting context.

Start here: consume the committed 45.1 protocol as immutable input. Before rendering, verify `frozen: true`, exact corpus/protocol hashes, and `heldOutConsumed == false`; the task requires a dry parse/hash validation first and a fresh output directory. The first emitted row unblinds the run, so complete all static rows, four temporal sequences, contact sheets, and provenance under that frozen contract; keep automated metrics hidden from reviewers until their reviews are complete. Any post-unblinding defect that changes pixels or metrics invalidates the entire run, increments the protocol version under 45.1, and restarts from the beginning.

Constraints and dependencies: copy treatment set, formulas, thresholds, deterministic tie order, temporal hysteresis, and performance budgets byte-for-byte from frozen v1. Human sheets compare automatic selection with the per-render-combination better opaque fixed control, using deterministic seeded left/right placement and hidden identities. Exactly three independent reviewers must submit `automatic`, `fixed`, or `no_preference`, confidence `1...5`, and artifact flags for every pair before automated metrics are shown. A pair is automatic only with a 2-of-3 majority; `no_preference` does not enter the automatic numerator; missing reviews fail the gate rather than shrinking its denominator. Report each static, temporal, human, runtime, and memory gate independently; one failed gate is KILL with no weighted override.

Validation to run: the task's future command `swift run aski lab accessibility legibility --corpus docs/Research/Corpus/glyph-legibility-v1 --protocol docs/Research/Corpus/glyph-legibility-v1/protocol-v1.json --split held-out --output-dir <fresh-dir>` is planned but unavailable now. Future focused result/selection tests, `swift run BuildResearchIndex`, `just research-check`, and `just check` are required after the run. Temporal excess delta must use adjacent-frame mean absolute linear-sRGB change minus baseline, clamped at zero, p95 over all pairs; each four-second sequence permits at most two switches.

First step: wait for 45.1's frozen/unconsumed evidence, run the non-rendering hash gate, then perform exactly one complete held-out pass into a new directory. Keep the human sitting blind until all three reviews per pair are present. On KILL record ASKI-43 as the product answer and file no issue; on all-gates KEEP file one separate evidence-linked product issue only after the note and index are complete.

Source map: `Tools/AskiAccessLab/AccessLabCLI.swift`, `Tests/AskiTests/AskiAccessLabRunTests.swift`, `docs/agents/research-methodology.md`, `Sources/Aski/Aski.docc/Masking.md`.
<!-- SECTION:NOTES:END -->
