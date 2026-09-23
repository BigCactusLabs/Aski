---
id: ASKI-61
title: >-
  Per-charset shape-query polarity: blocks direct, others inverted — measure
  under the ASKI-60 gate
status: To Do
assignee: []
created_date: '2026-09-01 20:37'
updated_date: '2026-09-16 17:37'
labels: []
dependencies: []
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MEASURE-FIRST. Follow-up lift from ASKI-60, which measured a FLAT shape-query polarity flip and KILLed it. Verdict note: docs/Research/2026-09-01-aski60-shape-query-polarity.md. Results: docs/Research/Results/2026-09-01-aski60-polarity-gate/.

WHY THIS SHAPE
ASKI-60 flipped the logPolar shape query from '1 - luma' to raw luma for every charset at once. On blocks that is the largest glyph-selection effect this repo has measured: MAE 0.66651 -> 0.35330 on nasa-steerable-v1 (+46.99%) and 0.65714 -> 0.39564 on nasa-occupancy-v1 (+39.79%), GMSD agreeing in sign in both cells (+36.38% / +1.42%), 38.6% / 35.5% of picks moving. It still died, on the pre-registered collateral clause: nasa-occupancy-v1 braille regressed -3.26% MAE and -17.50% GMSD, both oracles agreeing, past the 3.0% veto by 0.26 points.

So the flat treatment loses exactly where the flat treatment is unnecessary. A per-charset polarity keeps the blocks lift and vacates the failing clause by construction. NOT TESTED by ASKI-60 - it is a hypothesis with a mechanism, not a result.

MECHANISM (measured, ASKI-60 sections 5 and 8)
LogPolarKernel prunes to topK = 12 + round(density*24) = 12 at default density, and ShapeMatching takes prefix(min(topK, count)). blocks carries 8 glyphs, so its pool admits every glyph, the tone pre-filter selects nothing and the shape term decides alone. standard (95) and braille (256) both bind at 12.
IMPORTANT REFINEMENT from the ASKI-30/28 ten-charset re-run: a non-binding pool is NECESSARY BUT NOT SUFFICIENT. Production-arm MAE moves were blocks +42.32%, lines +15.85%, mixed +12.82%, but minimal/dots/cross/diamond/diagonal all +0.00% (all five sit at an identical 0.24754 MAE under both polarities - an undiagnosed degeneracy). standard +0.00%, braille +0.03%. So the per-charset map cannot be derived from glyph count alone; it has to be measured per charset.

WHAT NOT TO ASSUME
- Do not assume the map is 'blocks direct, everything else inverted'. lines and mixed also move by double digits and were never gated. Measure all ten built-in charsets.
- The scoring path (ink-high glyph raster vs raw source luma) shares its convention with 'direct', so 'direct' is partly flattered by its own oracle. GMSD is the convention-independent guard (zero-mean Prewitt filters make it invariant to a global negation of both planes) and the negative control is mandatory - reuse polarity-gate's, do not re-derive.
- A per-charset knob is a larger API surface than a global one. Keep it SPI/research-only until a gate says otherwise; ASKI-60 shipped shapeQueryPolarity SPI-only, default .inverted, and nothing about that should change without a decisive result.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Extend the AskiColorLab polarity-gate instrument to accept a per-charset polarity map rather than a single polarity, reusing its existing scoring path, oracle panel and mandatory negative control unchanged
- [ ] #2 Measure all ten built-in charsets at the shipping regime (columns 80, oversample 2, exhaustive census, both photographic corpora) and report per-charset MAE-first deltas, so the map is derived from measurement rather than from glyph count
- [ ] #3 Neither braille nor standard may regress by more than 3.0% MAE on either corpus under the proposed map, and GMSD must agree with MAE in sign wherever the map selects direct
- [ ] #4 No default change without an ASKI-56 arbiter score. The arbiter cannot express a converter-level polarity arm today, so this AC is BLOCKED on a protocol v2 - see ASKI-60 note section 9 for the exact surgery a v2 needs
- [ ] #5 Record the outcome as a research note with a decision rule pre-registered before the run, whatever the sign
- [ ] #6 Diagnose WHY braille regresses under the consistent (direct) convention before accepting a per-charset map: rule in or out the 64x64 square candidate raster flagged in ASKI-52/26 and the near-zero-mass descriptor on dark cells. If braille's loss traces to another defect, the global flip is the right fix and the per-charset map is a workaround for the wrong bug
- [ ] #7 Fix the polarity-gate render arm to downscale the SOURCE to the rendered geometry (area-weighted) instead of upsampling the render, so the sign check against ImageRenderer is a real check
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Wording correction after cross-model review of ASKI-60: the mechanism statement in the description overreaches. Read it as: on the ten built-in charsets, every charset that moved had a non-binding tone pool, and a non-binding pool was not enough on its own. Ten charsets are an observation, not a proof of necessity; and where the pool does not bind, the shape distance ranks the whole set with ShapeMatching's brightness/index tie-breaks still applied. AC#2 (measure, do not derive from glyph count) is the operative consequence.

