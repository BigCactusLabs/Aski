---
title: "Sampling-Lattice Support Collapse - the shipping 60D descriptor carries 2-3 bins"
slug: 2026-08-19-sampling-lattice-support-collapse
date: 2026-08-19
status: complete
subsystem: [shape-context, tile-grid]
summary: "Structural result, decisive by arithmetic and confirmed empirically. The converter caps its thumbnail's longest side at columns times oversample, so at the default oversample of 2 the per-cell source patch is exactly 2 pixels wide on every image, at every column count. ShapeContext.histogram60 then admits a pixel only when its radius falls in the half-open band between 0.5 and min(width,height)/2, which for a 2-pixel-wide cell admits 2 or 3 pixels out of 8 and reaches 2 or 3 of the 60 bins - one bin per admitted pixel. After L1 normalization the shipped 60-dimensional log-polar shape context is a one-to-two parameter vertical-asymmetry statistic. A sweep of source aspect from 3 to 1 through 1 to 3, read back from the converter's own resolved geometry, shows every aspect landing on the same 2 by 4 footprint at columns 80, so the collapse is not an artifact of one image shape. Cell-height parity flips which bins are reachable - even heights land in radial bin 4, odd heights in radial bin 0. The current exact-lattice 3072-square census finds transitions through column 16 and none above 16, so the discontinuity is real in the thumbnail regime and never fires at the frozen preset's 76 columns. The candidate side is unaffected because glyph reference descriptors are rasterized at 64 by 64 and average 27.9 non-zero bins, so the matcher compares a 2-to-3-sparse query against dense candidates that do not live on the same support. Three further consequences are measured: only 4 to 8 of 95 glyphs are ever used at default settings; integer cell pitch silently truncated up to about 10 percent of image height off the bottom edge - SINCE FIXED by ASKI-65, which draws the thumbnail into an exact columns times cellWidth by rows times cellHeight raster so nothing is dropped, at the cost of a second resampling stage; this one clause no longer describes the shipping converter and the rest of the note still does; and a 1-pixel-wide cell, reachable at oversample 1 on portrait sources, yields an all-zero descriptor that matches the space glyph. ASKI-29 has since closed the regime evidence gap: a current exact-lattice ASTSK-42-style replay held the archived KILL under MAE, GMSD, 1 minus HaarPSI, contrast-weighted SSIM, and MILO at both shipping 3-of-60 support and a separate 48-of-60 comparator. A second unstudied lattice parameter, sub-cell phase, was measured over a full 16-arm sweep with a pitch derived from the converter's own cell and killed - best-to-worst spread is 0.38 to 1.24 percent against a selection optimality gap of 18.7 percent on standard and 51.7 percent on the shipped blocks preset, so it is 20 to 50 times too small to be worth a per-image search."
related_specs: [docs/Research/Discoveries.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-occupancy-v1]
runners: [AskiColorLab]
next_action: "Decide whether the shipping regime should keep a descriptor it cannot support. The evidence follow-ups are now closed: ASKI-25 and ASKI-65 removed the zero-support and dropped-pixel failures; ASKI-31 measured the exact-lattice change as NO HARM; ASKI-26 measured candidate-side alternatives; and ASKI-29 replayed ASTSK-42 at the shipping regime, where all five metrics held the archived KILL. Raising oversample remains a measured null, not a fix."
---

# Sampling-lattice support collapse

**Status:** SETTLED — structural finding, decisive by construction. The core claim is arithmetic over
`ShapeContext.histogram60`'s admission rule and is reproducible without any oracle; the corpus numbers
confirm it on real images rather than establishing it.

**Branch:** `research/selection-ceiling-and-grid-phase` · **Date executed:** 2026-08-19

**Companion note:** [2026-08-19 — Selection optimality gap](2026-08-19-selection-optimality-gap.md). This
note establishes *what the descriptor can represent*; the companion measures *how much the descriptor's
opinion is worth*. They were run together and should be read together.

## 1. Question

Six consecutive attempts to improve glyph selection have been killed (ASTSK-27/31 shape residual,
ASTSK-35 basis augmentation, ASTSK-42 steerable channel, plus ASTSK-7 occupancy and the ASTSK-41/43/45
temporal line). Every post-mortem framed the failure as a property of the *log-polar basis* — that it is
an orientation low-pass, degenerate on radial and diagonal content.

