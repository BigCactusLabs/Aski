---
title: "Trap audit — every precondition and fatalError in Sources/Aski classified; 18 latent public-input traps share one root cause"
slug: 2026-08-23-aski36-trap-audit
date: 2026-08-23
status: complete
subsystem: [meta]
summary: "ASKI-36. Static classification of all 73 precondition/preconditionFailure/fatalError sites and 37 force unwraps in Sources/Aski into: enforced-at-a-public-boundary (36), internal invariant (56), and latent public-input trap (18). All 18 class-C sites share one static shape: ASCIIConverter accepts any public ASCIICharacterSet conformance without checking its documented parallel-array invariant (characters, brightnessValues, rawDensityValues, shapeVectorLanes, steerableSignatures, structure channels), then LogPolarKernel forwards those arrays into ShapeMatching guards several calls deep, where a count mismatch or empty array traps far from the call the caller wrote. The consolidated fix is one boundary validation, not 18 patches; filed as a single follow-up task rather than the 18 the acceptance criteria anticipated, because every trigger path runs through the same unvalidated conformance."
related_specs: [docs/Research/Discoveries.md]
datasets: []
runners: []
next_action: "One consolidated follow-up task validates the ASCIICharacterSet parallel-array invariant at the ASCIIConverter boundary (covering all 18 ShapeMatching trigger paths). No behaviour changed under ASKI-36 itself. Class-B rows double as the registry a future public entry point must re-check before bypassing an internal invariant."
---

# ASKI-36 — Trap audit

**Status:** SETTLED as an audit. No behaviour changes. **Task:** ASKI-36 · **Date executed:** 2026-08-23
Produced by a static sweep (read-only worker) over Sources/Aski; classifications verified against the
call paths named in each row. The class-C table is the evidence base for the consolidated follow-up.



Static-only audit of all `Sources/Aski` files. I found 73 `precondition`/`preconditionFailure`/`fatalError` sites and 37 syntactic force unwraps: 110 sites total. There are no `assert`, `assertionFailure`, `try!`, or `as!` matches. I did not run builds or tests.

The 18 C sites share one static shape: `ASCIIConverter` accepts a public `ASCIICharacterSet` conformance without checking its documented parallel-array invariant, then `LogPolarKernel` forwards those arrays into matcher guards.

## A — Enforced at a public boundary

