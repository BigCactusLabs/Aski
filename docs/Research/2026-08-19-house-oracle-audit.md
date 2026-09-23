---
title: "House-Oracle Audit - MAE is adopted, GMSD is disqualified from defining an optimum, and the ranking-headroom margin turns out to be thinner than corpus variance"
slug: 2026-08-19-house-oracle-audit
date: 2026-08-19
status: complete
subsystem: [shape-context, frontier]
summary: "ASKI-27. Every archived descriptor verdict was decided by per-cell GMSD, which Ding, Ma, Wang and Simoncelli (IJCV 2021) rank last of eleven full-reference metrics used as an optimization objective and diagnose as luminance-blind. This audit screens five candidate per-cell oracles - GMSD, HaarPSI, MAE, RMSE and single-scale SSIM - with a disqualifier run first: make the source cell BE a rendered glyph, push it through the production scoring path, and require the oracle to make that glyph the unique argmin. MS-SSIM and the deep metrics are unreachable at a 24px footprint and are excluded by arithmetic, not by preference. Four results. First, at the footprint itself every oracle recovers every glyph on every charset, so no metric is blind in the trivial sense. Second, the screen separates them the moment the anisotropic cell geometry is added with the rasterizer held fixed: MAE, RMSE and single-scale SSIM recover 8 of 8, 95 of 95 and 256 of 256, while GMSD loses the half-block pair and 51 of 256 braille glyphs and HaarPSI loses 20 of 256. A metric that cannot recover a glyph from a picture of that glyph must not be the metric that defines the optimum, so MAE is adopted as the house oracle and GMSD and HaarPSI are demoted to cross-checks. The disqualification is scoped: it bars argmin and ceiling use, not the A-versus-B comparison of two realizable renderings the archived kills actually made, so no archived verdict flips. Third, a separate and oracle-independent loss is measured at the 24px footprint itself - all five oracles lose the same 1 of 8 blocks and about 70 of 256 braille references when a native-scale raster is resampled down - which is the footprint and the bounds-centering rasterizer discarding position, not any metric failing. Fourth, the selection ceiling is re-scored under all five oracles across oversample 2 through 32. Under the house oracle the dense-charset ranking headroom is 1.83 to 2.41 percent, below the 3.0 percent promotion bar at every arm including the 48-of-60-bin regime the kills were measured at - but the same measurement on the default corpus gives 2.88 to 3.93 percent, above the bar at oversample 4 and higher. The margin that re-read the kill record as unwinnable is thinner than the difference between two corpora, and that is the finding this note leaves. The tone-only inversion on the frozen sparse preset survives every oracle five out of five, which is the one result the audit strengthens rather than qualifies. Also recorded: the selection-ceiling reproduce command in the companion note omits --corpus and therefore reproduces a different corpus than the one it reports, worth up to 10 gap points."
related_specs: [docs/Research/Discoveries.md, docs/Research/2026-08-19-selection-optimality-gap.md, docs/Research/2026-08-19-sampling-lattice-support-collapse.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1]
runners: [AskiColorLab]
next_action: "The house oracle is MAE and every future per-cell arm must be built in the matcher's ink-high convention, because MAE is polarity- and calibration-sensitive - the cell arm of the screen shows exactly what it costs when the two sides are not rendered through the same path. Two follow-ups are now unblocked and one is not. ASKI-30 (tone-weighted score for sparse charsets) is unblocked and strengthened: the tone-only inversion on the frozen preset holds under all five oracles, and the house oracle puts the production pick at rank 7.22 of 8 there. ASKI-28 (pool-width sweep, dense charsets) stays low priority: under the house oracle the pool term is 2.85 to 3.08 percent. What is NOT unblocked is any magnitude claim about human-visible quality: the audit replaced an impeached metric with a screened one, it did not produce a perceptual arbiter, and the parked human-preference / VLM A-B instrument is still the missing measurement. Do not quote the dense-charset ranking headroom as a settled number without naming the corpus - the corpus moves it across the promotion bar."
---

# House-oracle audit

**Status:** SETTLED as a **decision**. It adopts an oracle, disqualifies two from one specific use, and
re-scores the ceiling under all five. It does not re-run any archived experiment and it does not settle
whether any of these metrics tracks human preference — see §6.

**Branch:** `aski-27-house-oracle` · **Date executed:** 2026-08-19 · **Task:** ASKI-27

