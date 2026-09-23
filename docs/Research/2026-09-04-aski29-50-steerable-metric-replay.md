---
title: "ASKI-29/50 - Exact-lattice steerable metric replay rule"
slug: 2026-09-04-aski29-50-steerable-metric-replay
date: 2026-09-04
status: complete
subsystem: [shape-context, frontier]
summary: "COMPLETE. The pre-registered current-path ASTSK-42-style replay scored 51840 cells from six oriented fixtures and three nasa-steerable-v1 images at columns 80. The exact shipping arm resolved to 2 by 4 cells with 3 of 60 bins; the separate exact historical-support comparator resolved to 38 by 85 with 48 of 60. The archived KILL held independently under all five losses: MAE, GMSD, 1 minus HaarPSI, contrast-weighted SSIM, and pinned official MILO. The shipping aggregate deltas were minus 0.1783, minus 0.3805, minus 0.1116, minus 0.1709, and minus 1.2606 percent respectively. No Sources, package dependency, or default changed."
related_specs: [docs/Research/2026-06-27-astsk42-steerable-channel.md, docs/Research/2026-08-19-sampling-lattice-support-collapse.md, docs/Research/2026-08-19-house-oracle-audit.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1]
runners: [AskiColorLab]
---

# ASKI-29/50 — exact-lattice steerable metric replay rule

This file is the rule of record before measurement. The task records establish
that the June cell-pair artifacts do not survive, so this is a current-path
regeneration. It does not alter the historical ASTSK-42 KILL.

## 1. Question and boundary

Run one controlled replay of the ASTSK-42 baseline versus
`steerableShapeAssist = 0.5`. Ask two separate questions:

1. Does the KILL hold when the matcher runs at the shipping 2-to-3-of-60-bin
   support regime?
2. Does it hold in a current exact-lattice replay of the historical
   48-of-60-bin support regime, and do MILO and contrast-weighted SSIM agree
   with the established oracle panel?

This is lab-only instrument evidence. It cannot promote a matcher, add a
shipping dependency, change a default, or edit `Sources/`.

## 2. Revalidated metric definitions