| File:line | Condition | Class | Guaranteeing public entry point / guard |
|---|---|---|---|
| `ASCIIPalette.swift:28` | Fixed palette must be nonempty | A | `PaletteContent.fixed(_:)`; guard is this line. |
| `RasterizedCharacterSet.swift:29` | Characters must be nonempty | A | `RasterizedCharacterSet.init`; guard is this line. |
| `TilePalette.swift:36` | Fixed tile palette must be nonempty | A | `TilePalette.fixed(_:)`; guard is this line. |
| `AnimationOptions.swift:17` | Duration must be finite and positive | A | `AnimationOptions.init`; guard is this line. |
| `CyclingOptions.swift:45` | Speed must be finite and positive | A | `CyclingOptions.init` calls `validateSpeed()` at line 38; animation entry points re-check mutable values. |
| `CyclingOptions.swift:46` | Speed must be within representable bounds | A | `CyclingOptions.init` calls `validateSpeed()` at line 38; animation entry points re-check mutable values. |
| `OngoingPattern.swift:63` | Wave frequency must be finite and positive | A | Public pattern acceptors call `validate()`, for example `AnimationOptions.init` at `AnimationOptions.swift:18`. |
| `OngoingPattern.swift:67` | Pulse period must be finite and positive | A | Public pattern acceptors call `validate()`, for example `AnimationOptions.init` at `AnimationOptions.swift:18`. |
| `ASCIIConverter+Animation.swift:11` | Character count must be `1...UInt16.max` | A | `ASCIIConverter.animate`; guard is this line. |
| `ASCIIConverter+Animation.swift:22` | Cycling `k` must be positive | A | `ASCIIConverter.animate`; guard is this line. |
| `AnimatedASCIIGrid.swift:101` | Frame rate must be positive | A | `AnimatedASCIIGrid.materialize(frameRate:)`; guard is this line. |
| `AnimatedASCIIGrid.swift:115` | Materialized frame count must not exceed cap | A | `AnimatedASCIIGrid.materialize(frameRate:)`; guard is this line. |
| `ShapeMatching.swift:17` | Brightness-pool `topK` must be positive | A | Public SPI `ShapeMatching.poolIndices`; guard is this line. |
| `ShapeMatching.swift:49` | Ranked-match query must have 15 lanes | A | `ShapeMatching.findRanked`; guard is this line. |
| `ShapeMatching.swift:55` | Brightness limit must be positive | A | `ShapeMatching.findRanked`; guard is this line. |
| `ShapeMatching.swift:56` | Result limit must be positive | A | `ShapeMatching.findRanked`; guard is this line. |
| `ShapeMatching.swift:113` | Tone-pool `topK` must be positive | A | Public SPI `ShapeMatching.poolIndices`; guard is this line. |
| `ShapeMatching.swift:213` | Occupancy query must have 15 lanes | A | Public SPI `ShapeMatching.findRankedOccupancyScored`; guard is this line. |
| `ShapeMatching.swift:219` | Tone limit must be positive | A | Public SPI `ShapeMatching.findRankedOccupancyScored`; guard is this line. |
| `ShapeMatching.swift:220` | Occupancy result limit must be positive | A | Public SPI `ShapeMatching.findRankedOccupancyScored`; guard is this line. |
| `ShapeMatching.swift:221` | Tone weight must be nonnegative | A | Public SPI `ShapeMatching.findRankedOccupancyScored`; guard is this line. |
| `ShapeMatching.swift:269` | Best-scored query must have 15 lanes | A | `ShapeMatching.findBestScored`; guard is this line. |
| `ShapeMatching.swift:275` | Best-scored `topK` must be positive | A | `ShapeMatching.findBestScored`; guard is this line. |
| `ShapeMatching.swift:325` | Ranked-scored query must have 15 lanes | A | `ShapeMatching.findRankedScored`; guard is this line. |
| `ShapeMatching.swift:330` | Ranked-scored candidate set must be nonempty | A | `ShapeMatching.findRankedScored`; guard is this line. |
| `ShapeMatching.swift:331` | Ranked-scored brightness limit must be positive | A | `ShapeMatching.findRankedScored`; guard is this line. |
| `ShapeMatching.swift:332` | Ranked-scored result limit must be positive | A | `ShapeMatching.findRankedScored`; guard is this line. |
| `ShapeMatching.swift:333` | Ranked-scored lane count must match candidates | A | `ShapeMatching.findRankedScored`; guard is this line. |
| `ShapeMatching.swift:501` | Steerable `topK` must be positive | A | Public SPI `ShapeMatching.findBestSteerableScored`; guard is this line. |
| `ShapeMatching.swift:502` | Steerable query must have 15 lanes | A | Public SPI `ShapeMatching.findBestSteerableScored`; guard is this line. |
| `ShapeMatching.swift:576` | Ranked-steerable `topK` must be positive | A | Public SPI `ShapeMatching.findRankedSteerableScored`; guard is this line. |
| `ShapeMatching.swift:577` | Ranked-steerable result limit must be positive | A | Public SPI `ShapeMatching.findRankedSteerableScored`; guard is this line. |
| `ShapeMatching.swift:578` | Ranked-steerable query must have 15 lanes | A | Public SPI `ShapeMatching.findRankedSteerableScored`; guard is this line. |
| `ShapeMatching.swift:634` | Structure `topK` must be positive | A | Public structure match APIs reach this first guard before using `topK`; converter-derived `topK` is always positive. |
| `ShapeMatching.swift:635` | Structure query must have 15 lanes | A | Public structure match APIs reach this guard; converter-generated query lanes have length 15. |
| `ShapeMatching.swift:637` | Structure query histogram must have 8 bins | A | Public structure match APIs reach this guard; converter-generated histogram has 8 bins. |

## B — Internal invariant

