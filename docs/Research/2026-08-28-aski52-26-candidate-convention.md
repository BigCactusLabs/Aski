---
title: "ASKI-52 / ASKI-26 - What the Bounds-Centred Square Candidate Convention and the Single-Disc Support Actually Cost"
slug: 2026-08-28-aski52-26-candidate-convention
date: 2026-08-28
status: complete
subsystem: [shape-context, tile-grid]
summary: "Measurement, not a promotion, and it supersedes its own first version. A cross-model review caught two defects in the instrument before publication: the query field was sampled in raw luma where production uses 1 minus luma (LogPolarKernel.baseInvertedLuma), and the square baseline rung rasterized text at 64pt where BuildStandardVectors uses 32pt into the same 64x64 canvas. Both are confirmed against production source and fixed, and together they had invalidated the first run central claim, which is retracted here: the ladder does NOT show the query support carrying the production gap, because corrected there is no gap - rung (i) reproduces production at MAE 0.66651 against 0.66651 with 100.0 percent pick agreement. On the two tasks themselves the answer is unfavourable. Held at production own polarity the position-faithful vocabulary is inert to harmful, plus 0.04 percent on blocks steerable and minus 1.26 percent on occupancy, and negative on standard everywhere; the paper tiled construction is a small consistent win on text only, plus 1.93 and plus 0.68 percent, under the standing 3.0 percent bar in every cell. The largest effect found belongs to neither task: production shape term inverts the query while its tone pre-filter, its renderer and its ink-high candidate rasters all treat ink as bright, and flipping only that recovers 0.306 and 0.247 MAE on blocks and lifts SSIM from about 0.004 to 0.307 and 0.105 - subject to the caveat that the scoring oracle shares the direct convention. Bounds-centring at true cell aspect still edges out position-faithful on blocks in all four polarity-by-corpus cells, but by only about 0.75 to 1.5 percent: a third review pass found that the larger 12 to 26 percent gap an earlier revision reported was a scale-and-rasterization confound between those two rungs, now removed by putting both placements on one path at one point size. The census runs at both polarities over 27 NASA fixtures; tiled arms did not go degenerate (72 windows, 4320-D); a loader defect fixed in the course of the work made the JPEG-only occupancy corpus reachable for the first time, and its engineering-diagram fixtures carry 0.33 to 0.69 live bins of 60."
related_specs: [docs/Research/Discoveries.md, docs/Research/2026-08-19-sampling-lattice-support-collapse.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-occupancy-v1]
runners: [AskiColorLab]
next_action: "No promotion. The position-faithful vocabulary is not warranted on this evidence and the follow-up PR should record a decline unless the perceptual arbiter says otherwise. The query-polarity inconsistency is FILED AS ASKI-60 - the largest effect found here and belonging to neither ASKI-52 nor ASKI-26: production shape term uses 1 minus luma while its tone pre-filter, renderer and candidate rasters treat ink as bright. ASKI-60 is scoped measure-first and needs its own gate, because the scoring oracle used here shares the direct convention, so this run is a strong signal rather than a closed proof; it also carries an acceptance criterion to re-check whether any archived descriptor verdict was measured under the inconsistency. A polarity flip would NOT churn the .bin files - the inversion is confined to LogPolarKernel and candidate vectors are query-independent - but it would churn snapshot goldens. Second open question: why bounds-centring at true cell aspect beats position-faithful on blocks in all four cells. The .bin churn cost of any promotion is in section 6 and needs a deliberate ruling on the frozen digests, whose own comment forbids re-recording."
---

# ASKI-52 / ASKI-26 — the candidate convention and the sampling support, measured

**Status:** SETTLED as a **measurement**. This note establishes numbers and an instrument.
It does **not** promote anything, and it should not be read as a verdict for or against the
paper's convention. Vocabulary promotion is a separate follow-up PR, gated on the standing
ASKI-56 arbiter rule.

**Branch:** `aski-52-26` · **Date executed:** 2026-08-28
**Results:** [`Results/2026-08-28-aski52-26-convention-ablation/`](Results/2026-08-28-aski52-26-convention-ablation/)
(`geometry.csv`, `convention-delta.csv`, `ablation-ladder.csv`, `summary.md`, `result.yaml`; the
companion `direct` run is in `direct-polarity/`)

## 1. The two claims under test

