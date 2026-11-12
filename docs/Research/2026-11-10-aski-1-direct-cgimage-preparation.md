---
title: "ASKI-1 — direct CGImage preparation: resampler choice and selection-ceiling no-harm census"
slug: 2026-11-10-aski-1-direct-cgimage-preparation
date: 2026-11-10
status: complete
subsystem: [shape-context]
summary: "ASKI-1 closes NO HARM. ASKI-1 replaces the PNG encode and CGImageSource thumbnail that a decoded CGImage went through before conversion with one vImage Lanczos resample straight to the sampling lattice. A probe against the exact area average of each lattice pixel's source footprint chose Lanczos over CoreGraphics high and medium draws. Because the change moves the frozen-preset golden, this note pre-registered the ASKI-31 selection-ceiling reading rule before any census number was read (MAE-gated at a 1.01 no-harm guard on the frozen preset on both naturals corpora, GMSD reported and non-gating), then ran the census at 954a1c5 and at the implementation commit 05af50c. Frozen-preset production-arm MAE moves by x1.0000 on nasa-steerable-v1 and x0.9991 on nasa-structure-v1; every secondary arm stays within 0.1 percent of parity. GMSD rises 0.09 percent on nasa-structure-v1, a labelled direction disagreement. The frozen preset's production arm uses one to three glyphs, so the dense charsets are the sensitive cross-check, and they move by at most +0.09 percent MAE."
related_specs: [docs/Research/2026-09-02-aski-31-lattice-no-harm.md, docs/Research/2026-08-19-house-oracle-audit.md, docs/Research/2026-08-19-sampling-lattice-support-collapse.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1]
runners: [AskiColorLab]
next_action: "ASKI-1 is closed by this census. The before/after CSVs are the baseline for ASKI-2, which moves video-frame orientation into the same preparation step."
---

# ASKI-1 — direct CGImage preparation

**Task:** ASKI-1 · **Registered:** 2026-11-10, before any census number was read ·
**Before:** `954a1c5` (main `d53570d` plus the ASKI-1 benchmark file; library code identical to main) ·
**After:** `05af50c`, the ASKI-1 implementation commit on branch `aski-1-direct-cgimage-preparation`.

## 1. What changed

Before ASKI-1, a decoded `CGImage` whose longest side exceeded the conversion budget
(`thumbnailMaxPixelSize`) went through `ImageIOThumbnail.decode(image:maxPixelSize:)`: the image was
PNG-encoded, re-opened as a `CGImageSource`, and decoded as an ImageIO thumbnail. ASKI-65 then drew
that thumbnail into the exact sampling lattice (`columns*cellWidth × rows*cellHeight`) with
CoreGraphics `.high` interpolation. Every video frame took the same route.

After ASKI-1 (`Sources/Aski/CellSampling.swift`, `samplingLattice(image:maxPixelSize:columns:rows:colorSpace:)`):

- **Prepared size.** `preparedSize` puts the longest side on the budget and rounds the short side to
  the nearest pixel. ImageIO floored through an internal power-of-two subsample and could land a
  pixel lower; the cell pitch is the floored quotient of the prepared size by the grid, so a pitch
  can differ by one where the two sizes differ. The grid itself (`columns × rows`) depends only on
  the source dimensions and does not change.
- **One interpolation.** vImage converts the source to premultiplied RGBA8 in the target color space
  and resamples it once, with `kvImageHighQualityResampling` (Lanczos), straight to the lattice.
  Color is then clipped to alpha, because Lanczos can overshoot.
- **Unchanged inputs.** A source already within the budget keeps the CoreGraphics `.high` draw byte
  for byte. That covers the CLI and any caller that loads through `ImageIOThumbnail.decode(data:)`
  or `decode(source:)`, which keep their ImageIO thumbnail and EXIF orientation.
- **Removed API.** The public `ImageIOThumbnail.decode(image:maxPixelSize:)` is removed.

## 2. Resampler choice (exploratory, read before this rule was written)

The resampler was chosen on a probe that ran before this note. It is selection evidence for the
implementation, not the verdict; the verdict is the census in section 3.

