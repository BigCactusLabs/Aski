---
title: "ASTSK-45 Source-Tethered Glyph Hysteresis (Motion-Adaptive Debounce) for ASCII Temporal Coherence - Verdict"
slug: 2026-07-01-astsk45-source-tethered-hysteresis
date: 2026-07-01
status: complete
subsystem: [animation, shape-context, frontier]
summary: "KILL (non-robust), gate-emitted. The surviving ASTSK-41 lead — tether the glyph hold to the SOURCE, not the challenger — was measured over the same deterministic synthetic stimuli (S1 slow disc, S2 fast bar) at columns 64/80, sweeping rho in {0,0.25,0.5,1.0,2.0} at alpha=1 (EMA off), N=48 frames, fidelity anchored to the SOURCE (GMSD cross-checked by HaarPSI). The mechanism is genuinely NOT inert (unlike ASTSK-41's EMA): rho reduces glyph churn monotonically on BOTH stimuli. But it is scene-dependent. On S1 every rho qualifies in both columns (churn -87 to -88% at held fidelity). On S2 NO rho qualifies in either column — the churn drop is bought by washout (source-GMSD +6.2 to +7.7% past the x1.02 band, HaarPSI -10.1 to -13.5% past the x0.99 band, drift-vs-baseline ~0.27), the full freeze-trap triple; even rho=0 (release on any degradation) busts S2 fidelity, because on a fast source any held glyph strictly worsens the source match. The shared rho (rho=2.0) qualifies in 2/4 cells (both S1, neither S2) -> non-robust KILL, exactly the frontier-predicted most-likely death (scene-dependence across the slow/fast regime split). The oracle-sign band did NOT RERUN: on S2 both oracles agree fidelity worsened (same sign), so this is a clean real KILL, not instrument ambiguity. Default render byte-identical; hook stays @_spi off-by-default. Third falsification of the NCA temporal line (ASTSK-41 EMA, ASTSK-43 inter-cell, now ASTSK-45 source-tether)."
related_specs: [docs/Research/2026-06-29-astsk41-nca-temporal-prior.md]
runners: [AskiMotionLab]
next_action: "No default-promotion task. Fixed-tolerance glyph hysteresis is now falsified BOTH ways — relative-to-challenger (ASTSK-41 tau) and source-tethered (ASTSK-45 rho) — across the slow/fast regime split: no single scalar tolerance is robust. B2 is a real mechanism (churn falls monotonically, unlike inert EMA) but its built-in motion-adaptivity is insufficient. The only untried lever is an EXPLICIT per-cell motion/velocity signal scaling the tolerance rho(v) (the TAA confidence-factor analog) — a second parameter the pre-registration deliberately avoided, requiring a motion estimator the pipeline lacks, at low post-1.0 ROI since the ASCII medium itself cannot track fast motion (baseline S2 GMSD ~0.35). Captured as a theory below for later triage; not auto-filed. The Schmitt-band follow-up named in spec-6 would NOT rescue this — the KILL is scene-dependence, not boundary chatter."
---

# ASTSK-45 — Source-tethered glyph hysteresis (motion-adaptive debounce) for ASCII temporal coherence

**Status:** SETTLED — **KILL (non-robust)**, gate-emitted (2026-07-01). Every constant was frozen in the
pre-registration spec (`2026-07-01`, commit `8a79a63`) **before any measurement**; results + verdict are
appended here after the run, with no constant tuned to a result.
**Branch:** `astsk-45-source-tethered-hysteresis` · **Pre-registration:** the ASTSK-45 source-tethered-hysteresis design spec.
**Design lineage:** ASTSK-41 KILL (2026-06-29) → its `next_action` (theory 3: attack the discrete pick with a
source-fidelity tether) → 2026-07-01 frontier-search (temporal-coherence history rejection; TAA
motion-adaptive tolerance) → this gate. This is a **thin addendum** to the ASTSK-41 pre-registration; it
reuses that spec's instrument, stimuli, oracles, gate machinery, and discipline by reference.

---

## Mechanism under test (frozen)

An off-by-default `@_spi(AskiResearch)` lever on the **discrete** glyph pick in the existing temporal path
(`Sources/Aski/Animation/ASCIIConverter+Temporal.swift`), with **EMA fixed off (α=1)** — a 1-D experiment on
the single parameter `ρ`:

- On glyph lock (a frame where the displayed glyph changes) record `lockDist = distance(displayedGlyph,
  source)` — the held glyph's fit to the source **at its first appearance**.
- Per subsequent frame: **hold** the displayed glyph iff its fit to the *current* source stays within `ρ` of
  its commit fit (`heldDist ≤ lockDist · (1+ρ)`); otherwise **release** to the per-frame argmax.
- `lockDist` re-anchors **only on a genuine first appearance** (a frame where the displayed glyph changes) —
  a hold, or a release whose argmax equals the held glyph, carries it forward untouched. This bounds a held
  glyph's cumulative staleness to `ρ` relative to its first appearance (the rejected alternative — re-anchor
  on every release — was frozen out because it ratchets tolerance upward across a slow drift).

This is the **opposite of EMA** (which holds hardest exactly when the source moves fastest): here the hold
weakens in proportion to source motion, because source motion is what degrades the held glyph's fit. The
default render is byte-identical; the hook is inert unless a frame loop opts in (`sourceTetherRho` defaults
`nil`). AC#4 held.

## Measurement (frozen)

Same deterministic synthetic stimuli as ASTSK-41 — **S1** (slow translating disc) and **S2** (fast
translating bar) — at columns {64, 80}, sweeping `ρ ∈ {0, 0.25, 0.5, 1.0, 2.0}` at `α=1` (EMA off), `N=48`
frames. Stability = mean glyph churn frame-to-frame. **Fidelity is anchored to the SOURCE:** `GMSD` vs the
source frame, cross-checked by `HaarPSI`. Per (stimulus, column) cell, a `ρ` qualifies iff churn drops ≥20%
vs the `α=1` per-frame-independent (no-tether) baseline **and** `GMSD ≤ baseline × 1.02` **and** `HaarPSI ≥
baseline × 0.99` — the ASTSK-41 §7 triple screen and tolerance constants reused verbatim. The verdict reads
off ONE shared `ρ` (qualifying in the most cells; ties → larger churn drop). PASS requires it to qualify in
**all four** cells.

## Result — the full four-cell ρ grid

`shared_pass_point = (ρ=2.0)`. The `ρ=2.0` per-cell comparison (full grid below):

| stim | col | mean glyph churn B → T | GMSD vs source B → T | HaarPSI B → T | qualifies@shared |
|------|-----|------------------------|----------------------|---------------|------------------|
| S1   | 64  | 0.0120 → 0.0014 (−88%) | 0.4359 → 0.4371 (+0.3%) | 0.0796 → 0.0790 (−0.8%) | **yes** |
| S1   | 80  | 0.0108 → 0.0014 (−87%) | 0.4338 → 0.4349 (+0.3%) | 0.0761 → 0.0762 (+0.1%) | **yes** |
| S2   | 64  | 0.0630 → 0.0064 (−90%) | 0.3538 → 0.3812 (**+7.7%**) | 0.1025 → 0.0887 (**−13.5%**) | **no** (GMSD + HaarPSI bust) |
| S2   | 80  | 0.0561 → 0.0061 (−89%) | 0.3534 → 0.3752 (**+6.2%**) | 0.1010 → 0.0908 (**−10.1%**) | **no** (GMSD + HaarPSI bust) |

Worst per-frame GMSD regression at the shared point: s1/64 f47 +0.0025; s1/80 f47 +0.0024; **s2/64 f47
+0.0676; s2/80 f47 +0.0583**.

Full grid (release build, reproduces byte-for-byte):