Nobody had asked the prior question: **at the resolution the converter actually samples, how much of the
60-dimensional descriptor is reachable at all?** The sampling lattice — its pitch, its origin, and the
number of source pixels per cell — had never been characterized. This note characterizes it.

## 2. The mechanism (pre-run arithmetic)

Three pieces of the pipeline compose into the result. All three are load-bearing and none is a bug in
isolation.

**(a) The thumbnail budget caps the cell to `oversample` pixels wide.**
`ASCIIConverter.thumbnailMaxPixelSize` caps the decoded thumbnail's longest side at
`max(columns, rows) * oversample` (and, for portrait sources, at exactly `columns * oversample` on the
width — the ASTSK-47 portrait fix). `prepareConversion` then takes an **integer** cell pitch:

```swift
let cellWidth  = thumbnail.width  / cols     // ASCIIConverter.swift:433
let cellHeight = thumbnail.height / rows     // ASCIIConverter.swift:434
```

For a landscape or square source, `thumbnail.width == columns * oversample` exactly, so

> `cellWidth == oversample`, identically, for every image and every column count.

At the default `oversample: 2` — which is also the value frozen into the canonical shipping preset by
the ASTSK-47 freeze — **every cell is exactly 2 source pixels wide.**

**(b) The histogram's radius gate then discards most of those pixels.**
`ShapeContext.histogram60` accumulates a pixel only when its radius from the cell centre satisfies
`0.5 <= r <= min(width, height) / 2` (`ShapeContext.swift:37`). For a 2-pixel-wide cell that ceiling is
`maxRadius == 1.0`, and the centre sits at `centerX == 1.0` — so the right-hand pixel column has
`dx == 0` and the left-hand column has `dx == -1`, and everything further than 1.0 from the centre is
rejected outright.

**(c) One admitted pixel contributes to exactly one bin.** So the reachable-bin count cannot exceed the
admitted-pixel count.

Composing (a)+(b)+(c) gives the shipping support directly. The admission rule, enumerated over the cell
heights a 2-px-wide cell can take:

| cell (w×h) | admitted px | reachable bins | bin IDs | radial bins |
| --- | --- | --- | --- | --- |
| 2×2 | 2 / 4 | **2 / 60** | 54, 57 | 4 |
| 2×3 | 2 / 6 | **2 / 60** | 3, 9 | 0 |
| 2×4 | 3 / 8 | **3 / 60** | 51, 54, 57 | 4 |
| 2×5 | 2 / 10 | **2 / 60** | 3, 9 | 0 |
| 2×6 | 3 / 12 | **3 / 60** | 51, 54, 57 | 4 |
| 2×7 | 2 / 14 | **2 / 60** | 3, 9 | 0 |
| 2×8 | 3 / 16 | **3 / 60** | 51, 54, 57 | 4 |

**Which of these conversion actually resolves is a separate question, and the first version of this note
did not ask it.** The `lattice-support` command now sweeps source aspect from 3:1 through 1:3, reads the
geometry back from the converter's own `samplingGeometry`, and grows each probe until the thumbnail budget
binds. At `columns: 80` the answer is a single footprint per oversample across the *entire* aspect range:

| oversample | source shapes | cell | admitted px | reachable bins | radial | angular | dropped (px) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **2** | 3:1 … 1:3 (all nine) | **2×4** | 3 / 8 | **3 / 60** | {4} | 3 / 12 | 0 × 5 … 0 × 44 |
| 4 | eight of nine | 4×8 | 11 / 32 | 11 / 60 | {2,3,4} | 8 / 12 | 0 × 11 … 0 × 88 |
| 4 | 16:9 | 4×9 | 12 / 36 | 12 / 60 | {0,2,3,4} | 10 / 12 | 0 × 0 |
| 8 | eight of nine | 8×17 | 48 / 136 | 30 / 60 | {0..4} | 12 / 12 | 0 × 9 … 0 × 67 |
| 8 | 16:9 | 8×18 | 47 / 144 | 28 / 60 | {1,2,3,4} | 12 / 12 | 0 × 0 |
| 16 | eight of nine | 16×35 | 196 / 560 | 42 / 60 | {0..4} | 12 / 12 | 0 × 7 … 0 × 36 |
| 16 | 16:9 | 16×36 | 195 / 576 | 40 / 60 | {1,2,3,4} | 12 / 12 | 0 × 0 |

