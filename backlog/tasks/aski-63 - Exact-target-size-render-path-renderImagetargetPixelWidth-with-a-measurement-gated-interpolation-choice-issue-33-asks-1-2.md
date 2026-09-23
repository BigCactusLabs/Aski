---
id: ASKI-63
title: >-
  Exact target-size render path: renderImage(targetPixelWidth:) with a
  measurement-gated interpolation choice (issue #33, asks 1-2)
status: Done
assignee: []
created_date: '2026-09-01 22:16'
updated_date: '2026-09-02 02:40'
labels:
  - rendering
  - research
dependencies: []
priority: high
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From GitHub issue #33 and the research note docs/Research/2026-09-01-issue33-target-size-render-and-lossless-webp.md. A retina web consumer needs an exact output pixel width (1166 px @1x, 2332 px @2x from a 384-column grid) and today renders at native size then resizes every frame with CGInterpolationQuality.high outside the API. Measured in the note: font size and the CG scale transform are pixel-identical for Aski's fonts (0 differing bytes on bundled Courier Prime and Menlo at every ratio tried, including 0.38), so an exact width is a closed-form scale, not a resize. The open question is glyph-edge quality: direct render at the derived fractional cell advance versus integer supersample plus area average. This task builds the entry point, pre-registers that two-arm measurement on the consumer's own grid, ships the winner, and documents the loser. Byte-identical default path: the existing scale-based renderImage and every PNG golden stay untouched. No default changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ASCIIGrid gains a target-width render entry point (name settled in the design addendum, e.g. renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:)) whose output width equals the requested pixel width exactly for every input tried, including widths that are not a multiple of columns; height derives from the grid aspect. The pixel width is set directly and the scale derived from it, so RenderPixelBounds ceil rounding cannot add a pixel. The existing scale-based path and all PNG snapshot goldens are byte-identical.
- [x] #2 Pre-registered before any run, in a thin design addendum: arm A = direct render at the derived scale with all four Core Graphics subpixel flags set explicitly (allowsFontSubpixelPositioning and shouldSubpixelPositionFonts true, both quantization flags false); arm B = integer-factor supersample then area average in linear light; reference = 8x supersample area-averaged in linear light; oracles = MAE first, GMSD guard, on the consumer's 384-column canyon grid at 1166 and 2332 px plus one built-in fixture at 80 columns; a periodic-grid column-banding probe (per-column ink mass on a uniform single-glyph grid) with a stated bound. Decision rule written down before the numbers exist.
- [x] #3 The winning arm ships as the implementation of the target-width entry point; the losing arm and the numbers are recorded in a verdict note under docs/Research/ with the results dir committed. If neither arm clears the banding bound the task returns INCONCLUSIVE with the failing clause named rather than shipping either.
- [x] #4 DocC (Aski.docc) documents, with the measurement cited, that pointSize times scale is the effective pixel size for monochrome monospaced fonts, that target width is a derived scale, which resample space and filter the target-width path uses, and that color fonts and optical-size axes are out of scope.
- [x] #5 aski render exposes the target width (flag name settled in the addendum, e.g. --width <px>) and the render manifest records target width, derived scale, cell advance and resample space; the command-surface golden and knob-docs drift guards are updated in the same commit.
- [x] #6 Consumer validation: the bcl-web canyon generator reproduces its 1166 and 2332 px assets through the new entry point with its own resize step deleted; a diff report (MAE and GMSD against the shipped frames) is recorded in the verdict note. Any regression is a finding, not a blocker.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-01 orchestrated on branch aski-63. Entry point renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:) (43f0baa, 3d77566); rule note docs/Research/2026-09-01-aski63-target-width-rule.md frozen b066564 (section 9 area-weighted probe re-registered after run 1 INVALID, no threshold changed); instrument AskiColorLab target-width-gate (88a97a7, a4dab58); run 1 INVALID + run 2 SHIP-B results committed; verdict commit 55312b8 routes public path to supersample 4x linear-light area average; verdict note docs/Research/2026-09-01-aski63-target-width-verdict.md (12d0522); aski render --width + manifest fields + goldens (aea70ec). AC#6 consumer validation running on bcl-web branch aski-63-target-width.

AC#6 done: bcl-web branch aski-63-target-width commit 72ad894; old path byte-identical to shipped stills, new path sharper, heights 775/1550 vs 777/1555 recorded as a finding in verdict note section 5.

Merged to main via PR #35 (c45be5c) on 2026-09-01. Codex review round: two P2s (linear-composition reducer branch; 4x width bound end to end) fixed in fe9686b before merge. Post-merge cleanup: worktrees and aski-63-cli branch removed; bcl-web branch aski-63-target-width left unmerged pending the owner's asset-regeneration decision.
<!-- SECTION:NOTES:END -->