**Probe.** 40 corpus photos (`nasa-steerable-v1`, `nasa-structure-v1`) at three grid geometries
(76 columns at oversample 2, 24 at 2, 80 at 4), plus synthetic zone plates: 120 cases. The
reference is the exact area average of each lattice pixel's footprint in a full-size CoreGraphics
conversion of the source, in the premultiplied 8-bit encoding the samplers read. The figures are
mean absolute error in 8-bit code values against that reference.

| method | mean MAE | cases worse than the old path | cases above 1.25× old | worst ratio to old | geomean ratio to old |
|---|---|---|---|---|---|
| old: PNG → ImageIO thumbnail → CG `.high` into the lattice | 1.705 | — | — | — | — |
| CG `.high` draw, source → lattice | 2.064 | 84 | 51 | 7.0 | 1.235 |
| CG `.medium` draw, source → lattice | 1.362 | 44 | 30 | 7.0 | 0.719 |
| **vImage Lanczos, source → lattice** | **1.394** | **14** | **0** | **1.19** | **0.793** |

CG `.medium` has the lowest mean but is erratic: it was up to seven times worse than the old path on
some sRGB JPEGs. Lanczos was never more than 1.19× the old error, its geomean error is 21% lower, and
it is a documented, deterministic filter. A follow-up check found vImage's color conversion
byte-identical to a CoreGraphics draw for Display P3 (8- and 16-bit, including out-of-sRGB colors),
generic gray and sRGB sources into both target spaces.

**Cost.** Preparation of a 4032×3024 photo for the frozen preset took 434 ms on the old path and
27.6 ms with Lanczos; a 1920×1080 frame took 81.6 ms and 3.7 ms. Measured in separate processes,
peak footprint for the 12 MP photo was 295 MB on the old path and 104 MB with Lanczos. A no-op
process reached 100 MB, because building the test image itself peaks there, so the Lanczos figure
shows only that its copy stays under that peak, not its exact cost. The ASKI-1 benchmarks in
`Benchmarks/AskiBenchmarks/PreparationBenchmarks.swift` record the before/after figures for the PR.

**Unit fidelity.** `Tests/AskiTests/TargetSizePreparationTests.swift` pins the new path against the
same area-average reference on synthetic inputs, with the measured values and the wrong-path
magnitudes stated next to each tolerance. On those synthetic scenes the old path's cells sat
slightly closer to the reference grid in brightness (MAE 0.0016–0.0031 against 0.0024–0.0051 on a
0–1 scale), while the new raster sat closer in pixel MAE at three of four lattice geometries. Both
differences are under half a code value. Real photographs decide, which is what the census is for.

## 3. Reading rule — frozen before any census number was read

This is the ASKI-31 rule (`docs/Research/2026-09-02-aski-31-lattice-no-harm.md` §2), applied to the
ASKI-1 boundary without change of threshold.

The instrument is `aski lab color selection-ceiling` (`Tools/AskiColorLab/SamplingLattice/SelectionCeiling.swift`).
Its fixtures load each corpus asset at native size and redraw it into a DeviceGray image
(`Tools/AskiColorLab/ShapeResidual/RealFixture.swift`), so every fixture is larger than the budget and
goes through the changed path. Each cell's oracle reference is the native-resolution block the
converter's own `SamplingGeometry` says it read, so the reference is not softened by the path under
test. The ASKI-1 change touches no instrument code; any `Tools/AskiColorLab` diff across the boundary
must be comment-only, and the PR states it.

1. **Quantity.** Per-cell mean loss of the production arm `P` (CSV `arm == "P"`), read from the
   `--output` CSV and nothing else. Ratio `R = after / before`, four decimal places.
2. **Verdict oracle.** MAE, per ASKI-27. `R_MAE ≤ 1.0100` on the frozen preset (`blocks`,
   76 columns, oversample 2) on **both** `nasa-steerable-v1` and `nasa-structure-v1` → **NO HARM**.
   Any frozen-preset `R_MAE` in `(1.0100, 1.0300]` → **INCONCLUSIVE**. Any `R_MAE > 1.0300` →
   **HARM**. `R_MAE ≤ 0.9700` on both corpora is recorded as an improvement and changes nothing else.
