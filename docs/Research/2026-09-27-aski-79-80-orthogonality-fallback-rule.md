---
title: "Pre-registered verdict rule — ASKI-79 + ASKI-80 orthogonality-to-tone fallback, frozen before the decisive run"
slug: 2026-09-27-aski-79-80-orthogonality-fallback-rule
date: 2026-09-27
status: active
subsystem: [shape-context]
summary: "The frozen PASS/KILL/INCONCLUSIVE rule for the ASKI-79 blank-collapse fix candidate and the ASKI-80 texture intervention, committed after the phase-1 instrument and production baseline and before any arm-1 or arm-2 number was read. Arm 1 falls back to the tone-nearest pooled glyph when the cell's query shares no bins with any non-blank pooled candidate; arm 2 adds serial Floyd–Steinberg tone centring and is lab-only. MAE is the gating oracle, GMSD a cross-check that can demote a PASS, and texture readouts gate arm 2 and guard arm 1 on standard. The verdict corpus is nasa-steerable-v1, the held-out no-harm corpus nasa-structure-v1, and the frozen preset is also guarded on nasa-occupancy-v1, the only corpus with white-ground cells."
related_specs: [docs/Research/2026-08-24-aski-30-28-decisive-rule.md, docs/Research/2026-08-19-sampling-lattice-support-collapse.md, docs/Research/2026-08-19-selection-optimality-gap.md]
datasets: []
runners: [AskiColorLab]
next_action: "Implement arms 1 and 2 as SelectionCeiling arms, run them with arm P in the same invocation, confirm P reproduces the phase-1 baseline CSVs exactly, then apply §4 mechanically to the emitted CSVs. Do not edit any threshold here after the first arm-1 or arm-2 number is read."
---

# Pre-registered verdict rule — ASKI-79 + ASKI-80 orthogonality-to-tone fallback

- Status: **FROZEN — committed after the phase-1 instrument (`50d619f`) and production baseline (`b4892f1`), before any arm-1 or arm-2 number was read.** No threshold below may be edited after the first decisive number is read.
- Baseline: `docs/Research/Results/2026-09-27-aski-79-80-baseline/`. It holds production (arm P) only. Arm F rows are present in those CSVs but were not summarized, for the reason in §3.1.
- Precedent: `docs/Research/2026-08-24-aski-30-28-decisive-rule.md` (tie and `nan` policy, machine application from the CSV).

## 1. Purpose

At the shipping footprint every logPolar query occupies only bins 51, 54 and 56 (ASKI-55). Phase 1 measured the consequences:

- `minimal`, `dots`, `diagonal`, `cross` and `diamond` have no non-blank glyph with mass in those bins, so every cell is orthogonal and the zero-norm blank wins every cell (ASKI-79).
- On `standard`, 55–59% of picks on the PNG corpora are orthogonal and are decided by `|g|²` alone. The pick is then the lowest-norm pooled glyph, which produces same-glyph runs (ASKI-80).
- `braille` has 0% orthogonal picks on the PNG corpora. Its texture collapse comes from small non-zero overlaps, which this rule's arm 1 cannot reach.

This document fixes the arms, corpora, oracles and thresholds before either candidate is run.

## 2. Frozen instrument

- `aski lab color selection-ceiling` at `50d619f` plus only the arm code. Release build, `--oversample 2 --stride 1 --footprint 24`, inverted shape-query polarity (shipped default), density 0 (topK 12), monochrome palette, sRGB.
- Texture readouts (`glyphsUsed`, `blankShare`, `runMean`, `runP95`, `run5Share`) from the same census rows, as defined in `Tools/AskiColorLab/SamplingLattice/PickTexture.swift`.
- Columns: 80 and 288. Frozen preset: `blocks` at 76 columns.
- Corpora: `nasa-steerable-v1` is the verdict corpus. `nasa-structure-v1` is the held-out no-harm corpus. `nasa-occupancy-v1` (JPEG) is non-gating except for the frozen-preset row `frozen-76-occ` (§3.2).
- Charsets: all ten built-ins.
- Each arm runs in the same invocation as arm P. Every arm-P oracle mean must reproduce the phase-1 baseline CSV exactly; if any differs, the run is invalid and is not read. Phase 2 compares against the same-build P, never against the ASKI-31 archive (the structure-corpus P row has drifted ×0.99976 since then).

## 3. Arms

- **Arm P — production.**
- **Arm 1 — orthogonality → tone fallback.** Per cell where `cellSupportsShapeDescriptor` is true: build production's brightness pool. If every non-blank pooled candidate (`|g|² > 0`) has `q·g == 0` exactly, pick the tone-nearest pooled glyph (`poolIndices(...)[0]`, ties by index, the existing `degenerateToneRanking` order). Otherwise keep production's shape argmin. The exact-zero test needs no epsilon: bins are non-negative, and the smallest non-zero `q·g` in the baseline is 4.9e-4.
- **Arm 2 — arm 1 plus Floyd–Steinberg tone centring (lab-only).** Serial raster walk, left to right, no serpentine, mirroring `DotMatrixKernel.pick`: `target = adjustedL + e[cell]`, pool = `poolIndices(target, topK)`, arm-1 pick rule against `target`, `err = target − brightnessValues[pick]` at strength 1.0, diffused 7/16, 3/16, 5/16, 1/16 and dropped at the grid edge, target not clamped. Because the walk is serial, arm 2 cannot ship from this rule; a PASS only files a follow-up task.

