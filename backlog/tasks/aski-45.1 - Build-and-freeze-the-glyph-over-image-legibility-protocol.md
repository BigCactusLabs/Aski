---
id: ASKI-45.1
title: Build and freeze the glyph-over-image legibility protocol
status: To Do
assignee: []
created_date: '2026-08-21 00:42'
updated_date: '2026-09-10 04:31'
labels:
  - research
  - accessibility
  - color-science
  - masking
dependencies:
  - ASKI-43
references:
  - 'Source tracker issue #15 (not migrated)'
documentation:
  - docs/Research/
modified_files:
  - Tools/AskiAccessLab/Legibility
  - docs/Research/Corpus/glyph-legibility-v1
  - docs/Research/2026-08-20-glyph-legibility-protocol.md
parent_task_id: ASKI-45
priority: low
type: spike
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build and calibrate the deterministic research harness for automatic glyph-over-image legibility treatments, then freeze the protocol before any held-out evaluation.

Add a `legibility` subcommand to the existing `AskiAccessLab`; do not create another executable. The command reads a versioned corpus manifest and a machine-readable protocol, renders actual Aski glyph pixels, evaluates the complete candidate set, writes row-level measurements/contact sheets, and supports `development` and `held-out` splits. This task may run only the development split.

The v1 candidate set is fixed:

1. No-treatment baseline.
2. Opaque dark ground `#080808`.
3. Opaque light ground `#F7F7F7`.
4. Dark/light solid grounds at alpha `0.35, 0.50, 0.65, 0.80, 1.00`.
5. Source-image fog: Gaussian radius `0.5, 1.0, 2.0 × glyphWidth`, then dark/light overlay alpha `0.20, 0.35, 0.50`.
6. Dark/light glyph halos at width `0.06, 0.10, 0.14 × glyphWidth`, rounded to the nearest half pixel with a one-pixel minimum.

The corpus is `docs/Research/Corpus/glyph-legibility-v1/`: 24 static fixtures, evenly split development/held-out and stratified across portraits, landscapes, architecture, foliage/high-frequency texture, night scenes, and synthetic edge-collision scenes. Every stratum contributes two fixtures to each split. Each manifest row declares source/mask paths and hashes, provenance/license, split, source color space, hard/soft/inverted mask mode, valid column counts from `64, 128, 256, 384`, and optional deterministic motion metadata. The temporal subset uses four declared 48-frame/12-fps (four-second) transforms generated from corpus sources rather than committed frame duplication.

The harness derives an intrinsic glyph-alpha image by copying the grid with coverage `1`, no fallback, and no ground, then rendering on clear. Ink pixels are alpha `>= 0.25`. It records: alpha-weighted P10/P50 local WCAG-style contrast between unpremultiplied glyph color and active backing; normalized Sobel background-edge energy within a one-pixel dilation of glyph edges; treated/source Sobel detail-retention ratio; mean DeltaEOK from source; fraction of mask pixels with DeltaEOK `> 0.02`; treatment parameters; wall time; and peak additional allocation. These are diagnostics, not accessibility-conformance claims.

Development calibration freezes one region-level selector and one temporal hysteresis rule. Candidate selection first requires contrast P10 at least `max(1.6, 0.95 × betterFixedControlP10)` and edge interference no worse than `1.05 × betterFixedControl`; among admissible candidates it maximizes detail retention, then minimizes changed-pixel fraction, opacity, and a documented stable candidate order. If none qualify, select the better opaque fixed control, ties to dark. Across frames, require the same challenger to win three consecutive frames before switching; allow an immediate switch only when the current treatment falls below P10 `1.3` and the challenger reaches `1.6`.

The frozen human protocol requires exactly three independent reviewers for every held-out fixture/render combination. Each reviewer records `automatic`, `fixed`, or `no_preference`, confidence `1...5`, and artifact flags without seeing candidate identity or automated metrics. A pair counts as an automatic preference only when at least two reviewers choose automatic; `no_preference` never counts toward the automatic numerator. Missing reviews invalidate the human gate rather than shrinking its denominator.

Temporal excess delta is fixed as follows: convert selected-treatment and no-treatment frames to linear sRGB; for each adjacent pair compute the mean absolute RGB pixel delta; subtract the no-treatment delta from the selected-treatment delta and clamp at zero; report p95 over every adjacent pair. The switch-rate denominator is sequence duration in seconds, so each four-second sequence permits at most two treatment switches.

