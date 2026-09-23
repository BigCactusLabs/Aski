---
title: "Oversample factor for log-polar shape-context cells"
slug: 2026-05-05-oversample-shape-context-cells
date: 2026-05-05
status: complete
subsystem: [shape-context]
summary: "Why oversample = 2 gates Aski's edgeEmphasis Sobel path out at default settings, and what shape-aware ASCII pipelines do for per-cell sampling resolution. Plan amended to expose oversample as a converter init parameter so callers can opt into a working Sobel path, with the default unchanged to preserve pre-A1 bit-identity."
---

# Oversample factor for log-polar shape-context cells

**Date:** 2026-05-05
**Triggered by:** A1 plan, Task 14 — `renderingOptionsAffectOutput_edgeEmphasisChangesLogPolarMatching` produced 0 differing cells through the converter, even with the edgeEmphasis option correctly threaded into `LogPolarKernel`.
**Outcome:** Plan amended with a follow-up task — expose `oversample` as a converter init parameter so callers can opt into a working Sobel path. Default unchanged to preserve the pre-A1 bit-identity gate.

## Question

`ASCIIConverter.convert(_:columns:)` thumbnails the source to `max(columns, rows) * oversample` pixels with `oversample = 2` hardcoded, then carves it into cells. At typical column counts on representative inputs this produces `cellWidth = 2`. `LogPolarKernel.sobelMagnitude` has a `guard w >= 3, h >= 3` short-circuit, so the `edgeEmphasis` blend never fires through the converter at default settings. The option is wired but structurally dead.

Two things to learn before deciding:
1. What does the field do for per-cell sampling resolution in shape-aware ASCII pipelines?
2. Is the `oversample = 2` default a real bug, or is the deadness intentional (e.g., reserved for a future `algorithm: .logPolarHD` mode)?

## What the field says

### Foundational paper

