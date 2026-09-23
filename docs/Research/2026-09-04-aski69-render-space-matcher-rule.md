---
title: "ASKI-69 render-space matcher challenge - KILL"
slug: 2026-09-04-aski69-render-space-matcher-rule
date: 2026-09-04
status: complete
subsystem: [shape-context, frontier]
summary: "KILL. Under the rule committed before measurement, aligned MAE and its one-pixel bounded-alignment variant each broke the 1 percent GMSD guard on the held-out dense standard charset, while tone-plus-fill broke the dense MAE guard on both corpora. All arms also exceeded both time budgets; selector storage stayed under 1 MiB. No objective candidate exists, so the ASKI-62 human/VLM trigger did not fire. The lab-only result changes no production source, public API, or default."
related_specs: [docs/Research/2026-08-19-selection-optimality-gap.md, docs/Research/2026-08-19-house-oracle-audit.md, docs/Research/2026-09-04-aski62-arbiter-v2-protocol.md, docs/Research/2026-09-03-future-direction-and-architecture.md]
datasets: [docs/Research/Corpus/nasa-structure-v1, docs/Research/Corpus/nasa-steerable-v1]
runners: [AskiColorLab]
results: [docs/Research/Results/2026-09-04-aski69-render-matcher-challenge]
next_action: "Keep all three challenger arms research-only. Do not create a production replacement or optimization task. Revisit fixed-footprint matching only through a new pre-registration with a materially different mechanism and independent evidence that it can preserve dense shape at production-relevant cost."
---

# ASKI-69 render-space matcher challenge

Sections 1-7 are the rule frozen in commit `2ad2e8a` before any result was read. Section 8
records the one permitted result. A change to a corpus, geometry, raster, arm, threshold,
oracle role, tie-break, or performance budget requires a new task and a new pre-registration.

## 1. Question and boundary

Can one fixed-footprint render-space selector replace the shipping 60D log-polar selector
without becoming a second permanent matcher?

This is a research-only challenge. It changes no file in `Sources/Aski`, no public API,
no default, no shape-vector resource, and no frozen golden. Every arm receives the same
source cell, character set, renderer-faithful candidate mask, output geometry, and ink-high
monochrome convention. Only the selection loss changes.

The result has two independent readings:

- `blocks` is the sparse character set frozen into Vesper. It decides whether the challenger
  improves the product-relevant halftone-like regime.
- `standard` is a 95-glyph, shape-sensitive dense control. It prevents `blocks` from deciding
  the general matcher.

Neither reading is a population estimate. Each corpus has three named fixtures. The run is an
exhaustive census of those fixtures' cells.

## 2. Frontier evidence and what it licenses

