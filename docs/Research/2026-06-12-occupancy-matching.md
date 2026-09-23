---
title: "ASTSK-7 Occupancy-Aware Glyph Matching - Verdict"
slug: 2026-06-12-occupancy-matching
date: 2026-06-12
status: complete
subsystem: [shape-context, color-science]
summary: "ASTSK-7's occupancy-aware matcher improved pooled composited tone but failed the frozen verdict: both structure oracles regressed hard and glyph churn was effectively total. A follow-up isoluminant-rescue diagnostic at w = 0.25 also killed the constant-L rise verdict. ASKI-68 later removed occupancyMatching and its dedicated runner; this note and Git history retain the evidence."
datasets: [docs/Research/Corpus/nasa-occupancy-v1, docs/Research/Corpus/nasa-isoluminant-v1]
runners: [AskiColorLab]
next_action: "Closed with no promotion. Do not restore occupancy matching without a new pre-registered mechanism and qualifying Aski evidence."
---

# ASTSK-7 Occupancy-Aware Glyph Matching - Verdict

## Question

The current log-polar matcher chooses candidates from a brightness-keyed pool
and then ranks by 60D shape distance. ASTSK-7 tested whether that pool should
be keyed on absolute glyph occupancy and composited tone instead.

The verdict is **KILL**. The smallest verdict arm, `w = 0.25`, clears the
pooled tone gate (`0.130797 <= 0.144854`) and improves composited-cell OKLab
delta, but it fails the frozen no-harm and churn gates by a wide margin:
SSIM-structure drops by `0.215458`, GMSD rises by `0.049058`, pooled churn is
`0.975140`, and at least one decision image regresses by more than the allowed
2% tone-relative cap. `w = 0.50` has the same failure shape. The default remains
`occupancyMatching = 0`; no promotion task is created.

## Method

Implementation through Phase 4:

- `RenderingOptions.occupancyMatching` remains default-off. The decisive sweep
  uses explicit `w` arms: `0`, `0.25`, `0.50`, `0.75`, and `1.00`; the frozen
  verdict only considers `0.25` and `0.50`.
- Baseline characterization run:

```bash
swift run AskiColorLab occupancy-match-eval \
  --output-dir /tmp/occupancy-match-baseline-2026-06-12 \
  --columns 64 \
  --corpus docs/Research/Corpus/nasa-occupancy-v1/assets \
  --corpus docs/Research/Corpus/nasa-isoluminant-v1/assets
```

- Decisive run:

```bash
swift run AskiColorLab occupancy-match-eval \
  --output-dir /tmp/occupancy-match-2026-06-12 \
  --columns 64 \
  --corpus docs/Research/Corpus/nasa-occupancy-v1/assets \
  --corpus docs/Research/Corpus/nasa-isoluminant-v1/assets \
  --decisive
```

- Result rows: 37 total = 5 synthetic structured fixtures, 24
  `nasa-occupancy-v1` assets, and 8 legacy `nasa-isoluminant-v1` assets.
- Decisive result rows: 195 total = 39 sources x 5 `w` arms. The two
  `synthetic-isoluminant` rows are the Phase 3 `IsoluminantFixture.noHarmBattery`
  addition.
- Decision rows for the ASTSK-7 promotion verdict are the five
  `nasa-occupancy-v1` decision strata: `portrait`, `texture`, `line-art`,
  `dark-scene`, and `colorful`. `diagnostic-false-color` is diagnostic only;
  the legacy `natural` rows from `nasa-isoluminant-v1` are retained as
  companion context, not as promotion rows.
- Decisive adjudication uses pooled decision-strata metrics plus the frozen
  per-image vetoes: no decision image may regress by more than 2% relative on
  `tone_mse_blurred`, and no decision image may exceed `0.5` churn.

## Baseline

Pooled baseline, `w = 0`:

| pool | rows | tone_mse_blurred | cell_oklab_delta_mean | ssim_structure_mean | gmsd_mean | pool_shape_dispersion_mean | chosen_glyph_entropy_bits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| all rows | 37 | 0.127324 | 0.199770 | 0.419314 | 0.300725 | 0.260960 | 2.232616 |
| decision rows | 20 | 0.152478 | 0.198103 | 0.422625 | 0.312083 | 0.244768 | 2.168659 |

Decision and companion strata:

| stratum | rows | tone_mse_blurred | ssim_structure_mean | gmsd_mean | pool_shape_dispersion_mean | chosen_glyph_entropy_bits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| portrait | 4 | 0.176678 | 0.172380 | 0.334250 | 0.229049 | 3.244676 |
| texture | 4 | 0.123200 | 0.242300 | 0.239557 | 0.248172 | 3.092514 |
| line-art | 4 | 0.340023 | 0.623252 | 0.474600 | 0.143002 | 0.710592 |
| dark-scene | 4 | 0.037840 | 0.631495 | 0.256051 | 0.311617 | 1.651901 |
| colorful | 4 | 0.084650 | 0.443698 | 0.255958 | 0.291998 | 2.143614 |
| natural | 6 | 0.071823 | 0.550550 | 0.219353 | 0.290543 | 2.006876 |
| diagnostic-false-color | 6 | 0.087844 | 0.135585 | 0.277614 | 0.305643 | 2.602513 |
| synthetic-structure | 5 | 0.140683 | 0.589057 | 0.380674 | 0.236608 | 2.315450 |