The task ends by committing protocol v1 with exact formulas, corpus hashes, deterministic tie order, calibrated performance reference, and frozen KEEP/KILL gates. It must not inspect or render held-out fixtures.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `AskiAccessLab legibility --corpus <dir> --protocol <json> --split development|held-out --output-dir <dir>` is deterministic, documented in `--help`, and added to the command-surface golden.
- [ ] #2 The implementation is isolated under `Tools/AskiAccessLab/Legibility/` with separate corpus/protocol parsing, treatment rendering, metrics, selection, temporal evaluation, results, and contact-sheet units.
- [ ] #3 `glyph-legibility-v1` contains exactly 24 hashed/provenanced static fixtures, 12 per split, with two fixtures per scene stratum per split and explicit mask/color-space/column metadata.
- [ ] #4 Four deterministic temporal sequences are generated from manifest transforms at 48 frames and 12 fps (four seconds); frame generation is byte-stable for a fixed toolchain/SDK and does not duplicate source assets.
- [ ] #5 The candidate set and parameter grids exactly match the task description; no extra candidate enters v1 after development results are viewed without incrementing the protocol version.
- [ ] #6 Intrinsic glyph-alpha extraction uses coverage 1 and no fallback/ground; ink pixels use alpha `>= 0.25`; P10/P50 contrast, edge interference, detail retention, DeltaEOK/source change, runtime, and allocation formulas are unit-tested against hand-computable fixtures.
- [ ] #7 The region selector uses the stated admissibility thresholds and deterministic tie order; the temporal selector uses three-frame confirmation plus the stated emergency switch rule.
- [ ] #8 Development output includes row-level CSV, summary JSON, labeled normal-size and zoomed contact sheets, and a manifest recording command, Aski SHA, protocol hash, corpus hash, OS, SDK, and toolchain.
- [ ] #9 A research note records development findings and calibrates only the performance reference/budgets; it does not report held-out metrics.
- [ ] #10 Protocol v1 is committed with `frozen: true`, exact corpus asset hashes, candidate order, formulas, thresholds, temporal rules, performance budgets, and KEEP/KILL gates before ASKI-45.2 starts.
- [ ] #11 Tests prove `--split held-out` refuses when the protocol is draft, corpus/protocol hashes mismatch, or `heldOutConsumed == true`; a development run cannot mutate the held-out consumption marker.
- [ ] #12 Protocol v1 fixes exactly three blinded independent reviews per held-out fixture/render combination; pair preference uses a 2-of-3 majority, `no_preference` is not automatic, and missing reviews invalidate rather than reduce the denominator.
- [ ] #13 Temporal excess delta uses adjacent-frame mean absolute linear-sRGB change minus the no-treatment baseline, clamped at zero; p95 is reported and four-second sequences permit at most two treatment switches.
- [ ] #14 `just research-check`, focused AccessLab tests, command-surface golden, and `just check` pass without adding public Aski API or changing product defaults.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Development-only lab and protocol tests, `just research-check`, and `just check` pass.
- [ ] #2 Protocol v1 is committed as frozen with corpus/protocol hashes and held-out-unconsumed evidence.
- [ ] #3 Command-surface documentation and golden files are intentionally updated.
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
### File map

Create a focused `Tools/AskiAccessLab/Legibility/` directory:

- `LegibilityCommand.swift`: ArgumentParser surface and provenance options.
- `LegibilityCorpus.swift`: manifest models, SHA-256 verification, split filtering, and deterministic transform generation.
- `LegibilityProtocol.swift`: protocol schema/version/frozen-state validation and stable candidate order.
- `LegibilityTreatment.swift`: lab-local candidate enum and exact parameter expansion.
- `LegibilityRenderer.swift`: same-source grid/fallback rendering, intrinsic glyph-alpha extraction, solid/fog/halo treatment images.
- `LegibilityMetrics.swift`: pixel readers, quantiles, Sobel metrics, DeltaEOK/source-change metrics, runtime/allocation samples.
- `LegibilitySelection.swift`: region selector and temporal hysteresis state machine.
- `LegibilityResults.swift`: CSV/JSON/provenance writing.
- `LegibilityContactSheet.swift`: deterministic labels and seeded pair order.

Add matching focused test files under `Tests/AskiTests/` and register the subcommand in `AskiAccessLabCommand.configuration`.

### Development workflow

1. Write protocol/corpus decoding tests first, including unknown schema versions, duplicate fixture IDs, path escapes, hash mismatches, invalid split balance, and unsupported color-space/mask values.
2. Add the 24-fixture manifest and provenance before treatment code. Reuse suitable public-domain repository corpus assets where they meet the strata; add only missing fixtures and keep licenses explicit.
3. Implement intrinsic glyph-alpha extraction and hand-computable 8×8 metric fixtures. Quantiles use nearest-rank over alpha-weighted samples; Sobel magnitudes are computed in linear-light luminance and normalized by `4 * sqrt(2)`; zero-denominator detail retention resolves to `1` only when both source and treated energy are zero, otherwise `0`.
4. Implement candidates in the fixed enum order: none, dark fixed, light fixed, solid sweep dark then light by ascending alpha, fog dark then light by radius then alpha, halo dark then light by width. This order is the final tie-breaker and is serialized into the protocol.
5. Implement selection and temporal hysteresis as pure functions with table-driven tests for thresholds, ties, confirmation windows, emergency switching, and non-finite metric rejection. Implement temporal excess delta as `max(0, meanAbsLinearRGB(selected[t]-selected[t-1]) - meanAbsLinearRGB(baseline[t]-baseline[t-1]))`; p95 uses nearest-rank over all adjacent pairs.
6. Write results/provenance/contact-sheet output and verify a repeated development run produces identical row ordering, summary values, treatment selections, and contact-sheet labels.
7. Run the full development split. Use it only to record the reference-machine performance distribution and set two budgets: p50 analyzer time no more than 25% of p50 Aski render time, and peak additional memory no more than two RGBA output buffers. Do not alter static/temporal quality gates.
8. Commit `docs/Research/2026-08-20-glyph-legibility-protocol.md` and `protocol-v1.json` with `frozen: true`; record the exact corpus/protocol hashes and explicitly state that held-out assets were not rendered.

