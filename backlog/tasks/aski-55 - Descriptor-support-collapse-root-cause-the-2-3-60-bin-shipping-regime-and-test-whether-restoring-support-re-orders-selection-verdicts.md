---
id: ASKI-55
title: >-
  Descriptor support collapse: root-cause the 2-3/60-bin shipping regime and
  test whether restoring support re-orders selection verdicts
status: To Do
assignee: []
created_date: '2026-08-24 16:09'
updated_date: '2026-09-10 04:29'
labels: []
dependencies: []
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The shipped 60D log-polar descriptor carries only 2-3 of 60 bins at the shipping sampling regime (columns 80, oversample 2), while every archived descriptor kill (ASTSK-31/35/42) was measured at the 48-of-60-bin regime — so the negative results characterize a descriptor the shipping path never runs, and the ASKI-30 tone-inversion evidence (shape-free floor beating production on the frozen preset) may be a symptom of a degenerate shape term rather than a missing tone term. Evidence: docs/Research/2026-08-19-sampling-lattice-support-collapse.md and docs/Research/2026-08-19-selection-optimality-gap.md. Spike, lab-side first: identify the mechanism that collapses support (sampling lattice, footprint, thumbnail path), quantify support across regimes, and measure whether restoring support at shipping cost changes pick quality under the house oracle (MAE, per ASKI-27). Relation to ASKI-30/28: runs on the same census instrument; any interaction with the tone-weighted arm is recorded as lift, not folded into that battery's frozen verdict.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The mechanism that reduces descriptor support from 48/60 to 2-3/60 bins at the shipping regime is identified and documented with file:line evidence
- [ ] #2 Support is quantified across a swept set of sampling regimes (at minimum the shipping regime and the archived-kill regime) on both census corpora, with per-charset readouts
- [ ] #3 At least one support-restoring intervention is measured for pick quality under MAE against production at comparable cost, with a frozen PASS/KILL rule committed before the decisive run
- [ ] #4 If restored support re-orders any archived verdict's evidence, the oracle-agreement protocol fires and affected notes are marked superseded, not edited in place
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

**Current state.** The shipping descriptor is a 60-bin, five-radial by twelve-angular log-polar histogram. `ShapeContext.histogram60` admits pixels only above its weight threshold and within the inscribed radius. The exact-lattice path from ASKI-65 now maps each cell to its full source rectangle, so older dropped-edge measurements are historical. The dated support note records roughly 3/60 bins for the shipping 2x4 footprint, 11 at 4x8, 30 at 8x17, 42 at 16x35, and 48 at 32x71. Its selection-ceiling follow-up reports that support count did not track quality, so ASKI-55 still needs a preregistered support-restoring intervention and a fresh oracle decision; no fix is implied by the old counts.

**Start here.** Read `ShapeContext.histogram60`, `ConversionContext.cellSupportsShapeDescriptor`, and `samplingLattice` together. Then compare the independent `LatticeSupport.census` and the converter's real `cellQueryDescriptors` inside `SelectionCeiling.census` (public research SPI at `Sources/Aski/ASCIIConverter+Research.swift:118`). Existing lattice tests already assert that the shipping footprint reaches three bins and that the sampled block reaches the converter's exact edges. Keep the intervention in the lab surface and measure selection and output, not only histogram occupancy.

**Constraints and dependencies.** The support note's PNG-only loader limitation is historical. Current `RealFixture.assetExtensions` in `Tools/AskiColorLab/ShapeResidual/RealFixture.swift` accepts png, jpg, and jpeg, and `LatticeSupport.run` uses that loader; the occupancy corpus is now reachable. Keep the historical table tied to its original steerable fixtures, and label JPEG compression as part of new occupancy measurements. Use the exact current lattice, both task-required corpus arms, and the frozen MAE/PASS-KILL rule with GMSD guard. ASKI-68 removed settled default-off matcher branches, and ASKI-69 is a research-only KILL; neither licenses restoring production options or APIs.

**Validation to run.** First prove census agreement for every tested footprint and charset. Sweep the shipping regime and any support-restoring arm on the same held-out fixtures, recording support, mean rank, MAE, GMSD, and geometry. If an intervention changes an archived conclusion, run the required oracle-agreement check and write a supersede note. Any golden movement needs the no-harm selection-ceiling census.

**First step.** Pre-register the intervention, corpus/loader choice, exact-lattice geometry, and decision rule. Reproduce the existing support table in the lab, then add only the smallest support change that can test the mechanism.

Source map: `Sources/Aski/Algorithms/ShapeContext.swift`, `Sources/Aski/CellSampling.swift`, `Tools/AskiColorLab/SamplingLattice/LatticeSupport.swift`, `Tests/AskiTests/AskiColorLabSamplingLatticeTests.swift`, `docs/Research/2026-08-19-sampling-lattice-support-collapse.md`, `docs/Research/2026-08-19-selection-optimality-gap.md`, `docs/Research/2026-09-04-aski68-production-experiment-cleanup.md`, `docs/Research/2026-09-04-aski69-render-space-matcher-rule.md`.
<!-- SECTION:NOTES:END -->