**ASKI-52.** The matcher's candidate glyphs are rasterized *bounds-centred into a 64×64
square*: `CTLine` image bounds are taken and the ink is centred in a square canvas. Two
things are destroyed. Position — `▄` and `▀` become the same centred bar, and a glyph's
placement relative to its cell is gone. Aspect — a text cell is roughly 1:2, and squaring
it stretches every candidate against every query.

**ASKI-26.** The query and the candidate are not sampled on the same support. The shipped
path takes one inscribed disc over an anisotropic source cell and one inscribed disc over
a square candidate raster, and compares the two 60-D results. That is not a comparison of
like with like.

Both are properties of the *candidate side* and of the *comparison*, not of the source
image, so both are measurable without changing any default.

## 2. Grounding

- **Xu, Zhang & Wong, *Structure-based ASCII Art*, ACM TOG 29(4), SIGGRAPH 2010** —
  <https://ttwong12.github.io/papers/asciiart/asciiart.pdf>. The paper samples a *tiled*
  lattice of overlapping log-polar windows at stride 2 across the whole cell (5×12 bins
  per window, radius = half the shorter side) and concatenates them, so a 12×24 cell
  carries 72 windows and 4320 dimensions. It applies **the same pattern to both sides**,
  applies a 7×7 Gaussian pre-blur to both, and preserves position deliberately — its
  Fig. 7 faults plain shape context precisely for ignoring position. The paper
  under-specifies typographic placement, and **bounds-centring has no support in it**.
  Aski ships a single window, N = 1, 60 dimensions. The parity claim previously carried
  in `ASCIICharacterSet.swift` was wrong on both counts (construction and venue — it said
  SIGGRAPH Asia) and is corrected in this change.
- **Chafa** is the open-source precedent for the alternative: advance-box centring on a
  shared baseline, with FreeType bearings kept
  (`tools/chafa/chicle-font-loader.c`). Position-faithful placement is what a mature
  terminal-art renderer actually does.
- **GMSD is exactly degenerate on flat patches** — zero gradients make GMS constant at 1,
  so the deviation is 0 — which is why a blank candidate can score perfectly against a
  flat source. GMSD stays disqualified from defining an optimum under the ASKI-27 house
  rule, and every gate in this note is **MAE-first**.

## 3. The instrument

One shared sampler, `LogPolarCellSampling`, is called on **both sides** in every arm, so
an arm's query and its candidates always share a pixel geometry and a configuration. The
query is the converter's own resolved native source block, read back through
`samplingGeometry` so the lattice is the one the converter actually read, and
`LumaResample`d to the arm's candidate geometry before sampling.

Held constant across every arm: the selector shape (prune to the 12 brightness-nearest,
then descriptor argmin — production's own shape), the rendering path used for scoring (one
`GlyphCellRaster` at the sampling cell, resampled once to the 24-px footprint), and the
gate (pick quality against the source cell, MAE-first, never descriptor distance — a
convention that shrinks its own distances has not thereby chosen better glyphs).

**The five rungs.** Each walks exactly one step:

| rung | candidate placement | support | isolates |
| --- | --- | --- | --- |
| (i) `squareSingleDisc` | bounds-centred 64×64 | 1 disc | the shipped convention, given matched support |
| (ii) `rectSingleDisc` | bounds-centred at cell aspect | 1 disc | what the *square* costs |
| (iii) `faithfulSingleDisc` | position-faithful at cell aspect | 1 disc | what *bounds-centring* costs |
| (iv) `faithfulTiled` | position-faithful | tiled AISS + 7×7 blur | what the *single disc* costs |
| (v) `faithfulTiledNoBlur` | position-faithful | tiled AISS, no blur | how much of (iv) is the blur |

**Regime.** Release build, columns 80, oversample 2, converter defaults, exhaustive census
(stride 1) over every cell of all 27 fixtures — 8,640 cells on `nasa-steerable-v1` and
66,880 on `nasa-occupancy-v1`, per charset. Charsets `blocks`, `standard`, `braille`.
The exact reproduce command is in `summary.md`.

### 3.1 Two instrument defects, caught by cross-model review before publication

Per house practice, instrument corrections are recorded rather than quietly folded in. A
cross-model (`codex`) review of the first version of this census found two defects, both
confirmed against production source before any change was made. **Together they invalidated
this note's original central claim**, which is why they are documented here at length rather
than in a changelog line.

