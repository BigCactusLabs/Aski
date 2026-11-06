---
title: "ASKI-3 — color interpretation correction and frozen-selection guard"
slug: 2026-11-05-aski3-color-semantics
date: 2026-11-05
status: complete
subsystem: [color-science, tile-grid]
summary: "Pre-registered checks for correcting Generic RGB reinterpretation of encoded sRGB/Display P3 cell colors and engine gamut retagging. Native pixel regressions pass. All six paired production MAE/GMSD ratios equal 1.0 across 75468 cells; pooled selection evidence does not establish color fidelity. Review repairs (sRGB CLI colors, relative colorimetric intent) leave selection untouched; goldens were re-recorded on macOS 27.0.1 / Xcode 27.0 on an M3 Max after the ASKI-97 re-baseline was withdrawn."
related_specs: [Sources/Aski/ASCIICell.swift, Sources/Aski/Tiles/TileCell.swift, docs/agents/research-methodology.md, docs/Research/2026-09-02-aski-31-lattice-no-harm.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1, docs/Research/Corpus/nasa-occupancy-v1]
runners: [AskiColorLab]
results: [docs/Research/Results/2026-11-05-aski3-color-semantics]
next_action: "Review ASKI-3 with its review repairs and re-recorded goldens. ASKI-15 and ASKI-98 remain follow-up options."
---

# ASKI-3 — color interpretation and frozen-selection guard

## Scope and control

`displayColor` components are encoded in their grid's sRGB or Display P3 gamut.
Several raster paths construct Generic RGB colors instead. The engine also changes
that gamut tag without converting components. The correction changes source color
interpretation and engine adaptation, not glyph selection, palettes, sampling,
ShapeData, alpha/coverage rules, or the HDR gain policy. Keep explicitly tagged
caller colors in their own spaces. Preserve legacy literal Generic RGB solid mask
fallback and ground colorimetry in the original grid gamut across engine adaptation.

The control is `14c8697ce0211098630088cab14ef9e8a79b048e`, including the macOS 27.0.1
render baseline. A detached control checkout and release executable are retained.
The rule commit adds documentation only to that control. Record both code and rule
revisions with the results, and hash the actual executable used on each side.

## Acceptance fixed before the census

1. **Color contract.** In encoded direct ASCII/tile and effects raster output,
   opaque interior `(0.8, 0.2, 0.1)` must be `(204, 51, 26)` within one 8-bit step,
   with the correct sRGB/P3 tag. For gamut conversion, compare to independently
   drawn explicitly source-tagged Core Graphics colors. Linear composition must
   decode the encoded source; it must not relabel those numbers as linear.
   Exercise engine CGImage and CIImage output, target-width rendering, coverage,
   active ground, inherited character fallback, braille and tile shapes. Existing
   attributed-string and HDR contracts remain in force.
2. **Selection population.** Run the unchanged `selection-ceiling` instrument,
   production arm `P`, blocks, 76 columns, oversample 2, footprint 24, stride 1,
   inverted polarity, on all three declared corpora, before and after. Require
   identical corpus/charset/arm/configuration keys and cell counts. The current CSV
   reports corpus-level means, not per-fixture rows; preserve and hash the input
   corpus assets on both sides. Missing, non-finite, or
   unmatched rows cannot pass. Do not enable experimental arms.
3. **No-harm guard.** For each corpus and each of MAE and GMSD, compare the P-row mean losses reported in the CSV (`mae` and `gmsd`). Require after/before <= 1.0100 without rounding
   the ratio before the decision. If the baseline mean is zero, only an after mean
   of zero passes. Both metrics must pass on every corpus; a disagreement or guard
   breach stops acceptance for investigation. This is a conservative guard for
   this bug fix, not a universal GMSD policy or a new matcher promotion rule.
4. **Expected invariance.** Glyph selection is outside the change. Report whether
   every paired P-row metric is exactly unchanged, and explain any difference even
   if the aggregate guard passes. Preserve all emitted rows, not only passing
   production rows. Do not edit this rule after reading the census.
