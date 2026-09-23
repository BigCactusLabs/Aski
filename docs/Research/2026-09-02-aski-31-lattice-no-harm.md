---
title: "ASKI-31 — selection-ceiling no-harm before/after across the ASKI-65 lattice change"
slug: 2026-09-02-aski-31-lattice-no-harm
date: 2026-09-02
status: complete
subsystem: [shape-context]
summary: "ASKI-31 closes NO HARM. ASKI-31 required a selection-ceiling before/after under both MAE and GMSD as no-harm evidence before the sampling-lattice truncation was removed; ASKI-65 (PR #37) removed it by a third route — a lattice-sized raster that reads every source row through a second interpolation stage — and re-recorded the moved goldens without running the census. This note froze the reading rule first (MAE-gated at the ASKI-30/28 rule's 1.01 no-harm guard on the frozen preset on both naturals corpora, GMSD reported and non-gating), then ran the census on the last commit before ASKI-65 (64a8f98) and on main after it. Frozen-preset production-arm MAE moves by x1.0016 on nasa-steerable-v1 and x1.0085 on nasa-structure-v1, both inside the guard, with GMSD agreeing in direction; the effect decays to parity by oversample 16, and the dense charsets improve about 1.1 percent at oversample 2 because they now read the whole frame. The (a)/(b)/(c) choice is recorded: the shipped (c) dominates (b) and beats (a) on the merits at a measured cost of at most 0.85 percent MAE on blocks. Grid cell counts are identical on both sides, so uniform pitch and the parity-split guard are unchanged."
related_specs: [docs/Research/2026-08-19-sampling-lattice-support-collapse.md, docs/Research/2026-08-19-house-oracle-audit.md, docs/Research/2026-08-24-aski-30-28-decisive-rule.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1]
runners: [AskiColorLab]
next_action: "ASKI-31 is closed. The before/after CSVs remain the baseline for any future single-interpolation experiment. ASKI-66 subsequently closed INCONCLUSIVE, and ASKI-68 removed its chroma-shape treatment and dedicated runners."
---

# ASKI-31 — selection-ceiling no-harm across the ASKI-65 boundary

**Task:** ASKI-31 · **Executed:** 2026-09-02 · **Before:** `64a8f98` (last commit before ASKI-65) ·
**After:** `0ded424` (main, ASKI-65 merged at `611703d`; the commits between are docs-only).

## 1. Why this run exists

ASKI-31 framed the removal of the bottom/right sampling remainder as a product decision about the
frozen preset's output, not a bug fix, and required "a selection-ceiling before/after under both MAE
and GMSD" as the no-harm evidence (AC #3). ASKI-65 removed the remainder by a third route — it draws
the decoded thumbnail into an exact `columns*cellWidth × rows*cellHeight` raster
(`Sources/Aski/CellSampling.swift`, `samplingLattice`) — enumerated and re-recorded the six goldens the
change moved (`4db60d6`), and never ran the census. Re-recording a golden proves determinism, not
no-harm.

The shipped route carries a cost neither of ASKI-31's two candidate approaches had: the thumbnail is
already an interpolated downscale of the source, and the lattice raster re-reads it at
`interpolationQuality = .high`, so the pipeline now interpolates **twice** where approach (a) (make the
thumbnail an exact multiple of the grid) would have interpolated once. Whether that second stage
degrades glyph picks is exactly what the unrun census answers.

## 2. Reading rule — frozen before any number was read

The instrument is unchanged in behaviour across the boundary: the `Tools/AskiColorLab/SamplingLattice`
diff between `64a8f98` and `611703d` is comment-only (`SelectionCeiling.swift`, `SampledSource.swift`,
`LatticePhase` in `LatticeSupport.swift`). On both sides each cell's oracle reference is the
**native-resolution** block the converter's own `SamplingGeometry` says it read, so the reference
is never softened by the sampling path under test; a change in loss is a change in pick fidelity
against the source pixels, not an artefact of scoring a blurrier target.

1. **Quantity.** Per-cell mean loss of the production arm `P` (CSV `arm == "P"`), read from the
   `--output` CSV and nothing else. Ratio `R = after / before`, four decimal places.
2. **Verdict oracle.** MAE, per ASKI-27. `R_MAE ≤ 1.0100` on the frozen preset
   (`blocks`, 76 columns, oversample 2) on **both** `nasa-steerable-v1` and `nasa-structure-v1` →
   **NO HARM**. The 1.01 guard is the no-harm guard the ASKI-30/28 rule already uses.
   Any frozen-preset `R_MAE` in `(1.0100, 1.0300]` → **INCONCLUSIVE**. Any `R_MAE > 1.0300` → **HARM**
   (the +3.0% promotion bar, mirrored). `R_MAE ≤ 0.9700` on both corpora is recorded as an
   improvement but changes nothing — nothing is being promoted.
3. **GMSD.** Reported at every arm because AC #3 asks for it. It cannot gate (house-oracle audit §5).
   A GMSD direction that disagrees with MAE is recorded as a labelled cross-check note, not a demotion.