- Chafa 1.16.2 is maintained production evidence that a small fixed bitmap can support glyph
  selection. Its current source creates an at-most-eight-candidate bitmap shortlist, computes
  foreground/background colours for each candidate, and then scores the candidate's per-pixel
  rendered error. Its fill path is separate. This corroborates feasibility, not a universal
  metric or a win in Aski's font and corpus.
  ([renderer source](https://raw.githubusercontent.com/hpjansson/chafa/master/chafa/internal/chafa-symbol-renderer.c),
  [symbol-map source](https://raw.githubusercontent.com/hpjansson/chafa/master/chafa/chafa-symbol-map.c),
  [release record](https://github.com/hpjansson/chafa/releases))
- Xu, Zhang, and Wong show that aligned SSIM and blurred RMSE can prefer the glyph with more
  overlap rather than the glyph with the intended line shape. That is direct counter-evidence
  to treating aligned reconstruction as perceptual truth. It licenses the bounded-translation
  arm and requires a human arbiter before promotion.
  ([project page](https://ttwong12.github.io/papers/asciiart/asciiart.html),
  [paper](https://www.cg.tuwien.ac.at/courses/CA/material/papers/AsciiArt.pdf))
- Recent work formalizes Chamfer distance under translation for cases where translation is a
  nuisance variable. ASKI-69 does not adopt Chamfer distance; it uses the simpler exhaustive
  nine-position treatment because the registered displacement is only one pixel.
  ([Halevi, Zhang, and Zhang, 2026](https://arxiv.org/abs/2605.25280))
- UNICASSO is pre-release and has no paper yet. Its maintainer reports that reconstruction-only
  optimization turns line art into tone-heavy block structure, while its stronger system adds
  global perceptual and structural terms and is not compute-matched. This corroborates the
  failure mode and rejects UNICASSO as a dependency or authority for this local selector.
  ([repository and status](https://github.com/jakobrees/unicasso))

Tier coverage: primary implementation and release evidence, maintained project evidence, and
peer-reviewed or preprint research were checked. Credible current practitioner or pre-consensus
discussion specific to local glyph matching was thin and was not padded into the decision.

## 3. Frozen instrument

### 3.1 Corpora and geometry

Run both, never one in place of the other:

1. `docs/Research/Corpus/nasa-structure-v1/assets` - 2048-pixel calibration corpus.
2. `docs/Research/Corpus/nasa-steerable-v1/assets` - 3072-pixel held-out corpus.

For each corpus and character set:

- columns `80`;
- converter oversample `2`;
- scoring footprint `24 x 24`;
- stride `1`, so every cell is scored;
- `ASCIITileShape.wide`;
- `RenderingOptions.default`;
- `BuiltInPalette.monochrome` in sRGB;
- the converter's exact `SamplingGeometry`, with `droppedX == 0` and `droppedY == 0` asserted;
- native source blocks from `SampledSource.lumaBlock`, resampled once to the footprint.

The two charsets are `blocks` and `standard`. Any missing fixture, empty grid, non-exact lattice,
duplicate glyph, missing query descriptor, non-finite score, or production-pick mismatch fails the
run. A partial census is not a result.

### 3.2 One candidate raster bank

Every arm uses the same 24 by 24 ink-high mask per glyph. `GlyphCellRaster` renders Courier at
four-times supersample, with the renderer's typographic origin and baseline, and box-downsamples
once. Candidate masks are created before timing. No arm can use the bounds-centred vector-builder
raster, a different point size, a different antialiasing pass, or a private mask.

The oracle renders the selected index by looking up this same bank. Thus selector and oracle share
a raster but not a score: selection uses one registered loss below; the verdict recomputes MAE and
GMSD from the selected mask and source pixels.

### 3.3 Arms

All challenger arms search the full charset. Ties go to the lower character-set index.

| Arm | Frozen selector |
| --- | --- |
| `P` | Shipping `ShapeMatching.findBestScored`, `topK = 12`, on the converter's own 60D query and adjusted L. Its recovered index must equal the real converter grid. |
| `A` | Aligned fixed-footprint loss: mean absolute pixel error between candidate mask and source. |
| `S1` | Bounded alignment loss: minimum of the same MAE over the nine integer candidate offsets `dx,dy in -1...1`, with pixels outside the footprint set to zero. Offset enumeration is row-major from `dy=-1`, `dx=-1`; equal loss keeps the first offset, then the lower glyph index. |
| `TF` | Tone plus fill: `abs(mean(candidate) - mean(source)) + mean(abs((candidate - mean(candidate)) - (source - mean(source))))`. The two normalized terms have fixed equal weight. |

The run does **not** include analytic foreground/background fitting. That treatment would give a
candidate colours that the frozen monochrome path does not emit and would change palette fitting
at the same time as glyph selection. Chafa and UNICASSO make it a credible later arm, but it is a
confound here, not an omitted optimization.

### 3.4 Outputs

The one-shot command writes:

- `matcher-census.csv`: one row per `(corpus, charset, arm)`, with cell count, glyph count,
  distinct glyph use, largest glyph share, churn from P, mean MAE, mean GMSD, selection seconds,
  time ratio to P, and estimated peak selector bytes;
- `examples.txt`: every arm's actual character grid for the first fixture in each corpus and
  charset, labeled so the render can be inspected without re-running selection;
- `summary.md`: the mechanical verdict and the four separate regime rows;
- `result.yaml`: exact SHA, command, datasets, and outputs.

The process also records total wall time and process maximum resident size in `summary.md`. Those
are descriptive because all arms share the process and corpus decode. The gating memory measure is
the selector's deterministic live storage: candidate raster bank, source footprint, arm scratch,
and pick grid.

## 4. Required sanity checks

Before any corpus result is accepted:

1. `P` reproduces every real converter glyph.
2. `A` selects the exact mask when the source is one candidate mask.
3. `S1` selects a glyph after a known one-pixel displacement that makes `A` miss.
4. `TF` reports its tone and mean-centred fill components independently: a synthetic tone-only
   change alters only the first component, and a same-mean shape change alters only the second.
5. All arm losses are finite and tie-breaking is stable.
6. Re-running a small synthetic census gives identical picks and CSV field order.

These are instrument tests, not evidence that an arm improves photographs.

## 5. Frozen readouts

Report `blocks` and `standard` separately for each corpus. For each challenger against `P`:

- MAE improvement percent: `(P.mae - arm.mae) / P.mae * 100`; higher is better.
- GMSD regression percent: `(arm.gmsd - P.gmsd) / P.gmsd * 100`; lower is better.
- candidate churn: fraction of cells whose index differs from P.
- glyph use: distinct selected glyphs and largest-glyph share.
- performance: selection wall seconds and ratio to P.
- memory: deterministic estimated peak selector bytes; process maximum RSS is descriptive.

No SSIM, HaarPSI, visual preference, or mechanism story can change the rule. MAE is the house
oracle. GMSD is the convention-independent no-harm guard and does not define an optimum.

## 6. Mechanical decision rule

Evaluate each challenger independently.

### 6.1 Objective candidate

An arm is an **objective candidate** only if all conditions hold:

1. On `blocks`, MAE improves by at least `5.0%` against P on **both** corpora.
2. On `standard`, MAE is no worse than P by more than `1.0%` on either corpus.
3. GMSD is no worse than P by more than `1.0%` in any of the four
   `(corpus, charset)` cells.
4. Every cell count equals P and candidate churn is non-zero in every cell.

A sign disagreement on `blocks` between qualifying MAE and GMSD is not a KILL. It is an arbiter
trigger and stays HOLD because the two oracles answer different questions.

### 6.2 Performance and memory budget

For possible promotion, the arm's selection time ratio must be at most `4.0x` P on `blocks` and
`12.0x` P on `standard` in each corpus. Its deterministic selector storage must be at most
`1 MiB` per census. A quality-qualified arm outside either time budget is HOLD for one bounded
optimization task; it is not allowed into production slow and default-off. An arm above the
memory budget is KILL because the registered fixed-footprint design has no need for that storage.

### 6.3 Arbiter trigger

Every objective candidate triggers a blinded converter-level comparison under a versioned
extension of the ASKI-62 protocol. The generated metric examples are not votes. Existing ASKI-62
polarity votes cannot be re-labeled as matcher evidence. PROMOTE requires both the human and pinned
VLM legs to pass their validation gates and prefer the challenger under the protocol's decided-n,
JND, repeat, calibration, and human-authority rules.

If the objective trigger fires before that sitting exists, the ASKI-69 verdict is **HOLD -
PERCEPTUAL DISPOSITION OPEN**. Do not infer a vote.

### 6.4 Verdicts

- **PROMOTE** only when one arm is an objective candidate, meets both cost budgets, passes the
  arbiter rule, and has an approved replacement task whose production diff deletes more matcher
  and vector complexity than it adds. The replacement task deletes the obsolete log-polar stack;
  no second production matcher remains.
- **HOLD** when at least one arm is an objective candidate but cost optimization or the arbiter is
  still open. The arm remains only in this lab command.
- **KILL** when no arm is an objective candidate, or every quality-qualified arm exceeds the memory
  budget. Keep this rule, result artifacts, and Git history; create no production option.

If two arms qualify, prefer the simpler arm in the fixed order `A`, `S1`, `TF` when their mean
blocks MAE differs by less than `1.0` percentage point. Otherwise prefer the arm with the larger
mean blocks MAE improvement. This tie-break selects an arbiter treatment; it cannot bypass it.

## 7. Expected failure and strongest counter-case

The most likely KILL is that `A` reduces MAE while degrading perceived shape, `S1` spends too much
time buying a nuisance invariance, and `TF` returns to a tone-heavy result on `blocks`. The strongest
case for a challenger is the existing large MAE gap between P and the tone-only floor. The strongest
case against promotion is that aligned reconstruction has already failed on glyph-shape examples
and that a local cell objective cannot preserve long contours. The rule gives the local challenger
one fair, exact-lattice attempt and makes human evidence mandatory if the objective case succeeds.

*Adapted: the frontier pass stopped after one expansion because primary implementation evidence and
the strongest published counter-example converged; current practitioner discussion was too thin to
pad the rule.*

## 8. Result - KILL

The one permitted run used the committed instrument at
`78cd3d4441e23de7608efa0b8644123ec0c83741`. It wrote the complete census,
actual-grid examples, summary, and manifest to
[`Results/2026-09-04-aski69-render-matcher-challenge/`](Results/2026-09-04-aski69-render-matcher-challenge/).
Every regime contains 8,640 cells. The production-recovery assertion and all synthetic instrument
checks passed before the run.

For `P`, the stored 60D descriptor is the shipping matcher representation under challenge. The
identical-raster constraint means that its selected glyph is scored through the same fixed mask bank
as each challenger, not that P is rebuilt from that bank and thereby changed before comparison.

### 8.1 Quality by charset

All arms found the registered blocks opportunity. Their MAE improvement against P was 43.82-50.77%
on `nasa-structure-v1` and 45.98-53.01% on `nasa-steerable-v1`. The high churn is real, not a no-op:
93.81-94.97% on the structure corpus and 95.90-100.00% on the steerable corpus.

The dense `standard` control rejects every arm:

| Arm | Structure standard | Steerable standard | Frozen failure |
| --- | --- | --- | --- |
| `A` | MAE +4.77%; GMSD improves 3.51% | MAE +3.66%; GMSD regresses 2.44% | Held-out GMSD exceeds the 1.0% no-harm cap. |
| `S1` | MAE +4.08%; GMSD improves 1.27% | MAE +3.30%; GMSD regresses 2.44% | Held-out GMSD exceeds the 1.0% no-harm cap. |
| `TF` | MAE regresses 1.12%; GMSD improves 8.71% | MAE regresses 2.79%; GMSD improves 11.72% | Dense MAE exceeds the 1.0% no-harm cap on both corpora. |

The signs are the important result. Aligned reconstruction improves its own MAE while harming the
held-out dense shape guard; tone-plus-fill improves GMSD while harming the house oracle. This
corroborates the published warning that local reconstruction overlap is not sufficient evidence for
glyph shape. Bounded one-pixel alignment does not resolve that failure. It produces nearly the same
quality as `A` at much higher cost.

### 8.2 Cost, memory, and complexity

No arm is close to the registered time budget. `A`, the least expensive challenger, costs 12.94x and
17.63x P on `blocks`, against a 4.0x limit, and 45.91x and 45.12x P on `standard`, against a 12.0x
limit. `S1` costs 134.39-180.02x on `blocks` and 468.29-481.19x on `standard`. `TF` costs
34.41-42.07x and 104.15-105.57x respectively.

The deterministic selector storage passes: 89,856 bytes for `blocks` and 290,304 bytes for
`standard`, both below 1 MiB. The shared-process maximum resident size was 474,775,552 bytes and is
descriptive only, as pre-registered. Total measurement wall time was 18.416 seconds.

The implementation remains contained in `AskiColorLab`. Production source files changed: zero.
Public APIs or defaults changed: zero. Permanent production matcher paths added: zero. Because no arm
is an objective candidate, there is no replacement task and no production complexity budget to open.

### 8.3 Mechanical disposition

**KILL.** `A` and `S1` fail condition 3. `TF` fails condition 2. Therefore the objective-candidate
set is empty and section 6.4 requires KILL. The cost failures reinforce the outcome but do not decide
it; memory passes.

The ASKI-62 arbiter trigger did not fire. The generated grids are not human or VLM votes, no existing
ASKI-62 response was reused, and no perceptual result was inferred. Human/VLM evidence is therefore
not a blocking dependency for this KILL. Keep the rule, artifacts, lab command, and Git history; add
no production option.