```
[s1 / cols=64] baseline churn=0.0120 GMSD=0.4359 HaarPSI=0.0796
  rho=0.0   churn=0.0048 GMSD=0.4373 HaarPSI=0.0789 drift=0.0711  pass
  rho=0.25  churn=0.0029 GMSD=0.4372 HaarPSI=0.0789 drift=0.0741  pass
  rho=0.5   churn=0.0022 GMSD=0.4372 HaarPSI=0.0790 drift=0.0758  pass
  rho=1.0   churn=0.0018 GMSD=0.4371 HaarPSI=0.0790 drift=0.0778  pass
  rho=2.0   churn=0.0014 GMSD=0.4371 HaarPSI=0.0790 drift=0.0792  pass
[s1 / cols=80] baseline churn=0.0108 GMSD=0.4338 HaarPSI=0.0761
  rho=0.0   churn=0.0037 GMSD=0.4352 HaarPSI=0.0759 drift=0.0718  pass
  rho=0.25  churn=0.0028 GMSD=0.4351 HaarPSI=0.0759 drift=0.0738  pass
  rho=0.5   churn=0.0023 GMSD=0.4351 HaarPSI=0.0760 drift=0.0760  pass
  rho=1.0   churn=0.0017 GMSD=0.4350 HaarPSI=0.0761 drift=0.0775  pass
  rho=2.0   churn=0.0014 GMSD=0.4349 HaarPSI=0.0762 drift=0.0815  pass
[s2 / cols=64] baseline churn=0.0630 GMSD=0.3538 HaarPSI=0.1025
  rho=0.0   churn=0.0212 GMSD=0.4009 HaarPSI=0.0823 drift=0.2680
  rho=0.25  churn=0.0136 GMSD=0.3969 HaarPSI=0.0830 drift=0.2759
  rho=0.5   churn=0.0115 GMSD=0.3942 HaarPSI=0.0836 drift=0.2758
  rho=1.0   churn=0.0092 GMSD=0.3895 HaarPSI=0.0855 drift=0.2748
  rho=2.0   churn=0.0064 GMSD=0.3812 HaarPSI=0.0887 drift=0.2712
[s2 / cols=80] baseline churn=0.0561 GMSD=0.3534 HaarPSI=0.1010
  rho=0.0   churn=0.0160 GMSD=0.3949 HaarPSI=0.0821 drift=0.2689
  rho=0.25  churn=0.0123 GMSD=0.3887 HaarPSI=0.0847 drift=0.2678
  rho=0.5   churn=0.0104 GMSD=0.3870 HaarPSI=0.0847 drift=0.2708
  rho=1.0   churn=0.0078 GMSD=0.3808 HaarPSI=0.0879 drift=0.2700
  rho=2.0   churn=0.0061 GMSD=0.3752 HaarPSI=0.0908 drift=0.2680
```

**Verdict: KILL — non-robust.** The best `ρ` qualifies in 2/4 cells (both S1, neither S2). No single `ρ`
holds churn-down-at-fidelity-held across all four cells.

## Why it died (mechanistic — a real mechanism, but scene-dependent)

The headline is more informative than "non-robust." Reading churn down each cell's `ρ` column shows the
source-tether is **genuinely not inert** — churn falls monotonically as `ρ` grows, on *both* stimuli
(S1/64: 0.0120 → 0.0014; S2/64: 0.0630 → 0.0064). That is the sharpest contrast with ASTSK-41, where the EMA
prior reduced churn *nowhere* and the hysteresis deadband did all the work. **B2 does something.** It fails on
generalization, not on effect:

- **S1 (slow disc) — the predicted PASS shape.** The source barely moves per frame, so a held glyph's fit
  degrades slowly; every `ρ` (including `ρ=0`) keeps `heldDist` within tolerance and holds cheaply. Churn
  drops 87–88% while GMSD and HaarPSI stay flat inside band. Idle-flicker suppression at held fidelity — the
  hypothesis, realized.
- **S2 (fast bar) — the freeze-trap.** The source moves substantially per frame. Reducing churn requires
  holding, but on a fast source *any* hold shows a glyph the per-frame argmax has already moved off, so the
  composited luma diverges from the source: GMSD climbs +6.2 to +7.7% (past the ×1.02 band), HaarPSI falls
  −10.1 to −13.5% (past the ×0.99 band), and drift-vs-baseline sits at ~0.27 — the full ASTSK-41 freeze-trap
  triple (churn↓ + drift↑ + source-GMSD↑). **Even `ρ=0`** — release on *any* degradation — busts S2 fidelity
  (GMSD +13% at `ρ=0`), because the baseline per-frame argmax is already the best per-frame fit and the ASCII
  medium cannot track a fast bar; the tether's occasional held frames can only make the source match worse.
  There is no `ρ` on S2 that reduces churn without busting fidelity.

So the shared `ρ=2.0` qualifies in the two S1 cells and neither S2 cell → **non-robust**: a single fixed
tolerance cannot span the slow/fast regime split. This is precisely the frontier-informed prior from spec §6
(“a single shared ρ across slow+fast is at real risk of the same 2/4 non-robust shape ASTSK-41 hit — that
risk is the point of the test”).

