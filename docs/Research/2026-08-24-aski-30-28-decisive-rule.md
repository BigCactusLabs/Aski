---
title: "Pre-registered verdict rule — the ASKI-30 + ASKI-28 census battery, frozen before the decisive run"
slug: 2026-08-24-aski-30-28-decisive-rule
date: 2026-08-24
status: active
subsystem: [shape-context]
summary: "The frozen PASS/KILL/INCONCLUSIVE rule for the combined ASKI-30 (tone-weighted selection on sparse charsets) and ASKI-28 (brightness pre-filter width on dense charsets) census battery, committed after its instrument prerequisites landed and before any decisive number was read. Four realizable selectors are scored through one identical rendering path: P production, F a shape-free tone-only floor rebuilt on production's own tone pair, T the tone-weighted score with its pool width pinned so ASKI-30's treatment cannot be confounded with ASKI-28's, and K production's selector at a lab-supplied pool width reaching the full charset. MAE is the sole verdict oracle, RMSE and single-scale SSIM can only demote a PASS to INCONCLUSIVE, and GMSD and HaarPSI can never gate. Operating points are calibrated on nasa-structure-v1 and the verdict is read on the held-out nasa-steerable-v1 at a fixed 0.97 ratio margin against each baseline separately, with a 1.01 no-harm guard back on the calibration corpus. The two tracks gate independently. Two exploratory arms — lexicographic inversion at a frozen count-based shapeK grid, and a z-normalized score combination — are pre-registered as non-gating and cannot flip either verdict; if one fires it is split off to a new task under the lift rule. ASKI-28's expected outcome is stated as KILL in advance, since the measured pool gap sits below the bar, and the rule is written to be falsifiable in both directions regardless."
related_specs: [docs/Research/2026-08-19-selection-optimality-gap.md, docs/Research/2026-08-19-house-oracle-audit.md, docs/Research/2026-08-23-aski32-calibrated-recovery.md]
datasets: []
runners: [AskiColorLab]
next_action: "Run the battery. Calibrate w* and topK* on nasa-structure-v1, freeze them into the CSV, then run the held-out nasa-steerable-v1 sweep and apply §5 mechanically to the emitted CSV — not to the stdout table. Do not edit any threshold in this document after the first decisive number is read."
---

# Pre-registered verdict rule — ASKI-30 + ASKI-28 census battery (frozen before the decisive run)

- Target file: `docs/Research/2026-08-24-aski-30-28-decisive-rule.md`
- Status: **FROZEN — committed 2026-08-24 after the §3 prerequisites, before any decisive number was read.** No threshold below may be edited after the first decisive number is read.
- Drafted and frozen 2026-08-24. The battery had not been run when this was committed, so **no date in this document refers to an execution**; the execution date is whatever the run records, and is deliberately not asserted here. (The draft carried a literal execution-date placeholder on this line; the research registry rejects unresolved placeholders in a committed note, so the convention is stated in words instead. Header-block wording only — no threshold, arm, corpus, margin or readout is affected.)
- Battery scope: ASKI-30 (tone-weighted selection, sparse charsets) and ASKI-28 (brightness pre-filter width, dense charsets), run as ONE census over one corpus pair. Recorded as one battery at `backlog/tasks/aski-28…:29` and `backlog/tasks/aski-30…:35`.
- Precedent register: ASTSK-31 (`docs/Research/2026-06-09-shape-residual.md:101-126`) and ASTSK-41 (`docs/Research/2026-06-29-astsk41-nca-temporal-prior.md:37-70`). Deterministic point margins, machine-applied from a machine-readable artifact, explicit PASS/KILL/INCONCLUSIVE zones, pre-committed non-gating readouts, a lift rule that splits surprises into a new task, `Sources/Aski` untouched during measurement.

## 1. Purpose

