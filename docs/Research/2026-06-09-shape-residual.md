---
title: "Glyph Shape-Residual Field: does the discarded 60D match distance predict perceptual structure?"
slug: 2026-06-09-shape-residual
date: 2026-06-09
status: complete
subsystem: [shape-context]
summary: "Thread B surfaces the 60D log-polar shape distance the matcher computes and discards (additive, hot path byte-identical) and asks whether it rank-correlates with an independent pixel-level structure oracle. ASTSK-27 left it INCONCLUSIVE — two structure oracles (GMSD, SSIM-structure) disagreed sharply on oriented/curved content and no full-reference IQA metric is validated for the binary-glyph-vs-tone ~24px regime. ASTSK-31 built the missing instrument authority — a third, better-validated oracle (HaarPSI), a training-free median-of-ranks consensus, a real-content battery (3 NASA photos + a procedural glyph sheet), and a pre-registered two-axis PASS/KILL rule frozen BEFORE the decisive run — then re-settled the verdict at native 2048px over a 5-column sweep {44,52,64,72,80}. Verdict: GENERAL axis INCONCLUSIVE (pooled consensus ρ is stable and positive in both the synthetic and natural pools, +0.22…+0.32 — so not a KILL — but diagonal and radial each carry ≥2 oracles ≤ −0.30, so not a PASS; HaarPSI sides decisively with GMSD's negative read, confirming the log-polar orientation/curvature degeneracy). LINE-ART axis KILL: the residual is textbook-strong on SPARSE stroke marks (strokes consensus +0.86…+0.89, all oracles ≥ +0.50 at every column) but ANTI-correlates with structure fidelity on DENSE rendered text (glyphSheet consensus −0.55…−0.75 at every column) — the ASTSK-27 'line-art robust' claim was over-broad. The log-polar basis degeneracy is confirmed AND shown fixable: the lab basis-augmentation prototype at w=0.25 flips radial/diagonal from strongly negative to positive/near-zero without regressing strokes → split off as ASTSK-35."
related_specs: [docs/research-plan.md]
datasets: [docs/Research/Corpus/nasa-structure-v1]
runners: [AskiColorLab]
next_action: "Thread B and its production follow-up are settled negative results. ASKI-68 removed shapeStructureAssist and its production branches; the raw residual map remains a lab instrument. Do not restore an augmented-basis production path without a new, independently pre-registered mechanism and qualifying Aski evidence."
---

# Glyph Shape-Residual Field: does the discarded 60D match distance predict perceptual structure?

## Question

Aski's matcher computes a 60D log-polar shape distance for every glyph candidate,
picks the nearest, and **throws the distance away**. That distance is a free,
per-cell signal of *how well the chosen glyph fits the cell's structure*. Thread B
(ASTSK-27) asks one falsifiable question:

> Does the surfaced residual rank-correlate with an **independent** pixel-level
> measure of structural fidelity? If it does not, the residual is not a usable
> structure signal and this is a negative result.

The test is a Spearman rank correlation between the per-cell residual (higher =
worse fit) and an independent structure oracle (transformed so higher = worse), over
a battery of fixtures. A valid residual yields a **positive** ρ.

## Method

The plumbing is **purely additive** — every production `score`/`match`/`findBest`
path is left byte-identical (CI- and benchmark-relevant), so there is no perf
regression. `convertWithResidual` mirrors `convert` exactly and additionally
returns a row-major residual field; the `shape-residual-map` subcommand consumes it.

Per cell, the lab scores the **chosen glyph** against the **source cell** with
independent pixel-only oracles (rasterized glyph vs resampled source block; the
oracles never see the residual), then Spearman-correlates each against the residual.
ASTSK-27 used three oracles; **ASTSK-31 added a fourth and a consensus** (see below):