4. **Secondary arms, non-gating.** The 80-column `blocks,standard` sweep at oversample
   `2,4,8,16,32` and `braille` at oversample 2 on `nasa-steerable-v1`, and `blocks,standard` at
   oversample 2 on `nasa-structure-v1`, are reported so the change is characterised beyond the
   frozen preset. The ranking-headroom figures (`totalGap%`, `rankGap%`) are quoted from the stdout
   table for context only; the verdict is read from the `P` rows of the CSV.
5. **Population caveat, stated in advance.** The two sides do not score the same cells. Before
   ASKI-65 the census covered the top-left `rows*cellHeight` thumbnail rows only (10 % of image
   height unread at the shipping arm); after it every source row is read. Grid dimensions and the
   `cells` column may also differ where the exact lattice resolves a different row count. A ratio is
   still the right no-harm reading — it compares how well each shipped pipeline matches the pixels
   it actually samples — but it is a comparison of two pipelines, not a paired test on identical
   cells, and this note does not claim otherwise.
6. **Tie and `nan` policy** as in the ASKI-30/28 rule §5: a ratio of exactly `1.0000` is not
   improved and not harmed; a `nan` cell is never read as a pass.

## 3. Runs

Five invocations per side, identical flags, release build, `xcrun swift run -c release`:

```bash
AskiColorLab selection-ceiling --charset blocks --columns 76 --oversample 2 --corpus <STEER> --output frozen-steer.csv
AskiColorLab selection-ceiling --charset blocks --columns 76 --oversample 2 --corpus <STRUCT> --output frozen-struct.csv
AskiColorLab selection-ceiling --charset blocks,standard --columns 80 --oversample 2,4,8,16,32 --corpus <STEER> --output sweep-steer.csv
AskiColorLab selection-ceiling --charset blocks,standard --columns 80 --oversample 2 --corpus <STRUCT> --output default-struct.csv
AskiColorLab selection-ceiling --charset braille --columns 80 --oversample 2 --corpus <STEER> --output braille-steer.csv
```

`STEER = docs/Research/Corpus/nasa-steerable-v1/assets`, `STRUCT = docs/Research/Corpus/nasa-structure-v1/assets`.
Artifacts: `docs/Research/Results/2026-09-02-aski-31-lattice-no-harm/{before,after}/`.

## 4. Results

Both sides ran clean (exit 0, no deviations). The `after` side was built at `0eb5093`, which is
`0ded424` plus the §2 rule commit — docs only, code identical to main. Every `cells` count is
identical before and after (7752 at 76 columns, 8640 at 80), so the grid the converter resolved did
not change; what changed is the pixels each cell read. Ratios are `after / before` of the CSV means,
four decimals.

### 4.1 Frozen preset — the gating rows (`blocks`, 76 columns, oversample 2, arm `P`)

| corpus | cells | MAE before | MAE after | **R_MAE** | GMSD before | GMSD after | R_GMSD | R_RMSE | R_SSIM | R_HaarPSI |
|---|---|---|---|---|---|---|---|---|---|---|
| nasa-steerable-v1 | 7752 | 0.56314 | 0.56406 | **1.0016** | 0.33958 | 0.34099 | 1.0041 | 1.0036 | 0.9668 | 0.9942 |
| nasa-structure-v1 | 7752 | 0.55741 | 0.56216 | **1.0085** | 0.29531 | 0.29737 | 1.0070 | 1.0135 | 0.9458 | 0.9844 |

Both `R_MAE` values sit inside the 1.0100 guard. GMSD moves in the same direction on both corpora
(a 0.4 % and 0.7 % rise) and so does RMSE; SSIM on `blocks` is read as a raw-score direction only
(rule §2.4 of the ASKI-30/28 rule) and falls, i.e. disagrees, but it cannot gate and is noted as the
labelled cross-check it is. The tone-only floor `F` on the same rows improves (`R_MAE` 0.9850 and
0.9543), so the ranking headroom on the frozen preset widens slightly (`totalGap%` 61.75 → 62.40 on
steerable, 58.73 → 61.32 on structure, from the stdout tables) — the full frame is easier to match
by tone alone than the top 90 % was, and production's shape pick does not collect that gain.

### 4.2 Secondary arms (non-gating), arm `P`