| File:line | Condition | Class | Guarantee / invariant owner |
|---|---|---|---|
| `ResolvedPalette.swift:17` | Fixed content must expose colors | B | `PaletteContent` has private storage; a non-pass-through value can only be `.fixed(colors)`. |
| `ResolvedPalette.swift:30` | Tile resolved palette must be nonempty | B | `TilePalette.fixed` rejects empty input; adaptive resolution returns pass-through when empty. |
| `ResolvedPalette.swift:70` | Palette color space must be supported | B | `PaletteColorSpace` has no public initializer; callers can supply only its two public constants. |
| `ResolvedPalette.swift:86` | Palette color space must be supported | B | Same sealed `PaletteColorSpace` representation. |
| `CellSampling.swift:219` | Helmlab colors must be populated | B | `ResolvedPalette(content:needsHelmlab:)` derives population from the same matching policy. |
| `ASCIIConverter.swift:171` | Candidate stride must be positive | B | `animate` computes `max(1, ...)`; SPI `rankedCandidateIndices` checks `limit > 0` at `ASCIIConverter+Research.swift:66`. |
| `StandardCharacterSet.swift:26` | Built-in resource load failure | B | `loadOrFatal` receives only fixed built-in names from `StandardCharacterSet+Builtins.swift:4-13`. |
| `RasterizedCharacterSet.swift:47` | Two fixed assist footprints must match | B | Both values are library-owned tuning constants; no public caller supplies either. |
| `LumaResample.swift:9` | Source count must equal source dimensions | B | Only `LogPolarKernel` calls it with `baseInvertedLuma`, created at exactly `cellWidth * cellHeight`. |
| `LumaResample.swift:10` | All source and target dimensions must be positive | B | Conversion preparation establishes positive cell dimensions; target footprint is fixed or guarded by `bottleneck > 0`. |
| `Animation/BitSet.swift:11` | Set index must be in range | B | `ScheduleBuilder` derives it from bounded row/column loops over the same `cellCount`. |
| `Animation/BitSet.swift:22` | Lookup index must be in range | B | `AnimatedASCIIGrid.grid(at:)` derives it from bounded base-grid row/column loops. |
| `Animation/PatternEvaluator.swift:66` | Wave frequency must be valid | B | Every public pattern entry calls `OngoingPattern.validate()` before evaluator use. |
| `Animation/PatternEvaluator.swift:82` | Pulse period must be valid | B | Every public pattern entry calls `OngoingPattern.validate()` before evaluator use. |
| `Animation/ScheduleBuilder.swift:17` | Snapshot character count range | B | Only `ASCIIConverter.animate` calls it, after its line-11 check. |
| `Animation/ScheduleBuilder.swift:18` | Candidate stride must be positive | B | Caller passes the internally guarded `RankedConversionResult.candidateStride`. |
| `Animation/ScheduleBuilder.swift:21` | Cycling `k` must be positive | B | `ASCIIConverter.animate` validates it at line 22 before calling the builder. |
| `Animation/ScheduleBuilder.swift:26` | Candidate buffer size must match grid | B | `convertWithRankedCandidates` allocates this exact size and returns the buffer unchanged. |
| `Animation/ScheduleBuilder.swift:27` | Candidate-count buffer size must match grid | B | `convertWithRankedCandidates` allocates one count per cell. |
| `ShapeMatching.swift:544` | `rows.min` must exist | B | Lines 500-501 establish a nonempty candidate pool before rows are built. |
| `ASCIIConverter.swift:121` | Row buffer base address exists | B | `prepareConversion` establishes `rows >= 1` before the buffer is made. |
| `ASCIIConverter.swift:227` | Ranked row buffer base address exists | B | Same positive prepared grid invariant. |
| `ASCIIConverter.swift:228` | Candidate buffer base address exists | B | Positive rows, columns, and guarded candidate stride make the allocation nonempty. |
| `ASCIIConverter.swift:229` | Candidate-count buffer base address exists | B | Positive prepared grid makes the allocation nonempty. |
| `ASCIIConverter.swift:349` | Residual row buffer base address exists | B | Same positive prepared grid invariant. |
| `ASCIIConverter.swift:350` | Residual buffer base address exists | B | Positive rows and columns make the allocation nonempty. |
| `Tiles/TileGrid.swift:41` | Constant 1×1 fallback CGContext exists | B | All CGContext inputs are fixed constants, not public values. |
| `Tiles/TileGrid.swift:42` | Constant fallback image exists | B | Follows the fixed 1×1 fallback context. |
| `LightingApplicator.swift:49` | `CIRadialGradient` exists | B | Filter name is a compile-time constant; callers cannot alter it. |
| `LightingApplicator.swift:70` | `CIAdditionCompositing` exists | B | Filter name is a compile-time constant. |
| `LightingApplicator.swift:77` | `CIMultiplyCompositing` exists | B | Filter name is a compile-time constant. |
| `MaskCompositor.swift:11` | `CIBlendWithMask` exists | B | Filter name is a compile-time constant. |
| `Effects/ASCIIGrid+Effects.swift:622` | Constant 1×1 fallback CGContext exists | B | All inputs are fixed constants. |
| `Effects/ASCIIGrid+Effects.swift:623` | Constant fallback image exists | B | Follows the fixed 1×1 fallback context. |
| `Effects/ASCIIGrid+Effects.swift:674` | `CIBlendWithMask` exists | B | Filter name is a compile-time constant. |
| `StockCIEffectKernel.swift:66` | `CIVignette` exists | B | Filter name is a compile-time constant. |
| `StockCIEffectKernel.swift:80` | `CIBloom` exists | B | Filter name is a compile-time constant. |
| `StockCIEffectKernel.swift:104` | `CIGaussianBlur` exists | B | Filter name is a compile-time constant. |
| `StockCIEffectKernel.swift:112` | `CIPixellate` exists | B | Filter name is a compile-time constant. |
| `StockCIEffectKernel.swift:175` | `CIMultiplyCompositing` exists | B | Filter name is a compile-time constant. |
| `StockCIEffectKernel.swift:182` | `CICMYKHalftone` exists | B | Filter name is a compile-time constant. |
| `StockCIEffectKernel.swift:197` | `CISourceOverCompositing` exists | B | Filter name is a compile-time constant. |
| `StockCIEffectKernel.swift:229` | `CIScreenBlendMode` exists | B | Filter name is a compile-time constant. |
| `StockCIEffectKernel.swift:302` | `CIColorMatrix` exists | B | Filter name is a compile-time constant. |
| `StockCIEffectKernel.swift:312` | `CIAdditionCompositing` exists | B | Filter name is a compile-time constant. |
| `CellMaskExtractor.swift:5` | `CIColorMatrix` exists | B | Filter name is a compile-time constant. |
| `ImageRenderer.swift:584` | Constant 1×1 fallback CGContext exists | B | All inputs are fixed constants. |
| `ImageRenderer.swift:585` | Constant fallback image exists | B | Follows the fixed 1×1 fallback context. |
| `Animation/ASCIIConverter+Temporal.swift:172` | Row buffer base address exists | B | Public temporal conversion guards positive columns and prepared grid dimensions. |
| `Animation/ASCIIConverter+Temporal.swift:173` | OKLab buffer base address exists | B | `cellCount` is positive after grid preparation. |
| `Animation/ASCIIConverter+Temporal.swift:174` | Adjusted-L buffer base address exists | B | `cellCount` is positive after grid preparation. |
| `Animation/ASCIIConverter+Temporal.swift:175` | Alpha buffer base address exists | B | `cellCount` is positive after grid preparation. |
| `Animation/ASCIIConverter+Temporal.swift:176` | Held-index buffer base address exists | B | `cellCount` is positive after grid preparation. |
| `Animation/ASCIIConverter+Temporal.swift:255` | Lock buffer base address exists | B | The pointer is used only when `sourceTetherRho != nil`, which creates a `cellCount`-sized buffer. |
| `Animation/ASCIIConverter+Temporal.swift:257` | Lock buffer base address exists | B | Same source-tether allocation invariant. |
| `Algorithms/EdgeMapKernel.swift:136` | Canonical template exists for bucket | B | Template map is built from every `EdgeBucket.allCases`; bucket is an internal closed enum. |

