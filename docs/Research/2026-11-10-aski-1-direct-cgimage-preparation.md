---
title: "ASKI-1 — direct CGImage preparation: resampler choice and selection-ceiling no-harm census"
slug: 2026-11-10-aski-1-direct-cgimage-preparation
date: 2026-11-10
status: active
subsystem: [shape-context]
summary: "ASKI-1 replaces the PNG encode and CGImageSource thumbnail that a decoded CGImage went through before conversion with one vImage Lanczos resample straight to the sampling lattice. A probe against the exact area average of each lattice pixel's source footprint chose Lanczos over CoreGraphics high and medium draws. Because the change moves the frozen-preset golden, this note pre-registers the ASKI-31 selection-ceiling reading rule before any census number is read: MAE-gated at a 1.01 no-harm guard on the frozen preset on both naturals corpora, GMSD reported and non-gating."
related_specs: [docs/Research/2026-09-02-aski-31-lattice-no-harm.md, docs/Research/2026-08-19-house-oracle-audit.md, docs/Research/2026-08-19-sampling-lattice-support-collapse.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1]
runners: [AskiColorLab]
next_action: "Run the five selection-ceiling invocations before (954a1c5) and after (the ASKI-1 implementation commit) in release builds, commit the CSVs under docs/Research/Results/2026-11-10-aski-1-direct-cgimage-preparation/, and read the verdict mechanically from section 3."
---

# ASKI-1 — direct CGImage preparation

**Task:** ASKI-1 · **Registered:** 2026-11-10, before any census number was read ·
**Before:** `954a1c5` (main `d53570d` plus the ASKI-1 benchmark file; library code identical to main) ·
**After:** the ASKI-1 implementation commit on branch `aski-1-direct-cgimage-preparation`.

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

Pending. Filled in after both sides have run.
