---
id: ASKI-62
title: >-
  Arbiter protocol v2: converter-level arms, so a shape-query polarity treatment
  can be scored
status: In Progress
assignee: []
created_date: '2026-09-01 21:42'
updated_date: '2026-09-10 04:22'
labels:
  - research
  - arbiter
dependencies:
  - ASKI-56
documentation:
  - docs/Research/2026-09-04-aski62-arbiter-v2-protocol.md
  - docs/Research/2026-09-04-aski62-arbiter-v2-validation.md
modified_files:
  - Tools/AskiColorLab/Arbiter/ArbiterProtocol.swift
  - Tools/AskiColorLab/Arbiter/ArbiterCensus.swift
  - Tools/AskiColorLab/Arbiter/ArbiterPairPlan.swift
  - Tools/AskiColorLab/Arbiter/ArbiterCLI.swift
  - Tests/AskiTests/AskiColorLabArbiterV2Tests.swift
  - docs/Research/2026-09-04-aski62-arbiter-v2-protocol.md
  - docs/Research/2026-09-04-aski62-arbiter-v2-validation.md
priority: high
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OWNER-AUTHORIZED 2026-09-01 after the ASKI-60 review. The ASKI-56 arbiter v1 (AskiColorLab arbiter stimuli/judge/score) is the standing gate for any default promotion, but it cannot express a converter-level treatment: ArbiterCensus converts each fixture ONCE with the production converter and derives every arm by re-running SelectionCeiling.Arm selectors over that single query, then substitutes characters into the production grid. A polarity arm (RenderingOptions.shapeQueryPolarity, or the ASKI-61 per-charset map) needs a second convert with different RenderingOptions, and there is no seam for one in Census, ArmRef, ArmKey or PairPlan. The v1 protocol's own status line requires a v2 plus re-validation for any change after the first collected vote, and 45 votes were collected on 2026-08-26. Exact surgery: ASKI-60 verdict note section 9 (docs/Research/2026-09-01-aski60-shape-query-polarity.md). This task is the prerequisite that unblocks ASKI-61 AC#4 and any future default flip of the shape-query polarity.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Add a converter-level arm type parallel to SelectionCeiling.Arm that carries its own RenderingOptions delta (at minimum shapeQueryPolarity), and extend ArbiterCensus to run one convert per such arm instead of one convert per fixture
- [x] #2 Widen ArmRef, ArmKey and the key.json metric deltas to carry the converter-level arm so a stimulus is attributable to its convention on disk, mirroring the selection-ceiling CSV shapeQueryPolarity column
- [x] #3 Re-register the family budget (families C and M draw pairs from the arm pool, so adding an arm changes the sampled distribution the ~45-trial budget is defined over) and record the new budget before any vote is collected
- [ ] #4 Re-run the section 5.1 validation of the ASKI-56 protocol under v2 and record the result as a research note; v1 verdicts stay valid for v1 arms and are not re-scored
- [x] #5 Emit the inverted-vs-direct blocks stimuli from the ASKI-60 results so the owner can run the sitting; do NOT flip any default in this task
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Pre-register arbiter protocol v2 before generating evidence: schema, typed converter arms, fixed family budget, explicit polarity comparison family, compatibility boundary, and validation rules.
2. Add unified selection/converter arm identities, v2 key encoding with v1 decode, one real conversion per converter arm, and full-grid stimulus rendering.
3. Re-register the deterministic pair plan and add explicit inverted-versus-direct blocks pairs while preserving the v1 validation and calibration semantics.
4. Add independent tests for key compatibility, unknown-arm failure, real converter parity, blinding, budget, and seed determinism; update CLI help and generated command surface.
5. Run focused tests and check-fast, generate release v2 stimuli and machine evidence, record the non-human validation result, update the research registry and task evidence, then run full just check.
6. Commit locally. Keep ASKI-62 In Progress because the human and VLM section 5.1 sitting remains outstanding; check only acceptance criteria proven by automated evidence.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-02 blotter review: generate v2 stimuli from a RELEASE build (swift run -c release AskiColorLab arbiter stimuli). A debug build did not finish the protocol regime in 20 min; release took 65 s (ASKI-56). Recorded in the protocol note section 2.1 and docs/agents/research-methodology.md.

2026-09-04 implementation and automated evidence:
- Frozen protocol v2 was committed at f5a44a9 before any v2 census or stimulus generation.
- Converter-level inverted/direct arms, unified on-disk identities, schema-v2 writing with frozen v1 decoding, one conversion per converter arm, and the 51-pair V/D/X/C/M/R plan landed at dbf8e2a.
- Focused Swift 6.4 arbiter validation passed 72 tests across 7 suites. Full just check passed: 1,518 core tests with 3 existing known issues, 152 serial media tests, both deadlock sentinels, research-index and repo-map drift checks, formatting, and DocC.
- Release generation from dbf8e2a emitted 51 blinded triplets, 51 sheet PNGs, answers-template.csv, key.json, and manifest.json at /private/tmp/aski-62-v2-stimuli-dbf8e2a with seed 4242. Small machine records are committed under docs/Research/Results/2026-09-04-aski62-arbiter-v2/.
- AC #4 remains open. No human answers or VLM votes were collected and no X or default-change verdict is claimed. Exact remaining gate: one blinded human sitting over all 51 pairs and the pinned VLM leg over V+D+X+M; each must prefer F over production/inverted on at least 5 of 6 V pairs before X can be interpreted.