The shipped matcher prunes candidates to the `topK` brightness-nearest glyphs and then takes the argmin of pure 60D shape distance inside that pool (`Sources/Aski/ShapeMatching.swift:281-306`); tone survives only as a tie-break, so on the eight built-in charsets with ≤12 glyphs the pre-filter is a literal no-op and tone is discarded at selection time (`docs/Research/2026-08-19-selection-optimality-gap.md:165-169`, `:211-216`). The characterization run measured the consequence: on `blocks` — the charset ASTSK-47 froze into the shipping preset — a shape-free ink-coverage floor beats production under all five oracles, MAE 0.24637 vs 0.56329, with the production pick averaging rank 7.22 of 8 (`docs/Research/2026-08-19-house-oracle-audit.md:254-266`). That note is explicitly a characterization, "not a PASS/KILL gate" (`docs/Research/2026-08-19-selection-optimality-gap.md:16`). This document is the gate. It fixes, before any decisive number exists, the arms, the corpora, the oracle panel, the margins, and the exact conditions under which each track PASSes, KILLs, or returns INCONCLUSIVE — so the verdict can be applied mechanically from a CSV rather than argued from a table.

## 2. Frozen instrument

### 2.1 Census geometry (identical for every arm)

`columns: 80`, `oversample: 2`, scoring `footprint: 24` px, `stride: 1` (exhaustive), monochrome palette, `colorSpace: .sRGB`. Three fixtures per corpus × 80 columns × 36 rows = **8640 scored cells per arm per (charset, corpus)** (`docs/Research/2026-08-19-selection-optimality-gap.md:93-94`; emitted per row as `cells`, `Tools/AskiColorLab/SamplingLattice/SelectionCeiling.swift:299`). Source blocks are taken through the converter's own resolved `SamplingGeometry`, never an equal `rows × cols` partition — the defect the first publication of the parent note self-corrected (`docs/Research/2026-08-19-selection-optimality-gap.md:35-41`).

### 2.2 Corpora

- **Calibration:** `nasa-structure-v1` (2048 px; `earth-limb-sunrise`, `phoenix-night-grid`, `vavilov-crater`).
- **Held out (verdict):** `nasa-steerable-v1` (3072 px; `earth-limb-sunrise`, `sahara-dunes`, `vavilov-crater`) — the `selection-ceiling` default since the `--corpus` trap was closed (`Tools/AskiColorLab/SamplingLattice/SelectionCeiling.swift:160-166`).

Every number reported by this battery names its corpus. Standing rule 4 of the house-oracle audit (`docs/Research/2026-08-19-house-oracle-audit.md:317`): the dense-charset ranking headroom straddles the +3.0% bar between corpora — 1.83–2.41% on `nasa-steerable-v1` versus 2.88–3.93% on `nasa-structure-v1` (`:203-226`) — so an unlabelled figure is not quotable.

### 2.3 Charsets

- ASKI-30 (sparse) — gating: `blocks` (8). Non-gating readouts: `diagonal` (4), `diamond` (4), `cross` (5), `dots` (8), `minimal` (10), `lines` (12), `mixed` (12).
- ASKI-28 (dense) — gating: `standard` (95), `braille` (256).
Glyph counts from `docs/Research/2026-08-19-selection-optimality-gap.md:165-169`. All ten are accepted by the subcommand (`SelectionCeiling.swift:136-149`).

### 2.4 Arms and the exact quantity each one uses

All four arms are realizable selectors and are scored through one identical rendering path, in the matcher's ink-high convention (house-oracle standing rule 2, `docs/Research/2026-08-19-house-oracle-audit.md:312-314`; ASKI-32's name-the-convention rule, `docs/Research/2026-08-23-aski32-calibrated-recovery.md:185-187`).

