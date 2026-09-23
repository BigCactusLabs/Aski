---
title: "ASKI-63 verdict — exact target-width render ships as 4x supersample with linear-light area average (SHIP-B)"
slug: 2026-09-01-aski63-target-width-verdict
date: 2026-09-01
status: complete
subsystem: [frontier, animation]
summary: "Verdict note for ASKI-63. The two-arm gate pre-registered in the rule note was run twice. Run 1 returned INVALID on the reference banding self-check because the pre-registered probe binned device columns by floor(x / advance), which at a fractional cell advance assigns 3 or 4 columns per cell and so measures its own bin widths; banding was 0.000 at the one integer advance and equal across arms and reference elsewhere. Section 9 of the rule re-registered an area-weighted probe before any re-measurement and changed no threshold. Run 2 validated the instrument (reference banding at most 0.0147 against 0.02, negative-control drift at most 0.0121 against 0.02) and both arms cleared the 0.10 banding bound, so the decision fell to MAE: arm B (4x supersample, linear-light box average) beats arm A (direct render at the derived fractional advance with subpixel positioning) by 75.97 percent on mean MAE against the 8x reference, with GMSD agreeing at every one of the five fixture-width cells. B costs 1.55x A at the consumer's 2332 px width, under the 4x cheap-if-close ratio, so that clause did not fire. The public entry point ASCIIGrid.renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:) routes to B; A stays reachable through the research SPI. The shared-filter bias between B and the reference is recorded, not dissolved. No default changed; the scale path and every golden are byte-identical."
related_specs: [docs/Research/2026-09-01-aski63-target-width-rule.md, docs/Research/2026-09-01-issue33-target-size-render-and-lossless-webp.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1]
runners: [AskiColorLab]
next_action: "Owner decides whether the downstream website regenerates its canyon assets with this render path (heights change 777 to 775 and 1555 to 1550). ASKI-64 (lossless animated WebP) follows and should take its byte numbers from frames rendered by this path."
---

# ASKI-63 verdict — SHIP-B

