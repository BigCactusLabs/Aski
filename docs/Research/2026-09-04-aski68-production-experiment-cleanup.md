---
title: "ASKI-68 production experiment surface cleanup"
slug: 2026-09-04-aski68-production-experiment-cleanup
date: 2026-09-04
status: complete
subsystem: [shape-context, color-science, meta]
summary: "ASKI-68 removes five settled default-off experiments from the public and production matcher surface: occupancy matching, shape-structure assist, steerable-shape assist, ink pre-compensation, and the inconclusive chroma-shape assist. The durable record is the frozen notes, result artifacts, and Git history; rawDensityValues, the base residual map, selection-ceiling analysis, the ASKI-69 render-matcher challenger, and isolated temporal-research paths remain. RenderingOptions falls from twelve public controls to five, and StandardCharacterSet continues to read v3 files while ignoring their obsolete legacy channel block."
related_specs: [docs/Research/2026-06-09-shape-residual.md, docs/Research/2026-06-10-thread-c-ink-precompensation.md, docs/Research/2026-06-12-occupancy-matching.md, docs/Research/2026-06-24-astsk43-inter-cell-smoothing.md, docs/Research/2026-06-27-astsk42-steerable-channel.md, docs/Research/2026-06-29-astsk41-nca-temporal-prior.md, docs/Research/2026-07-01-astsk45-source-tethered-hysteresis.md, docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md, docs/Research/2026-09-04-aski66-exact-lattice-dose-redesign.md, docs/Research/2026-09-04-aski69-render-space-matcher-rule.md]
datasets: [docs/Research/Corpus/nasa-occupancy-v1, docs/Research/Corpus/nasa-isoluminant-v1, docs/Research/Corpus/nasa-structure-v1, docs/Research/Corpus/nasa-steerable-v1]
next_action: "Do not restore a settled treatment to the public or production surface without a new pre-registered Aski experiment and qualifying product evidence."
---

# ASKI-68 — production experiment surface cleanup

## Decision

Delete the five settled experiments instead of keeping permanent default-off
branches. Their decision rules and measurements remain in the dated notes and
result stores. Git preserves the exact implementations. No live product option
or dedicated runner is required after ASKI-29, ASKI-50, and ASKI-66 closed.

`RenderingOptions` therefore changes from twelve public controls to the five
active controls: `coverage`, `density`, `edgeEmphasis`, `brightness`, and
`contrast`. The research-only `shapeQueryPolarity` remains because the open
ASKI-62 arbiter uses it. `rawDensityValues` also remains: it is independent
glyph data used by tone and decolor-oracle work, not one of the killed
treatments.

## Experiment inventory and minimum durable replay record

| treatment | settled evidence and sampling regime | consumers removed | minimum durable replay record |
| --- | --- | --- | --- |
| `occupancyMatching` | KILL. The 2026-06-12 decision pooled five NASA occupancy strata at 64 columns, with 39 sources and five weights. Tone improved, but both structure oracles, per-image vetoes, and churn failed. | Public option and tuning constants; `LogPolarKernel` and `ShapeMatching` pool/ranker branches; the occupancy lab directory; isoluminant interaction helpers; dedicated tests. | [Verdict note](2026-06-12-occupancy-matching.md), both committed corpora, and Git history. No open task needs the executable branch. |
| `inkPreCompensation` plus floor and background | KILL. The 2026-06-10 absolute-density run at 80 columns scored 7,200 cells per arm and palette. Luminance improved, but full-color chroma regressed because the back-solve left display gamut. | Three public options; `InkPreCompensation`; converter post-pick branches; `compensation-ab`; arguments and tests. | [Verdict note](2026-06-10-thread-c-ink-precompensation.md), including the run at `904efd0`, and Git history. `rawDensityValues` remains. |
| `shapeStructureAssist` plus bottleneck and glyph channels | KILL after the 2026-06-15 fidelity-fix remeasurement. The rank-correlation lift reproduced, but native-footprint chosen-glyph GMSD missed the +3% bar and harmed checker/naturals. | Public option, SPI bottleneck, `ShapeStructureChannels`, structure arrays, matcher rank-mix, production-path arm, decisive-production residual mode, benchmarks, and dedicated tests. | [Residual and production follow-up note](2026-06-09-shape-residual.md), its recorded result locations, and Git history. Base residual-map and lab-local basis analysis remain. |
| `steerableShapeAssist` plus glyph signatures | KILL under the original June native-footprint GMSD battery, then HELD in the ASKI-29/50 exact-lattice replay under MAE, GMSD, HaarPSI loss, CSSIM loss, and MILO. The replay separates current shipping support (2x4 cells, 3/60 bins) from historical support (38x85 cells, 48/60 bins). | Public option and tuning constants; `SteerableEnergy`; signature arrays; matcher blend; steerable-channel and steerable-metric-replay commands; production path, benchmarks, and dedicated tests. | [Original verdict](2026-06-27-astsk42-steerable-channel.md), [exact-lattice replay](2026-09-04-aski29-50-steerable-metric-replay.md), committed replay results, and Git history. The reusable lab battery and ASKI-69 challenger remain. |
| `chromaShapeAssist` | DELETE after INCONCLUSIVE. ASKI-65 retracted the apparent competition-ramp PASS because its truncating lattice omitted the bottom band. ASKI-66 tested 64 candidates x two axes x 21 lambda arms on an exact 8x18 lattice; all 2,688 rows were invariant, so no candidate qualified and the rule stopped before holdouts. The separate NASA corpus verdict remained KILL. | Public option and tuning constants; chroma-gradient query branch; isoluminant-rescue and dose-calibration directories/commands; benchmarks and dedicated tests. | [Exact-lattice record](2026-09-04-aski66-exact-lattice-dose-redesign.md), committed calibration results, earlier frozen notes/corpus, and Git history. No live branch is retained. |