| arm | selector | tone quantity | score |
| --- | --- | --- | --- |
| **P** production | `ShapeMatching.findBestScored`, `topK = 12` (`density = 0`) | query `stats.adjustedL` vs `characterSet.brightnessValues` | pure 60D squared-L2 shape distance; tone = pool filter + tie-break only (`ShapeMatching.swift:281-306`) |
| **F** tone-only floor | argmin over the FULL charset of `abs(brightnessValues[i] − stats.adjustedL)`, single matcher-convention polarity | **same as P** | no shape term |
| **T** tone-weighted | `@_spi ShapeMatching.findRankedOccupancyScored`, `toneLimit` pinned to `glyphCount`, `toneWeight = w` supplied independently | **production's pair, as F** — `stats.adjustedL` vs `brightnessValues`, supplied by the lab so P/F/T differ only in the scored term | `distance + w · toneDelta²` (`ShapeMatching.swift:238`) |
| **K** pool-width | `findBestScored` with a lab-supplied `topK` | same as P | same as P |

**Arm F is re-defined by this rule.** The floor as built today compares `characterSet.rawDensityValues` against the mean of the native `block.luma` (`SelectionCeiling.swift:238-247`, `:172`), which is a different tone pair from production's. Prerequisite 3 rebuilds it on production's pair so that P, F and T differ only in the term under test. Two-polarity floors stay rejected — they hand MAE a free degree of freedom, and the single-polarity margin is the conservative one (`docs/Research/2026-08-19-selection-optimality-gap.md:108-113`).

`toneLimit` is decoupled from `topK` deliberately. Setting the shipped `occupancyMatching` scalar would simultaneously set `toneWeight = w·50`, widen the pool by `round(w·24)`, and switch the pre-filter quantity (`Sources/Aski/Algorithms/LogPolarKernel.swift:421-427`) — confounding ASKI-30's treatment with ASKI-28's. `shapeStructureAssist` and `steerableShapeAssist` stay at their defaults of 0 (selection precedence, `LogPolarKernel.swift:62-124`).

### 2.5 Sweeps

- **T:** `w ∈ {0, 1, 2, 5, 10, 25, 50}`. Range bounded by the shipped `toneWeight = occupancyMatching × 50 ∈ [0, 50]` (`RenderingOptions.swift:153-162`). `w = 0` reproduces a shape-argmin over the full pool and is a built-in sanity anchor.
- **K:** `topK ∈ {12, 18, 24, 36, 48, 64, 95}` on `standard` and `{12, 18, 24, 36, 48, 64, 128, 256}` on `braille`. Must include 12 (production), 36 (the ceiling reachable through the shipped `density` knob) and the full pool (95 / 256), per ASKI-28 AC#1.
- **Lex (exploratory arm §6.1):** `shapeK ∈ {2, 3, 4, 6}` on sparse charsets — prune to the `shapeK` shape-nearest candidates, rank survivors by tone. The grid is scale-free (a count, not a distance tolerance), and its endpoints are built-in anchors: `shapeK = 1` reproduces production's shape argmin modulo tie-break, and `shapeK = glyphCount` reproduces the tone-only floor F. Frozen here because §6.1 pre-registers the arm and an unset grid would be a post-hoc degree of freedom.
- **Cost:** wall-clock seconds for the selection phase of one 8640-cell census, per (charset, `topK`), median of 3 runs on one machine, recorded in the CSV for every point including `topK = 12`.

### 2.6 Oracle panel

MAE is the **sole verdict oracle** — the house oracle, adopted at `docs/Research/2026-08-19-house-oracle-audit.md:142-147` and reaffirmed on production geometry by ASKI-32 (`docs/Research/2026-08-23-aski32-calibrated-recovery.md:7`, parent resolution `:404-420`). RMSE (same-family) and single-scale SSIM (disjoint) are confirmatory cross-checks with exactly one power: to demote a PASS to INCONCLUSIVE when they invert the sign of the MAE verdict comparison. GMSD and HaarPSI are reported as comparators only and can never gate — they are disqualified from defining an optimum (`:309-311`). The harness runs all five unconditionally (`SelectionCeiling.swift:182`, `:249`, `:305`); the rule reads the `mae` row.

