---
title: "Perceptual arbiter protocol v1 — human-arbitrated, VLM pre-screened pairwise adjudication for ASCII renders"
slug: 2026-08-25-aski56-arbiter-protocol
date: 2026-08-25
status: active
subsystem: [meta]
summary: "The frozen v1 protocol for the ASKI-56 perceptual arbiter: the missing instrument every reconstruction-oracle verdict in this repo has had to defer to. The human owner is the arbiter and the VLM is a pre-screen and tie-breaker that counts for nothing until it passes an instrument-validation gate on six unanimous-oracle validation pairs. The instrument is a three-subcommand group on AskiColorLab — stimuli, judge, score — that materializes blinded reference/left/right triplets from the real converter geometry and the real candidate pool, judges them in both presentation orders with repeated sampling, and scores the human leg by exact one-sided binomial with ties excluded and a pre-registered decided-n threshold. Calibration fits a logistic psychometric curve of choice probability against signed delta-MAE by IRLS and reports JND75 as a bootstrap band resampled by source image, which is then used to assess whether the standing 3.0 percent MAE bar is perceptually grounded. Identity lives only in key.json; no rater-visible artifact carries an arm name, a filename, or a metric."
related_specs: [docs/Research/2026-08-24-aski-30-28-decisive-rule.md, docs/Research/2026-08-19-house-oracle-audit.md, docs/Research/Discoveries.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1]
runners: [AskiColorLab]
next_action: "Generate the stimuli, rate the human leg blind in one sitting, then run the VLM leg and score. Do not edit any decision rule in this document after the first vote is collected."
---

# ASKI-56 — Perceptual arbiter protocol, v1 (frozen)

status: FROZEN before any judging run. Changes after the first collected vote require a v2 and re-validation.
authored: 2026-08-25. The run artifacts are named for whatever date the run records; no date in this
document refers to an execution. (The draft carried literal execution-date placeholders on this line
and in §6; the research registry rejects unresolved placeholders in a committed note, so the
convention is stated in words instead. Header and AC-map wording only — no role, rule, family,
gate or computation is affected.)
task: ASKI-56. Supersedes the "contact-sheet-only" informal perceptual check named in
`docs/Research/2026-08-24-aski-30-28-decisive-rule.md` §7 once AC#4 lands.
evidence base: frontier survey 2026-08-25 (arXiv:2603.24578, 2604.25235, 2402.01162,
2406.07791, 2604.23178, 2602.02219, 2604.11589, 2403.10390, 2312.08962, Q-Insight
arXiv:2503.22679, Katsigiannis QUX 2018, ITU-R BT.500-15). Key structural findings:
VLM pairwise judging tracks humans on clearly separated pairs and degrades on near-ties;
pairwise beats absolute scoring; frozen API pins do not buy determinism in 2026 (temperature
controls rejected by current Claude/GPT APIs), so reproducibility = exact model ID + K
repeated samples + published per-pair vote splits.

## 1. Roles

- **Human (owner) is the arbiter.** Verdicts are read from the human leg only.
- **VLM is a pre-screen and tie-breaker, never co-equal.** Its verdicts count only after it
  passes the §5.1 validation gate, and never alone on near-ties (in-repo finding,
  `docs/Research/Discoveries.md:501-504`).

## 2. Instrument

New subcommand group on the existing lab: `swift run AskiColorLab arbiter <stimuli|judge|score>`
(reuses the SelectionCeiling arm selectors in-target; a dedicated lab waits for ASKI-48).
House pattern: `LabExitCode`, `ProvenanceOptions` (`--output-dir`, `--aski-git-sha`),
`SeedOption` (`--seed`), injectable `execute(...) -> LabExitCode`, `result.yaml` + manifest
with schema_version/date/aski_git_sha/command. The command-surface golden
(`Tests/AskiTests/Goldens/command-surface.json`) must be regenerated.

### 2.1 `arbiter stimuli`

Operational note (2026-09-02, not a decision rule): generate stimuli from a release build,
`swift run -c release AskiColorLab arbiter stimuli`. At the protocol regime (columns 80,
footprint 24, 6 sources x 2 charsets) a debug build did not finish in 20 minutes; the release
build took 65 s. ASKI-62 inherits this for the v2 stimuli.

For each selected (source, charset, armA, armB) pair:
1. Convert the source with the production converter; capture the real grid geometry and the
   real candidate pool via `@_spi(AskiResearch)` (as `SelectionCeiling.census` does).
