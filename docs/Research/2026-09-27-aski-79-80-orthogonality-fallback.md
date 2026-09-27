---
title: "ASKI-79 + ASKI-80 — orthogonality-to-tone fallback and error-diffused tone centring: decisive verdict"
slug: 2026-09-27-aski-79-80-orthogonality-fallback
date: 2026-09-27
status: complete
subsystem: [shape-context]
summary: "Arm 1 (fall back to the tone-nearest pooled glyph when the logPolar query shares no descriptor bin with any non-blank pooled candidate) is KILL, and arm 2 (arm 1 plus serial Floyd-Steinberg tone centring, lab-only) is INCONCLUSIVE, under the rule frozen at 40bafb0. Arm P reproduced all 43 phase-1 baseline rows exactly. Arm 1 removes the all-blank grid on every fixture of the five blank-collapsed sets and changes at most 0.02 percent of cells on blocks, lines, mixed and braille on the PNG corpora, but on standard it raises per-cell MAE by 3.0-4.2 percent on both PNG corpora at 80 and 288 columns, past the 1.0300 KILL bar, and GMSD by 15-43 percent. Neither per-cell oracle clearly rewards removing the blank collapse of the five sparse sets: against the all-blank grid, their tone ramp's MAE ratio is 0.98-1.08 and its GMSD ratio is 1.16-1.91. Arm 2 cuts the share of inked cells in same-glyph runs of five or more by 0.27-0.38 against arm 1, but glyphsUsed does not rise on three of the four gated rows and braille on nasa-steerable-v1 exceeds the 1.0100 MAE and GMSD guards. Production is unchanged; ASKI-79 is closed by documentation: logPolar is no longer recommended with minimal or dots, and custom sets are told to use dotMatrix."
related_specs: [docs/Research/2026-09-27-aski-79-80-orthogonality-fallback-rule.md, docs/Research/2026-08-19-sampling-lattice-support-collapse.md, docs/Research/2026-08-19-selection-optimality-gap.md, docs/Research/2026-08-19-house-oracle-audit.md, docs/Research/2026-08-24-aski-30-28-decisive-rule.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1, docs/Research/Corpus/nasa-occupancy-v1]
runners: [AskiColorLab]
next_action: "No production follow-up from either arm. A perceptual check (the ASKI-56 arbiter) is the instrument that could say whether an all-blank or single-glyph logPolar render is worse than a tone ramp, since on these corpora GMSD prefers the blank grid and MAE barely separates the two. Texture collapse on braille, blocks, lines and mixed is out of this rule's reach and is tracked separately (ASKI-84, ASKI-55, ASKI-30)."
---

# ASKI-79 + ASKI-80 — orthogonality-to-tone fallback: decisive verdict

- Frozen rule: `docs/Research/2026-09-27-aski-79-80-orthogonality-fallback-rule.md`, committed at `40bafb0` after the phase-1 instrument (`50d619f`) and production baseline (`b4892f1`), before any arm-1 or arm-2 number was read. No threshold was edited.
- Arm code: `bd6779a` (`Tools/AskiColorLab/SamplingLattice/OrthogonalityFallback.swift`, new `SelectionCeiling` arms `A1` and `A2`). Every decisive CSV records this SHA.
- Raw results: `docs/Research/Results/2026-09-27-aski-79-80-decisive/`, committed at `0256a91` before the rule was applied. The verdict tables below are the output of `Scripts/research/aski-79-80-verdict.py` (committed with the raw data, before it was run), saved as `verdict.md` in the same directory. The §5 readouts come from `Scripts/research/aski-79-80-readouts.py`, saved as `readouts.md`.

## 1. Question

At the shipping footprint every logPolar cell query occupies only descriptor bins 51, 54 and 56 (ASKI-55). A non-blank glyph with no mass there has `q·g = 0` against every query, so the squared-L2 distance ranks it by its own norm, and the zero-norm blank beats it. Phase 1 measured the consequences: `minimal`, `dots`, `diagonal`, `cross` and `diamond` render every cell blank (ASKI-79), and 55–59% of `standard` picks on the PNG corpora are decided by `|g|²` alone (ASKI-80).

