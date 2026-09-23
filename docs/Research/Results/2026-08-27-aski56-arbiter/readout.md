# ASKI-56 perceptual arbiter — readout

Protocol: `docs/Research/2026-08-25-aski56-arbiter-protocol.md` (v1, frozen).

## Validation gate (section 5.1)

- Human leg: **pass** — 6/6 V pairs answered F (bar: 5).
- VLM leg: **pass** — 6/6 V pairs decided F under the both-orders rule.

## Human leg

- Split: 32/37 chose the lower-MAE side (decided n = 37).
- Exact one-sided binomial p = 0.0000 at alpha = 0.0500.
- Tie rate: 0.0750 (3 ties).
- Verdict: the rater prefers the lower-MAE side (p = 0.0000, n = 37).
- Rater consistency on 5 repeats: 0.8000 (reported, never gated).

## Calibration (AC#3)

- Fitted on 27 trials from families C + M; V and D are excluded (see the protocol's pre-run errata).
- Regressor units: `relative-mae-margin` — the fractional improvement `1 - MAE_better / MAE_worse`, which is the same quantity the section 5.2 bar is written in.
- JND75 band: -0.3451 ... 0.0719 relative MAE margin (point -0.0292), bootstrapped by SOURCE IMAGE over 1676/2000 usable resamples.
- PSE: -0.1706 relative MAE margin.
- Section 5.2 disposition of the 3.0 percent bar: **straddles-the-bar**.

## Per-family splits

family | answered | chose lower MAE | ties
--- | --- | --- | ---
V | 6 | 6 | 0
D | 6 | 1 | 2
C | 20 | 18 | 1
M | 8 | 7 | 0

## VLM order-inconsistency rate (section 4, recorded not gated)

- V: 0.0000
- D: 0.5000
- M: 0.1250
