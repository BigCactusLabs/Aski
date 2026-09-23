---
title: "ASKI-66 - Exact-lattice chroma dose-response redesign - INCONCLUSIVE"
slug: 2026-09-04-aski66-exact-lattice-dose-redesign
date: 2026-09-04
status: complete
subsystem: [shape-context]
summary: "INCONCLUSIVE. The rule and runner were committed before measurement. All 64 valid luma-split x chroma-scale candidates ran both color axes over 21 lambda arms on the exact 8x18 calibration lattice; every 2,688 axis-arm row had one invariant flipped fraction and no lambda-50, so no candidate qualified and the frozen stop rule skipped both holdouts. The June chromaShapeAssist dose-response PASS remains retracted as a truncating-lattice artifact. The archived-verdict audit also finds every named pre-ASKI-65 battery non-exact or incompletely recorded; non-exact KILLs are candidate false negatives, not automatically reversed verdicts. No production default changed."
related_specs: [docs/Research/2026-06-11-isoluminant-dose-response.md, docs/agents/research-methodology.md]
datasets: []
runners: [AskiColorLab]
next_action: "Closed INCONCLUSIVE. ASKI-29 and ASKI-50 completed their separate archived-verdict replay, and ASKI-68 removed chromaShapeAssist and its dedicated runners. Do not widen or re-tune this instrument without a new pre-registered mechanism."
---

# ASKI-66 — exact-lattice chroma dose-response redesign rule

Sections 1-6 are the rule committed at `51de4e6` before the calibration
instrument and its measurements. The runner was committed at `27e2492`; the
result and audit follow in Sections 7-8.

## 1. Question and boundary

The old competition ramp gave a graded response only on the invalid 8x17
truncating cell. Exact 8x18, 8x20, and 16x36 cells were inert; an exact 8x19
cell was binary. This round asks one narrow question: can the existing
luma-versus-chroma competition design produce a graded response on exact
lattices after a bounded re-tune?

This is instrument calibration. It cannot promote `chromaShapeAssist`, reverse
the failed natural-corpus gate, change its default, or add a product option.
The treatment stays default-off during this task.

## 2. Frozen calibration grid

The fixture keeps the same two color axes, mid-cell period-eight luma grating,
horizontal chroma edge, OKLab-L pedestal, converter path, glyph set, palette,
and exact-lattice guard. Only these inputs vary:

- luma split minimum: `{0.005, 0.01, 0.02, 0.04}`;
- luma split maximum: `{0.08, 0.12, 0.16, 0.24}`, with `minimum < maximum`;
- chroma scale: `{0.08, 0.16, 0.24, 0.32}`;
- lambda: `0.00...1.00` in increments of `0.05`.

Calibration geometry is 512x522 at 64 columns: 29 rows of exact 8x18 cells.
Every candidate runs both `redGreenCompetition` and
`blueYellowCompetition`. Gamut failure, geometry failure, any off-band glyph
change, or a decreasing flip fraction makes that candidate invalid.

## 3. Candidate rule

A calibration candidate qualifies only when both color axes have:

- at least five distinct flipped fractions after rounding to 0.001;
- a monotone non-decreasing curve;
- zero off-band changes;
- an override midpoint between lambda 0.20 and 0.80 inclusive.

If more than one candidate qualifies, select mechanically by:

1. greatest minimum distinct-count across the two color axes;
2. greatest minimum flip-fraction range;
3. smallest chroma scale;
4. smallest luma split maximum;
5. smallest luma split minimum.

If no candidate qualifies, stop. The verdict is `INCONCLUSIVE`; do not widen
the grid or change the fixture after reading the result.

## 4. Frozen holdouts

Evaluate only the selected candidate on both holdouts:

- 640x648 at 80 columns: exact 8x18 cells over a different grid extent;
- 1024x1044 at 64 columns: exact 16x36 cells at twice the linear sample scale.

Each holdout must keep both axes monotone, keep all off-band glyphs unchanged,
produce at least four distinct fractions per axis, and keep the lambda-50 point
within 0.15 of calibration. A missing lambda-50 is a failure. Both holdouts
must pass. Otherwise the redesign verdict is `INCONCLUSIVE`.

Passing means only that the synthetic instrument is graded and stable enough
to characterize dose. It does not make the treatment a product candidate.

## 5. Archived-verdict audit contract

The task's audit table will name, one row per verdict, the battery dimensions,
column counts, whether every measured fixture was an exact sampling lattice,
whether the matcher ran at the shipping low-support footprint or a fuller
descriptor footprint, and the consequence. These are separate defects:

- lattice validity asks whether source pixels were truncated or resampled;
- descriptor support asks how much of the 60D query could be populated.

The required rows are ASTSK-27/31 shape residual, ASTSK-7 occupancy, the
decolor oracle, ASTSK-35 structure assist, and ASTSK-42 steerable assist. A
non-exact KILL is flagged as a candidate false negative. The audit does not
reverse a verdict without a valid re-run.

## 6. Falsifiers and stop rule

The redesign is falsified by no qualifying calibration candidate, any holdout
failure, off-band leakage, non-monotonic response, or a response that exists
only at one sample scale. The search is exactly one frozen grid and one selected
candidate. No second tuning round belongs to ASKI-66.

## 7. Result — INCONCLUSIVE

The one permitted run used release commit
`27e249254a931850627c79b8b079470b7a79f82b` and wrote the committed artifacts
under
[`Results/2026-09-04-aski66-dose-calibration/`](Results/2026-09-04-aski66-dose-calibration/).