- **Arm 1** keeps production's shape argmin unless the query is orthogonal to every non-blank pooled candidate, and then picks the tone-nearest pooled glyph, the order `degenerateToneRanking` already uses for one-pixel footprints.
- **Arm 2** is arm 1 plus a serial Floyd–Steinberg walk that carries the tone residual into the pool centre and the fallback target. It is serial and therefore lab-only; a PASS would only have filed a follow-up.

## 2. Run validity

- **Arm P reproduces the baseline.** All 43 gating P rows (all ten sets at 80 and 288 columns on both PNG corpora, plus the frozen preset at 76 on three corpora) equal the phase-1 CSVs in cells, glyphs, all five oracle means, every texture column, footprint, stride, oversample and polarity. Zero mismatches.
- **Instrument**: `aski lab color selection-ceiling`, release build, `--oversample 2 --stride 1`, footprint 24, inverted query polarity, density 0 (topK 12), monochrome palette, sRGB, macOS 27, owner hardware.
- **Re-run.** The two gating `braille` jobs at 288 columns were killed with the session that launched them before they wrote a row. They were re-run with the same binary and flags; their P rows reproduce the baseline like every other row.
- **§4.2 reading.** The KILL clause of rule §4.2 is read with "on `nasa-steerable-v1` at 288 columns" scoping both conditions (the `run5Share` fall and the `R(arm 2 / arm 1) > 1.0300` test). It does not change the arm-2 verdict: neither condition fires under either reading.
- **Rounding.** `R` and `G` are rounded to four decimals as the rule says; texture shares are compared unrounded. One KILL clause sits on the fourth decimal (`standard`, `nasa-structure-v1`, 80 columns: 0.261090 / 0.253468 = 1.03007, read as 1.0301). The other three `standard` ratios are 1.0338–1.0423, so the verdict does not depend on it.

## 3. Arm 1 — KILL

### Item 1 — defect removed: PASS

Every one of the 60 fixture × column × set cells has arm-1 `blankShare < 1.0`. The blank share that remains is the share of cells where the blank is the tone-nearest glyph: 0% on `sahara-dunes`, and 92–99% for `minimal`, `diagonal`, `cross` and `diamond` on the dark `earth-limb-sunrise` frame of `nasa-steerable-v1`, where `dots` is at 0–1%.

### Items 2, 3 and 5 — `standard`

| corpus | cols | MAE P | MAE A1 | R | item 2 bar | GMSD P | GMSD A1 | G | run≥5 P | run≥5 A1 |
|---|---|---|---|---|---|---|---|---|---|---|
| nasa-steerable-v1 | 80 | 0.240806 | 0.250995 | **1.0423** | ≤ 1.0000 | 0.199776 | 0.284875 | 1.4260 | 0.5779 | 0.5835 |
| nasa-steerable-v1 | 288 | 0.240072 | 0.248333 | **1.0344** | ≤ 1.0000 | 0.201817 | 0.274709 | 1.3612 | 0.5975 | 0.5269 |
| nasa-structure-v1 | 80 | 0.253468 | 0.261090 | **1.0301** | ≤ 1.0100 | 0.242464 | 0.277818 | 1.1458 | 0.5789 | 0.5527 |
| nasa-structure-v1 | 288 | 0.250117 | 0.258571 | **1.0338** | ≤ 1.0100 | 0.256589 | 0.298845 | 1.1647 | 0.5541 | 0.5483 |

Item 2 fails on all four rows, and every row is above the 1.0300 KILL bar. GMSD agrees in direction and by a larger margin (item 3 fails). Item 5 (texture no-harm) passes: arm 1 does not lengthen runs.

### Item 4 — no harm elsewhere: PASS (near-vacuous, as the rule said it would be)

On the PNG corpora arm 1 changes 0.00–0.02% of cells for `blocks`, `lines`, `mixed` and `braille`, and every ratio is 0.9998–1.0000. The frozen preset (`blocks`, 76) is untouched on `nasa-steerable-v1` and `nasa-structure-v1`. On `nasa-occupancy-v1` arm 1 changes 12.8% of frozen-preset cells (the white-ground zero-query cells, rule §3.2), with MAE ×0.8651 and GMSD ×1.1667; item 4 gates MAE only, so this row passes.

