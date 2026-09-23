---
title: "Thread D: Isoluminant Rescue (chroma-gradient shape assist) — PASS"
slug: 2026-06-10-isoluminant-rescue
date: 2026-06-10
status: complete
subsystem: [color-science, shape-context]
summary: "Injecting the OKLab (a,b) vector-gradient magnitude into the logPolar shape query rescues isoluminant chromatic edges: on constant-OKLab-L red/green and blue/yellow vertical edges the edge band melts to a single glyph at λ=0 (entropy 0.000 bits) and the edge cell column flips to a vertically-structured glyph at every λ>0 (entropy 0.722 bits — a step, saturating at the first arm), while a pure-luminance control is exactly λ-invariant. Two design corrections were load-bearing: the gradient must be the Di Zenzo vector gradient √(|∇a|²+|∇b|²) (the sketched scalar-chroma-magnitude field is near-blind to red/green, whose chroma magnitude is ~constant while a flips sign), and the injection must be a mass-normalized blend (the sketched peak-1 additive bump can never exceed ~9% of the L1-normalized descriptor mass against the inverted-luma flood of saturated colors)."
related_specs: [docs/research-plan.md]
datasets: []
runners: [AskiColorLab]
next_action: "ASKI-65 retracted the follow-up dose-response AC #1 PASS (this note's step-edge result was not re-measured on an exact lattice), the exact-lattice ASKI-66 redesign closed INCONCLUSIVE, and ASKI-68 removed chromaShapeAssist and its dedicated runners. Preserve this note as historical evidence; do not restore the treatment without a new pre-registered mechanism."
---

# Thread D: Isoluminant Rescue (chroma-gradient shape assist) — PASS

