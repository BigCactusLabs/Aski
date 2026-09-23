---
title: "ASTSK-42 Steerable Oriented-Energy Descriptor Channel - Verdict"
slug: 2026-06-27-astsk42-steerable-channel
date: 2026-06-27
status: complete
subsystem: [shape-context, frontier]
summary: "KILL, decisive. A steerable oriented-energy channel (Freeman-Adelson G2/H2, continuous angular resolution + a magnitude-preserving normalized-distance blend at Kr=0.5) was appended to the 60D log-polar descriptor as an off-by-default matcher path and scored by the REAL converter over the frozen oriented battery {spokes, diagonals 15/30/60/75, arcs} x columns {48,64,80,96,120} plus a held-out >=3072px NASA naturals corpus, on native-footprint GMSD(chosen glyph, source). Result: aggregate delta -0.19% (bar +3.0%), naturals delta -0.92% (a regression). Fails clauses (a) and (c) of the frozen rule. The channel is inert on the single-orientation content it was built to rescue (diagonals +0.0%, arcs +0.0%; only spokes +0.32%) and actively harms naturals. Third failed attempt (after ASTSK-31, ASTSK-35) to lift glyph pick-quality with an orientation/structure side-channel. ASKI-68 later removed steerableShapeAssist, the SPI hook, and the dedicated runners; this note, the replay record, and Git history retain the evidence."
related_specs: [docs/Research/Discoveries.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1]
runners: [AskiColorLab]
next_action: "Closed with no promotion and removed by ASKI-68. Do not attempt another orientation-channel variant without a fundamentally different perceptual oracle or a rendering-model change."
---

# ASTSK-42 — Steerable oriented-energy descriptor channel

**Status:** SETTLED — **KILL** (2026-06-27, decisive: full frozen sweep, naturals present, zero upsampled
cells). The decision rule was **frozen 2026-06-24 before any measurement** (the ASTSK-42 pre-registration
+ `docs/Research/Discoveries.md`, 2026-06-24 entry); results + verdict appended after the run, no
constant tuned to a result.
**Branch:** `astsk-42-fourier-feature-basis` · **Date frozen:** 2026-06-24 · **Date executed:** 2026-06-27
**Design lineage:** 2026-06-18 NCA brief → 2026-06-24 frontier-search redirect (Fourier-feature → steerable
oriented energy) → 2026-06-27 frontier-search bolster → this gate. Attempt **#3** on the wall that KILLED
ASTSK-31 (regime oracle) and ASTSK-35 (basis augmentation).

## The candidate (frozen)

APPEND a deterministic, Nyquist-capped **steerable** oriented-energy channel (Freeman–Adelson G2/H2 quadrature
pairs) to the 60D log-polar descriptor — differing from the KILLED ASTSK-35 `shapeStructureAssist` in the two
ways that made it a *valid* attempt:

1. **Continuous angular resolution.** A per-cell, per-glyph fine-bin (24-bin, 7.5°) phase-invariant
   orientation-energy signature via the closed-form dominant orientation `θ* = ½·atan2(2r_b, r_a−r_c)` and
   energy `E = R_G2(θ*)² + R_H2(θ*)²` — not the discrete 8-bin (22.5°) histogram that already failed.
2. **Magnitude-preserving normalized-distance blend.** Within the brightness pool,
   `combined = shapeL2 + Kr·scale·(sigDist/2)`, `scale = mean(shapeL2 over pool)`, `Kr = 0.5` pre-registered —
   not a rank-mix-at-pool (the ASTSK-31/35 mechanism that reproduced bit-for-bit and KILLed twice).

## Decision rule (frozen, not tuned to pass)

- Battery: `{radial spokes, off-axis diagonals 15/30/60/75°, arcs, held-out naturals}` × columns
  `{48,64,80,96,120}`.
- Metric: native-footprint **GMSD(chosen glyph, source)** (lower = better); `delta = (base − treatment)/base`.
- **PASS** iff ALL: (a) aggregate delta ≥ **+3.0%**; (b) **no** oriented sub-battery (spokes/diagonals/arcs)
  regresses > 0.5%; (c) naturals do not regress. **KILL** otherwise.
- ρ inadmissible (a rank-correlation lift is not evidence — it reproduced and KILLed twice).

## Result — KILL