So at the shipping `oversample: 2`, **every** aspect ratio lands on 2×4 — the 3-bin, radial-{4} row. The
2×2/2×3/2×5/2×7 rows above are properties of the admission rule, not configurations a caller reaches at
this column count. `cellWidth == oversample` holds across the whole range once the thumbnail binds, which
is the stronger form of claim (a). (The first version's fixed `2...8` height table also mis-stated the
higher arms: at `oversample: 8` and `16` the resolved heights are 17 and 35, so none of the printed rows
were reachable there. Caught by an automated code review of this branch, 2026-08-19.)

Two consequences follow, and neither depends on any image or any oracle:

1. **The shipped descriptor is a 1-to-2 parameter statistic.** `histogram60` L1-normalizes its output, so
   a 3-bin vector has 2 free parameters and a 2-bin vector has 1. The reachable bins for even cell heights
   are radial-4 / angular {3, 6, 9} — "down, left, up"; for odd heights they are radial-0 / angular {3, 9}
   — literally the up-versus-down ratio of two pixels. Whatever the log-polar basis is degenerate at, at
   shipping resolution it is not being *used* as a shape basis at all.

2. **Cell-height parity flips the descriptor's meaning — but only at low column counts.** Even heights
   populate radial bin 4; odd heights populate radial bin 0. These are disjoint coordinates, so an
   even-height and an odd-height render are not measuring a coarser and finer version of the same
   quantity — they are measuring different quantities. Since `rows` is derived from `columns` and the image
   aspect, output quality *can* be a discontinuous function of the requested column count. Swept on a
   square 3072px fixture at `oversample: 2`:

   | columns | 4 | **5** | 6 | 7 | **8** | 9 | **10** | **11** | 12 | **13** | 14 | **15** | 16 … 80 |
   | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
   | cell | 2×8 | **2×5** | 2×6 | 2×4 | **2×5** | 2×4 | **2×5** | **2×5** | 2×4 | **2×5** | 2×4 | **2×5** | 2×4 |
   | bins | 3 | **2** | 3 | 3 | **2** | 3 | **2** | **2** | 3 | **2** | 3 | **2** | 3 |

   (16, 17, 18, 19, 20, 24, 32, 40, 52, 60, 64, 76 and 80 all checked; all 2×4.)

   **The flip is dense below 16 columns and absent at 16 and above.** The first version of this note stated
   the discontinuity without bounding it, which overstated it: at the ASTSK-47-frozen preset's **76
   columns** the cell is 2×4 for every source aspect from 3:1 to 1:3, and the parity discontinuity never
   fires on any realistic render. It is a genuine sharp edge in the low-column regime — ASCII "thumbnail"
   sizes — and a non-issue elsewhere. Recorded at its true scope.

### Degeneracy check

The obvious objection is that this is an artefact of how the census counts. It is not, and the check is
cheap: the census reproduces `histogram60`'s admission predicate verbatim (same `0.5` floor, same
`min(w,h)/2` ceiling, same `atan2`/`log` binning), and the empirical arm below runs the **real converter**
and reads the reachable support back from the same footprints the converter actually chose. The analytic
and empirical columns agree exactly on every fixture.

## 3. What the corpus shows

Committed `nasa-steerable-v1` naturals (3 fixtures, 3072×3072), `columns: 80`, standard 95-glyph charset,
monochrome palette. `admitted` and `reachableBins` are the census evaluated at the footprint the converter
actually selected; `dropped` is the unread thumbnail remainder.

| fixture | oversample | cell | admitted px | reachable bins | dropped | distinct glyphs used |
| --- | --- | --- | --- | --- | --- | --- |
| earth-limb-sunrise | 2 | 2×4 | 3 / 8 | 3 / 60 | 0 × 16 | 4 / 95 |
| earth-limb-sunrise | 4 | 4×8 | 11 / 32 | 11 / 60 | 0 × 32 | 5 / 95 |
| earth-limb-sunrise | 8 | 8×17 | 48 / 136 | 30 / 60 | 0 × 28 | 5 / 95 |
| earth-limb-sunrise | 16 | 16×35 | 196 / 560 | 42 / 60 | 0 × 20 | 5 / 95 |
| sahara-dunes | 2 | 2×4 | 3 / 8 | 3 / 60 | 0 × 16 | 7 / 95 |
| sahara-dunes | 4 | 4×8 | 11 / 32 | 11 / 60 | 0 × 32 | 7 / 95 |
| sahara-dunes | 8 | 8×17 | 48 / 136 | 30 / 60 | 0 × 28 | 6 / 95 |
| sahara-dunes | 16 | 16×35 | 196 / 560 | 42 / 60 | 0 × 20 | 8 / 95 |
| vavilov-crater | 2 | 2×4 | 3 / 8 | 3 / 60 | 0 × 16 | 8 / 95 |
| vavilov-crater | 4 | 4×8 | 11 / 32 | 11 / 60 | 0 × 32 | 7 / 95 |
| vavilov-crater | 8 | 8×17 | 48 / 136 | 30 / 60 | 0 × 28 | 8 / 95 |
| vavilov-crater | 16 | 16×35 | 196 / 560 | 42 / 60 | 0 × 20 | 7 / 95 |

