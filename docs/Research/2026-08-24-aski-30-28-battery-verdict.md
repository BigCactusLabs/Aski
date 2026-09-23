---
title: "ASKI-30 + ASKI-28 census battery — verdicts applied mechanically from the frozen rule"
slug: 2026-08-24-aski-30-28-battery-verdict
date: 2026-08-24
status: complete
subsystem: [shape-context]
summary: "The decisive run of the combined ASKI-30 / ASKI-28 battery, executed 2026-08-24 under the frozen rule committed at 9a2a73d's parent and applied mechanically to the held-out CSV. ASKI-28 is KILL on both dense charsets, as the rule predicted in advance: standard never reaches the 0.97 bar on nasa-steerable-v1 (best 0.9775 at topK=64 — the calibration point's 0.9590 did not transfer across corpora), and braille is flat at its best point (0.9999 at topK=18) with monotonic degradation beyond it. ASKI-30 is INCONCLUSIVE by pre-committed cross-check demotion: the tone-weighted arm at the calibrated w*=2 clears every MAE gate decisively on blocks (0.4186 of production, 0.8935 of the tone-only floor, no-harm guard passed, RMSE agreeing), but the SSIM raw-score direction inverts against the floor by 0.00026 (0.3055764 vs 0.3058391) and the rule carries no epsilon. Both exploratory arms fired on blocks under the lift rule — lexicographic shapeK=6 at 0.9355 of the floor and the z-normalized combination at w=10 at 0.8943 — and are split off to a new task, converting no verdict. All arm MAE values reproduced byte-identically across replicate runs."
related_specs: [docs/Research/2026-08-24-aski-30-28-decisive-rule.md, docs/Research/2026-08-19-selection-optimality-gap.md, docs/Research/2026-08-19-house-oracle-audit.md]
datasets: []
runners: [AskiColorLab]
next_action: "ASKI-28 closes as KILL. ASKI-30 closes as INCONCLUSIVE; the named blocker is a 0.09% SSIM inversion against the floor, which only a perceptual arbiter (ASKI-56) or an owner-signed contact-sheet review can adjudicate. The exploratory-arm lift is filed as its own task per rule §9."
---

# ASKI-30 + ASKI-28 battery — verdicts (decisive run, executed 2026-08-24)

- Frozen rule: `docs/Research/2026-08-24-aski-30-28-decisive-rule.md`, committed before any decisive number. Operating points frozen at commit `9a2a73d` (`docs/Research/Results/2026-08-24-aski-30-28-battery/frozen-operating-points.csv`) **before** the held-out run executed, per rule §4.2.
- Verdicts below are applied only to `docs/Research/Results/2026-08-24-aski-30-28-battery/heldout-nasa-steerable-v1.csv` (rule §3.4). Calibration CSV, two dense-charset cost replicates, and the stdout census table sit beside it in the same result store.
- Instrument: `AskiColorLab selection-ceiling`, release build, at rule §2.1 geometry (columns 80, oversample 2, footprint 24, stride 1, 8640 cells per arm per charset per corpus). Arm MAE values are byte-identical across the three replicate runs.

## Verdict — ASKI-28 (pool width, dense charsets): KILL on both charsets

Per-charset gate, rule §5.2. Baseline is production `topK = 12` on the same charset; ratios at four decimals.

| charset | topK* (calib) | calib ratio | held-out ratio at topK* | best held-out ratio anywhere | verdict |
| --- | --- | --- | --- | --- | --- |
| `standard` | 64 | 0.9590 | **0.9775** | 0.9775 (topK=64) | **KILL** — no swept point reaches ≤ 0.97 |
| `braille` | 18 | 0.9995 | **0.9999** | 0.9999 (topK=18) | **KILL** — no swept point reaches ≤ 0.97 |

The rule stated KILL as the expected outcome in advance (§5.2, pool gaps 2.73–2.85% < the 3.0% bar) and the sweep confirms it. Two findings worth keeping:

1. **Calibration transfer failed on `standard` in exactly the direction the corpus-straddle warning predicted.** topK=64 improves 4.10% on `nasa-structure-v1` — above the bar — but only 2.25% on held-out. The dual-corpus design did its job: a single-corpus run on the calibration side would have declared a false PASS.
2. **The curve is U-shaped on `standard` and monotone-degrading on `braille`.** `standard` improves through topK=64 then *worsens* past its own baseline at the full pool (1.0161 at 95); `braille` never improves beyond noise and reaches 1.1428 at the full 256. Widening the pool widens the descriptor's opportunity to rank badly, exactly as the parent note put it.

Cost (R3, median of 3 runs): selection wall time scales mildly — 1.31× at `standard` topK=64, 2.07× at `braille` topK=256; every quality-relevant point is far under the 2.0× cap, so cost gates nothing. The KILL is on quality alone.