5. **Interpretation limit.** The census is monochrome sRGB selection evidence; it
   does not score Vesper's P3 duotone color rendering or rule out cancelling
   per-fixture changes in a pooled metric. Correct source interpretation
   is established by the native color checks. A golden re-record alone establishes
   neither color correctness nor universal image quality. Inspect changed images,
   retain the before/after CSVs with changed frozen goldens, and pass `just check`.

## Commands

Build each revision with `xcrun swift build -c release --product aski`. Run its
release `aski` executable from that checkout. Repeat this command for each of
`nasa-steerable-v1`, `nasa-structure-v1`, and `nasa-occupancy-v1`, replacing the
placeholders with the corpus name and a side-specific output path:

```text
aski lab color selection-ceiling --charset blocks --columns 76 --oversample 2 --footprint 24 --stride 1 --shape-query-polarity inverted --corpus docs/Research/Corpus/<corpus>/assets --output <side>/<corpus>.csv
```

Retain stdout separately. Use the CSV fields, not the stdout rounded table, to
apply the rule. Record macOS, Xcode, Swift, source revisions and executable hashes
in the result manifest. The output directory must follow the research registry's
manifest and file-completeness checks.

## Results — 2026-11-05

The rule above was committed unchanged at
`6b47141d13409e5fdde52bafb370e646b9d5c40a` before measurements. The
[result package](Results/2026-11-05-aski3-color-semantics/README.md) retains all
before/after CSVs, source patch, executable/input hashes, commands, and toolchain.
All production and floor-comparator quality/selection fields are exactly unchanged;
timing and revision identity differ. All six production MAE/GMSD ratios are 1.0.
This passes the frozen guard across 75,468 cells per side.

Native regressions first failed on the control's RGB values, then passed with
explicit encoded source colors and engine gamut conversion. The source-component
contract, output tags, independent Core Graphics conversion reference, alpha and
coverage, linear composition, active ground, and inherited character fallback
are covered by `RenderColorSemanticsTests`. NaN/infinity engine probes did not
reproduce the review's conditional conversion-trap concern.

### Integration test contract

Correcting Generic RGB interpretation changes mid-gray neutrals as well as
non-neutral colors. The bloom test now uses an independent conversion of its old
physical gray stimulus, leaving bloom strength, radius, and every assertion
threshold unchanged.

The horizontal gradient's total MSSIM fell from 0.07575288421475966 to
0.06950675148949562, below its former 0.07 floor; the diagonal score moved from
0.07237566291470883 to 0.07008130072440694. An independent remap reproduces the old
interpretation on the fixed renderer and matches the control's complete raw pixel
hash and score **exactly** for both fixtures. The result package retains the probe
and measurements. This attributes the drop to the intended tone correction on
these fixtures.

The structure tests now compare the original full-color result against the same
cells in reverse row/column order. They require a strict win and retain the
`blank + 0.03` margin, identity check, and high-frequency-loss control. The new
contract detects incorrect arrangement and blank collapse; it removes the
absolute total-fidelity floor and is weaker against gradual fidelity loss. Native
color checks and inspected goldens cover tone/color. No benchmark thresholds or
snapshot tolerances change. This is a correctness fix, not a universal quality
improvement claim.

### Review and limits

Independent review found no required production correction. The inherited
character fallback engine test and clipping documentation close its small
coverage/documentation observations. Per-call gamut conversion cost is unmeasured;
no performance improvement is claimed. The existing split in literal Generic RGB
mask paint interpretation across sync/effects paths is tracked separately in
ASKI-98. Explicitly named caller colors keep their own source spaces.

### Final validation and pause point