- **GMSD** — gradient-magnitude similarity deviation (Prewitt gradients, std-dev
  pooling), the gradient/edge metric that tops SROCC on LIVE/CSIQ/TID
  ([Xue et al. 2013, arXiv:1308.3052](https://arxiv.org/abs/1308.3052)).
- **SSIM structure term** — `(σ_xy+C3)/(σ_xσ_y+C3)`, the covariance-only component;
  luminance-insensitive and, by construction, exactly `1.0` on a flat source block
  (σ=0) so flat cells contribute no spurious signal (unit-tested).
- **HaarPSI** (ASTSK-31) — Haar wavelet-based perceptual similarity
  ([Reisenhofer et al. 2018, arXiv:1607.06140](https://arxiv.org/abs/1607.06140);
  MIT reference port from [rgcda/haarpsi](https://github.com/rgcda/haarpsi)). FSIM-lineage
  but with only two tunable constants and higher SROCC than FSIM/SSIM/VSI on the
  standard databases; chosen as the **arbiter** for the GMSD-vs-SSIM-structure split.
- **full SSIM** — retained as a contrast oracle; luminance-confounded for a binary
  glyph vs a continuous-tone source.
- **Consensus** (ASTSK-31) — per-cell **median of the three structure-oracle ranks**
  (`gmsd`, `1−ssim_structure`, `1−haarpsi`), a training-free rank-aggregation rule
  (ranks computed within the population being correlated). This is the gated quantity
  for the general axis.

All oracles are computed at a **fixed 24×24 footprint** (glyph rasterized 24×24, source
block resampled 24×24), decoupled from `columns`.

The ASTSK-31 battery has **9 fixtures across three pools**: **synthetic** (`checker`,
`diagonal`, `radial`, `strokes`, `mixedFrequency`), **natural** (`earth-limb-sunrise`,
`vavilov-crater`, `phoenix-night-grid` — 3 NASA public-domain photos at native 2048px,
`docs/Research/Corpus/nasa-structure-v1`), and a **line-art** axis (`glyphSheet`, a
procedural Courier sheet, plus `strokes`). Every cell is scored at **native resolution**
(each source block ≥ 24px, machine-enforced — see below) across a **column sweep**
`{44, 52, 64, 72, 80}`.

### The ASTSK-27 instrument problem (why this was re-opened)

Two instrument bugs had to be fixed before the question could be answered honestly:

1. **Pixel mis-alignment (PR #31).** With the default `oversample`, the matcher
   thumbnailed the fixture before computing the residual, while the oracle read native
   blocks — so ImageIO resampling loss masqueraded as glyph residual. The fix raises
   `oversample` so residual and oracle read the **same** pixels.
2. **Sub-cell upsampling.** On the 256px fixtures, at canonical columns each cell is
   only ~3 native px; the 24×24 oracle then compares a detailed glyph raster against a
   tiny block **upsampled** to 24×24, so the correlation is dominated by grid-phase
   aliasing, not structure. The cure is `--fixture-size`, rendering the battery
   self-similarly at large native sizes so each block reaches **≥ 24px native** — no
   upsampling into the oracle. ASTSK-31 makes this a **machine-enforced guard**
   (`oracleBlockWouldUpsample`): a bare `--columns 80` run against the 256px default
   now exits nonzero; an explicitly `--allow-upsampled-oracle-blocks` run is stamped
   *exploratory* and cannot feed the verdict.

With those fixed, ASTSK-27 found the residual is a strong, oracle-robust signal on
glyph-scale `strokes` (+0.7…+0.9 on both oracles at every native column), ≤0 on the
low-structure `mixedFrequency`, and **sharply oracle-dependent on oriented/curved
content** (`diagonal`/`radial`: GMSD strongly negative, SSIM-structure near-zero). With
two "independent" structure oracles disagreeing that much, and **no full-reference
metric validated for the binary-glyph-vs-tone ~24px regime**
([Ding et al. 2020](https://arxiv.org/pdf/2005.01338)), neither a PASS nor a KILL was
honest. That INCONCLUSIVE — *the oracle, not the residual, was the thing under test* —
is what ASTSK-31 set out to settle with a better-matched instrument and a rule fixed in
advance.

## Pre-registered verdict rule (ASTSK-31, frozen before the decisive run)

This rule is frozen verbatim from the approved design addendum
(the 2026-06-09 shape-residual regime-oracle design addendum)
and committed **before** the decisive ASTSK-31 sweep is run — the same sequencing
discipline by which ASTSK-27's retraction was earned. The re-settled verdict below
applies this rule **mechanically** from `spearman_summary.csv`, with no post-hoc
threshold changes.

Validity precondition: native resolution only — every source block ≥ `oracleCellSize` px native, machine-enforced by the new oracle-native guard (Scope §5); a run with `--allow-upsampled-oracle-blocks` is exploratory by definition and cannot feed this rule.

Two pools are gated, each pooled separately: **synthetic** (the 5 `StructuredFixture` members) and **natural** (the 3 NASA fixtures only — `glyphSheet` is deliberate best-case content and is excluded from the natural pool; it counts toward the line-art axis instead).

The verdict has **two independent axes** — the AC's "PASS-in-a-validated-regime" disposition. A KILL on the general axis does not invalidate the line-art axis, and vice versa; the note reports both.

**General-signal axis:**
- **PASS:** pooled ρ(residual, consensus) ≥ **+0.20** at every column in `{44, 52, 64, 72, 80}` in BOTH pools, AND ≥2 of 3 per-oracle pooled ρ > 0 at every column in both pools, AND no fixture has ≥2 oracles ≤ **−0.30** at the canonical column (80).
- **KILL:** pooled consensus ρ ≤ 0 at any column in either pool, or the pooled consensus sign flips across the sweep within either pool.
- **Otherwise INCONCLUSIVE**, with the blocker named in the note (the 0 < ρ < +0.20 band is deliberately inconclusive — no knife-edge verdicts).

**Line-art-regime axis** (`strokes` + `glyphSheet`, per-fixture):
- **PASS:** EACH of the two fixtures has per-fixture ρ ≥ **+0.50** on all three structure oracles at every column.
- **KILL:** either fixture has per-fixture consensus ρ ≤ 0 at any column.
- **Otherwise INCONCLUSIVE.**

Descriptive (non-gating) readouts pre-committed alongside: which incumbent oracle HaarPSI sides with on `diagonal`/`radial`; whether the disagreement reproduces on natural content; the AC#4 lift table — a pre-registered augmentation mix `w ∈ {0.25, 0.5, 0.75}` shows **lift** iff it raises per-fixture ρ(augmented, consensus) on BOTH `radial` and `diagonal` by ≥ **+0.20** without dropping `strokes` by > **0.05** (measured at the canonical run; if any mix fires, the production-basis change is split off to a new tracked task with the evidence attached, and `Sources/Aski` stays untouched here regardless).

## Re-settled verdict (ASTSK-31, decisive run 2026-06-13)

Decisive run: `--fixture-size 2048 --columns 44 --columns 52 --columns 64 --columns 72
--columns 80 --battery all`, at git `b0b2a11`, logPolar, `monochrome`, `.sRGB`. All 9
fixtures native at every column (the tightest, col 80, is `floor(2048/80)=25 ≥ 24` px).
Every number below is read mechanically from
the run's `spearman_summary.csv`.

**General-signal axis → INCONCLUSIVE.** Pooled consensus ρ is positive, stable, and
≥ +0.20 across the whole sweep in BOTH gated pools, so it is **not a KILL** and clears
two of the three PASS bars (magnitude and breadth). It fails the third — *no fixture
with ≥2 oracles ≤ −0.30 at col 80* — on exactly the two pure-synthetic degenerate
fixtures (`diagonal`, `radial`). So the signal is real but regime-limited, not a PASS.

| pooled ρ(residual, consensus) | C=44 | C=52 | C=64 | C=72 | C=80 |
| --- | ---: | ---: | ---: | ---: | ---: |
| **synthetic** | +0.222 | +0.227 | +0.240 | +0.226 | +0.268 |
| **natural** | +0.312 | +0.291 | +0.286 | +0.320 | +0.324 |

Per-oracle pooled ρ at the canonical column (every one positive — 3/3 > 0, exceeding
the ≥2/3 bar; this holds at every column in both pools):

| pool (C=80) | 1−ssim_struct | gmsd | 1−haarpsi | consensus |
| --- | ---: | ---: | ---: | ---: |
| synthetic | +0.388 | +0.276 | +0.253 | +0.268 |
| natural | +0.517 | +0.253 | +0.278 | +0.324 |

Per-fixture ρ at the canonical column (the failing PASS conjunct is the diagonal/radial
`≥2 oracles ≤ −0.30`, **bold**):

| fixture | pool | 1−ssim_struct | gmsd | 1−haarpsi | consensus | read |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `checker` | synthetic | +0.398 | +0.633 | +0.648 | +0.632 | all + |
| `diagonal` | synthetic | +0.065 | **−0.628** | **−0.487** | −0.571 | 2 oracles ≤ −0.30 → blocks PASS |
| `radial` | synthetic | +0.083 | **−0.632** | **−0.544** | −0.608 | 2 oracles ≤ −0.30 → blocks PASS |
| `strokes` | synthetic | +0.703 | +0.860 | +0.759 | +0.858 | line-art, robust ✓ |
| `mixedFrequency` | synthetic | −0.150 | −0.246 | −0.385 | −0.220 | low-structure; only 1 oracle ≤ −0.30 |
| `glyphSheet` | line-art | +0.724 | **−0.603** | **−0.587** | −0.551 | KILLs the line-art axis (below) |
| `earth-limb-sunrise` | natural | +0.681 | +0.572 | +0.543 | +0.568 | all + |
| `vavilov-crater` | natural | +0.451 | +0.219 | +0.325 | +0.430 | all + |
| `phoenix-night-grid` | natural | +0.219 | +0.004 | +0.064 | +0.137 | oriented grid: gmsd/haarpsi ~0 (mild echo) |

**Line-art-regime axis → KILL.** The gated pair is `strokes` + `glyphSheet`. `strokes`
is a textbook PASS — ρ ≥ +0.50 on all three oracles at every column (consensus
+0.86…+0.89). But `glyphSheet` has per-fixture **consensus ρ ≤ 0 at every column**
(−0.55…−0.75), which fires the KILL. The residual *anti-correlates* with gradient-based
structure fidelity on dense rendered text.

| C | strokes consensus | strokes gmsd | strokes haarpsi | glyphSheet consensus | glyphSheet gmsd | glyphSheet haarpsi |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 44 | +0.882 | +0.884 | +0.852 | **−0.755** | −0.781 | −0.755 |
| 52 | +0.870 | +0.885 | +0.854 | **−0.703** | −0.732 | −0.713 |
| 64 | +0.893 | +0.891 | +0.883 | **−0.691** | −0.775 | −0.686 |
| 72 | +0.889 | +0.885 | +0.888 | **−0.669** | −0.717 | −0.694 |
| 80 | +0.858 | +0.860 | +0.759 | **−0.551** | −0.603 | −0.587 |

The honest read: "line-art robust" is the wrong regime label. The robustness is a
property of **sparse glyph-scale stroke marks**, not of glyph content broadly — dense
text triggers the same oriented-structure degeneracy as the synthetic `diagonal`.
(`glyphSheet`'s SSIM-structure is strongly positive, +0.72…+0.82, but the two
gradient-based oracles dominate the consensus.)

### Descriptive readouts (pre-committed, non-gating)

1. **HaarPSI arbiter call.** On the contested `diagonal`/`radial` fixtures, HaarPSI is
   strongly negative (−0.487 / −0.544 at col 80), siding with **GMSD** (−0.628 / −0.632),
   **not** with SSIM-structure (+0.065 / +0.083). The better-validated arbiter resolves
   the ASTSK-27 tie toward the gradient/negative reading: by a 2-of-3 majority the
   residual anti-correlates with structural fidelity on single-orientation and concentric
   content. The same pattern holds on `glyphSheet`. This is the new authority ASTSK-31
   added — and it **confirms the basis-degeneracy theory rather than rescuing the
   residual**.
2. **Natural-content reproduction.** The sharp synthetic disagreement does **not**
   reproduce on real content. All three NASA naturals are positive on every oracle
   (earth-limb +0.54…+0.68; vavilov +0.22…+0.45). The lone mild echo is
   `phoenix-night-grid` (an oriented street grid): gmsd/haarpsi sit near zero
   (+0.004 / +0.064), not strongly negative. Notably the synthetic `radial` degeneracy
   does **not** survive on real concentric texture (a crater field is not pure rings).
   Pooled natural consensus stays +0.29…+0.32. The degeneracy is a worst-case property
   of *pure* synthetic single-orientation / concentric fixtures, strongly attenuated on
   real mixed content.
3. **AC#4 lift table.** Per-fixture ρ(augmented, consensus) at the canonical column,
   lift = augmented − baseline; criterion = both `radial` and `diagonal` ≥ +0.20 with
   `strokes` not dropping by > 0.05:

   | fixture | baseline | w=0.25 (lift) | w=0.5 (lift) | w=0.75 (lift) |
   | --- | ---: | ---: | ---: | ---: |
   | `radial` | −0.608 | +0.234 (**+0.842**) | −0.421 (+0.187) | −0.554 (+0.054) |
   | `diagonal` | −0.571 | −0.177 (**+0.394**) | −0.405 (+0.166) | −0.538 (+0.033) |
   | `strokes` | +0.858 | +0.968 (+0.110) | +0.971 (+0.113) | +0.970 (+0.112) |

   **w=0.25 fires the lift criterion** (radial +0.842 and diagonal +0.394 both ≥ +0.20;
   strokes rises, no drop). w=0.5 and w=0.75 do not clear the radial threshold. Per the
   pre-registered rule this splits off the production-basis change → **ASTSK-35**, with
   this evidence attached. `Sources/Aski` stays untouched in ASTSK-31.

### Instrument caveat (HaarPSI footprint)

After HaarPSI's reference preprocessing (2×2 mean filter + dyadic subsample), the 24×24
oracle inputs become a 12×12 field — the small end of HaarPSI's validated regime, with a
coarse scale-3 weight map. We keep the reference defaults anyway (re-tuning is the
unvalidated-knob trap ASTSK-27 escaped) and lean on bit-level test-vector parity with the
reference for trust. HaarPSI is therefore reported as a **corroborating arbiter**, not a
sole authority — but it agrees with GMSD on the contested fixtures, which is what the
consensus needed.

## Interpretation and forward theories

- **The instrument is now trustworthy enough to settle the question — and it does, in two
  directions.** ASTSK-31's contribution was authority: a third oracle with different
  failure modes (HaarPSI), a training-free consensus, a real-content battery, and a rule
  fixed before the run. The general axis stays INCONCLUSIVE, but for a *sharper, named*
  reason than ASTSK-27's "two oracles disagree": the pooled signal clears the magnitude
  and breadth bars in both pools, and the only thing standing between it and a PASS is the
  per-fixture degeneracy on two pure-synthetic fixtures — now corroborated by a 2-of-3
  oracle majority rather than resting on GMSD alone.
- **`radial`/`diagonal` are the log-polar basis exposing itself — confirmed.** A log-polar
  descriptor bins energy by orientation; rotationally-symmetric (radial) and
  single-orientation (diagonal) structure are exactly where it is near-degenerate
  ([Shape context](https://en.wikipedia.org/wiki/Shape_context)). HaarPSI siding with GMSD
  removes the ambiguity ASTSK-27 had to leave open.
- **The degeneracy is fixable — demonstrated, not just theorized.** The lab
  basis-augmentation prototype (orientation-energy + radial-frequency channels) at w=0.25
  flips `radial`/`diagonal` from strongly negative to positive/near-zero while *improving*
  `strokes`. That is the AC#4 lift firing, and it makes the production basis change
  (ASTSK-35) an evidence-backed next step rather than a speculative one.
- **Prior art holds.** Treating a matcher's discarded distance as a per-cell confidence is
  the stereo / dense-matching **cost-volume confidence** idea
  ([Poggi et al. 2021](https://arxiv.org/pdf/2101.00431)) ported from disparity to
  glyph-shape — encouraging for the sparse-stroke case, where it is strong and
  oracle-robust.

## Caveats

- **"Line-art" was the wrong generalization.** The residual's robustness is specific to
  sparse glyph-scale stroke marks. Dense rendered text (`glyphSheet`) anti-correlates with
  gradient-structure fidelity — the line-art axis is a KILL, not a PASS, and the ASTSK-27
  blanket line-art claim is narrowed accordingly.
- **HaarPSI at a 12×12 effective field** is at the edge of its validated regime (above);
  it is a corroborating arbiter, not a sole authority.
- **`oracleCellSize=24` is fixed.** Holding it fixed keeps the decisive runs comparable;
  tying the oracle footprint to native px is a deferred robustness follow-up.
- **logPolar only.** edgeMap's `scoreScored` returns a template-fit distance (different
  semantics) and dotMatrix returns `nan`; the residual map is logPolar, where the distance
  is a true per-glyph shape fit.

## Next action

Thread B is settled. The defensible production use of the **raw** residual is narrow: a
per-cell confidence signal for **sparse glyph-scale stroke content only** — it
anti-correlates with structural fidelity on dense/oriented/curved content, so it must not
be used as a general structure-confidence signal. The forward path is **ASTSK-35**
(production basis augmentation: port the orientation-energy + radial-frequency channels
the prototype validated, which lift `radial`/`diagonal` without regressing `strokes`);
once it lands, prefer the augmented basis over the raw residual even for line-art. The
**general** per-cell structure-confidence claim stays INCONCLUSIVE until that augmented
basis is validated in production.