> **Corpus correction.** The first version of this table reported `carina-cosmic-cliffs` and
> `james-lovell-portrait`, which live in `nasa-occupancy-v1` as **JPEGs**. `RealFixture.load` globs `*.png`
> only, so those rows were not reproducible from the committed command — a reader running §8 would have got
> a load error, not a mismatch. The table above is the corpus the command reads. The mixed-aspect coverage
> those two fixtures were carrying is now supplied analytically by §2's aspect sweep, which is a stronger
> instrument for that job: it spans 3:1 to 1:3 instead of two accidental aspects.

**Glyph utilization is 4–8 of 95 at the shipping regime.** Roughly 95% of the charset is never emitted.
That is consistent with a 1-to-2 parameter selector, and it is worth noting the *product* consequence
directly: the ASTSK-47 preset A/B chose `blocks` over letterforms, and a charset whose extra glyphs are
unreachable is a charset whose richness cannot pay.

### The candidate side does not collapse

Glyph reference descriptors are built at a fixed **64×64 square** raster
(`RasterizedCharacterSet.swift:32`, `BuildStandardVectors.swift:92`) and then run through the same
`histogram60`. Measured over the standard 95-glyph set: **mean 27.94 non-zero bins of 60** (min 0, max 40),
with all 5 radial and all 12 angular bins reachable.

So the matcher's L2 distance is taken between a **2-to-3-sparse query** and **dense ~28-bin candidates**.
These are not coarse and fine versions of one representation; the query's support is a measure-zero subset
of the candidate's. Most of each candidate's descriptor mass sits in bins the query can never occupy, and
that mass enters every distance identically as a near-constant offset. This is a plausible mechanistic
account of why brightness pre-filtering does most of the observable work — and the companion note measures
exactly how much.

### The anisotropy is a divergence from the published baseline, not just a resolution problem

The support mismatch is not only about *how many* pixels survive; it is about *which region of the cell*
survives, and this holds at every oversample. `maxRadius = min(w, h) / 2` inscribes a disc in the
**shorter** axis. On a square 64×64 glyph raster that disc covers ~79% of the raster. On a 1:2 source cell
it covers `π(w/2)² / (w · 2w) ≈ 39%` — and the excluded region is not scattered, it is **the top and
bottom quarters of every cell, entirely**. The query descriptor is structurally blind to the vertical
extremes of the cell it is describing, while the candidate descriptor sees the whole glyph.

`ASCIICharacterSet.swift:8` states the 60D descriptor "matches the published baseline from Xu/Zhang/Wong
SIGGRAPH Asia 2010." **The dimensionality matches; the sampling does not.** Xu et al. use the same
5 radial × 12 angular = 60 bins and the same "radius ≈ half the shorter side" rule — but they **tile
N isotropic log-polar windows across the non-square cell and concatenate them**, precisely so a 1:2 cell
gets full vertical coverage (their worked example is 72 windows → 4320-D for a 12×24 glyph). Aski uses
**N = 1** and inscribes a single disc in a stretched cell. That is a real divergence from the cited
baseline, and it is the mechanism behind the "log-polar is an orientation low-pass, degenerate on radial
and diagonal content" reading the kill record settled on: a single disc inscribed in the short axis cannot
see the content the diagonal and radial fixtures put in the corners.

The published fix is cheap in its minimal form — a 1×2 stack (upper-half disc + lower-half disc) restores
full vertical coverage at 120-D. This note does **not** propose building it: the companion note's
oversample null and pool decomposition both say the descriptor is not where the quality is, and a
correctness fix to the descriptor should be justified on its own evidence rather than on this note's.
It is recorded because the code comment's parity claim is currently inaccurate and should be either fixed
or qualified.