## C — Latent public-input trap

| File:line | Condition | Class | Public call path and concrete trigger |
|---|---|---|---|
| `ShapeMatching.swift:16` | Brightness candidate set nonempty | C | `ASCIIConverter.init(characterSet:) -> convert(_:columns:) -> LogPolarKernel.score -> degenerateToneRanking -> ShapeMatching.poolIndices`; use a custom set with `characters = ["x"]`, `brightnessValues = []`, `.square`, `oversample = 1`, and a 1×1 image. |
| `ShapeMatching.swift:54` | Ranked brightness candidate set nonempty | C | `ASCIIConverter.rankedCandidateIndices(_:columns:limit:) -> convertWithRankedCandidates -> LogPolarKernel.match -> ShapeMatching.findRanked`; one-character custom set with `brightnessValues = []`, `limit = 2`. |
| `ShapeMatching.swift:57` | Ranked candidate lanes match candidate count | C | Same ranked path; use `characters = ["x"]`, `brightnessValues = [0]`, and `shapeVectorLanes = []`. |
| `ShapeMatching.swift:112` | Tone candidate set nonempty | C | `ASCIIConverter.init -> convert -> LogPolarKernel.score -> degenerateToneRanking -> ShapeMatching.poolIndices`; custom set overrides `rawDensityValues = []`, with `occupancyMatching = 1`, and use the 1×1 degenerate-cell trigger. |
| `ShapeMatching.swift:218` | Occupancy tone candidate set nonempty | C | `ASCIIConverter.init -> convert -> LogPolarKernel.score -> findBestOccupancy -> findBestOccupancyScored -> findRankedOccupancyScored`; custom set has `rawDensityValues = []`, with `occupancyMatching = 1`. |
| `ShapeMatching.swift:222` | Occupancy candidate lanes match tone candidates | C | Same occupancy path; use `rawDensityValues = [0]` and `shapeVectorLanes = []`. |
| `ShapeMatching.swift:274` | Best-scored brightness candidate set nonempty | C | `ASCIIConverter.init -> convert -> LogPolarKernel.score -> findBest -> findBestScored`; custom set has `characters = ["x"]`, `brightnessValues = []`. |
| `ShapeMatching.swift:276` | Best-scored candidate lanes match candidates | C | Same default log-polar path; use `characters = ["x"]`, `brightnessValues = [0]`, and `shapeVectorLanes = []`. |
| `ShapeMatching.swift:500` | Steerable candidate set nonempty | C | `ASCIIConverter.init -> convert -> LogPolarKernel.score -> findBestSteerableScored`; custom set has `brightnessValues = []`, nonnil `steerableSignatures`, and `steerableShapeAssist = 1`. |
| `ShapeMatching.swift:503` | Steerable candidate lanes match candidates | C | Same steerable path; use `brightnessValues = [0]`, `shapeVectorLanes = []`, valid signature storage, and `steerableShapeAssist = 1`. |
| `ShapeMatching.swift:504` | Steerable signatures match candidates | C | Same steerable path; use one valid 15-lane candidate plus `steerableSignatures = []` and `steerableShapeAssist = 1`. |
| `ShapeMatching.swift:575` | Ranked-steerable candidate set nonempty | C | `ASCIIConverter.rankedCandidateIndices -> convertWithRankedCandidates -> LogPolarKernel.match -> findRankedSteerableScored`; use `brightnessValues = []`, nonnil signatures, and `steerableShapeAssist = 1`. |
| `ShapeMatching.swift:579` | Ranked-steerable candidate lanes match candidates | C | Same ranked-steerable path; use `brightnessValues = [0]`, `shapeVectorLanes = []`, and `steerableShapeAssist = 1`. |
| `ShapeMatching.swift:580` | Ranked-steerable signatures match candidates | C | Same ranked-steerable path; use valid 15 lanes, `steerableSignatures = []`, and `steerableShapeAssist = 1`. |
| `ShapeMatching.swift:633` | Structure candidate set nonempty | C | `ASCIIConverter.init -> convert -> LogPolarKernel.score -> findBestStructure -> structureScoredPool`; use `brightnessValues = []`, nonnil structure channels, and `shapeStructureAssist = 1`. |
| `ShapeMatching.swift:636` | Structure candidate lanes match candidates | C | Same structure path; use `brightnessValues = [0]`, `shapeVectorLanes = []`, nonnil channels, and `shapeStructureAssist = 1`. |
| `ShapeMatching.swift:638` | Structure orientation histograms match candidates | C | Same structure path; use valid 15 lanes and `ShapeStructureChannels(orientationHistograms: [], radialPeaks: [0])`, with `shapeStructureAssist = 1`. |
| `ShapeMatching.swift:639` | Structure radial peaks match candidates | C | Same structure path; use valid 15 lanes and `ShapeStructureChannels(orientationHistograms: Array(repeating: 0, count: 8), radialPeaks: [])`, with `shapeStructureAssist = 1`. |

