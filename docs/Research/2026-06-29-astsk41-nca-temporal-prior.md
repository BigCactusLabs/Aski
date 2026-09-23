---
title: "ASTSK-41 NCA-Style Local-Update Temporal Prior for ASCII Animation - Verdict"
slug: 2026-06-29-astsk41-nca-temporal-prior
date: 2026-06-29
status: complete
subsystem: [animation, shape-context, frontier]
summary: "KILL (non-robust), gate-emitted. A hand-authored off-by-default @_spi temporal prior (EMA leaky-integration on the continuous cell-state + score-margin hysteresis on the logPolar glyph pick) was measured over deterministic synthetic moving stimuli (S1 slow disc, S2 fast bar) at columns 64/80, alpha in {1,0.6,0.35,0.2} x tau in {0,0.05,0.1,0.2}, N=48 frames, fidelity anchored to the SOURCE (GMSD cross-checked by HaarPSI). The frozen shared operating point (alpha=0.6, tau=0.2) qualifies in only 2/4 cells (both S1, neither S2). Mechanistic finding: the EMA prior (the actual NCA bounded-local-change mechanism) reduces glyph churn nowhere; at fixed tau the churn is flat-or-worse as EMA strengthens, and on S2 strong EMA increases churn and drives the freeze-trap. All churn reduction comes from the hysteresis deadband (a debounce on the discrete pick), which already achieves the drop at alpha=1 on S1 and only holds fidelity where the source barely moves; on S2 it busts fidelity by washout/lag (GMSD +1.9 to +10.7 percent, drift-vs-baseline 0.26 to 0.29). Both spec-9 death paths realized (inert EMA + freeze-trap). Default render byte-identical; hook stays @_spi off-by-default. This note records the run-2 verdict after a pre-registered re-instrument of the oracle-sign check (run-1 returned RERUN on a noise-floor sign split in s1/80)."
related_specs: [docs/Research/2026-06-18-neural-cellular-automata-implicit-decoder.md]
runners: [AskiMotionLab]
next_action: "No default-promotion task. If temporal coherence is revisited, attack the DISCRETE pick with a source-fidelity tether (motion-adaptive hysteresis: suppress a glyph switch only when the source-residual is below threshold), not the continuous state via leaky integration. Captured as a theory below for later triage."
---

# ASTSK-41 — NCA-style local-update temporal prior for ASCII animation

**Status:** SETTLED — **KILL (non-robust)**, gate-emitted (2026-06-29). Constants were frozen in the
pre-registration spec (2026-06-26) before any measurement; results + verdict are appended here after the run,
with no constant tuned to a result.
**Branch:** `astsk-41-nca-temporal-prior` · **Pre-registration:** the 2026-06-26 ASTSK-41 NCA-temporal-prior design spec
**Design lineage:** 2026-06-18 NCA cross-domain brief (the temporal prior was its highest-value transfer) →
2026-06-26 frontier-search (rule form + fidelity-vs-source metric) → this gate.

---

## Mechanism under test (frozen)

An off-by-default `@_spi(AskiResearch)` conversion path in `Sources/Aski`, two composable levers applied to
the continuous per-cell state **before** glyph quantization:

- **EMA** — leaky-integration of the continuous cell-state across frames (parameter `α`; `α=1` = no
  integration, the per-frame-independent baseline). This is the NCA "bounded local change" approximation.
- **Hysteresis** — a score-margin deadband on the discrete glyph pick (parameter `τ`): keep the previously
  chosen glyph unless a challenger beats it by more than `τ`, scored via the new
  `LogPolarKernel.distance(ofGlyph:forCell:)`.