2. Materialize each arm's per-cell picks into a full character grid and render it to PNG via
   the same path production output takes (`ASCIIGrid.renderImage` or
   `GridComposite.compose`), NOT per-glyph rasters — this preserves position distinctions
   that `GlyphRaster` bounds-centering erases (decisive-rule §7 bound).
3. Render the reference: the source photo scaled to the same pixel size as the renders.
4. Emit a blinded triplet per pair: `pair-NNN-ref.png`, `pair-NNN-left.png`,
   `pair-NNN-right.png`. Left/right assignment is seeded-random per pair. Identity
   (arm, charset, w, source) lives ONLY in `key.json`, which the rater must not open before
   submitting answers. `answers-template.csv` (pairID, choice ∈ {L, R, tie}) is emitted for
   the human leg. A `sheet/` dir holds one composite PNG per pair (ref above, L/R below,
   coded label only) for fast sequential review.
5. Per-pair metric deltas (MAE, RMSE, SSIM, GMSD, HaarPSI for each side vs the census
   source vectors) are computed at stimuli time and stored in `key.json` — never in any
   rater-visible artifact.

Pair families (fixed budget, seeded selection; sources = the 3 `nasa-steerable-v1` + 3
`nasa-structure-v1` assets; charset = blocks unless stated):
- **V (validation), 6 pairs:** tone-only floor F vs production P on blocks, all 6 sources.
  The unanimous five-oracle inversion; expected answer F.
- **D (disagreement), 6 pairs:** tone-weighted T(w*=2) vs floor F on blocks, all 6 sources.
  The ASKI-30 SSIM-inversion near-tie. Behavior recorded, not gated.
- **C (calibration ladder), ~20 pairs:** arm pairs chosen (seeded) so signed ΔMAE spans
  roughly even steps from near-0 to the largest available margin, drawn from
  {P, F, T(w ∈ sweep), K(topK), lex(shapeK=6), znorm(w=10)} on blocks plus ≥4 pairs on
  standard (dense-charset contrast).
- **M (adversarial), ~8 pairs:** MAD-style — minimize |ΔMAE| while maximizing |ΔSSIM|
  (and/or |ΔGMSD|) over the candidate arm/source pool, so calibration probes where MAE is
  blind, not only where it works.
- **R (repeats), 5 pairs:** seeded re-draws of already-emitted pairs with fresh left/right
  randomization and new pairIDs; used only for the rater-consistency statistic.

Total ≈ 45 human trials (~40 unique). Fixed conversion regime: columns=80, oversample=2 —
the shipping regime every standing verdict was measured at.

### 2.2 `arbiter judge` (VLM leg)

- Transport: subprocess, injectable via `--runner` (tests inject a stub). Default pin:
  `codex exec -s read-only -m gpt-5.6-terra -c model_reasoning_effort=xhigh -i <ref> -i <first> -i <second> --skip-git-repo-check`.
- Judge config (`judge.json`, embedded in the run manifest): transport, exact model ID,
  effort, prompt text + SHA-256, K, order policy. **Upgrade path:** any judge change (e.g.
  to the Q-Insight comparison checkpoint pinned by HF revision hash) is a new judge config
  and requires re-passing the §5.1 validation gate before its verdicts count.
- Frozen prompt (images attached in-order: reference, first, second; no filenames, metrics,
  or provenance):
  > The first image is a reference photograph. The second and third images are two ASCII-art
  > renderings of it. Which rendering preserves the reference's structure and tonality more
  > faithfully? Think briefly about structure, then tone. End with exactly one line:
  > `VERDICT: FIRST` or `VERDICT: SECOND`.
- Sampling: each pair judged in both presentation orders × K=3 samples = 6 calls. A pair is
  **decided** for a side only if both order-majorities agree; otherwise it is a VLM tie.
  Per-pair raw vote splits (all 6 verdicts) are recorded in the results.
- Scope: V + D + M pairs always; C pairs optional via `--include-calibration` (budget).
- Parsing: last `VERDICT:` line; a call with no parseable verdict is retried once, then
  recorded `invalid` (counts toward neither side).

### 2.3 `arbiter score`

Ingests `answers.csv` (human) and/or the judge results; joins against `key.json`; emits
`result.yaml` + a Markdown readout. Computations:
- **Human verdict per question:** exact one-sided binomial on decided (non-tie, non-repeat)
  trials, α=0.05. Ties are allowed, excluded from n, and reported as a tie rate. A verdict
  line is emitted only if decided n ≥ 30; below that the readout reports the split and CI
  only (pre-registered).
