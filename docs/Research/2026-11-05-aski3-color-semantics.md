---
title: "ASKI-3 — color interpretation correction and frozen-selection guard"
slug: 2026-11-05-aski3-color-semantics
date: 2026-11-05
status: active
subsystem: [color-science, tile-grid]
summary: "Pre-registered checks for correcting Generic RGB reinterpretation of encoded sRGB/Display P3 cell colors and engine gamut retagging. Native non-neutral pixel regressions decide color correctness. A paired frozen-selection census guards glyph selection; it cannot establish color fidelity. No census results have been read."
related_specs: [Sources/Aski/ASCIICell.swift, Sources/Aski/Tiles/TileCell.swift, docs/agents/research-methodology.md, docs/Research/2026-09-02-aski-31-lattice-no-harm.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1, docs/Research/Corpus/nasa-occupancy-v1]
runners: [AskiColorLab]
results: []
next_action: "Run the frozen control and corrected renderer after this rule is committed; retain per-side CSVs, hashes, native color checks, and any changed golden images."
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