**(a) Query polarity.** The census sampled the query field in RAW luma. Production's shape
term uses `1 − Rec.601 luma` (`LogPolarKernel.baseInvertedLuma`, `LogPolarKernel.swift:565`).
Candidate rasters are ink-high (`RasterizedCharacterSet.rasterize` fills the canvas at
`gray: 0` and draws the glyph at `gray: 1`). So the instrument was pairing a differently
oriented query with production's candidates than production itself does.

**(b) Square-rung font scale.** Rung (i) claims to *be* the shipped candidate convention. It
rasterized text at 64pt Courier into a 64×64 canvas, via `GlyphRaster.luma`'s
canvas-derived default. `BuildStandardVectors.swift:55` builds the committed `.bin` vectors
at **32pt** into the same 64×64 canvas. Bounds-centring re-centres ink but does not rescale
it, so rung (i) was carrying a 2× scale change on top of the convention it was meant to
isolate.

**(c) Placement rungs on different rasterization paths and point sizes.** Found in a third
review pass, on the PR. Rung (ii) `boundsCentredRect` went through `GlyphRaster` at a
canvas-derived point size (24pt at a 12x24 cell, native, no supersampling); rung (iii)
`positionFaithful` went through `GlyphCellRaster`, whose point size is `height / 1.2`
(effectively 20pt) rendered 4x and box-downsampled. The rung pair that exists to isolate
*placement* was therefore also changing scale by 20% and changing the antialiasing path.
Both placements now share one path and one scale: `GlyphCellRaster` — the renderer's own
convention, which is the production-truthful choice for the two cell-aspect rungs — with a
`boundsCentred` flag that applies the matcher's `CTLineGetImageBounds` centring inside that
same path, in the supersampled domain. Braille ignores the flag, since `BrailleRasterizer`
covers the whole cell rect and has no bounds-cropped form, which is what keeps the null
control in §3.3 exact. Rung (i) is untouched and still models the shipped `.bin` convention
(32pt into 64x64, native), which is why it still reproduces production. **This dissolved
most of a result the note had called counterintuitive and unexplained; see §4.2 reading 4.**

**(d) Geometry reported one native block size per fixture instead of the range.** Also from
the third pass. Native-to-thumbnail scaling is fractional, so the block varies cell to cell,
and the census emitted the last cell visited. `geometry.csv` and the printed table now carry
min-max: `nasa-steerable-v1` is 38-39 x 76-77, not the singular 39x76 previously reported.

**What the fixes bought.** Rung (i) now reproduces production: on `nasa-steerable-v1`
`blocks` it scores MAE 0.66651 against production's 0.66651 at **100.0% pick agreement**
(95.3% on occupancy). Before the fixes that agreement was 12.4%, and the resulting spread
was misread as evidence for a sampling-support effect. A third finding (P2) was also
confirmed and fixed: the pool was scanned in glyph-index order, but
`ShapeMatching.findBestScored` (`ShapeMatching.swift:286-305`) sorts by brightness delta
with ties to the lower index and keeps the FIRST minimum, so a descriptor tie resolves to
the tone-nearest candidate. Ties are common here because the shipping descriptor is
collapsed.

### 3.2 Query polarity is a measured factor, not an assumed constant

Fixing (a) surfaced a contradiction that could not be resolved by picking a value, so the
census runs at **both** polarities and reports the pair:

- `inverted` — `1 − luma`, reproducing production's shape term.
- `direct` — raw luma, matching the ink-high candidates, the renderer, and the scoring path.

The contradiction is inside production. Its tone pre-filter matches a **bright** source cell
to a **dense** glyph — the pairing the renderer draws (light ink on a dark ground) and the
one every archived pick-quality screen scores under. Its shape term inverts the query and
therefore treats **dark** source regions as ink. The two disagree about which end of the
source is ink. Assuming either value would have been the improvisation this unit is not
allowed to make.

### 3.3 The braille null control

For braille, rungs (ii) and (iii) both draw dots over the whole cell rect via
`BrailleRasterizer`, so they are the *same vocabulary* and every braille number must agree
between them exactly. It does, in all four (polarity × corpus) cells: 0.25355 / 0.35135
under `inverted`, 0.25284 / 0.34897 under `direct`. Pinned by a unit test.

Braille is **not** a null control for the compound delta in §4.1: `BuildStandardVectors`
rasterizes braille at a **64×64 square** like every text glyph, so what braille escapes is
the `CTLine` bounds crop, not the square.

## 4. Results

