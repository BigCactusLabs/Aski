---
id: ASKI-15
title: Investigate full-color desaturation vs June-era converter output
status: To Do
assignee: []
created_date: '2026-08-19 03:49'
updated_date: '2026-09-16 17:37'
labels: []
dependencies:
  - ASKI-3
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rendering the committed Carina corpus image with the current build (xcrun swift run AskiDemo docs/Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg --columns 512 --font-size 16) yields mean saturation ~0.45 across the PNG, where a June 2026 build of the exact same command produced ~0.76 at equal mean brightness (~0.07). Grid geometry is identical (133x512) but 43.5 percent of glyph picks differ. The June render is committed as the README hero (docs/assets/hero-carina-512.png); the current build cannot reproduce it. Suspects: color-pipeline changes landed between June and August (gamut mapping, render color space, area-weighted luma resample fidelity fix).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Root-cause the saturation drop with a bisect or instrumented A/B on the Carina corpus image, separating glyph-pick drift from per-cell color drift
- [ ] #2 Settle keep/revert/knob with a pass rule frozen before the decisive measurement
- [ ] #3 If current-build vibrancy is restored, regenerate the README hero from a clone and add the verbatim-reproducibility claim back to its caption
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24 (deep pass): Repro-command drift: swift run AskiDemo still resolves (contrary to comment #1), but PNG output now needs --render-png <path> and preserveAspect defaults true — pin --no-preserve-aspect to reproduce the June 133x512 baseline. No color-path commit since June touches saturation; defect presumed still live.

### Implementer context — 2026-09-10 (base 952529a)

**Current state.** This remains an investigation. Current `ASCIIConverter` defaults are linear-light averaging, OKLab Euclidean palette matching, Ray Trace gamut mapping, sRGB, and encoded display composition. The changelog records the linear-light default in v0.3.1 and Ray Trace default in v0.4.0; the v0.6 ASTSK-50 change says its LUT/traversal optimization preserved output. The local public history starts at v0.6.0, so the June-era implementation is not a local bisect base. The backlog's Carina saturation and glyph-difference observations still need a controlled reproduction; this inspection did not measure them.

**Start here.** Trace `ASCIIConverter.prepareConversion` through `samplingLattice`, `ConversionContext.sampledCellColor` (private, in `Sources/Aski/CellSampling.swift`), `cellSourceStats`, and `finalizeColor`. Compare each cell's selected character before comparing `ASCIICell.displayColor`; this separates glyph-selection drift from per-cell color drift. Use `ImageRenderer.renderImage` and the CLI parser to hold output geometry constant. The current CLI surface is `swift run aski render ... --render-png ...`; CLI parsing defaults `preserveAspect` to true while the library renderer defaults `preserveSourceAspect` to false. Pin `--no-preserve-aspect` for the 512-column by 133-row comparison.

**Constraints and dependencies.** `AskiDemo` remains a compatibility product; use `aski render` for new commands and include the explicit PNG output and aspect flags. Freeze the pass/revert/knob rule before the decisive measurement. Test suspected policy knobs independently (encoded versus linear sampling, gamut mapping, palette policy, and render space) while holding the exact lattice fixed. A README hero rewrite is downstream: regenerate it only after an evidenced improvement and retain a reproducible caption. Do not infer a color cause from the selection-ceiling or polarity work.

**Validation to run.** Create a pre-measurement A/B table, then record output dimensions, character sequences, per-cell display colors, and saturation/brightness summaries for the current Carina command and each policy arm. Reuse the existing sampler parity tests and compare against `docs/assets/hero-carina-512.png`. A decisive result must identify whether glyph picks, display colors, or both moved; no single aggregate saturation number can do that.

**First step.** Write the frozen measurement rule and clone the current hero command into a dated result directory. Use the committed hero PNG as the image baseline. Verify its historical command and build provenance before claiming an exact reproduction; the June source tree is not in the local public history.

Source map: `CHANGELOG.md`, `Sources/Aski/ASCIIConverter.swift`, `Tests/AskiTests/AskiColorLabSamplingPoliciesTests.swift`, `Tests/AskiTests/AskiDemoTests.swift`, `Sources/Aski/Renderers/ImageRenderer.swift`, `README.md`.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-08-21 02:13
---
Repro-command update: after PR #19 (aski executable product), 'xcrun swift run AskiDemo <image> ...' no longer resolves — the AskiDemo target is published as the 'aski' product. Equivalent command once #19 merges: xcrun swift run aski render docs/Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg --columns 512 --font-size 16 (or 'swift run aski <image> ...' via the default subcommand). Conversion behavior is unchanged by the CLI move; the June-vs-August comparison stays valid.
---
<!-- COMMENTS:END -->