- **MILO:** use raw error from the authors' official implementation at commit
  `4f5b6fc641cae1a8aeaa8c4f04296dcad388b867`, not the learned MOS remap.
  The model predicts a multiscale visibility mask and pools masked absolute RGB
  error; lower is better. The published metric is peer-reviewed in ACM TOG and
  the [official project page](https://milo.mpi-inf.mpg.de/) links the
  [Apache-2.0 implementation and weights](https://github.com/ugurcogalan06/MILO/tree/4f5b6fc641cae1a8aeaa8c4f04296dcad388b867).
  The replay repeats grayscale luma into RGB and evaluates each 24x24 cell pair.
  This small-cell use is outside the paper's full-image benchmark setting, so
  MILO is a comparator, never the sole verdict oracle.
- **Contrast-weighted SSIM (CSSIM):** implement equation 27 from Jiang et al.
  with the source cell as the continuous-tone reference: an 11x11 Gaussian
  window with sigma 1.5 computes the local SSIM map and reference contrast;
  `sigma = 2 * localStandardDeviation` and
  `CSSIM = sigma * SSIM + (1 - sigma)`. Average the valid-window map and report
  `1 - CSSIM` as a lower-is-better loss. The definition is from the
  [peer-reviewed IEEE TIP paper](https://doi.org/10.1109/TIP.2023.3318937),
  whose [author manuscript](https://arxiv.org/abs/2304.12152) specifically
  targets binary halftones.
- **Established panel:** MAE is the house loss. GMSD and `1 - HaarPSI` remain
  comparator losses. All metrics receive the same glyph/source 24x24 luma pair;
  none can read descriptor vectors or matcher scores.

## 3. Frozen corpus, arms, and regimes

- Battery: deterministic `spokes`, `diagonals` at 15/30/60/75 degrees, `arcs`,
  and all three committed images in `nasa-steerable-v1`.
- Columns: `{80}`. Synthetic side: 3072. Character set: the existing
  Courier-rasterized standard 95-glyph set. Treatment: `Kr = 0.5`.
- Oracle footprint: 24x24. Score every cell; no sampling or dropped row is
  allowed.
- **Shipping-support arm:** converter `oversample = 2`. The expected square
  footprint is 2x4 with 3/60 reachable bins.
- **Historical-support arm:** use the existing no-downscale oversample resolver.
  The expected square footprint is 38x85 with 48/60 reachable bins.

For every fixture and regime, the runner must record native dimensions, grid,
cell footprint, reachable-bin count, and sampling-raster dimensions. It must
fail unless `samplingWidth == columns * cellWidth`,
`samplingHeight == rows * cellHeight`, and both dropped counts are zero. A
support expectation failure invalidates the run; it does not silently relabel
an arm.

The oracle source block is obtained through `SampledSource`, which follows the
converter's current sampling geometry back to the native source. It is then
resampled once to the 24x24 scoring footprint. The base and treatment use the
same source block and candidate raster convention.

## 4. Frozen gate and agreement rule

For each metric, sub-battery, and regime, pool cell losses before taking the
delta:

`delta = (baseLoss - treatmentLoss) / baseLoss`.

Apply the original ASTSK-42 gate independently to each metric:

- aggregate delta must be at least +3.0%;
- no oriented sub-battery may be below -0.5%;
- naturals may not be below -0.5%.

A metric-level KILL is reported as **HELD** relative to the archived KILL. A
metric-level PASS is reported as **FLIPPED**. MAE is the house-oracle verdict.
The other four metrics can only reduce confidence:

- all five HELD: panel result **HELD**;
- all five FLIPPED: panel result **FLIPPED**;
- any split: invoke the ASKI-27 agreement rule and report **INCONCLUSIVE**.

No metric can adjudicate a split. The shipping-support and historical-support
panels are decided separately. Historical numbers remain historical; the note
will show the June GMSD values beside the new rows and state plainly that no
June HaarPSI, MAE, CSSIM, or MILO artifacts exist.

## 5. Column-parity census

For ASKI-29 AC3, independently census a square 3072px fixture at shipping
oversample 2 for every integer column count 4 through 80. Record the resolved
cell footprint and reachable coordinates. Characterize each transition between
even-height and odd-height support, and state whether any transition survives
at 16 columns or above. This structural census does not reuse image-quality
numbers and cannot change the replay gate.

## 6. Artifacts and falsifiers

The Swift export writes the non-MILO metric rows, exact-regime rows, parity
rows, and a temporary binary stream of MILO pairs. A pinned Python bridge runs
the official model and writes only aggregate MILO rows. Finalization validates
the complete matrix, applies Section 4 mechanically, and writes a summary plus
the standard result manifest. The large temporary MILO stream is not committed.

Missing corpus members, non-exact geometry, the wrong reachable-bin count, a
non-finite loss, a partial MILO matrix, or a metric with zero base loss makes
the run **INVALID**. There is one execution and no threshold, corpus, column,
Kr, footprint, or pooling revision after results are read.

## 7. Execution and exact lattice

The rule above was committed as `bcc67b2` before the runner existed. The
reviewed runner and its tests were then committed as `7f2f73c`, and the replay
ran once from that clean commit. It emitted **51,840** cell records: 2 regimes
times 9 fixtures times 2,880 cells. The durable result store is
[`Results/2026-09-04-aski29-50-steerable-metric-replay/`](Results/2026-09-04-aski29-50-steerable-metric-replay/).

| regime | oversample | grid | footprint | admitted pixels | reachable bins | sampled raster | dropped |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| shipping current path | 2 | 80x36 | 2x4 | 3/8 | 3/60 | 160x144 | 0x0 |
| historical-support comparator | 39 | 80x36 | 38x85 | 1,130/3,230 | 48/60 | 3,040x3,060 | 0x0 |

These are separate comparisons. The second row reproduces the June run's
descriptor-support class, but it does not reconstruct the June truncating
lattice and is not a replacement for its five-column historical record.

The MILO bridge verified the authors' runner and weights before scoring:

- implementation commit: `4f5b6fc641cae1a8aeaa8c4f04296dcad388b867`;
- `MILO_runner.py` SHA-256:
  `9e7185f2b4dc1c856b9907c5b08b85300da1f1b9b47c26b99ec779d7c416870a`;
- `MILO.pth` SHA-256:
  `a1d66a7e0ebe0f839564ad70160ffdec709708f0b9a7dd03b19c0bee90d31f79`;
- PyTorch 2.14.0 on MPS, batch 512, with the official masked absolute-error
  expression reduced per cell before sub-battery pooling.

## 8. Result - the archived KILL holds

Positive is better. The frozen +3.0% aggregate and -0.5% collateral clauses
were applied without revision.

| regime | metric | aggregate | spokes | diagonals | arcs | naturals | result |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| shipping | MAE | -0.1783% | -3.1689% | -0.0415% | +0.1356% | -0.4315% | HELD |
| shipping | GMSD | -0.3805% | -3.1267% | -0.0561% | +0.1754% | -0.9622% | HELD |
| shipping | 1-HaarPSI | -0.1116% | -0.3904% | -0.0074% | -0.2024% | -0.2342% | HELD |
| shipping | CSSIM loss | -0.1709% | +0.1491% | -0.2875% | +0.2748% | +0.0530% | HELD |
| shipping | MILO | -1.2606% | -30.9752% | +3.2490% | +23.5317% | -21.5779% | HELD |
| historical support | MAE | -0.0154% | -0.1517% | +0.0000% | +0.0065% | -0.0543% | HELD |
| historical support | GMSD | -0.2524% | -0.2606% | +0.0000% | -0.0019% | -1.0685% | HELD |
| historical support | 1-HaarPSI | +0.0195% | -0.1102% | +0.0000% | -0.0003% | +0.0912% | HELD |
| historical support | CSSIM loss | -0.0044% | -0.4773% | +0.0000% | +0.0123% | -0.0318% | HELD |
| historical support | MILO | +3.0050% | -2.0511% | +0.0000% | +0.0468% | +7.6310% | HELD |

All five metrics return **HELD** in both regimes. The ASKI-27 disagreement
protocol does not fire because there is no split. MILO's large sub-battery
swings reinforce its stated small-cell limitation; they do not alter the
result because its aggregate and collateral clauses still fail.

The only surviving June rows are GMSD: spokes +0.32%, diagonals +0.0015%, arcs
+0.0022%, naturals -0.92%, aggregate -0.19%, hence KILL. No June MAE, HaarPSI,
CSSIM, MILO, or cell-pair artifact survives. Those values are unavailable, not
zero, and this current-path replay does not fabricate or overwrite them.

## 9. Current shipping parity census

On a 3,072-square exact lattice at shipping oversample 2, cell-height parity
changes when the requested columns become **5, 6, 8, 9, 10, 12, 13, 14, 15,
and 16**. There is no further transition from 17 through 80. Thus one
transition survives at 16, but none survives above 16; the frozen C80 replay is
on the stable 2x4, 3/60-bin side. `parity.csv` records every footprint,
admitted coordinate, bin index, and zero-drop assertion for all 77 counts.

## 10. Disposition

The shipping-support evidence gap is closed without reversing the historical
KILL. MILO and contrast-weighted SSIM corroborate the result at the panel level,
so this audition adds confidence that the verdict was not an artifact of the
old GMSD-only gate. It does not make MILO a package dependency, does not make a
24x24 cell a validated MILO benchmark, and does not change MAE's house-oracle
role. `steerableShapeAssist` remains research-only and default-off; `Sources/`
and all defaults are unchanged.
