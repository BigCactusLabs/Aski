---
title: "Helmlab MetricSpace Port — Evaluation"
slug: 2026-06-07-helmlab-metricspace-eval
date: 2026-06-07
status: active
subsystem: [color-science]
summary: "Ports Helmlab MetricSpace (v21, 72 params) as two opt-in palette-matching policies and records the perturbation-recovery oracle (small-ΔE ground truth) plus the divergence/saturation probe and a real-image visual review; the recovery oracle ties at 100% with OKLab (no measured win), and the predicted helmlabCompressed saturation collapse does not appear in practice."
datasets: []
runners: [AskiColorLab]
next_action: "Decide promotion only on recovery-oracle + visual-review evidence; do not read the cross-metric divergence CSV as a quality signal. If promotion is ever revisited, build the dense-palette / near-threshold oracle described in §5 — the built-in palettes are too sparse to discriminate."
---

# Helmlab MetricSpace Port — Evaluation

1. **Question** — Does Helmlab MetricSpace beat OKLab for Aski palette
   matching, and does the trained ΔE's ~0.15 saturation hurt small-palette
   (large-ΔE) ranking?

2. **What the field says** — arxiv 2602.23010 v3 (MetricSpace v21, COMBVD
   STRESS 22.48 vs CIEDE2000 29.20); reference `Grkmyldz148/helmlab` (MIT,
   params in `metric_params.json`); Color.js #722 (v21 port, dropped from the
   CSS registry as a distance-only space). The v20b/v21 reconciliation is in
   the spec stop gate: PyPI `helmlab` 0.14.0 ships the v21 params, byte-matched
   against the Color.js #722 block labelled `// Core parameters (v21, 72
   params)`. The win MetricSpace claims is a **small-ΔE** STRESS win on a
   perceptual difference dataset — not a palette-quantization claim.

3. **What we picked, and why** — Two distances over one transform:
   `helmlabEuclidean` (monotonic, ranks distant candidates) and
   `helmlabCompressed` (trained Minkowski + monotonic compression, small-ΔE
   accurate, saturation risk). Both are opt-in `PaletteMatchingPolicy` cases;
   `oklabEuclidean` stays the default.

4. **What the data says** (all reproducible via the `result.yaml` command):
   - **Reference fidelity** — 130 reference rows; forward XYZ→MetricSpace
     matches the pinned Python to machine precision (~1e-15), round-trip
     <1e-9, no NaN on out-of-gamut queries.
   - **Recovery oracle (the small-ΔE ground truth)** — across 23 non-clamping
     lightness- and chroma-directed perturbations spanning all four built-in
     palette groups, **all three policies recover 23/23 (100%)**. The oracle
     is *saturated*: at magnitude 0.04 on these palettes every metric recovers
     the un-perturbed entry, so there is **no measured palette-matching win**
     for either Helmlab variant over OKLab. They tie at ceiling.
   - **Divergence probe (cross-metric, NOT a quality signal)** — both Helmlab
     variants pick a different ANSI16 entry than the OKLab baseline on **4/15**
     fixtures (`oklabHyAB` diverges on 1/15, `oklabEuclidean` 0/15 by
     definition). Distances are in different units across spaces, so this only
     says *where* the metrics disagree, not which is right.
   - **Large-ΔE visual review** — the predicted `helmlabCompressed` saturation
     **collapse does not appear**. The compression is monotonic, so the argmin
     is preserved: on the synthetic saturated primaries all three policies keep
     6 distinct picks, and on the real images the Helmlab variants use *more*
     distinct ANSI16 entries than OKLab, not fewer — Earthrise: OKLab 7,
     helmlabEuclidean 8, helmlabCompressed 8; Carina Nebula "Cosmic Cliffs":
     OKLab 7, helmlabEuclidean 9, **helmlabCompressed 10**. (Corpus = two NASA
     public-domain photographs, chosen for neutrals + blues + highly saturated
     content.)

5. **Theory — why no win shows up here, and where it would** — The recovery
   oracle and the built-in palettes are the wrong instrument to *detect* a
   MetricSpace edge, even though MetricSpace genuinely wins on COMBVD. Two
   reasons, both novel to this evaluation:
   - **Sparsity hides the metric.** ANSI16/monochrome entries are far apart in
     any reasonable space, so the nearest-entry argmin is decided by gross
     geometry that every ΔE agrees on. A metric's *calibration* only changes
     the winner when two candidates sit near the decision bisector — which on a
     16-entry palette is rare. Prediction: divergence-from-OKLab rate should
     grow monotonically with palette density; a 256-entry palette should push
     the 4/15 divergence well past 27%.
   - **The win is sub-threshold for quantization.** MetricSpace's STRESS edge
     is on *just-noticeable* differences. Palette quantization operates above
     JND by construction (you are snapping to a coarse grid), so the regime
     where MetricSpace is calibrated better is exactly the regime quantization
     discards. The honest hypothesis: **for coarse palettes OKLab is already at
     the quality ceiling, and any trained ΔE is wasted precision.** The place
     to look for a real Aski win is dense, near-continuous palettes (gradient
     LUTs, photographic palettes) and near-threshold source colors — not the
     built-in 16-color sets.
   - **Corollary (queued in Discoveries):** a hybrid — `helmlabCompressed` for
     near candidates, monotonic `helmlabEuclidean`/OKLab for ranking distant
     ones — is only worth building once a dense-palette oracle shows the two
     pure variants split by distance regime. The current data shows no such
     split, so the hybrid stays YAGNI.

6. **Verdict** — Both policies ship as experimental opt-ins (ASTSK-2 requires
   exposure); promotion-to-default is out of scope and unsupported by this
   evidence. The doc-comments and `PaletteMatching.md` state the thin evidence
   plainly, mirroring `oklabHyAB`. STRESS vs COMBVD was **not** recomputed —
   the dataset is not bundled; we rely on the machine-precision forward-vector
   and ΔE-case validation. No CI gate is coupled to STRESS.

7. **Sources** — [arxiv](https://arxiv.org/abs/2602.23010) ·
   [helmlab](https://github.com/Grkmyldz148/helmlab) ·
   [Color.js #722](https://github.com/color-js/color.js/pull/722) ·
   corpus imagery [images.nasa.gov](https://images.nasa.gov) (public domain).
