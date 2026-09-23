---
title: "ASKI-62 - Arbiter v2 automated validation and stimulus handoff"
slug: 2026-09-04-aski62-arbiter-v2-validation
date: 2026-09-04
status: active
subsystem: [shape-context, meta]
summary: "Arbiter v2 is implemented and its automated construction gates pass. A release build at the original implementation commit dbf8e2a, preserved on main by content-equivalent commit d616951, emitted the pre-registered 51 blinded triplets: 46 unique V/D/X/C/M comparisons plus 5 delayed repeats, including six explicit inverted-versus-direct blocks comparisons. The schema-v2 key and manifest (withheld from this repository until the sitting is scored) preserve converter-arm polarity identity, while the frozen schema-v1 key remains readable without migration or re-scoring. The one permitted frozen default VLM leg completed once at code SHA 0f9226d with 26 expected pairs, 156 calls, 0 retries, and 0 invalids; its judge configuration byte-matched the pin and an external structural recomputation passed. Raw decisions remain unopened and embargoed, so no VLM score, X interpretation, or verdict exists. ASKI-62 remains active until the owner completes the blinded 51-sheet sitting and both section 5.1 gates can be scored."
related_specs: [docs/Research/2026-09-04-aski62-arbiter-v2-protocol.md, docs/Research/2026-08-25-aski56-arbiter-protocol.md, docs/Research/2026-08-27-aski56-arbiter-verdict.md, docs/Research/2026-09-01-aski60-shape-query-polarity.md]
datasets: [docs/Research/Corpus/nasa-steerable-v1, docs/Research/Corpus/nasa-structure-v1]
runners: [AskiColorLab]
next_action: "Run one blinded owner sitting over all 51 sheet images while the collected VLM decisions remain unopened. After the owner submits the complete sitting, score both section 5.1 validation gates before interpreting any X comparison."
---

# ASKI-62 — arbiter v2 automated validation and stimulus handoff

## Outcome

The v2 instrument is implemented and its machine-checkable construction gates pass. This run
does **not** supply the human or VLM evidence required by protocol section 5.1. It makes no claim
about which shape-query polarity looks better and does not change the production default.

The protocol was frozen in the original side-branch commit `f5a44a9` before this run; its
main-reachable, content-equivalent commit is `9d34f8d45e616f46b8512a4500413262e700ae05`.
The release executable came from original implementation commit
`dbf8e2a4e6b8e0558e0a7d33d7668a23257adacc`; its main-reachable, content-equivalent commit is
`d6169510b766768ebc24e47c1e3016fe855a1502`. The original SHAs identify the exact measured
builds. The main-equivalent SHAs make their source trees reproducible from a main-only clone.

## Automated validation

The focused Swift 6.3.2 arbiter run passed 72 tests across 7 suites. Independent v2 tests prove:

- the committed schema-v1 key still decodes as 45 selection-only pairs and retains protocol v1;
- schema v2 round-trips selection and converter arms with both registered polarity values;
- unknown arm kinds, names, parameter combinations, and polarity values fail instead of falling
  back to production;
- the two converter arms equal independent real `ASCIIConverter` runs, cell for cell;
- converter grids remain separate, selection-only substitutions cannot leak across arms, and each
  converter arm is converted exactly once per source and charset census;
- the family budget is V=6, D=6, X=6, C=20, M=8, R=5, and seed 4242 is deterministic.

The full local `just check` then passed: 1,518 core tests (3 existing known issues), 152 serial
media tests, both deadlock sentinels, research-index and repo-map drift checks, formatting, and
DocC validation.

## Release stimulus generation

The following release-build command ran from `dbf8e2a`:

```bash
xcrun swift run -c release AskiColorLab arbiter stimuli \
  --output-dir <scratch-dir> \
  --seed 4242
```

It emitted 51 blinded triplets (153 top-level PNGs), 51 one-pair sheet PNGs, a 52-line answer
template including its header, a schema-v2 key, and a schema-v2 manifest. The complete 48 MB
visual bundle stays outside the Swift package. The result bundle with the small machine records,
including the blind key, is withheld from this repository until the blinded sitting is scored; the
full visual bundle is reproducible from the command above.

The generated manifest records protocol v2, schema v2, seed 4242, 51 pairs, columns 80,
oversample 2, footprint 24, and the full implementation SHA. The key was copied as an opaque
machine artifact; it was not used to rate or interpret the blinded sheets.

## Frozen VLM collection status

The one permitted frozen default VLM leg completed exactly once against code SHA `0f9226d`.
Collection produced the expected 26 V+D+X+M pairs and 156 calls, with 0 retries and 0 invalid
calls. The judge configuration byte-matched the frozen pin, and an external structural
recomputation passed.

This is collection-integrity evidence only. The raw decisions remain unopened and embargoed until
the owner submits the complete one-sitting sheet review. No VLM score, X interpretation, product
decision, or default-change verdict exists.

## Remaining human gate

The owner must rate all 51 files in `sheet/` in one sitting on the same display and submit the
answers before opening `key.json` or the embargoed VLM decisions. The human leg must prefer F over
production/inverted on at least 5 of the 6 V pairs. The collected VLM leg must independently pass
the same 5-of-6 V gate. Only after both gates pass can scoring interpret the six X comparisons.

X alone contains six comparisons. It cannot independently satisfy the standing minimum of 30
decided non-repeat trials for a default-change verdict. That limit is intentional: X is an
explicit diagnostic block inside the complete v2 sitting, not a standalone promotion rule.
