---
title: "ASKI-96 — Dither Veil mechanism read against Aski"
slug: 2026-11-24-aski96-dither-veil-mechanism-read
date: 2026-11-24
status: active
subsystem: [animation, frontier]
summary: "Read-only comparison for ASKI-96 AC#1. React Bits' Dither Veil (1eeb6f1) splits into eighteen parts. Aski already covers cell sampling, tone grade, Floyd–Steinberg diffusion, duotone output, and the photo under the veil. New: position-locked ordered tone thresholds (Bayer 8x8, void-and-cluster rank), a per-cell rank gate on mask coverage, and a rank-jittered hard-step reveal. Out of scope: pointer trail, shockwaves, rim band, background keying, per-channel RGB dither. The shipped dotMatrix control dithers at strength 0, and aski lab video cannot select dotMatrix; AC#2 must settle both."
related_specs: [docs/Research/2026-07-01-astsk45-source-tethered-hysteresis.md, docs/Research/2026-07-16-webgpu-frame-difference-ascii-motion.md, Sources/Aski/Aski.docc/Masking.md]
next_action: "AC#2: pre-register the control strength, the ordered-threshold arms and their glyph-ladder mapping, the still and motion corpus (with the video-lab algorithm and coverage flags this needs), and a decision rule over MAE, GMSD, glyph churn and dotMatrix walk time, using the questions in the last section. No arm is built or measured before that rule is frozen."
---

# ASKI-96 — Dither Veil mechanism read against Aski

## Purpose and scope

