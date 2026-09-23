---
title: "Selection Optimality Gap - on the shipped preset a shape-free floor beats the real matcher, and we have no arbiter"
slug: 2026-08-19-selection-optimality-gap
date: 2026-08-19
status: complete
subsystem: [shape-context, frontier]
summary: "Characterization run of the optimality-gap instrument proposed in the Discoveries log on 2026-07-29 but never executed. For every cell of an exhaustive census the probe scores every candidate glyph against the source block the converter actually read - mapped back through the converter's own resolved sampling geometry, not an equal partition of the native image - under three oracles: GMSD, which every archived descriptor verdict was decided by, HaarPSI, the record's existing cross-check, and MAE, added because the first two are both gradient or wavelet structure metrics and are therefore not a disjoint pair. The distance from the production pick to the loss-optimal pick is decomposed into a pool-exclusion term and a ranking term against the real matcher pool read back from the converter. Four results. First, the pre-registered rule that a gap under 3 percent would close the family permanently is not triggered, but only narrowly on the dense charsets - the smallest measured gap is 3.58 percent on braille under MAE - so what keeps selection open is the sparse shipping preset, not the dense sets the kill record was measured on. Second, the composition of the gap inverts with charset size, because the pre-filter admits 12 candidates while eight of the ten built-in character sets hold 12 glyphs or fewer: on the dense sets pool exclusion is the majority term of a modest total, while on the sparse sets including the frozen blocks preset the pre-filter is a literal no-op and the whole gap is descriptor mis-ranking, at an order of magnitude larger. Third and most consequential, on that frozen shipping preset a shape-free matcher that picks purely by ink coverage beats the real matcher under all three oracles by 40 percent to 4.1 times, because once the pre-filter is inert brightness survives only as a tie-break and tone information is discarded at selection time, leaving the pick to a descriptor the companion note shows carries 2 or 3 of 60 bins. Under MAE the production pick on blocks averages rank 7.22 of 8 - second worst available. Fourth, descriptor support is not the lever: raising oversample sixteenfold, lifting reachable bins from 3 of 60 to 48 of 60, moves the shipped gap by 0.50 points and leaves mean rank unchanged at 3.75 versus 3.74 of 8. A ranker that does not improve when handed sixteen times the information is not information-limited, and on sparse charsets its opinion is worse than silence. The first published version of this note scored an equal row-by-column partition of the native image rather than the converter's sampled rectangle, which inflated the dense-charset gaps by two to six times; that error was caught in review and every number here is the corrected measurement."
related_specs: [docs/Research/Discoveries.md, docs/Research/2026-08-19-sampling-lattice-support-collapse.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1]
runners: [AskiColorLab]
next_action: "The cheapest and most direct follow-up is ASKI-30: on sparse charsets the pre-filter is inert, so tone is discarded at selection time and a shape-free floor beats the real matcher by 40 percent to 4.1 times - score shape distance plus a tone term instead, reusing the toneWeight machinery occupancyMatching already has. Do not build another descriptor channel and do not widen the pool on this evidence. The blocking gap is an arbiter: ASKI-27 audits the per-cell oracle (GMSD is ranked last of eleven as an optimization objective and Xu et al. already showed full-reference-optimal glyph picks are perceptually wrong), and until it settles, no reconstruction-metric result licenses a default change. ASKI-28 holds the pool-width sweep for the dense charsets only, and its priority drops now that the corrected dense-charset gap is 3.6 to 4.7 percent under MAE rather than 8 to 10. The frozen rule against another orientation-channel variant is unchanged and this note strengthens it - the corrected dense-charset ranking headroom is 2.26 percent of production GMSD, below the 3.0 percent promotion bar those channels had to clear."
---

# Selection optimality gap

**Status:** SETTLED as a **characterization** — explicitly not a PASS/KILL gate. The headlines (a large gap
on the sparse shipping preset that does not close with descriptor support; a shape-free floor that beats
the real matcher there) reproduce across three charsets, three oracles and five oversample arms. The
*interpretation of the gap's size* is deliberately left open, because §5 shows the oracle defining
"optimal" is itself contested; the §3b tone-only inversion does **not** depend on that, since it compares
two real selectors rather than a selector against a metric's argmin.

