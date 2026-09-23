---
title: "Perceptual arbiter protocol v2 — converter-level arms and an explicit shape-query-polarity treatment"
slug: 2026-09-04-aski62-arbiter-v2-protocol
date: 2026-09-04
status: active
subsystem: [shape-context, meta]
summary: "The pre-registered v2 extension of the ASKI-56 perceptual arbiter. It adds typed converter-level arms, a schema-v2 identity record, and six explicit inverted-versus-direct blocks comparisons while retaining the v1 validation, disagreement, calibration, adversarial, repeat, scoring, and human-authority rules. The registered budget is 51 trials: 46 unique comparisons and 5 delayed repeats. Historical v1 keys and verdicts stay frozen and are never re-scored as v2 evidence."
related_specs: [docs/Research/2026-08-25-aski56-arbiter-protocol.md, docs/Research/2026-08-27-aski56-arbiter-verdict.md, docs/Research/2026-09-01-aski60-shape-query-polarity.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1]
runners: [AskiColorLab]
next_action: "The registered schema, pair plan, release-build stimuli, and one permitted default VLM collection are complete; the VLM decisions remain unopened and embargoed. Run the blinded 51-sheet owner sitting, then score both section 5.1 validation gates before interpreting the six polarity comparisons."
---

# ASKI-62 — Perceptual arbiter protocol v2 (pre-registered)

status: FROZEN before any v2 census, stimulus generation, or vote collection. An edit to a
family, budget, decision rule, arm meaning, scoring rule, or blinding rule requires v3.
authored: 2026-09-04. This note records the rule, not a result.
task: ASKI-62. Extends the ASKI-56 v1 protocol only where converter-level treatments require it.

## 1. Compatibility boundary

The ASKI-56 v1 protocol and its 2026-08-27 verdict remain frozen. V2 does not rewrite, migrate,
or re-score those votes. A v1 `key.json` remains readable so the existing result store can still
be inspected and scored by current tooling. A new run always writes schema and protocol version
`2`; an unknown schema, arm kind, arm name, or converter delta fails the run.

All v1 rules not changed below carry forward unchanged: the human owner is the arbiter; the VLM
is a pre-screen and tie-breaker; identity is absent from rater-visible files; the section 5.1
validation floor is at least 5 of 6 F-over-production decisions for each leg; the human verdict
requires at least 30 decided non-repeat trials; calibration uses the same source-resampled JND75
fit; and repeats remain delayed, side-inverted re-presentations.

## 2. Arm and census model

V2 has one unified internal arm identity with two closed variants:

- `selection`: the v1 selector arms F, F_legacy, T(w), K(topK), lex(topK), and znorm(w). The v1
  selection-only P identity is decoded for compatibility but is not registered in the v2 pool.
- `converter`: production conversion with one declared `shapeQueryPolarity` delta. The two
  registered values are `inverted` and `direct`. The default/inverted arm must equal an ordinary
  production conversion cell for cell.

The current knob is `@_spi(AskiResearch) public` at
`Sources/Aski/RenderingOptions.swift:118`; it is not in the public initializer. Each converter
arm constructs its own `ASCIIConverter`, applies its own typed `RenderingOptions` delta, and calls
`convert` exactly once for each source and charset census. Its rendered stimulus is its real full
grid, not a character substitution onto another arm's grid. Selection arms continue to use the
inverted production converter's grid, query descriptors, geometry, colour, alpha, and coverage;
only their selected characters differ. Every arm is scored against the same sampled source cells
and fixed 24 by 24 oracle footprint.

`key.json` schema v2 records `kind`, `name`, selector parameters when present, and
`shape_query_polarity` for converter arms. This identity is included for both sides of every
metric record. A missing `kind` is interpreted only as the historical v1 selection shape. No
unknown field combination is guessed.

## 3. Re-registered family plan

The sources, charsets, columns=80, oversample=2, footprint=24, seed algorithm, blinding, and v1
selector sweep are unchanged. V2 removes selection-P from the live pool, replaces it with the
production/inverted converter arm, adds the production/direct converter arm, and adds an explicit
polarity family:

- **V, 6:** F versus production/inverted on blocks, all six sources. This preserves the v1
  section 5.1 known-case validation meaning.
- **D, 6:** T(w=2) versus F on blocks, all six sources. Recorded, not gated.
- **X, 6:** production/inverted versus production/direct on blocks, all six sources. This is the
  ASKI-60 treatment. It is descriptive until v2 passes section 5.1, and six pairs alone cannot
  satisfy the standing decided-n threshold for a default-change verdict.
- **C, 20:** the same ladder construction and dense minimum of four, drawn from the v2 arm pool.
- **M, 8:** the same rank-sum adversarial construction, drawn from the v2 arm pool.
- **R, 5:** the same delayed repeats, sampled from all 46 unique V/D/X/C/M trials.

The fixed total is **51 trials: 46 unique plus 5 repeats**. Family X is explicit rather than left
to a seeded C or M draw. This makes all six ASKI-60 blocks comparisons available for the owner
sitting and keeps the treatment count stable across seeds. The extra six trials are accepted
instead of shrinking C or M because those v1 counts support the existing JND75 calibration and
adversarial coverage.

The VLM default scope becomes V + D + X + M; C remains opt-in. X results count only after the
VLM leg passes the v2 V gate. The human leg must also repeat the same section 5.1 validation in
the v2 sitting before X can be interpreted.

## 4. Pre-registered validation and evidence rule

Before the human sitting, automated validation must prove:

1. a frozen v1 key decodes as selection arms without changing its recorded version or metrics;
2. a v2 key round-trips both arm kinds and both polarity values;
3. unknown arm kinds, names, parameters, and polarity values fail loudly;
4. production/inverted equals an ordinary converter and production/direct equals a converter
   with the direct SPI option, on actual pixels and grids;
5. a converter arm cannot reuse another arm's grid, and exactly one conversion is requested per
   converter arm in a census;
6. family counts are V=6, D=6, X=6, C=20, M=8, R=5 and the same seed reproduces the complete
   identity and side-assignment sequence.

Stimuli must be generated with a release build. Generated PNGs, manifests, and keys prove only
that the registered instrument executed. They are not human or VLM evidence. The task remains in
progress until one blinded human sitting supplies all 51 answers and the v2 section 5.1 human gate
passes, and until the pinned VLM leg is rerun and passes its own v2 gate. Only then can a result
note interpret X. No default changes in ASKI-62.

## 5. Strongest counter-case

A six-pair X family increases the sitting from 45 to 51 trials and still cannot independently
meet the n=30 human verdict threshold. The lean alternative is to place the polarity pair only in
the C/M pool and keep 45 trials. That is rejected because seed-dependent inclusion can omit the
exact treatment the task exists to expose, and reducing C or M would silently weaken a calibration
whose v1 budget already has collected evidence. X is therefore a fixed diagnostic block, not a
standalone promotion verdict.