The pre-cleanup consumer inventory was taken from `d7b2a52` before deletion:

- Product code: `RenderingOptions`, `ASCIICharacterSet`, `ASCIIConverter`,
  `ASCIIConverter+Temporal`, `LogPolarKernel`, `ShapeMatching`, `RasterizedCharacterSet`,
  `StandardCharacterSet`, `InkPreCompensation`, `OccupancyMatching`,
  `ShapeStructureChannels`, `SteerableEnergy`, and `LumaResample`.
- Labs: `AskiColorLabCommand`, the `OccupancyMatch` and
  `IsoluminantRescue` directories, the structure/steerable production arms,
  `SelectionCeiling`, and the `AskiDecolorLab` compensation path.
- Validation: ASTSK-55 assist benchmarks; the option, character-set, kernel,
  matcher, raster, residual, command, and lab suites dedicated to these paths;
  and the generated command-surface golden.
- Documentation: public API articles, command/tool inventories, architecture
  and repository maps, release history, research notes, and result manifests.
  Historical release and research records remain unchanged. Current-state docs
  and generated inventories change with the code.

### Failed temporal-path inventory

The task also requires an inventory of settled temporal work. These paths do
not share the public option and ordinary matcher surface removed above:

| experiment | verdict and sampling regime | current consumers | minimum replay surface and disposition |
| --- | --- | --- | --- |
| ASTSK-41 temporal prior | KILL, non-robust. S1 slow-disc and S2 fast-bar stimuli, columns 64/80, 48 frames, alpha in 1/0.6/0.35/0.2 and tau in 0/0.05/0.1/0.2. The shared point qualified only on both S1 cells. | `TemporalPriorState` and `convertTemporalFrame` in the separate animation research extension; `TemporalPriorExperiment`, `TemporalGate`, `TemporalPriorSubcommand`, `MotionLabCommand`; their argument, run, gate, hook, parity, and synthetic-motion tests. | Keep the isolated SPI plus MotionLab replay and [verdict note](2026-06-29-astsk41-nca-temporal-prior.md). It is stateful frame-sequence research and is not folded into the three ordinary converter loops. |
| ASTSK-45 source tether | KILL, non-robust. The same two stimuli and columns over 48 frames, alpha fixed at 1 and rho in 0/0.25/0.5/1/2. Churn fell, but neither S2 cell held fidelity. | `sourceTetherRho` and lock-distance state in the same separate SPI extension; `SourceTetherExperiment`, `SourceTetherGate`, `SourceTetherSubcommand`, `MotionLabCommand`; their experiment, gate, hook, and parity tests. | Keep the shared isolated SPI plus MotionLab replay and [verdict note](2026-07-01-astsk45-source-tethered-hysteresis.md). No public option or ordinary-converter branch exists. |
| ASTSK-43 inter-cell smoothing | KILL, robust across columns 48/64/80/96 on one line-art and three 2048px NASA fixtures. The input-side guided-filter screen was inert and never created a library hook. | Lab-only `InterCellSmoothingSubcommand` and command, guided-filter/seam helpers, and their lab tests. | Keep the self-contained ColorLab replay and [verdict note](2026-06-24-astsk43-inter-cell-smoothing.md). It has no production surface to clean up. |

## Retained boundaries

- `.bin` v3 remains readable. `StandardCharacterSet` validates and skips the
  obsolete nine-float-per-glyph channel block. `BuildStandardVectors` keeps the
  old channel encoding in a generator-local helper so regeneration can remain
  byte-stable without putting the dead math back into the library.
- `selection-ceiling` keeps its tone-weighted comparison. The small equation is
  local to the tool and no longer depends on the removed public occupancy API.
- `shape-residual-map`, the ASKI-62 arbiter, and ASKI-69
  `render-matcher-challenge` remain. They do not expose a killed treatment.
- The ASTSK-41 temporal-prior and ASTSK-45 source-tether paths are also KILLs,
  but they are already isolated behind `@_spi(AskiResearch)` in a separate
  stateful conversion file and owned by dedicated MotionLab replays. They do
  not add a public `RenderingOptions` control or a branch to the ordinary
  converter loops. ASKI-68 records that boundary and leaves the separate
  temporal replay lifetime unchanged.

## Command surface removed

- `AskiColorLab occupancy-match-eval`
- `AskiColorLab isoluminant-rescue`
- `AskiColorLab isoluminant-dose-calibration`
- `AskiColorLab steerable-channel`
- `AskiColorLab steerable-metric-replay`
- `AskiDecolorLab compensation-ab`
- `AskiColorLab shape-residual-map --decisive-production` only; the base
  residual-map command remains.

The same removals flow through the importable lab modules owned by `aski lab`.
The historical replay executables stay as thin shims for the commands that
remain. Frozen result artifacts are not edited or regenerated.

## Validation status

Complete on the tree reconciled to `8fbb9bb`. The command golden was
re-recorded, the research index covers 53 notes, and the repository map covers
106 source files. The v3 audit found all 10 built-in sets byte-identical, with
maximum delta 0 and no sort permutation; canonical vector regeneration produced
no `ShapeData` diff. Focused validation passed 215 production/API/temporal/CLI
tests plus 43 artifact-contract tests. The authoritative `just check` gate then
passed 1,394 core tests, 152 serial media tests, and two isolated deadlock
sentinels, followed by DocC validation.
