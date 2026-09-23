---
id: ASKI-16
title: >-
  Decide edgeMap by product evidence: remove it or prove an edgeMap-local
  matcher
status: Done
assignee: []
created_date: '2026-08-19 05:13'
updated_date: '2026-09-04 05:15'
labels:
  - correctness
  - algorithms
  - edge-map
dependencies: []
references:
  - docs/Research/2026-09-03-future-direction-and-architecture.md
priority: high
type: bug
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The public .edgeMap algorithm still fails its advertised orientation job after its two local defects were fixed: the honest bucket x charset matrix fails 9 of 20 cases, and .diagonal emits X for every non-blank bucket. The kernel classifies a source cell into a Sobel orientation bucket, then compares a canonical candidate-side 60D template with candidate glyph descriptors. It never compares a source-cell descriptor with a glyph descriptor. Repairing that second stage would therefore add another production matcher beside logPolar.

The 2026-09-03 architecture review changes this from an assumed repair into a remove-versus-prove decision. Vesper uses logPolar, no in-repo product path requires edgeMap, and source compatibility is not a project constraint. The default recommendation is removal unless a named app or bounded product probe establishes value that logPolar, dotMatrix, or a render-space challenger cannot supply. Preserve the historical failure evidence either way.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Inventory every in-repo consumer and name any external app or accepted product probe that requires .edgeMap; absence of a concrete consumer is evidence for removal, not a reason to invent a generic use.
- [x] #2 If no concrete consumer exists, remove the public enum case, EdgeMapKernel, canonical orientation templates, CLI/docs claims, misleading tests, and the baked all-X golden while preserving the historical task and research record.
- [x] #3 If a concrete consumer exists, pre-register an edgeMap-local matcher experiment and require the full six-bucket matrix across .lines, .cross, .diagonal, and .mixed plus the standing no-harm and performance gates before retaining the algorithm.
- [x] #4 logPolar and dotMatrix output stays byte-identical; no shared matcher change is smuggled through this task.
- [x] #5 just check passes.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Confirm no current product or accepted probe consumes `.edgeMap` and preserve the historical research record.
2. Remove the public enum case, edge-map implementation, canonical templates, obsolete golden, and path-specific tests.
3. Retarget shared behavior tests and current docs to the surviving `logPolar` and `dotMatrix` algorithms without changing their output.
4. Regenerate the repository map, run focused tests, and verify frozen output fingerprints.
5. Run the full local gate, record objective evidence, and finalize the task through the Backlog CLI.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verify-close attempt 2026-08-23 (Opus worker, read-only harness vs EdgeMapKernel.templateMatch): AC#1 FAILS. 16.1/16.2 removed the blank collapse (no bucket wins SPACE) but orientation selection is still wrong: .diagonal emits X for ALL five non-blank buckets (/ and \ unreachable, / ranks 3rd on its own bucket); .mixed picks x for both diagonals (correct glyph 10th of 12) and | over + for cross; .lines picks the same ├ for both diagonal buckets (├/┴/┬ within 0.005 — noise). Root cause is NOT in the subtask fixes: the 60D log-polar descriptor does not separate orientation at glyph scale (matches the documented support-collapse finding). Fixing inside the descriptor touches shared machinery (ShapeContext.histogram60) and would violate AC#4's logPolar byte-identity; the plausible shape is an edgeMap-LOCAL matcher (orientation histograms per glyph instead of log-polar templates) — an architecture call, not done. AC#3/#4 verified PASS (rule documented at EdgeMapKernel.swift decision site; only edgeMap sources touched; ce549f5 deliberately re-recorded the .diagonal golden — which now bakes in the all-X defect). AC#2 gap deliberately not filled: an honest orientation matrix test would fail 9 of 20 cells today. AC#5 not run (no verdict possible). Task stays open.