> **Superseded in part, same day, by
> [2026-08-19 — House-oracle audit](2026-08-19-house-oracle-audit.md) (ASKI-27).** Nothing below is
> withdrawn and every number here reproduces exactly under that audit. Three things change. **(1)** The
> §5 oracle question is settled: MAE is the house oracle; GMSD and HaarPSI are disqualified from
> *defining* an optimum (they fail a reference-recovery screen through the converter's own cell geometry),
> though not from the A/B comparisons the archived kills actually made. **(2)** §4's ranking-headroom
> reading is no longer safe to quote unqualified — under the house oracle the same measurement gives
> 1.8–2.4% on `nasa-steerable-v1` and 2.9–3.9% on `nasa-structure-v1`, i.e. it straddles the +3.0% bar
> depending on corpus. **(3)** The §8 reproduce command below **omits `--corpus`** and therefore runs the
> 2048px `nasa-structure-v1` default rather than the 3072px `nasa-steerable-v1` this note reports; append
> `--corpus docs/Research/Corpus/nasa-steerable-v1/assets` to reproduce these tables.

> **Revision, same day.** Every number in this note is a **re-measurement**. The first version scored each
> glyph against an equal `rows × cols` partition of the native image rather than the rectangle the
> converter actually sampled, and subsampled cells at a fixed lattice phase while calling the result a
> population mean. Both were caught by an automated code review of this branch and both are fixed (§2, degeneracy checks
> 4 and 5). The dense-charset gaps fell 2–6×, the sparse-preset gap and the tone-only margin grew, and two
> conclusions changed direction — see the call-outs in §3a and §4. The `oversample` null (§3c) and the
> `oversample: 4` anomaly reproduced unchanged, which is the strongest evidence either has.

**Branch:** `research/selection-ceiling-and-grid-phase` · **Date executed:** 2026-08-19

**Companion note:** [2026-08-19 — Sampling-lattice support collapse](2026-08-19-sampling-lattice-support-collapse.md).
That note establishes *what the descriptor can represent* (2–3 of 60 bins at shipping settings); this one
measures *what its opinion is worth*. The two lock together in §4.

## 1. Question

The Discoveries entry of 2026-07-29 proposed settling the whole selection-improvement family at once, and
pre-registered a rule:

> *if gap < ~3% aggregate, the proposal is dead on arrival and the whole family is permanently
> deprioritized.*

Its stated prior was that the gap would be **small** — Coumar & Kingston (arXiv 2503.14375, Mar 2025) ran
13 selection rules from log-polar shape matching through ResNet18 and got SSIM 0.6317–0.6681, a 5.8%
relative spread with the *classical log-polar matcher scoring highest*; and ASTSK-35's
ρ-lift-that-did-not-transfer read as consistent with a near-ceiling argmax. The instrument was never
built. This note builds and runs it.

## 2. Instrument

Per sampled cell, over the **full** charset:

| quantity | meaning |
| --- | --- |
| `prod` | the glyph the real converter picked |
| `optGlobal` | loss-optimal glyph — best over *all* candidates |
| `optPool` | best glyph *inside the pool the matcher actually saw* |
| `toneOnly` | shape-free floor: glyph whose ink coverage best matches the cell mean |

```
totalGap = (prod − optGlobal) / prod        how far the pick is from optimal
rankGap  = (prod − optPool)   / prod        cost of mis-ranking INSIDE the pool
poolGap  = (optPool − optGlobal) / prod     cost of the optimum never entering the pool
```

`totalGap = rankGap + poolGap` by construction. The split is the point: it separates *"the descriptor
ranked badly"* from *"the descriptor was never shown the right answer."*

**Method fidelity.** Scoring reproduces `ProductionPathArm` verbatim — candidate rasterized at a fixed
24px footprint, source block taken at native resolution and resampled to the same footprint by the
validated `LumaResample`, compared under each oracle in turn. The source block is the one the converter
*read*: each cell is mapped back through the converter's own resolved `SamplingGeometry`, not through an
equal `rows × cols` partition of the native image (see degeneracy check 4 — this correction is worth 2–6×
on the dense charsets). GMSD and HaarPSI are gradient/wavelet based and hence
inversion-invariant, so glyph luma and source luma are comparable without ink matching; MAE is not, and is
run in the matcher's own polarity convention. Reusing the record's construction is what makes this run
readable against the record.

**Corpus.** Committed `nasa-steerable-v1` held-out naturals (3 fixtures, 3072×3072), `columns: 80`,
monochrome palette, **exhaustive cell census** (`stride: 1`) → **8640 scored cells per arm**.

### Pre-run degeneracy checks

1. **Metric overfitting.** The argmin under one metric is not the perceptual optimum. Mitigated by running
   **three** oracles, each taking **its own** argmax, and deliberately including one (MAE) that is
   separable and luminance-aware rather than a structure metric. **Not eliminated** — see §5.
2. **A hand-rebuilt pool.** The first version reconstructed the pool from cell mean luma. That was wrong:
   the pre-filter compares the source cell's **OKLab L** (`stats.adjustedL`) against each glyph's
   **normalized ink density** — different quantities, different polarity convention. The error produced a
   structurally impossible **negative `rankGap`** (a pool minimum worse than a pool member), which is what
   caught it. The final probe reads the **real** ranked pool back out of the converter via the
   `@_spi(AskiResearch)` `rankedCandidateIndices`. *Instrument lesson: a decomposition whose terms carry a
   known sign constraint has a built-in tripwire — check the sign before reading the magnitude.*
3. **A rigged floor.** `toneOnly` follows the matcher's own polarity convention — `GlyphRaster.luma` is
   ink-high and the pre-filter maps high source L to high ink density (light ink on a dark ground), so the
   floor sees exactly the orientation production sees. An earlier draft tried both polarities and kept the
   better; that is harmless under the two inversion-invariant oracles but silently hands the floor a free
   degree of freedom under MAE, which is polarity-sensitive. The §3b result is reported with the corrected
   single-polarity floor and is *smaller* than the two-polarity version, i.e. conservative.
4. **Scoring the pixels the converter never read.** The first published version of this note partitioned
   the native image into `rows × cols` equal blocks. That is not the converter's partition: the integer
   cell pitch means only the top-left `columns·cellWidth × rows·cellHeight` of the thumbnail is ever
   sampled, and at the shipping arm 16 of 160 thumbnail rows — **10% of the image height** — are dropped.
   The equal partition therefore charged each glyph against a patch displaced *cumulatively with row
   index*, reaching 299 native pixels — **about four cell heights** — at the bottom row. The first version
   listed this under "other limits" and sized it at "≤ one cell row, ≈2.8%, does not affect
   comparability." **That estimate was wrong and the dismissal was wrong**: correcting it moved the
   dense-charset gap by 2–6× (standard GMSD 30.99% → 18.71%, braille HaarPSI 38.60% → 6.04%) and
   `optInPool` on `braille` from 6.9% to 37.3%. The probe now
   maps every cell through the converter's own `SamplingGeometry` (`SampledSource.lumaBlock`). *Instrument
   lesson: a misregistration that grows with index is not bounded by its per-step size — bound it at the
   last index, not the first.* Caught by an automated code review of this branch, 2026-08-19.
5. **A fixed-phase subsample presented as a population mean.** The first version subsampled cells at
   `stride: 2` with both loops starting at zero, i.e. only cells congruent to `(0,0) mod 2`, and the flag's
   own help text called that "unbiased." It is one phase of the lattice, and it can alias with periodic
   content and with cell-position effects. This run is an **exhaustive census** — every cell, `stride: 1`.
   Also caught in review.

## 3. Results

All rows: `columns: 80`, `oversample: 2` (shipping), 8640 scored cells (exhaustive), three fixtures. GMSD and MAE are
distances, HaarPSI a similarity; every gap is normalized to the production score and signed so **positive
always means "optimal is better."** `poolW` is the mean realized pre-filter width.

### 3a. The gap is large on every charset, and its composition inverts

| charset | glyphs | poolW | oracle | prod | optPool | optGlobal | **totalGap** | rankGap | poolGap | meanRank | optInPool |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **blocks** (shipped) | 8 | 8.0 | GMSD | 0.33993 | 0.16435 | 0.16435 | **51.65%** | 51.65% | 0.00% | 3.75 / 8 | 100.0% |
| **blocks** (shipped) | 8 | 8.0 | HaarPSI | 0.09480 | 0.40517 | 0.40517 | **327.38%** | 327.38% | 0.00% | 2.53 / 8 | 100.0% |
| **blocks** (shipped) | 8 | 8.0 | MAE | 0.56329 | 0.21528 | 0.21528 | **61.78%** | 61.78% | 0.00% | 7.22 / 8 | 100.0% |
| standard | 95 | 12.0 | GMSD | 0.20146 | 0.19691 | 0.16377 | **18.71%** | 2.26% | 16.45% | 24.79 / 95 | 41.5% |
| standard | 95 | 12.0 | HaarPSI | 0.37160 | 0.38723 | 0.39937 | **7.47%** | 4.21% | 3.27% | 33.59 / 95 | 46.7% |
| standard | 95 | 12.0 | MAE | 0.24363 | 0.23916 | 0.23222 | **4.68%** | 1.83% | 2.85% | 20.65 / 95 | 43.6% |
| braille | 256 | 12.0 | GMSD | 0.20387 | 0.19870 | 0.16515 | **18.99%** | 2.54% | 16.46% | 90.29 / 256 | 37.3% |
| braille | 256 | 12.0 | HaarPSI | 0.38286 | 0.38978 | 0.40597 | **6.04%** | 1.81% | 4.23% | 87.91 / 256 | 37.8% |
| braille | 256 | 12.0 | MAE | 0.24324 | 0.24118 | 0.23453 | **3.58%** | 0.85% | 2.73% | 42.49 / 256 | 35.6% |

**The pre-registered 3% rule is not triggered on any charset under any oracle** — but on the dense sets it
is a near thing, and that is a correction to this note's first version rather than a confirmation of it.
The smallest gap is **3.58%** (`braille` under MAE), against a bar of "~3%". Read honestly: on the dense
charsets, under the luminance-aware oracle, selection **is** close to ceiling and the pre-registered rule
very nearly fires. What keeps the family alive is not the dense sets — it is the shipped sparse preset,
where the gap is 52–327%.

> The first version of this note reported the smallest gap as 8.33% and called the rule "falsified on every
> charset under every oracle." That was an artifact of scoring against source patches the converter never
> read (§2, degeneracy check 4). The corrected dense-charset gaps are 2–6× smaller. **The conclusion
> narrows from "selection has headroom everywhere" to "selection has headroom on sparse charsets."**

**Composition inverts with charset size.** The pre-filter admits `topK = 12 + round(density * 24)` — **12**
at the default `density: 0` — while built-in glyph counts are diagonal 4, diamond 4, cross 5, **blocks 8**,
dots 8, minimal 10, lines 12, mixed 12, standard 95, braille 256. So on **eight of the ten built-in sets
the pre-filter admits the entire charset and is a literal no-op** (`poolW == 8.0` for blocks above, and
`optInPool == 100%`, `poolGap == 0`).

- **Dense sets:** the pre-filter binds. On `standard` the optimum is outside the pool in ~58% of cells;
  on `braille`, ~63%. Pool exclusion is still the majority term under GMSD (16.45 of 18.71 points on
  `standard`, 16.46 of 18.99 on `braille`) — but the *total* is now small, so the majority is of a modest
  number. Under HaarPSI and MAE the two terms are comparable and both are low single digits.
- **Sparse sets, including the frozen `blocks` preset:** the pool is irrelevant and the gap is **100%
  ranking** — and it is now the largest gap in the table by an order of magnitude, not by a factor of two.

**MAE splits the two regimes sharply, and the split is the load-bearing result.** Under the
luminance-aware separable oracle the dense-charset gap is **3.6–4.7%** — at the pre-registered bar — while
the shipped `blocks` gap stays at **62%**. Read together with §5: on dense charsets both the structure
metrics' extra headroom *and* most of the absolute gap were instrument, and what survives correction is a
single sharp finding about the sparse shipping preset.

### 3b. On the shipped preset, a shape-free matcher beats the real matcher

`toneOnly` removes the shape term entirely and picks purely by ink coverage, using the matcher's own
polarity convention (`GlyphRaster.luma` is ink-high; the pre-filter maps high source L to high ink
density — light ink on a dark ground). Lower is better for GMSD and MAE, higher for HaarPSI.

| charset | oracle | production | toneOnly | winner |
| --- | --- | --- | --- | --- |
| **blocks** | GMSD | 0.33993 | **0.20278** | **tone-only, by 40%** |
| **blocks** | HaarPSI | 0.09480 | **0.38673** | **tone-only, by 4.1×** |
| **blocks** | MAE | 0.56329 | **0.24637** | **tone-only, by 2.3×** |
| standard | GMSD | **0.20146** | 0.20808 | production, by 3.2% |
| standard | HaarPSI | **0.37160** | 0.36731 | production, by 1.2% |
| standard | MAE | **0.24363** | 0.24959 | production, by 2.4% |
| braille | GMSD | **0.20387** | 0.20607 | production, by 1.1% |
| braille | HaarPSI | **0.38286** | 0.37425 | production, by 2.2% |
| braille | MAE | **0.24324** | 0.24467 | production, by 0.6% |

> **On the ASTSK-47-frozen shipping preset, discarding the 60D shape descriptor entirely and matching on
> ink coverage alone produces a better result under all three oracles — by 40% to 4.1×.**

The correction sharpened this result in both directions. On `blocks` the tone-only margin **grew** (GMSD
17% → 40%, HaarPSI 2.0× → 4.1×). On the dense sets production's margin **shrank** to 0.6–3.2%, and the one
oracle that previously sided with tone-only on `braille` now sides with production. The pattern is
therefore cleaner than the first version reported: **the shape term is decisive-and-wrong on sparse
charsets and near-inert on dense ones**, rather than mixed everywhere.

The mechanism is exact and follows from §3a. `findBestScored` prunes to the `topK` brightness-nearest
candidates and then takes `argmin` of shape distance *within that pool*, with brightness surviving only as
a tie-break in the `(distance, brightnessDelta, index)` ordering. When `topK >= glyphCount` the pruning
step is a no-op, so **tone information is discarded at selection time** and the pick is decided by a shape
term that the companion note shows carries 2–3 bins. On dense charsets the pre-filter is still doing the
tone work, which is why production wins there. On sparse charsets nothing is.

This is a stronger and more specific claim than "the descriptor is weak": on the configuration the product
actually ships, the descriptor is not merely uninformative, it is **actively worse than not consulting it**.

### 3c. Descriptor support is not the lever — the null reproduces on both charsets and all three oracles

The companion note shows `oversample` lifts reachable descriptor support from **3 of 60 bins** to **48 of
60**. If starvation were the binding constraint, pick quality would track it.

| oversample | cell | reachable bins | blocks GMSD | blocks HaarPSI | blocks MAE | blocks meanRank | standard GMSD | standard meanRank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2 (shipping) | 2×4 | 3 / 60 | 51.65% | 327.38% | 61.78% | 3.75 / 8 | 18.71% | 24.79 / 95 |
| 4 | 4×8 | 11 / 60 | **55.17%** | **543.88%** | 58.26% | **6.21 / 8** | **20.32%** | **35.85 / 95** |
| 8 | 8×17 | 30 / 60 | 52.11% | 332.94% | 62.12% | 3.72 / 8 | 18.95% | 24.31 / 95 |
| 16 | 16×35 | 42 / 60 | 52.07% | 335.67% | 62.31% | 3.76 / 8 | 18.82% | 25.50 / 95 |
| 32 | 32×71 | 48 / 60 | 52.15% | 336.20% | 62.40% | 3.74 / 8 | 18.74% | 24.25 / 95 |

**It does not track.** Sixteen-fold more descriptor support changes the `blocks` gap by **0.50 points**
(GMSD), **8.82 points** on a 327-point base (HaarPSI) and **0.62 points** (MAE), and the `standard` gap by
**0.03 points**. `blocks` meanRank is 3.75/8 at 3 bins and 3.74/8 at 48. A ranker with 3 bins and a ranker
with 48 bins are, for practical purposes, identically far from optimal. Whatever is wrong with the ranking
is **not** a resolution problem.

The **`oversample: 4` arm is reproducibly the worst** under both structure oracles on both charsets — a
4×8 cell reaches 11 bins over radial rings {2,3,4} and 8 of 12 angular bins, a *lopsided, partially
populated* support. Under the corrected instrument the effect is **larger** than first reported: `blocks`
meanRank degrades from 3.75 to **6.21 of 8** where a coin flip gives 4.5, and `standard` meanRank from
24.79 to **35.85 of 95**. The conjecture is that a partially populated log-polar basis expresses a *biased*
opinion where an almost-empty one expresses nearly none. It is a conjecture and not a finding: MAE does
**not** reproduce it (58.26% at `oversample: 4` is the *best* MAE arm, as it was in the first version), so
the effect is oracle-dependent — and its reproduction across an instrument correction that moved every
other number is the strongest evidence it is real.

## 4. Reading this against the kill record

ASTSK-31, ASTSK-35 and ASTSK-42 all proposed **ranking** improvements — a better basis, an augmented
basis, a steerable orientation channel — and all were killed. Two things follow.

**First, on the dense charset those gates were scored against, the total ranking headroom is 2.26% of
production GMSD — against a +3.0% promotion bar.** A perfect ranker, one that picked the pool optimum in
every cell, would have moved `standard` GMSD by less than the bar it had to clear. Those gates were
unwinnable on their own terms before the first line of channel code was written, and no amount of basis
work could have changed that. Meanwhile the 16.45-point pool term — seven times larger — sat uninstrumented
the entire time. Each kill remains correct; the inference drawn from them, that *selection* is
near-ceiling, was drawn from the one charset family where it happens to be nearly true, and does not
transfer to the sparse sets the product ships.

> This is a reversal from the first version of this note, which put the dense-charset ranking headroom at
> 4.40% — above the bar — and read the kills as "competing for two-thirds of the available headroom." With
> the source blocks aligned, the headroom is *below* the bar. The kills look better, not worse.

**Second, and more usefully, the whole line was measured on the wrong configuration.** Combining §3b and
§3c with the companion note gives the shipped path in one sentence:

> The pre-filter is inert, so the pick is pure shape distance; the shape descriptor carries 2–3 bins;
> giving it 48 bins changes nothing; and simply not consulting it beats it under every oracle.

A ranker that does not improve when handed sixteen times the information is not information-limited. It is
optimizing something other than what the oracles measure — and on sparse charsets its opinion is worse
than silence.

## 5. The oracle is impeached — read the gap accordingly

This section is why the note stops at characterization. A frontier sweep run alongside it surfaced two
primary results, neither previously in the record, that undercut GMSD as a per-cell objective:

- **Ding, Ma, Wang & Simoncelli, IJCV 2021** rank **GMSD last of 11** full-reference metrics used as an
  *optimization objective* in a four-task human study, diagnosing it as **luminance-blind**; they find
  plain **MAE** competitive and MS-SSIM's advantage over MAE statistically insignificant. Mechanistically:
  GMSD pools by the **standard deviation** of the gradient-magnitude-similarity map, so a per-cell argmin
  rewards *uniform mediocrity* over a glyph that is right across most of a cell and wrong in one corner.
  In a medium where per-cell tone is half the signal, that is the wrong preference.
- **Xu, Zhang & Wong, SIGGRAPH 2010, Figure 7** already demonstrated — for glyph selection specifically —
  that the loss-optimal pick under alignment-sensitive full-reference metrics is *perceptually wrong*:
  SSIM and blurred-RMSE select `=` for a centred horizontal line where `-` is the right answer, because
  the lower stroke maximizes overlap area.

Two further cautions. **GMSD and HaarPSI are not a disjoint pair** — both are gradient/wavelet structure
metrics — so their agreement in §3a is weaker evidence than the house two-oracle rule normally implies;
and HaarPSI's pooling uses a **global denominator**, so a strict per-cell argmax under it is not cleanly
well-posed. Aski's GMSD also deliberately omits the canonical 2×2 mean filter and dyadic subsample, so
published GMSD correlation numbers do not transfer to this variant.

**Consequence for this note.** The measured gap is real *as those metrics score it*, which is exactly the
right frame for re-reading a record decided by those metrics — that inference stands. It is **not** a
promise that a human would prefer the optimal picks, and §3b's `blocks` result should make anyone
suspicious in the other direction: a metric under which the shape term is *worse than useless* — tone-only
beats it by 40% — on the charset a human A/B chose as best-looking (ASTSK-47) is either detecting something
real about the shipping path or measuring the wrong thing, and the oracles cannot tell us which.
**MAE was therefore run as a third, separable, luminance-aware oracle, and it matters.** On the dense
charsets it cuts the measured gap by roughly four times (standard 18.71% → 4.68%; braille 18.99% → 3.58%),
which is direct evidence that most of the structure metrics' reported headroom there is luminance blindness
rather than recoverable quality. On the shipped `blocks` preset it does **not** — 61.78%, larger than
GMSD's 51.65% — and it agrees with both structure oracles that the shape-free floor wins (§3b). So the
oracle critique bites hardest exactly where the record's attention was (dense charsets, ranking channels)
and leaves the shipped-preset finding standing.

**The blocking instrument is an arbiter, not another channel.** When the selector and the scorer disagree
by 52% on the shipped preset and the scorer is impeached, the next measurement must be something that can
adjudicate — the
parked human-preference / VLM A-B instrument (Discoveries, 2026-07-06 and 2026-07-29), not a fourth
orientation channel.

## 6. Other limits

- **A characterization, not a gate.** Three fixtures, one column count, one tile shape, no frozen
  PASS/KILL rule. The cell census is exhaustive, but the corpus is not a sample of anything. Sized to
  answer "is there headroom, and where," not to promote anything.
- **`exactOptimal` is tie-deflated on sparse charsets.** With 8 block glyphs, ties are common and the probe
  credits only an exact index match, which is why `blocks` shows 0.9% exact-optimal under GMSD while its
  `meanRank` of 3.75/8 is merely mediocre rather than catastrophic. Read `meanRank`, `totalGap` and the §3b
  head-to-head, which are tie-robust; do not quote `exactOptimal` for sparse sets. Note the sharpest single
  number in the run is a rank: under MAE the production pick on `blocks` averages **7.22 of 8** — second
  worst available.
- **§3b compares two selectors, not a selector against a metric.** That is why it survives §5: it needs the
  oracles only to rank two *realizable* renderings, not to define an unreachable optimum. It is still an
  oracle-mediated comparison, so a perceptual arbiter remains the right confirmation — but no argmin-over-
  a-metric step is involved.
- **Residual sub-pixel misregistration.** The cell→native mapping is floor-rounded on both edges, so the
  oracle's block can differ from the converter's by under one native pixel per edge (≈2.6% of a 38px block
  width here). The *systematic* misregistration this bullet used to describe — the equal-partition drift
  that reached 10% of frame height — is gone; see §2 degeneracy check 4. This also means the run is **no
  longer construction-identical to the archived ASTSK-35/42 arms**, which score the equal partition. Those
  arms are self-consistent, so their internal comparisons stand, but their absolute magnitudes are not
  directly comparable with this note's.
- **`optInPool` is a lower bound on what a wider pool could reach**, not a prediction — widening the pool
  also widens the descriptor's opportunity to rank badly, and the ranking term is not zero.

## 7. What we picked, and why

**No default changes.** `topK` stays `12 + round(density * 24)`, the descriptor is untouched, rendering is
byte-identical. The deliverable is the measurement and the redirect.

The redirect is **not** "build a better descriptor" and **not** "widen the pool." It is that on sparse
charsets the scoring function discards tone, and the cheapest experiment in the whole space is to stop
doing that — score `shapeDistance + w · toneDelta²` instead of pruning-then-shape-argmin. That machinery
already exists for `occupancyMatching` (`toneWeight = occupancyMatching · 50`) and would need a different
gate, not new code. Filed as ASKI-30.

Follow-ups: ASKI-30 (tone-weighted score for sparse charsets — the direct consequence of §3b), ASKI-27
(oracle audit — the blocker on any magnitude claim), ASKI-28 (pool-width sweep, dense charsets only),
ASKI-29 (re-run an archived verdict at the shipping regime).

## 8. Reproducing

```bash
swift run AskiColorLab selection-ceiling --charset blocks,standard --columns 80 --oversample 2,4,8,16,32
```

## Sources

- Discoveries log, 2026-07-29 — "Optimality-gap instrument", the pre-registered <3% rule this falsifies;
  2026-06-14 — the ρ-lift-vs-pick-quality entry §4 explains; 2026-07-06 and 2026-07-29 — the parked
  human-preference / VLM arbiter §5 calls for.
- Ding, Ma, Wang, Simoncelli, *Comparison of Full-Reference Image Quality Models for Optimization of Image
  Processing Systems*, IJCV 2021 — GMSD ranked last of 11 as an objective; MAE competitive.
- Xu, Zhang, Wong, *Structure-based ASCII Art*, ACM TOG 29(4):52 / SIGGRAPH 2010 — Fig. 7's demonstration
  that full-reference-optimal glyph picks are perceptually wrong; also the source of the 60-bin design.
- Coumar & Kingston, *Evaluating Deep Learning for ASCII Art Generation*, arXiv 2503.14375 (Mar 2025) —
  13 selection rules, SSIM 0.6317–0.6681, classical log-polar highest. The near-ceiling prior. Scope
  caveats carried from the record: 10×10px tiles, pre-extracted line art, no colour, no variance reported.
- Blau & Michaeli, *The Perception-Distortion Tradeoff*, CVPR 2018 — why §5 refuses to call the measured
  gap perceptual headroom.
- `ProductionPathArm` in Git history (retired by ASKI-68) — the scoring construction reused verbatim
  for comparability.