## Verdict — ASKI-30 (tone-weighted selection, blocks): INCONCLUSIVE

Gate at calibrated `w* = 2` on `blocks`, rule §5.1. MAE, held-out `nasa-steerable-v1`:

| comparison | value | gate | result |
| --- | --- | --- | --- |
| `MAE_T / MAE_P` held-out | **0.4186** | ≤ 0.97 | clears (58.1% better) |
| `MAE_T / MAE_F` held-out | **0.8935** | ≤ 0.97 | clears (10.7% better) |
| `MAE_T / MAE_P` calibration (no-harm) | 0.5351 | ≤ 1.01 | clears |
| `MAE_T / MAE_F` calibration (no-harm) | 0.9372 | ≤ 1.01 | clears |
| RMSE direction, both comparisons | T < F < P | no inversion | clears |
| SSIM raw-score direction vs P | 0.3055764 vs 0.0021392 | no inversion | clears |
| SSIM raw-score direction vs F | **0.3055764 vs 0.3058391** | no inversion | **INVERTS** |

MAE says T beats the floor; single-scale SSIM says the floor beats T, by 0.00026 raw (−0.09%). The rule's demotion clause (§5.1: "if the MAE comparison clears both 0.97 gates but RMSE or SSIM moves the opposite way against either baseline, the verdict is INCONCLUSIVE, not PASS") carries no epsilon, deliberately — so the verdict is **INCONCLUSIVE**, blocker named: *SSIM direction inversion against the tone-only floor*.

The KILL condition is nowhere near firing: T beats the floor at every swept `w ≥ 1` (ratios 0.8935–0.9485) and beats production at every `w ≥ 1` (0.4186–0.4444). `w = 0` reproduces production to four decimals (ratio 1.0000), confirming the sanity anchor.

**Reading, stated plainly.** The MAE case for tone-weighting on `blocks` is not marginal — it is the largest margin any arm has posted in this research line, and it holds on both corpora with the same ordering under RMSE. What demotes it is a knife-edge disagreement from an oracle that the house-oracle audit already ranked below MAE and that normalizes production on `blocks` at 0.00214. But the rule was frozen with that demotion power in it, precisely so a favorable surprise could not be waved through — so it stands. The discriminator this leaves us needing is perceptual, not reconstructive: the parked arbiter instrument (ASKI-56) or an owner-reviewed PresetLab contact sheet. Either would settle whether the 0.09% SSIM objection corresponds to anything a viewer can see.

## Lift — both exploratory arms fired on `blocks` (rule §6/§9)

Non-gating, converts no verdict; recorded and split off:

| arm | point | held-out MAE | vs P | vs F |
| --- | --- | --- | --- | --- |
| lexicographic (prune shapeK by shape, rank by tone) | shapeK = 6 | 0.24690 | 0.4383 | 0.9355 |
| z-normalized combination | w = 10 | 0.23602 | 0.4190 | 0.8943 |

Both clear the §5.1 MAE margin against both baselines on the held-out corpus. The tone-weighted arm T at w*=2 (0.23580) remains the numerically best selector on `blocks`; z-norm at w=10 sits 0.00022 behind it. The lexicographic result matters structurally: shapeK=6 of 8 means "veto the two shape-worst glyphs, then rank purely by tone" already recovers most of the tone-weighted win, supporting the external precedent that lexicographic beats a fragile weighted sum when tone is the dominant term. Filed as one lift task with this table attached.

## Pre-committed readouts

**R1 — best T per charset, held-out** (w minimizing MAE; gate applies only to `blocks`):

| charset | best w | vs P | vs F | | charset | best w | vs P | vs F |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `blocks` | 2 | 0.4186 | 0.8935 | | `minimal` | 1 | 0.9818 | 0.9956 |
| `diagonal` | 1 | 0.9778 | 0.9771 | | `lines` | 50 | 0.8150 | 1.0018 |
| `diamond` | 1 | 0.9832 | 0.9874 | | `mixed` | 5 | 0.8670 | 0.9548 |
| `cross` | 50 | 0.9901 | 1.0007 | | `dots` | 1 | 0.9863 | 0.9452 |