The full local `just check` passed on the final production and test contents:
1,449 core tests, 156 serial media tests, and two isolated deadlock sentinels
(1,607 total), plus format, build, research registry, repo-map, and DocC checks.
The separate snapshot/golden run passed all 53 tests after inspecting and
replacing 61 PNG references and the G0 byte reference. Two DocC mask-ground
examples were regenerated from their existing canonical test; the mask asset
itself is unchanged. The result package records asset hashes and alpha attribution.
The final status/validation text was added afterward and the research registry
was regenerated and checked again; production and test file hashes were unchanged.

This completes ASKI-3 on `fix/aski-3-render-color-space`, above the existing
`batch/aski-current-2026-11-05` draft PR15 (ASKI-8, ASKI-83, ASKI-97). The control
checkout and local execution logs are retained. No follow-up implementation has
started. Review this branch against the PR15 branch to keep the two batches
separate. Work pauses after committing and pushing this layer.

### Review repairs and re-record — 2026-11-06

Review repairs followed the census. They change raster and CLI color construction only:

- The CLI's `--background`, `--mask-fallback-color` and `--mask-ground` colors, and
  the HDR lab's `--background-hex`, are built in sRGB instead of Generic RGB.
  Before, `aski render --background "#808080"` wrote `#929292` pixels while its
  manifest recorded `#808080FF`.
- `AskiRenderEngine` gamut conversion and attributed-string color resolution use
  the relative colorimetric intent. Core Graphics clips out-of-gamut values for
  the matrix sRGB and Display P3 profiles, and every intent gave identical
  components on the re-record host, so output did not change.
- The literal Generic RGB mask-paint check compares against the color-space name
  that `CGColor(red:green:blue:alpha:)` produces, read once. It no longer uses a
  string literal. Behavior is unchanged.
- DocC and README examples tag their colors as sRGB.

Regression tests cover the first two items. A CLI render test decodes the
written PNG for gray, non-neutral and mask-fallback colors. An engine test
converts Display P3 colors that lie outside sRGB to sRGB output and compares
them with Core Graphics' own relative colorimetric conversion. Both tests failed
against a temporary revert of their fix. `review-repairs.patch` and the
`review_repairs` entry in `source-sha256.json` in the
[result package](Results/2026-11-05-aski3-color-semantics/README.md) identify
these source changes. `production.patch` still identifies the census code.

None of these repairs touches glyph selection, sampling or the conversion color
path that the `selection-ceiling` instrument scores. The census therefore still
describes this code and was not rerun.

The branch then merged the base that withdraws the ASKI-97 re-baseline. The
control's macOS 27.0.1 render baseline mentioned above is no longer current, and
ASKI-97 is open again. Fifteen CoreImage-path references were re-recorded with
`SNAPSHOT_TESTING_RECORD=failed`. The two DocC mask-ground assets were
regenerated together with `ASKI_RECORD_MASK_GROUND_DOCC=1` and stay
byte-identical to their test references. The re-record host was macOS 27.0.1
(26A434), Xcode 27.0 (27A266a) and Swift 6.4 on an Apple M3 Max. That is the
host on which the restored original goldens pass. Two later non-recording
snapshot runs passed every test. Against the original goldens, each re-recorded
image changes by the same pixel counts and maximum channel deltas as the census
review recorded, with at most two pixels' difference. Against this branch's
earlier recordings, each differs by at most one 8-bit step, with alpha
unchanged. That is the host-dependent drift ASKI-97 documents.
`golden-deltas.csv` now uses the base's original goldens as `before`.
Exact rasters remain host-dependent, as ASKI-78 tracks.

Core Graphics contract references: Apple's
[component constructor](https://developer.apple.com/documentation/coregraphics/cgcolor/init(red:green:blue:alpha:)),
[explicit-space constructor](https://developer.apple.com/documentation/coregraphics/cgcolor/init(colorspace:components:)),
and [color conversion API](https://developer.apple.com/documentation/coregraphics/cgcolor/converted(to:intent:options:)).
The native measurements above establish Aski behavior on the recorded toolchain.