### Frozen KEEP gates written by this task

ASKI-45.2 may return KEEP only when all hold on held-out data:

- Median automatic P10 contrast is at least 95% of the per-fixture better opaque fixed control.
- No more than 5% of fixture/render combinations regress P10 contrast by more than 10% versus that control.
- Median detail retention improves by at least 0.10 absolute versus that control.
- Exactly three blinded reviewers judge every held-out fixture/render pair; a 2-of-3 majority defines the pair verdict. Automatic wins at least 60% of pair verdicts, with no scene stratum below 50%; missing reviews fail the gate.
- Each four-second sequence has at most two treatment switches, and p95 treatment-induced excess adjacent-frame mean absolute linear-sRGB delta is at most 0.02.
- The frozen performance and memory budgets pass.

Any failed gate is KILL; there is no weighted aggregate override.

### Verification

```bash
xcrun swift test --filter 'LegibilityCorpusTests|LegibilityProtocolTests|LegibilityMetricsTests'
xcrun swift test --filter 'LegibilitySelectionTests|LegibilityResultsTests'
ASKI_RECORD_COMMAND_SURFACE=1 xcrun swift test --filter CommandSurfaceGoldenTests
swift run AskiAccessLab legibility --corpus docs/Research/Corpus/glyph-legibility-v1 --protocol docs/Research/Corpus/glyph-legibility-v1/protocol-v1.json --split development --output-dir /tmp/aski-legibility-dev
just research-check
just check
```
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design pass completed 2026-08-20. Development execution has not started; held-out fixtures remain out of bounds.

Board audit 2026-08-24 (deep pass): Cost flag for scheduling: AC#3 demands 24 hashed, provenanced, licensed fixtures across six strata plus three independent human reviewers per pair — heavy for a Low task; surface to owner before scheduling.

### Implementer context — 2026-09-10 (base 952529a)

Current state: ASKI-45.1 is To Do; its task record says development has not started and held-out fixtures remain out of bounds. `Tools/AskiAccessLab/` contains only the existing audit units (`AccessLabArguments`, `AccessFixtures`, `AccessScoring`, `AccessLabResults`, CVD model, command/CLI). The planned `Tools/AskiAccessLab/Legibility/` directory, `glyph-legibility-v1` corpus, `protocol-v1.json`, and `2026-08-20-glyph-legibility-protocol.md` are all missing.

Start here: extend `AskiAccessLabCommand.configuration` with the new subcommand; the current list is only `[AccessLabAuditCommand.self]`. `Tools/AskiCLI/AskiCommand.swift` reuses that list under `aski lab accessibility`, so the canonical surface changes with the replay surface. `Tests/AskiTests/CommandSurfaceGoldenTests.swift` includes both `AskiAccessLab` and `aski lab accessibility`; an intentional command change requires the golden update after prose docs are updated. `Package.swift` already declares `AskiAccessLab` as a library target at `Tools/AskiAccessLab`, so no new executable is needed.

Constraints and dependencies: build separate corpus/protocol parsing, treatment, renderer, metrics, selector, temporal, result, and contact-sheet units under the planned directory. Freeze exactly 24 static fixtures (12 development and 12 held-out), two per each of six strata in each split, with hashes, provenance/license, mask mode, color space, valid columns, and four declared transform-based temporal sequences. Candidate order and formulas are fixed by the task, including intrinsic alpha from coverage 1/no fallback/no ground, contrast and Sobel/DeltaEOK diagnostics, selector thresholds, three-frame hysteresis, and emergency switching. Human protocol is exactly three blinded independent reviews per pair; `no_preference` is not automatic and missing rows fail the denominator. Do not add a public API or inspect/render held-out assets.

Validation to run: future focused parser/metric/selection/result tests should cover unknown schema, duplicate IDs, path escapes, hash mismatch, hand-computable 8×8 metrics, non-finite rejection, tie order, hysteresis, and held-out refusal. The task's future development command is `swift run aski lab accessibility legibility ... --split development`, but that command is not present now. Existing checks verified from the current recipe are `just research-check` (BuildResearchIndex check) and `just check`; include the command-surface golden.

First step: add corpus/protocol decoding and refusal tests before treatment code or corpus assets, then add only development fixtures and run the development split to set performance reference/budgets. The completed freeze must include all 24 manifest fixtures and exact hashes, while development inspection/rendering remains restricted to its 12-fixture split. Commit the frozen protocol before handing off to 45.2.

Source map: `Tools/AskiAccessLab/AskiAccessLabCommand.swift`, `Tests/AskiTests/AskiAccessLabArgumentsTests.swift`, `docs/Research/Corpus/README.md`, `docs/agents/research-methodology.md`.
<!-- SECTION:NOTES:END -->