Dense (per ASKI-30 AC#1's sparse-and-dense split): `standard` best w=1 → 0.9941 vs P; `braille` best w=10 → 0.9998 vs P. Tone-weighting is inert on dense charsets, where the brightness pre-filter already does the tone work. No sparse charset other than `blocks` clears both margins, so no additional lift fires from R1.

**R2 — floor vs production (`MAE_F / MAE_P`)**: held-out — blocks 0.4685, lines 0.8135, mixed 0.9081, minimal 0.9861, cross 0.9895, diamond 0.9958, diagonal 1.0007, dots 1.0435; calibration — blocks 0.5709, lines 0.8598, mixed 0.9433, all others ≥ 1.0. The floor's dominance is a blocks/lines/mixed phenomenon, not a universal sparse-charset one, so the AC#4 question ("disable the shape term for sparse charsets wholesale?") answers itself **no** — and is moot anyway, since the arm beat the floor and the KILL branch that triggers the AC#4 disposition never fired.

**R3** — cost/quality curves recorded per charset per topK in the CSVs; medians quoted above.

**R4 — meanRank, MAE**: production pick on `blocks` held-out = 7.22 of 8 (second-worst available, reproducing the parent note). **Instrument gap, recorded honestly:** the census CSV does not emit meanRank for arm T, and the stdout table computes it only for the production pick, so the arm-T half of R4 was not measured. Descriptive readout only; nothing gates on it. Carried to the lift task as an instrument to-do.

**R5** — GMSD and HaarPSI comparator columns are in the CSV for every gating comparison (blocks at w*: GMSD 0.19999 T vs 0.20452 F vs 0.33993 P; HaarPSI 0.37876 T vs 0.37907 F vs 0.09480 P — HaarPSI sides with SSIM's knife-edge preference for F, GMSD sides with MAE; comparator label mandatory, never gating).

**R6 — band-relative sensitivity (labelled sensitivity only):** on held-out `blocks` the P-vs-F spread is 0.29938 MAE; T's improvement over F is 0.094 spreads, over P 1.094 spreads. Had the rule used a band-relative margin at any conventional κ, the vs-P verdict would be unchanged and the vs-F verdict would depend entirely on κ — the instability the fixed-ratio margin was chosen to avoid.

**R7** — the exploratory table above.

**R8 — floor re-definition audit**: legacy floor (rawDensityValues vs mean block luma) vs rebuilt floor (brightnessValues vs adjustedL) on `blocks`: held-out 0.24637 → 0.26391, calibration 0.26321 → 0.31809. The rebuild made the floor a *weaker* baseline in absolute MAE — i.e., the frozen comparison was **harder** on production's tone pair than the legacy pair would have been for the arm, and the arm still cleared it. The legacy 0.24637 is exactly the parent note's published floor, confirming continuity.

## Deviations and gaps, complete list

1. R4's arm-T meanRank was never emitted by the instrument (above). Descriptive only.
2. The §5.2 cost medians come from three runs of the dense-charset census; the sparse-charset wall times are single-run (cost gates nothing on sparse arms).
3. `braille` topK=256 sits at 2.07× wall cost — above the cap, moot under KILL, recorded for the R3 curve.

## Disposition

- **ASKI-28 → Done, verdict KILL.** `topK = 12` stands. The shipped `density` knob's reachable range [12, 36] contains everything worth reaching on `braille` and undershoots `standard`'s (sub-bar) optimum — no knob change is licensed by a sub-bar gain that fails calibration transfer.
- **ASKI-30 → Done, verdict INCONCLUSIVE**, blocker: SSIM inversion vs the floor, 0.00026 raw. No Sources change, no knob, no default motion. The evidence is preserved here and in the CSV store; re-opening requires the perceptual discriminator (ASKI-56 or an owner-signed contact-sheet review), not another reconstruction-metric run.
- **Lift task filed** for the two exploratory-arm wins (lex shapeK grid, z-normalized combination), per §9.
- `Sources/Aski` untouched throughout the measurement, per the rule's standing clause.

## Resolution note (2026-08-27, append-only) — the missing discriminator now exists

The sentence above ("the parked arbiter instrument (ASKI-56) or an
owner-reviewed PresetLab contact sheet") is resolved on its first half: the
ASKI-56 arbiter was built, validated (both instrument gates passed 6/6 — it
recovers the unanimous five-oracle blocks inversion on every source), and run
(`docs/Research/2026-08-27-aski56-arbiter-verdict.md`).

On this battery's named blocker specifically — the 0.09% SSIM inversion
against the tone-only floor — the arbiter's D (disagreement) family put the
T(w*=2)-vs-F pair in front of the blinded owner on all six sources: 1 of 4
decided trials went to the lower-MAE side (T), 2 were ties, and the VLM judge
flipped across presentation orders on half the pairs. Recorded, not gated:
the near-tie behaves like a genuine perceptual near-tie, with what little
signal there is leaning toward the floor — the side SSIM preferred. Four
decided trials is far below the protocol's decided-n threshold, so **ASKI-30
remains INCONCLUSIVE**; a dedicated D-focused arbiter run is the named path
to settle it if promotion of the tone-weighted arm is ever wanted.