Reading conventions, pre-committed: `exactOptimal` is never quoted on sparse charsets (tie-deflated — `docs/Research/2026-08-19-selection-optimality-gap.md:325-330`); SSIM **percentages** are read on dense charsets only, because SSIM on `blocks` normalizes by a production score of 0.00214 (`docs/Research/2026-08-19-house-oracle-audit.md:296-299`) — the SSIM cross-check on `blocks` is therefore evaluated as a **raw-score direction**, not a ratio.

## 3. Prerequisites — must land BEFORE this rule is committed

All lab-side except prerequisite 0, and `Sources/Aski` stays untouched for the whole measurement.

0. **`@_spi(AskiResearch)` reflection entry point** (the sole `Sources/Aski` change, landed before the freeze). The lab cannot feed arms F/T/K today: `ShapeMatching.findBestScored` (public) and `findRankedOccupancyScored` (`@_spi`) take per-cell `queryLanes` and a query tone, but the 60D query descriptor is `private` (`LogPolarKernel.swift:429`, `:440` `extractShapeVector`) and `stats.adjustedL` is `internal` (`CellSampling.swift:12-27`), and none of the three existing research accessors (`ASCIIConverter+Research.swift:33`, `:61`; `ASCIIConverter.swift:306`) returns either — `rankedCandidateIndices` returns the pre-filter's own pool, so it caps at the width under test. Add one behavior-neutral reflection accessor on `ASCIIConverter` in the shape of the existing research surface, returning per-cell `(lanes, adjustedL)` alongside the grid. Rendering output stays byte-identical; the lab re-deriving these quantities itself is rejected on the recorded precedent that the 2026-08-19 run did exactly that and got the polarity convention wrong (`ASCIIConverter+Research.swift:5-7`). This is compatible with the "untouched" clause because that clause governs measurement: no threshold, arm, or selector semantics change, and the accessor lands before any decisive number exists.
1. **Pool-width arm parameter.** Thread a lab-only `topK` (or `--density`) through `SelectionCeiling.run(columns:oversamples:charsetNames:footprint:stride:corpus:)` (`Tools/AskiColorLab/SamplingLattice/SelectionCeiling.swift:152-159`) and the CLI wrapper (`Tools/AskiColorLab/AskiColorLabCommand.swift:534-573`). The shipped `density` knob reaches only `topK ∈ [12, 36]` (`Sources/Aski/RenderingOptions.swift:10-11`) and cannot reach 95 or 256, so arm K calls `ShapeMatching.findBestScored` (public, `Sources/Aski/ShapeMatching.swift:259-265`) directly with an arbitrary `topK`; `ShapeMatching.poolIndices(queryBrightness:candidateBrightness:topK:)` (`:8-31`, already `@_spi(AskiResearch)`) supplies the pool half.
2. **Tone-weighted arm parameters.** Add arm T to `SelectionCeiling` with `toneWeight` and `toneLimit` as independent flags, calling `@_spi(AskiResearch) ShapeMatching.findRankedOccupancyScored` (`Sources/Aski/ShapeMatching.swift:201-209`). The converter is currently constructed with no `options:` at `SelectionCeiling.swift:184-189`, so the occupancy path is unreachable from the subcommand today.
3. **Floor-quantity fix.** Rebuild arm F on `brightnessValues` vs `stats.adjustedL`, replacing the `rawDensityValues` vs mean `block.luma` comparison at `SelectionCeiling.swift:238-247`. Record the before/after floor scores on both corpora so the re-definition is auditable.
4. **Machine-readable output with provenance.** `selection-ceiling` prints a pipe table to stdout and has no `--output` and no `ProvenanceOptions` (`SelectionCeiling.swift:353-379`; contrast `AskiColorLabCommand.swift:330`). Emit CSV or JSON with one row per (corpus, charset, arm, `w`, `topK`, columns, oversample, footprint, stride, cells, glyphs, per-oracle mean, selection wall seconds, git SHA). **This rule is applied only to that file**, per the ASTSK-31 discipline (`docs/Research/2026-06-09-shape-residual.md:103-109`).
5. **Duplicate-glyph guard.** Production picks are recovered by `glyphs.firstIndex(of: picked)` (`SelectionCeiling.swift:223-224`), which would collapse indices on a charset holding a repeated character. Assert uniqueness per charset and fail the run rather than mis-attribute a pick.

