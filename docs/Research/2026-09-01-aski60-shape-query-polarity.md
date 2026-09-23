---
title: "ASKI-60 - The Shape Query's Ink Convention, Measured Against the Rest of the Pipeline"
slug: 2026-09-01-aski60-shape-query-polarity
date: 2026-09-01
status: complete
subsystem: [shape-context]
summary: "Measurement, not a promotion. Production's logPolar shape query has histogrammed 1 minus Rec.601 luma since the first commit, so it treats DARK source regions as ink, while the candidate rasters, the tone pre-filter and the renderer all treat BRIGHT as ink. The asymmetry was deliberate at origin and unintended as an asymmetry: the rationale recorded in 2026-05-04 was to match the ink-high candidate convention, which is correct only for dark-on-light input, and nothing ever reconciled it with the light-on-dark tone and render path that shipped from the same commit. A new RenderingOptions.shapeQueryPolarity knob, SPI-only and defaulting to the shipped inverted behavior, makes both arms reachable from one binary; a new AskiColorLab polarity-gate drives the REAL converter over 27 NASA fixtures at the shipping regime with a decision rule pre-registered before the run. The verdict is KILL, and not on the charset the unit was about. On blocks the direct query is a very large win - MAE 0.66651 to 0.35330 on steerable, plus 46.99 percent, and 0.65714 to 0.39564 on occupancy, plus 39.79 percent, with GMSD agreeing in sign in both cells - but occupancy braille regresses 3.26 percent MAE and 17.50 percent GMSD, both oracles agreeing, past the pre-registered 3.0 percent collateral veto. The mechanism behind the charset dependence is measured rather than assumed: the tone pre-filter admits topK 12 candidates and blocks carries 8 glyphs, so blocks is the only charset whose prune excludes nothing and whose shape term therefore ranks the whole set. That explains standard cleanly, where polarity moves 0.1 to 0.3 percent of picks and MAE is inert to four decimals, and braille only in part. GMSD is carried as the convention-independent guard because its Prewitt filters are zero-mean and a global negation of both planes leaves it unmoved; a mandatory negative control re-scored all 453120 pairs negated and held at 2.9e-07. No default changed and no binary or frozen digest moved."
related_specs: [docs/Research/2026-08-28-aski52-26-candidate-convention.md, docs/Research/2026-08-24-aski-30-28-battery-verdict.md, docs/Research/2026-08-25-aski56-arbiter-protocol.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-occupancy-v1]
runners: [AskiColorLab]
next_action: "No promotion, and no default change: shapeQueryPolarity ships .inverted and the default conversion path is byte-identical. The pre-registered rule killed a treatment whose headline number is very large, on collateral damage to braille, and that is the honest reading of it. The obvious lift is a PER-CHARSET polarity - direct on blocks, inverted elsewhere - which this unit did NOT test and which is filed as its own measure-first task; the mechanism section says why that shape is plausible and why it is not evidence. Any default flip, per-charset or not, needs an ASKI-56 arbiter sitting, and the arbiter cannot express a polarity arm today: its arms are selection-rule variants over ONE production convert, so a converter-level knob needs a protocol v2 and re-validation. That was an owner decision, recorded as BLOCKED and not attempted; the owner authorized the v2 on 2026-09-01 and it is filed as ASKI-62."
---

# ASKI-60 — the shape query's ink convention, measured

## 1. The inconsistency, and whether it was deliberate (AC#3)

Production's `logPolar` matcher compares a query and a candidate that disagree about
which end of the source is ink.

- Candidate rasters are **ink-high**. `RasterizedCharacterSet` fills the canvas at
  gray 0 and draws the glyph at gray 1, so a dense glyph carries descriptor mass
  everywhere.
- The shape query is **inverted**. `LogPolarKernel` built its per-cell field as
  `1 − Rec.601 luma`, so DARK source regions carried the descriptor mass.