2026-09-04 integration-review correction: the focused arbiter validation used Swift 6.3.2, not Swift 6.4. The exact measured side-branch commits remain f5a44a9 (protocol) and dbf8e2a (implementation); main preserves content-equivalent trees at 9d34f8d45e616f46b8512a4500413262e700ae05 and d6169510b766768ebc24e47c1e3016fe855a1502. The validation note and result provenance now record both. Follow-up hardening rejects schema/protocol mismatches, missing v2 arm kinds, budget/count drift, duplicate IDs, and broken repeats, and reports the input key protocol version in score artifacts.

2026-09-04 frozen VLM collection status: the one permitted default VLM leg completed exactly once against code SHA 0f9226d. Collection produced the expected 26 V+D+X+M pairs and 156 calls, with 0 retries and 0 invalid calls. The judge configuration byte-matched the frozen pin, and an external structural recomputation passed. Raw decisions remain unopened and embargoed until the owner submits the complete 51-sheet one-sitting review. This is collection-integrity evidence only: no VLM score, X interpretation, product decision, or default-change verdict exists. ASKI-62 remains In Progress and AC #4 remains open.

### Implementer context — 2026-09-10 (base 952529a)

Current state: ASKI-62 remains In Progress. Arbiter v2 is shipped and machine validated. `Arbiter.ConverterArm` registers production/inverted and production/direct; `Arbiter.ArmRef` records arm kind and `shape_query_polarity`; `KeyFile.pairs()` keeps schema-v1 decoding while enforcing v2 identity, budget, and repeat invariants. `Census.run` converts each converter arm once per source/charset and keeps its full grid separate. `PairPlan.build` emits 51 trials: V=6, D=6, X=6, C=20, M=8, R=5. The committed validation record traces a release stimulus build from dbf8e2a (main-equivalent d616951), seed 4242, and six corpus-qualified sources. It records one permitted default VLM collection at code SHA 0f9226d with 26 V+D+X+M pairs, 156 calls, zero retries, and zero invalid calls. Raw VLM decisions remain unopened and embargoed; no VLM score, X interpretation, polarity verdict, or default change exists.

Start here: Read `docs/Research/2026-09-04-aski62-arbiter-v2-protocol.md` and `docs/Research/2026-09-04-aski62-arbiter-v2-validation.md`; then inspect `Tools/AskiColorLab/Arbiter/ArbiterProtocol.swift` (`ArmRef`, `KeyFile.pairs`), `Tools/AskiColorLab/Arbiter/ArbiterCensus.swift` (`Census.run`), `Tools/AskiColorLab/Arbiter/ArbiterPairPlan.swift` (`FamilyPlan`, `PairPlan.build`), and `Tests/AskiTests/AskiColorLabArbiterV2Tests.swift` plus `Tests/AskiTests/AskiColorLabArbiterPairFamilyTests.swift`. The small provenance files are `docs/Research/Results/2026-09-04-aski62-arbiter-v2/manifest.json` and `result.yaml`; the visual bundle is not committed.

Constraints and dependencies: ASKI-56 v1 keys and verdicts stay frozen and are never re-scored as v2 evidence. The human owner is the arbiter. The pending human sitting must rate all 51 sheets in one sitting before opening `key.json`; the human section 5.1 gate is at least 5 of 6 F-over-production/inverted V decisions. The pinned VLM leg must independently pass the same 5-of-6 V gate. VLM scope is V+D+X+M unless C is explicitly opted in. Only after both gates pass may the six X comparisons be interpreted, and X cannot meet the standing 30 decided non-repeat threshold by itself. Release generation is required; no default flip is authorized.

Validation to run: The current unified command is `swift run -c release aski lab color arbiter stimuli --output-dir <output-dir> --seed 4242 --columns 80 --oversample 2 --footprint 24`; the committed manifest's `AskiColorLab arbiter stimuli` command is historical provenance for the measured release build. After the owner submits answers, the future score command is `swift run aski lab color arbiter score --output-dir <score-dir> --stimuli-dir <stimuli-dir> --answers <answers.csv> --judge-results <judge-results.json>`. Keep the existing frozen stimulus/key/VLM bundle for the pending sitting. The stimulus command is a replay reference; never pair regenerated stimuli or a new key with already collected votes. Do not run judge, score, collection, or any response generation during this handoff.

First step: complete the blinded 51-sheet owner sitting, preserve the unopened key and raw VLM decisions, then score both v2 validation gates. A failed human gate stops downstream interpretation; v1 evidence remains untouched.

Source map: `Tools/AskiColorLab/Arbiter/ArbiterSubcommands.swift`.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented and machine-validated arbiter protocol v2 with typed converter-level polarity arms, schema-v1 read compatibility, a registered 51-pair budget, and release-built blinded stimuli. No default changed. ASKI-62 remains In Progress because the required human and VLM section 5.1 validation has not run.
<!-- SECTION:FINAL_SUMMARY:END -->