The default render is byte-identical; the hook is inert unless a frame loop opts in (AC#5).

## Measurement (frozen)

Deterministic synthetic moving stimuli — **S1** (slow translating disc) and **S2** (fast translating bar) —
at columns {64, 80}, over the grid `α ∈ {1, 0.6, 0.35, 0.2} × τ ∈ {0, 0.05, 0.10, 0.20}`, `N = 48` frames.
Stability = mean glyph churn frame-to-frame. **Fidelity is anchored to the SOURCE** (not the processed
output): `GMSD` vs the source frame, cross-checked by `HaarPSI`. Per (stimulus, column) cell, an operating
point qualifies iff churn drops ≥20% relative to the `α=1, τ=0` baseline **and** `GMSD ≤ baseline × 1.02`
**and** `HaarPSI ≥ baseline × 0.99`. The verdict reads off ONE shared operating point with `α<1` (the one
qualifying in the most cells; ties → larger churn drop). PASS requires it to qualify in **all four** cells.

## Re-instrument provenance (run-1 RERUN → run-2 KILL)

The first decisive run (commit `90b0876`) returned `RERUN (instrument)`: the `α=0.6, τ=0.2` shared point in
**s1/80** showed GMSD slightly worse (Δ≈−0.0004) while HaarPSI was slightly better (Δ≈+0.0002) — a sign
disagreement, but at the **noise floor** (0.09% / 0.26%, an order of magnitude below the gate's own ±2% / −1%
qualify bands). The frozen gate used an absolute float-dust deadband (`oracleSignDeadband = 1e-4`) for the
oracle-sign check, so it tripped on this sub-band split and short-circuited before the substantive verdict.

Per spec discipline the frozen gate is not tuned after seeing numbers, so this was handled as a **new
pre-registration** (spec §7.1, committed `7a4921d` **before** re-measuring): the oracle-sign check is reframed
as a per-oracle **equivalence-bound (SESOI) test** with bounds set equal to the already-frozen §7 qualify
tolerances — GMSD `baseline × 0.02`, HaarPSI `baseline × 0.01`. RERUN fires only when **both** oracles move
beyond band **and** the signs differ; a within-band change is "fidelity held", not instrument failure. Zero
new free parameters. This is the canonical equivalence-testing frame (declare "no meaningful difference" by
bounding the effect within a pre-specified smallest-effect-size-of-interest / indifference zone; Lakens 2017,
*Equivalence Tests: A Practical Primer*; Lakens, Scheel & Isager 2018, *A Tutorial*), and it sidesteps the
"not significantly different ≠ equivalent" fallacy because the change is deterministic and measured to lie
*within* the SESOI.

The re-run (commit `263fccc`) reproduced **every** churn / GMSD / HaarPSI / worst-frame number byte-for-byte;
the only line that changed was the verdict: `RERUN` → `KILL (non-robust)`. That is the cleanest possible
evidence the re-instrument changed the *instrument*, not the *measurement*. At the shared point the s1/80 split
is now correctly inside band (GMSD band ±0.0087, HaarPSI band ±0.00076) and the other three cells have
same-sign deltas, so no cell trips the oracle-sign check and the gate reaches its own robustness verdict.

## Result — the one shared point across all four cells

`shared_pass_point = (α=0.6, τ=0.2)`.

| stim | col | mean glyph churn B → T | GMSD vs source B → T | HaarPSI B → T | qualifies@shared |
|------|-----|------------------------|----------------------|---------------|------------------|
| S1   | 64  | 0.0120 → 0.0009 (−92%) | 0.4359 → 0.4367 (+0.2%) | 0.0796 → 0.0793 (−0.4%) | **yes** |
| S1   | 80  | 0.0108 → 0.0001 (−99%) | 0.4338 → 0.4342 (+0.1%) | 0.0761 → 0.0763 (+0.3%) | **yes** |
| S2   | 64  | 0.0630 → 0.0102 (−84%) | 0.3538 → 0.3918 (**+10.7%**) | 0.1025 → 0.0862 (−15.9%) | **no** (GMSD + HaarPSI bust) |
| S2   | 80  | 0.0561 → 0.0020 (−96%) | 0.3534 → 0.3600 (+1.9%) | 0.1010 → 0.0967 (**−4.3%**) | **no** (HaarPSI bust) |

Worst per-frame GMSD regression at the shared point: s1/64 f47 +0.0018; s1/80 f43 +0.0008; **s2/64 f47
+0.0834; s2/80 f45 +0.0225**.

**Verdict: KILL — non-robust.** The best `α<1` point qualifies in 2/4 cells (both S1, neither S2). No single
`α<1` operating point holds churn-down-at-fidelity-held across all four cells.

## Why it died (mechanistic — the EMA prior is inert; hysteresis debounces; S2 freeze-traps)

The headline "non-robust" understates it. Reading churn at fixed `τ=0.2` across `α` exposes the real biology:

- **s1/80:** churn is **0.0001 at every `α`** — the EMA contributes literally nothing.
- **s1/64:** churn is 0.0009 (`α=1`), 0.0009 (`α=0.6`), 0.0011 (`α=0.35`), 0.0013 (`α=0.2`) — flat, then
  *worse* as EMA strengthens.
- **s2/80:** churn is 0.0004 (`α=1`), 0.0020 (`α=0.6`), 0.0056 (`α=0.35`), 0.0100 (`α=0.2`) — EMA makes churn
  **monotonically worse**.

So the EMA leaky-integration — the actual NCA "bounded local change" mechanism — reduces glyph churn
**nowhere**. The hysteresis deadband `τ` does all of the churn removal, and at `α=1` (no EMA at all) it already
reaches the 20% drop on S1. That is **debouncing the discrete pick, not a temporal prior on the state.** The
`α<1` points qualify on S1 *despite* the EMA, not because of it (τ dominates); formally that is "non-robust"
rather than the gate's "hysteresis-only collapse" trigger, but the substance is the same — spec §9 death path
(a). On S2, the only way churn falls is by the output **lagging/washing out**: drift-vs-baseline climbs to
~0.26–0.29 while GMSD regresses +1.9% (s2/80) to +10.7% (s2/64) — spec §9 death path (b), the freeze-trap.
Both honest priors fired at once.

## Theories generated (for later triage, not assumed)

1. **NCA's abstraction is mismatched to discrete glyph churn.** Glyph identity is an argmax over a quantized
   60D log-polar basis. Smoothing the continuous *pre-quantization* state (EMA) cannot change the argmax
   unless it crosses a decision boundary — which a slow source rarely does (S1: argmax already stable → EMA
   no-op) and a fast source does in the *wrong* direction (S2: EMA lag pulls the state off the true source →
   argmax locks onto a wrong-but-stable glyph = freeze-trap). "Bounded local change" stabilizes the wrong
   variable. This is consistent with the prior log-polar-degeneracy findings (ASTSK-31 regime oracle, ASTSK-35
   basis augmentation): the basis is the bottleneck, and operations on the continuous state upstream of the
   argmax do not transfer to the pick.
2. **The freeze-trap is fully quantified here** and is a clean, reusable instrument: stability bought by lag
   shows as churn-down **with** drift-up **and** source-GMSD-up. Any future coherence lever can be screened
   against this triple cheaply.
3. **A coherence prior that could plausibly work** would act on the *discrete decision with a source tether*:
   motion-adaptive hysteresis — suppress a glyph switch only while the per-cell source-residual stays below a
   threshold, releasing the hold the instant the source actually moves. That is the opposite of leaky
   integration (which holds *hardest* exactly when the source moves fastest). Not chased here; logged as the
   single most promising direction if temporal coherence is reopened.

## Product decision

**No default promotion.** The hook stays `@_spi(AskiResearch)` off-by-default; default rendering and the
shipped animation path are byte-identical (AC#5 held). The EMA + hysteresis levers remain in the tree as
research instruments, off.

## Acceptance criteria

- **AC#1** — local-update rule evolves the cell-state grid frame-to-frame; glyph quantization at render time
  via the existing matcher. **Met** (`TemporalPriorState` / `convertTemporalFrame`).
- **AC#2** — flicker measured vs the baseline at equal-or-near single-frame fidelity, reusing AskiMotionLab.
  **Met, via the registered deviation** (spec §2): C1 is a still image animated by candidate-cycling with no
  source motion, so the baseline is per-frame-independent conversion of a moving source — the reference the
  temporal-consistency literature actually compares against.
- **AC#3** — hand-authored kernel only, no NCA training infrastructure. **Met.**
- **AC#4** — verdict recorded under `docs/Research` with PASS/KILL framing. **Met** (this note).
- **AC#5** — default render and shipped animation path byte-identical; prior opt-in/experimental. **Met.**

## Reproduce

```bash
xcrun swift run -c release AskiMotionLab temporal-prior --stimulus all --columns all --output-dir /tmp/astsk41
xcrun swift test --filter 'TemporalGate|TemporalPrior|SyntheticMotion'
```

Deterministic: the grid reproduces byte-for-byte on this branch.