## 4. The regime split — the finding with the widest blast radius

`ShapeResidualCommand.noDownscaleOversample` (`ShapeResidualCommand.swift:149`) deliberately raises
`oversample` until the converter does **not** thumbnail, so the residual stays pixel-aligned with the
oracle's native source blocks. That is a correct instrument decision for measuring the descriptor. It also
moves the descriptor into a completely different regime:

| configuration | cell | admitted px | reachable bins | radial | angular |
| --- | --- | --- | --- | --- | --- |
| **shipping** (`oversample: 2`, cols 80) | 2×4 | 3 / 8 | **3 / 60** | {4} | 3 / 12 |
| ASTSK-31 lab (2048px, cols 80 → os 26) | 25×56 | 493 / 1400 | **48 / 60** | {0..4} | 12 / 12 |
| ASTSK-42 lab (3072px, cols 80 → os 39) | 38×85 | 1130 / 3230 | **48 / 60** | {0..4} | 12 / 12 |
| glyph-side raster | 64×64 | 3206 / 4096 | 52 / 60 | {0..4} | 12 / 12 |

> **Every decisive descriptor experiment in the record was run at 48 of 60 reachable bins. The frozen
> shipping preset runs at 2 or 3.**

This does **not** reverse any verdict. ASTSK-31/35/42 asked "does adding an orientation/structure channel
improve pick quality?" and answered no, at a regime where the base descriptor was fully supported — which
is the *harder* test for the channel, since a starved baseline would have been easier to beat. The kills
stand on their own terms.

What it does mean is narrower and still important: **the record contains no measurement of the descriptor
in the configuration users get.** Any statement of the form "the log-polar basis is the bottleneck for
Aski output" is unevidenced for the shipping path, because at 2–3 bins the log-polar basis is not what is
deciding anything.

## 5. Two defects found along the way

Both are structural consequences of the integer cell pitch. Filed separately; neither is speculative.

**(a) Silent bottom/right truncation.** `cellWidth * cols` and `cellHeight * rows` need not equal the
thumbnail dimensions, and the remainder is never sampled — `GridRowWalk`/`CellSampling` index strictly
`baseY = row * cellHeight` upward (`CellSampling.swift:293-294`, `330-331`). Measured drop at `columns: 80`
on the square `nasa-steerable-v1` fixtures, and across the source-aspect sweep at the shipping oversample:

| source | oversample | thumbnail | grid | dropped | % of height |
| --- | --- | --- | --- | --- | --- |
| square (corpus) | 2 | 160×160 | 80×36 | 0 × 16 px | **10.0%** |
| square (corpus) | 4 | 320×320 | 80×36 | 0 × 32 px | **10.0%** |
| square (corpus) | 8 | 640×640 | 80×36 | 0 × 28 px | 4.4% |
| square (corpus) | 16 | 1280×1280 | 80×36 | 0 × 20 px | 1.6% |
| square (corpus) | 32 | 2560×2560 | 80×36 | 0 × 4 px | 0.2% |
| 3:1 (sweep) | 2 | 160×53 | 80×12 | 0 × 5 px | **9.4%** |
| 1:3 (sweep) | 2 | 160×480 | 80×109 | 0 × 44 px | **9.2%** |

Up to roughly a tenth of the image's height is silently absent from the output. It is always the bottom
edge, so it is systematic rather than noise — and because the fraction is a function of `oversample`, it is
also a *confound* for any experiment that sweeps `oversample`. This note's first version and its companion's
both fell into exactly that trap; see the companion's §2 degeneracy check 4.

> The first version of this table reported `carina-cosmic-cliffs` and `james-lovell-portrait`, from the
> JPEG-only `nasa-occupancy-v1` corpus that `RealFixture` cannot load. Same corpus correction as §3.

**(b) A zero-descriptor cell is still reachable.** At `oversample: 1` on a portrait source,
`columns: 120` yields `cellWidth == 0` on `james-lovell-portrait` (975×1280 → thumbnail 119×158, grid
120×71). `prepareConversion` guards `cellWidth > 0` and bails, so the render is empty rather than wrong.
A 1×2 cell — reachable at the same setting on other aspect ratios — passes the guard but produces
`admitted == 0`, i.e. an **all-zero descriptor**, which is exactly equidistant from every candidate and
resolves to the space glyph. This is the same failure family as the ASTSK-47 portrait blank-render bug
(fixed for the `columns * oversample` width budget) and as backlog ASKI-16.1 (`edgeMap` zero-descriptor
collapse), but the `logPolar` path at `oversample: 1` is not covered by either fix.

