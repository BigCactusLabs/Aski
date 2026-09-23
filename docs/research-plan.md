# Aski — Novel Color-Theory Threads: Keystone Eval + Break-the-Decoupling + Expressive Wow

> **Historical plan with executed status notes.** This is the original implementation plan for five novel ASCII color-theory threads,
> produced from a 42-agent frontier-research sweep + adversarial scoring against the codebase.
> It now includes inline execution notes for the slices that have shipped; treat unchecked sections as future work, not the whole document as not-started.
> Repo-truth boundary: commands and targets introduced below were target-state in the original plan. Prefer current inline execution notes, `Package.swift`, and CLI `--help` output before implementation.
> **Note:** this document is kept for its evidence and rationale, not its ordering; it is not the current sequencing authority.
> **ASKI-68 current-state addendum (2026-09-04):** the later KILL/INCONCLUSIVE work closed and removed the Thread C ink-precompensation and Thread D chroma-assist product options, implementation branches, and dedicated commands. The prose below remains the frozen plan and result narrative; use the [ASKI-68 cleanup record](Research/2026-09-04-aski68-production-experiment-cleanup.md) for the live surface and replay boundary.

## Context

Aski's color research corpus is mature but keeps hitting the same wall: every prior color experiment (CAM16-UCS, HyAB, Helmlab, accessible-ansi16) died at **"no measured win."** A frontier-research sweep (8 angles + 5 cross-cutting provocations, 42 agents, adversarially scored against the codebase) found the root cause is not the color science — it's that **nothing scores a *rendered grid* against its *source*.** Prior metrics scored the wrong signal (raw cell-average ΔE) when the eye actually sees the *area-toned composite* of glyph ink over background: `k·FG + (1−k)·BG`.

This plan develops five genuinely novel, Aski-specific threads, in three gated phases. The keystone is an eval oracle whose payoff is *multiplicative* — it converts a queue of nulls into falsifiable verdicts and de-risks everything downstream.

**Novel theories being operationalized (none currently in the corpus):**
- **Area-tone oracle** — score the recomposited cell appearance, not the raw cell average.
- **Isoluminant-blindness is the dual of "glyph = luminance"** — an isoluminant chromatic edge produces zero luminance gradient → both sides collapse to one glyph → subject melts into background. Inject `λ·|∇chroma|` into the shape channel.
- **Ink-fraction area-tone** — a sparse `.` composites to mostly-background and reads muddy; back-solve FG so the composite matches the source.
- **The background is dead slack** — promoting BG to a per-cell pick lifts color cardinality from N to ~N².
- **The matcher's discarded distance is a free no-reference structure signal.**

**Hard project rules honored:** Don't rename `ASCII*` types. Aux targets live under `Tools/`/`Tests/` (not `Sources/`). Regenerated `.metallib` is N/A (no Metal touched). `.bin` regeneration is CI-byte-diffed → called out explicitly. No public-API stability contract (source-breaking OK when justified) — but every default here is byte-identical, so no snapshot churn unless a new knob is enabled. Each lab needs a `docs/Research/` note + `result.yaml` + `BuildResearchIndex --check`.

---

## Phase 0 — Keystone Eval (build first; gates everything)

### Thread A — Composited-Cell Perceptual Oracle  *(effort L; the gate)*

**Target** `Tools/AskiDecolorLab/` (mirror `Tools/AskiAccessLab/`) is registered in `Package.swift` as an `.executableTarget(dependencies: ["Aski", "AskiToolSupport"])` and added to `AskiTests` deps (so the `check` subcommand is unit-tested). It must be registered to be a valid `result.yaml` `runner` (`IndexCheck` parses `Tools/`-pathed executable targets from `Package.swift`).

**Mechanism:** drive the **real** `ASCIIConverter` over a small fixed fixture corpus (reuse `AccessFixtures` generators + add `isoluminantSwatch`, `lowInk_sparse`). Per `ASCIICell`: read chosen `character` + `displayColor` (FG); resolve ink-fraction `k` from `characterSet.brightnessValues[glyphIndex]`; `BG` = lab-supplied background. Compute `perceived = k·sRGBDecode(FG) + (1−k)·sRGBDecode(BG)` in linear light → `ColorConversion.linearSRGBToOKLAB`. Compare to the source-cell OKLab aggregate (lab owns the fixture pixels; average them with the same linear-light path as `CellSampling.linearLightAverage`). Metrics: `l_fidelity`, `chroma_fidelity`, full ΔE (reuse `AccessScoring.oklabDelta`). CVD variant via `CVDModel.simulateEncodedSRGB(_, deficiency:)` for all 3 deficiencies.

