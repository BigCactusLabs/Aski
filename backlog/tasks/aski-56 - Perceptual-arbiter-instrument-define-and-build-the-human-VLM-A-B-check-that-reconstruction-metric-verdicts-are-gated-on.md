---
id: ASKI-56
title: >-
  Perceptual arbiter instrument: define and build the human/VLM A/B check that
  reconstruction-metric verdicts are gated on
status: Done
assignee: []
created_date: '2026-08-24 16:09'
updated_date: '2026-08-27 04:00'
labels: []
dependencies: []
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-27 adopted MAE as the house oracle but explicitly parked the human-preference/VLM A/B arbiter as the missing instrument, and every standing rule since (ASKI-28 AC#3, ASKI-30 AC#3, the ASKI-30+28 frozen decisive rule's perceptual gate) requires a perceptual check before any default change — currently satisfied only by an informal PresetLab contact-sheet review. This task builds the real instrument: a defined, repeatable A/B protocol (owner-blinded side-by-side renders and/or a VLM judge with a frozen prompt and model pin), validated against known cases (the blocks tone-only-vs-production inversion, which all five reconstruction oracles agree on, and at least one case where oracles disagree), and used to calibrate what MAE margin corresponds to a visible difference — grounding the 3.0 percent bar perceptually or replacing it. External grounding: MAE-class metrics have poor perceptual relevance (Ding et al. IJCV 2021; ambiguity-interval work by Cheon et al. 2021). Judge-reliability caveat applies: a VLM judge must itself be validated against human judgment on the known cases before its verdicts count.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An A/B protocol is defined and documented: stimuli generation, blinding, question wording, judge (human, VLM, or both), model/prompt pins for any VLM, and a frozen decision rule
- [x] #2 The instrument is validated on known cases: it must agree with the unanimous five-oracle blocks inversion and its behavior on at least one oracle-disagreement case is recorded
- [x] #3 The MAE margin corresponding to a just-visible difference on the census fixtures is estimated and reported, and the standing 3.0 percent bar is either perceptually grounded, adjusted, or explicitly retained with reasons
- [x] #4 The perceptual-gate wording in the standing rules is updated to point at this instrument, superseding the informal contact-sheet-only check
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CHECKPOINT 2026-08-25: instrument built+triple-reviewed on branch aski-56 (892fe13, worktree ../aski-56, unpushed). Stimuli generated (arbiter-run/stimuli, seed 0, release build, 65s) and VLM judge leg complete (arbiter-run/judge, 20 pairs V+D+M, 0 invalid votes). REMAINING: owner rates arbiter-run/stimuli/sheet/ into answers-template.csv (one sitting, same display, BEFORE opening key.json) -> arbiter score -> AC#4 docs sweep (site table: arbiter-run/ac4-wording-sites.md) -> full just check -> one PR. Handoff detail in session memory.

VERDICT RUN COMPLETE 2026-08-27: both §5.1 gates PASS 6/6 (human + VLM recover the unanimous blocks inversion). Human leg 32/37 decided for lower MAE (p≈0, ties 3, repeat consistency 0.80). JND75 band -0.345…+0.072 relative MAE margin straddles the 3.0% bar → pre-registered §5.2 disposition: bar RETAINED, arbiter (not the bar alone) required for any default promotion. D family (ASKI-30 near-tie) recorded: 1/4 decided for lower MAE, 2 ties, VLM order-flip 0.50 — leans to the SSIM side, non-gating. Verdict note docs/Research/2026-08-27-aski56-arbiter-verdict.md; result store docs/Research/Results/2026-08-27-aski56-arbiter/. AC#4 wording sweep executed per arbiter-run/ac4-wording-sites.md (decisive-rule addendum + §6→§7 xref fix, battery-verdict resolution note, Discoveries entry).
<!-- SECTION:NOTES:END -->