Line-art diagnostics:

| image | tone_mse_blurred | ssim_structure_mean | gmsd_mean | pool_shape_dispersion_mean | chosen_glyph_entropy_bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| rcs-function-diagram | 0.355021 | 0.763986 | 0.480944 | 0.142781 | 0.441388 |
| reentry-communications-diagram | 0.314850 | 0.483222 | 0.469134 | 0.143417 | 0.742424 |
| rocket-systems-diagram | 0.339927 | 0.594659 | 0.471341 | 0.143100 | 0.997223 |
| spacecraft-attitude-diagram | 0.350293 | 0.651140 | 0.476982 | 0.142710 | 0.661333 |

## Decisive Sweep

Decision strata, pooled by `w`:

| w | rows | tone_mse_blurred | cell_oklab_delta_mean | ssim_structure_mean | gmsd_mean | churn_rate | pool_shape_dispersion_mean | chosen_glyph_entropy_bits |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0.00 | 20 | 0.152478 | 0.198103 | 0.422625 | 0.312083 | 0.000000 | 0.244768 | 2.168659 |
| 0.25 | 20 | 0.130797 | 0.150985 | 0.207167 | 0.361141 | 0.975140 | 0.157485 | 0.454059 |
| 0.50 | 20 | 0.130857 | 0.150998 | 0.206973 | 0.361168 | 0.975184 | 0.156227 | 0.474998 |
| 0.75 | 20 | 0.130881 | 0.151003 | 0.206841 | 0.361181 | 0.975184 | 0.165654 | 0.493258 |
| 1.00 | 20 | 0.130920 | 0.151066 | 0.206844 | 0.360993 | 0.975205 | 0.167040 | 0.516548 |

Frozen verdict gates:

| w | pooled tone gate | max image tone regression | color rise | SSIM drop | GMSD rise | pooled churn | max image churn |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 0.25 | PASS: 0.130797 <= 0.144854 | FAIL: 3.74% at `reentry-communications-diagram` | PASS: -0.047118 | FAIL: 0.215458 | FAIL: 0.049058 | FAIL: 0.975140 | FAIL: 1.000000 at `apollo11-bootprint` |
| 0.50 | PASS: 0.130857 <= 0.144854 | FAIL: 3.75% at `reentry-communications-diagram` | PASS: -0.047105 | FAIL: 0.215653 | FAIL: 0.049085 | FAIL: 0.975184 | FAIL: 1.000000 at `apollo11-bootprint` |

Verdict: **KILL**. Both verdict arms improve pooled tone but fail both
structure oracles, fail pooled and per-image churn, and fail the per-image tone
veto. This is not INCONCLUSIVE; the structure oracles agree on harm and the
non-structure churn gate fails independently.

## Findings

- **The composited-tone thesis was partly right, but the matcher implementation
  is too blunt.** The decision-strata pooled `tone_mse_blurred` improves from
  `0.152478` to `0.130797` at `w = 0.25`, easily clearing the 5% pooled tone
  gate. `cell_oklab_delta_mean` also improves from `0.198103` to `0.150985`.
- **The structure cost is decisive.** At `w = 0.25`, SSIM-structure drops from
  `0.422625` to `0.207167`, and GMSD rises from `0.312083` to `0.361141`.
  Both no-harm oracles agree on harm by much more than the `0.005` tolerance.
- **Churn is not marginal; it is essentially total.** Pooled churn is
  `0.975140` at `w = 0.25`, with image-level churn reaching `1.000000`. This
  independently kills the candidate even before structure is considered.
- **The target line-art stratum got worse on tone.** Line-art `tone_mse_blurred`
  rises from `0.340023` to `0.347016` at `w = 0.25`, while chosen-glyph entropy
  collapses from `0.710592` to `0.011203`. The knob does not solve the
  line-detail diversity cap that motivated ASTSK-7.
- **Default stays off.** `occupancyMatching = 0` remains the default, and no
  promotion task is filed. The Phase 5 isoluminant-rescue rerun will
  use `w = 0.25` only as a diagnostic comparison arm.

## Phase 5 Isoluminant-Rescue Diagnostic

Phase 5 threaded `--occupancy-w` through every `isoluminant-rescue` converter
site: synthetic sweep arms, no-harm guard baseline and candidate, and optional
real-image corpus review. The default omission remains `w = 0`.

Verification and diagnostic commands:

```bash
swift test --filter AskiColorLabIsoluminantRescueTests
swift run AskiColorLab isoluminant-rescue --output-dir /tmp/aski-isoluminant-w0-astsk7 --columns 64
swift run AskiColorLab isoluminant-rescue --output-dir /tmp/aski-isoluminant-w025-astsk7 --columns 64 --occupancy-w 0.25
```