**First-cut deliberately uses the relative brightness ramp (no `.bin` change).** Tradeoff stated in the result summary: monotonic with true ink-fraction → valid for **discrimination/ranking** (which is what the gate tests), biased for **absolute** L-fidelity. The absolute-fraction `.bin` work is deferred behind the gate (shared with Thread C).

**FAIL-FAST gate (encoded as `swift run AskiDecolorLab check`, run in CI):**
1. **Discrimination:** mean `l_fidelity` must strictly separate `monochrome` > `ansi16` > `fullColor` with non-overlapping bootstrap CIs; coverage-aware vs coverage-blind scoring must re-rank ≥X% of cells.
2. **2AFC calibration:** synthetic cell pairs (true sub-glyph half-tone vs flat tone matched in mean L, at phone-DPI cell sizes) — if the model can't beat chance, **that is the publishable KILL.** The `check` subcommand returns nonzero → red build → team converts to a negative-result note instead of starting Phase 1/2.

**result.yaml:** `outputs:["perceived_fidelity.csv"]`, `runner:"AskiDecolorLab"`, plus required `ResultManifest` keys. CSV: `…, fixture_id, palette_id, row, col, character, ink_fraction, ink_model, fg_hex, bg_hex, perceived_hex, source_hex, deficiency, l_fidelity, chroma_fidelity, oklab_delta`.

**Tests:** `AskiDecolorLabRunTests` (row counts; `check` passes on baseline, fails on a degraded palette) + `AskiDecolorLabScoringTests` (composite math vs hand-computed blends). No `.bin`/PNG churn. **Concurrency:** value-type `Sendable` rows; per-fixture `TaskGroup` collects into local arrays (no `@unchecked`).

### Thread B — Glyph Shape-Residual Field  *(effort M; independent, can run parallel to A)*

Surface the winning 60D distance the matcher already computes and discards.

- `ShapeMatching.swift`: add `findBestScored(...) -> (index: Int, distance: Float)` (returns the `bestDistance` dropped at line 116) and `findRankedScored(...) -> [(index, distance)]` (returns `scored` *with* `distance`, dropped by `.map(\.index)` at line 67). Refactor `findBest` to call `findBestScored().index` — keeps the `@inlinable` hot path byte-identical.
- `Algorithms/LogPolarKernel.swift` + `EdgeMapKernel.swift`: add a `scoreScored` returning `(Character, Float)`; `EdgeMapKernel.pick` also returns its `bestDistance`; `DotMatrixKernel` returns a documented sentinel (no shape distance). **Do not touch `AlgorithmKernel.score`/`match`** → production path unchanged, no perf regression.
- `ASCIIConverter.swift`: add `internal func convertWithResidual(_:columns:) -> (grid: ASCIIGrid, residual: [Float])` (mirrors `convertWithRankedCandidates`), filling a row-major `[Float]`.
- Lab command `shape-residual-map` (in `AskiColorLab`, which already has CSV/seed/output plumbing): emits `shape_residual.csv` + `shape_residual_heatmap.png` (both listed in `result.yaml outputs` or `IndexCheck` fails).

**Experiment + KILL:** residual must rank-correlate (Spearman) with an independent structure oracle (re-rasterize chosen glyph, SSIM vs source cell); KILL if no correlation. **Tests:** `findBestScored.index == findBest`, `distance` == hand-computed L2. Prefer a CSV golden over a PNG baseline. No `.bin` churn.

**▸ GATE: Thread A discrimination + 2AFC `check` must pass before any Phase 1/2 work begins.**

---

## Phase 1 — Break the Decoupling (gated by the Phase 0 oracle)

### `.bin` format v2 — shared prerequisite for Thread C and E1 *(one regeneration event, one PR)*

