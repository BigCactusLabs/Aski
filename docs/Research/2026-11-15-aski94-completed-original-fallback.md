---
title: "ASKI-94 completed original-image fallback rule"
slug: "2026-11-15-aski94-completed-original-fallback"
date: "2026-11-15"
status: "active"
subsystem: [meta]
summary: "Register an exact-parity test and paired render benchmark for drawing the grounded original-image fallback once through the populated-cell clip."
next_action: "Run native parity and five release pairs if parity passes."
related_specs: [docs/agents/paired-benchmarks.md, docs/benchmark-validation.md]
---

## Question and treatment

Can a single original-image draw reduce the cost of the inactive branch of a
grounded ASCII render? The control at
`fee0e5e61a1a7b964e9a7fafe2ee537055d8392b` draws the same sized image once per
populated cell in `ASCIIGrid.drawMaskFallbackOverlay`. The candidate makes the
same cell rectangles and clips to their union. It draws once at alpha 1, with
the same sizing rectangle and context state. An empty clip needs zero draws.
The candidate diff must leave the existing variable-coverage loop and all
non-image switch arms byte-identical to the control. Check this in diff review.

Core Graphics documents the clip as the region within an array of user-space
rectangles. That establishes the geometry of the operation. It leaves shared-edge
pixel composition at fractional coordinates to the native test.
[Apple CGContextClipToRects reference](https://developer.apple.com/documentation/coregraphics/cgcontextcliptorects)

## Exact parity

Both arms use the same [case manifest](../../Scripts/research/aski94-2026-11-15/parity-cases.json).
It crosses sizing, mask edges, gamut, composition, ground, scale and exact-width
routes, source aspect, and rectangular and ragged geometry. Extra cases exercise
opaque and transparent canvases, an opaque source and ground, P3-to-sRGB, one
populated cell, and all-empty rows. An all-empty grid has zero columns, so the
renderer returns the 1×1 sentinel before reaching the completed branch. The export
asserts those dimensions. Source-aspect and width-97 cases exercise fractional
device edges. In each checkout use a fresh absolute directory whose parent
exists. Capture the control twice to qualify repeatability before comparing
the candidate.

```bash
ASKI94_PARITY_OUTPUT="$capture" xcrun swift test -c release --no-parallel --filter ASKI94FallbackParityTests
python3 -B Scripts/research/aski94-2026-11-15/compare_parity.py "$control" "$control_repeat"
python3 -B Scripts/research/aski94-2026-11-15/compare_parity.py "$control" "$candidate"
xcrun swift test --no-parallel --filter 'MaskFallbackGroundworkTests|RaggedASCIIGridTests|ImageRendererMaskTests|MaskSnapshotTests'
```

The comparator checks the complete registered inventory, native metadata and
active raster bytes, without color conversion. A difference between the two
control captures invalidates the parity run and leaves the result inconclusive.
With a repeatable control, an exact candidate mismatch rejects the treatment.
Invalid or missing evidence is inconclusive. A rejected parity arm retains a
replayable patch and mismatch evidence. Capture a control-only
release baseline for the 27 workloads and record which comparative
measurements the veto prevented. No frozen-reference golden may move.

## Release decision

Use the literal `aski94` selection in the
[shared workload inventory](../../Scripts/research/rendering-groundwork-workloads.json).
Require all 27 workloads and all four metrics in every capture. Run
`Scripts/validate-benchmarks.py` with `--filter '^aski94-.*$'`, `--expect` for
each listed ID, and `--require-metric` for `cpuTotal`, `mallocCountTotal`, and
`peakMemoryResident`. The adapter requires `wallClock` by default. Qualify each
arm separately and verify inventory equality, Release, toolchain, dependency locks,
export units and observed allocator before recording decision pairs.

Pair distinct clean revisions serially on one quiet physical Mac with the same
configuration and identical benchmark support. Freeze SHAs, full inventory and
rule reference in the paired manifest. Run five adjacent pairs in control-first,
candidate-first, control-first, candidate-first, control-first order. Use the
median of the five per-pair percentage changes between run medians. Retain
every capture, including failures or noise, without replacing pairs.

- Each of the nine grounded original-image workloads needs at least 5% render
  wall-time improvement. The nine variable-coverage originals and nine other
  fallback controls permit at most 3% wall-time regression per workload.
- Each of the 27 workloads permits at most 3% regression each in CPU time,
  native allocation calls and sampled absolute workload-process peak RSS.
  The reviewed interposer counts measured allocation calls. RSS includes
  process residency outside the render and sampling can miss transient peaks.
  Neither metric assigns deltas to individual calls in the clip.
- Require the median and at least four of five pairs to pass each bar. A failing
  median with at least four pairs on the failing side makes the arm unsupported
  and rejects it. Other threshold straddles, contention, unavailable metrics,
  incomparable captures, and incomplete pairs are inconclusive.
- The source-derived draw census for the 80, 160 and 320 column workloads is
  1,600 / 6,400 / 25,600 in grounded control and one each in grounded candidate.
  The overlays count 1,200 / 4,800 / 19,200 and the other fallbacks count zero
  original-image draws in both arms. For this arm the exact source-derived count
  replaces the diagnostic call census in the
  [rendering groundwork guidance](../agents/rendering-groundwork.md).
  The literal grid has columns/4 rows of populated cells. The completed control
  loop draws once per cell, and the candidate draws once after clipping the
  nonempty list. The variable-coverage loop skips the quarter of cells with
  coverage 1. These fixed paths and workload dimensions determine the number of
  source-image draw invocations per render. Runtime traces and framework raster
  work are outside this census.

Adoption requires exact parity and the draw census, all registered decision bars,
`just check` and the separate mask/render benchmark compatibility capture
(`masked-ascii-convert-80cols-transparent-fallback`,
`masked-ascii-convert-render-80cols`, `masked-effects-render-solid-fallback`,
and `render-image-gradient-80cols`). Keep the complete paired reports and failed
cells after a rejection. Record the disposition alongside the registered rule.