### 4.1 The compound delta — production against a corrected matcher

| polarity | corpus | charset | production | faithful | improve | picks differing |
| --- | --- | --- | --- | --- | --- | --- |
| inverted | steerable | blocks | 0.6665 | 0.6663 | +0.04% | 0.2% |
| inverted | occupancy | blocks | 0.6571 | 0.6648 | −1.17% | 7.5% |
| inverted | steerable | standard | 0.2286 | 0.2312 | −1.14% | 41.6% |
| inverted | occupancy | standard | 0.3669 | 0.3732 | −1.70% | 55.9% |
| direct | steerable | blocks | 0.6665 | 0.3517 | +47.24% | 42.7% |
| direct | occupancy | blocks | 0.6571 | 0.3967 | +39.63% | 40.7% |
| direct | steerable | standard | 0.2286 | 0.2310 | −1.07% | 42.0% |
| direct | occupancy | standard | 0.3669 | 0.3713 | −1.18% | 54.8% |

**The +47% blocks headline survives only under the polarity swap.** Held at production's own
polarity, the position-faithful vocabulary makes essentially the same picks as production on
`blocks` — 0.2% of cells differ on steerable — and buys +0.04%. The first version of this
note reported the +47% as a candidate-convention effect. It is not one.

### 4.2 The ladder — the single-variable reading

MAE, matched support on both sides, percentages against rung (i):

| polarity | corpus | charset | (i) square | (ii) rect | (iii) faithful | (iv) tiled | (v) noBlur |
| --- | --- | --- | --- | --- | --- | --- | --- |
| inverted | steerable | blocks | 0.66651 | +0.78% | +0.04% | +0.00% | +0.00% |
| inverted | occupancy | blocks | 0.65656 | −0.30% | −1.26% | −0.66% | −0.26% |
| inverted | steerable | standard | 0.23066 | −0.63% | −0.24% | +1.52% | +1.93% |
| inverted | occupancy | standard | 0.36799 | −0.99% | −1.40% | +0.20% | +0.68% |
| inverted | steerable | braille | 0.23911 | −6.04% | −6.04% | −0.18% | −0.03% |
| inverted | occupancy | braille | 0.35336 | +0.57% | +0.57% | −0.31% | +0.07% |
| direct | steerable | blocks | 0.36031 | +3.88% | +2.40% | +1.20% | −1.35% |
| direct | occupancy | blocks | 0.40970 | +3.92% | +3.17% | +2.62% | −0.47% |
| direct | steerable | standard | 0.23083 | −0.74% | −0.09% | +1.64% | +2.08% |
| direct | occupancy | standard | 0.36817 | −0.80% | −0.84% | +0.19% | +0.85% |
| direct | steerable | braille | 0.23704 | −6.67% | −6.67% | +0.38% | +0.28% |
| direct | occupancy | braille | 0.34379 | −1.51% | −1.51% | +0.36% | +0.23% |

**1. The query-path attribution is withdrawn.** The first version of this note claimed the
gap between production (0.667) and rung (i) (0.314) was the query support, and pointed at
ASKI-55 as the larger win. With the instrument corrected there is no such gap: rung (i) is
0.66651 against production's 0.66651 at 100.0% agreement. The 0.314 was this instrument's
own polarity and scale defects. **That reading was wrong and is retracted.**

**2. The dominant effect is the polarity, and it is neither ASKI-52 nor ASKI-26.** Holding
the arm, the vocabulary and the scoring fixed and flipping only the query field, `blocks`
rung (i) goes from 0.66651 to 0.36031 on steerable (0.306 MAE recovered) and 0.65656 to
0.40970 on occupancy (0.247). Production `blocks` SSIM is 0.0040 / 0.0050; the faithful
vocabulary reproduces that under `inverted` (0.0040 / −0.0009) and reaches 0.307 / 0.105
under `direct`. The near-zero structural agreement of the shipped `blocks` pick is a
polarity artifact.

*Caveat.* The scoring path (ink-high raster vs raw source luma) shares its convention with
`direct`, so `direct` is partly flattered by the oracle it is judged under. What defends it
beyond the oracle is that it is also the convention of the renderer and of production's own
tone pre-filter, while `inverted` matches none of the three. A strong signal, not a closed
proof; a production change needs its own gate.