## Proposed follow-up tasks for class C

No behavior change is proposed here. Each task records one reachable contract hole and its trigger path.

1. **`ShapeMatching.swift:16` — Empty brightness pool on a degenerate cell.** Record the unvalidated custom-character-set route. Trigger: `ASCIIConverter.convert -> LogPolarKernel.score -> degenerateToneRanking -> poolIndices` with `brightnessValues = []` and a 1×1 `.square` conversion at `oversample = 1`.

2. **`ShapeMatching.swift:54` — Empty ranked brightness pool.** Record the ranked conversion route. Trigger: `ASCIIConverter.rankedCandidateIndices -> convertWithRankedCandidates -> LogPolarKernel.match -> findRanked` with `brightnessValues = []`.

3. **`ShapeMatching.swift:57` — Ranked shape-lane mismatch.** Record the ranked conversion route. Trigger: `rankedCandidateIndices -> convertWithRankedCandidates -> LogPolarKernel.match -> findRanked` with one brightness value and no shape lanes.

4. **`ShapeMatching.swift:112` — Empty occupancy pool on a degenerate cell.** Record the occupancy fallback route. Trigger: `ASCIIConverter.convert -> degenerateToneRanking -> poolIndices` with `rawDensityValues = []`, `occupancyMatching = 1`, and a degenerate cell.