`AskiColorLab steerable-channel --battery all --columns 48,64,80,96,120 --side 3072 --kr 0.5`
(gate output recorded in the run's `result.yaml`). **147,168 cells scored, 0 skipped /
upsampled** (every native block ≥ 24 px at every column — gate integrity clean).

| sub-battery | GMSD base | GMSD treat | Δ = (base−treat)/base | cells |
| --- | --- | --- | --- | --- |
| spokes      | 0.14332 | 0.14287 | **+0.32%** | 16,352 |
| diagonals   | 0.37382 | 0.37381 | **+0.0015%** | 65,408 |
| arcs        | 0.44411 | 0.44410 | **+0.0022%** | 16,352 |
| naturals    | 0.19947 | 0.20131 | **−0.92%** | 49,056 |
| **aggregate** | — | — | **−0.19%** | 147,168 |

**Verdict: KILL.** Two clauses fail independently:
- **(a) aggregate Δ = −0.19%** — not merely below the +3.0% bar but *negative*; the channel is net-harmful
  pooled across the battery.
- **(c) naturals Δ = −0.92%** — a real regression (worse than the −0.5% floor). On real continuous-tone
  content the blend moves glyph picks the **wrong** way.

Clause (b) is technically satisfied only because the channel is **inert** where it was supposed to help:
on the single-orientation gratings the per-cell steerable signature barely perturbs the pick (diagonals
+0.0015%, arcs +0.0022%). The one non-trivial oriented gain is spokes (+0.32%, multi-orientation), an order of
magnitude short of the +3% bar and swamped by the naturals regression.

## Mechanistic finding

The steerable primitive itself is sound — its unit tests confirm continuous angular resolution (resolves 45°
vs 50°, which the 8-bin histogram folds) and phase invariance. The failure is in **transfer**: a
reconstruction-side orientation-energy signal, blended by magnitude into the pool, does not change which glyph
best reconstructs a cell. At the cell footprint the dominant-orientation signature is near-degenerate for a
single grating (one bin dominates for both query and the handful of pool candidates), so `sigDist ≈ 0` and the
blend collapses to the pure-shape argmin — hence the ~0% on diagonals/arcs. Where the signature *does* vary
(textured naturals), it pulls the pick toward glyphs that match orientation energy but reconstruct the tone
worse, costing GMSD. This is the same wall as ASTSK-31 (regime oracle) and ASTSK-35 (basis augmentation),
reached by a third, mechanically distinct route — consistent with the reconstruction-vs-perception literature
and the 2026-06-27 frontier-search bolster, both of which predicted KILL.

## Known limitation (frozen metric)

The signature distance used in the blend (`findBestSteerableScored` / `SteerableEnergy.signatureDistance`) is a
**linear** bin-by-bin L1 over what is actually a *circular* `[0, π)` orientation histogram — orientation 0 and
orientation π−ε are the same physical orientation, so the two endpoint bins are neighbors, not opposites. Linear
L1 reads a query/glyph pair straddling that wrap as near-maximally distant. This was caught in review (Codex,
PR #55) **after** the gate was frozen and run, so the metric is kept as-is rather than swapped post-hoc (a
circular/earth-mover distance would be a different, post-registration experiment requiring a full re-run).

It does **not** soften the KILL. The error can only ever *inflate* `sigDist` for a genuinely orientation-matching
candidate (one whose energy sits across the wrap), which *raises* its blended cost and makes it *less* likely to
be picked — i.e. the bug biases strictly **against** the steerable treatment. A correct circular distance could
therefore only have *helped* the treatment; and with the synthetic batteries inert (`sigDist ≈ 0`, so the wrap is
moot there) and naturals only −0.92%, it is not plausible the aggregate would cross the +3.0% bar. The recorded
KILL is conservative with respect to this limitation.

## Disposition

- **`steerableShapeAssist` stays default 0.** Shipped as a documented negative result (mirrors ASTSK-35). The
  Sources changes are off-by-default and **byte-identical by construction** (flag-off path unchanged; built-in
  sets carry no `steerableSignatures`, so the knob is a no-op on them — two byte-identical tests + the
  full-suite golden guard prove it). No promotion, no `.bin` v4.
- **The wall has held three times.** Do not attempt a fourth orientation/structure side-channel against the
  reconstruction GMSD oracle. A real lift would require either a *perceptual* oracle (not reconstruction GMSD)
  or a rendering-model change (sub-cell stroke continuation / non-monospace) — separate, larger work, not
  chased here.

## Reproduce

```sh
xcrun swift run -c release AskiColorLab steerable-channel \
  --battery all --columns 48,64,80,96,120 --side 3072 --kr 0.5 \
  --output-dir /tmp/steerable-channel-2026-06-27
```

Naturals corpus: `docs/Research/Corpus/nasa-steerable-v1` (3 NASA photos ≥3072 px, see its `PROVENANCE.md`).
The gate **fails loudly** (nonzero exit) if any (fixture, column) would upsample the oracle or a sub-battery is
empty — it never scores a partial battery.

## 2026-09-04 exact-lattice replay addendum

ASKI-29/50 regenerated a one-column ASTSK-42-style comparison on the current
exact lattice because the June cell-pair artifacts do not survive. The two
declared regimes were kept separate: shipping at C80 is 2x4 with 3/60 reachable
bins, while the historical-support comparator is 38x85 with 48/60. The June
five-column result above remains the historical record.

The archived KILL **held under every current-path comparator** in both regimes:
MAE, GMSD, 1-HaarPSI, contrast-weighted SSIM, and pinned official MILO. Shipping
aggregate deltas were respectively -0.1783%, -0.3805%, -0.1116%, -0.1709%, and
-1.2606%. See the frozen rule, provenance, full table, and artifacts in
[the ASKI-29/50 replay note](2026-09-04-aski29-50-steerable-metric-replay.md).