OPEN DECISION for next session (2026-08-23): fix requires an architecture call — (a) edgeMap-LOCAL matcher (per-glyph orientation histograms instead of log-polar templates; preserves logPolar byte-identity / AC#4), possibly filed as subtask 16.3, or (b) wait for ASKI-32 (reference-recovery calibration) to settle how glyph rasters are scored before designing any new matcher. Session recommendation: ASKI-32 first. Also outstanding: the .diagonal snapshot golden re-recorded in ce549f5 bakes the all-X defect into the baseline and must be re-recorded again with the real fix; the honest 6-bucket x 4-set coverage matrix (AC#2) should land WITH the fix since it fails 9/20 cells today.

Board audit 2026-08-24 (deep pass): Description's evidence table predates subtasks 16.1/16.2 and no longer reproduces; current failure mode is the one in these notes (.diagonal emits X for all non-blank buckets, etc.). Verdict holds; AC#1/#2 remain. ASKI-32 blocker is cleared — the edgeMap-local-matcher vs log-polar-templates call is now takeable. Orientation-histogram machinery exists in ShapeMatching.swift:633-671 (ASTSK-35, default-off) as possible reuse.

2026-08-28 (ASKI-52/26 measure-first unit) — consume/decline decision on the position-faithful candidate convention: DEFERRED to the promotion follow-up PR, not taken here.

What the measurement found (docs/Research/2026-08-28-aski52-26-candidate-convention.md):
- A position-faithful, cell-aspect candidate vocabulary was built and censused against the shipped bounds-centred 64x64 square convention at the shipping regime (columns 80, oversample 2, defaults) over 27 NASA fixtures, gated on pick quality MAE-first.
- At MATCHED query support the single-variable convention delta is small and charset-dependent: +0.60%/+0.24% on standard, -11.90%/-2.31% on blocks, -0.22%/-2.54% on braille (steerable/occupancy). The shipped blocks preset gets WORSE when the candidate convention is corrected in isolation.
- The paper's tiled AISS support is the best arm on text at +2.44%/+0.93% with the prescribed 7x7 pre-blur REMOVED, which is under the standing 3.0% bar.
- The large compound production-vs-corrected gap (blocks MAE 0.667 vs 0.352; production SSIM 0.004) is mostly the QUERY path, not the candidate convention: the shipped square convention measured at matched support scores 0.314, about half production's error, and agrees with production on only 12.4% of cells.

Why this matters to ASKI-16 specifically: ASKI-16 is about edgeMap orientation matching failing to select orientation-appropriate glyphs, and CanonicalOrientationTemplates (AlgorithmKernel.swift:87) rasterizes its templates at a 64x64 SQUARE — it inherits exactly the convention ASKI-52 measured. So a promotion would move ASKI-16's templates too. But this unit gives no evidence that the square convention is what breaks orientation selection: the ladder points the larger defect at the query support (ASKI-55's 2x4 thumbnail cell carrying ~3 of 60 live bins), and the new occupancy-corpus rows show engineering line-art fixtures collapsing to 0.33-0.69 live bins of 60 — a plausible mechanism for orientation blindness that has nothing to do with candidate placement.

Decision: do NOT consume the convention into ASKI-16 now. Re-evaluate when the promotion follow-up PR is decided (gated on the ASKI-56 arbiter rule); if it is declined, ASKI-16 should be re-scoped against ASKI-55 instead.

2026-08-28 CORRECTION to the note appended earlier today (ASKI-52/26 unit). A cross-model review found two P1 defects in that census's instrument, both confirmed against production source: the query field was sampled in raw luma where production uses 1-luma (LogPolarKernel.swift:565), and the square baseline rung rasterized text at 64pt where BuildStandardVectors.swift:55 uses 32pt into the same 64x64 canvas.

RETRACTED from the earlier note: the claim that the ladder pointed the production gap at the query support and therefore at ASKI-55. With the instrument corrected there is no such gap — ladder rung (i) reproduces production at MAE 0.66651 vs 0.66651 with 100.0% pick agreement (it had been 12.4%). Do not rely on that earlier reasoning.

