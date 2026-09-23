---
title: "Thread D: λ dose-response + no-harm characterization (chromaShapeAssist) — PASS RETRACTED; exact-lattice redesign INCONCLUSIVE"
slug: 2026-06-11-isoluminant-dose-response
date: 2026-06-11
status: complete
subsystem: [color-science, shape-context]
summary: "RETRACTED 2026-09-02 (ASKI-65), CLOSED INCONCLUSIVE 2026-09-04 (ASKI-66): the AC #1 dose-response PASS below was an artifact of the truncating sampling lattice. A preregistered one-shot redesign ran 64 valid candidate fixtures x two axes x 21 lambda arms on an exact 8x18 lattice; every response was invariant, no candidate qualified, and the stop rule skipped holdouts. The synthetic dose-response question is INCONCLUSIVE with no wider search authorized. AC #2/#3 and the algebraic constant-L cancellation result stand. ASKI-68 later removed chromaShapeAssist and its dedicated runners; this note and Git history retain the evidence."
related_specs: [docs/research-plan.md, docs/Research/2026-09-04-aski66-exact-lattice-dose-redesign.md]
datasets: []
runners: [AskiColorLab]
next_action: "Closed by the exhausted ASKI-66 redesign and ASKI-68 cleanup. Do not restore chromaShapeAssist or re-tune this instrument without a new mechanism and a separately committed rule."
---

# Thread D: λ dose-response + no-harm characterization (chromaShapeAssist) — PASS RETRACTED