> **Corrected — see §9.** "Exactly equidistant from every candidate" is wrong; the mechanism is sharper
> than that. Both defects were fixed in ASKI-25; the trigger conditions and the failure modes above are
> unchanged.

## 6. Lattice phase is inert — a second free parameter, measured and killed

The lattice origin is pinned at pixel `(0,0)`: `CellSampling` indexes strictly
`baseX = column * cellWidth`, `baseY = row * cellHeight` (`CellSampling.swift:293-294`). Sub-cell
**phase** — where cell boundaries fall relative to image content — is therefore not a parameter any
caller can set, and had never been measured. ASTSK-43's mechanistic finding (ASCII seam-breaking is
*structural*, caused by monospace side-bearing gutters at every cell seam) predicts it should matter:
content straddling a seam is cut by the gutter, content centred in a cell is not.

**Instrument.** Phase is emulated by cropping the native image before conversion. Every arm crops a window
of **identical dimensions** — native size minus exactly one cell pitch on each axis — at origin
`(fx·pitchX, fy·pitchY)` for `fx, fy ∈ {0, ¼, ½, ¾}`. Identical window size means identical grid shape and
an identical crop→thumbnail→convert path for every arm, so only content-to-boundary alignment varies. Each
arm is scored against **its own** cropped source — through that arm's own resolved `SamplingGeometry`, i.e.
the pixels the converter actually read from that crop — so content differences between windows are not
charged to phase. A **null arm** at a full pitch (`fx = fy = 1.0`) is phase-equivalent to `(0,0)`; its
delta is the content-change floor the phase spread must clear.

The pitch is derived from the converter's cell, `cellHeight · nativeHeight / thumbnailHeight`, not from
`nativeHeight / rows`. The first version of this note used the latter, which overstates the cell (56 native
rows against a true 51.2 at the shipping arm, a 9% error) and therefore put every fractional arm at the
wrong phase and left the "null" arm not actually null. Corrected here; caught by an automated code review of this branch, 2026-08-19.

| fixture | oversample | native pitch | phase arms | best | worst | **spread** | null-arm floor |
| --- | --- | --- | --- | --- | --- | --- | --- |
| earth-limb-sunrise | 2 | 25×51 | 16 | 0.27188 | 0.27524 | **1.24%** | 0.08% |
| phoenix-night-grid | 2 | 25×51 | 16 | 0.24109 | 0.24200 | **0.38%** | 0.05% |
| vavilov-crater | 2 | 25×51 | 16 | 0.24012 | 0.24188 | **0.73%** | 0.04% |
| earth-limb-sunrise | 8 | 25×54 | 16 | 0.24619 | 0.24834 | **0.87%** | 0.07% |
| phoenix-night-grid | 8 | 25×54 | 16 | 0.24920 | 0.25074 | **0.62%** | 0.08% |
| vavilov-crater | 8 | 25×54 | 16 | 0.23625 | 0.23812 | **0.79%** | 0.13% |

**KILL.** Best-to-worst spread over a full sub-cell phase sweep is **0.38–1.24%** of GMSD, at both the
shipping and a high-support regime. It sits 5–15× above the content-change floor, which is now a tight and
consistently non-zero 0.04–0.13% (the corrected pitch made the null arm genuinely near-null), so the effect
is real rather than noise — but the companion note measures the selection optimality gap on the same corpus
and oracle at **18.7% on `standard` and 51.7% on the shipped `blocks` preset**. Phase is **20–50× too small
to matter**, and it would cost a per-image search over the phase grid to capture. There is no version of
this that pays. The verdict is unchanged from the first version; only its margin moved.

Two riders worth recording. First, at the shipping regime the question is nearly moot by arithmetic
anyway: `cellWidth == oversample == 2`, so the horizontal phase space has exactly **2** distinguishable
states. Second, the ASTSK-43 prediction is not vindicated — seam-breaking being structural does not make
seam *placement* a quality lever, because the gutter cuts content wherever it is put.

## 7. What we picked, and why

