---
title: "ASKI-108 — near-white boundary inspection"
slug: 2026-11-14-aski108-near-white-inspection
date: 2026-11-14
status: complete
subsystem: [shape-context]
summary: "A visible cutoff is supported in the Lovell portrait sky under the frozen Vesper preset. The two line diagrams do not establish a gradient cliff. Native render pairs, exact zero-query boundaries and a passing diagnostic are retained. Shipping behavior is unchanged; a separate lab-only opacity-taper arm is specified for future evaluation."
datasets: [docs/Research/Corpus/nasa-occupancy-v1]
next_action: "ASKI-111 evaluates the frozen lab arm below; do that before proposing any shipping change. Keep near-white regions as ground."
---

# ASKI-108 — near-white boundary inspection

**Verdict: a visible cutoff is supported in the portrait sky.** This is the lead
AI reviewer's scoped visual assessment, not an owner or blinded human assessment.
It closes the requested inspection and proposes a future lab arm. It does not
change the shipping matcher, preset, or the prior decision to keep near-white
regions as dark ground.

The [inspection protocol](../../Scripts/research/aski108-2026-11-14/PROTOCOL.md)
and executable were committed at
`bc0e31feb3e45e6ff03c26619ee0b9bdafc4e359` before capture. The wrapper built a
release executable from an archive of that commit. It used the three named NASA
fixtures at native source size and the unmodified canonical Vesper preset.
Capture exited 0 on macOS 27.0.1, Xcode 27.0, Swift 6.4, arm64.
[Results and replay](Results/2026-11-14-aski108-near-white/README.md) retain the
source/render pairs, mask PNGs, exact Float32 descriptor lanes at every candidate
edge, geometry, source hashes and logs.

## What was observed

The reviewer viewed each original and canonical image before opening its mask and
CSV. The instrument's independently rendered SPI grid matched the canonical PNG
and its pixel layout/provider bytes for all four captures. Masks therefore refer
to the grid that produced the inspected image.

| Fixture | Grid / candidate adjacencies | Visual assessment |
| --- | --- | --- |
| RCS function diagram | 76×27 / 472 | Abrupt glyph/ground transitions follow lettering and the hard module/arrow contours. No supported smooth-gradient cliff in this pair. This does not assess overall shape fidelity. |
| Spacecraft attitude diagram | 76×27 / 718 | The title, left module outline and lower contours explain the inspected transitions. No supported smooth-gradient cliff in this pair; the source is mostly white field and hard black lines. |
| James Lovell portrait | 76×45 / 245 | The left part of the smooth sky becomes a large charcoal region with a stepped edge against bright horizontal glyph runs. The source has no matching hard sky contour. This is the supported visible cliff. |

Coordinates below are zero-based `(row, column)`. Selected **zero/space →
nonzero/glyph** pairs in the portrait CSV are `(0,26)→(0,27)`,
`(3,25)→(3,26)`, `(5,30)→(5,31)` and `(6,30)→(6,31)`.
The last two cover source rectangles approximately `x=384.87…410.53`,
`y=142.22…170.67` and `y=170.67…199.11`. These are smooth sky regions, clear
of the hair and tower. The row-5 render starts its bright run near `x=521`,
against the dark region to its left. The whole native pair, rather than a
contrast-enhanced crop, supplies the visibility evidence.

For comparison, diagram edges `(7,26)→(7,27)` and `(10,24)→(10,25)` in RCS,
and `(6,7)→(6,8)` and `(14,9)→(14,10)` in the attitude diagram map to black
module contours on white. They establish query transitions, not a new gradient
artifact. All zero endpoints are spaces. Some nonzero endpoints are also spaces;
query transitions must not be counted as visible edges automatically.

The diagnostic ramp passed. Its middle row has last nonzero ink at column 45,
a nonzero space at 46, and zero-query spaces starting at 47. There are 34
zero/nonzero adjacencies. The canonical diagnostic visibly cuts from bright bars
to charcoal as its source approaches white. It validates transition detection;
only the three NASA fixtures determine the fixture verdict.