- **Rater consistency:** agreement rate on the 5 R-repeats (reported, not gated).
- **Validation gate (§5.1) evaluation** with FAIL-FAST exit: gate failure → `LabExitCode.failure`.
- **Calibration (AC#3):** logistic fit of P(choose side with lower MAE) against signed
  ΔMAE via IRLS; report PSE and **JND75 = ΔMAE at P=0.75** with a bootstrap CI resampled
  **by source image** (not by pair). Reported as a band, never a scalar.

## 3. Blinding and hygiene

- Rater sees only coded composites; no filenames carrying arm identity, no metric values,
  no key.json. Left/right seeded per pair. Rate in one sitting, same display, no zooming
  differences between sides. Submit answers before opening key.json or any readout.
- The immediate-swap trick is a VLM-leg control only; human repeats are the R family
  (delayed, re-randomized).

## 4. Known-case expectations (AC#2)

- **V pairs:** every leg that claims validity must prefer F over P. All five reconstruction
  oracles agree here and the margin is huge (MAE ratio ≈ 0.47) — a judge that misses this
  is invalid, full stop.
- **D pairs:** the oracle-disagreement near-tie (MAE says T, single-scale SSIM +
  HaarPSI say F, −0.09% raw). No gate; the recorded behavior — including VLM
  order-inconsistency rate — is the deliverable, and is expected to show the near-tie
  unreliability regime.

## 5. Frozen decision rules

### 5.1 Instrument validation gate

- Human leg: ≥5 of 6 V pairs answered F (binomial p≈0.11 at 5/6, accepted for a
  huge-margin sanity screen at n=6; the gate is screening the *instrument*, not the arms).
- VLM leg: ≥5 of 6 V pairs decided F under the §2.2 both-orders rule. VLM verdicts count
  for nothing until this passes; on failure the VLM leg is reported invalid and the human
  leg stands alone.

### 5.2 The 3.0 percent bar (AC#3)

The standing bar (`MAE_arm/MAE_baseline ≤ 0.97`, inherited from the archived channel gates)
is assessed against the calibrated JND75 band on the census fixtures:
- JND75 band entirely below a 3.0% MAE margin → the bar is **perceptually grounded** (a
  passing arm is visibly different); retain, cite this run.
- Band entirely above 3.0% → the bar admits invisible "wins"; **adjust** the bar to the
  band's upper edge (rounded to 0.5%) in a follow-up rule change, or retain with explicit
  reasons.
- Band straddles 3.0% → **retain** the bar, record that it sits inside the ambiguity
  interval, and require the arbiter (not the bar alone) for any default promotion —
  consistent with Cheon et al. ambiguity-interval findings.

### 5.3 Near-tie clamp

For any future decisive use: pairs with |ΔMAE| below the JND75 band's lower edge are
adjudicated by the human leg only; VLM votes on such pairs are advisory and must be
labeled as inside the unreliability regime.

## 6. AC map

- AC#1 → this document (§1–§5) + `judge.json` pins.
- AC#2 → §4/§5.1, executed in the validation run, whose result store is
  `docs/Research/Results/` under a directory named for the run's own execution date, suffixed
  `-aski56-arbiter`.
- AC#3 → §2.3 calibration + §5.2 assessment, same run.
- AC#4 → wording updates across the perceptual-gate sites (separate commit on this branch;
  site list from the 2026-08-25 instrument-surface survey).

## 7. Errata (pre-run, append-only)

Recorded 2026-08-25, **before any vote was collected**, from the adversarial
review of the instrument build. The freeze rule in the header binds changes made
after the first vote; nothing below alters a decision rule's intent, and each
entry states what the frozen text says, what the instrument does, and why. §1–§6
above are unchanged — read them together with this section.

### E1 — the calibration regressor is the margin's MAGNITUDE, not its sign

**2026-08-25.** §2.3 says the logistic is fitted "against signed ΔMAE". Taken
literally that curve is non-monotone — a pair where arm A wins by 5% and one
where arm B wins by 5% are the same trial with the sides relabelled, so
P(choose the lower-MAE side) rises in BOTH directions away from zero and a single
logistic cannot describe it. JND75 would then have no unique solution. The
instrument fits the MAGNITUDE, with the response defined as "chose the lower-MAE
side" — which is what §2.3's own PSE and JND75 definitions presuppose. The sign
is retained in `key.json` (`delta_mae`) and is what names the better side.