What still stands, and what it means for ASKI-16:
- The consume/decline decision is UNCHANGED: still DEFERRED to the promotion follow-up, and the measurement is now more clearly unfavourable. Held at production's own polarity the position-faithful vocabulary is inert-to-harmful (+0.04% blocks steerable, -1.26% occupancy, negative on standard everywhere).
- CanonicalOrientationTemplates (AlgorithmKernel.swift:87) still rasterize at 64x64 square, so they still inherit the convention and would still move with any promotion.
- NEW and more relevant to ASKI-16 than anything in the earlier note: production's shape term inverts the query field while its tone pre-filter, its renderer and its ink-high candidate rasters all treat ink as bright. Flipping only that recovers 0.306/0.247 MAE on blocks and lifts SSIM from ~0.004 to 0.307/0.105. If orientation matching is selecting wrong glyphs, a query field that is upside-down relative to the templates it is matched against is a far more likely mechanism than candidate placement. ASKI-16 should test that first. Caveat: the scoring oracle shares the 'direct' convention, so this is a strong signal rather than a closed proof.

Verdict: docs/Research/2026-08-28-aski52-26-candidate-convention.md (sections 3.1 and 4.2).

2026-08-28 SECOND CORRECTION — retracting the polarity pointer from the note appended earlier today. A second cross-model review caught it and it is confirmed wrong.

WHAT I GOT WRONG: the earlier note said 'a query field upside-down relative to the templates it is matched against is a likelier mechanism for orientation-blind selection than candidate placement, and ASKI-16 should test that first.' That mechanism does not exist on this task's code path. Disregard it.

WHY, verified against source:
- ASKI-16 exercises the .edgeMap kernel. EdgeMapKernel.templateMatch (EdgeMapKernel.swift:136-160) compares a CanonicalOrientationTemplate against characterSet.shapeVectorLanes directly: 'template[laneIndex] - characterSet.shapeVectorLanes[baseLane + laneIndex]'. BOTH sides are candidate-side data. The source cell contributes no descriptor to that comparison at all.
- There is no per-cell 60D source query on this path, and EdgeMapKernel never references LogPolarKernel.baseInvertedLuma (which appears nowhere in Sources/Aski outside LogPolarKernel.swift).
- The only source-derived input is the 4-bin Sobel orientation histogram (EdgeMapKernel.swift:106-121) from EdgeMap gradientMagnitude/edgeAngle, which selects the bucket. That histogram is invariant to a global luma inversion in any case: inverting negates the gradient, leaving magnitude unchanged and shifting the angle by pi, and edgeAngle is a FOLDED edge tangent in [0, pi) (EdgeMap.swift:6), so the folded value is identical.

CONSEQUENCE: flipping the log-polar query polarity cannot change any edgeMap pick. ASKI-60 and ASKI-16 are INDEPENDENT; ASKI-60's task text has been corrected to say so. ASKI-16 must be diagnosed on its own path — the bucket classifier and the template-vs-lanes comparison — not by way of the log-polar query.

STILL STANDING from the earlier notes: CanonicalOrientationTemplates (AlgorithmKernel.swift:87) do rasterize at 64x64 square and so do inherit the ASKI-52 candidate convention, and would move with any vocabulary promotion. The consume/decline decision remains DEFERRED to the promotion follow-up, and the ASKI-52/26 measurement remains unfavourable to promotion.

Lesson worth keeping: two of the three cross-task mechanisms I asserted in this record were wrong on first pass. Trace the actual kernel before claiming a shared mechanism.

2026-09-04 removal verdict: repository-wide consumer inventory found no current product or accepted probe that requires edgeMap. The conditional retention experiment in AC3 is therefore not applicable. Removed the public case, both kernels, canonical templates, edgeMap tests, and the baked all-X snapshot. Preserved historical task and research records. Surviving logPolar and dotMatrix behavior is guarded by unchanged exact-output and snapshot tests. Regenerated the repository map. Validation: just check-fast passed; the final just check passed with 1,512 core tests in 223 suites (three known ASKI-66 issues), 152 media tests in 36 suites, two deadlock sentinels, registry and repo-map checks, and DocC; all six renderer-only charset goldens were also inspected visually.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed the failed, unused edgeMap algorithm and all current claims and fixtures that implied it worked. Replaced matcher-coupled charset snapshots with deterministic renderer-only glyph grids, updated README, DocC, architecture, changelog, and the generated repo map, and preserved historical evidence. Verified with the full local just check gate and visual inspection of all six revised charset snapshots.
<!-- SECTION:FINAL_SUMMARY:END -->