> **Retracted 2026-09-02 (ASKI-65).** The AC #1 dose-response below was measured
> through a truncating sampling lattice that never read the bottom 19 rows of the
> battery. Re-measured on exact lattices the instrument does not grade on any
> geometry probed, so the run is invalid and the June PASS is withdrawn. The
> dose-response question itself is now finally INCONCLUSIVE under ASKI-66. AC #2 and AC #3
> are not affected. Details: [Addendum](#addendum-2026-09-02-aski-65-the-pass-above-was-measured-on-a-truncated-lattice).

## Question

ASTSK-30 (PR #36) shipped `chromaShapeAssist` (λ∈0…1, default **0**, opt-in):
it injects an OKLab (a,b) Di Zenzo vector-gradient field into the logPolar
shape descriptor so isoluminant (constant-L) color edges produce glyph
structure instead of melting. It PASSED, but the synthetic **step-edge**
fixtures saturate at the first nonzero λ — entropy jumps 0→0.722 bits at λ=0.25
and is flat thereafter (`2026-06-10-isoluminant-rescue.md`). A step is a
delta-function gradient: the whole band flips all-or-nothing once, so the
instrument cannot discriminate λ values. This round asks: **is there a fixture
that yields a non-degenerate λ dose-response, and at the resulting candidate λ
does the injection harm normal colored content?**

This is a **characterization round. The default `chromaShapeAssist` stays 0.**
We report a *candidate* λ and a no-harm verdict; we do not flip the perceptual
default. The later ASTSK-37 real-corpus gate also failed promotion;
psychophysics — Switkes/De Valois, Kingdom/Gheorghiu — has luminance dominating
spatial form, so chroma stays a low-weight opt-in rescue.

## The cancellation theorem (negative result, load-bearing)

The first-built instrument — a constant-OKLab-L ramp grading **chroma
contrast** per row — is **mathematically degenerate**, and proving so reshaped
the round. The kernel's injection (`LogPolarKernel.extractShapeVector`) is
mass-normalized:

```
scale      = λ · lumaMass / chromaMass
blended[i] = (1−λ)·luma[i] + scale · chromaGradient[i]
```

For a ramp row of contrast `c`, the chroma field is `c·base`, so
`chromaMass = c·baseMass`, and the injected term is

```
scale·chroma[i] = (λ·lumaMass / (c·baseMass)) · (c·base[i])
                = λ·lumaMass·base[i] / baseMass        ← the c CANCELS
```

After normalization **every ramp row is identical** — the per-row contrast
grading is erased by construction. All rows flip at the same λ, the band
entropy is intrinsically binary, and a pure-isoluminant edge's rescued glyph is
λ-invariant above its single flip threshold. **No constant-L chroma fixture can
yield a λ dose-response.** This is not a tuning bug; the mass normalization was
chosen precisely so saturated colors can't flood the descriptor, and it forbids
the per-row signal we wanted. The two constant-L ramps are kept in the battery
as committed `.probe` evidence — they read `dose:2` (binary), the falsification
made reproducible (`constantLRampsSaturateBinary` pins it).

## Method: the competition ramp

The dose-response lives wherever chroma **competes** with luminance. The
working instrument is a luma-vs-chroma **competition ramp**:

- A **vertical achromatic luma grating** (period 8px = one canonical cell, with
  transitions placed mid-cell at `x ≡ 4 mod 8`), whose luma split `g` is
  **graded per grating block** weakest→strongest left→right.
- crossed by a **horizontal isoluminant chroma edge** at `edgeY = 260` (5px
  inside cell-row 15's Sobel interior).
- on a **non-white ink pedestal** (background OKLab L=0.55).

Why the pedestal matters — and why the sketch's intuition was incomplete: the
kernel's luma field is **inverted** luma (`1 − Y`), so `lumaMass` is dominated
by the background pedestal, not by edge contrast. A graded **luma** edge of
contrast `g` therefore enters the blend as `(1−λ)·α·g` (uncancelled) while the
chroma ridge carries exactly λ of the mass; the per-column flip point
`λ*(g) = αg/(1+αg)` genuinely sweeps with `g`. On a **white** background
`1−Y → 0`, `lumaMass ∝ g`, and `g` would cancel exactly like the constant-L
ramp's chroma did. The competition fixture is "near-isoluminant with a graded
luma competitor", not constant-L.

**Instrument: flipped fraction, not entropy.** Band = the cell row straddling
`edgeY`, all 64 columns. Per arm, `flippedFraction` = share of band cells whose
glyph differs from the λ=0 arm. AC #1: every competition ramp's flipped fraction
is monotone non-decreasing in λ and takes ≥3 distinct values across the 5-arm
sweep, with no off-band flips (an off-band flip — the grating rows carry no
above-floor chroma — would be an instrument fault). Band entropy is still
reported, but it is the wrong readout here: at λ=1, 56–58% of band cells have
flipped yet band entropy is back at its λ=0 value, because the flip set is a
*relabeling*, not a histogram spread. Flip fraction is the dose; entropy is not.

512px fixtures, `--columns 64` (native, no-downscale; 8px cells), λ ∈ {0, 0.25,
0.5, 0.75, 1.0}. Reporter only (exit 0). The constant-L verdict steps and the
pure-luminance control from ASTSK-30 are byte-intact and still gate AC #2.

## Findings

Canonical run (`isoluminant-rescue --columns 64 --fixture-size 512`):

Band flipped fraction vs λ=0 — competition ramps:

| fixture               | λ=0  | λ=0.25 | λ=0.5 | λ=0.75 | λ=1.0 | dose |
|-----------------------|------|--------|-------|--------|-------|------|
| redGreenCompetition   | 0.00 | 0.00   | 0.00  | 0.39   | 0.56  | 3    |
| blueYellowCompetition | 0.00 | 0.00   | 0.00  | 0.50   | 0.58  | 3    |

- **AC #1 dose-response: PASS.** Both competition ramps are graded (≥3 distinct
  flipped fractions), monotone, and flip nothing off-band.
- **Override onset is in (0.5, 0.75].** `override λ50` (smallest λ flipping ≥50%
  of the band) = 0.75 (blueYellow) / 1.0 (redGreen). Flipping is luminance being
  *overridden* by chroma — a thing a safe default mostly avoids — so this is the
  **upper** guard rail, not the candidate.
- **Candidate λ = 0.25, rescue-driven.** The smallest swept λ at which every
  constant-L verdict step has achieved the AC #2 entropy rise. It sits well
  below override onset — the rescue fires before chroma starts overriding luma.
- **AC #2 rise verdict: PASS** (unchanged from ASTSK-30); pure-luminance control
  exactly λ-invariant.
- **AC #3 no-harm: PASS.** At candidate λ=0.25 the colored battery
  (`colorLumaHueEdge` — dark-blue→bright-yellow luminance+hue edge;
  `orthogonalChromaEdge` — the adversarial orthogonal luma/chroma cross) shows
  **zero** SSIM-structure drop and **zero** GMSD increase vs λ=0, scored against
  the source luma block (tol 0.005). Consistent with the candidate sitting below
  override onset.
- **Floor probes straddle as intended.** `noisyBelowFloor` (Di Zenzo peak under
  0.02) is λ-invariant; `noisyAboveFloor` flips at λ>0. Committed evidence that
  the 0.02 floor rejects quantization-scale ripple and that the achromatic-flip
  measurement fires above it. (`ChromaShapeAssistTuning.gradientFloor` is now the
  single source of truth the kernel reads — behavior-preserving, no `.bin`
  churn.)

## Frontier grounding

Two design forks were grounded against the literature rather than asserted:

- **No portable chroma-noise floor constant.** CIELAB image noise "is not a
  standard measurement" (Imatest); the 0.02 floor must be *measured* on flat
  achromatic regions, not looked up. The corpus arm implements that measurement
  (p99 chroma-gradient on flipped flat cells); a sensor-calibrated *value*
  was deferred until ASTSK-37. That corpus run reported recommended floor
  `0.02000` but did not promote the default.
- **No portable chromatic-vs-luminance dominance multiplier.** Kingdom, Bell,
  Gheorghiu & Malkoc (2010, *J. Vision* / PMC4975110) — whose orthogonal
  color/luminance checkerboard is exactly the `orthogonalChromaEdge` geometry —
  state the contrasts that "roughly equate the reliability of the cues" are
  "essentially arbitrary"; Switkes/Bradley/De Valois (1988, *JOSA A* 5:1149)
  normalize to each observer's threshold, not a fixed cross-channel constant. So
  the override threshold had to be **measured** (the `override λ50`), parallel to
  the floor. The masking literature has luminance dominating spatial *form*
  (keeping a low/opt-in λ the principled default), even though Kingdom finds
  chroma over-weighted for edge *localization* — a real form-vs-localization
  split, but one that does not move the default off 0 this round.

## Real-image corpus arm

`--review-corpus DIR` was built and synthetic-tested during the ASTSK-36
characterization run, which originally had no committed corpus. ASTSK-37 now
commits `docs/Research/Corpus/nasa-isoluminant-v1/` and pre-registers the
decisive run below. The corpus arm enumerates `png/jpg/jpeg/heic`, converts each
at every λ (no-downscale so fine chroma edges survive), classifies each native
cell — `isoluminant` (low luma ∇, high chroma ∇), `achromatic-flat` (chroma ∇
below floor), `other` (luminance-structured colored) — and writes per-λ
glyph-flip rate by class plus the flat-cell p99 chroma-gradient (the
recommended-floor readout) to `isoluminant_corpus.csv`. The synthetic test
confirms isoluminant flip rate rises with λ while achromatic-flat stays ≈0 at
every λ.

**Surfaced subtlety (worth a future round):** the kernel's luma field is
**Rec.601**, but the fixtures are **OKLab**-isoluminant — and these disagree. An
OKLab-L-equal red/green edge can carry a real Rec.601 luma step (so the corpus
classifier files it as `other`, not `isoluminant`). The synthetic corpus image
is therefore matched in **Rec.601** luma, not OKLab L. A real-corpus round should
decide whether "isoluminant" for this kernel means Rec.601-isoluminant (what the
luma field sees) or perceptually isoluminant.

## ASTSK-37 pre-registered corpus gate

ASTSK-37 is the decisive real-corpus round. The run uses the committed
`docs/Research/Corpus/nasa-isoluminant-v1/` corpus and the canonical command:

```bash
swift run AskiColorLab isoluminant-rescue --output-dir /tmp/isoluminant-corpus-2026-06-11 --columns 64 --review-corpus docs/Research/Corpus/nasa-isoluminant-v1/assets --require-corpus-summary
```

The natural stratum alone can promote `chromaShapeAssist` from default `0` to
default `0.25`. The thresholds are pre-registered engineering thresholds for
this Aski harness, not externally standardized psychophysical constants:

- Coverage: at least 500 natural `isoluminant` cells, 2,000 natural
  `achromatic-flat` cells, 2,000 natural `other` cells, and at least three
  natural images with nonzero `isoluminant` cells.
- Rescue: at lambda `0.25`, pooled natural `isoluminant` flip rate must rise
  by at least `0.02` absolute over lambda `0`, and at least two natural images
  must show positive `isoluminant` lift.
- Noise: natural `achromatic-flat` flip rate at lambda `0.25` must be `<=0.005`
  pooled and `<=0.02` for every natural image.
- No harm: natural `other` flip rate at lambda `0.25` must be `<=0.01` pooled
  and `<=0.03` for every natural image.
- Floor: if flat flips are zero, keep `ChromaShapeAssistTuning.gradientFloor`
  at `0.02`. If flat flips occur but pass the noise gate, promote only with a
  conservatively rounded-up floor from flipped-flat p99.
- Diagnostics: `diagnostic-false-color` images cannot promote the default.
  They must include candidate rows for `achromatic-flat` and `other`
  (`completeness_diagnostic_flat_candidate_rows`,
  `completeness_diagnostic_other_candidate_rows`). They block promotion if
  `diagnostic_flat_pooled_flip_025` exceeds `0.02`,
  `diagnostic_other_pooled_flip_025` exceeds `0.03`, or either
  `diagnostic_flat_max_image_flip_025` or `diagnostic_other_max_image_flip_025`
  exceeds `0.08` in `isoluminant_corpus_summary.csv`.

The decision reads from `isoluminant_corpus_summary.csv`, not from manual visual
inspection. Image-level gates are retained because neighboring cells are
spatially correlated; pooled cell rates alone do not earn a default flip.

## ASTSK-37 corpus verdict

Result: **FAIL — keep `chromaShapeAssist` default 0.**

The NASA corpus run's decisive artifact is
`isoluminant_corpus_summary.csv`; failed gates: natural_isoluminant_delta_025,natural_positive_rescue_images,natural_other_pooled_flip_025,natural_other_max_image_flip_025,diagnostic_other_pooled_flip_025,diagnostic_other_max_image_flip_025.

Because the natural/visible-light decision stratum did not pass every
pre-registered gate, λ=0.25 remains opt-in. The corpus result is still useful:
it records the observed class split, image-level churn, and sensor-floor
readout for future ASTSK-7 occupancy-aware rechecks.

## Caveats

- Characterization only; **default stays 0.** Candidate λ=0.25 and the override
  onset are synthetic measurements, not a perceptual default.
- The competition g-range (OKLab L split 0.02→0.24) is tuned to the canonical
  64-col/512px geometry and the shape match's brightness-gated candidate pool:
  gratings stronger than g≈0.15 pin their pool-best glyph regardless of λ, so a
  different grid or character set would need re-tuning. The instrument refuses
  off-pattern geometry (`gratingMisaligned`, `edgeOnCellRowBoundary`) rather than
  mis-measuring.
- ASTSK-37 supplied the real-corpus sensor-floor readout: recommended floor
  `0.02000`. The default still remains 0 because the promotion gates failed.
  The measurement mechanism is implemented and unit-tested on a synthetic
  stand-in, and the 0.02 floor is confirmed to reject committed synthetic ripple.

## Decision

> **Superseded 2026-09-02 (ASKI-65).** ~~AC #1 PASS~~ is retracted: invalid run,
> instrument artifact. Current standing: AC #1 INCONCLUSIVE (ASKI-66), AC #2 PASS,
> AC #3 PASS, `chromaShapeAssist` default 0. The paragraph below is the original
> June text, kept for the record.

**PASS — characterization complete; `chromaShapeAssist` stays default 0, opt-in.**
AC #1 (dose-response) PASS via the competition ramp after the constant-L ramp was
proven degenerate; AC #2 (rise) and AC #3 (no-harm at candidate λ=0.25) PASS. No
`.bin` churn (kernel algorithm untouched; the floor became a behavior-preserving
SPI shim, verified by `git status` on `Sources/Aski/Resources/ShapeData/`).

## Pointers

- Knob: `Sources/Aski/RenderingOptions.swift` (`chromaShapeAssist`,
  `ChromaShapeAssistTuning.gradientFloor`)
- Kernel: `Sources/Aski/Algorithms/LogPolarKernel.swift` (`extractShapeVector`,
  `chromaGradientFloor` → SPI shim)
- Lab: `Tools/AskiColorLab/IsoluminantRescue/` (`IsoluminantFixture`,
  `IsoluminantRescueCommand`, `IsoluminantNoHarmGuard`, `IsoluminantCorpusReview`,
  `IsoluminantChromaGradient`)
- Tests: `Tests/AskiTests/AskiColorLabIsoluminantRescueTests.swift`,
  `Tests/AskiTests/ChromaShapeAssistTests.swift`

## Addendum 2026-09-02 (ASKI-65): the PASS above was measured on a truncated lattice

The AC #1 dose-response above was measured before ASKI-65 (GitHub #36). At
that time the converter took a floored integer cell pitch and sampled the
thumbnail from the origin, so the 512² battery at 64 columns (29 rows) was read
as an 8×17 cell — aspect 2.125, below the 2.2 wide-tile ratio — with the
bottom 19 rows never sampled. ASKI-65 draws every thumbnail into an exact
`columns*cellWidth × rows*cellHeight` lattice, and this lab now refuses a fixture that is not an exact lattice for
its resolved grid (the shape-residual and decolor labs instead map their native
oracle blocks through the lattice). The battery is therefore authored at the
exact-lattice height for its column count: 512×522 at 64 columns, an 8×18 cell.

Re-measured on exact lattices, band flipped fraction over λ∈{0,.25,.5,.75,1}:

| geometry | cell | rows | redGreen | blueYellow | distinct |
|---|---|---|---|---|---|
| 512×522 @ 64 | 8×18 | 29 | 0/0/0/0/0 | 0/0/0/0/0 | 1 |
| 256×270 @ 32 | 8×18 | 15 | 0/0/0/0/0 | 0/0/0/0/0 | 1 |
| 640×648 @ 80 | 8×18 | 36 | 0/0/0/0/0 | 0/0/0/0/0 | 1 |
| 1024×1044 @ 64 | 16×36 | 29 | 0/0/0/0/0 | 0/0/0/0/0 | 1 |
| 512×209 @ 64 | 8×19 | 11 | 0/.562/.562/.562/.562 | 0/.578/.578/.578/.578 | 2 |
| 512×140 @ 64 | 8×20 | 7 | 0/0/0/0/0 | 0/0/0/0/0 | 1 |

The graded curve existed only on the defective 2.125-aspect cell. Cell-height
parity moves the response (odd 8×19 responds, even 8×18/8×20 are inert),
consistent with the disjoint-bin finding for 2×4 vs 2×5 cells in ASKI-25, and
where it responds it saturates below λ=0.25. No exact-lattice geometry probed
reaches the ≥3 bar.

**Status:** the June AC #1 PASS is retracted as an invalid run (the instrument had no
response window on any exact lattice, so its readings carry no information about λ).
ASKI-66 has now closed the dose-response question as INCONCLUSIVE. The direct test
asserts the settled inert exact-lattice behavior with no known-issue pin.
`chromaShapeAssist` stays opt-in / default 0 (the ASTSK-37 corpus gate had already
failed), so no shipped behavior depends on this verdict.

## Final addendum 2026-09-04 (ASKI-66): bounded redesign found no response window

The redesign rule was committed before measurement, then implemented as a
research-only one-shot runner. It swept 64 luma-split x chroma-scale candidates,
both competition axes, and lambda 0...1 by 0.05 on 512x522 at 64 columns (exact
8x18 cells). All 64 candidates were valid. Every one of the 2,688 axis-arm rows
had the same flipped fraction as lambda 0, so each axis had one distinct response
and no lambda-50. No candidate qualified; the frozen stop rule therefore skipped
the 640x648 and 1024x1044 holdouts and prohibited a wider search.

**Final AC #1 verdict: INCONCLUSIVE.** The competition-ramp family did not yield
a graded exact-lattice dose instrument. The cancellation theorem for the
constant-L ramps remains valid; AC #2/#3 remain historical results on their own
questions. Full rule, historical lattice audit, provenance, and CSV:
[ASKI-66 exact-lattice redesign](2026-09-04-aski66-exact-lattice-dose-redesign.md).