The nominal 0.95 cutoff acts on each admitted sample in the resolved RGBA8
lattice. The SPI records post-histogram zeros, not pre-threshold luma or the
margin of each sample to the cutoff. At the selected sky pairs adjusted OKLab L
is 1 on both sides; that field is not the cutoff's luma. The evidence supports
an abrupt zero-query boundary aligned with a smooth source gradient. It does
not identify a particular sample's luma, measure perceptual severity, or show
that all visible defects in these renders arise from this threshold.

## Pre-registered future lab arm: taper existing ink toward ground

**Proposed only; no treatment has been implemented or measured.** The control is
`bc0e31f`'s canonical preset and its existing admitted-weight cutoff of 0.05.
All fixtures, decoding, sampling lattice, descriptor, glyph selection, palette,
font, background and render settings remain fixed. No new production option or
public API is authorized by this note.

Uniformly reducing a descriptor's weights can disappear during histogram
normalization. Therefore this arm leaves the descriptor and selected glyph
unchanged and varies only the existing cell ink alpha after matching:

1. For each cell, obtain the same inverted Rec.601 sample weights `w` used by
   the frozen query, over the same footprint/annulus sample indices before the
   `w < 0.05` rejection. Use the existing Float arithmetic and resolved raster.
2. If the control query is zero, retain the control space and alpha exactly.
   Otherwise let `m` be the maximum of those sample weights and set
   `t = clamp((m - 0.05) / 0.03, 0, 1)` and `gain = t*t*(3 - 2*t)`.
3. Multiply the control cell alpha by `gain`. Render with the unchanged charcoal
   background and existing renderer. No neighbor mixing, glyph replacement,
   threshold lowering, alternative width or parameter sweep is allowed.

The gain is zero at 0.05, one at 0.08, and continuous between. It can remove ink
from a formerly nonzero cell; it cannot introduce ink into a control zero-query
cell. A cell containing a stronger dark sample stays unchanged. This is a
hypothesis for reducing the sky cliff, not evidence of a quality improvement.

Before reading any treatment result, commit its implementation and verify:

- Independent arithmetic cases `m=0.05, 0.065, 0.08` produce gains `0, 0.5, 1`
  within Float tolerance. A nonzero-glyph diagnostic must produce distinct
  pixels at half gain, so a normalization no-op cannot pass.
- The captured gray ramp produces a changed transition band with the white end
  still ground. Existing near-white ground tests and flat white/near-white
  images pass. Every control zero-query cell stays a space, no cell gains alpha,
  and every cell with `m >= 0.08` retains its control state exactly. Any violation
  kills the arm before fixture scoring.
- Freeze native paired views of the four named portrait sky sites above, with
  randomized side labels and a saved private key before review. A reviewer must
  select less abrupt transitions for the treatment at all four sites without
  consulting the key; any tie or disagreement is inconclusive.
- Hold out every other asset in `nasa-occupancy-v1` at `bc0e31f` (21 assets).
  Paired, blinded review must find no new loss of subject/line legibility or
  distracting halo in any held-out fixture. Any confirmed regression kills the
  arm. Publish per-fixture assessments and the unblinded key with the verdict.
- Before promotion, run the required before/after selection-ceiling MAE and GMSD
  census on both frozen naturals corpora. Reject any corpus with either ratio
  above 1.01; disagreement in oracle direction is inconclusive under the standing
  methodology. Check the oracle on an all-blank known-failure render first; if
  it cannot distinguish that failure, its apparent improvement cannot support
  promotion. Preserve the visual decision and all numeric results separately.

A passing lab result would still need a concrete shipping decision and the
frozen-preset golden/no-harm evidence in its own PR. A KILL result would remove
the treatment implementation and retain the protocol and result artifacts.