**Supersedes, in part:** [2026-08-19 — Selection optimality gap](2026-08-19-selection-optimality-gap.md)
§4 and §5. That note's numbers all reproduce here byte-for-byte and none of them is withdrawn; what
changes is what may be concluded from the ranking-headroom figure (§4 below) and which oracle is allowed
to define an optimum (§3). The older note is left as written.

## 1. Question

Every archived descriptor verdict — ASTSK-31 regime oracle, ASTSK-35 basis augmentation, ASTSK-42
steerable channel — was decided by per-cell GMSD, cross-checked by HaarPSI. Two primary results impeach
that instrument:

- **Ding, Ma, Wang & Simoncelli, IJCV 2021** (arXiv 2005.01338) rank **GMSD last of 11** full-reference
  metrics used as an *optimization objective* in a four-task human study, and diagnose it as discarding
  local luminance. They find plain **MAE** competitive and name MAE and MS-SSIM the dominant robust
  objectives for denoising. Mechanically, GMSD pools by the **standard deviation** of the
  gradient-magnitude-similarity map, so a per-cell argmin rewards uniform mediocrity over a glyph that is
  right across most of a cell and wrong in one corner.
- **Xu, Zhang & Wong, SIGGRAPH 2010, Fig. 7** already showed, for glyph selection specifically, that the
  loss-optimal pick under alignment-sensitive full-reference metrics is perceptually wrong.

Two further cautions carried from the record: GMSD and HaarPSI are **not a disjoint pair** (both are
gradient/wavelet structure metrics), and HaarPSI pools with a **global denominator**, so a strict per-cell
argmax under it is not cleanly well-posed.

So: what should the house oracle for per-cell pick quality be?

## 2. Instrument

### 2a. The candidate panel, and what is excluded by arithmetic

| oracle | family | luminance-aware | separable | polarity-sensitive |
| --- | --- | --- | --- | --- |
| GMSD | gradient structure | no | no | no |
| HaarPSI | wavelet structure | no | no | no |
| **MAE** | pixel distance | yes | yes | **yes** |
| RMSE | pixel distance | yes | yes | **yes** |
| SSIM (single-scale) | structure + luminance + contrast | yes | no | no |

**MS-SSIM is excluded, and not by preference.** Its five-scale pyramid halves the image four times and
needs roughly **161px** a side; the scoring footprint is **24px**. It cannot be evaluated here at all, so
the Ding et al. recommendation transfers only through its other half, MAE. Single-scale SSIM is the
reachable stand-in. LPIPS, DISTS and MILO fail the same test by a wider margin — their receptive fields
are larger than the whole cell — so no deep metric is a candidate at this footprint.

### 2b. AC#2, run first, as a disqualifier

The screen (`ReferenceRecovery`, exposed as `AskiColorLab reference-recovery`) makes the weakest possible
demand on a full-reference metric: **the source cell IS a rendered glyph**, pushed through the production
scoring path — candidate rasterized at the 24px footprint, source resampled to the same footprint by the
same validated `LumaResample` — and the oracle must name the glyph it was handed. A metric that cannot
recover a glyph from a picture of that glyph is not measuring glyph choice.

Four source constructions are run, and separating them is the point. A single arm cannot distinguish *the
oracle is blind* from *the footprint threw the information away before the oracle saw it*:

| arm | source | isolates |
| --- | --- | --- |
| `footprint` | glyph rendered at 24×24; resample is an identity | the oracle alone — **gate** |
| `square` | glyph rendered at 96×96 → 24×24 | + downscale loss at fixed aspect |
| `roundTrip` | 24×24 raster stretched to the cell block and resampled back | + the cell's anisotropy, rasterizer held fixed — **gate** |
| `cell` | glyph rendered into the 38×76 native cell block → 24×24 | production geometry, **confounded** (below) |

The cell block is the converter's own — resolved through `samplingGeometry` and taken through
`SampledSource`, never an equal `rows × cols` partition (the error that inflated dense-charset gaps 2–6×
in the companion note, and the same root cause as ASKI-25).

**Why `cell` is reported but not gated.** `GlyphRaster` sizes the font to the raster *height*, so drawing
a glyph into a 1:2 block clips it at the sides and lands it on an ink fraction that is not calibrated
against the square candidate. That is a property of how the probe drew the reference, not of the oracle,
and in production the source cell is a photograph rather than a rendered glyph. `roundTrip` is the same
geometry with the rasterizer held fixed, which is why it, not `cell`, is the geometry gate.

