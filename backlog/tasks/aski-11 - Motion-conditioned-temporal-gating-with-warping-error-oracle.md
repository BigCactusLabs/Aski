---
id: ASKI-11
title: Motion-conditioned temporal gating with warping-error oracle
status: To Do
assignee: []
created_date: '2026-08-18 18:02'
updated_date: '2026-09-10 04:38'
labels:
  - research
  - animation
dependencies: []
priority: medium
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The signal-free temporal-stability family is 0-for-4 (EMA prior, tau debounce, source-tethered hysteresis, inter-cell smoothing — all killed as inert, non-robust, or freeze-trapped; see docs/Research/ verdicts). A 2026-07-29 frontier sweep confirms the 2025 video-stylization consensus is motion-signal-CONDITIONED coherence: information shared along optical flow, evaluated with warping-error (flow-warped previous frame vs current, short- AND long-term), e.g. Synchronized Multi-Frame Diffusion (CGF 2025 cgf.70095). No current paper uses fixed-tolerance hysteresis. Direction: condition glyph re-selection on per-cell source-motion magnitude (frame difference or cheap flow) — a hard-release gate that opens when the source actually moves — and replace raw churn as the oracle with the literature's warping-error. Related theory seed worth piggybacking one probe: grid-motion resonance (churn vs pan-speed should be non-monotonic, peaking near ~1 cell/frame; if confirmed, fps/columns co-tuning near the band is the real fix).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pre-registered decisive run over the synthetic scenes AND at least two real clips, with SESOI-style equivalence bounds committed before measuring
- [ ] #2 KILL if the motion-conditioned gate inherits the static-scene freeze-trap or wins on only one scene class (non-robust)
- [ ] #3 Adopt warping-error (short- and long-term) as the coherence oracle; raw churn demoted to a secondary diagnostic
- [ ] #4 Resonance probe: churn vs pan-speed sweep in AskiMotionLab reported (non-monotonicity confirmed or refuted) regardless of gate verdict
- [ ] #5 Default byte-identical; any hook stays @_spi off-by-default unless the decisive run passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)
Current state: temporal controls exist only as research SPI. `Sources/Aski/Animation/ASCIIConverter+Temporal.swift:5` exposes `@_spi(AskiResearch) public struct TemporalPriorState`, and its public research-SPI `convertTemporalFrame` method is at line 45 with alpha, challenger tau, and optional sourceTetherRho; the production convert path is unchanged. The existing ASTSK-41 and ASTSK-45 labs and gates cover EMA, debounce, and source-tether hysteresis on synthetic S1/S2 fixtures. Their records are KILL or non-robust, and the tests protect those historical controls and the byte-identical control arm. The repository has no motion-conditioned hard release, per-cell motion magnitude input, short/long warping-error oracle, real-clip battery, or resonance sweep. The dated frame-difference spike is a lab lead only; it explicitly does not authorize a public motion API or a new backend.

Start here: Sources/Aski/Animation/ASCIIConverter+Temporal.swift, Tests/AskiTests/TemporalPriorHookTests.swift, Tools/AskiMotionLab/SyntheticMotion.swift, TemporalGate.swift, SourceTetherGate.swift, MotionLabCommand.swift, and docs/Research/2026-07-16-webgpu-frame-difference-ascii-motion.md. Existing video decode/encode paths can supply real frames later, but the current synthetic gates are not the ASKI-11 decisive run.

Constraints and dependencies: pre-register the synthetic corpus, at least two real clips, and SESOI bounds before measurement. AC #3 makes short- and long-term warping error the primary oracle and raw churn secondary; no current implementation supplies that instrument. Keep temporal coherence and spatial fidelity separate in the preregistration: short/long warping error is this task's coherence oracle, while MAE with GMSD supplies the standing spatial no-harm checks. The older GMSD/HaarPSI gates remain historical controls, not a replacement for warping error. A motion signal must release quickly during source movement without creating static-scene freeze traps, noise-triggered releases, or global-pan failures. Keep any new path lab-only and @_spi off by default; the production output must remain byte-identical until promotion. Do not restore edgeMap or promote killed temporal treatments, and do not invent thresholds from the dated spike.

Validation to run: once preregistration and implementation exist, run focused hook, synthetic, gate, and command wiring tests, then the real-clip lab and the repository research/artifact gates. Report the AC #4 pan-speed/churn resonance sweep whether the gate passes or fails. No tests or builds were run here.

First step: write the new preregistered measurement contract around the existing SPI lattice, including the warping-error definitions and release/failure cases, while preserving the historical KILL artifacts.

Source map: `Tools/AskiMotionLab/TemporalGate.swift`, `Tools/AskiMotionLab/SourceTetherExperiment.swift`, `docs/agents/research-methodology.md`.
<!-- SECTION:NOTES:END -->