**3. The convention delta proper is small, and mostly unfavourable.** Rung (i) → (iii) is
+0.04% / −1.26% on blocks under production's polarity, and negative on `standard` in every
cell of the design. Under `direct` it helps blocks (+2.40 / +3.17) and still hurts
`standard` and `braille`. The first run's −11.90% / −2.31% blocks figures were defect
artifacts and should not be cited.

**4. The bounds-centred rung's apparent effect largely dissolved under review.** An earlier
revision of this note reported rung (ii) — cell aspect restored, bounds-centring kept — as
the standout `blocks` arm at +12.64% / +13.44% direct and +26.12% / +15.26% inverted, and
called the result counterintuitive and unexplained. A third review pass found why: rung (ii)
was rasterized through `GlyphRaster` at a canvas-derived 24pt with no supersampling, while
rung (iii) went through `GlyphCellRaster` at an effective 20pt with 4x supersampling, so the
delta those two rungs exist to isolate was confounded with a 20% scale change and a
different antialiasing path (§3.1c). With both placements on one path at one scale, rung
(ii) falls to **+0.78% / −0.30% (inverted) and +3.88% / +3.92% (direct)** — it is no longer
a standout, and under production's own polarity it is inert.

What survives is much smaller and worth stating without drama: on `blocks`, bounds-centring
still edges out position-faithful by roughly **0.75% to 1.5%** in all four cells (rung (ii)
0.66132 vs rung (iii) 0.66626 inverted-steerable; 0.65856 vs 0.66481 inverted-occupancy;
0.34632 vs 0.35167 direct-steerable; 0.39364 vs 0.39669 direct-occupancy). That is a
consistent sign but a small magnitude, it is confined to the 8-glyph `blocks` set, and on
`standard` the ordering reverses. At that size it does not carry the weight the earlier
reading put on it, and no explanation is offered or needed.

**5. The paper's tiled construction is a small, consistent win on text only.** Rung (v) is
+1.93% / +0.68% (inverted) and +2.08% / +0.85% (direct) on `standard`, under the standing
+3.0% bar in every case. The pre-blur the paper prescribes hurts on `standard` in three of
four cells.

### 4.3 Degeneracy check — the known trap did not fire

At the 12×24 candidate geometry every tiled rung carried the paper's full construction —
**72 windows, 4320-D** — on both corpora and both polarities, so the tiled rows are real
measurements.

The collapse is on the other side of the instrument, and it is unchanged by the corrections
because geometry does not depend on polarity: the shipped kernel samples a **2×4 thumbnail
cell on all 27 fixtures**, holding 2 windows and ~3 of 60 live bins. That reproduces
`2026-08-19-sampling-lattice-support-collapse.md` on 27 fixtures instead of 3. The ASKI-55
regime is real; what has changed is that it is no longer credited with the `blocks` failure.


## 5. The loader defect

`RealFixture.load` globbed `*.png`. `nasa-occupancy-v1` (24 assets) and
`nasa-isoluminant-v1` (8 assets) are committed as **JPEG**, so both were unreachable from
every Tools-side battery that routes through this loader. The failure mode was loud, not
silent — the loader throws `corpusAssetUnreadable` when a directory yields no PNGs — but
the consequence was that no Tools-side census could measure those corpora at all, and
`2026-08-19-sampling-lattice-support-collapse.md` had to **retract two fixtures** from a
published table for exactly this reason (its §3 and §5 corrections).

The loader now accepts `png`, `jpg` and `jpeg`. Two caveats travel with that:

- **The occupancy assets are lossy.** JPEG compression artifacts are now part of the
  measurement of that corpus. Any figure quoted from `nasa-occupancy-v1` must name the
  corpus; it is not interchangeable with the lossless PNG corpora.
- **The change is Tools-side only.** `Sources/Aski` is untouched by it.

**What the unlocked corpus showed.** `nasa-occupancy-v1` carries a content stratum the PNG
corpora do not: engineering line-art. Its four diagram fixtures carry **0.33 to 0.69 live
bins of 60** — an order of magnitude below the ~3/60 of photographic content, i.e. near-total
descriptor collapse on line art. `james-lovell-portrait` sits at 2.22. No Tools-side census
had previously been able to see this stratum.

## 6. What promotion would cost (ASKI-52 AC#2)

Recorded here because it is a decision, not a mechanical regen. Adopting a position-faithful
candidate vocabulary in `Sources/Aski` would require a `BuildStandardVectors` regeneration,
and therefore:

- **All 10 committed `.bin` files churn** (`blocks`, `braille`, `cross`, `diagonal`,
  `diamond`, `dots`, `lines`, `minimal`, `mixed`, `standard`).
- **The ten frozen digests in `StandardCharacterSetScalarValidationTests.swift:224` need a
  deliberate re-record decision.** Their own comment says "do NOT re-record them" — they are
  byte-identity anchors, and a moved digest is defined there as a decode change that ASKI-23
  AC#4 forbids. Promotion therefore cannot quietly refresh them; it has to argue that a
  vocabulary change is a different event from the drift the anchors were written to catch,
  and get that ruled on.
- **~80 snapshot goldens churn**, since every glyph pick can move.
- **Archived-verdict comparability breaks.** Every prior descriptor kill was measured
  against the current vocabulary. A vocabulary change means those verdicts characterize a
  matcher that no longer exists, and the ASKI-55 regime split already makes that record
  fragile.
- **`CanonicalOrientationTemplates` (`AlgorithmKernel.swift:87`) inherit the square
  convention** and would have to move with it.

None of this is a blocker. It is the reason this unit deliberately stops at measurement.

## 7. Verdict, stated cautiously

**This unit measures. It does not promote.** The instrument is validated where it matters —
rung (i) reproduces production at 100.0% pick agreement (§3.1), the braille null control
holds in all four cells of the design (§3.3), and the known degeneracy trap did not fire
(§4.3).

**A retraction first.** The first version of this note claimed the ladder pointed most of the
production-vs-corrected gap at the *query support*, and that the largest available win here
was therefore ASKI-55's rather than ASKI-52's. That claim was an artifact of two defects in
this note's own instrument (§3.1), and it is **withdrawn**. Corrected, there is no such gap:
rung (i) is production, to five decimal places.

**On ASKI-52 and ASKI-26, the answer is unfavourable and now well-measured.** Held at
production's own polarity, the position-faithful vocabulary is inert-to-harmful: +0.04% /
−1.26% on `blocks`, negative on `standard` in every cell. The paper's tiled construction is
a small consistent win on text only (+1.93% / +0.68% inverted, +2.08% / +0.85% direct),
under the +3.0% bar everywhere, on a reconstruction oracle that the ASKI-56 rule requires be
backed by the perceptual arbiter before any promotion. **No promotion is warranted on this
evidence.**

**The largest effect this unit found belongs to neither task.** Production's shape term
inverts the query field while its tone pre-filter, its renderer and its candidate rasters all
agree that ink is bright. Flipping only that, `blocks` MAE recovers 0.306 / 0.247 and SSIM
goes from ~0.004 to 0.307 / 0.105. That is an order of magnitude more than anything the
candidate convention is worth. Subject to the §4.2 caveat that the scoring oracle shares
`direct`'s convention, this is the finding worth acting on. It is **filed as ASKI-60**, scoped
measure-first with its own gate, and is deliberately not actioned here.

It *may* also bear on a result the ASKI-30/28 battery already recorded — a shape-free tone
floor beating the real matcher on the shipped preset — since a shape term matched against an
inverted query would fight the tone term rather than help it. **Untested hypothesis, flagged
as such deliberately:** this is the same species of cross-task mechanism claim as two others
in this unit that failed verification (the query-path attribution in §4.2 and an asserted
ASKI-16 link, both retracted), and nothing has been run to test it. Verification belongs to
ASKI-60's acceptance criterion on re-checking archived verdicts, not to this note.

One practical note that ASKI-60 carries: a polarity flip is **query-side only**. The
inversion is confined to `LogPolarKernel` (no other file in `Sources/Aski` references
`baseInvertedLuma`), and `BuildStandardVectors` has no polarity dependence, so candidate
vectors are query-independent — **no `.bin` regeneration, and none of the frozen digests
move**, since those anchor `.bin` decode rather than picks. Snapshot goldens *would* churn,
because picks change. That is a far cheaper blast radius than the vocabulary promotion
costed in §6.

**Also settled:** the parity claim and venue in `ASCIICharacterSet.swift` were wrong and are
corrected; bounds-centring at true cell aspect still edges out position-faithful on `blocks`
in all four cells, but by roughly 0.75-1.5% rather than the 12-26% an earlier revision
reported — most of that gap was a scale-and-rasterization confound between the two rungs
(§3.1c), and at the surviving magnitude the result carries no weight and needs no
explanation; and the JPEG-only occupancy corpus is measurable for the first time.
