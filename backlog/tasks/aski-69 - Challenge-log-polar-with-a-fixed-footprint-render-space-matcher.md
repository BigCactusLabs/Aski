---
id: ASKI-69
title: Challenge log-polar with a fixed-footprint render-space matcher
status: Done
assignee:
  - '@codex'
created_date: '2026-09-04 03:45'
updated_date: '2026-09-04 13:02'
labels:
  - research
  - matcher
  - frontier
dependencies: []
references:
  - docs/Research/2026-08-19-sampling-lattice-support-collapse.md
  - docs/Research/2026-08-19-selection-optimality-gap.md
  - docs/Research/2026-09-03-future-direction-and-architecture.md
  - 'https://hpjansson.org/chafa/ref/chafa-ChafaSymbolMap.html'
  - 'https://github.com/jakobrees/unicasso'
  - docs/Research/2026-09-04-aski62-arbiter-v2-protocol.md
documentation:
  - docs/Research/2026-09-04-aski69-render-space-matcher-rule.md
  - docs/Research/Results/2026-09-04-aski69-render-matcher-challenge/summary.md
modified_files:
  - AGENTS.md
  - Tools/AskiColorLab/AskiColorLabCommand.swift
  - Tools/AskiColorLab/SamplingLattice/RenderMatcherChallenge.swift
  - Tests/AskiTests/AskiColorLabCLITests.swift
  - Tests/AskiTests/AskiColorLabRenderMatcherChallengeTests.swift
  - Tests/AskiTests/Goldens/command-surface.json
  - docs/README.md
  - docs/architecture.md
  - docs/Research/2026-09-04-aski69-render-space-matcher-rule.md
  - docs/Research/Results/2026-09-04-aski69-render-matcher-challenge
  - docs/Research/README.md
  - docs/Research/index.json
priority: high
type: spike
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The shipping log-polar query carries only 2-3 of 60 bins and compares that sparse query with dense candidate descriptors. On the frozen blocks preset, a shape-free tone floor beats production under MAE, GMSD, and HaarPSI. This justifies a bounded challenger, not a pre-decided replacement. Prior work cuts both ways: chafa ships small bitmap matching, while the AISS authors report that aligned RMSE or SSIM overweights overlap and misses shape. UNICASSO shows analytic per-cell color fitting inside a much heavier whole-grid objective; it is pre-release evidence for an experiment, not a dependency or product architecture.

Build this research-only. Compare the current matcher with a same-footprint glyph-mask reconstruction loss, a soft-edge or small-alignment-tolerant variant, and a tone-plus-fill baseline. Keep glyph, placement, color, raster, and sampling conventions fixed within each comparison. Do not add a public option or a second permanent production matcher. A PROMOTE verdict must replace substantial old complexity rather than coexist with it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Commit a pre-registered rule before reading results: named corpora, exact sampling lattices, frozen preset and at least one shape-sensitive dense charset, MAE house oracle, GMSD guard, ASKI-62 human/VLM arbiter trigger, performance budget, and PROMOTE/HOLD/KILL thresholds.
- [x] #2 Implement research-only arms for aligned fixed-footprint glyph-mask loss, a soft-edge or bounded alignment-tolerant variant, and a tone-plus-fill baseline; include analytic foreground/background fitting only if it is isolated as its own variable.
- [x] #3 Compare every arm with current production at identical glyph, placement, raster, color, and sampling conventions; report candidate churn, glyph use, MAE, GMSD, arbiter result when required, wall time, and peak memory.
- [x] #4 Report frozen blocks and shape-sensitive charsets separately so a halftone-like preset cannot decide the general matcher.
- [x] #5 Record PROMOTE, HOLD, or KILL in docs/Research. PROMOTE creates a replacement task with a negative complexity budget; this spike makes no Sources public API or default change.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Audit the current converter, exact-lattice research infrastructure, ASKI-62 arbiter trigger, and historical matcher evidence.
2. Use frontier research to bound three research-only matcher arms and freeze a decision rule before measurements.
3. Implement identical-convention aligned-mask, bounded soft/alignment, and tone-plus-fill arms with independent tests and machine artifacts.
4. Run the frozen blocks and dense-charset battery once; report quality, churn, glyph use, time, memory, and any open perceptual disposition.
5. Apply PROMOTE/HOLD/KILL exactly, update research docs and generated registries, run the full gate, and commit locally.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Frozen rule commit: 2ad2e8a. Research instrument commit: 78cd3d4. The one permitted release run used 78cd3d4441e23de7608efa0b8644123ec0c83741 and wrote docs/Research/Results/2026-09-04-aski69-render-matcher-challenge/.

Mechanical result: KILL. A and S1 each fail the held-out standard GMSD guard; TF fails the standard MAE guard on both corpora. No arm meets the time budgets. Selector storage passes. The objective-candidate set is empty, so the ASKI-62 arbiter trigger did not fire and no human or VLM result is inferred. No Sources file, public API, default, or production matcher path changed.

All acceptance criteria are complete. The combined implementation-plus-result tree passed just check: 1,546 core tests, 152 serialized media tests, 2 isolated deadlock sentinels, and DocC.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architectural review
created: 2026-09-04 13:02
---
Post-refactor interpretation: the KILL is stronger than “render-space matching has no signal.” The aligned arm improved `blocks` MAE by roughly 51-53%, which is a large sparse-vocabulary reconstruction signal, but it did not generalize cleanly to the dense `standard` charset and it missed the frozen performance budget by an order of magnitude or more. Treat log-polar as the incumbent production matcher after this result.

Do not iterate another family of local fixed-footprint feature/loss variants by default. A future matcher challenge should be opened only for a fundamentally different hypothesis class — for example whole-grid/global optimization, a learned teacher/student selector, or contextual/neighborhood selection — and must retain ASKI-69's replacement rule: no second permanent production matcher and a successful challenger must carry a negative production-complexity budget.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
KILL under the pre-registered rule. The three research-only fixed-footprint arms found large blocks MAE gains, but none preserved the dense-charset guards and none met the registered time budgets. Memory passed. No ASKI-62 perceptual sitting was triggered, no production replacement task was created, and no product API or default changed. Full repository validation passed with 1,546 core tests, 152 media tests, 2 deadlock sentinels, and DocC.
<!-- SECTION:FINAL_SUMMARY:END -->