| corpus | charset | columns | oversample | cells | R_MAE | R_GMSD | R_RMSE |
|---|---|---|---|---|---|---|---|
| nasa-steerable-v1 | blocks | 80 | 2 | 8640 | 1.0016 | 1.0039 | 1.0034 |
| nasa-steerable-v1 | blocks | 80 | 4 | 8640 | 1.0010 | 1.0048 | 1.0032 |
| nasa-steerable-v1 | blocks | 80 | 8 | 8640 | 1.0008 | 1.0029 | 1.0016 |
| nasa-steerable-v1 | blocks | 80 | 16 | 8640 | 1.0003 | 1.0001 | 1.0005 |
| nasa-steerable-v1 | blocks | 80 | 32 | 8640 | 1.0000 | 0.9999 | 1.0000 |
| nasa-steerable-v1 | standard | 80 | 2 | 8640 | 0.9887 | 0.9917 | 0.9893 |
| nasa-steerable-v1 | standard | 80 | 4 | 8640 | 0.9886 | 0.9921 | 0.9889 |
| nasa-steerable-v1 | standard | 80 | 8 | 8640 | 0.9950 | 1.0011 | 0.9961 |
| nasa-steerable-v1 | standard | 80 | 16 | 8640 | 0.9979 | 0.9965 | 0.9970 |
| nasa-steerable-v1 | standard | 80 | 32 | 8640 | 0.9997 | 0.9990 | 0.9996 |
| nasa-steerable-v1 | braille | 80 | 2 | 8640 | 0.9896 | 0.9925 | 0.9905 |
| nasa-structure-v1 | blocks | 80 | 2 | 8640 | 1.0097 | 1.0110 | 1.0140 |
| nasa-structure-v1 | standard | 80 | 2 | 8640 | 0.9447 | 0.9727 | 0.9488 |

Three regularities, all consistent with the mechanism ASKI-65 changed:

- **The effect decays with oversample and vanishes by 16–32.** Before ASKI-65 the unread fraction
  was `thumbnailHeight % rows`, largest at oversample 2 and near zero at 16+; after it there is no
  unread fraction at any arm. The ratios track that: 1.0016 → 1.0000 on `blocks`, 0.9887 → 0.9997 on
  `standard`. Whatever the second interpolation stage costs, it is not visible once the two lattices
  read the same rows.
- **Dense charsets improve, `blocks` does not.** `standard` and `braille` gain ~1.1 % MAE at
  oversample 2 on the held-out corpus and 5.5 % on `nasa-structure-v1`; `blocks` is flat to
  +1 %. The frozen preset is the one charset where the change is a slight loss, and it is the one
  the rule gates on.
- **The largest `blocks` move is on `nasa-structure-v1` at 80 columns** (`R_MAE` 1.0097, inside the
  guard by 0.0003). This is the corpus the house-oracle audit already flagged as the one whose
  numbers sit up to 10 gap points from the held-out corpus, and it is reported here as the
  sensitivity it is, not as a demotion — the frozen preset's own row on the same corpus is 1.0085.

## 5. Verdict and the (a)/(b)/(c) record

**NO HARM**, read mechanically from §2.2: the frozen preset's production-arm MAE ratio is 1.0016 on
`nasa-steerable-v1` and 1.0085 on `nasa-structure-v1`, both ≤ 1.0100, and GMSD agrees in direction on
both. The second interpolation stage that distinguished the shipped approach from ASKI-31's
candidates costs at most 0.85 % MAE on the frozen preset and nothing measurable on any arm at
oversample 16 or above, while the dense charsets gain from reading the whole frame. AC #3's missing
half is now on record.

**AC #1's choice, recorded and justified after the fact.** ASKI-31 offered (a) size the thumbnail to
an exact multiple of the grid and (b) centre the lattice so the loss is split top and bottom. ASKI-65
shipped a third route, (c): draw the decoded thumbnail into an exact `columns*cellWidth ×
rows*cellHeight` raster. The ordering on the merits, with this note's evidence:

- (c) over (b): (b) never recovers the dropped rows, it only moves half the loss to the top; (c)
  reads every row, and the dense-charset gains in §4.2 are the recovered content showing up in the
  picks. (b) is dominated.
- (c) over (a): (a) interpolates once, (c) twice, and the extra stage was the open question. The
  measured cost on the frozen preset is ≤ 0.85 % MAE, inside the guard, and (c) keeps
  `thumbnailMaxPixelSize` — and the ASTSK-47 portrait blank-render fix that lives in it — untouched,
  which (a) could not. Should a future change need the last 0.85 % back, single-stage (a) is the
  place to look, and this note's CSVs are the baseline to measure it against.

Uniform pitch (AC #2) is structural under (c): `SamplingGeometry` carries scalar `cellWidth` /
`cellHeight`, `latticeIsAnExactMultipleOfTheGrid` asserts the lattice, and the identical `cells`
counts on both sides in §4 confirm the grid did not move. The §3 parity split of the
support-collapse note therefore still never fires.

**What this note does not claim.** It is a comparison of two pipelines on the pixels each actually
samples, not a paired test on identical cells (§2.5). It does not reopen any archived kill — the
ASKI-66 lattice audit is where a pre-ASKI-65 verdict's battery gets checked. And a 0.85 % MAE move
on `blocks` is below the arbiter's JND band in either direction, so no contact-sheet review is
warranted for the frozen preset's goldens.

## 6. Reproduce

```bash
git worktree add --detach ../aski-31-before 64a8f98
# in each of ../aski-31-before and a checkout at/after 611703d:
xcrun swift build -c release --product AskiColorLab
xcrun swift run -c release --skip-build AskiColorLab selection-ceiling \
  --charset blocks --columns 76 --oversample 2 \
  --corpus docs/Research/Corpus/nasa-steerable-v1/assets --output frozen-steer.csv
# ... and the other four §3 invocations. ~13 min per side in release on owner hardware.
```