ASKI-96 asks whether two ideas from React Bits' Dither Veil transfer to Aski:
ordered (position-locked) thresholds for dotMatrix tone, and a rank-ordered
cell-by-cell reveal. This note completes acceptance criterion 1 only. It reads
the Dither Veil source at react-bits commit
[1eeb6f1](https://github.com/DavidHDev/react-bits/blob/1eeb6f105c68b964289d85dabbe84a1d551f3797/src/content/Animations/DitherVeil/DitherVeil.jsx)
(committed 2026-09-27, read 2026-11-24) against Aski at
`f3f7663fde1e269197cfe27265df44b4a0929805`, and classifies each part as
covered, new, or out of scope.

No arm was built, nothing was measured, and no production source changed. The
literature section states hypotheses for Aski, not findings. GitHub reports the
React Bits licence as `NOASSERTION` (repository metadata read 2026-11-24), so
this note describes the mechanism in its own words and copies no code. Bayer
matrices and void-and-cluster arrays are public algorithms; any arm builds them
from the cited papers.

## The mechanism, by part

Dither Veil is a single WebGL component. A still photograph is drawn on a grid of
square cells a few device pixels wide. Its parts:

1. **Cell lattice and sampling.** Each output cell reads the photo once at its
   centre from a mipmap level chosen so the read approximates the cell's average.
2. **Tone grade.** Luma (or each RGB channel) passes through contrast, brightness,
   and a fixed power curve of exponent 1.6.
3. **Bayer 8x8 threshold.** The 8x8 Bayer index is computed from the cell's
   coordinates modulo 8 by bit interleaving.
4. **Blue-noise rank threshold.** A 64x64 rank texture is built once on the CPU
   by void-and-cluster: a 10% random initial pattern, a Gaussian energy filter
   with sigma 1.5 over a wrap-around 13x13 neighbourhood, relaxation of the
   tightest cluster into the largest void until stable, then ranks assigned by
   removing points down to zero and adding points up to full.
5. **Engraving threshold.** A diagonal triangle-wave threshold of period six
   cells, perturbed slightly by the Bayer value, which renders tone as diagonal
   hatching.
6. **Error diffusion.** On the CPU, Floyd–Steinberg or Atkinson diffusion with a
   serpentine row order, computed once per still and cached under a key of the
   settings and canvas size. It is recomputed only when those change, never per
   frame.
7. **N-level quantization.** For the ordered patterns, the graded value is scaled
   to the number of levels; the cell takes the upper level when the fractional
   part exceeds the cell's threshold, otherwise the lower level.
8. **Per-channel colour.** An RGB palette dithers each channel independently.
9. **Duotone output.** The quantized level mixes a configurable ink colour and
   paper colour.
10. **Pointer trail mask.** A half-resolution ping-pong texture holds a trail.
    Each frame it fades by a rate set by a linger time and stamps a soft capsule
    between the previous and current pointer positions.
11. **Rank-gated reveal.** Each cell shows the full-colour photo when the trail
    value at that cell (scaled up and clamped) reaches the cell's own Bayer rank.
    The rank is taken from the transposed cell coordinate, so it is independent
    of the tone pattern. The veil therefore opens and closes one cell at a time
    in Bayer order, not along a smooth edge.
12. **Photo under the veil.** Revealed cells show the untouched photo at full
    resolution.
13. **Rim band.** An optional rim colour fills cells whose trail value lies in a
    band just below their reveal rank.
14. **Click shockwaves.** Up to four expanding rings feed the same reveal gate.
15. **Radial intro.** On load, each cell appears when an eased clock passes a
    per-cell start: 72% normalized distance from the centre plus 28% Bayer rank
    (offset in phase). The step is hard; a cell is either ink or image.
16. **Background keying.** A 32x32 thumbnail's border ring is checked for low
    colour variance. A plain border marks the photo background as a matte that is
    keyed out and used to fill letterbox space.
17. **Autonomous wander.** Without a pointer, an optional Lissajous path drives
    the trail, disabled under reduced motion.
18. **Idle stop.** The animation loop stops once the trail, bursts, and intro have
    all settled.

Two facts bound what Dither Veil can tell Aski. Its source is a still image, so
it never re-dithers moving content and offers no evidence about temporal
stability of tone dither. Its cells are device pixels holding one of N
uniform levels, while Aski's cells hold glyphs whose brightness ladder is not
uniform.

## Aski's current state, by part

Line numbers are at the audited commit.

- **dotMatrix tone.** [`DotMatrixKernel.swift`](../../Sources/Aski/Algorithms/DotMatrixKernel.swift)
  `:53-84` picks the glyph whose normalized brightness is nearest the cell
  target plus accumulated error, then diffuses the residual times the dither
  strength with Floyd–Steinberg weights (`:72-78`). The error buffer is
  cross-cell mutable state (`:5-14`, `:20-26`). The walk is plain raster
  order, left to right on every row
  ([`ConversionEngine.swift`](../../Sources/Aski/ConversionEngine.swift)
  `:113-118`), not serpentine.
- **Strength.** `RenderingOptions.coverage` is the Floyd–Steinberg strength
  ([`RenderingOptions.swift`](../../Sources/Aski/RenderingOptions.swift)
  `:25-27`). Its default is `0` (`:54`, `:68`), and the CLI default is
  also `0` ([`AskiDemoCommand.swift`](../../Tools/AskiToolSupport/AskiDemoCommand.swift)
  `:67-71`). At the shipped default, dotMatrix is undithered
  nearest-brightness quantization.
- **Serial walk.** [`GridRowWalk.swift`](../../Sources/Aski/GridRowWalk.swift)
  `:3-6` and `:15-16` state that dotMatrix must resolve `.forcedSerial`;
  every dotMatrix call site passes it
  ([`ASCIIConverter.swift`](../../Sources/Aski/ASCIIConverter.swift)
  `:103-111`, `:156-166`, `:221-230`). The kernel also keeps a mutable
  ranked-candidate cache (`DotMatrixKernel.swift:27-29`, `:93-121`), so even
  at strength 0 a parallel walk would need that cache made safe first.
- **Video.** [`ASCIIVideoConverter.swift`](../../Sources/Aski/Video/ASCIIVideoConverter.swift)
  `:38` and `:45` convert every frame independently with a fresh kernel. No
  error state crosses frames.
- **Video lab.** `aski lab video` builds its converter without an algorithm or
  coverage option
  ([`VideoLabCLI.swift`](../../Tools/AskiVideoLab/VideoLabCLI.swift)
  `:324-335`), so it always renders logPolar today.
- **Churn instrument.** [`FlickerMetrics.swift`](../../Tools/AskiMotionLab/FlickerMetrics.swift)
  `:23-53` computes mean and max glyph churn (fraction of cells whose
  character changes between consecutive frames) and alpha churn over
  `ASCIIGrid` frames. The ASTSK-41/45 gates used a 20% churn-drop bar
  ([`TemporalGate.swift`](../../Tools/AskiMotionLab/TemporalGate.swift)
  `:59`).
- **Entrance reveal.** [`EntrancePattern.swift`](../../Sources/Aski/Animation/EntrancePattern.swift)
  `:5` declares `.reveal(origin:easing:)`.
  [`PatternEvaluator.swift`](../../Sources/Aski/Animation/PatternEvaluator.swift)
  `:34-43` gives each cell a start time equal to its normalized radial
  distance from the origin (`:125-141`) times 0.8, then ramps alpha through an
  eased window fixed at 20% of the duration (`:13`). The result multiplies
  cell alpha in
  [`AnimatedASCIIGrid.swift`](../../Sources/Aski/Animation/AnimatedASCIIGrid.swift)
  `:58-66`. The front is continuous: neighbouring cells differ only by distance.
- **Mask coverage.** [`MaskSampler.swift`](../../Sources/Aski/Masking/MaskSampler.swift)
  `:91-104` draws the mask to the grid and takes Rec. 709 luma per cell as
  coverage; `softEdges: false` thresholds every cell at the same 0.5
  (`:97-99`), then `invert` flips (`:100-102`).
  [`MaskOptions.swift`](../../Sources/Aski/Masking/MaskOptions.swift)
  `:11-21` holds fallback, ground, soft edges, and invert.
- **Photo dissolve.** `MaskFallback.originalImage`
  ([`MaskFallback.swift`](../../Sources/Aski/Masking/MaskFallback.swift)
  `:8`) shows the source photo where coverage is below 1, and coverage mixes
  the completed active and inactive branches linearly
  ([Masking guide](../../Sources/Aski/Aski.docc/Masking.md), "Coverage weight"
  and "Active-Region Grounds"). The CLI exposes this as `--mask` with
  `--mask-fallback original`.
- **Cell sampling.** Cells are area averages over an oversampled lattice
  ([`CellSampling.swift`](../../Sources/Aski/CellSampling.swift) `:208`).
- **Tone grade and palette.** `brightness` and `contrast` act on OKLab L
  (`RenderingOptions.swift:39-45`). `BuiltInPalette.monochrome`
  ([`ASCIIPalette.swift`](../../Sources/Aski/ASCIIPalette.swift) `:74`) with
  a render background colour gives a two-colour result.

## Classification

The out-of-scope rows follow the task's own list (pointer-driven trails,
shockwaves, the rim band, background keying) plus parts with no Aski
counterpart. "Deferred" marks a new part that ASKI-96 does not name and that
this note does not propose as an arm.