**Two pre-registered predictions, checked honestly:**

1. Spec §5 named **HaarPSI busting on S2** as *the single most likely KILL vector* (“the tether bounds the
   wrong oracle”). Reality is stronger: on S2 **both** oracles bust, and they **agree in sign** (both say
   fidelity worsened) → the oracle-sign equivalence band did **not** RERUN → a clean, unambiguous KILL. The
   log-polar commit-fit tolerance (`distance(held, source)` within `ρ`) and the composited-luma GMSD/HaarPSI
   genuinely decouple under large source motion, so the “partly mechanical GMSD pass” the spec disclosed did
   **not** protect S2 — GMSD busted there too.
2. Spec §6 pre-identified the **Schmitt band** as the next step *if the run showed boundary chatter*. It did
   not — the neither-S2-cell KILL is scene-dependence, not chatter. A two-threshold band is still a single
   fixed tolerance and would not make `ρ` robust across S1/S2. Correctly **not** chased.

## Theories generated (for later triage, not assumed)

1. **Fixed-tolerance glyph hysteresis is now falsified both ways.** Relative-to-challenger (`τ`, ASTSK-41)
   and source-tethered (`ρ`, ASTSK-45) both hit the same 2/4 non-robust wall: any *scalar* tolerance that
   suppresses S1 idle flicker at fidelity washes out S2. The regime split (slow vs fast) is the invariant
   killer, not the reference the tolerance is measured against.
2. **The only untried lever is an explicit motion signal.** TAA's fix (spec §6) is a velocity/confidence
   factor that tightens tolerance during motion; B2 tried to get this *structurally* (the fit-degradation
   rate is itself a motion proxy) and the result shows that built-in adaptivity is **insufficient** — the
   proxy still can't distinguish “held glyph fits by luck” from “source has moved on” on a fast bar. A
   genuinely motion-adaptive `ρ(v)` scaling per-cell tolerance by an estimated source velocity is the
   remaining direction — but it needs a motion estimator the pipeline lacks, adds the second free parameter
   the pre-registration avoided, and carries low post-1.0 ROI given the ASCII medium's ~0.35 baseline GMSD on
   fast motion (it cannot render a fast bar faithfully regardless of coherence). **Not auto-filed.**
3. **`meanDriftVsBaseline` as an early-exit screen.** On S2 drift jumps to ~0.27 the moment the tether
   engages, while on S1 it stays ~0.07–0.08. Drift-vs-baseline alone cleanly separates “coherence” from
   “washout” before the fidelity oracles are even consulted — a cheap first-pass filter for any future
   coherence lever, corroborating the ASTSK-41 freeze-trap-triple instrument.

## Product decision

**No default promotion.** The hook stays `@_spi(AskiResearch)` off-by-default; default rendering and the
shipped animation path are byte-identical (AC#4 held). The `sourceTetherRho` lever and `lockDistance` state
remain in the tree as research instruments, inert unless opted in.

## Acceptance criteria

- **AC#1** — source-tethered hysteresis on the discrete pick; no leaky integration (α=1 fixed); no learned
  model; hand-authored. **Met** (`convertTemporalFrame` `sourceTetherRho` / `lockDistance`).
- **AC#2** — reuse the AskiMotionLab temporal-prior harness over S1/S2; fidelity anchored to the source
  (GMSD × HaarPSI); screen against the freeze-trap triple. **Met** (`SourceTetherExperiment`).
- **AC#3** — gate pre-registered before measuring; no constant tuned after seeing numbers. **Met** (spec
  frozen at commit `8a79a63`, before any implementation or measurement).
- **AC#4** — default render and shipped animation path byte-identical; lever `@_spi` off by default. **Met**
  (`sourceTetherRho` nil-default; production `convert` never calls the hook).
- **AC#5** — verdict recorded under `docs/Research` with PASS/KILL framing. **Met** (this note).

## Reproduce

```bash
xcrun swift run -c release AskiMotionLab source-tether --stimulus all --columns all --output-dir /tmp/astsk45
xcrun swift test --filter 'SourceTetherGate|SourceTether|SyntheticMotion'
```

Deterministic: the grid reproduces byte-for-byte on this branch.