> **Corrected — see [§9](#9-corrections).** The `roundTrip` row's "gate" label and the paragraph above
> overstate what that arm is. `roundTrip` builds its source *from* the 24×24 footprint raster, so it never
> carries more information than the footprint did: it is a **blur-tolerance control**, not the production
> downscale. The numbers are unchanged; what they license is narrower.

**Polarity.** MAE and RMSE compare absolute tone, so both sides run in the matcher's own convention:
`GlyphRaster.luma` is ink-high, and the pre-filter maps high source L to high ink density. This is now a
standing requirement — see §7.

### 2c. AC#3, run as a bound rather than a re-run

Re-running an archived experiment under a new oracle would re-litigate a verdict; re-scoring the
**ceiling** bounds what any ranker could have won, and a bound that stays under the promotion bar holds
the verdict without re-running anything. The selection-ceiling probe is re-run under all five oracles,
over oversample 2, 4, 8, 16 and 32 — reaching the **48-of-60-bin** regime the archived kills were measured
at, not only the shipping oversample-2 arm — with an exhaustive cell census (8640 cells per arm).

## 3. The screen disqualifies the two incumbents

Full screen, `columns: 80`, `oversample: 2`, 24px footprint, 3072px cell block. `unique` = reference is
the sole argmin; `MISS` = the oracle strictly preferred a different glyph.

| arm | oracle | blocks (8) | standard (95) | braille (256) |
| --- | --- | --- | --- | --- |
| `footprint` | **all five** | **8 / 8** | **95 / 95** | **256 / 256** |
| `roundTrip` | **MAE** | **8 / 8** | **95 / 95** | **256 / 256** |
| `roundTrip` | **RMSE** | **8 / 8** | **95 / 95** | **256 / 256** |
| `roundTrip` | **SSIM** | **8 / 8** | **95 / 95** | **256 / 256** |
| `roundTrip` | GMSD | 7 / 8 (`▄→▀`) | 95 / 95 | **205 / 256** (`⠂→⠈`) |
| `roundTrip` | HaarPSI | 8 / 8 | 95 / 95 | **236 / 256** (`⠁→⢀`) |

**No oracle is blind in the trivial sense.** At the footprint itself, with the resample an identity, all
five recover every reference on every charset. That matters: it means the failures below are not an
artifact of some metric being degenerate on binary rasters.

**The separation appears the moment the cell's anisotropy is added.** The `roundTrip` arm changes exactly
one thing — the picture takes a trip through the converter's own 38×76 cell block and back — and it
splits the panel cleanly along the luminance-awareness axis the IJCV ranking names. The three
luminance-aware oracles are perfect on all three charsets. GMSD loses **51 of 256** braille references and
confuses the **half-block pair on the shipping charset**: `▄→▀` is a pure vertical position swap with
identical ink, which is the textbook luminance-blind confusion. HaarPSI loses 20 of 256.

> **Corrected — see [§9](#9-corrections).** "the cell's anisotropy is added" is right; "therefore the
> production sampling path" is not. The `roundTrip` arm is a blur-tolerance control, so these failures are
> evidence that GMSD and HaarPSI lose glyph identity under a mild anisotropic softening — not a
> measurement of the native-block downscale. §9 states what the disqualification rests on instead, and the
> counter-evidence in §3b that is not yet answered.

> **Decision (AC#1).** **MAE is adopted as the house oracle** for per-cell pick quality: it is
> luminance-aware, separable, the cheapest of the panel, the one Ding et al. find competitive, and the
> only family that is perfect on both gating arms across all three charsets. RMSE is retained as its
> same-family cross-check and single-scale SSIM as the disjoint one. **GMSD and HaarPSI are disqualified
> from defining an optimum** — no argmin, no ceiling, no "loss-optimal pick" under either — and are kept
> only as comparators.

**The disqualification is scoped, and the scope is load-bearing.** Naming an argmin over 95 candidates is
a far stronger demand than ranking two realizable renderings A and B. The archived kills made the *second*
kind of measurement: ASTSK-35 and ASTSK-42 compared a base render against an augmented render, cell by
cell. Nothing here says GMSD cannot do that. **No archived verdict flips on this decision** (AC#4: the
supersede protocol therefore fires only for the reading change in §4, not for a verdict).

### 3a. An oracle-independent loss, which is the footprint's fault and not a metric's

| arm | GMSD | HaarPSI | MAE | RMSE | SSIM |
| --- | --- | --- | --- | --- | --- |
| `square`, blocks | 7 / 8 | 7 / 8 | 7 / 8 | 7 / 8 | 7 / 8 |
| `square`, standard | 95 / 95 | 94 / 95 | 94 / 95 | 95 / 95 | 93 / 95 |
| `square`, braille | 186 / 256 | 185 / 256 | 188 / 256 | 185 / 256 | 185 / 256 |

Five metrics with different failure modes lose **the same** references, within a spread of 3 on a base of
256. That is not five oracles failing; it is one bottleneck upstream of all of them. Two things compose
into it: the 24px footprint, and `GlyphRaster` centring each glyph by its **image bounds**
(`Tools/AskiToolSupport/GlyphRaster.swift`, the `CTLineGetImageBounds` centring), which erases
position-only distinctions — `▄` and `▀` become the same centred bar, and single-dot braille glyphs
collapse onto each other. **Any lab result about position-sensitive charsets read through `GlyphRaster` is
bounded by this**, independently of which oracle scored it.

### 3b. The `cell` arm, reported with its confound

| oracle | blocks | standard | braille | mean reference rank, braille |
| --- | --- | --- | --- | --- |
| GMSD | 3 / 8 | 31 / 95 | 168 / 256 | 2.40 |
| HaarPSI | 5 / 8 | 27 / 95 | 180 / 256 | 1.54 |
| MAE | 4 / 8 | 34 / 95 | **7 / 256** | **16.06** |
| RMSE | 5 / 8 | 31 / 95 | 24 / 256 | 10.50 |
| SSIM | 6 / 8 | 27 / 95 | 183 / 256 | 1.49 |

Under a source whose ink fraction was changed by the rasterizer, the tone-sensitive oracles collapse
(MAE recovers 7 of 256; its worst confusion is `⣿→⠀`, a full braille cell read as blank) while the
structure oracles are near-invariant. `roundTrip` proves this is the **rasterizer**, not the geometry:
the same anisotropy with a calibrated source leaves MAE perfect. Read it as the price of luminance
awareness — **the house oracle is only trustworthy when both sides are rendered through the same path** —
and as the exact mirror of GMSD's luminance blindness. It is not evidence against the decision in §3; it
is the condition attached to it.

> **Corrected — see [§9](#9-corrections).** "`roundTrip` proves this is the rasterizer, not the geometry"
> claims more than the arm can carry: `roundTrip` never renders into the block, so it cannot separate the
> rasterizer from anything a real anisotropic downscale does. This table is the audit's **open
> counter-evidence** — on the one arm that actually draws into the cell block, MAE recovers 7 of 256
> braille glyphs where GMSD recovers 168 — and §9 says what it would take to answer it.

## 4. The ceiling under the house oracle — and the margin that does not survive

Re-scored ceiling, `columns: 80`, exhaustive census (8640 cells/arm), `nasa-steerable-v1`. `rankGap` is
the term the +3.0% promotion bar was written against: what a *perfect ranker inside the pool the matcher
saw* would have won.

**`standard` (95 glyphs) — the dense charset the archived gates were scored on:**

| oversample | reachable bins | GMSD rankGap | HaarPSI | **MAE (house)** | RMSE | SSIM |
| --- | --- | --- | --- | --- | --- | --- |
| 2 (shipping) | 3 / 60 | 2.26% | 4.21% | **1.83%** | 1.59% | 4.29% |
| 4 | 11 / 60 | 4.20% | 3.80% | **2.41%** | 2.59% | 4.29% |
| 8 | 30 / 60 | 2.46% | 4.18% | **2.29%** | 2.07% | 4.06% |
| 16 | 42 / 60 | 2.53% | 4.03% | **2.09%** | 1.94% | 4.23% |
| 32 | 48 / 60 | 2.44% | 4.14% | **2.19%** | 1.99% | 4.22% |

**Under the house oracle the ranking headroom at the nearest measurable regime remains below the +3.0%
bar at every arm**, including `oversample: 32`, which is the 48-of-60-bin support the archived kills were
measured at. On its own that holds the companion note's §4 reading.

**It does not survive the corpus.** The same measurement on the harness's *default* corpus
(`nasa-structure-v1`, 2048px — the corpus the ShapeResidual battery uses for the general axis, i.e. closer
to the archived kill runs than the corpus the companion note reported):

| oversample | GMSD rankGap | **MAE (house)** |
| --- | --- | --- |
| 2 (shipping) | 4.21% | **2.88%** |
| 4 | 7.97% | **3.93%** |
| 8 | 3.93% | **3.53%** |
| 16 | 3.95% | **3.50%** |
| 32 | 4.03% | **3.54%** |

> **The margin that re-read the kill record as unwinnable is thinner than the difference between two
> corpora.** Under the house oracle the dense-charset ranking headroom is 1.8–2.4% on one corpus and
> 2.9–3.9% on the other, straddling the bar. The companion note's §4 sentence — "a perfect ranker would
> have moved `standard` GMSD by less than the bar it had to clear" — is true as measured and false as a
> general claim. **No verdict flips** (the kills were A/B measurements, not ceiling claims), but the
> *inference* that they were unwinnable-by-construction is not robust and should not be quoted without
> naming the corpus.

**A defect in the companion note's reproduce command, which is how this surfaced.** Its §8 command passes
no `--corpus`, so it silently runs `nasa-structure-v1` while the note reports `nasa-steerable-v1` — worth
up to 10 gap points. With the corpus passed explicitly, **every number in that note reproduces exactly**
(blocks GMSD 51.65%, HaarPSI 327.38%, MAE 61.78%, meanRank 3.75/8; standard GMSD 18.71%/2.26%; braille MAE
3.58%), which is also the check that the two oracles added here are inert on the incumbents. The
`--corpus` help text now states the trap.

> **Harness change since this run — see [§9](#9-corrections).** `selection-ceiling --corpus` now defaults
> to the 3072px `nasa-steerable-v1` corpus, the one this note and its companion report, and the same
> native side the screen resolves its cell block from. The trap described above is closed at the root: the
> companion note's §8 command now reproduces the numbers the companion note states. Every figure in this
> section was re-measured after the change and is unchanged. To reproduce the `nasa-structure-v1` column,
> pass that corpus explicitly (§8).

### 4a. What the house oracle says about the shipped preset

The one result the audit **strengthens**. On the ASTSK-47-frozen sparse preset (`blocks`), a shape-free
matcher that picks by ink coverage alone beats the real matcher under **all five** oracles:

| oracle | production | toneOnly | winner |
| --- | --- | --- | --- |
| GMSD | 0.33993 | **0.20278** | tone-only |
| HaarPSI | 0.09480 | **0.38673** | tone-only |
| **MAE (house)** | 0.56329 | **0.24637** | **tone-only, by 2.3×** |
| RMSE | 0.63874 | **0.26377** | tone-only |
| SSIM | 0.00214 | **0.30568** | tone-only |

Unanimous, and it compares two *realizable* selectors rather than a selector against an unreachable
argmin — so it never depended on the disqualified oracles in the first place. Under the house oracle the
production pick on `blocks` averages rank **7.22 of 8**. On the dense charsets production wins under all
five (MAE by 2.4% on `standard`, 0.6% on `braille`). ASKI-30 is the follow-up and this run raises its
priority.

## 5. What each acceptance criterion landed on

| AC | outcome |
| --- | --- |
| #1 luminance-aware separable objective adopted or rejected, documented as house oracle | **Adopted: MAE**, with the same-path/ink-high precondition of §3b and §7. RMSE and single-scale SSIM retained as cross-checks; GMSD and HaarPSI demoted (§3). |
| #2 reference-recovery screen run as a disqualifier, per oracle, per charset | **Run first**, five oracles × three charsets × four arms. Gating arms: `footprint` (all pass) and `roundTrip` (MAE/RMSE/SSIM pass; GMSD and HaarPSI fail). Zero soft-fail ties anywhere — every failure is a strict miss (§3). |
| #3 at least one archived decisive run re-scored, verdict held or flipped | Taken as a **bound**, per the task's own note: the ceiling is re-scored under all five oracles over oversample 2–32. Headroom **holds below the bar on `nasa-steerable-v1`, crosses it on `nasa-structure-v1`** (§4). |
| #4 if a verdict flips, supersede rather than edit | **No verdict flips.** The §4 *reading* changes, so this note supersedes the companion's §4/§5 in place of editing them, and a forward pointer was added to the older note without touching its numbers or its verdict. |

> **Corrected — see [§9](#9-corrections).** The AC#2 row calls `footprint` and `roundTrip` "gating arms".
> `footprint` is a gate; `roundTrip` is a blur-tolerance control. AC#2 is still met — the screen ran first
> and did disqualify two oracles — but on blur evidence plus the IJCV prior, not on production geometry.

## 6. Limits

- **This is not a perceptual arbiter.** The audit replaced an impeached metric with a screened one. Every
  metric here is still a reconstruction metric, and Blau & Michaeli's perception–distortion tradeoff still
  says a lower distortion is not a promise of a preferred picture. The parked human-preference / VLM A-B
  instrument (Discoveries, 2026-07-06 and 2026-07-29) remains the missing measurement, and Xu et al.'s
  Fig. 7 is a direct warning that full-reference-optimal glyph picks can be perceptually wrong.
- **Reference recovery is a necessary condition, not a sufficient one.** Passing it means the oracle is
  not blind to a distinction that matters; it says nothing about whether its ordering of *wrong* answers
  matches a human's.
- **Corpus and column count.** Two corpora, three fixtures each, one column count, one tile shape. The
  cell census is exhaustive; the corpus is not a sample of anything. The archived ASTSK-31/35/42 arms also
  ran different column counts and score an equal `rows × cols` partition rather than the converter's
  sampled rectangle, so their absolute magnitudes are **not** directly comparable with these — which is
  why AC#3 is phrased as a bound at the nearest measurable regime rather than as a re-run.
- **Percentages under the higher-is-better oracles are normalized by a production score that can be near
  zero.** SSIM on `blocks` reports a 14778% gap because production scores 0.00214, not because anything is
  four orders of magnitude wrong. Read SSIM's gaps on dense charsets only, and read `blocks` through
  `meanRank` and the §4a head-to-head.
- **`GlyphRaster` bounds-centring bounds every arm** that depends on glyph position (§3a), the audit
  included.
- **No arm measures the production downscale with a calibrated source.** `roundTrip` is a blur control and
  `cell` is confounded by the rasterizer, so the screen bounds blur tolerance, not anisotropic sampling.
  The `cell` arm's inversion (MAE 7/256 against GMSD 168/256 on braille) is open counter-evidence, and
  answering it needs an instrument this branch does not build — see [§9](#9-corrections).

## 7. Standing rules this note sets

1. **The house oracle is MAE.** Any new per-cell pick-quality arm reports MAE first; RMSE and single-scale
   SSIM are the cross-checks. GMSD and HaarPSI may appear for comparability with the archived record but
   **must not define an optimum** — no argmin, no ceiling, no "loss-optimal" claim.
2. **MAE is polarity- and calibration-sensitive, so every future arm must be built in the matcher's own
   convention** — `GlyphRaster.luma` ink-high, high source L to high ink density — and **both sides must
   be rendered through the same path**. §3b is what happens when they are not.
3. **A new oracle passes the screen before it scores anything.** `AskiColorLab reference-recovery` is the
   gate; `AskiColorLabReferenceRecoveryTests` keeps the shipping-charset case firing in `just check`.
4. **Name the corpus.** Any quoted gap or headroom figure states which corpus produced it (§4).
5. **Record the regime.** Following ASKI-29 AC#2, the ShapeResidual harness now prints the resolved cell
   footprint and reachable-bin count next to every ρ it reports, so a verdict read at 48 of 60 bins can
   never again be quoted against a preset that runs at 2 or 3.

## 8. Reproducing

```bash
# The screen (AC#2). ~18s in release; the debug build is ~70x slower.
swift run -c release AskiColorLab reference-recovery

# The re-scored ceiling (AC#3). --corpus now DEFAULTS to nasa-steerable-v1, so
# these reproduce with or without it; it is passed here so the command still
# states which corpus produced the numbers (§7 rule 4).
swift run -c release AskiColorLab selection-ceiling --charset blocks,standard \
  --columns 80 --oversample 2,4,8,16,32 \
  --corpus docs/Research/Corpus/nasa-steerable-v1/assets
swift run -c release AskiColorLab selection-ceiling --charset braille \
  --columns 80 --oversample 2 --corpus docs/Research/Corpus/nasa-steerable-v1/assets

# The nasa-structure-v1 column of §4 needs that corpus passed explicitly:
#   --corpus docs/Research/Corpus/nasa-structure-v1/assets
```

## 9. Corrections

**2026-08-19 — `roundTrip` is a blur-tolerance control, not production geometry.** Caught by an automated
code review of this branch, before merge. The original text of §2b, §3, §3b and §5 is left as written;
this section says what is withdrawn and what replaces it.

**The mechanism.** The `roundTrip` arm renders each glyph at the 24×24 scoring footprint, upsamples that
raster into the 38×76 cell block, and resamples it straight back to 24×24. Its source is *built from the
footprint*, so it can never carry more information than the footprint already held. What the arm varies is
**blur** — an anisotropic resample round trip and the tone shift it causes. Production does the opposite
trip: it starts from a genuine 38×76 block of photographic content at native resolution and downscales it
once. `roundTrip` does not measure that path, and no arm of this screen does with a calibrated source.

**Withdrawn.** The "**gate**" label on the `roundTrip` row of the §2b table; the §2b sentence "`roundTrip`
is the same geometry with the rasterizer held fixed, which is why it, not `cell`, is the geometry gate";
the §3b sentence "`roundTrip` proves this is the **rasterizer**, not the geometry"; the phrase "gating
arms" applied to `roundTrip` in the §5 AC#2 row; and any reading in which a `roundTrip` failure is
evidence about the production sampling path.

**Not withdrawn.** Every number. The screen reproduces byte-for-byte after the correction — `blocks` GMSD
7/8 (`▄→▀`), `braille` GMSD 205/256 and HaarPSI 236/256, MAE/RMSE/SSIM perfect on all three charsets at
`roundTrip`, all five perfect at `footprint`. The correction is to what those numbers license, not to what
they are.

**What the disqualification rests on now.** Three things, and it is worth being explicit that none of them
is a production-path measurement:

1. **The `footprint` arm.** All five oracles recover every reference when the resample is an identity. That
   is what makes any later failure interpretable: the oracles are not degenerate on binary glyph rasters,
   so when one stops recovering, something specific was added.
2. **A blur control.** The only thing `roundTrip` adds is an anisotropic softening. Under it, GMSD loses 51
   of 256 braille references and the half-block pair on the shipping charset — `▄→▀`, a pure vertical
   position swap at identical ink — while the three luminance-aware oracles stay perfect. Blur is not an
   exotic condition for this pipeline; every production cell is a downscale of a larger block. But the
   evidence is "blind to blur and to the tone shifts blur causes", not "blind at the production footprint".
3. **Ding, Ma, Wang & Simoncelli, IJCV 2021** (arXiv 2005.01338), which ranks GMSD **last of eleven**
   full-reference metrics used as an optimization objective and diagnoses the same mechanism — discarded
   local luminance — independently of anything measured here.

A prior plus a reproduced failure mode under blur is enough to stop letting GMSD *define* an optimum. It
is not enough to claim GMSD fails at the geometry the converter actually samples.

**The counter-evidence, stated plainly.** §3b is not a footnote to the decision; it is the strongest
argument against it, and it is unanswered. On the `cell` arm — the only arm that actually draws the
reference into the converter's own 38×76 block — the ranking **inverts**: MAE recovers **7 of 256** braille
glyphs where GMSD recovers **168**, and MAE's worst confusion is `⣿→⠀`, a full braille cell read as blank.

That arm is confounded, and the confound is specific: `GlyphRaster` sizes the font to the raster
**height**, so drawing a glyph into a 1:2 block makes it twice as tall as the block is wide and clips it at
the sides, and the ink fraction it lands on is not calibrated against the square 24×24 candidate it will be
compared with. A tone-sensitive oracle is then being asked to match two different ink fractions, which it
cannot do and a structure oracle need not. So the arm does not, as written, refute the decision.

**But "confounded" is not "answered".** The confound explains how the inversion *could* be an artifact; it
does not show that it is. The only instrument that would settle it is an anisotropic arm built correctly —
the reference drawn into the native block at a calibrated ink fraction, or a photographic source block
rather than a rendered glyph — and this branch does not build one. Until it exists, the honest position is:
MAE is adopted on the evidence in this section, and the one arm that comes closest to production geometry
points the other way for reasons that are plausibly, but not demonstrably, instrumental. That follow-up is
filed as a separate task by the repo owner and **gates ASKI-30's decisive run**: ASKI-30 reads pick quality
on `blocks` under the house oracle, and if the house oracle is wrong under real anisotropic sampling, so is
that verdict.

> **Resolved, 2026-08-23, by
> [2026-08-23 — Calibrated production-geometry recovery](2026-08-23-aski32-calibrated-recovery.md)
> (ASKI-32).** The gap this correction leaves open is closed, not narrowed: that note builds the
> anisotropic arm called for above — `GlyphCellRaster`, the reference drawn into the native 38×76 block
> at a calibrated, measured ink fraction (not assumed) instead of `GlyphRaster`'s height-keyed, clipped
> one — and the inversion **disappears entirely** on it. Every oracle recovers every glyph on every
> charset through the calibrated gate (8/8, 95/95, 256/256), so the gate is a validity check, not a
> discriminator; GMSD's disqualification rests on the blur control, its lone failure against the
> matcher's braille vocabulary at production geometry, and the IJCV prior (companion note §3, §3c).
> Nothing here is withdrawn: the house oracle is **reaffirmed on repaired evidence**, ASKI-30's decisive run
> is unblocked, and two standing rules are added going forward — a future oracle must pass the
> `calibratedSamePath` arm, not just `footprint`; and any raster comparison states which drawing
> convention (`GlyphRaster` bounds-centred vs `GlyphCellRaster` typographic) produced each side. The
> companion note's `calibratedCell` arm also surfaces a separate finding — the matcher's bounds-centred
> **text-charset** candidate rasters fail recovery under all five oracles, while braille's
> position-faithful dot vocabulary recovers under every luminance-aware one — which is a
> selection-machinery question, not a reason to revisit this section.

**2026-08-19 — three harness corrections landing with this note.** None of them moves a number in it; all
three were verified by re-running the screen and the ceiling.

- **`selection-ceiling --corpus` now defaults to `nasa-steerable-v1`** (3072px), matching the native side
  `reference-recovery` resolves its cell block from and the corpus both 2026-08-19 notes report. §4's
  "harness's default corpus" wording describes the state at the time of the run; the trap it documents is
  now closed at the root, and the companion note's §8 command reproduces the companion note's numbers.
- **Reference-recovery rank accounting.** A reference the oracle could not score was dropped from the
  rank numerator while the mean still divided by the full charset, so an oracle that failed on *every*
  glyph would have printed a mean rank better than perfect. Unscoreable references are now charged the
  worst possible rank and counted in a fourth `invalid` bucket — which also closes the case where every
  competing candidate is non-finite and the reference was recorded as a unique recovery for want of an
  opponent. The bucket is zero on every row of this note's screen.
- **A degenerate-denominator floor on the ceiling's gap percentages.** They normalize by the mean
  production score, and single-scale SSIM is the first oracle in the panel that can average near zero;
  below 1e-6 the ratios now report `nan` instead of an unbounded percentage. The floor is three orders of
  magnitude under the smallest mean reported here (SSIM on `blocks`, 0.00214), so the 14778% figure in §6
  stands.

## 2026-09-04 metric-audition cross-check

A current-path, exact-lattice ASTSK-42-style replay added two structurally
different comparators: contrast-weighted SSIM and the pinned official MILO raw
error. Both held the archived KILL at shipping 3-of-60 support and at a separate
48-of-60 comparator; MAE, GMSD, and 1-HaarPSI also held, so the agreement
protocol did not fire. This strengthens the no-reversal conclusion but does not
change MAE's sole house-oracle role: MILO at 24x24 remains outside its published
full-image benchmark setting. See
[the ASKI-29/50 replay](2026-09-04-aski29-50-steerable-metric-replay.md).

## Sources

- Ding, Ma, Wang, Simoncelli, *Comparison of Full-Reference Image Quality Models for Optimization of Image
  Processing Systems*, IJCV 2021 (arXiv 2005.01338) — GMSD ranked last of 11 as an optimization objective
  and diagnosed as luminance-blind; MAE competitive; MS-SSIM's advantage over MAE not statistically
  significant.
- Xu, Zhang, Wong, *Structure-based ASCII Art*, ACM TOG 29(4):52 / SIGGRAPH 2010 — Fig. 7, full-reference-
  optimal glyph picks that are perceptually wrong; also the source of the 60-bin design.
- Wang, Simoncelli, Bovik, *Multiscale Structural Similarity for Image Quality Assessment*, Asilomar 2003 —
  the five-scale pyramid whose scale requirement puts MS-SSIM out of reach at a 24px footprint.
- Blau & Michaeli, *The Perception-Distortion Tradeoff*, CVPR 2018 — why §6 refuses to read any of this as
  perceptual headroom.
- [2026-08-19 — Selection optimality gap](2026-08-19-selection-optimality-gap.md) and
  [2026-08-19 — Sampling-lattice support collapse](2026-08-19-sampling-lattice-support-collapse.md) — the
  two notes that filed this task; every number in the first reproduces here on its stated corpus.
- [`ReferenceRecovery`](../../Tools/AskiColorLab/SamplingLattice/ReferenceRecovery.swift) and
  [`SelectionCeiling`](../../Tools/AskiColorLab/SamplingLattice/SelectionCeiling.swift) — the screen and
  the re-scored ceiling.