### Item 6 — sparse-set gain (structural, not deciding): FAIL

On `nasa-steerable-v1` at 80 columns, `R(A1/P)` equals `R(F/P)` to every digit for all five sets, as rule §3.1 predicted: minimal 0.9839, dots 1.0436, diagonal 1.0003, cross 0.9875, diamond 0.9924. None reaches 0.97. Under the rule this would only have made a non-KILL verdict INCONCLUSIVE.

**Verdict: KILL.** The fallback removes the all-blank grid, but on the deciding charset it costs 3.0–4.2% per-cell MAE on both corpora at both column counts.

## 4. Arm 2 — INCONCLUSIVE

Strength 1.0, 288 columns, against arm 1.

| corpus | charset | run≥5 A1 | run≥5 A2 | fall | used A1 | used A2 | R(A2/A1) | G(A2/A1) |
|---|---|---|---|---|---|---|---|---|
| nasa-steerable-v1 | standard | 0.5269 | 0.1796 | 0.3473 | 48 | 48 | 0.9896 | 0.9245 |
| nasa-steerable-v1 | braille | 0.5619 | 0.1797 | 0.3822 | 13 | 13 | **1.0136** | **1.1428** |
| nasa-structure-v1 | standard | 0.5483 | 0.2761 | 0.2721 | 77 | 77 | 0.9932 | 0.9787 |
| nasa-structure-v1 | braille | 0.5071 | 0.2342 | 0.2729 | 20 | 21 | 0.9934 | 0.9783 |

- PASS fails on two named blockers: `glyphsUsed` does not rise on three of the four rows, and `braille` on `nasa-steerable-v1` exceeds both the 1.0100 MAE guard and the 1.0100 GMSD guard.
- KILL does not fire: the run≥5 share falls by 0.35 and 0.38 on `nasa-steerable-v1`, and no `R(A2/A1)` exceeds 1.0300.

**Verdict: INCONCLUSIVE.** Nothing is filed; the rule reserves a follow-up for a PASS. Arm 2 sits on arm 1, which is KILL, so on `standard` its MAE is still 2.4–2.7% above production's even where it beats arm 1.

## 5. Non-gating readouts (rule §5)

Full tables: `readouts.md` in the results directory.

- **Cells changed against P.** Arm 1 changes 47–58% of `standard` cells, 0% of `braille`, `blocks`, `lines` and `mixed` cells on the PNG corpora, and 53–100% of the five sparse sets' cells (the cells where the blank is not tone-nearest). Arm 2 at strength 1 changes 29–34% of `braille` cells, all through the carried error.
- **Arm 2 at strength 0.5.** Runs fall about half as far (`standard` 0.53 → 0.28 on `nasa-steerable-v1` at 288), `R(A2/A1)` is 0.9903–1.0050, and `braille` on `nasa-steerable-v1` has `G` 1.0510.
- **`nasa-occupancy-v1` at 80 columns.** This JPEG corpus has 13–15% white-ground zero-query cells. There arm 1 lowers MAE for every set except `standard` (×1.0112) and `braille` (0.04% of cells changed, ×1.0000): the five sparse sets ×0.87–0.92, `blocks` ×0.8619, `lines` ×0.9531, `mixed` ×0.8878. GMSD rises for every set except `braille` (×1.08–1.75).
- **Per-fixture `standard` blank share.** Production's blank share ranges from 0% (`sahara-dunes`) to 97% (`earth-limb-sunrise` on `nasa-steerable-v1`); arm 1 brings every fixture to 29% or less, and all but that dark frame to under 1%.
- **Render pair (rule §3.2).** On two white-ground occupancy JPEGs through the frozen preset, arm 1 changes 669 of 3420 cells (`james-lovell-portrait`) and 1718 of 2052 (`rcs-function-diagram`). In both, pure white turns from dark ground into full `█` ink. The owner decision this pair was prepared for is moot, because arm 1 does not ship.