3. **GMSD.** Reported at every arm. It cannot gate (house-oracle audit §5). A GMSD direction that
   disagrees with MAE is recorded as a labelled cross-check note, not a demotion.
4. **Secondary arms, non-gating.** The 80-column `blocks,standard` sweep at oversample
   `2,4,8,16,32` and `braille` at oversample 2 on `nasa-steerable-v1`, and `blocks,standard` at
   oversample 2 on `nasa-structure-v1`. The ranking-headroom figures (`totalGap%`, `rankGap%`) are
   quoted from the stdout tables for context only.
5. **Population caveat, stated in advance.** Both sides score the same grid cells, because the grid
   depends only on the source dimensions. Where ImageIO's floored size and the rounded prepared size
   differ, the lattice pitch, and therefore the native block each cell reads, can differ by one
   lattice pixel on an axis. The ratio compares two shipped pipelines against the pixels each one
   samples, as ASKI-31's did; it is not a paired test on identical footprints.
6. **Tie and `nan` policy** as in the ASKI-30/28 rule §5: a ratio of exactly `1.0000` is neither
   improved nor harmed; a `nan` cell is never read as a pass.
7. **Consequence.** NO HARM lets the PR claim no harm on the frozen preset. INCONCLUSIVE or HARM is
   reported in the PR as the verdict, and the default change goes to the owner for a decision; it
   is not shipped on a re-recorded golden alone.

## 4. Runs

Five invocations per side, identical flags, release build, from the repository root:

```text
xcrun swift run -c release aski lab color selection-ceiling --charset blocks --columns 76 --oversample 2 --corpus <STEER> --output frozen-steer.csv
xcrun swift run -c release aski lab color selection-ceiling --charset blocks --columns 76 --oversample 2 --corpus <STRUCT> --output frozen-struct.csv
xcrun swift run -c release aski lab color selection-ceiling --charset blocks,standard --columns 80 --oversample 2,4,8,16,32 --corpus <STEER> --output sweep-steer.csv
xcrun swift run -c release aski lab color selection-ceiling --charset blocks,standard --columns 80 --oversample 2 --corpus <STRUCT> --output default-struct.csv
xcrun swift run -c release aski lab color selection-ceiling --charset braille --columns 80 --oversample 2 --corpus <STEER> --output braille-steer.csv
```

`STEER = docs/Research/Corpus/nasa-steerable-v1/assets`, `STRUCT = docs/Research/Corpus/nasa-structure-v1/assets`.
Stdout goes to the matching `.txt`. Artifacts:
`docs/Research/Results/2026-11-10-aski-1-direct-cgimage-preparation/{before,after}/`.

## 5. Results

Both sides ran clean (exit 0, no deviations from section 4). `before/` was built at `954a1c5` and
`after/` at `05af50c`, the ASKI-1 implementation commit; each CSV's `gitSHA` column records its
side. The two sides ran concurrently under the shared machine lock; the census is deterministic and
gates on no timing column. Every `cells` count is identical before and after (7752 at 76 columns,
8640 at 80), as section 3.5 predicted. Ratios are `after / before` of the CSV means, four decimals.
The script that produced the tables reads only the committed CSVs.

### 5.1 Frozen preset — the gating rows (`blocks`, 76 columns, oversample 2, arm `P`)

| corpus | cells | MAE before | MAE after | **R_MAE** | GMSD before | GMSD after | R_GMSD | R_RMSE | R_SSIM | R_HaarPSI |
|---|---|---|---|---|---|---|---|---|---|---|
| nasa-steerable-v1 | 7752 | 0.56406 | 0.56405 | **1.0000** | 0.34099 | 0.34099 | 1.0000 | 1.0000 | 1.0011 | 1.0001 |
| nasa-structure-v1 | 7752 | 0.56202 | 0.56149 | **0.9991** | 0.29741 | 0.29768 | 1.0009 | 0.9992 | 0.9845 | 1.0028 |