| # | Dither Veil part | Aski today | Class |
| --- | --- | --- | --- |
| 1 | Cell lattice, prefiltered centre read | Area-averaged oversampled cells | Covered |
| 2 | Contrast, brightness, power 1.6 | OKLab L brightness and contrast; no fixed power curve | Covered (power curve not proposed) |
| 3 | Bayer 8x8 tone threshold | None; dotMatrix uses nearest brightness plus diffusion | **New** (AC#2 arm) |
| 4 | 64x64 void-and-cluster rank threshold | None | **New** (AC#2 arm) |
| 5 | Engraving diagonal threshold | None | New, deferred |
| 6 | Floyd–Steinberg diffusion | Floyd–Steinberg, raster order, strength `coverage` | Covered (control) |
| 6a | Serpentine order, Atkinson kernel | Not present | New, deferred |
| 7 | Threshold between adjacent uniform levels | Nearest glyph on a non-uniform ladder | New mechanics, part of rows 3-4 |
| 8 | Per-channel RGB dither | A glyph is one symbol; colour is per cell | Out of scope |
| 9 | Ink/paper duotone | `monochrome` palette plus background colour | Covered |
| 10 | Decaying pointer trail mask | None | Out of scope (task list) |
| 11 | Per-cell rank gate on the mask value | Uniform 0.5 hard threshold or linear soft coverage | **New** (AC#4 candidate) |
| 12 | Photo under the veil | `MaskFallback.originalImage` | Covered |
| 13 | Rim band | None | Out of scope (task list) |
| 14 | Click shockwaves | None | Out of scope (task list) |
| 15 | Radial intro with rank jitter, hard step | `EntrancePattern.reveal`: radial start, smooth 20% window | Radial front covered; rank jitter and hard step **new** (AC#4) |
| 16 | Background keying | None | Out of scope (task list) |
| 17 | Autonomous wander path | None | Out of scope (pointer trail) |
| 18 | Idle stop of the render loop | Not applicable; Aski renders frames on request | Out of scope |

Headline: covered — sampling, tone grade, Floyd–Steinberg diffusion, duotone,
photo under the veil, and the radial reveal front. New — ordered tone
thresholds (Bayer, blue-noise rank), a per-cell rank gate on mask coverage, and
a rank-jittered hard-step reveal. Out of scope — trail, shockwaves, rim, keying,
per-channel colour, wander, and the render loop.

Rows 11 and 15 are the same primitive: compare a per-cell rank against a
progress value. Row 11 takes progress from mask coverage, row 15 from the
animation clock. One lab rank source could serve both, which matches the
task's claim that the reveal needs no new compositing.

## Literature, and what it does and does not predict for Aski

Sources were opened on 2026-11-24 unless marked otherwise.

- **Ulichney 1993, void-and-cluster.**
  [The void-and-cluster method for dither array generation](https://cv.ulichney.com/papers/1993-void-cluster.pdf)
  (SPIE vol. 1913). Ordered dither is a point operation that needs no
  neighbouring pixels, which the paper notes matters for motion video. It
  describes Bayer's 1973 arrays as a subset of recursive tessellation with
  strong periodic structure, and builds homogeneous arrays as small as 32x32
  with a Gaussian filter of sigma 1.5. Dither Veil's blue-noise texture follows
  this construction. Bayer's 1973 paper itself was not opened this run; claims
  about it here rest on Ulichney's account.
  *Predicts for Aski:* an ordered arm can score every cell independently, so the
  dotMatrix walk could run row-parallel. *Does not predict:* static MAE or GMSD
  on a glyph ladder, or whether an 8-cell Bayer period is visible at character
  scale, where one period spans eight glyph columns instead of eight pixels.
- **Wolfe, Morrical, Akenine-Möller, Ramamoorthi 2022, spatiotemporal blue noise.**
  [Scalar Spatiotemporal Blue Noise Masks](https://arxiv.org/abs/2112.09629)
  (arXiv v1 2021-12-17; EGSR 2022; [paper PDF](https://cseweb.ucsd.edu/~ravir/stbn.pdf)).
  STBN extends void-and-cluster so that each pixel's sequence of values across
  64 mask slices is itself blue noise (64x64x64 masks, sigma 1.9, 10% initial
  density). Its goal is faster convergence and stability under temporal
  filtering (TAA or exponential moving average), and it is meant to change every
  frame. *Predicts for Aski:* nothing in favour of lower glyph churn. An animated
  STBN arm would raise per-cell churn by design, because it relies on the viewer
  or a filter averaging over frames; Aski's glyph flips are discrete and visible
  at 12 to 30 fps. The relevant arm for ASKI-96 is a single fixed 2D mask.
  STBN stays relevant only if a later task wants temporally averaged alpha or
  tone, not stable glyph identity.
- **Rehman and Evans 2010, temporal artifacts in binary video halftones.**
  [A Framework for the Assessment of Temporal Artifacts in Medium Frame-rate Binary Video Halftones](http://users.ece.utexas.edu/~bevans/papers/2011/video/index.html)
  (EURASIP J. Image and Video Processing, article 625191). The opened page
  states the scope: two temporal artifacts, flicker and the dirty-window effect,
  in binary halftone video up to 30 fps, with a measure and a halftoning method
  for each. *Unverified lead* (search summary only; the full text was not
  reachable): per-frame ordered dither shows low flicker but a high
  dirty-window effect, where the fixed threshold pattern appears to stay still
  while the content moves behind it. *Predicts for Aski, if confirmed:* glyph
  churn alone would reward an ordered arm while missing its main temporal
  artifact, so the decision rule needs a second temporal measure or a visual
  check.
- **Pope 2017, Return of the Obra Dinn devlog.**
  [TIGSource devlog, November 2017](https://dukope.com/devlogs/obra-dinn/tig-32/)
  (post of 2017-11-23). A practitioner report: a screen-fixed dither on moving
  content gave "a wiggling mess of pixels"; the fix mapped the dither pattern to
  camera rotation so it stayed pinned to the scene. The game used an 8x8 Bayer
  matrix for smoother shade ranges and a 128x128 blue-noise field for less
  ordered output. *Predicts for Aski:* a threshold locked to cell position is
  stable on static or slow regions but not locked to content, so panning or
  fast motion may churn as much as diffusion. This matches the slow/fast split
  that killed ASTSK-45 (S1 slow disc versus S2 fast bar).
- **Brüll, Kern, Grosch 2025, spatio-temporal dithering for order-independent
  transparency.** EGSR 2025 short paper, listed on the
  [EGSR 2025 paper index](https://www.realtimerendering.com/kesen/egsr2025Papers.htm);
  [source repository](https://github.com/TU-Clausthal-Rendering/SpatioTemporalDithering).
  A 2025 rendering use of small permuted dither matrices over time, with STBN
  among its comparison options; its README describes one periodic temporal
  option as flickering heavily. This is the only 2025-2026 follow-up found. It
  targets stochastic transparency under temporal accumulation and predicts
  nothing about glyph churn.
- **ASCII Magic, Bayer dithering guide.**
  [Bayer Dithering and the Bayer Matrix](https://www.ascii-magic.com/blog/bayer-dithering)
  (page updated 2026-10-09). Practitioner guidance, not a measurement: use
  ordered dither for animation, because error diffusion "crawls and boils" on
  video. It does not cover character output. It is relevant because ASCII Magic
  is Aski's parity floor.
- **Character-art renderers.** Search surfaced two GitHub pull requests that
  describe Bayer or coordinate-hash thresholds keyed to cells for stable ASCII
  output (`pirut/jrbussard` #27 and `andmckay01/auto-ascii` #29). *Unverified
  leads:* neither was opened this run. No primary source measured glyph churn for
  ordered versus diffused character art.

**Refutation attempts.** (1) "An ordered threshold lowers churn." Per-frame
Floyd–Steinberg is deterministic, so a frame identical to its predecessor
already gives zero churn under both methods. Any difference must come from how
far a local change or source noise propagates, and from moving content, where
the Obra Dinn report and the unverified dirty-window lead both say a
position-locked pattern has its own artifact. The claim survives only as a
claim about propagation, and needs per-region measurement. (2) "Blue noise
beats Bayer for temporal stability." Refuted for the animated form: STBN is
designed to vary each frame. For a fixed mask, no opened source compares Bayer
and blue noise on churn; the published difference is spatial (periodic
structure). (3) "Dither Veil shows the reveal works cell by cell." Confirmed
in source (row 11), but its veil sits over a static photo; it says nothing
about a rank gate on an animating grid.

## Open questions for the AC#2 pre-registration

These are questions, not a frozen rule.

**Control**

1. The shipped `coverage` default is 0, which is no diffusion at all. Is the
   control dotMatrix at 0, at 1.0, or both? If both, which one does the
   decision rule compare against?
2. Which charsets: the density ladders the docs pair with dotMatrix
   (`minimal`, `blocks`, `dots`, `braille`), `standard`, or a fixed subset?
   The ladder shape sets how much room any dither has.

**Arms**

3. How does a threshold map onto a non-uniform glyph ladder: bracket the target
   between the two nearest glyph brightnesses and compare the fractional
   position with the rank, or quantize to uniform levels first?
4. Does an ordered arm take a strength, as `coverage` scales diffusion, and is
   it swept or fixed?
5. Which masks: Bayer 8x8 only, or also 4x4; void-and-cluster at 32x32 or 64x64;
   which sigma (1.5 per Ulichney); which seed, recorded for replay?
6. Is the mask phase fixed to grid cell (0, 0), and what happens when the column
   count changes between frames?
7. Lab-only target or `@_spi(AskiResearch)` hook, and where does the kernel
   variant live so production dotMatrix stays byte-identical?

**Corpus**

8. Which stills: the frozen-render-reference images, the NASA occupancy corpus,
   or both? Which column counts (64 and 80 match ASTSK-45)?
9. Which motion: the S1 slow disc and S2 fast bar synthetic stimuli from the
   motion lab, plus at least two real clips? Which clips, at what fps and frame
   count, with what licence?
10. `aski lab video` cannot select dotMatrix or a coverage value today. Is
    adding `--algorithm` and `--coverage` to the video lab part of AC#3, and
    does it need its own review?

**Metrics**

11. Static quality: MAE and GMSD against the source on the exact sampling
    lattice, as AC#3 says. Which renderer settings fix the lattice, and is
    HaarPSI kept as the cross-check oracle as in ASTSK-41/45?
12. Glyph churn: reuse `FlickerMetrics.meanGlyphChurn` as is? Split it into
    static and moving regions (by source frame difference) so a gain on static
    regions cannot hide a loss on moving ones?
13. How is churn from source noise (compression, sensor grain) separated from
    churn the arm causes? Is a noise-only clip (static scene, real camera) in
    the corpus?
14. Is there a measure for the dirty-window effect, or is it a recorded visual
    check with a pre-stated pass condition?
15. Walk time: dotMatrix serial (control) versus ordered arm serial and
    row-parallel, on which grid sizes, and does a wall-time result count
    toward PASS or only get recorded?
16. Sanity check: two identical consecutive frames must give zero churn for
    every arm. Is that asserted before the measured run?

**Decision rule**

17. Which churn drop counts: the prior 20% bar, per region or overall?
18. Which static band: a ratio bound on MAE and GMSD (the ASTSK-45 bands were
    x1.02 GMSD and x0.99 HaarPSI)? An ordered dither is expected to cost static
    error, so what cost is acceptable?
19. How many of the (stimulus, columns, charset) cells must qualify, with one
    shared arm setting, for PASS, and what makes the result INCONCLUSIVE rather
    than KILL?

**Reveal (AC#4)**

20. Rank source for the reveal: the same mask as the tone arm or a separate one,
    and is it transposed as in Dither Veil so tone and reveal do not align?
21. Blend between radial distance and rank (Dither Veil uses 72/28), and hard
    step or a short window?
22. What concrete app use would justify keeping it, and is a mask-coverage rank
    gate (row 11) tested in the same prototype?

## Sources

- React Bits, [DitherVeil.jsx at 1eeb6f1](https://github.com/DavidHDev/react-bits/blob/1eeb6f105c68b964289d85dabbe84a1d551f3797/src/content/Animations/DitherVeil/DitherVeil.jsx), commit dated 2026-09-27; [demo page](https://reactbits.dev/animations/dither-veil) (not opened this run).
- R. Ulichney, [The void-and-cluster method for dither array generation](https://cv.ulichney.com/papers/1993-void-cluster.pdf), SPIE vol. 1913, 1993.
- A. Wolfe, N. Morrical, T. Akenine-Möller, R. Ramamoorthi, [Scalar Spatiotemporal Blue Noise Masks](https://arxiv.org/abs/2112.09629), arXiv 2021; EGSR 2022 ([PDF](https://cseweb.ucsd.edu/~ravir/stbn.pdf)).
- H. Rehman, B. L. Evans, [A Framework for the Assessment of Temporal Artifacts in Medium Frame-rate Binary Video Halftones](http://users.ece.utexas.edu/~bevans/papers/2011/video/index.html), EURASIP JIVP, 2010.
- L. Pope, [Return of the Obra Dinn devlog, TIGSource November 2017](https://dukope.com/devlogs/obra-dinn/tig-32/).
- F. Brüll, R. Kern, T. Grosch, Spatio-Temporal Dithering for Order-Independent Transparency on Ray Tracing Hardware, EGSR 2025 ([paper index](https://www.realtimerendering.com/kesen/egsr2025Papers.htm), [code](https://github.com/TU-Clausthal-Rendering/SpatioTemporalDithering)).
- ASCII Magic, [Bayer Dithering and the Bayer Matrix](https://www.ascii-magic.com/blog/bayer-dithering), updated 2026-10-09.