## 6. What the numbers show beyond the rule

1. **Neither per-cell oracle clearly rewards removing the all-blank grid.** For the five sparse sets, arm 1 is a tone ramp and P is a blank grid. Against the blank grid, the ramp's MAE is ×0.98–1.04 on `nasa-steerable-v1` and ×1.00–1.08 on `nasa-structure-v1`, and its GMSD is ×1.16–1.91 on both. GMSD rates the image of spaces better than the tone rendering everywhere; MAE rates the ramp slightly better on some steerable rows (×0.98 for `minimal`) and worse on others, never by the 0.97 margin of §4.1 item 6. Neither oracle, by itself, can reward fixing ASKI-79. The rule's KILL on `standard` therefore says that arm 1 does not improve per-cell MAE or GMSD. It does not show that an all-blank or run-heavy render looks better. That question needs a perceptual instrument (the ASKI-56 arbiter), not a third per-cell metric.
2. **Hypothesis, not tested: per-cell MAE favours the dark ground on dark cells.** Per-pixel absolute error is minimised by the block's median, not its mean. On a mostly dark cell the blank (dark ground) sits near the median, while a tone-matched glyph puts full-intensity ink on pixels where the source is dark. The corpora are mostly dark space imagery, and on the white-ground occupancy corpus arm 1 lowers MAE for every set it changes except `standard`. This fits the numbers, but no independent check has been run.
3. **`glyphsUsed` did not move between arm 1 and arm 2 on `standard`** (48, 77, 40 and 70 at both strengths). A hypothesis that also fits: arm 1 already uses every glyph that is tone-nearest for some tone in the corpus, and error diffusion moves targets inside the same range. If so, the rule's "`glyphsUsed` rises" clause was close to unreachable for any arm built on arm 1.

## 7. Consequences

- **Production unchanged.** `Sources/Aski` changes only in doc comments. Rule §6: an arm-1 KILL closes ASKI-79 by documenting the defect and dropping the recommendation to pair logPolar with the blank-collapsed sets.
- **Docs (ASKI-79 AC#3).** The logPolar row of the pairing table in `Algorithms.md` now lists `standard` and `braille` only. The table is followed by the measured failure groups: the five sets that render all blank, and `blocks`, `lines` and `mixed`, which use one to four distinct glyphs per image for `blocks` and one or two for `lines` and `mixed` (phase 1, Table T). The `ASCIIAlgorithm.logPolar` doc comment matches, and `CommandLine.md` notes that `aski render` renders those five sets blank under its default `--algorithm logPolar` and that `--algorithm dotMatrix` (added by ASKI-82 in the same batch) avoids it.
- **Custom sets (ASKI-79 AC#4).** `CharacterSets.md` and the `RasterizedCharacterSet` doc comment gain a documented diagnostic: a custom set whose glyphs miss the reachable bins renders all blank or repeats one glyph under logPolar; use dotMatrix. Both custom-set examples (`CharacterSets.md`, `GettingStarted.md`) now pass `algorithm: .dotMatrix`: under logPolar the `GettingStarted` ramp rendered every cell of the `vavilov-crater` fixture blank, and the `CharacterSets` star set rendered every cell as `★`. `LogPolarReachableSupportTests` pins both halves for a custom `RasterizedCharacterSet` with no glyph in the reachable bins: all blank under logPolar, not all blank under dotMatrix.
- **ASKI-80.** AC#1 and AC#2 were met in phase 1. AC#3 is met: arms 1 and 2 were measured against production on runs and MAE/GMSD together under this rule. AC#4 is this note.
- **Out of reach.** Arm 1 leaves `braille`, `blocks`, `lines` and `mixed` almost unchanged on the PNG corpora (0.00–0.02% of cells changed). Their texture collapse is tracked separately (ASKI-84; the ASKI-55 support-restoration and ASKI-30 tone-in-pool routes).
- **Lab code stays.** Arms `A1` and `A2` remain as `selection-ceiling` arms so these results can be replayed; nothing in production depends on them.
