---
title: "ASKI-15 — Carina hero saturation is not a converter regression"
slug: 2026-11-07-aski15-hero-provenance
date: 2026-11-07
status: complete
subsystem: [color-science, meta]
summary: "The README hero's higher saturation is not reproducible from any converter build. Nineteen builds from 2026-06-08 through the ASKI-3 fix all give the same per-cell chroma, which matches the source image's own per-cell chroma; the old hero has about 1.9x that chroma at the same hue plus a 17% pure-black floor, the shape of an outside saturation and black-point adjustment. The only glyph change since June is the ASKI-65 lattice correctness fix. Verdict: keep current behavior; the hero is regenerated from the current build with a recorded command."
related_specs: [README.md, Sources/Aski/CellSampling.swift, docs/Research/2026-11-05-aski3-color-semantics.md, docs/agents/research-methodology.md]
datasets: [docs/Research/Corpus/nasa-occupancy-v1]
results: [docs/Research/Results/2026-11-07-aski15-hero-provenance]
next_action: "None for ASKI-15. A higher-vibrancy rendering option would be a new pre-registered research arm, not a fix."
---

# ASKI-15 — Carina hero saturation is not a converter regression

## Question

ASKI-15 recorded that the current build renders the Carina corpus image with mean
saturation about 0.45, while the README hero, described as a June 2026 render of the
same command, measures about 0.76. The task asked whether glyph picks, per-cell color,
or both had drifted, and whether to keep, revert, or add a knob.

## Method

- **Metric.** The task's 0.76 / 0.45 figures have no recorded definition. The closest
  reproduction is HSV saturation and value averaged over the PNG box-downsampled to the
  512 × 134 cell grid ("cell-grid S/V"): 0.736 / 0.080 for the old hero, 0.474 / 0.072
  for public main. Per-cell comparisons use OKLab chroma of each cell's ink (pixels with
  V ≥ 0.5 × the cell's maximum V).
- **Builds.** Nineteen builds were rendered with the documented command
  (`--columns 512 --font-size 16`, aspect preserved, PNG output): seventeen from
  pre-public history (2026-06-08 through the 2026-09-23 cutover state, including
  v0.6.0), public main `dbfec3a`, and the ASKI-3 fix. Pre-public builds are labeled by
  date in the results; their commits are not in this repository.
- **Anchor and classes.** The anchor is a 2026-06-29 build. Thresholds were fixed before
  any bisect row was computed: a build is *hero-like* if its same-glyph median chroma
  ratio against the anchor is ≥ 1.5 or its black floor (cells whose ink max channel is
  ≤ 5/255) is ≥ 10%; *anchor-like* if the ratio is within [0.9, 1.1] and the black floor
  is within 2 points of the anchor.
- **Hero glyphs.** No hero text file exists, so hero glyphs were recovered by template
  matching against a current render (self-recovery error 0.23–0.30% on inked cells).

Host: Apple M3 Max, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4.

## Results

Full table: [bisect.csv](Results/2026-11-07-aski15-hero-provenance/bisect.csv).

| Build | Glyph diff vs anchor | Same-glyph chroma ratio | Black floor | Cell-grid S |
|---|---|---|---|---|
| Old README hero | 32.9% | **1.93** | **17.0%** | 0.736 |
| All builds 2026-06-08 → 2026-09-01 (incl. v0.6.0) | 0–0.02% | 1.000 | 0.74% | 0.472 |
| ASKI-65 lattice fix (2026-09-02) → public main | 55.7% | 1.010 | 0.77% | 0.474 |
| ASKI-3 fix | 55.7% | 1.001 | 0.77% | 0.511 |

1. **No build reproduces the old hero.** Every build is anchor-like; none is hero-like.
   The builds from June through v0.6.0 produce one byte-identical PNG (one early build
   differs by 17 glyphs), and that PNG is not the hero.
2. **Current color matches the source.** The source image's own per-cell linear-light
   mean chroma is 0.071; the current `displayColor` mean chroma is 0.0712. The old hero's
   ink chroma is 1.69× the source's per cell. An affine encoded-RGB fit from the anchor
   to the hero has diagonal gains of 1.5–2.3, negative off-diagonals, and negative
   offsets: a global saturation boost plus a lowered black point. Median hue shift is
   under 2°.
3. **The only glyph change is ASKI-65.** Before the ASKI-65 fix, the sampler read only
   the top 536 of the thumbnail's 593 rows, so the bottom 9.6% of the image was never
   sampled. The fix resamples the whole thumbnail, which re-registers every grid row
   and changes 55.7% of cells. It is a correctness fix and does not change chroma.
4. **No exposed policy lever reaches the gap.** Encoded sampling, gamut mapping (clip,
   adaptive, ray trace; inactive for sRGB → sRGB), Display P3 output, and the June-era
   ink pre-compensation, chroma-shape assist, contrast, and brightness knobs were probed.
   Contrast and brightness reproduce the black floor but not the chroma; none brings
   chroma near 1.9×.
5. **ASKI-3 changes raster encoding only.** Text and `displayColor` are byte-identical
   to public main. The PNG darkens mid-tones (cell-grid V 0.072 → 0.063), which raises
   HSV S without raising OKLab chroma.
6. **Task-note corrections.** The grid is 134 rows; `wc -l` reports 133 because the text
   has no trailing newline. The hero's 4916 × 2831 geometry needs aspect preservation
   (the CLI default), not `--no-preserve-aspect`.

## Verdict

**Keep.** There is no converter change to revert and no knob that recovers the old
hero's look; current output is faithful to the source's color. The likeliest origin of
the old hero is a pre-adjusted input or an unrecorded post-process. That cannot be
verified from either history.

The README hero is regenerated from the current build (ASKI-3 fix included) with:

```text
xcrun swift run -c release aski render docs/Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg \
  --columns 512 --font-size 16 --render-png docs/assets/hero-carina-512.png
```

Exact PNG bytes can differ by host (see the
[snapshot baseline](../../CONTRIBUTING.md#toolchain-and-snapshot-baseline)).

## Not done

- Unmerged branches and a macOS 26 render were not checked; neither history has them.
- A vibrancy option (for example coloring each glyph from only the pixels under its ink,
  or OKLab chroma scaling toward the gamut limit at constant hue) would need its own
  pre-registered arm and no-harm census.
