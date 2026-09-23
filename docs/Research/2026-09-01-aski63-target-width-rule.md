---
title: "Pre-registered design addendum and verdict rule — ASKI-63 exact target-width render, frozen before the two-arm run"
slug: 2026-09-01-aski63-target-width-rule
date: 2026-09-01
status: active
subsystem: [frontier, animation]
summary: "Thin design addendum to the issue #33 research note for ASKI-63. Fixes the entry point shape (ASCIIGrid.renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:), pixel width set directly and the scale derived from it), the two arms (A: direct render at the derived fractional cell advance with all four Core Graphics subpixel flags set explicitly; B: integer 4x supersample then area average in linear light), the reference (8x supersample, area average in linear light), the oracles (MAE first, GMSD guard, both on Rec.601 luma of 8-bit sRGB), the fixtures (the consumer's 384-column canyon grid at 1166 and 2332 px; earth-limb-sunrise at 80 columns at 243, 600 and 960 px), a periodic-grid column-banding probe with a 0.10 bound and a 0.02 reference self-check, and the four-way SHIP-A / SHIP-B / INCONCLUSIVE / INVALID rule including a cheap-if-close clause. Written and committed before the instrument existed and before any number was read."
related_specs: [docs/Research/2026-09-01-issue33-target-size-render-and-lossless-webp.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1]
runners: [AskiColorLab]
next_action: "Build the entry point with both arms reachable, build AskiColorLab target-width-gate, run it once on the fixtures below, apply section 6 mechanically to the emitted JSON, then ship the winning arm and write the verdict note. Do not edit any threshold in this document after the first decisive number is read; append-only addenda are allowed."
---

# ASKI-63 — pre-registered design addendum and verdict rule