- The tone pre-filter goes the other way: a high source `adjustedL` asks for a high
  candidate ink density, i.e. a BRIGHT cell asks for a dense glyph. So does the
  renderer, which draws light ink on a dark ground.

Three against one. The archaeology says this was **deliberate at origin and
unintended as an asymmetry**. The `1 − luminance` line entered on 2026-05-04 in
archive commit `4f613488` with the written rationale *"Invert so ink = high value
(matches RasterizedCharacterSet convention)"*. That reasoning is sound for
paper-style dark-on-light input, where the dark parts of the source really are the
ink. But the tone pre-filter and the renderer were light-on-dark from the same
initial commit and were never flipped, and no document anywhere in the repo decides
the resulting shape-versus-tone disagreement. It is a local decision that was never
reconciled with its neighbours, not a considered fork.

## 2. What the literature does with polarity

Nothing, is the short answer — and that itself is informative.

Xu, Zhang and Wong's structure-based ASCII art (ACM TOG 29(4) Art. 52, 2010,
<https://www.cg.tuwien.ac.at/courses/CA/material/papers/AsciiArt.pdf>) accumulates
ink with a single convention applied to **both** sides of the comparison: "During
the pixel summation, black pixel has a grayness of 1 while the white one is 0",
used identically for the rasterized reference line art and the rasterized
character. Polarity is never a parameter in that paper, because source and glyph
are never allowed to disagree about it. So the literature does not offer a
"convention fork" to pick a side of; it offers the constraint that the two sides
share an axis.