[Xu, Zhang, Wong — *Structure-based ASCII art* (ACM SIGGRAPH 2010)](https://dl.acm.org/doi/10.1145/1833349.1778789) is the source the project's own `ASCIICharacterSet` docstring cites as its baseline. Their pipeline computes the log-polar shape context **per-glyph at the glyph's native font cell size** (rasterized at the resolution the glyph will be rendered at), not on a thumbnail-shrunk tile. The matching tile from the source image is then aligned to that resolution. The descriptor is computed on dense raster support.

Practical implication for Aski: the canonical convention is to *not* downsample the per-cell raster below the glyph's natural sampling resolution. Aski's hardcoded `oversample = 2` does exactly that, and the consequence (Sobel guard tripping, `edgeEmphasis` going dead) is downstream of that mismatch.

### Canonical descriptor parameters

[Belongie & Malik — *Matching with Shape Contexts* (NeurIPS 2000)](https://proceedings.neurips.cc/paper/1913-shape-context-a-new-descriptor-for-shape-matching-and-object-recognition.pdf) and the [Wikipedia summary](https://en.wikipedia.org/wiki/Shape_context) confirm the 5 radial × 12 angular = 60 bin layout Aski uses is the canonical default, but neither prescribes a minimum cell pixel size. The descriptor needs enough non-zero sample points for the histogram to have signal; on a 2×N raster that signal is dominated by single-pixel placement noise.

### Most recent practitioner deep-dive

[Alex Harri — *ASCII characters are not pixels: a deep dive into ASCII rendering*](https://alexharri.com/blog/ascii-rendering) (published **January 2026**, the most recent serious treatment of structure-aware ASCII rendering we located). Two quotable signals:

- "Pick a sampling quality of [N] with the samples placed like so" — Harri's final pipeline uses **9 samples per cell** placed in a fixed pattern. He explicitly rejects "more samples → mean lightness" as the wrong axis for shape-aware rendering.
- "Increasing the number of samples is insufficient. No matter how many samples we take per cell, the samples will be averaged into a single lightness value, used to render a single pixel."

He's making a different point (sparse-sample shape descriptors beat dense brightness averaging), but the architectural premise overlaps: meaningful per-cell features need richer per-cell information than a 2-pixel-wide raster can carry.

### Sobel kernel size baseline

[Sobel operator (Wikipedia)](https://en.wikipedia.org/wiki/Sobel_operator) and [OpenCV's Sobel docs](https://docs.opencv.org/4.x/d2/d2c/tutorial_sobel_derivatives.html) confirm the standard 3×3 kernel as the minimum useful size; OpenCV explicitly notes "When the size of the kernel is 3, the Sobel kernel ... may produce noticeable inaccuracies" and offers Scharr as a more accurate alternative at the same size. Aski's `LogPolarKernel.sobelMagnitude` correctly guards `w >= 3, h >= 3` — that guard is right; the bug is upstream where cellWidth ends up as 2.

### Prior art in the wild

A survey of open-source image-to-ASCII projects active in 2025–2026 gives a convergent rather than
authoritative signal: most map brightness only, and where Sobel-style edge detection appears at all,
it operates on the **full image** — never on a 2px per-cell sub-thumbnail. Aski's choice to compute Sobel inside the cell is more aggressive than typical practice, which makes the `oversample` undersizing more impactful here than it would be in a "Sobel on full image" pipeline.

## What we picked, and why

**Decision:** Add an `oversample: Int = 2` init parameter to `ASCIIConverter`. Default unchanged. Document the relationship to `edgeEmphasis` in DocC. Add a converter-level wiring test at `oversample = 4`. Track as Task 17 in the A1 plan, sequenced after Task 16.

**Why we didn't flip the default to 4:**

- Task 1 of the A1 plan froze a `CharacterizationTests` golden specifically to gate against drift in default-converter output. Bumping `oversample` to 4 changes per-cell averaging, shape-context mass, and picked glyphs across the board — it would re-pick a non-trivial fraction of cells and force re-recording every snapshot in Task 15. That's a behavioral break dressed up as a bug fix.
- The frontier evidence (Xu/Zhang/Wong glyph-native, Harri 9-sample) supports a *higher* per-cell sampling budget than 2, but doesn't pin a specific number. Picking 4 over 8 over glyph-native would itself be a judgement call, not a fact lookup.
- The current behavior at `oversample = 2` isn't broken for the default `.logPolar` path with `edgeEmphasis = 0` (the path the golden was captured under). It's only broken for the opt-in `edgeEmphasis > 0` case. Putting the fix behind an opt-in matches the blast radius of the bug.

**Why we didn't auto-tune `oversample` from `(algorithm, edgeEmphasis)`:**

- It would change behavior implicitly (set `edgeEmphasis = 0.1` and the whole pipeline silently uses different cell sizes), which is the kind of magic that bites later.
- Documentable as an A1.5 follow-up if the manual knob proves annoying.

**Why we didn't drive `oversample` from `characterSet.shapeVectorDimension`:**

- That mirrors Xu/Zhang/Wong's "rasterize at native cell size" convention but couples a sampling decision to a descriptor-layout constant. The shape vector is 60 floats regardless of the source raster size; the two aren't actually proportional. It would feel principled and not be.

## Sources

**Primary:**

- [Structure-based ASCII art — Xu, Zhang, Wong (SIGGRAPH 2010)](https://dl.acm.org/doi/10.1145/1833349.1778789)
- [Matching with Shape Contexts — Belongie & Malik (NeurIPS 2000)](https://proceedings.neurips.cc/paper/1913-shape-context-a-new-descriptor-for-shape-matching-and-object-recognition.pdf)
- [Shape context — Wikipedia](https://en.wikipedia.org/wiki/Shape_context)

**Practitioner deep-dives:**

- [Alex Harri — *ASCII characters are not pixels* (Jan 2026)](https://alexharri.com/blog/ascii-rendering)
- [Exploring Structure-based ASCII Art — Gettysburg College summer research blog](https://xsigsummer.wordpress.com/2023/06/10/exploring-structured-based-ascii-art-the-process-behind-shape-matching/)

**Reference / sanity-check:**

- [Sobel operator — Wikipedia](https://en.wikipedia.org/wiki/Sobel_operator)
- [OpenCV — Sobel Derivatives tutorial](https://docs.opencv.org/4.x/d2/d2c/tutorial_sobel_derivatives.html)