Rule of record: [2026-09-01-aski63-target-width-rule.md](2026-09-01-aski63-target-width-rule.md),
frozen at `b066564` before the instrument existed. Parent:
[issue #33 research note](2026-09-01-issue33-target-size-render-and-lossless-webp.md).

## 1. What shipped

- `ASCIIGrid.renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:)`: the
  pixel width is set directly, the scale is derived as `targetPixelWidth / (columns × pointSize × 0.6)`,
  the height follows the grid's glyph geometry. The public path renders at 4× the target with
  the four Core Graphics subpixel-positioning flags set, then reduces every 4×4 block in linear
  light (sRGB-decoded, alpha-premultiplied box average, re-encoded) into the grid's render colour
  space. Arm A (single direct render) is reachable through
  `@_spi(AskiResearch) renderImage(...resample: .direct)`.
- `aski render --width <px>` (requires `--render-png`); the manifest's `render` object gains
  `targetPixelWidth`, `derivedScale`, `cellAdvancePixels`, `resampleSpace`
  (`linear-srgb-area-average-4x`), additive under schema v1, omitted when `--width` is absent.
- `AskiColorLab target-width-gate`: the committed instrument; `TargetWidthGate.verdict`
  encodes rule section 6 with one unit test per branch.
- DocC `Rendering.md`, "Exact pixel width": `pointSize × scale` is the effective pixel size for
  monochrome monospaced fonts (0 differing bytes, parent note section 1); target width is a
  derived scale; the resample space; colour fonts and optical-size axes out of scope.
- PR #35 review (Codex, two P2 findings, both fixed): (1) under
  `RenderCompositionPolicy.extendedLinearPerGamut` the supersampled bitmap is linear-tagged, so
  the reducer now averages its premultiplied bytes as-is instead of running the sRGB transfer
  on already-linear values (unit test: a black/white 2×2 block reduces to byte 128 linear
  against 188 encoded); (2) the public path's bound is now `ASCIIGrid.maxTargetPixelWidth`
  = 262 144 on both axes, enforced at geometry, mirrored by `aski render --width` validation,
  and the command refuses to write the 1×1 fallback or a manifest for it. Neither change
  touches the gate runs: the default composition policy and the fixture widths are unaffected.
- Byte-identical: the scale path, mask-ground branch, effects overloads,
  `renderExtendedRangeImage`, the `imagerenderer-g0-srgb.bin` golden and every PNG snapshot.
  No default changed.

## 2. Run 1 — INVALID, and why that was the instrument

Provenance `88a97a7`. The canyon-384 input is a private photograph that is not redistributed.
The run bundles of both runs are not published, so these runs cannot be replayed from the public tree.

| cell | A banding | B banding | reference banding |
|---|---|---|---|
| canyon-384 @ 1166 | 0.3603 | 0.3621 | 0.3616 |
| canyon-384 @ 2332 | 0.2126 | 0.2259 | 0.2223 |
| earth-limb-80 @ 243 | 0.3598 | 0.3680 | 0.3677 |
| earth-limb-80 @ 600 | 0.1802 | 0.1796 | 0.1784 |
| earth-limb-80 @ 960 | 0.0000 | 0.0000 | 0.0000 |

The reference failed `B_ref` 0.02 at every fractional advance and passed with exactly zero at
the integer one, and the arms matched the reference to two decimals everywhere. A probe that
cannot tell an 8× reference from a single-pass render is not measuring the render. The
pre-registered binning `floor(x / advance)` gives cells alternately 3 and 4 device columns at a
3.036 px advance, so per-cell mass swings by about a third by construction. Section 9 of the
rule re-registered the estimator (column `x` contributes its overlap with each cell it straddles)
before run 2 and left every bound and the decision rule untouched. Precedent: ASTSK-41's
re-instrument before re-measurement.

## 3. Run 2 — the numbers

Provenance `a4dab58`.
Oracles are arm against the 8× reference on Rec.601 luma at identical dimensions.

| cell | arm | MAE | GMSD | banding | swapped Δ | cost ms |
|---|---|---|---|---|---|---|
| canyon-384 @ 1166 | A | 0.009227 | 0.034565 | 0.0106 | 0.0057 | 510 |
| canyon-384 @ 1166 | B | 0.001290 | 0.005463 | 0.0144 | 0.0121 | 513 |
| canyon-384 @ 2332 | A | 0.003817 | 0.038719 | 0.0017 | 0.0004 | 542 |
| canyon-384 @ 2332 | B | 0.001892 | 0.022683 | 0.0154 | 0.0085 | 837 |
| earth-limb-80 @ 243 | A | 0.000520 | 0.022508 | 0.0106 | 0.0042 | 13.6 |
| earth-limb-80 @ 243 | B | 0.000093 | 0.003142 | 0.0132 | 0.0102 | 15.7 |
| earth-limb-80 @ 600 | A | 0.000176 | 0.008276 | 0.0037 | 0.0015 | 8.0 |
| earth-limb-80 @ 600 | B | 0.000022 | 0.000432 | 0.0050 | 0.0011 | 47.8 |
| earth-limb-80 @ 960 | A | 0.000083 | 0.016551 | 0.0000 | 0.0000 | 8.2 |
| earth-limb-80 @ 960 | B | 0.000025 | 0.004705 | 0.0000 | 0.0000 | 110 |

Reference banding: 0.0143, 0.0147, 0.0130, 0.0047, 0.0000. Reference cost: 784, 1999, 34, 166,
410 ms.

Rule section 6 applied mechanically by `TargetWidthGate.verdict`:

1. INVALID checks: reference banding ≤ `B_ref` at every cell; negative-control drift ≤ 0.02 at
   every arm-cell; dimensions match; equivalence test passed. None fired.
2. Eligibility: both arms ≤ `B_max` 0.10 at every cell. Both eligible.
3. MAE margin `(A − B) / A` on the equal-weight mean over the five cells: 75.97 %, above
   `M_tie`. B is the MAE winner. GMSD veto: B's GMSD is lower than A's at every cell, so no veto.
4. Cheap-if-close: B's MAE lead is not within `C_close` 5 %, so the clause cannot fire; for the
   record, B's cost at canyon-384 @ 2332 is 1.55× A's, under `C_ratio` 4 either way.

**Verdict: SHIP-B.**

## 4. Caveats the run does not dissolve

- **Shared-filter bias.** The reference is arm B's pipeline at 8×. Rule section 2 states the
  bias and why the banding probe and GMSD guard were carried. Two observations bound it without
  removing it: the margin is large at every cell, not only where a box-filter family would
  agree with itself; and at the integer advance (960 px), where no placement question exists,
  B is still 3.3× closer to the reference than A on MAE, which is a statement about Core Text's
  own coverage antialiasing at 12 px cells versus an area integral, not about placement.
- **Banding is not the discriminator it was meant to be.** Under the corrected probe both arms
  and the reference sit between 0.000 and 0.016 at every width; arm A is the lowest at the
  fractional widths. The pre-registered bound (0.10) was six times looser than anything
  observed. Placement banding is a non-issue for either arm on this grid; the probe's remaining
  value is the instrument self-check it now passes.
- **Cost.** B's per-render cost grows with the supersampled pixel count: 1.55× A at 2332 px
  on the consumer grid, 13× A at earth-limb @ 960 where A is already sub-10 ms. For a 17-frame
  animation at 2332 px this is about 14 s against 9 s. Recorded; the rule did not gate on it
  above the ratio.
- **Negative control.** B's swapped-probe drift (0.0121 at 1166) is twice A's. Both are under
  the 0.02 tolerance; the asymmetry comes from the sRGB-encoded ink mass of a `#232323`
  background not being the mirror of white, so the swapped run measures a different mean.

## 5. Consumer validation (rule section 7)

On a branch of the downstream website the canyon generator calls the new
entry point with `targetPixelWidth: outputWidth` and its `resize` step is deleted (30 lines
removed, 5 added; the manifest gains `resampleSpace` and records the rendered height). Aski at
`f84b6b1`. Oracles on Rec.601 luma over the common width and the common top-anchored rows.

| width | shipped | new path | new wall s | old wall s | MAE vs shipped | GMSD vs shipped |
|---|---|---|---|---|---|---|
| 1166 | 1166 × 777 | 1166 × 775 | 14.4 | 10.4 | 0.0319 | 0.2835 |
| 2332 | 2332 × 1555 | 2332 × 1550 | 18.1 | — | 0.0379 | 0.3540 |

Control: the unmodified generator at the same Aski commit reproduced the shipped 1166 px still
byte for byte (MAE 0, GMSD 0), so the converter output has not drifted since the shipped
provenance and the whole difference is the render path.

Findings, none gating:

- **Height.** The shipped height came from the source aspect (3072 × 2048 → 777 and 1555). The new
  path derives it from the grid's glyph geometry (116 rows), giving 775 and 1550. Rows therefore
  drift out of phase by up to 2 and 5 px over the image, which inflates both oracles; the numbers
  above are an upper bound on the render-path difference, not an estimate of it. The consumer's
  layout reads the manifest height, so the change is self-describing.
- **Sharpness.** Side-by-side crops show the shipped still as a blurred `CGInterpolationQuality.high`
  downscale of a 3072 px render (ratio 0.38) with glyph interiors smeared; the new still resolves
  individual glyphs. This is the intended change and the reason the oracles are large: they measure
  distance from the blurred asset, not quality.
- **Cost.** 14.4 s against 10.4 s for the still plus 17 frames at 1166 px (1.38×); 18.1 s at 2332 px.
  Consistent with section 4.
- **Bytes.** PNG still 848 KB against 1008 KB shipped at 1166 px; GIF 2.61 MB against 3.04 MB. The
  sharper frames quantise smaller. ASKI-64 should take its WebP numbers from these frames.

The downstream website's branch is left unmerged for the owner; regenerating and shipping the
assets is a decision for that website.

## 6. What this does not decide

- Whether the scale path should set the subpixel-positioning flags. Out of scope; it is
  byte-identical.
- Arm B's factor. 4 was fixed by the rule; no other factor was measured.
- Lossless animated WebP (ASKI-64) — its byte numbers should be taken on frames from this path.