Current practice agrees and picks the other axis. Alex Harri's rendering write-up
(<https://alexharri.com/blog/ascii-rendering>) pairs source *lightness* with glyph
*ink coverage* — lighter cells choose denser glyphs — for light-on-dark output, and
the Python port at <https://github.com/mayz/ascii-renderer> rasterizes glyphs
ink-high and exposes `--invert` as a **source-only** flip, never a glyph-table one.
Render-and-compare evaluation is also established: Coumar and Kingston
(<https://arxiv.org/html/2503.14375v1>) score rendered ASCII against the source
rather than scoring descriptors.

The useful conclusion is narrow: the fix a reader of the literature would propose is
"make the query and the candidate table share one ink axis", not "choose a house
polarity". Which axis they share is then a free choice, and the display polarity is
a separate render-time decision.

## 3. Instrument, and the rule frozen before the run

The knob. `RenderingOptions.shapeQueryPolarity` is `@_spi(AskiResearch)`, absent
from the public `init`, and defaults to `.inverted`. `LogPolarKernel.baseInkField`
(formerly `baseInvertedLuma`) applies the inversion only under `.inverted`. Every
shape sub-term — the 60D descriptor, the structure query, the steerable channel and
the chroma-assist blend — reads that one field, so they flip together and the knob
can never half-apply. The default path is byte-identical: a test asserts that an
unset default equals an explicit `.inverted` cell for cell and bit for bit.

The instrument. `AskiColorLab polarity-gate` drives the **real**
`ASCIIConverter.convert` once per polarity and scores the converter's own picks. No
lab sampler stands in for the matcher on either side — the defect that invalidated
the first run of the companion ASKI-52/26 census. The scoring path is shared
byte-for-byte with `convention-ablation` through one extracted function, so the two
instruments cannot drift onto different rasters. Cross-check: on
`earth-limb-sunrise` the inverted arm reproduces `convention-ablation`'s production
arm at MAE 0.83833 over the same 2880 cells.

Oracles. MAE decides direction (the house oracle, ASKI-27). GMSD is the
**convention-independent guard**: its Prewitt filters are linear and zero-mean, so
negating an image negates both directional gradients and leaves the magnitude map
unchanged, and GMSD therefore cannot be flattered by the ink convention under test
(definition: Xue et al., <https://arxiv.org/pdf/1308.3052>; the invariance is a
derivation from it, not a claim the paper makes). SSIM and HaarPSI are reported and
never decide — SSIM keeps a luminance term and is polarity-coupled by construction.

The **negative control is mandatory** and ran on every scored pair, not a sample:
both planes negated and re-scored. Max |ΔGMSD| 2.9e-07 and max |ΔMAE| 1.6e-08 over
453,120 pairs against a 1e-06 tolerance. The residual is float rounding in `1 − x`;
a unit test pins the invariance on dyadic-fraction planes where it is exact.

The rule, pre-registered in the design addendum before any number was measured and
encoded in `PolarityGate.verdict` with one unit test per branch:

- **KILL** iff `direct` is worse than `inverted` on blocks MAE on either corpus, OR
  any non-blocks charset regresses by more than 3.0% MAE on either corpus.
- **CANDIDATE** iff blocks MAE lift exceeds 3.0% on BOTH corpora, GMSD agrees with
  MAE in sign on both, and no non-blocks charset regresses.
- **INCONCLUSIVE** iff `direct` wins blocks on both corpora but inside the bar on
  one, or GMSD disagrees with MAE in sign. It routes to the arbiter exactly as
  CANDIDATE does, because the 3.0% bar sits inside the ASKI-56 JND75 band.
- **INVALID** iff the negative control moves or an arm is missing. A re-instrument,
  never a result about the treatment.

Regime: release build, columns 80, oversample 2, footprint 24, sampling cell 12×24,
converter defaults, exhaustive census over every cell of all 27 fixtures in
`nasa-steerable-v1` and `nasa-occupancy-v1`.

## 4. Results, and the verdict

All numbers from `docs/Research/Results/2026-09-01-aski60-polarity-gate/`
(`summary.md`, `oracle-means.csv`, `polarity-gate.json`). `improve%` is signed so
positive always means `direct` picked better.

| corpus | charset | cells | MAE inverted | MAE direct | MAE improve% | GMSD improve% | picks moved |
|---|---|---|---|---|---|---|---|
| steerable | **blocks** | 8640 | 0.66651 | 0.35330 | **+46.99** | +36.38 | 38.6% |
| occupancy | **blocks** | 66880 | 0.65714 | 0.39564 | **+39.79** | +1.42 | 35.5% |
| steerable | standard | 8640 | 0.22860 | 0.22862 | −0.01 | +0.01 | 0.1% |
| occupancy | standard | 66880 | 0.36692 | 0.36693 | −0.00 | −0.01 | 0.3% |
| steerable | braille | 8640 | 0.23846 | 0.23794 | +0.22 | −0.05 | 4.1% |
| occupancy | braille | 66880 | 0.35285 | 0.36437 | **−3.26** | **−17.50** | 19.5% |

**Verdict: KILL.** Deciding clause: *no other charset regresses > 3.0% MAE* —
occupancy braille at −3.26%.

Stated plainly: the blocks lift is very large, larger than anything else this repo
has measured on glyph selection, and it does not survive. Every other clause passed,
including the blocks lift and GMSD sign agreement on blocks. What kills it is
collateral damage to a charset the treatment was not aimed at, and the veto is
cleared by only 0.26 percentage points — a close call, which is exactly why the rule
was written down first. Two things argue against reopening it: MAE and GMSD agree on
the direction of the braille loss, and GMSD's −17.50% is not a marginal number.

## 5. Mechanism: why this is a blocks-set effect

Measured, not assumed. `LogPolarKernel` prunes to `topK = 12 + round(density·24)`
brightness-nearest candidates — 12 at the default density — and `ShapeMatching`
takes `prefix(min(topK, count))`.

| charset | glyphs | topK | pool | prune binds |
|---|---|---|---|---|
| blocks | 8 | 12 | **8** | **no** |
| standard | 95 | 12 | 12 | yes |
| braille | 256 | 12 | 12 | yes |

`blocks` is the only charset whose glyph count sits under `topK`, so it is the only
one where the tone pre-filter admits every glyph and excludes nothing; the shape
distance then ranks the whole set, with `ShapeMatching`'s brightness-delta and
index tie-breaks still applied on equal distances. Everywhere else the tone term has already narrowed the
field to 12 tone-plausible candidates before shape is consulted, which is why an
inconsistent shape convention costs so little there.

The measurement confirms the *binding* half cleanly and complicates the other half.
`standard` behaves exactly as predicted — 0.1% and 0.3% of picks move and MAE is
inert to four decimal places. `braille`'s prune binds too, yet 19.5% of its occupancy
picks move and both oracles say it gets worse, so the prune explains `braille` only
in part.

The ASKI-30/28 re-run in section 8 widens this to ten charsets and settles the
question the other way: **on the ten built-in charsets, every charset that moved
had a non-binding pool, and a non-binding pool was not enough on its own.** Ten
charsets are an observation, not a proof of necessity.
Production-arm MAE under `inverted` → `direct`, with each charset's glyph count:

| binds | charset | glyphs | production MAE move |
|---|---|---|---|
| no | blocks | 8 | **+42.32%** |
| no | lines | 12 | **+15.85%** |
| no | mixed | 12 | **+12.82%** |
| no | minimal / dots / cross / diamond / diagonal | 10 / 8 / 5 / 4 / 4 | +0.00% each |
| yes | standard | 95 | +0.00% |
| yes | braille | 256 | +0.03% |

Every charset that moves is one whose prune does not bind, so the mechanism is not
wrong. But five of the eight non-binding charsets do not move at all, and all five
sit at exactly the same MAE (0.24754) under both polarities — a degeneracy of their
own that this note does not diagnose. The honest statement is therefore narrower
than "the pool no-op explains the effect": on these ten charsets, a pool no-op is
what let the shape term matter, and among the charsets where it held, only those
with enough distinct shape to exploit it actually moved.

## 6. Real-renderer arm

An existence proof, not a second verdict: one fixture per corpus per polarity
rendered through the shipped `ImageRenderer` (blocks, 76 columns, white ink on
black), resampled to the source geometry and scored on luma. The frozen preset is
deliberately not used — scoring is on luma, so its duotone palette cannot affect the
answer, and a plain converter keeps the arm a statement about the renderer rather
than about one palette. PNGs in `recheck`-adjacent `render-arm/`.

| corpus | polarity | MAE | GMSD |
|---|---|---|---|
| steerable | inverted / direct | 0.78143 / **0.03710** | 0.40123 / **0.17503** |
| occupancy | inverted / direct | 0.48325 / **0.46659** | **0.29853** / 0.30486 |

**Three of four sign comparisons agree** with the cell-wise census. MAE agrees in
both corpora; GMSD agrees on steerable and disagrees on occupancy, which is the one
cell where the census margin was itself only +1.42%. Caveat worth recording: the
render is 548×539 and the sources are 3072² and 1280², so the resample to source
geometry is an **upsample of the render, not a downscale**. That adds no information
and smooths the render's gradients, which is tolerable for a sign check and would
not be for a magnitude claim.

## 7. Churn sizing (AC#4)

Worktree-only: the default was temporarily forced to `.direct`, the suite run, the
edit reverted, and the tree confirmed clean. 1658 tests in 259 suites produced
**11 distinct failures**:

- **2 knob-default guards** — `ShapeQueryPolarityTests.defaultIsInverted` and
  `unsetDefaultMatchesExplicitInvertedCellForCell`. Failing is their job.
- **7 log-polar goldens** — `DefaultPathExactGoldenTests:30`, `SnapshotTests:14`,
  `:47`, `:112`, `CharacterizationTests:80`, `AlgorithmScalarBoundaryTests:66`,
  `VesperPresetTests:96`.
- **2 lab analyses, not goldens** — `AskiColorLabIsoluminantRescueTests:129/131` and
  `:144/148` re-derive the isoluminant dose-response from live converter picks, so a
  default flip would have to re-settle that verdict, not re-record a file.

Nothing in `.edgeMap`, `.dotMatrix`, tiles, masks, palettes, effects, video or DocC
moved, confirming the change is confined to `LogPolarKernel`.

Binaries and digests are **unmoved**. All ten `Sources/Aski/Resources/ShapeData/*.bin`
are SHA-256-identical to `main` before and after, and
`StandardCharacterSetScalarValidationTests` passes 6/6 with the default forced to
`.direct` — confirming those digests anchor `.bin` decode, not picks.

## 8. Archived verdicts (AC#5)

All nine archived verdicts were checked. Scope was set by the mechanism in
section 5: a verdict whose arms ran only on `standard` cannot move much, because
`standard`'s tone prune binds and polarity moved 0.1-0.3 percent of its picks in the
census above.

| Verdict | Charset(s) its arms ran on | Evidence | Action |
|---|---|---|---|
| ASKI-30 | 10 charsets incl. blocks, braille | `Results/2026-08-24-aski-30-28-battery/result.yaml:6` | RE-RUN |
| ASKI-28 | same battery, same 10 charsets | same | RE-RUN |
| ASTSK-42 | `standard` only | `SteerableChannelCommand.swift:155-158` (`StandardCharacterSet.standard.characters`) | statement |
| ASTSK-43 | `standard` only | `InterCellSmoothingCommand.swift:61` | statement |
| ASTSK-7 | `standard` only | `OccupancyMatchCommand.swift:220,268` | statement |
| ASTSK-45 | `standard` only | `SourceTetherExperiment.swift:18` | statement |
| ASTSK-27 | not reproducible from record | `2026-06-09-shape-residual.md:21-99`; no committed results, no complete command | statement |
| ASTSK-31 | not reproducible from record | same note `:101-188` | statement |
| ASTSK-35 | not reproducible from record | same note `:209-222` | statement |

### 8.1 The re-run (ASKI-30 / ASKI-28)

The battery was re-run from its own recorded command at both polarities. Outputs in
`Results/2026-09-01-aski60-polarity-gate/recheck-aski30-28/`.

**Instrument validation.** The `inverted` arm reproduces the archived
`heldout-nasa-steerable-v1.csv` **exactly** on all 226 rows and every data column;
only the wall-time and git-SHA columns differ, and the re-run CSVs carry one extra
trailing `shapeQueryPolarity` column that the archive predates (added after cross-model
review so a `direct` census is distinguishable from the default one on disk). The
polarity seam is inert at its default, and the archived battery is reproducible from
record.

**ASKI-30 — the parent note's UNTESTED HYPOTHESIS, tested.** The hypothesis was that
an inverted shape term actively fights the tone term, and that this is why a
shape-free tone floor beat the real matcher on the frozen preset. On blocks:

| arm | MAE inverted | MAE direct |
|---|---|---|
| P (production matcher) | 0.56329 | **0.32488** |
| F (shape-free tone floor) | 0.26391 | 0.26391 |
| T (tone-weighted, w=2) | 0.23580 | 0.23421 |

F is byte-identical across the polarities, which is the control working: the floor
consumes no shape query, so it must not move, and it does not.

The hypothesis is **CONFIRMED as a mechanism and REJECTED as an explanation**.
Production recovers enormously — F/P goes from 0.4685 to 0.8123, so the inverted
query was costing the matcher most of the gap. But **the shape-free floor still beats
the real matcher** under `.direct` (0.26391 against 0.32488). The archived finding
does not change sign: fixing the polarity narrows the embarrassment, it does not
remove it.

ASKI-30's actual decision clause was the T/F MAE ratio against the 0.97 bar: 0.8935
inverted, 0.8874 direct. Passes under both; **no sign change**. What does flip is the
SSIM reversal that made ASKI-30 INCONCLUSIVE in the first place: SSIM(T) − SSIM(F)
is −0.0002628 under `inverted` and **+0.0001253** under `direct`, so under the
matched convention SSIM stops contradicting MAE. Recorded, not promoted to a
finding: it is a 1e-4 quantity on an oracle whose luminance term is polarity-coupled
by construction, which is precisely the reason SSIM does not decide anything in this
note. It does not convert ASKI-30's INCONCLUSIVE by itself.

**ASKI-28 — no sign change, verdict reinforced.** The KILL clause was the pool-width
arm missing the 0.97 bar at the frozen operating points:

| charset | topK* | K/P inverted | K/P direct | bar |
|---|---|---|---|---|
| standard | 64 | 0.9775 | 0.9840 | ≤ 0.97 |
| braille | 18 | 0.9999 | 1.0000 | ≤ 0.97 |

Both miss under both polarities, and both are marginally worse under `direct`. The
KILL stands.

### 8.2 Comparability statements (no re-run)

- **ASTSK-42, ASTSK-43, ASTSK-7, ASTSK-45** were each measured on `standard` alone.
  All were measured under the inverted query. `standard`'s tone prune binds at
  topK = 12 out of 95 glyphs, and in both the census above and the battery re-run the
  production arm on `standard` moves by less than 0.005 percent MAE with 0.1-0.3
  percent of picks changing. A sign change is implausible on that evidence. None was
  re-run.
- **ASTSK-27, ASTSK-31, ASTSK-35** are **not reproducible from record**: no committed
  results directory and no complete executable command survives for any of them (the
  fixture families and flags are recorded, the invocations are not). They were
  measured under the inverted query; the sign is **unknown** and cannot be
  established without first reconstructing their instruments. Recorded as such rather
  than guessed.

## 9. What a promotion would need

**A per-charset polarity is the obvious lift, and this unit did not test it.**
Section 5 says why the shape is plausible: the effect lives where the tone prune is
a no-op, and the two charsets that lose are the two where it binds. `direct` on
blocks with `inverted` retained elsewhere would, on these numbers, keep the entire
blocks lift and vacate the clause that killed the flat treatment. That is a
hypothesis with a mechanism, not a result — it has been measured on neither corpus
and is filed as its own measure-first task rather than asserted here.

**Any default flip needs the arbiter, and the arbiter cannot express this arm
today.** The standing ASKI-56 rule is that default promotion requires an
`arbiter score` sitting. The frozen v1 protocol cannot represent a polarity arm:
`ArbiterCensus` converts each fixture **once** with the production converter and
derives every arm's picks by re-running `SelectionCeiling.Arm` *selectors* over that
single query, then substitutes characters into the production grid. A polarity arm
needs a second `convert` with different `RenderingOptions`, and there is no seam for
one in `Census`, `ArmRef`, `ArmKey` or `PairPlan`. Adding an arm also changes the
pool that families C and M draw pairs from, so it changes the sampled distribution
the frozen ~45-trial budget is defined over. The protocol's own status line requires
a v2 and re-validation for any change after the first collected vote, and 45 votes
were collected on 2026-08-26. A v2 would need: a converter-level arm type parallel to
`SelectionCeiling.Arm`; `Census` extended to run one convert per arm; `ArmRef`,
`ArmKey` and `key.json` metric deltas widened to carry it; a re-registered family
budget; and §5.1 re-validation. **That is an owner decision. It is recorded as
BLOCKED and was not attempted.** Update, 2026-09-01: the owner authorized the v2
after review. The surgery above is filed as ASKI-62; ASKI-61's arbiter clause is
blocked on that task rather than on a decision.

## 10. Verdict

KILL under the pre-registered rule, on the collateral clause rather than on the
deciding charset. **No default change**: `shapeQueryPolarity` ships `.inverted`, the
default conversion path is byte-identical, no `.bin` file or frozen digest moved,
and no archived verdict changes sign. The knob and the `polarity-gate` instrument
stay in the tree so the follow-up per-charset question can be measured against the
same gate rather than a new one.