## 4. Calibration protocol

Operating points are chosen on **`nasa-structure-v1`** and never on the corpus that decides the verdict.

1. Run the full sweep (§2.5) on `nasa-structure-v1`. For ASKI-30 select `w*` per charset as the `w` minimizing mean MAE on `blocks`; for ASKI-28 select `topK*` per charset as the smallest swept `topK` minimizing mean MAE.
2. Freeze `w*` and `topK*` into the CSV before the held-out run is executed.
3. Run the same sweep on **`nasa-steerable-v1`**. Each PASS condition in §5 is read at the calibrated `w*` / `topK*` only; the KILL conditions consult the full held-out sweep, because they require failure at **every** swept point. An arm that fails at its calibrated point but clears the margin at some other swept point is a calibration-transfer failure and lands in INCONCLUSIVE, never PASS.
4. Re-read the calibration corpus at the same operating point for the **no-harm guard**.

No statistical confidence intervals. The census is exhaustive (8640 cells), deterministic, and reproduces byte-for-byte; the repo's frozen rules gate on point margins (ASTSK-31 `:116-124`, ASTSK-41 `:42-45`) and this one matches them. Corpus robustness is supplied by the dual-corpus requirement, not by a CI. This is a deliberate divergence from the external recommendation of bootstrapped paired image-level CIs (El Jurdi, Varoquaux & Colliot 2025) — recorded in §11 item 6, not adopted.

## 5. Verdict bands

Margin form for both tracks: pre-registered **percentage improvement against each baseline separately**, ratio form `MAE_arm / MAE_baseline ≤ 0.97` — a ≥3.0% mean-MAE improvement, the bar this family inherits from the archived channel gates (`docs/Research/2026-06-09-shape-residual.md:11`). No band-relative or baseline-spread margin enters any verdict; a band-relative reading may appear only as a labelled sensitivity note (§8, readout R6).

The two tracks gate **independently**. A KILL on one never widens, narrows or otherwise modifies the other's bands, and neither track's outcome is evidence about the other.

### 5.1 ASKI-30 track — tone-weighted selection on sparse charsets

Gating charset: `blocks`. Baselines: **P** (production) and **F** (tone-only floor as re-defined in §2.4).

> **PASS** iff, at the calibrated `w*` on `blocks`: `MAE_T / MAE_P ≤ 0.97` on `nasa-steerable-v1` **AND** `MAE_T / MAE_F ≤ 0.97` on `nasa-steerable-v1` **AND** `MAE_T / MAE_P ≤ 1.01` on `nasa-structure-v1` **AND** `MAE_T / MAE_F ≤ 1.01` on `nasa-structure-v1` **AND** neither RMSE nor single-scale SSIM inverts the direction of either held-out comparison.
> **KILL** iff, on `nasa-steerable-v1`, `MAE_T / MAE_F ≥ 1.00` at **every** swept `w` — the arm never beats the floor at any weight — **OR** `MAE_T / MAE_P ≥ 1.00` at every swept `w`.
> **Otherwise INCONCLUSIVE**, with the blocker named. The band `0.97 < ratio < 1.00` against either baseline is deliberately inconclusive — no knife-edge verdicts.

Cross-check demotion: if the MAE comparison clears both 0.97 gates but RMSE or SSIM moves the opposite way against either baseline, the verdict is **INCONCLUSIVE**, not PASS. SSIM on `blocks` is read as a raw-score direction (§2.6).

Tie and zero policy: ratios are computed at four decimal places; a ratio of exactly `1.0000` counts as **not improved**. Where a baseline mean falls below the harness's `degenerateScoreFloor = 1e-6` the ratio is `nan` (`SelectionCeiling.swift:131-133`, `:330-333`); a `nan` cell scores as not-PASS and is never read as a win.

