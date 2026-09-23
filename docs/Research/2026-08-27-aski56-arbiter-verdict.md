---
title: "ASKI-56 perceptual arbiter — validation run verdict: instrument PASSES its gate, the 3.0% bar straddles the JND75 band and is retained"
slug: 2026-08-27-aski56-arbiter-verdict
date: 2026-08-27
status: complete
subsystem: [shape-context]
summary: "The frozen v1 arbiter protocol was executed end to end: 45 blinded human trials rated in one sitting plus the pinned VLM leg (gpt-5.6-terra, both orders, K=3). Both §5.1 validation gates PASS at 6/6 — human and VLM each recover the unanimous five-oracle tone-floor-vs-production inversion on every source, so the instrument is validated and its verdicts count. The human leg prefers the lower-MAE side on 32 of 37 decided trials (exact one-sided binomial p ≈ 0, tie rate 0.075, repeat consistency 0.80): MAE's direction is perceptually grounded. Calibration (27 C+M trials, relative-MAE-margin units per erratum E2) yields a JND75 band of −0.345 to +0.072 with point −0.029, bootstrapped by source over 1676/2000 usable resamples; the band contains its point estimate and straddles the 3.0% bar, so per the pre-registered §5.2 rule the bar is RETAINED, recorded as sitting inside the ambiguity interval, and the arbiter — not the bar alone — is required for any default promotion. On the D (disagreement) family, the ASKI-30 SSIM-inversion near-tie, the rater chose the lower-MAE side on only 1 of 4 decided trials with 2 ties, and the VLM's order-inconsistency rate was 0.50 — recorded, not gated: weak evidence the 0.09% SSIM objection is on the perceptible side of a genuine near-tie, far below the decided-n threshold for a verdict line."
related_specs: [docs/Research/2026-08-25-aski56-arbiter-protocol.md, docs/Research/2026-08-24-aski-30-28-decisive-rule.md, docs/Research/2026-08-24-aski-30-28-battery-verdict.md, docs/Research/2026-08-19-house-oracle-audit.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1]
runners: [AskiColorLab]
next_action: "The 3.0% bar stands; every future default promotion runs through `AskiColorLab arbiter score` with the §5.3 near-tie clamp. ASKI-30 remains INCONCLUSIVE — the recorded D behavior leans toward the floor but is 4 decided trials; a dedicated D-focused arbiter run (the instrument is now validated and cheap to re-run) is the way to settle it if promotion of the tone-weighted arm is ever wanted."
---

# ASKI-56 arbiter — validation run verdict (executed 2026-08-25 → 2026-08-27)

Machine-applied readout: `docs/Research/Results/2026-08-27-aski56-arbiter/readout.md`
(result store also holds `result.yaml` and `manifest.json`; the blinded `answers.csv`, `key.json`,
and the VLM leg's `judge.json` + `judge-results.json` are not published). Stimuli
PNGs (135 images + 45 composites) are reproducible from the pinned command in
`manifest.json` (seed 0, columns 80, oversample 2, footprint 24) and are not
committed.

Protocol: `docs/Research/2026-08-25-aski56-arbiter-protocol.md` (v1, frozen with
pre-run errata E1–E5 before any vote was collected). No decision rule changed
after the first vote.

## Timeline and provenance

- 2026-08-25: stimuli generated and VLM leg judged at source SHA `892fe13`
  (recorded in `manifest.json` / `judge.json`).
- 2026-08-26 (local): the owner rated all 45 pairs blind, in one sitting, on one
  display, before `key.json` was opened by anyone.
- 2026-08-27 (UTC): `arbiter score` joined answers + judge results against the
  key; exit 0.
- The branch was rebased onto main between the machine legs and scoring, which
  rewrote `892fe13` → `b5e9434`. The two trees are identical in every source,
  resource, and doc file; the only difference is an appended checkpoint note in
  one backlog task file. The recorded SHAs name the true measurement tree.

## What the run established

1. **The instrument is valid (§5.1, AC#2).** Human 6/6 and VLM 6/6 on the V
   family — both legs independently recover the unanimous five-oracle
   tone-floor-vs-production inversion on all six sources. The VLM's verdicts
   count under its pinned config; any judge change re-runs this gate.
2. **MAE's direction is perceptually real (AC#3, first half).** 32/37 decided
   trials chose the lower-MAE side (p ≈ 0). The house oracle points the right
   way on these fixtures.
3. **The 3.0% bar sits inside the ambiguity interval (AC#3, disposition).**
   JND75 band −0.345 to +0.072 relative MAE margin (point −0.029, 1676/2000
   usable source-bootstrap resamples, band contains its point estimate). The
   band straddles 0.030, so per the pre-registered §5.2 rule the bar is
   **retained**, explicitly recorded as not-perceptually-resolving on its own,
   and **any default promotion requires the arbiter, not the bar alone**. The
   width is the honest consequence of 27 fit trials over 6 sources — the
   reviewer's pre-registered expectation — not a fittable-away artifact.
4. **The ASKI-30 near-tie behaves like a near-tie (D family, recorded not
   gated).** Tone-weighted T(w*=2) vs floor F: 1/4 decided trials for the
   lower-MAE side (T), 2 ties, and the rater's other 3 decided picks went to F —
   the side single-scale SSIM preferred by 0.09%. The VLM flip-flopped across
   presentation orders on half these pairs (order-inconsistency 0.50). This is
   weak, small-n evidence that the SSIM objection tracked something visible; it
   does not convert ASKI-30's INCONCLUSIVE (decided n = 4 against a
   pre-registered threshold of 30), and per §5.3 pairs this close fall to the
   human leg only.

## Standing-rule consequences (AC#4)

- `2026-08-24-aski-30-28-decisive-rule.md` §7: the arbiter is no longer parked;
  the promotion path runs through `arbiter score` with the PresetLab contact
  sheet demoted to an informal preview. Addendum appended there.
- `2026-08-24-aski-30-28-battery-verdict.md`: resolution note appended — the
  discriminator named as missing now exists and is validated; ASKI-30 stays
  INCONCLUSIVE pending a D-focused run.
- Near-tie clamp (§5.3): as frozen, the clamp keys on the band's **lower
  edge**, and this run's lower edge is negative (−0.345) — so the clamp as
  written fires on no pair and is vacuous under this fit. Recorded as-is; the
  §5.2 disposition (arbiter required for any promotion) subsumes it, and a
  tighter future fit with a positive lower edge would re-arm it without any
  rule change.