The `w = 0` run preserved the committed June 10 result on the legacy surface:
projecting the current nine-fixture CSV down to `redGreen`, `blueYellow`,
`lumaControl`, and the old columns produced a 27,841-line file byte-identical
to the 2026-06-10 isoluminant-rescue run's `isoluminant_rescue.csv`.
The current expanded run has 83,521 rows because it also includes probe and
competition fixtures plus `fixture_kind`.

At `w = 0.25`, the AC #2 rise verdict is **KILL**:

| fixture | w = 0 entropy by λ | w = 0.25 entropy by λ | readout |
| --- | --- | --- | --- |
| redGreen | 0.000 / 0.722 / 0.722 / 0.722 / 0.722 | 0.000 / 0.000 / 0.000 / 0.000 / 0.000 | occupancy flattens the red/green edge; all band glyphs are `.` |
| blueYellow | 0.000 / 0.722 / 0.722 / 0.722 / 0.722 | 0.000 / 0.722 / 0.722 / 0.722 / 0.722 | rise survives, with different glyph choices |
| lumaControl | 1.522 / 1.522 / 1.522 / 1.522 / 1.522 | 1.522 / 1.522 / 1.522 / 1.522 / 1.522 | invariant |

The luma-vs-chroma competition ramps do show more structural diversity under
`w = 0.25`: distinct flipped fractions rise from `3` to `4` on both ramps, and
override `λ50` moves earlier (`redGreenCompetition`: `1.00 -> 0.50`;
`blueYellowCompetition`: `0.75 -> 0.50`). That is not enough to rescue the
thesis. Occupancy-aware pool keying can widen diversity in the competition
instrument, but on the literal constant-L verdict fixtures it is asymmetric and
can collapse red/green to a single glyph. No-harm still passes, but the rise
verdict fails, so this diagnostic refutes "tone-keyed pool widens structural
diversity at L≈0.4" as a general fix.

## Pre-Registered Verdict Predicates

Copied from the ASTSK-7 occupancy-matching design spec; frozen after this
Phase 2 checkpoint.

Decision strata exclude `diagnostic-false-color`. For each verdict `w > 0`,
compare against baseline `w = 0`.

Tone gate:

- Pooled `tone_mse_blurred(w) <= 0.95 * baseline`.
- No decision image regresses by more than 2% relative.

Structure no-harm gate:

- SSIM-structure drop is `<= 0.005`.
- GMSD rise is `<= 0.005`.
- The no-harm verdict requires both oracles to agree.

Composited-cell color gate:

- `cell_oklab_delta_mean` rise is `<= 0.005`.

Churn gate:

- Pooled churn is `<= 0.35`.
- Per-image churn is `<= 0.5`.

Verdict precedence is exhaustive and evaluated in order:

- **PASS at `w*`**: the smallest verdict `w > 0` satisfying all four gates.
- **INCONCLUSIVE**: no `w` passes all four gates, and at least one `w` passes
  tone, color, and churn while exactly one structure oracle fails.
- **KILL**: everything else, including no tone-passing `w`, both structure
  oracles agreeing on harm for every tone-passing `w`, or failure of the color
  or churn gates.

Failures on churn or composited-cell delta are KILL, not INCONCLUSIVE. The
instrument worked; the glyph-side thesis lost.

## Phase 2 Checkpoint Record

Historical checkpoint approved 2026-06-12 before implementing
`occupancyMatching`.

User review confirmed both checkpoint questions. The predicates above are now
frozen.

- **Headroom:** the decision-strata pooled baseline (0.152478) sits far from
  the instrument floor (strata span 0.0378–0.3400); the tone gate needs only a
  −0.0076 pooled movement, and line-art alone (about 45% of pooled error from
  20% of decision rows) can carry it.
- **Pool diagnostic:** the line-art rows reproduce the structural-homogeneity
  signature (dispersion 0.1427–0.1434 across all four diagrams, entropy
  0.44–1.00 bits, highest tone error alongside the best SSIM-structure).
  Recorded as a real-image **proxy**: the literal L≈0.4 isoluminant fixture
  battery was not part of this run, and line-art glyph entropy is partly
  confounded by whitespace dominance.

Scope adjustments adopted at review (carried in the execution plan):

1. The `IsoluminantFixture.noHarmBattery` synthetic arm — planned for Phase 1
   but never landed — folds into Phase 3, so the literal L≈0.4 single-glyph
   pool is reproduced at w = 0 and graded across the sweep.
2. `natural` joins `OccupancyCorpus.Stratum` as a companion (non-decision)
   stratum so the Phase 4 `--decisive` run can include nasa-isoluminant-v1
   without failing strict metadata validation.

`carina-cosmic-cliffs` and `san-francisco-night` exist in both corpora, so each
contributes two CSV rows with identical metrics. The isoluminant copies land in
companion strata and never enter decision pooling, but carina is double-weighted
in the diagnostic-false-color stratum mean.