5. **`ShapeMatching.swift:218` — Empty occupancy candidate set.** Record the normal occupancy route. Trigger: `ASCIIConverter.convert -> LogPolarKernel.score -> findBestOccupancy -> findRankedOccupancyScored` with `rawDensityValues = []`.

6. **`ShapeMatching.swift:222` — Occupancy shape-lane mismatch.** Record the normal occupancy route. Trigger: `ASCIIConverter.convert -> findBestOccupancy -> findRankedOccupancyScored` with `rawDensityValues = [0]` and `shapeVectorLanes = []`.

7. **`ShapeMatching.swift:274` — Empty default log-polar candidate set.** Record the default scoring route. Trigger: `ASCIIConverter.convert -> LogPolarKernel.score -> findBest -> findBestScored` with `brightnessValues = []`.

8. **`ShapeMatching.swift:276` — Default log-polar shape-lane mismatch.** Record the default scoring route. Trigger: `ASCIIConverter.convert -> findBest -> findBestScored` with one brightness value and no shape lanes.

9. **`ShapeMatching.swift:500` — Empty steerable candidate set.** Record the steerable scoring route. Trigger: `ASCIIConverter.convert -> LogPolarKernel.score -> findBestSteerableScored` with `brightnessValues = []`, nonnil signatures, and `steerableShapeAssist = 1`.

10. **`ShapeMatching.swift:503` — Steerable shape-lane mismatch.** Record the steerable scoring route. Trigger: `ASCIIConverter.convert -> findBestSteerableScored` with one brightness value, no shape lanes, and `steerableShapeAssist = 1`.

11. **`ShapeMatching.swift:504` — Steerable signature mismatch.** Record the steerable scoring route. Trigger: `ASCIIConverter.convert -> findBestSteerableScored` with valid lanes, empty signatures, and `steerableShapeAssist = 1`.

12. **`ShapeMatching.swift:575` — Empty ranked-steerable candidate set.** Record the ranked steerable route. Trigger: `rankedCandidateIndices -> convertWithRankedCandidates -> findRankedSteerableScored` with `brightnessValues = []`.

13. **`ShapeMatching.swift:579` — Ranked-steerable shape-lane mismatch.** Record the ranked steerable route. Trigger: `rankedCandidateIndices -> findRankedSteerableScored` with one brightness value and no shape lanes.

14. **`ShapeMatching.swift:580` — Ranked-steerable signature mismatch.** Record the ranked steerable route. Trigger: `rankedCandidateIndices -> findRankedSteerableScored` with valid lanes, empty signatures, and `steerableShapeAssist = 1`.

15. **`ShapeMatching.swift:633` — Empty structure candidate set.** Record the structure scoring route. Trigger: `ASCIIConverter.convert -> LogPolarKernel.score -> findBestStructure -> structureScoredPool` with `brightnessValues = []`, nonnil channels, and `shapeStructureAssist = 1`.

16. **`ShapeMatching.swift:636` — Structure shape-lane mismatch.** Record the structure scoring route. Trigger: `ASCIIConverter.convert -> findBestStructure -> structureScoredPool` with one brightness value, no shape lanes, and nonnil channels.

17. **`ShapeMatching.swift:638` — Structure orientation-histogram mismatch.** Record the structure scoring route. Trigger: `ASCIIConverter.convert -> findBestStructure -> structureScoredPool` with valid lanes and empty `orientationHistograms`.

18. **`ShapeMatching.swift:639` — Structure radial-peak mismatch.** Record the structure scoring route. Trigger: `ASCIIConverter.convert -> findBestStructure -> structureScoredPool` with valid lanes, eight orientation values, and empty `radialPeaks`.