Parent: [issue #33 research note](2026-09-01-issue33-target-size-render-and-lossless-webp.md),
sections 1 and 2. Task: ASKI-63. Everything below is fixed before the measurement instrument
exists. The parent note already established that font size and `scale` are the same knob
for Aski's fonts (0 differing bytes, six ratios, two fonts), so this document does not
re-derive that; it settles the open glyph-edge question by measurement.

## 1. Entry point (AC#1)

```swift
public extension ASCIIGrid {
    func renderImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        targetPixelWidth: Int,
        preserveSourceAspect: Bool = false
    ) -> CGImage
}
```

- `pixelWidth = targetPixelWidth` exactly. `scale = targetPixelWidth / (columns × pointSize × 0.6)`.
  `pixelHeight = ceil(rows × glyphHeight × scale)` through `RenderPixelBounds.pixelExtent`, where
  `glyphHeight` follows the existing `renderGeometry` rule (`pointSize × 1.2`, or
  `glyphWidth × 2.2` when `preserveSourceAspect`). Height derives from the grid, never from the
  source image; the consumer's source-aspect height is compared in section 7, not adopted.
- Invalid input (`targetPixelWidth <= 0`, above `RenderPixelBounds.maxPixelExtent`, empty grid,
  derived scale non-finite) returns the existing 1×1 `emptyImage()`, matching the scale path.
- The existing `renderImage(font:backgroundColor:scale:preserveSourceAspect:)`, the mask-ground
  branch, the effects overloads, and `renderExtendedRangeImage` are byte-identical. Guard: the
  `imagerenderer-g0-srgb.bin` golden and every PNG snapshot under `Tests/AskiTests/__Snapshots__`
  stay unchanged; no golden is re-recorded in this task.
- Equivalence test: when `targetPixelWidth` equals the scale path's `pixelWidth` for some
  integer scale `k` (width = columns × pointSize × 0.6 × k with no ceil slack), the target-width
  path under arm A with the four subpixel flags OFF must reproduce the scale path byte for byte.
  This binds the new geometry to the old one. It is a test of the geometry, not of the arm.
- Both arms are reachable in the shipped package so the run is reproducible from the committed
  instrument: the public entry point routes to the winning arm; the losing arm stays reachable
  through an `@_spi(AskiResearch)` overload taking an explicit `TargetWidthResample` value.
  No other public surface is added.

## 2. Arms

**Arm A — direct.** One render at the derived scale. Cell advance in device space is
`targetPixelWidth / columns`, fractional in general (1166 / 384 = 3.036 px). Before any glyph
is drawn the context sets, explicitly, `setAllowsFontSubpixelPositioning(true)`,
`setShouldSubpixelPositionFonts(true)`, `setAllowsFontSubpixelQuantization(false)`,
`setShouldSubpixelQuantizeFonts(false)`. Antialiasing and font smoothing are left at the
context defaults, the same defaults the scale path runs under, so the only difference from the
scale path is the four positioning flags. Braille cells go through `BrailleRasterizer` as today.

**Arm B — supersample 4×, area average in linear light.** Render as arm A at
`4 × targetPixelWidth` (same flags, same geometry rule, height `4 × pixelHeight` so the factor
is exactly integer on both axes), then reduce each 4×4 block to one pixel: un-premultiply,
decode sRGB to linear per channel, premultiply by alpha, box-average the four channels,
un-premultiply, encode to sRGB, re-premultiply into an 8-bit `premultipliedLast` sRGB context.
For an opaque background this is a plain linear-light box average. Factor 4 is fixed: the
consumer's 1166 px cell is 3.04 px, so 4× gives 12.1 px supersampled cells, the same order as
the shipping 12 px sampling cell; 2332 px gives 24 px. 8× is reserved for the reference.

**Reference.** Arm B's pipeline at factor 8. It is the area-coverage ground truth for a glyph
at the target size: Core Text antialiasing and a box-filtered supersample both estimate
coverage, so the reference is the higher-resolution estimate of the same quantity, not a
member of one arm's family. Stated bias, not dissolved: B and the reference share a filter;
B converges to the reference as its factor rises. This is why the banding probe, the GMSD
guard and the cheap-if-close clause exist.

## 3. Fixtures

| id | grid | font | widths (px) | cell advance (px) |
|---|---|---|---|---|
| `canyon-384` | consumer source (a private photograph that is not redistributed), `DefaultConverter().animate(_, columns: 384, options:)` base grid, `standard` charset, `fullColor`, seed 0, cycling k=4 speed 1 intensity 0.6, `preserveSourceAspect: true`, background `#232323` | `ASCIIFont.system(size: 13.333333)` | 1166, 2332 | 3.036, 6.073 |
| `earth-limb-80` | `docs/Research/Corpus/nasa-steerable-v1/assets/earth-limb-sunrise.png`, `DefaultConverter().convert(_, columns: 80)` defaults, `preserveSourceAspect: true`, background black | `ASCIIFont.system(size: 12)` | 243, 600, 960 | 3.04, 7.5, 12.0 |

243 matches the consumer's density on an in-repo image; 600 is a non-multiple width with a
fractional advance; 960 is an exact integer advance and doubles as the geometry sanity point.
The consumer image is not committed; the run reads it from `--input`. Every fixture is the still base grid; animation frames are not scored.

**Banding probe grid.** For each fixture width, a synthetic grid of the same columns and rows
filled with a single glyph, `#` for `standard`, every cell white on the fixture background.
Rendered through each arm and through the reference.

## 4. Oracles

Scored on Rec.601 luma of the 8-bit sRGB render (`PolarityGate.luma` convention, 0.299 / 0.587
/ 0.114, values in 0…1), arm against reference at identical pixel dimensions, no resampling at
score time. Same dimensions are guaranteed by construction; a dimension mismatch is INVALID.

- **MAE** decides direction (ASKI-27 house oracle). Lower is better.
- **GMSD** is the guard (`GMSD.gmsd`, Prewitt, existing lab implementation). Lower is better.
- **Banding coefficient** `b`: on the probe grid, per-cell ink mass is the sum of `1 − luma`
  over the device pixels whose column index `x` satisfies `floor(x / advance) == c` for cell
  column `c`, summed over all rows. Over interior cell columns (drop the first and last two),
  `b = (max − min) / mean`. Reported per arm, per width, and for the reference.
- **Cost**: wall time per render at each fixture width, release build, median of 5, reported
  for A, B and the reference. Reported, and used only by the cheap-if-close clause.

Negative control: the probe grid rendered with foreground and background swapped must give `b`
within 0.02 of the unswapped value for each arm (ink mass is measured as `1 − luma` on the
swapped render's inverted luma). A larger drift means the probe is measuring the background
fill, not glyph placement, and the run is INVALID.

## 5. Bounds (frozen)

| symbol | value | meaning |
|---|---|---|
| `B_ref` | 0.02 | reference banding self-check; above it the instrument is INVALID |
| `B_max` | 0.10 | banding bound an arm must clear at every width to be eligible |
| `M_tie` | 2.0 % | relative MAE margin below which MAE does not decide |
| `G_tie` | 2.0 % | relative GMSD margin below which GMSD does not decide |
| `G_veto` | 5.0 % | an MAE winner whose GMSD is worse than the other arm's by more than this is vetoed |
| `C_close` | 5.0 % | cheap-if-close: B must beat A by more than this in MAE to ship if B costs more than `C_ratio` × A |
| `C_ratio` | 4.0 | cost ratio for the clause above |

Relative margins are `(loser − winner) / loser` on the mean over the five fixture-width cells,
each cell weighted equally.

## 6. Decision rule (applied mechanically to the emitted JSON)

1. **INVALID** if any: reference `b > B_ref` at any width; negative control drifts more than
   0.02; any arm/reference dimension mismatch; the section 1 equivalence test fails.
2. Eligibility: an arm is eligible if `b ≤ B_max` at every width. Neither eligible →
   **INCONCLUSIVE**, verdict names the banding clause and the offending widths, nothing ships,
   the entry point is not added to the public surface (kept `@_spi` for the follow-up).
3. One eligible arm → that arm ships, subject to no further test (the other arm failed a
   pre-registered bound; its numbers are recorded).
4. Both eligible:
   - MAE margin ≥ `M_tie` → MAE winner, unless its GMSD is worse by more than `G_veto`, in which
     case **INCONCLUSIVE** naming the GMSD veto.
   - MAE margin < `M_tie` → GMSD margin ≥ `G_tie` decides; else tie → **arm A** (simpler,
     no resample space, no 16× pixel traffic).
   - Cheap-if-close overlay: if the winner is B, B's MAE margin over A is ≤ `C_close`, and
     B's median cost exceeds `C_ratio` × A's at the 2332 px width, ship **arm A** and record
     the clause. This clause can only convert a SHIP-B into SHIP-A, never the reverse.
5. The verdict is one of `SHIP-A`, `SHIP-B`, `INCONCLUSIVE`, `INVALID`, encoded in
   `TargetWidthGate.verdict` with one unit test per branch (repo precedent: `PolarityGate.verdict`).

## 7. Consumer validation (AC#6, a finding never a blocker)

On a branch of the downstream website, the canyon generator calls the new entry point with `targetPixelWidth:
outputWidth` and its `resize` step is deleted. The regenerated 1166 and 2332 px stills are
diffed against the shipped 1166 and 2332 px stills
(MAE and GMSD on luma). Shipped height is 777 from the source aspect; the derived height comes
from the grid. If the heights differ, the diff is taken on the common top-anchored rows and the
difference in pixels is recorded as a finding. Any regression is recorded, not gated.

## 8. What this document does not decide

- Whether the four subpixel flags should also be set on the scale path. Out of scope; the
  scale path is byte-identical in this task.
- The CLI flag name. `--width <px>` on `aski render`, requiring `--render-png`; the manifest's
  `render` object gains optional `targetPixelWidth`, `derivedScale`, `cellAdvancePixels`,
  `resampleSpace` (`"none"` for arm A, `"linear-srgb-area-average-4x"` for arm B). Additive
  under manifest schema v1. Existing manifests stay byte-identical (fields omitted when unused).
- Color fonts and optical-size axes: out of scope, stated in DocC (AC#4).

## 9. Addendum (2026-09-01, append-only) — run 1 INVALID, probe re-registered before run 2

Run 1 (provenance `88a97a7`)
returned **INVALID** on the reference banding self-check: 0.3616 at canyon-384@1166 against
`B_ref` 0.02. The cause is the probe estimator in section 4, not the renders: `floor(x / advance)`
assigns 3 device columns to most cells and 4 to every third cell at a 3.036 px advance, so per-cell
mass varies by about a third by construction. Diagnostic: banding is 0.000 for every arm and the
reference at the one integer advance (earth-limb-80@960), and equals the reference's at every
fractional width. The arms were never judged; no threshold is changed.

**Re-registered probe (replaces the binning sentence of section 4 only).** Device column `x`
spans `[x, x + 1)`. Cell column `c` spans `[c × advance, (c + 1) × advance)`. Column `x` contributes
`overlap(x, c) × Σ_rows (1 − luma)` to cell `c`, where `overlap` is the length of the intersection
of the two spans (0, 1, or a fraction at the two boundary columns). Every cell therefore integrates
exactly `advance` columns of ink, and residual variation is glyph placement and rasterization, which
is what the probe was meant to measure. Interior trim, `b = (max − min) / mean`, the negative
control, and every bound in section 5 are unchanged. At an integer advance the new estimator equals
the old one exactly.

Run 2 is a separate run. The run bundles of both runs are not published, so these runs cannot be
replayed from the public tree. If the reference
still fails `B_ref` under the corrected estimator, that is a real finding about the 8× reference and
the task returns INVALID with that clause named.
