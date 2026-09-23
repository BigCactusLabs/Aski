---
id: ASKI-60
title: >-
  Shape-term query polarity is inverted relative to the tone filter, renderer
  and candidate rasters
status: Done
assignee: []
created_date: '2026-08-28 17:13'
updated_date: '2026-09-01 21:44'
labels: []
dependencies: []
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Production's 60D shape matcher compares a query and a candidate that disagree about which end of the source is ink. Found while measuring ASKI-52/26; it is larger than either of those tasks and belongs to neither, so it is split out here. MEASURE-FIRST: no default changes without a decisive gate.

MECHANISM (all verified against source, 2026-08-28)
- Candidate rasters are ink-high: RasterizedCharacterSet.swift:120-127 fills the canvas at gray 0 and draws the glyph at gray 1. BuildStandardVectors builds the committed .bin lanes from those rasters.
- Production's shape query is INVERTED: LogPolarKernel.swift:565 computes 'grayscale[...] = 1 - luminance' (Rec.601). So the shape term treats DARK source regions as ink.
- Production's tone pre-filter goes the other way: it matches a high source adjustedL to a high candidate ink density, i.e. a BRIGHT cell asks for a DENSE glyph. That is also what the renderer draws (light ink on a dark ground, e.g. the frozen bone-on-oxblood preset) and the convention every archived pick-quality screen scores under.
- So the shape term contradicts the tone term, the renderer, and the candidate rasters. Three against one.

MEASURED EFFECT (docs/Research/Results/2026-08-28-aski52-26-convention-ablation/, both polarity runs; verdict note docs/Research/2026-08-28-aski52-26-candidate-convention.md sections 3.1-3.2 and 4.2)
Holding the arm, the vocabulary and the scoring fixed and flipping ONLY the query field, on the shipped 'blocks' preset at columns 80 / oversample 2, exhaustive census over 27 NASA fixtures:
- nasa-steerable-v1: MAE 0.66651 -> 0.36031 (0.306 recovered)
- nasa-occupancy-v1: MAE 0.65656 -> 0.40970 (0.247 recovered)
- SSIM ~0.004/0.005 -> 0.307/0.105
That is an order of magnitude more than the ASKI-52 candidate convention is worth (+0.04% / -1.26% on the same cells). The instrument is validated: ladder rung (i) reproduces production at MAE 0.66651 vs 0.66651 with 100.0% pick agreement.

CAVEAT THAT SETS THE BAR
The scoring path used above (ink-high glyph raster vs raw source luma) shares its convention with the 'direct' polarity, so 'direct' is partly flattered by the oracle it is judged under. What defends it beyond the oracle is that it also matches the renderer and production's own tone pre-filter, while 'inverted' matches none of the three. This is a strong signal, NOT a closed proof, and it is why this task needs its own gate rather than inheriting the ASKI-52/26 numbers.

COHERENCE WITH AN EXISTING RESULT
ASKI-30/28 recorded that a shape-free tone floor (arm F) beats the real matcher on the frozen preset: blocks MAE 0.264 vs production 0.563 (docs/Research/Results/2026-08-24-aski-30-28-battery/). A shape term matched against an inverted query would actively fight the tone term - a candidate mechanism for that otherwise puzzling result. UNTESTED HYPOTHESIS: this is the same species of cross-task claim as two others in this unit that failed verification (the query-path attribution and the ASKI-16 link, both retracted); nothing has been run to test it. Verification belongs to this task's AC on re-checking archived verdicts. Worth checking whether any archived descriptor verdict was measured under the inconsistency and would move.