> See also the [ASKI-65 addendum](2026-06-11-isoluminant-dose-response.md#addendum-2026-09-02-aski-65-the-pass-above-was-measured-on-a-truncated-lattice) (2026-09-02), which retracts the follow-up note's AC #1 dose-response PASS; its exact-lattice re-measurement covers the competition ramps, not the step-edge fixtures reported here.

## Question

Isoluminant blindness is the dual of the "glyph = luminance" decoupling: the
logPolar shape query is built from inverted Rec.601 luma, so a chromatic edge
at constant luminance produces a flat shape field — both sides of the edge
collapse to one glyph and the subject melts into its background. Thread D asks
the falsifiable question from `docs/research-plan.md` §Thread D: does injecting
`λ·|∇chroma|` into the shape **query** (candidate vectors untouched — no
`.bin` churn) make the matcher resolve isoluminant edges, measured as Shannon
entropy of the chosen-glyph histogram across the edge band rising with λ?

## Method

Implementation (ASTSK-30, this branch):

- One `RenderingOptions` knob — `chromaShapeAssist` (λ, 0…1, default **0** =
  off, byte-identical: the chroma loop is skipped entirely behind the same
  guard pattern as `edgeEmphasis`, and an explicit golden test pins
  `chromaShapeAssist: 0` == `.default` cell-for-cell).
- In `LogPolarKernel.extractShapeVector`, after the inverted-luma field and
  before the `edgeEmphasis` blend: per-pixel OKLab (a,b) via `sRGBDecode` →
  `linearSRGBToOKLAB`/`linearP3ToOKLAB` (per `context.colorSpace`), the
  existing `sobelMagnitude` run on the a-field and b-field separately, combined
  per pixel as `√(|∇a|²+|∇b|²)`, then blended **mass-normalized**:
  `g′ = (1−λ)·g + λ·(Σg/Σ∇c)·∇c`, so λ is exactly the fraction of descriptor
  mass carried by the chroma channel. An internal noise floor
  (`chromaGradientFloor = 0.02`, raw OKLab Sobel units) skips cells whose
  chroma variation is quantization ripple — without it the mass normalization
  would amplify arbitrarily faint noise to λ of the descriptor.
- Lab: `AskiColorLab isoluminant-rescue` — 512px fixtures at `--columns 64`
  (native, no-downscale; 8px cells; the edge at x=260 sits 4px inside its cell
  and the lab *refuses* boundary-aligned geometry rather than mis-measuring).
  Battery: red/green at OKLab L=0.40, blue/yellow at L=0.45 (blue's gamut
  ceiling is L≈0.452), pure-luminance gray control. λ ∈ {0, 0.25, 0.5, 0.75,
  1.0}; the AC verdict reads {0, 0.25, 0.5}. Band = edge cell column ±2
  columns × all 29 rows (145 cells). The runtime verdict additionally
  requires the control to be λ-invariant (every arm grid-equal to its λ=0
  arm); a drifted control voids the run as INVALID rather than letting the
  isoluminant fixtures carry a PASS (PR #36 review r3390979957). Reporter
  only (exit 0); per-cell CSV + `result.yaml`.

### Two design corrections locked at pickup (both load-bearing)

1. **Vector gradient, not gradient of chroma magnitude.** The design sketch
   said "per-pixel chroma `c = √(a²+b²)`, Sobel on the chroma field". On the
   sketch's own red/green KILL fixture that operator is nearly blind: at
   constant L the two sides have similar chroma *magnitude* (C ≈ 0.26 vs
   0.21 at L=0.4) while `a` flips sign (+0.14 → −0.11) — the hue rotates, the
   radius barely moves. The corrected operator is the multi-channel vector
   gradient `√(|∇a|²+|∇b|²)` — the Frobenius norm of the (a,b) Jacobian, i.e.
   the unsmoothed trace of the Di Zenzo color structure tensor, the standard
   color-edge operator since Di Zenzo 1986 (frontier-search: van de Weijer &
   Gevers CIC 2004 names the red/green edge as the canonical case where
   per-channel signals cancel and tensor summation is the fix).
2. **Mass-normalized blend, not peak-1 additive bump.** The sketch said
   "normalize Sobel to peak 1, `g += λ·∇c`". `ShapeContext.histogram60`
   L1-normalizes the descriptor, and the shape field is *inverted* luma — so
   saturated colors are always high-mass (Rec.601 luma of saturated primaries
   is well below 1; g ≈ 0.7–1.0/px across the whole cell). Against that flood
   a peak-1 bump on a ~2px edge band carries ≤9% of descriptor mass even at
   λ=1, while flipping a flat descriptor to a line-like one needs roughly 40%
   (‖U‖² ≈ 0.018, ‖U−E‖² ≈ 0.13). The sketched arithmetic is structurally
   inert on its own fixtures — it would have produced a KILL that measured the
   injection arithmetic, not the chroma signal (the ASTSK-27 instrument
   lesson). The blend `g′ = (1−λ)·g + λ·(Σg/Σ∇c)·∇c` makes λ the descriptor
   mass fraction directly: λ=0 byte-identical, λ=1 pure chroma shape,
   scale-invariant in `∇c`.

## Findings

Edge-band glyph entropy (bits), canonical run
(`isoluminant-rescue --columns 64 --fixture-size 512`, sha c04e4b9):

| fixture     | λ=0    | λ=0.25 | λ=0.5  | λ=0.75 | λ=1.0  | verdict |
|-------------|--------|--------|--------|--------|--------|---------|
| redGreen    | 0.0000 | 0.7219 | 0.7219 | 0.7219 | 0.7219 | RISES   |
| blueYellow  | 0.0000 | 0.7219 | 0.7219 | 0.7219 | 0.7219 | RISES   |
| lumaControl | 1.5219 | 1.5219 | 1.5219 | 1.5219 | 1.5219 | invariant |

- **Melt is exact at λ=0.** All 145 band cells pick `=` on both isoluminant
  fixtures: identical adjustedL on both sides plus an (L1-normalized) flat
  descriptor → one glyph, H = 0. The edge is invisible.
- **Rescue is a clean step.** At every λ>0 exactly the 29 edge-column cells
  flip `=` → `+` (the vertically-structured glyph in the mid-density
  brightness pool): H = −0.8·log₂0.8 − 0.2·log₂0.2 = 0.7219 bits. The AC's
  "entropy rises with λ" is satisfied as a step that saturates at the first
  nonzero arm — at this synthetic geometry the injected line structure
  dominates the descriptor as soon as it clears the flip threshold.
- **The control validates the floor end-to-end.** The gray step fixture (zero
  chroma) renders byte-identically at every λ (a unit test pins grid equality,
  not just entropy equality), so the injection cannot perturb achromatic
  content no matter the knob.
- Unit level (kernel): a red/green constant-L cell with a dark brightness pool
  flips blank → non-blank at λ>0 (AC #3), and the pure luminance edge is
  pick-invariant at every λ — the no-op control is exact, not merely
  byte-identical-at-zero.

## Caveats

- The entropy step (no further rise λ=0.25 → 1.0) means the synthetic
  fixtures cannot discriminate λ values above the flip threshold; real images
  with graded chroma edges are needed for a true dose-response curve. The AC
  as written ("rises with λ over {0, 0.25, 0.5}") is satisfied.
- `chromaGradientFloor = 0.02` is calibrated to 8-bit quantization ripple on
  synthetic fields, not to photographic sensor noise; real-image validation
  may move it.
- Glyph choice changes only within the brightness top-K pool (the injection
  changes the query lanes, not `adjustedL`), so a rescue is only as good as
  the pool's structural diversity — at L≈0.4 the pool offered `+`; pools
  without any line-like glyph would cap the rescue (relates to ASTSK-7
  occupancy work).

## Decision

**PASS — keep `chromaShapeAssist`, default 0 (byte-identical), opt-in.** AC #2
and #3 verified by lab + tests; AC #4's KILL criterion was not met. No `.bin`
churn (candidate vectors untouched, verified by `git status` on
`Sources/Aski/Resources/ShapeData/`).

## Pointers

- Knob: `Sources/Aski/RenderingOptions.swift` (`chromaShapeAssist`)
- Kernel: `Sources/Aski/Algorithms/LogPolarKernel.swift` (`extractShapeVector`,
  `chromaGradientFloor`)
- Lab: `Tools/AskiColorLab/IsoluminantRescue/`
- Tests: `Tests/AskiTests/ChromaShapeAssistTests.swift`,
  `Tests/AskiTests/AskiColorLabIsoluminantRescueTests.swift`