**No default change is proposed in this note, and none should be made from it alone.** Raising `oversample`
is the obvious reflex, and the companion note measures it directly as a **null**: lifting reachable support
from 3 of 60 bins to 48 of 60 moves the selection optimality gap by **0.50 points on the shipped `blocks`
preset** and **0.03 points on `standard`**, and leaves `blocks` meanRank at 3.74 of 8 where 3 bins gave
3.75. A lopsided intermediate footprint (`oversample: 4`, 11 bins over radial rings {2,3,4}) is reproducibly
*worse* than the nearly-empty shipping one on both charsets. So "raise oversample" is not a fix — it is a
cost with no measured return.

That null is what makes this note's framing land. A descriptor that carries 2–3 bins is not merely starved;
it is a ranker whose accuracy does not improve when handed sixteen times the information. The support
collapse is a real and previously unknown property of the shipping path, and it explains why the descriptor
contributes little — but it is not, by itself, the thing to fix.

What this note fixes is the *epistemic* state: the sampling regime is now characterized, the lab/product
split is on the record, and future descriptor work has a mandatory precondition — state which regime it is
measuring, because the two are not the same experiment.

## 8. Reproducing

```bash
# §2 realizable-footprint census + §3 corpus arm
swift run AskiColorLab lattice-support --columns 80 --oversample 2,4,8,16 \
    --corpus docs/Research/Corpus/nasa-steerable-v1/assets
# §6 phase sweep (default corpus: nasa-structure-v1)
swift run AskiColorLab lattice-phase --columns 80 --oversample 2,8
```

`census` is a pure function of `(cellWidth, cellHeight)` and needs no corpus. The realizable arm feeds it
the footprints `prepareConversion` resolves across the source-aspect range, read back from the converter's
own `samplingGeometry` — it probes with synthetic images grown until the thumbnail budget actually binds,
so it reports regimes rather than probe artifacts. The corpus arm loads the committed NASA fixtures through
the same `RealFixture` loader the ShapeResidual battery uses; note that loader takes **PNG only**, so the
`nasa-occupancy-v1` JPEG corpus cited by the first version of this note is not reachable from this command.

> **Updated 2026-09-16 (loader change, 1f33b59 / ASKI-52+26, 2026-08-28).** The PNG-only limit above is
> historical. `RealFixture.assetExtensions` now accepts `png`, `jpg`, and `jpeg`, so the
> `nasa-occupancy-v1` and `nasa-isoluminant-v1` JPEG corpora are reachable from this command and from
> every Tools-side battery that routes through the loader. A result quoted from a lossy corpus has to say
> so, because the compression artifacts are part of the measurement. The sentence above is the original
> August text.

## 9. Corrections

**2026-08-19 — the zero-descriptor mechanism in §5(b).** Found while implementing the fix (ASKI-25), and
recorded here rather than edited into §5 so the original reading stays legible.

§5(b) says an all-zero descriptor is "exactly equidistant from every candidate" and therefore resolves to
the space glyph by tie-break. The premise is wrong. Squared-L2 from the zero vector to a candidate is that
candidate's *own* squared norm, so the distances are not equal — measured on
`StandardCharacterSet.standard`, all **95 of 95 are distinct**. The space glyph is the set's only
zero-norm reference (index 0, distance exactly 0; the next smallest is `'e'` at 0.045), so it does not win
a tie — it wins outright wherever the brightness pre-filter admits it. The sharper statement is that on a
zero-support cell the shape term describes only the candidates and carries no information about the cell.

The conclusion §5(b) draws is unaffected: the trigger is still a footprint with a one-pixel axis, the
observed failure is still a render that collapses to the space glyph, and the fix is still to detect the
degenerate footprint and stop consulting the shape term. It matters only for anyone reasoning about *why*
a tie-break was involved — it was not.

> **Updated 2026-09-02 (ASKI-65).** The §5(a) resolution recorded below — truncation kept as a
> documented contract — was superseded. ASKI-65 removed the truncation outright by drawing the
> thumbnail into an exactly grid-sized lattice raster, so `droppedX` and `droppedY` are now zero on
> every arm (asserted in `SamplingLatticeContractTests` and `AskiColorLabSamplingLatticeTests`). The
> fold preserves a UNIFORM cell pitch, so the §3 parity discontinuity described below still never
> fires. ASKI-31, which tracked the removal, is NOT thereby closed: it also required a
> selection-ceiling before/after under both MAE and GMSD as no-harm evidence for the frozen
> preset's output, and ASKI-65 re-recorded the moved goldens without running it. That census ran
> on 2026-09-02 and closed ASKI-31 as NO HARM (frozen-preset MAE ×1.0016 / ×1.0085, inside the 1.01
> guard; `docs/Research/2026-09-02-aski-31-lattice-no-harm.md`). The paragraph below is the
> original August text.