2026-09-01: owner authorized the arbiter protocol v2 after PR #34 review. The v2 work is filed as ASKI-62 (converter-level arms, budget re-registration, section 5.1 re-validation); AC#4 here is blocked on ASKI-62, not on an owner decision any more.

### Implementer context — 2026-09-10 (base 952529a)

**Current state.** The production seam is the `@_spi(AskiResearch) public` property `RenderingOptions.shapeQueryPolarity` at `Sources/Aski/RenderingOptions.swift:50`; `ShapeQueryPolarity` itself is a top-level public enum. Its default is `.inverted`; `LogPolarKernel.baseInkField` uses either `1 - Rec.601 luma` or raw luma, and all shape subterms read that field. Existing tests show that the default equals explicit inverted behavior, direct polarity changes at least one pick on bright-ink/dark-ground input, and display color is unchanged. `PolarityGate` and its CLI currently run one global polarity per converter arm. They do not accept a per-charset map. ASKI-60 therefore killed flat direct polarity: blocks improved, while braille collateral exceeded the regression limit. The per-charset map is a hypothesis, not a measured result.

**Start here.** Read `RenderingOptions.shapeQueryPolarity`, `LogPolarKernel.baseInkField`, `PolarityGate.run`, and `PolarityGateSubcommand`. Preserve the current four-oracle scoring and negative-control logic. Enumerate the ten built-in charsets named by the task, including blocks, standard, and braille, and make the map an internal lab/instrument value rather than a public API. The ASKI-60 note and public result tables contain the objective evidence; the ASKI-62 v2 note and validation record the separate promotion gate.

**Constraints and dependencies.** The non-binding pool observation is necessary context, not proof that polarity should follow pool size. Measure every charset at the shipping regime on both required corpora with the exact lattice. Keep MAE primary, retain GMSD agreement and the 3% regression veto, and diagnose the braille 64x64 candidate raster/dark-cell path before interpreting a map. The render arm must downscale the source to rendered geometry with area-weighted sampling as required by the task; do not use the old upsampled existence check. ASKI-62 still has no default change: its public validation says the human/VLM gate is open and raw decisions remain embargoed. Do not open private response data or rerun collection.

**Validation to run.** Pre-register the map-selection method, decisive comparison, and negative control, then extend the lab gate and output schema so each arm records the map, charset, corpus, polarity, and render geometry. Run the full ten-charset matrix and confirm that default `.inverted` and global polarity behavior remain byte-stable. Only after the ASKI-62 owner review and independent gate can a candidate be considered for default discussion.

**First step.** Add the smallest lab-side map representation and unit tests for map parsing/defaults. Fix the render-arm geometry, then measure the existing global arms as controls before measuring any map.

Source map: `Sources/Aski/Algorithms/LogPolarKernel.swift`, `Tests/AskiTests/ShapeQueryPolarityTests.swift`, `Tools/AskiColorLab/SamplingLattice/PolarityGate.swift`, `Tools/AskiColorLab/AskiColorLabCommand.swift`, `docs/Research/2026-09-01-aski60-shape-query-polarity.md`, `docs/Research/2026-09-04-aski62-arbiter-v2-validation.md`.

Dependency review 2026-09-16 (backlog architecture audit, docs/Research/2026-09-02-backlog-architecture-audit.md). AC#4 is blocked on the ASKI-62 arbiter protocol v2, as recorded above. A hard ASKI-61 -> ASKI-62 dependency edge was considered and deliberately NOT added: a Backlog.md edge is task-granular and would mark all of ASKI-61 unstartable, but AC#1, #2, #3, #6 and #7 are instrument and measurement work that need nothing from ASKI-62. ASKI-62's instrument has shipped; its remaining AC#4 is a blinded 51-sheet human sitting. Start the measurement ACs now; hold only the default-change verdict for the arbiter score.
<!-- SECTION:NOTES:END -->