> **✅ EXECUTED (ASTSK-28): shipped as designed.** Layout details were locked in the private
> development archive (decision #1); the regeneration folded in a sanctioned Core Text AA drift
> (see Discoveries 2026-06-10).

`RasterizedCharacterSet.swift`: add `public let rawDensityValues: [Float]` (the pre-`maxRaw`-divide `rawBrightness`); keep `brightnessValues` exactly as-is so matching stays byte-identical. `StandardCharacterSet.swift`: bump `.bin` to **v2** (extra `[charCount × f32]` raw-density block; v1 loads with `rawDensityValues == brightnessValues`). `Tools/BuildStandardVectors/BuildStandardVectors.swift`: write the raw block; **regenerate all 10 `Sources/Aski/Resources/ShapeData/*.bin`** (CI byte-diff is the intended, reviewed churn). Add a v1→v2 parse round-trip test.

### Thread C — Ink-Fraction Color Pre-Compensation  *(effort M–L)*

> **✅ EXECUTED (ASTSK-29, PR #35): KILL — gamut-bound, not algorithm-bound.** The back-solve is
> infeasible at real ink fractions (every compensated FG′ projects to the achromatic boundary);
> knobs stay in, off by default. Verdict + revival candidates:
> `docs/Research/2026-06-10-thread-c-ink-precompensation.md`.

Back-solve `linearFG' = (linear(source) − (1−k)·linear(BG)) / k`, gamut-map (`rayTrace`), palette-match FG'; gate on `k ≥ k_min` with fallback below.

**Pipeline split** (confirmed necessary — `cellStats` finalizes `displayColor` *before* the glyph is picked):
- Split `CellSampling.cellStats` into `cellSourceStats(at:) -> CellSourceStats` (stops before palette-match: `sourceOKLab`, `adjustedL`, `rawL`, `alpha`, `linearBG`) and `finalizeColor(source:inkFraction:)`.
- In `ASCIIConverter.convert`: build a *provisional* `CellStats` (palette-matched on `adjustedL`, identical to today) so the glyph picker is byte-identical when compensation is off → pick glyph → look up `k = rawDensityValues[index]` → if `k ≥ k_min`, recompute `displayColor` via the back-solve; else keep provisional.
- New knobs in `RenderingOptions` (+ `ResolvedRenderingOptions` clamps): `inkPreCompensation: Float = 0` (0 → bit-identical) and `inkPreCompensationFloor: Float` (k_min, default ~0.15).

**Expected concentration:** `fullColor` wins; `ansi16` quantizes FG' back to 16 entries → ~no-op (document, not a bug). **Scored by the Thread A oracle** (compensation on/off). **KILL** if no oracle win on `fullColor`, or if `rayTrace` projection routinely cancels the correction. **Tests:** golden test that `inkPreCompensation=0` → byte-identical grid; back-solve algebra unit test. **`.bin` churn called out in PR.**

### Thread D — Isoluminant Rescue  *(effort M; independent of C, query-vector change only)*

> **✅ EXECUTED (ASTSK-30, PR #36): PASS — but the sketch below is superseded on two points.**
> The shipped gradient is the **Di Zenzo vector gradient** `√(|∇a|²+|∇b|²)`, not Sobel on the
> scalar chroma field `c = √(a²+b²)` (which is near-blind to red/green hue edges: `C` stays
> ~constant while `a` flips sign), and the injection is a **mass-normalized blend**
> `g′ = (1−λ)·g + λ·(Σg/Σ∇c)·∇c`, not the peak-1 additive bump (which caps at ~9% of the
> L1-normalized descriptor mass against the inverted-luma flood of saturated colors — structurally
> inert). Do not re-implement this paragraph as written. Verdict + derivations:
> `docs/Research/2026-06-10-isoluminant-rescue.md`; the matching locked decisions (#3/#4) were
> recorded in the private development archive. λ dose-response and real-image calibration
> deferred to ASTSK-36.

`Algorithms/LogPolarKernel.swift` `extractShapeVector` (lines 60–107): after the inverted-luma `grayscale` (lines 65–77) and before the `edgeEmphasis` Sobel blend (83–93), if `chromaShapeAssist > 0`, compute per-pixel OKLab chroma `c = √(a²+b²)` (via `sRGBDecode → linearSRGBToOKLAB`/`linearP3ToOKLAB` per `context.colorSpace`), run the **existing `sobelMagnitude`** on the chroma field, normalize to peak 1, `grayscale[i] += λ·|∇chroma|[i]`. New `RenderingOptions.chromaShapeAssist: Float = 0` (λ=0 skips the chroma loop entirely → bit-identical; same guard pattern as `edgeEmphasis`).

**Fixtures + metric (lab):** isoluminant edges at constant OKLab L (red/green, blue/yellow). Metric = Shannon entropy of chosen-glyph histogram across the edge band. **KILL** if entropy doesn't rise with λ. **Tests:** `chromaShapeAssist=0` byte-identical on a color fixture; isoluminant edge yields a non-blank glyph at λ>0, blank at λ=0. No `.bin` churn (changes the query vector, not candidate vectors).

---

## Phase 2 — Expressive Wow (gated by Phase 0; fully spec E1, sketch E2)

**Recommendation: ship E1 first.** E1 is additive (nil-default `ASCIICell` field + per-cell 2-means + renderer bg specialization). E2 needs a new `RenderColorSpace` case (every exhaustive `switch colorSpace`), a **float `CGBitmapContext`** (explicitly *deferred* in `ColorPipelinePolicies.swift`), and depends on the unbuilt ASTSK-10 EDR stub.

### Thread E1 — Two-Color Cells  *(effort L; depends on `.bin` v2 + oracle)*

- `ASCIICell.swift`: add `public let backgroundColor: SIMD3<Float>? = nil` (trailing defaulted init param → all 4 existing call sites stay source-compatible; `Hashable`/`Sendable` auto-synthesize).
- `CellSampling.swift`: per-cell **2-means in OKLab** over the cell window (k=2, init from extreme-L pixels, ≤5 iters reusing `KMeansRefinement` constants — avoids a per-cell 33³ SAT). Assign smaller-area cluster → FG, larger → BG by ink-area split; palette-match both. **Re-rank the glyph within the existing top-K** so `rawDensityValues[index]` ≈ measured ink-area (this is why E1 depends on `.bin` v2).
- **Shape-hijack guard:** re-rank stays inside the shape top-K; lab checks Spearman(source L-gradient, chosen-glyph density-gradient) doesn't degrade vs baseline; clamp re-rank strength if it does.
- **Renderers that learn per-cell bg:** `ImageRenderer` (overpaint cell rect when non-nil; global fill stays as base), `AttributedStringRenderer` (bg text attribute), `PlainTextRenderer` (degrades to FG-only — documented), `Animation/AnimatedASCIIGrid` (copy `backgroundColor` verbatim per frame to preserve the color-fixed invariant), `Effects/Internal/CellRasterBuilder`. GIF/Video converters flow through `renderImage` → no direct change.
- Gate `RenderingOptions.twoColorCells: Bool = false` (false → nil bg → byte-identical, no snapshot regen).
- Lab `two-color-eval`: cardinality gain + oracle fidelity on/off + Spearman guard. **KILL** if no oracle fidelity gain beyond single-color, or Spearman degrades. New `twoColorCells=true` snapshot baseline (isolated; created after `.bin` v2).

### Thread E2 — Coverage-Gated EDR Gain  *(sketch only; lowest priority)*

New `RenderColorSpace.extendedLinearDisplayP3` (updates every exhaustive `switch colorSpace` — source-breaking, acceptable, flag in PR), float `CGBitmapContext` path (lifts the deferred float-bitmap work), `EDRGainPolicy` mapping ink-fraction `k` → FG luminance multiplier >1.0 with an H-K headroom-allocation term. SDR fallback keeps the existing `[0,1]` clamp → bit-identical. Defer until E1 ships and the float-bitmap deferral is lifted; relates to existing ASTSK-10.

---

## Sequencing & dependencies

1. **A first-cut** (relative ramp) + **B** — parallel, no deps.
2. **▸ GATE:** A discrimination + 2AFC `check` pass. KILL → stop, write negative-result note.
3. **`.bin` v2** (absolute density) — shared prerequisite for C and E1.
4. **C** (loop split, scored by A) and **D** (query-vector change) — can run in parallel after the gate.
5. **E1** (renderer fan-out, depends on `.bin` v2 + A).
6. **E2** — sketch; deferred.

**API-break flags:** `.bin` v2 (versioned, back-compat path); E2's new `RenderColorSpace` case. A/B/D/E1 are purely additive with byte-identical defaults.

**Research hygiene:** track one task per thread (relate C to ASTSK-7 occupancy, E2 to ASTSK-10 EDR). Each lab gets a `docs/Research/<date>-*.md` note + `result.yaml`; run `swift run BuildResearchIndex --check`. On approval, the implementation follows the brainstorming → planning → execution handoff.

---

## Verification

- **Build/test:** `swift build && swift test`; targeted golden tests prove byte-identity at default knobs (`inkPreCompensation=0`, `chromaShapeAssist=0`, `twoColorCells=false`).
- **Phase 0 gate:** `swift run AskiDecolorLab evaluate --output-dir /tmp/aski-decolor --columns 80` then `swift run AskiDecolorLab check --output-dir /tmp/aski-decolor-check --columns 80` (CI). Inspect `perceived_fidelity.csv` from the evaluate run for monochrome > ansi16 > fullColor separation; confirm 2AFC d′ above threshold.
- **Thread B:** `swift run AskiColorLab shape-residual-map --output-dir /tmp/aski-lab`; eyeball heatmap localizes to high-frequency regions; CSV Spearman vs SSIM oracle.
- **Thread C:** re-run the oracle with `inkPreCompensation` on/off on a fullColor corpus; assert `l_fidelity`+`chroma_fidelity` drop on fullColor.
- **Thread D:** isoluminant fixtures, sweep λ∈{0,0.25,0.5}; glyph-pick entropy rises across the edge band; control luminance edge unchanged at λ=0.
- **Thread E1:** `two-color-eval` cardinality + oracle fidelity gain; Spearman shape-channel guard holds; visual diff an 80-col render.
- **Resource integrity:** after `.bin` v2, `swift run BuildStandardVectors` produces the committed bytes; v1→v2 round-trip test passes; CI byte-diff reflects only the intended format bump.
- **Research index:** `swift run BuildResearchIndex --check` passes for every new Results dir + note.

**Critical files:** `Sources/Aski/ASCIIConverter.swift`, `Sources/Aski/CellSampling.swift`, `Sources/Aski/ShapeMatching.swift`, `Sources/Aski/Algorithms/LogPolarKernel.swift`, `Sources/Aski/CharacterSets/{RasterizedCharacterSet,StandardCharacterSet}.swift` + `Tools/BuildStandardVectors/BuildStandardVectors.swift` (the `.bin` v2 event), `Sources/Aski/ASCIICell.swift` + renderers (E1); `Tools/AskiDecolorLab/` registered in `Package.swift`.

---

## Appendix — full ranked thread shortlist (for reference / future picks)

The five threads above were selected from 19 scored candidates (composite = novelty + implementability + expectedGain + productValue − risk). Threads not selected, in case priorities shift:

| Thread | Axis | Effort | Score | Core idea |
|--------|------|--------|-------|-----------|
| Composited-Cell Perceptual Oracle ✅ | eval | L | 16 | Score recomposited cell vs source (keystone) |
| Glyph Shape-Residual Field ✅ | eval | M | 14 | Surface the discarded 60D match distance |
| Isoluminant Rescue ✅ | fidelity | M | 14 | Chroma-gradient → shape channel (sleeper) |
| CSV structure/color/salience triple | eval | L | 13 | Chen-CSV 3-channel decomposed quality score |
| categoricalHue + naming oracle | fidelity | M | 13 | Match by basic-color *name*, not ΔE |
| Cell-size-scaled CVD audit | a11y | S | 13 | CSF area-factor + coverage-blend on the audit |
| Coverage-as-Chroma Daltonization | a11y | L | 13 | Lost chroma → glyph density (CVD carrier) |
| Dual-Constraint CVD Palette Synthesis | a11y | M | 13 | Generate (not audit) CVD-safe palettes |
| Blue-Noise Glyph Dithering | temporal | S | 13 | Kill FS worms; spatial mask as temporal stabilizer (note: pre-scoped in archived v2 design) |
| Ink-Fraction Color Pre-Compensation ✅ | fidelity | M–L | 12 | Back-solve FG for the composite |
| Two-Color Cells ✅ | expressive | L | 12 | Per-cell background → ~N² colors |
| Chroma Bleed | fidelity | M | 11 | Cross-cell a/b low-pass, L preserved |
| Dichromat-Space Palette Matching | a11y | M | 11 | argmin in CVD-simulated OKLab |
| Coverage-Gated EDR Glow (sketch) ✅ | hdr | L | 11 | Sparse bright glyphs bloom on XDR |
| Dithered Temporal Color | temporal | M | 10 | Out-of-palette hues via frame integration (flicker-fusion risk) |
| Chroma error diffusion | fidelity | M | 8 | FS the full OKLAB residual (corpus calls FS-in-OKLAB "table stakes") |
| Mood-Seeded OKLCH Palettes | expressive | L | 8 | Mood seed → harmonic palette + CVD variants |
| Decidability Registry | eval | M | 4 | Experiments-as-assets + CI gate (park: assumes the oracle) |
| CSF-weighted palette match | fidelity | M | 3 | Scale-dependent L/a/b ellipsoid (park: library has no cell-size; corpus-duplicate) |

✅ = selected for this plan.