Both §5 defects are now closed. §5(a)'s truncation was settled as an explicit, tested contract rather than
removed (`droppedX == thumbnailWidth % columns`, `droppedY == thumbnailHeight % rows`, origin-anchored),
and §5(b)'s degenerate cell now falls back to a tone-only pick, so `oversample: 1` renders a tone ramp
instead of a blank grid. The fractional-lattice fix that would have removed the truncation outright was
attempted and rejected: distributing the remainder makes per-cell heights non-uniform, and by §3's own
parity result a 2×4 cell reaches bins {51, 54, 56} while a 2×5 cell reaches {3, 8} — disjoint supports. At
the shipping arm that would put 16 of 36 grid rows on different descriptor coordinates from the other 20,
firing the §3 parity discontinuity on every render where it currently never fires. Tracked as ASKI-31.

## 10. Current-path replay update

ASKI-29/50 ran the exact-lattice C80 comparison separately at shipping 2x4 /
3-of-60 support and historical-support 38x85 / 48-of-60 support. The KILL held
under all five registered losses in both regimes. Its full 4...80 census updates
the old pre-ASKI-65 boundary: parity changes at columns 5, 6, 8, 9, 10, 12,
13, 14, 15, and 16, with no further transition above 16. See
[the replay note](2026-09-04-aski29-50-steerable-metric-replay.md) and its
committed `parity.csv`; the older measurements remain historical context.

## Sources

The primary evidence is this repository. Cross-references:

- [`ShapeContext.histogram60`](../../Sources/Aski/Algorithms/ShapeContext.swift) — the radius gate and bin
  assignment the census reproduces.
- [`ASCIIConverter.thumbnailMaxPixelSize` / `prepareConversion`](../../Sources/Aski/ASCIIConverter.swift) —
  the thumbnail budget and integer cell pitch.
- [`ShapeResidualCommand.noDownscaleOversample`](../../Tools/AskiColorLab/ShapeResidual/ShapeResidualCommand.swift)
  — the lab's regime choice.
- [2026-06-09 — Glyph shape-residual field](2026-06-09-shape-residual.md) and
  [2026-06-27 — ASTSK-42 steerable channel](2026-06-27-astsk42-steerable-channel.md) — the verdicts whose
  regime this note re-frames.
**Field sources** (frontier sweep run alongside this note, 2026-08-19):

- Xu, Zhang, Wong, *Structure-based ASCII Art*, ACM TOG 29(4):52 / SIGGRAPH 2010 — the cited baseline.
  Same 5×12=60 bins and same "radius ≈ half the shorter side" rule, but **N tiled isotropic windows** over
  a non-square cell rather than Aski's single inscribed disc; also a 7×7 Gaussian pre-blur to suppress
  bin-discretization aliasing, which Aski does not apply on either side. Their framing of misalignment
  tolerance as *implicitly defined by the log-polar diagram* is the reason §6's phase null is unsurprising
  in hindsight.
- Kopf, Shamir, Peers, *Content-Adaptive Image Downscaling*, SIGGRAPH Asia 2013 — optimizing downsampling
  kernel *locations* to align with local features does work in general, which is what made §6's phase
  question worth asking and its null worth reporting.
- `stong/gradscii-art` (GitHub, AGPL-3.0; last commit 2026-01-24, dormant since — a ~2-day burst project).
  Its learnable warp is per-cell lattice phase bounded at ±½ cell, and the author names the mechanism
  (features pulled onto cell boundaries so the row gutter becomes a free crisp edge). **No ablation
  numbers, galleries only**, and the warp is realized by bilinear resampling against an MSE objective, so
  its own evidence cannot separate alignment from resampling blur. Treated as a hypothesis source, not
  evidence; §6 supplies the controlled number it lacks. Read for ideas, vendor nothing.
- Turkowski, *Filters for Common Resampling Tasks* (1990) — an even-tap box has no selectable phase, which
  is why §6 emulates phase by integer native-pixel crops with an identical resample path on every arm
  rather than by fractional offsets.