- 64 of 64 candidates were valid and in sRGB gamut.
- Both color axes ran at all 21 lambda values for every candidate: 2,688 CSV
  rows, with no missing or invalid row.
- Every axis for every candidate had exactly one distinct flipped fraction,
  remained monotone, and kept the off-band invariant.
- No axis produced a lambda-50. Therefore no candidate qualified.
- The frozen stop rule skipped both holdouts. No second search ran.

**Verdict: INCONCLUSIVE.** The bounded redesign did not recover a graded
exact-lattice competition instrument. This closes the synthetic dose-response
question for this design. It does not change `chromaShapeAssist`, which remains
default-off, and it does not disturb the still-valid algebraic cancellation
result for constant-L ramps.

## 8. Archived-verdict lattice audit

This table audits the historical runs, not their current implementations.
ASKI-65 did not exist when they ran. “Non-exact” therefore means the old
origin-anchored integer-pitch path omitted source remainders. Descriptor support
is separate: it records how much of the 60D query was populated, or states when
the surviving record cannot establish it.

| verdict | battery and columns | lattice at measurement | descriptor support | consequence |
| --- | --- | --- | --- | --- |
| ASTSK-27 shape residual — INCONCLUSIVE | Five 256x256 procedural fixtures; the complete column list and executable command do not survive | Not reproducible in full. The recorded 80-column arm resolved 36 rows, so 256 mod 80 = 16 and 256 mod 36 = 4: non-exact, old truncating path. It also compared about 3-pixel native blocks to a 24x24 oracle. | Low native support at the canonical arm; exact reachable-bin counts were not recorded. The matcher/oracle alignment and upsampling defects are independently documented. | Invalid as a general descriptor claim for both lattice and oracle reasons. It ended INCONCLUSIVE, so no KILL is reversed. ASTSK-31 superseded it. |
| ASTSK-31 shape residual — GENERAL INCONCLUSIVE; LINE-ART KILL | Nine fixtures: five procedural, one glyph sheet, and three NASA images, all at native 2048px; columns 44, 52, 64, 72, 80 | Non-exact at every column as a complete 2048-square lattice. For example, 80 columns resolved 36 rows and omitted remainders 48x32. | Full lab regime: 25x56 cells and 48/60 reachable bins at 80 columns, not the shipping 2-3/60 regime. | The line-art KILL is a **candidate false negative** because its battery was non-exact. Do not reverse it: the high-support experiment remains evidence on its own regime, and the record is not fully reproducible. ASKI-29 owns a valid replay. |
| ASTSK-7 occupancy — KILL | 39 sources x five weights = 195 rows at 64 columns: five structured procedural fixtures, two synthetic isoluminant fixtures, 24 NASA occupancy assets, and eight legacy NASA assets | The complete battery was not exact. The 256-square structured fixtures resolved 29 rows and omitted 24 vertical pixels; the 512-square isoluminant fixtures omitted 19. Native corpus dimensions varied and exactness was not recorded. All used the old truncating path. The source oracle used fractional full-source blocks, so it did not share the converter's cropped partition. | A no-downscale oversample kept native pixels. Structured fixtures used 4x8 cells and 11/60 bins; support varied elsewhere and was not fully recorded. This was not the shipping fixed-oversample regime. | **Candidate false negative.** Large structure regressions and near-total churn make a sign flip unlikely, but the audit does not guess: a replay needs an exact lattice and explicit support metadata. |
| Decolor oracle — PASS | Five deterministic 96x48 fixtures x three palettes at 80 columns; 21,600 cell rows plus 512 seeded 2AFC trials | Non-exact: 18 rows, 1x2 cells, and 16x12 source pixels omitted by the old truncating path. The oracle deliberately copied that same cell math, so it stayed aligned with the converter's crop. | The 1-pixel-wide source cell had zero descriptor support. Descriptor augmentation was not the treatment; this gate tested recomposition and palette discrimination. | A non-exact PASS is a candidate false positive, not the requested false-negative class. The area-tone result is not reversed, but it is evidence only for the aligned cropped footprint until replayed. |
| ASTSK-35 structure assist — KILL | The ASTSK-31 nine-fixture, native-2048 lineage and five-column sweep; the exact decisive command and result directory do not survive | The surviving record ties it to the same non-exact 2048-square grids and old truncating path. Exact per-row reconstruction is unavailable. | Full lab regime; the 80-column arm used 25x56 cells and 48/60 reachable bins. This was not shipping support. | **Candidate false negative.** Do not reverse: the direct pick-quality arm missed the +3% bar and regressed checker/naturals after its fidelity fix, but a valid replay is required for product transfer. |
| ASTSK-42 steerable assist — KILL | Oriented battery plus three >=3072px NASA naturals at 3072px; columns 48, 64, 80, 96, 120; 147,168 cells | Non-exact at every column as a complete square lattice. At 80 columns it resolved 36 rows and omitted remainders 32x12; every arm used the old truncating path. | Full lab regime: 38x85 cells and 48/60 reachable bins at 80 columns, not shipping support. | **Candidate false negative.** Do not reverse: aggregate -0.19% and naturals -0.92% remain a strong negative in the measured high-support regime. ASKI-29/50 own replay and metric modernization. |

The audit therefore corroborates the ASKI-65 concern but does not license a
blanket verdict flip. Lattice truncation can create false positives, as the June
dose PASS proved, or false negatives. Support mismatch is an additional transfer
problem. A replacement verdict needs a preregistered run that controls both.