### E2 — the §5.2 bar is a RATIO, so the band is fitted in ratio units

**2026-08-25.** §5.2 assesses the JND75 band against "a 3.0% MAE margin". The
standing bar it refers to is `MAE_arm / MAE_baseline ≤ 0.97`
(`docs/Research/2026-08-24-aski-30-28-decisive-rule.md:97`) — a 3.0 percent
**relative** improvement. A band fitted against the absolute mean-MAE gap is not
comparable to it: at the census fixtures' own magnitudes (production mean MAE
0.5571, floor 0.3181 on `blocks`) an absolute gap of 0.030 is only a 5.4 percent
relative improvement, so reading the absolute figure against the bar is roughly
1.8x too permissive — and the error lands, every time, on the side of concluding
that the bar is well grounded.

The regressor is therefore the **relative margin**

> `1 − MAE_better / MAE_worse`, equivalently `|ΔMAE| / max(MAE_A, MAE_B)`

which is exactly the standing bar's own quantity with the worse arm taken as the
baseline. A pair that just clears `ratio ≤ 0.97` has a margin of exactly 0.030.
JND75 and PSE are reported in these units, `result.yaml` records
`calibration_units: relative-mae-margin`, and the three §5.2 dispositions are
read off the band against 0.030 unchanged. **No disposition threshold moved; only
the units the band is expressed in were corrected.**

### E3 — the fit is C + M; V and D are excluded

**2026-08-25.** §2.3 fits the curve on the calibration ladder, but did not say
which families enter it. V pairs sit an order of magnitude beyond the ladder's
largest rung (the §4 margin is a MAE ratio of ≈ 0.47), so including them makes
six trials the highest-leverage points in the whole regression and lets them set
the slope on their own. The fit is therefore **C + M**: C is the ladder, and M is
registered by §2.1 as calibration-adjacent — it exists precisely to probe where
MAE is blind, which is the region JND75 is read in. **V and D are excluded**; V
is the gate's own screen and D is a recorded behavior, not calibration data.
`result.yaml` and the readout both record the fit's family composition, so a
reader can see what the number was computed from.

### E4 — blinding hardening (no rule change)

**2026-08-25.** Three §3 blinding gaps found in the build, fixed without changing
any decision rule. (a) Pair IDs are assigned after a **seeded shuffle** of the
unique pairs; numbering them in family emission order made `pair-001`…`pair-006`
the V family in every run, and a rater who can find the validation pairs is no
longer screened by them. (b) The per-family budget moved out of the
rater-visible `manifest.json` into `key.json`. (c) The images handed to the VLM
are re-staged under position-neutral filenames (`reference.png`, `first.png`,
`second.png`), because `pair-007-left.png` on the judge's command line names the
side the both-orders swap exists to conceal. R repeats remain last by design —
§3 calls them "delayed" — and now present the **opposite** side from their
origin rather than an independent draw, since an independent draw left about half
of them pixel-identical to the trial they repeat.

### E5 — repeats are placed inside a delay zone, superseding part of E4

**2026-08-25.** E4 above records that "R repeats remain last by design". That
half of E4 is **superseded**; the rest of E4 stands. This block is append-only,
so E4's wording is left as written and corrected here.

Keeping the repeats in a fixed tail satisfied §3's "delayed" requirement but
created a marker: with the budget known, positions 41–45 ARE the R family. A
rater who knows a trial is a repeat answers it from memory rather than from the
image, which is precisely the quantity the rater-consistency statistic is
supposed to measure — so the marker made that number partly self-fulfilling.

The five repeats are now placed at **seeded-random slots inside the last 40% of
the sheet**, and each draws its origin from the trials appearing earlier on the
sheet. Both §3 properties are preserved — every repeat is still strictly delayed
relative to the trial it repeats, and still re-randomized (the side remains the
negation of its origin's, per E4) — while the position no longer identifies the
family. The zone fraction is `FamilyPlan.repeatDelayZone`, recorded with the
rest of the plan.

No decision rule changes: rater consistency remains reported and never gated.

A repeat's origin is always a **unique trial, never another repeat**: a repeat of
a repeat would apply the side inversion twice and land back on the original
trial, and would put one underlying trial on the sheet three times rather than
giving the R family five distinct re-presentations.