NO CONNECTION TO ASKI-16 (corrected 2026-08-28 after a second cross-model review)
An earlier version of this task claimed a polarity flip was a likely fix for ASKI-16. That was WRONG and is retracted. ASKI-16 exercises the .edgeMap kernel, which never builds a per-cell 60D source query and never touches LogPolarKernel.baseInvertedLuma. Verified:
- EdgeMapKernel.swift:136-160 templateMatch compares a CanonicalOrientationTemplate against characterSet.shapeVectorLanes directly ('template[laneIndex] - characterSet.shapeVectorLanes[baseLane + laneIndex]'). Both sides are candidate-side data; the source cell contributes no descriptor at all.
- The only source-derived input is the 4-bin Sobel orientation histogram (EdgeMapKernel.swift:106-121) built from EdgeMap gradientMagnitude and edgeAngle, fed to classifyBucket.
- That histogram is INVARIANT to a global luma inversion anyway: inverting negates the gradient vector, which leaves the magnitude unchanged and shifts the angle by pi, and edgeAngle is a FOLDED edge tangent in [0, pi) (EdgeMap.swift:6), so the folded angle is identical.
So flipping the log-polar query polarity cannot change any edgeMap pick, and ASKI-16 must be diagnosed on its own path. ASKI-60 and ASKI-16 are independent.

BLAST RADIUS IF PROMOTED
- .bin files are NOT affected. The inversion is confined to LogPolarKernel (verified: no other file in Sources/Aski references baseInvertedLuma) and BuildStandardVectors has no polarity dependence at all. Candidate vectors are query-independent, so no regen.
- The ten frozen digests in StandardCharacterSetScalarValidationTests.swift:224 are NOT affected either: they anchor .bin DECODE (builtInSetsDecodeByteIdentically), not picks.
- Snapshot goldens WOULD churn, because picks change. That is the real cost and it should be sized before any flip.
- Archived descriptor verdicts would need a comparability statement.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Reproduce the polarity effect through the REAL converter (not the lab harness) on both photographic corpora at the shipping regime, and report per-charset pick-quality deltas MAE-first
- [x] #2 Establish a gate that does not share the candidate/scoring convention with the treatment, so 'direct' cannot be flattered by its own oracle; ASKI-56 arbiter-backed if the reconstruction margin lands near the bar
- [x] #3 State whether the inversion is deliberate (find the rationale in history if one exists) or an unintended asymmetry, before proposing any change
- [x] #4 Size the snapshot-golden churn a flip would cause, and confirm empirically that no .bin file and no frozen digest moves
- [x] #5 Re-check whether any archived descriptor verdict (ASTSK-31/35/42/43/45, ASKI-30) was measured under the inconsistency and would change sign
- [x] #6 No default change without a decisive gate result recorded as a research note
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-01 measured, verdict KILL for a global flip (docs/Research/2026-09-01-aski60-shape-query-polarity.md; results under docs/Research/Results/2026-09-01-aski60-polarity-gate/). AC#1: real-converter census, 27 fixtures x 3 charsets x 2 corpora: blocks direct beats inverted +47.0%/+39.8% MAE, standard inert, braille -3.26% MAE on occupancy (GMSD -17.5%) -> pre-registered regression veto fires. AC#2: GMSD negation-invariant guard + mandatory negative control (max dGMSD 2.9e-7 over 453,120 pairs); arbiter v1 cannot host a polarity arm (single production convert, frozen arm inventory) -> protocol v2 is an owner decision, recorded as a blocked prerequisite on ASKI-61. AC#3: DELIBERATE at origin (archive 4f613488, 2026-05-04, 'ink = high value matches RasterizedCharacterSet'), UNINTENDED as an asymmetry; tone filter and renderer were light-on-dark from the same commit. AC#4: 11 failures under forced .direct (2 knob guards, 7 log-polar goldens, 2 lab analyses); all 10 ShapeData .bin SHA-256 identical; frozen digests pass. AC#5: ASKI-30/28 battery re-run at both polarities reproduces the archive exactly at inverted; no verdict changes sign; shape-free floor still beats the fixed matcher (0.264 vs 0.325 MAE); standard-only verdicts get comparability statements; ASTSK-27/31/35 not reproducible. AC#6: default stays .inverted; knob is @_spi shapeQueryPolarity. Follow-up: ASKI-61 per-charset polarity (measure-first). Task file had CLI-duplicated SECTION:DESCRIPTION markers (from the 2026-08-28 edits); deduped by hand so the CLI could parse the ACs again.
<!-- SECTION:NOTES:END -->