### 3.1 Known in advance (H1)

On a fully orthogonal cell, arm 1 picks exactly what arm F picks. On the five blank-collapsed sets every cell is orthogonal, so arm 1 equals arm F there, and its score is already in the baseline CSVs and in the ASKI-30/28 archive. The sparse-set gain is therefore recorded as structural (§4.1 item 6) and is not the deciding test. The deciding evidence is `standard` and the no-harm rows.

### 3.2 White-ground cells (H2)

A cell whose pixels all have luma above 0.95 has an all-zero query under the shipped polarity. Today the blank wins it, so on the frozen preset pure white renders as the dark ground. Arm 1 gives it the tone-nearest glyph, which is the densest glyph, so white renders as ink. These cells are 0% of `nasa-steerable-v1`, at most 0.02% of `nasa-structure-v1`, and 13–15% of `nasa-occupancy-v1`. The PNG guard would pass without testing them, so `frozen-76-occ` is a gated no-harm row. Whether white should render as ink or as ground on the preset is a product decision that no per-cell oracle settles. Phase 2 produces a before/after render pair on a white-ground occupancy fixture for the owner, and that decision is made in PR review before merge. It does not change the verdict.

### 3.3 No area-tone oracle (H4)

Per-cell MAE penalizes error diffusion by design. This unit does not build an area-tone oracle, since a new instrument would need its own validation first. Arm 2's MAE clause is a no-harm guard only, and its deciding evidence is texture.

## 4. Decision rule

`R = MAE_arm / MAE_P`, `G = GMSD_arm / GMSD_P`, read from the CSV to four decimal places. A ratio of exactly 1.0000 is not an improvement. A `nan` never reads as a pass.

### 4.1 Arm 1 (ASKI-79 fix candidate; ASKI-80 AC#3 intervention on `standard`)

**PASS** iff all of:

1. *Defect removed.* On every fixture of `nasa-steerable-v1` and `nasa-structure-v1`, at 80 and 288 columns, each of `minimal`, `dots`, `diagonal`, `cross` and `diamond` has arm-1 `blankShare < 1.0`.
2. *Deciding charset `standard`.* `R ≤ 1.0000` on `nasa-steerable-v1` at 80 and at 288 columns, and `R ≤ 1.0100` on `nasa-structure-v1` at both.
3. *GMSD agrees.* Every item-2 comparison has `G ≤ 1.0100`. A GMSD ratio above 1.0100 where MAE passes makes the verdict INCONCLUSIVE.
4. *No harm elsewhere.* `R ≤ 1.0100` for `blocks`, `lines`, `mixed` and `braille` at 80 and 288 on both PNG corpora, and for the frozen preset (`blocks`, 76) on steerable, structure and occupancy. The record must state that the PNG rows are expected to be near-vacuous (about 0% orthogonal).
5. *Texture no-harm on `standard`.* `run5Share(arm 1) ≤ run5Share(P) + 0.02` absolute on both PNG corpora at both column counts.
6. *Sparse-set gain (structural, recorded, not deciding).* `R ≤ 0.97` for each of the five sets on `nasa-steerable-v1` at 80 columns. The note must say this equals the arm-F ratio.

**KILL** iff item 1 fails on any PNG fixture, or `R(standard) > 1.0300` on either PNG corpus at either column count, or any item-4 ratio is above 1.0300.

**INCONCLUSIVE** otherwise, naming the blocker: an item-2 or item-4 ratio in (1.0100, 1.0300], a GMSD disagreement, a failed item 5, or a failed item 6.

### 4.2 Arm 2 (ASKI-80 texture candidate; lab-only)

**PASS (files a production follow-up; ships nothing)** iff, on `standard` and on `braille`, at 288 columns, on both PNG corpora: `run5Share` falls by at least 0.10 absolute against arm 1, `glyphsUsed` rises, `R(arm 2 / arm 1) ≤ 1.0100`, and `G(arm 2 / arm 1) ≤ 1.0100`.

**KILL** iff, on `nasa-steerable-v1` at 288 columns, `run5Share` falls by less than 0.10 on both `standard` and `braille`, or `R(arm 2 / arm 1) > 1.0300` on either charset.

**INCONCLUSIVE** otherwise.

## 5. Non-gating readouts (pre-committed)

- Per charset, the share of cells whose pick changed against P, for each arm.
- Occupancy-corpus texture and MAE for every arm.
- Arm 2 at strength 0.5, labelled non-gating.
- Per-fixture `standard` `blankShare` under arm 1 next to P.

## 6. Promotion path

An arm-1 PASS licenses the production change in `LogPolarKernel` (`score`, `scoreScored` and `matchWithDescriptor` together, as the degenerate path does), goldens re-recorded with this census as the no-harm evidence, and the ASKI-79 AC#3/#4 doc and custom-set work. It does not license a default change for any charset where arm 1 was a no-op. An arm-1 KILL or INCONCLUSIVE leaves production unchanged, and ASKI-79 is instead closed by documenting the defect and removing the recommendation to pair logPolar with the blank-collapsed sets. Arm 2 files at most a follow-up task.

## 7. Out of scope

- `braille`, `blocks`, `lines` and `mixed` texture (arm 1 cannot reach them on the PNG corpora). Candidate routes are support restoration (ASKI-55), tone entering the ≤ 12-glyph pool (ASKI-30 track), or a magnitude-free distance with a tone tie-break.
- Near-orthogonal cells. The exact-zero test is a cliff by design.
