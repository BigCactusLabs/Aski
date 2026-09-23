---
title: "AskiDecolorLab Composited-Cell Perceptual Oracle (Phase 0 keystone gate)"
slug: 2026-06-09-decolor-oracle
date: 2026-06-09
status: complete
subsystem: [color-science]
summary: "AskiDecolorLab recomposites each rendered ASCIICell as k·FG+(1−k)·BG in linear light and scores it against the source-cell OKLab aggregate. At columns=80 the FAIL-FAST gate PASSES: mean l_fidelity discriminates monochrome>ansi16>fullColor with disjoint 95% CIs, and a 2AFC test separates true sub-glyph half-tones from mean-L-matched flats at d′=2.49 — validating the area-tone thesis and unlocking Phase 1/2. The ansi16↔fullColor separation is marginal/resolution-dependent (overlaps at columns=64); k uses the relative brightness ramp (first-cut)."
related_specs: [docs/research-plan.md]
datasets: []
runners: [AskiDecolorLab]
next_action: "Phase 1 follow-ups have been executed or split: .bin v2 shipped, Thread C full-strength back-solve is KILL with revival candidates in docs/Research/2026-06-10-thread-c-ink-precompensation.md, and Thread D chromaShapeAssist PASS is deferred to ASTSK-36 for dose-response and real-image calibration. Remaining color-plan work is E1 two-color cells and the E2 EDR sketch."
---

# AskiDecolorLab Composited-Cell Perceptual Oracle (Phase 0 keystone gate)

## Question

Aski's color-research corpus repeatedly stalled at "no measured win" because every
prior metric scored the wrong signal: the raw cell-average ΔE, when the eye
actually sees the *area-toned composite* of glyph ink over background,
`k·FG + (1−k)·BG`. This keystone asks two falsifiable questions:

1. **Discrimination** — does scoring the recomposited cell appearance rank color
   fidelity across palettes (more color → lower error: `monochrome > ansi16 > fullColor`)?
2. **2AFC (the thesis)** — can the area-tone model distinguish a *true sub-glyph
   half-tone* cell from a *flat tone matched in mean L* better than chance? If it
   cannot, that is the designed, publishable KILL of the whole "score the
   composite, not the average" program.

A failure on either is a green-to-red CI signal that converts a queue of color
nulls into a verdict and stops Phases 1–2 before they start.

## Method

`AskiDecolorLab` ships two SAP subcommands:

```bash
swift run AskiDecolorLab evaluate --output-dir /tmp/decolor-lab-2026-06-09 --columns 80 --background-hex '#101010'
swift run AskiDecolorLab check --output-dir /tmp/decolor-check --columns 80    # FAIL-FAST gate; nonzero exit == KILL
```
(Run at git `50381d4`. `check` writes nothing — it requires `--output-dir` only because it shares `ProvenanceOptions`; see Caveats.)