Both `R_MAE` values are inside the 1.0100 guard. On `nasa-steerable-v1` the ratio is 0.99998,
which rounds to the tie value 1.0000 (rule 3.6). On `nasa-structure-v1` MAE falls 0.09% while GMSD
rises 0.09%: a direction disagreement, recorded under rule 3.3 as a labelled cross-check note and not
as a demotion. Neither move is close to the guard.

### 5.2 Secondary arms (non-gating), arm `P`

| corpus | charset | columns | oversample | cells | R_MAE | R_GMSD | R_RMSE |
|---|---|---|---|---|---|---|---|
| nasa-steerable-v1 | blocks | 80 | 2 | 8640 | 1.0000 | 1.0000 | 1.0000 |
| nasa-steerable-v1 | blocks | 80 | 4 | 8640 | 1.0000 | 1.0000 | 0.9999 |
| nasa-steerable-v1 | blocks | 80 | 8 | 8640 | 1.0000 | 1.0000 | 1.0000 |
| nasa-steerable-v1 | blocks | 80 | 16 | 8640 | 1.0000 | 1.0000 | 1.0000 |
| nasa-steerable-v1 | blocks | 80 | 32 | 8640 | 1.0000 | 1.0000 | 1.0000 |
| nasa-steerable-v1 | standard | 80 | 2 | 8640 | 1.0003 | 1.0002 | 1.0006 |
| nasa-steerable-v1 | standard | 80 | 4 | 8640 | 1.0004 | 1.0001 | 1.0008 |
| nasa-steerable-v1 | standard | 80 | 8 | 8640 | 1.0002 | 0.9999 | 1.0004 |
| nasa-steerable-v1 | standard | 80 | 16 | 8640 | 1.0001 | 1.0000 | 1.0003 |
| nasa-steerable-v1 | standard | 80 | 32 | 8640 | 1.0001 | 0.9999 | 1.0003 |
| nasa-steerable-v1 | braille | 80 | 2 | 8640 | 1.0001 | 1.0003 | 1.0004 |
| nasa-structure-v1 | blocks | 80 | 2 | 8640 | 0.9992 | 1.0011 | 0.9994 |
| nasa-structure-v1 | standard | 80 | 2 | 8640 | 1.0009 | 1.0012 | 1.0014 |

Every production-arm MAE ratio lies within ±0.1% of parity. The ranking-headroom figures barely
move: on the frozen preset `totalGap%` goes 62.97 → 62.96 on steerable and 61.44 → 61.40 on
structure; on `standard` at oversample 2 it goes 4.76 → 4.79 and 7.64 → 7.72; on `braille`,
3.65 → 3.66.

### 5.3 Cross-check notes (non-gating)

- **The gating arm is insensitive.** The frozen preset's production arm picks one to three distinct
  glyphs across the whole corpus (`glyphsUsed`), with rows of nearly identical glyphs (`runMean` 75
  of 76 on steerable). This is the known descriptor-support collapse on `blocks`
  (`docs/Research/2026-08-19-sampling-lattice-support-collapse.md`), not an ASKI-1 effect: the
  `before/` side shows it too. So the frozen-preset rows can detect only a large change in tone.
  The arms that do respond to the sampled pixels, `standard` and `braille`, move by at most +0.04%
  MAE on steerable and +0.09% on structure.
- **The tone-only floor `F` rises slightly.** `R_MAE` for arm `F` is 1.0004 to 1.0039 on
  `blocks` and 0.9998 to 1.0021 on `standard` and `braille`. The cell tone from one Lanczos
  resample sits marginally further from the native block average than the old thumbnail-then-lattice
  pair, which blurred more. This agrees with the unit-level finding in section 2. The shift is
  smaller than 0.0012 in mean loss and does not reach the production arm.

## 6. Verdict

**NO HARM.** By rule 3.2, the frozen-preset `R_MAE` is 1.0000 on `nasa-steerable-v1` and 0.9991 on
`nasa-structure-v1`, both at or below 1.0100. Neither is at or below 0.9700, so no improvement is
recorded. The ASKI-1 PR may claim no harm on the frozen preset; its speed and memory evidence comes
from `Benchmarks/AskiBenchmarks/PreparationBenchmarks.swift` and is reported in the PR, not here.
