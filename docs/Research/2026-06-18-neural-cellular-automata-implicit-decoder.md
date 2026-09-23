---
title: "Neural Cellular Automata \"From Cells to Pixels\" — Cross-Domain Brief for Aski"
slug: 2026-06-18-neural-cellular-automata-implicit-decoder
date: 2026-06-18
status: active
subsystem: [frontier, animation, shape-context]
summary: "The two requested sources (the Cells2Pixels GitHub repo and arxiv 2506.22899v3) are one work, the SIGGRAPH 2026 paper Neural Cellular Automata: From Cells to Pixels, and it is not about ASCII conversion. Read as cross-domain transfer it still earns a brief: its implicit decoder (LPPN) maps an interpolated coarse-cell state plus an intra-cell coordinate to appearance, which is structurally isomorphic to Aski's coarse glyph grid plus glyph rasterizer, and its defining temporal property is bounded local change. The highest-value transfer is an NCA-style local-update rule over the ASCII cell-state grid as a temporal-coherence prior for animation, tested against the existing ASCII Temporal Flicker Index. A second cheap test swaps a Fourier-feature sub-cell basis for the log-polar shape basis. Adopting NCA wholesale is a dead end: it needs GPU training, emits continuous output, and has no discrete-glyph component."
next_action: "Tracked as ASTSK-41 (animation temporal prior — the priority spike), ASTSK-42 (Fourier sub-cell basis), and ASTSK-43 (inter-cell state smoothing). Theory 1 and Theory 5 are deliberately not tracked (reframing and dead end)."
---

# Neural Cellular Automata "From Cells to Pixels" — Cross-Domain Brief for Aski

**Date:** 2026-06-18
**Status:** Research synthesis (cross-domain transfer)
**Scope:** Read the two requested sources, establish what they actually are, and extract only what transfers to Aski's coarse-cell → pixel pipeline. Frontier-search bolstered the novelty and mechanism questions.

## Question

What in the Cells2Pixels repo and arxiv 2506.22899v3 materially benefits Aski's 60D log-polar shape matching and OKLAB color pipeline?

## Source reality check (read this first)

The two URLs are **the same work**, and it is **not about ASCII art or image-to-text conversion**:

- [github.com/TheDevilWillBeBee/Cells2Pixels](https://github.com/TheDevilWillBeBee/Cells2Pixels) is the official code for the paper below — PyTorch (`torch==2.8.0`), Kaolin for mesh rasterization, `python train.py --config ...`, ~79% Jupyter. It grows/synthesizes RGBA images, PBR textures, 3D volumes, and radiance fields from a seed. No glyphs, no charset, no SSIM, no log-polar.
- [arxiv 2506.22899v3](https://arxiv.org/abs/2506.22899v3) — *Neural Cellular Automata: From Cells to Pixels*, Pajouheshgar, Xu, Abbasi, Mordvintsev, Jakob, Süsstrunk; submitted 2025-06-28, v3 2026-05-01; **SIGGRAPH 2026**. [Project page](https://cells2pixels.github.io/).

The "cells" are NCA grid cells (a learned local update rule self-organizing a state field), not ASCII character cells. The name collision with Aski's tile/cell vocabulary is coincidental. So this brief is **cross-domain transfer**, explicitly speculative — not a list of findings to apply.

That said, the structural parallel is real enough to be worth a brief, and frontier-search confirmed the bridge is unexplored: **no NCA-based image→ASCII converter surfaced**. The neural ASCII work that exists is CNN-based ([DeepAA](https://github.com/OsciiArt/DeepAA), [ascii-net](https://github.com/a-metz/ascii-net), [n3ar](https://github.com/nenadmarkus/n3ar)); classic cellular automata appear only as a *pattern generator* ([ASCII Automata, Show HN](https://news.ycombinator.com/item?id=45621571)), not as an image converter.

## Executive thesis

The paper's contribution is an **implicit decoder** — the **Local Pattern Producing Network (LPPN)** — that decouples grid resolution from output resolution. After NCA evolution on a coarse grid, the LPPN renders at arbitrary resolution from:

```text
LPPN inputs  : s̄(p) ∈ ℝ^C  — cell state, locally interpolated (bilinear / barycentric)
             : u(p)         — intra-primitive coordinate, sinusoidal positional-encoded
                              (sin(πu), cos(πu), …, sin(nπu), cos(nπu))
LPPN body    : 4-layer SIREN (3 sine layers + linear), ≈25% param overhead vs the NCA
LPPN outputs : K channels   — K=3 RGB, K=9 PBR
```

Reframed in Aski's terms, **Aski already runs this exact shape — with the decoder frozen and discrete**:

```text
Aski cell state          ↔  NCA cell state s̄(p)
glyph rasterizer + FG/BG ↔  LPPN  (maps cell state + sub-cell coordinate → ink/color)
the character set        ↔  a discrete, hand-authored decoder codebook
```

Aski's glyph raster *is* a "map cell-state + local coordinate → appearance" decoder. The difference is the whole ballgame: Aski's decoder is **discrete** (a fixed glyph codebook, output is serializable text) and **untrained**; the LPPN is **continuous** and **learned**. The transfer value is in three reframings and one product bet, below — not in importing NCA.

## Priority map

| Priority | Idea | Why it matters for Aski | Cost | Task |
| --- | --- | --- | --- | --- |
| P1 | NCA-style local-update animation prior (Theory 3) | Bounded per-cell change *by construction* directly attacks the known flicker/churn failure mode; Aski already measures the metric. | Low (reuses AskiMotionLab) | ASTSK-41 |
| P2 | Fourier-feature sub-cell basis vs log-polar (Theory 2) | Cheap, falsifiable test of whether a learned/continuous positional basis beats the degenerate log-polar one on radial/diagonal content. | Low (reuses shape-residual-map) | ASTSK-42 |
| P3 | Inter-cell state smoothing before glyph pick (Theory 4) | The paper's own artifact failure mode maps onto Aski's per-cell-independence grid artifacts. | Medium | ASTSK-43 |
| — | Continuous implicit re-decode for export (Theory 5) | Dead end — the font already gives Aski resolution independence. Logged so nobody re-derives it. | n/a | not tracked |

## 1. The glyph is a frozen, discrete LPPN (Theory 1 — reframing)

The single most useful takeaway is conceptual: stop thinking of the character set as "style" and start thinking of it as **a discrete, hand-authored implicit decoder**. The LPPN earns its keep because one tiny shared decoder, conditioned on a sub-cell coordinate, reconstructs high-frequency detail a coarse grid can't hold. Aski's glyph does the same job with a codebook lookup instead of an MLP.

This sharpens the existing glyph-set-capacity question (see the 2026-05-26 frontier brief): the codebook's *job* is to be a good decoder basis. The discrete/text output is the feature, not a limitation — it is exactly what a continuous LPPN destroys.

```text
Aski framing to adopt:
  charset = decoder codebook over (cell state, sub-cell position) → ink coverage
  quality(charset) = how well the codebook reconstructs source cells, NOT aesthetics
```

Source: [LPPN method, arxiv HTML v3](https://arxiv.org/html/2506.22899v3); [project page](https://cells2pixels.github.io/).

## 2. Fourier sub-cell basis vs the degenerate log-polar basis (Theory 2 — testable)

The LPPN encodes the **intra-cell coordinate** with a sinusoidal basis (`sin(nπu), cos(nπu)`) to recover high-frequency sub-cell structure. Aski's 60D log-polar descriptor is *also* a fixed positional basis over the cell — and ASTSK-31/35 settled that this basis is **degenerate on radial and diagonal content**, with the basis-augmentation rescue (`shapeStructureAssist`) KILLED because its ρ lift didn't transfer to glyph picks ([2026-06-09 shape-residual](2026-06-09-shape-residual.md)).

The LPPN insight is a concrete alternative: a **Fourier-feature sub-cell basis** may be a better-conditioned shape descriptor than log-polar bins for oriented/curved content, because sinusoidal features are isotropic in orientation where log-polar bins are not.

```text
Experiment (cheap, reuses the existing oracle):
  add a Fourier-feature descriptor variant alongside logPolar in the cell sampler
  re-run AskiColorLab shape-residual-map over the frozen battery + column sweep
  compare Spearman ρ(residual, oracle) AND, decisively, GMSD pick-quality
  pre-register the same >= +3% pick-quality bar that KILLED shapeStructureAssist
```

This is the right way to test the idea: against the instrument that has already failed two prior shape-basis rescues, so a positive result would be hard-won rather than a ρ artifact.

Source: [arxiv HTML v3 — positional encoding](https://arxiv.org/html/2506.22899v3); prior Aski verdicts in [2026-06-09 shape-residual](2026-06-09-shape-residual.md).

## 3. NCA as a temporal-coherence prior for ASCII animation (Theory 3 — highest value)

This is the strongest product angle. NCA's defining property: each frame is produced by applying a **local update rule to a persistent cell state**, so consecutive frames differ by a *bounded local perturbation*. That is precisely the property Aski's animation subsystem lacks — its known failure mode is temporal flicker / glyph churn / shimmer, which Aski already quantifies as the **ASCII Temporal Flicker Index** ([2026-06-02 motion-lab](2026-06-02-motion-lab-frame-export.md)). The frontier already shows NCA doing real-time coherent animation: [DyNCA — Real-time Dynamic Texture Synthesis Using NCA](https://arxiv.org/pdf/2211.11417).

Theory: run an NCA-style local-update rule **over the ASCII cell-state grid** (descriptor / brightness / chroma state), then quantize to a glyph at render time. Per-cell churn is bounded by the update rule's locality and step size — flicker reduction *by construction*, not by a post-hoc penalty.

```text
Experiment (reuses AskiMotionLab's flicker instrument):
  cell-state grid = (brightness, OKLab chroma, descriptor) per cell
  per frame: state' = state + α · local_rule(neighborhood)   // hand-authored or distilled
  render: quantize state' → glyph + FG/BG (existing matcher)
  measure: ASCII Temporal Flicker Index vs current C1 animation at equal single-frame quality
  success: lower glyph_switch_rate / churn at equal-or-near-equal per-frame fidelity
```

Note: the *learned* NCA needs training infrastructure Aski does not have and should not add (see §"What does not transfer"). The transferable piece is the **local-update temporal model on cell state**, which can start as a hand-authored kernel — no training required for a first spike.

Authority signal: co-author Sabine Süsstrunk leads EPFL's IVRL color/vision lab; the NCA texture-animation line (DyNCA and successors) is the relevant prior art here, not the high-res-rendering contribution of this specific paper.

Source: [arxiv 2506.22899v3](https://arxiv.org/abs/2506.22899v3); [DyNCA](https://arxiv.org/pdf/2211.11417); flicker metric in [2026-06-02 motion-lab](2026-06-02-motion-lab-frame-export.md).

## 4. The paper's failure mode is Aski's per-cell-independence artifact (Theory 4)

Stated limitation, verbatim: the LPPN "conditions only on intra-primitive coordinates and locally interpolated state (no access to cells outside the enclosing primitive), which can produce faint **primitive-aligned patch artifacts**." This is the same disease as Aski's **per-cell glyph independence**: each cell picks its glyph without seeing neighbors, producing grid-aligned blockiness and strokes that break at cell boundaries.

The paper's structural mitigation is that the **NCA evolution propagates information between cells before the decoder runs**. The transferable hypothesis: a cheap inter-cell **state-smoothing / message-passing** pass over the cell grid, *before* glyph selection, could reduce grid-aligned artifacts — a different lever than the joint glyph-color compositing already proposed in the 2026-05-26 brief.

```text
Experiment:
  before matching, run 1–2 iterations of a small fixed neighbor-mixing kernel on cell state
  then run the existing matcher
  measure: edge continuity across cell boundaries + shape fidelity (GMSD) vs unsmoothed
  watch: smoothing must not wash out genuine high-frequency detail (the obvious failure)
```

Source: [arxiv HTML v3 — limitations](https://arxiv.org/html/2506.22899v3).

## 5. What does NOT transfer (the honest counter-case)

Read this before getting excited:

- **Opposite objective.** NCA *generates* from a seed (morphogenesis, texture synthesis). Aski *faithfully converts* an arbitrary input image to a glyph grid. The losses (relaxed-OT texture loss; RGBA-recon + shape + LPIPS for morphology) are synthesis losses, not conversion fidelity losses.
- **No discrete-symbol component, anywhere.** The hard combinatorial core of Aski — discrete glyph selection over a fixed codebook — is untouched by this work. The LPPN is continuous; it is the *opposite* of glyph quantization.
- **Opposite compute model.** NCA = PyTorch + GPU training (28–38 GB train, 1.2–2.2 GB inference). Aski = Metal kernels, real-time, on-device, no training. Importing NCA literally would mean a training pipeline Aski has no business adding (cf. the "no SDK ceremony / no abstractions without concrete product need" project rules).
- **No fidelity metrics to borrow.** The paper reports throughput and parameter counts, **not PSNR/SSIM/FID** — so there is no quality benchmark to lift, only the architecture idea.
- **Theory 5 is a dead end.** "Decode the compact cell grid at arbitrary resolution" is genuinely the LPPN's headline trick, but Aski gets resolution independence for free by re-rasterizing glyphs at any size. Logged here so it isn't re-proposed.

Net: the deliverable from this paper is **one product experiment (Theory 3) + one cheap basis test (Theory 2) + two reframings**. It is not "adopt NCA."

## Bottom line

Track as research context, with exactly one experiment worth queuing now: the **NCA-style local-update temporal prior for animation** (Theory 3). It is the only idea that (a) attacks a problem Aski demonstrably has (flicker), (b) is measurable on an instrument Aski already built (ASCII Temporal Flicker Index), and (c) can be spiked with a hand-authored kernel before committing to any learned model. The Fourier-basis test (Theory 2) is a cheap second, gated by the same pick-quality bar that already killed `shapeStructureAssist`. Everything else is conceptual reframing. **Do not build an NCA training pipeline.**

## Citations

Grouped by tier; every URL was fetched or surfaced in this run.

- **T1/T3 — primary (the work itself):** [arxiv abstract 2506.22899v3](https://arxiv.org/abs/2506.22899v3) · [arxiv HTML method/limitations](https://arxiv.org/html/2506.22899v3) · [project page](https://cells2pixels.github.io/) · [Cells2Pixels code](https://github.com/TheDevilWillBeBee/Cells2Pixels)
- **T3 — related NCA research:** [DyNCA: Real-time Dynamic Texture Synthesis via NCA](https://arxiv.org/pdf/2211.11417) · [Neural Cellular Automata Can Respond to Signals](https://arxiv.org/pdf/2305.12971) (controllability, context)
- **T4/T5 — neural-ASCII prior art (for novelty check):** [DeepAA](https://github.com/OsciiArt/DeepAA) · [ascii-net](https://github.com/a-metz/ascii-net) · [n3ar](https://github.com/nenadmarkus/n3ar) · [ASCII Automata (Show HN)](https://news.ycombinator.com/item?id=45621571)

**Tier coverage:** T1/T3 primary (paper, code, project page) and T3 related-research are solid; T4/T5 cover the neural-ASCII prior art that establishes the bridge is unexplored. T2 (maintenance/authority) skipped deliberately — adopting this code is out of scope, so repo health is not decision-relevant. Confidence: the source identification and LPPN mechanism are high-confidence (cross-confirmed across abstract, HTML, and project page); the cross-domain transfer theories are explicitly speculative and flagged as such.