The lab drives the **real** `ASCIIConverter` pinned to `.sRGB` over five
deterministic synthetic fixtures (`hue-stripes`, `neutral-ramp`, `edge-contrast`,
`isoluminant-swatch`, `low-ink-sparse`) against three palettes (`monochrome`,
`ansi16`, and `fullColor` = the pass-through palette). Per `ASCIICell` it reads
the chosen `character` + `displayColor` (FG), resolves the ink fraction `k` from
the standard character set's **relative brightness ramp** (first-cut;
`ink_model=relative_ramp`), composites `perceived = k·linear(FG) + (1−k)·linear(BG)`
in linear light, converts to OKLab, and compares against the source-cell OKLab
aggregate (a local linear-light block average of the lab's own fixture pixels).

A **no-downscale invariant** guards the source ground truth: the lab throws if the
converter would thumbnail the fixture (`max(cols,rows)·oversample < longest side`),
so the source aggregate is sampled at the same resolution the converter sampled.
This keeps the metric a measure of *recompositing fidelity*, not ImageIO
resampling loss. (At `columns=80`, `maxPixelSize = 160 ≥ 96`, so the 96×48
fixtures are never downscaled.)

Metrics per cell: `l_fidelity = |ΔL|`, `chroma_fidelity = |Δchroma|`,
`oklab_delta = ‖Δ‖` in OKLab. The gate combines **discrimination** (a seeded
percentile-bootstrap of each palette's mean `l_fidelity`, requiring descending
means with disjoint adjacent 95% CIs) and **2AFC** (a signal-detection `d′` over
512 seeded synthetic half-tone vs mean-L-matched-flat trials).

The lab is deterministic on a given Aski revision, toolchain, SDK, and OS, but
exact glyph/color rows can drift across platform revisions. Treat
`perceived_fidelity.csv` as a platform-pinned research snapshot, not a CI
byte-diff baseline.

## Findings

The `evaluate` run produced **21,600 rows**. The `check` gate verdict at
`columns=80`:

**Discrimination — PASS.** Mean `l_fidelity` descends with color count, adjacent
95% bootstrap CIs disjoint:

| Palette | mean l_fidelity | 95% CI |
| --- | ---: | --- |
| `monochrome` | 0.1385 | [0.1359, 0.1408] |
| `ansi16` | 0.0579 | [0.0570, 0.0589] |
| `fullColor` | 0.0556 | [0.0549, 0.0563] |

**2AFC — PASS.** `d′ = 2.4937` (threshold 0.5); signal (half-tone) μ=0.0078
σ=0.0060, noise (flat, mean-L matched) μ=0.1074 σ=0.0561.

**Gate verdict: PASS — Phase 1/2 unlocked.**

Interpretation: the area-tone thesis holds. The 2AFC `d′` is driven entirely by
the **OKLab-L Jensen gap** — L is concave in linear luminance (`cbrt`), so the
linear-light composite of a half-tone (`L(½·linFG+½·linBG)`) differs from the
coverage-blind L-average (`½·L(linFG)+½·L(linBG)`) that defines the matched flat.
An independent check confirmed the construction is falsifiable, not rigged: with
L forced linear, `d′` collapses to ≈0.04 (a correct KILL). `monochrome`'s high
error is the expected loss of all chroma (a grey composite scored against a
saturated source).

## Caveats and first-cut tradeoffs

- **Relative-ramp `k` (first-cut).** `k` comes from the relative brightness ramp,
  which is monotonic with — but biased against — the true ink area fraction. That
  is valid for *discrimination/ranking* (what the gate tests) but biased for
  *absolute* L-fidelity. The absolute-fraction `k` (the `.bin` v2 raw-density
  block) is deferred to Phase 1 Thread C.
- **Marginal ansi16↔fullColor separation.** The headline discrimination win is
  really `monochrome` vs *color*. The `ansi16`↔`fullColor` CIs are disjoint at
  `columns=80` (gap ≈ 0.0007) but **overlap at `columns=64`**, where the gate
  KILLs. The deeper coverage-aware-vs-coverage-blind signal is the intended job of
  the `low-ink-sparse` fixture and the absolute-`k` work in Phase 1; treat the
  ansi16/fullColor separation as weak first-cut evidence, not a settled win.
- **CVD deferred.** `deficiency` is emitted as `none`; the CVD variant (three
  Brettel-1997 deficiencies) is a follow-up slice that will decide `CVDModel`
  placement (it currently lives in the `AskiAccessLab` target).
- **`check` ergonomics.** The gate subcommand requires a `--output-dir` it never
  writes to. Minor follow-up: give `check` its own options without
  `ProvenanceOptions`' required output dir.
- **CSV footprint.** `perceived_fidelity.csv` is ~6.3 MB at `columns=80`; the
  per-row `command` column is redundant bulk. A follow-up could trim the schema
  or commit per-palette aggregates instead of the full row dump.

## Next action

Phase 0 is complete. The gate PASS unlocked Phase 1, and the immediate follow-ups
have now been executed or split:

- `.bin` v2 raw-density vectors shipped.
- Thread C full-strength ink pre-compensation is a measured KILL; see
  `docs/Research/2026-06-10-thread-c-ink-precompensation.md` for revival
  candidates.
- Thread D `chromaShapeAssist` is a measured PASS (rescue, 2026-06-10). The
  `ASTSK-36` λ dose-response PASS was later retracted as a sampling-lattice
  artifact (ASKI-65, 2026-09-02) and is INCONCLUSIVE pending ASKI-66.
- Thread B residual work continues as `ASTSK-31`; remaining color-plan work is E1
  two-color cells and the E2 EDR sketch in `docs/research-plan.md`.