**AC#4 disposition, pre-committed.** If the KILL condition fires on the floor comparison — the arm cannot beat F on `blocks` at any swept `w` — the note records, from the same CSV, whether the shape term should simply be disabled for sparse charsets: report `MAE_F / MAE_P` on `blocks` and on all seven non-gating sparse charsets, on both corpora, and state whether F clears 0.97 against P on every sparse charset. Filing that as a production change requires a new task and the §7 perceptual gate; the shipped `degenerateToneRanking` path (`LogPolarKernel.swift:14-59`), which already drops the shape term and ranks on tone when the descriptor is unsupported, is the precedent to extend, not new math.

### 5.2 ASKI-28 track — pool width on dense charsets

Gating charsets: `standard` and `braille`, reported separately (AC#2). Baseline: production `topK = 12` on the same charset.

> The verdict is declared **per charset**, independently for `standard` and `braille`.
> **PASS** for a charset iff, at that charset's calibrated `topK*` (§4): `MAE_K / MAE_(topK=12) ≤ 0.97` on `nasa-steerable-v1` **AND** that point's selection wall time is `≤ 2.0 ×` the `topK = 12` time on the same charset **AND** at the same `topK*` on `nasa-structure-v1` `MAE_K / MAE_(topK=12) ≤ 1.01` **AND** neither RMSE nor SSIM inverts the direction of the held-out comparison.
> **KILL** for a charset iff, on `nasa-steerable-v1`, no swept `topK` on that charset reaches `≤ 0.97`, **or** every point on that charset that reaches `≤ 0.97` costs more than `2.0 ×` the baseline.
> **Otherwise INCONCLUSIVE** for that charset — including the calibration-transfer case (§4.3), a point clearing 0.97 on the held-out corpus but failing the 1.01 no-harm guard on `nasa-structure-v1`, or a cross-check inversion.

The cost/quality curve — mean MAE and selection wall seconds at every swept `topK`, per charset, per corpus — is recorded either way, PASS or KILL. Tie and zero policy as in §5.1.

**Expected outcome, stated honestly in advance.** The measured MAE pool gap on `nasa-steerable-v1` is 2.85% on `standard` and 2.73% on `braille` (`docs/Research/2026-08-19-selection-optimality-gap.md:141-151`), and `optPool` is an upper bound on what a wider pool can recover only in the sense that widening also "widens the descriptor's opportunity to rank badly" (`:342-343`). Both figures sit **below** the 0.97 bar, so **KILL is the expected verdict**. The rule is written to be falsifiable in both directions regardless: the sweep is exhaustive to the full pool, and a point clearing 0.97 within the cost cap is a PASS no matter how surprising.

## 6. Exploratory arms — pre-registered, non-gating

Both are recorded in the CSV, reported in the note, and **cannot flip any verdict in §5** under any result.

1. **Lexicographic inversion (sparse).** Prune to the `shapeK` shape-nearest candidates (grid frozen in §2.5), then rank the survivors by tone — the inverse of production's prune-by-tone-then-rank-by-shape. External precedent: *Painting with Paintings* (SIGGRAPH Asia 2025) retrieves top-*k* by color similarity then ranks by SSIM, avoiding the addition of incomparable scores; the codex sweep's own recommendation is that lexicographic selection is preferable to a fragile weighted sum when tone is a hard constraint.
2. **z-normalized score combination.** Per-charset normalization of the shape-loss and tone-loss distributions before weighting, replacing the fixed `toneErrorWeight = 50` scale (`RenderingOptions.swift:161`, whose own doc comment admits it only puts the terms "into the same rough magnitude range"). Reported at the same `w` grid on normalized units.

If either fires — beats both baselines by the §5.1 margin on `blocks` on the held-out corpus — it does **not** convert this battery's verdict. It is split off to a new tracked task with the evidence attached, per §9.

## 7. Perceptual gate and promotion path

A reconstruction-metric win does not license a default change (ASKI-27; ASKI-28 AC#3; ASKI-30 AC#3; `docs/Research/2026-08-19-house-oracle-audit.md:283-287`). MAE-class pixel metrics have poor perceptual relevance — a PASS supports "lower MAE", not "better-looking ASCII art".

A PASS on either track licenses exactly: **an opt-in knob, default off, byte-identical when off**, plus a follow-up task for default promotion. That follow-up is gated on a defined perceptual check — a PresetLab-style A/B contact sheet (`swift run AskiPresetLab ab --input <portrait> --output-dir <dir>`) on **real portrait fixtures**, arm versus production, reviewed and signed off by the owner. The parked VLM / human arbiter remains the missing instrument and stays parked; it is named here so no future reader mistakes the contact sheet for it.

Two standing bounds are restated because they bear on this battery's gating charset. `GlyphRaster` centres each glyph by its image bounds, which erases position-only distinctions — `▄` and `▀` become the same centred bar (`docs/Research/2026-08-19-house-oracle-audit.md:163-171`, `:301`) — and `SelectionCeiling` scores through it (`SelectionCeiling.swift:176-178`). And ASKI-32 validated the oracle on pictures of glyphs, not photographic cells; "an oracle perfect at recovering rendered glyphs may still mis-rank two wrong-but-plausible picks on a photograph" (`docs/Research/2026-08-23-aski32-calibrated-recovery.md:170-177`).

## 8. Pre-committed readouts (descriptive, non-gating)

| # | readout | granularity |
| --- | --- | --- |
| R1 | `MAE_T / MAE_P` and `MAE_T / MAE_F` at every swept `w` | 7 sparse charsets × 2 corpora |
| R2 | `MAE_F / MAE_P` — does the shape-free floor beat production | 8 sparse charsets × 2 corpora (AC#4 input) |
| R3 | Cost/quality curve: mean MAE vs selection wall seconds | `standard`, `braille` × every `topK` × 2 corpora |
| R4 | `meanRank` of the production pick and of arm T | all 10 charsets, MAE only |
| R5 | GMSD and HaarPSI comparator columns for every gating comparison | comparator label mandatory; never gating |
| R6 | Band-relative sensitivity note: the §5 margins re-read as multiples of the P-vs-F baseline spread | labelled sensitivity only |
| R7 | Exploratory arms §6.1 and §6.2 against both baselines | `blocks` gating-equivalent + 7 sparse readouts |
| R8 | Floor re-definition audit: arm F before/after prerequisite 3 | 2 corpora |

`exactOptimal` is not reported for sparse charsets (§2.6).

## 9. Lift rule

If any non-gating readout or exploratory arm clears the §5.1 PASS margin against **both** baselines on the held-out corpus while the gating charset does not — for example, tone weighting winning on `dots` or `minimal` while failing on `blocks`, or a sparse-set win appearing only under the z-normalized combination — that is **lift**, not a verdict. Lift is recorded in the note with the evidence attached and **split off to a new tracked task**. This battery's verdict is unchanged by it, and `Sources/Aski` stays untouched here regardless.

## 10. AC coverage map

| AC | text (abridged) | satisfied by |
| --- | --- | --- |
| ASKI-30 #1 | tone-weighted score measured against current matcher AND shape-free floor, sparse and dense separately | §2.3, §2.4 (arms P/F/T), §2.5, §8 R1–R2 |
| ASKI-30 #2 | frozen rule set before the run; arm must beat BOTH baselines | §5.1 PASS conjunction; §3 (freeze after prerequisites, before any number) |
| ASKI-30 #3 | default change confirmed perceptually, not by reconstruction metrics | §7 |
| ASKI-30 #4 | if the arm cannot beat the floor on `blocks`, record whether the shape term should be disabled for sparse sets | §5.1 AC#4 disposition; §8 R2 |
| ASKI-28 #1 | `topK` swept 12 → full charset on `standard`/`braille`; pick quality plus cost, ≥2 oracles incl. a luminance-aware one | §2.5 (K sweep to 95/256), §2.6 (five oracles, MAE gating), §5.2 cost cap, §8 R3 |
| ASKI-28 #2 | reported per charset | §2.3, §5.2 (per-charset PASS), §8 |
| ASKI-28 #3 | frozen PASS/KILL rule before the run plus a perceptual check | §5.2, §7 |

## 11. External grounding

1. **Lakens, Scheel & Isager 2018, *A Tutorial on Equivalence Testing*** — margins should be meaningful raw or percentage bounds; standardized bounds inherit sample-SD randomness. Grounds §5's fixed 0.97 ratio and the rejection of a baseline-spread margin (kept only as R6).
2. **Rubin 2021, *When to adjust alpha during multiple testing*** ([arXiv:2107.02947](https://arxiv.org/abs/2107.02947)) — a conjunction ("must beat both baselines") is an intersection–union claim and needs no multiplicity adjustment; adjustment would be needed if success meant winning on *any* metric or corpus. Licenses §5.1's AND-form gate.
3. **Efros & Freeman, SIGGRAPH 2001, *Image Quilting*** — the tone-vs-structure weight is scheduled from ~0.1 to ~0.9 across passes rather than fixed, evidence that no single λ is canonical. Grounds sweeping `w` instead of asserting one.
4. ***Painting with Paintings*, SIGGRAPH Asia 2025** ([doi:10.1145/3757376.3771411](https://doi.org/10.1145/3757376.3771411)) — lexicographic selection: retrieve top-*k* by color similarity, then rank by SSIM, avoiding the addition of incomparable scores. Direct precedent for exploratory arm §6.1.
5. **Practitioner implementation, revised 2026-08-10** ([yiyuiii.github.io](https://yiyuiii.github.io/en/posts/building-shape-matched-ascii-art/)) — `pixel-MSE + mean-gray-MSE` with equal weights fails when term scales differ; estimate both loss distributions on representative samples before choosing normalization. Direct precedent for exploratory arm §6.2 and a caution on the fixed `×50` scale.
6. **El Jurdi, Varoquaux & Colliot 2025** ([arXiv:2307.10926](https://arxiv.org/abs/2307.10926)) — bootstrap paired image-level CIs, clustered at source image. **Noted and not adopted**: this battery follows repo precedent (deterministic exhaustive census, point margins) and supplies robustness through the dual-corpus requirement instead. Recorded so the divergence is deliberate and visible.

## Addendum (2026-08-27, append-only) — the arbiter is no longer parked

§7 above says "the parked VLM / human arbiter remains the missing instrument
and stays parked." As of 2026-08-27 that is no longer true: the ASKI-56
arbiter was built, frozen, and validated — both §5.1 gates passed at 6/6 —
and delivered its first verdict
(`docs/Research/2026-08-27-aski56-arbiter-verdict.md`, result store
`docs/Research/Results/2026-08-27-aski56-arbiter/`).

Consequences for this rule, without altering any frozen decision text:

- The default-promotion follow-up that §7 gates on "a defined perceptual
  check" now runs through **`AskiColorLab arbiter score`** under the frozen
  protocol (`docs/Research/2026-08-25-aski56-arbiter-protocol.md`). The
  PresetLab contact sheet remains available as an informal preview but no
  longer satisfies the gate on its own.
- The 3.0% MAE bar in §5.1 is **retained**: the arbiter's JND75 band
  (−0.345 … +0.072 relative MAE margin) straddles it, so per the arbiter
  protocol's pre-registered §5.2 rule the bar stands, is recorded as sitting
  inside the perceptual ambiguity interval, and no default promotion may rest
  on the bar alone.
- A same-day §6→§7 cross-reference typo in the AC#4 disposition paragraph was
  corrected alongside this addendum (verdict-independent).
