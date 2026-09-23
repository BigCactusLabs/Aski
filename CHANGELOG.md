# Changelog

All notable changes to Aski are documented in this file.

Development before v0.7.0 happened in a private repository; this repository's history begins at a
single root commit shortly before v0.7.0, and entries up to and including v0.7.0 are summarized from
the private history. Commit SHAs, issue and pull-request numbers, and tags before v0.7.0 cited in this
file and under `docs/` refer to that repository and do not resolve here.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/) for tagged releases. Aski is pre-1.0; per SemVer 2.0.0 § 4, "anything may change at any time" while the major version is `0`. Minor version bumps within the `0.y.z` range may carry source-breaking changes; consumers should pin to exact versions if they depend on a stable API surface.

## Unreleased

## v0.7.0 — 2026-09-23

### Added

- **Unified research-lab command tree (ASKI-48, #23).** The first-class `aski` product now owns
  `aski lab {color,motion,video,accessibility,decolor,hdr,preset}`, generates Bash, Zsh, and Fish
  completions for the full tree, and launches through an async-correct root. The seven lab
  implementations are importable package modules; the historical `Aski*Lab` products remain as
  byte-thin replay shims with byte-identical help, usage, and exit behavior. Built-binary launch,
  canonical/replay parity, complete command-surface golden, and package-manifest tests guard the
  boundary.
- **CLI mask and photo-dissolve compositing (ASKI-44, #6).** `aski render` now accepts raster
  masks with transparent, solid-color, or original-photo fallbacks; original sizing; active-region
  grounds; hard-edge thresholding; and inversion. It decodes the source once, stages text/PNG/
  manifest outputs as one rollback-capable transaction, and records resolved mask state in the
  additive v1 render-manifest `mask` block when a mask is supplied. Closes issues #6 and #7.
- **Active-region mask grounds (ASKI-43, #7).** `MaskOptions.groundColor` can place an opaque or
  translucent caller-selected color behind active ASCII glyphs and tiles. ASCII and tile grids
  retain the resolved ground, and soft masks interpolate once between completed active and
  inactive branches. The default and effective no-ground paths remain byte-identical; text output
  ignores raster grounds, and the extended-range renderer rejects positive-alpha grounds rather
  than changing its opaque/full-coverage contract.
- **Exact target-width rendering (ASKI-63, #35).** New public
  `ASCIIGrid.renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:)` renders to an
  exact output pixel width instead of a font-size-derived scale, and `aski render --width` exposes it
  on the command line, so PNG pixel size no longer depends on `--font-size`. The shipped arm draws at
  4x the target and area-averages down in linear light — selected over direct rendering by the
  pre-registered ASKI-63 gate (SHIP-B, run 2). `ASCIIGrid.maxTargetPixelWidth` bounds the request at a
  quarter of the renderer's pixel-extent ceiling because the supersampled bitmap must itself fit it;
  out-of-range geometry returns the 1x1 fallback image, matching the scale renderer. The CLI never
  writes one: an out-of-range `--width` is refused up front as a validation error, and a width whose
  *derived height* exceeds the ceiling is caught after the render and refused as a runtime error, so no
  fallback image and no manifest describing one reaches disk. `--width` requires `--render-png`. The
  direct arm remains reachable through the `@_spi(AskiResearch)` `TargetWidthResample` overload for
  research comparison. Addresses issue #33 asks 1 and 2; ask 3 (a lossless animated WebP encoder) stays
  open as ASKI-64, so #33 is not yet closed.
- **Transparent PNG backgrounds (#8).** `aski render --background` now accepts `clear` and
  `transparent` alongside `#RRGGBB` and the existing named colors, producing an alpha-zero ground
  for `--render-png`. The opaque-black default is unchanged. Closes issue #5.

### Changed

- **Custom character sets use one validated glyph snapshot (ASKI-71).** `ASCIIConverter` now
  adapts the four public per-glyph arrays into one internal `GlyphBank` at initialization and whenever
  `characterSet` is assigned. Reference-type conformers that mutate their arrays in place must assign
  the character set again before conversion to refresh the snapshot.
- **`swift-argument-parser` upgraded to 1.8.x (ASKI-47, #26).** Requirement raised from 1.5.1 to
  `from: "1.8.0"` (resolves 1.8.2); the ASTSK-61 command-surface golden was regenerated for the
  richer 1.8 `_dumpHelp` serialization with no semantic surface change. `package-benchmark` is
  held at `"1.31.0"..<"1.36.0"` because 1.36.x removes the Jemalloc trait the benchmark target
  requires. Closes issue #22.
- **DocC Markdown sidecars are opt-in (#12).** `Scripts/validate-docc.sh` now defaults to the
  single warnings-as-errors validation conversion; `--emit-markdown` requests the second
  conversion and fails loudly if the toolchain lacks the flag. The release build passes it, so the
  published Markdown manifest and sidecar assets are unchanged — only local gates stop compiling
  the catalog twice.
- **One build per `just check` (#11).** The gate builds the full test graph once with
  `swift build --build-tests`; the drift tools and every test phase consume it via `--skip-build`.
  Registry assertions the pre-test tools already cover are no longer re-run in-process, while
  `docsRootMatchesAllowlist` stays in the broad run.
- **Media tests run as a bounded serial partition (#13).** `GIF|Video|MotionLab` cases leave the
  parallel core phase and run with `--no-parallel` from the same prebuilt bundle, ahead of the two
  deadlock sentinels. Swift Testing's default concurrency had these competing for the media
  engine, I/O, and temp files with every other suite — the contention behind ASKI-39. Ad-hoc
  `just test-media` keeps its previous parallel scope.
- **`repo-doctor` no longer pins an Xcode version.** `just doctor` and `just release-preflight`
  report the active Xcode and read the Swift minimum from `swift-tools-version` in `Package.swift`;
  `ASKI_REQUIRED_SWIFT_VERSION` remains an override.
- **Render goldens re-recorded on macOS 27 / Xcode 27 (ASKI-77).** Core Text, Core Graphics, Metal
  and Core Image output drifted on unchanged source, so the PNG snapshots and the G0 byte golden were
  re-recorded and `default.metallib` was regenerated with the Xcode 27 Metal toolchain. Glyph
  selection is unchanged: text, selection and `VesperPreset` goldens pass as before. Committed
  `ShapeData` is not regenerated because the ASKI-51 drift audit fired on macOS 27; ASKI-78 owns
  that decision. The goldens now fail on macOS 26.

### Removed

- **Settled experiment surface (ASKI-68).** Removed five failed or inconclusive
  default-off treatments from the public and production matcher surface: occupancy matching,
  shape-structure assist, steerable-shape assist, ink pre-compensation, and chroma-shape assist.
  `RenderingOptions` now has five public controls instead of twelve. `rawDensityValues`, the base
  residual map, selection-ceiling analysis, ASKI-69's lab-only matcher challenger, frozen research
  notes/results, and Git history remain. `.bin` v3 files stay readable, but their obsolete structure
  channels are skipped and the byte-compatible encoder is local to the generator.
- **The failed `edgeMap` algorithm (ASKI-16).** No product or accepted
  probe used it, and its template matcher selected the wrong orientation in 9
  of 20 honest bucket-by-charset cases even after two local fixes (ASKI-16.1
  and ASKI-16.2, #9 and #10), which are superseded by the removal. The public
  `ASCIIAlgorithm.edgeMap` case, its kernels, canonical templates, misleading
  tests, and baked all-X golden are gone. This is a deliberate source-breaking
  change; `logPolar` and `dotMatrix` output are unchanged.

### Fixed

- **Converters dropped the bottom source rows (ASKI-65, #36).** All three converter paths took a
  floored integer cell pitch and sampled the decoded thumbnail from the origin, so the bottom
  `height % rows` rows and right `width % columns` columns were never read — up to 10% of image
  height — while the renderer still drew the grid over the full source aspect, producing a
  vertically stretched, downward-drifting result. The pitch is unchanged and still uniform, but
  the thumbnail is now drawn into a sampling lattice of exactly `columns * cellWidth ×
  rows * cellHeight`, so the origin-anchored walk tiles the raster exactly and
  `SamplingGeometry.droppedX`/`droppedY` are zero. Every rendered-grid golden and snapshot was
  re-recorded against the corrected sampling; no tolerance was loosened. Before the ASKI-68 cleanup,
  the `isoluminant-rescue` lab refused fixtures that were not exact sampling lattices for their resolved
  grids. Re-measured there, the ASTSK-36 competition-ramp instrument no longer graded. ASKI-66 later
  closed its exact-lattice redesign INCONCLUSIVE, and ASKI-68 removed the chroma-shape treatment and
  dedicated runner. The surviving shape-residual and decolor labs map their native oracle blocks
  through the lattice instead.

## v0.6.0 — 2026-08-17

First public release, under the Apache-2.0 license. Code is identical to the
final private-repo state. Changes since v0.5.0:

### Added

- **Canonical Vesper render preset (ASTSK-47).** New public `VesperPreset` —
  `VesperPreset.canonical` is the built-in frozen duotone share preset (blocks charset,
  76 columns, bone `#E8E2D2` sRGB figure on oxblood `#5E1B18` Display P3 ground, `.wide` +
  aspect-faithful render, bundled Courier Prime, contrast `+0.15`, `#161616` charcoal ground, SDR),
  bundling the converter recipe and render parameters as one drift-proof source of truth with
  `render(_:)` as its single entry point. Every knob carries a one-line rationale; knobs were
  settled on `AskiPresetLab` A/B evidence over real faces. Purely additive — existing API output is
  byte-identical. Locked by a golden byte-snapshot plus a guard test that fails if the golden ever
  renders blank, uses non-blocks glyphs, or drops either duotone color.
- **`AskiPresetLab` charset × columns A/B tooling (ASTSK-47).** New research lab: `ab` renders one
  portrait across charset/column candidates through the draft Vesper preset, writing labeled
  candidate PNGs, a contact sheet (thumbnails double as the phone-glance legibility test), and a
  provenance manifest. `--font-size`/`--scale` are bounds-validated at parse time like the other
  labs.
- **Video tooling fidelity + animated-overlay levers (ASTSK-39).** `AskiVideoLab` exposes the
  per-frame quality levers — `--charset`, `--oversample`, `--brightness`, `--contrast`, `--density`,
  `--edge-emphasis` (defaults reproduce `DefaultConverter()` byte-for-byte) — and a time-modulated
  overlay, `--pattern none|wave|pulse`, with `--pattern-amplitude`/`--pattern-frequency` (wave) and
  `--pattern-period`/`--pattern-depth` (pulse). The overlay's global phase is driven by each frame's
  presentation time, so it stays coherent across frames (GIF uses accumulated post-resample
  presentation time). `--pattern-frequency` and `--pattern-period` are validated finite and positive
  at parse time. New public `ASCIIGrid.applyingOngoingPattern(_:at:)` and
  `ASCIIVideoFrame.applyingOngoingPattern(_:)`; `convertVideo(...)` gained an optional `pattern:`
  parameter. The default (`--pattern none` plus the historical lever defaults) is byte-identical to
  prior output.
- **Cosmetic post-render effects for video (ASTSK-44, ASTSK-39 step b).** `AskiVideoLab` exposes
  opt-in `--bloom`/`--scanlines`/`--vignette` (with `--bloom-radius` and `--scanline-frequency`) that
  apply a time-invariant cosmetic `EffectChain` to every rendered frame across all four paths
  (uncapped/capped/resampled MP4, GIF). Effects compose in a fixed bloom → scanlines → vignette order
  (bloom softens glyph edges first, the CRT-style composite lands last). Intensities clamp to `0...1`;
  radius/frequency are validated finite and positive at parse time. Effects are deliberately
  time-invariant — per-frame stochastic effects (glitch/film grain) are not exposed because per-frame
  noise flickers. Each intensity defaults to `0` (off), so omitting every flag is byte-identical to
  prior output. Reuses the existing `ASCIIGrid.renderImage(…, effects:)` overload (no new kernels);
  `convertVideo(...)` gained an optional `effects:` parameter.

### Changed

- **Temporal portrait parity and descriptor reuse (ASTSK-53).** The research-only
  `convertTemporalFrame` path now shares production conversion's portrait-aware thumbnail bound, so portrait
  frames keep the intended per-cell width instead of collapsing to blank one-pixel-cell grids. Each temporal
  cell also extracts its 60-D log-polar descriptor once and reuses those lanes for matching, held-glyph checks,
  and source-tether lock maintenance. Square and landscape output, held/unheld decisions, state arrays, and
  floating-point distance accumulation remain byte-identical; no public or new SPI surface was added.
- **Bounded video export pipeline (ASTSK-52).** The one-shot `convertVideo` path now overlaps ordered
  decode + conversion of the next frame with render + encode of the current frame through a one-frame
  prefetch (two frames in flight total). The original pull semantics remain available unchanged through
  `ASCIIVideoDecoder.grids(...)`; the new sibling `pipelinedGrids(...)` is additive. On deterministic
  12-frame 720p fixtures, wall p50 improved 393 -> 326 ms for identity input and 593 -> 400 ms for rotated
  input, with flat CPU and a structurally bounded resident peak. Exact PTS order, cancellation/failure,
  early termination, and rotated cell-for-cell parity are covered. Adjacent GIF metadata reuse and fused
  orientation-thumbnail prototypes were measured and rejected; the latter failed its color-fidelity gate.
  No benchmark threshold was loosened.
- **Parallel per-cell conversion walk (ASTSK-51).** The per-cell grid loop now walks rows in parallel via
  `DispatchQueue.concurrentPerform` behind a grid-size gate (`GridRowWalk`, default crossover at 1200
  cells), across all four conversion entry points (`convert`, `convertWithRankedCandidates`,
  `convertWithResidual`, and the research-only `convertTemporalFrame`). Writes target pre-sized storage at
  proven-disjoint per-row indices, so output is **byte-identical** to the previous serial walk (guarded by a
  serial↔parallel parity suite and a frozen pre-change golden). `dotMatrix` always walks serially — its
  Floyd–Steinberg error diffusion is cell-order-dependent. Video/animation parallelism stays *within* each
  frame; no nested frame-level fan-out is introduced. Default single-still converts run ~18–40% faster at
  and above the threshold; small grids stay serial where parallelism would lose. Three adjacent
  micro-optimizations from the same audit (existential→generic kernel dispatch, per-cell scratch reuse, and
  a per-conversion log-polar bin table) were each implemented, measured, and **rejected** as non-wins — the
  60-D descriptor compute dominates per-cell cost. No benchmark threshold was loosened.
- **Bit-identical conversion and render cleanup (ASTSK-50).** The default linear-light sampler now uses a
  raw-alpha-gated 256-entry sRGB decode table for opaque pixels and tighter unsafe-buffer traversal while
  preserving the existing partial-alpha path. Helmlab reuses its preserved hue angle; mask fallback scans and
  per-character mask construction are gated behind their constant-time prerequisites; matching, TileGrid
  drawing, palette/color-space setup, and the three production conversion prologues shed verified duplication.
  The research-only temporal conversion path remains separate and unchanged. Default goldens and render
  snapshots remain byte-identical; `just bench` passed unchanged thresholds, with mixed/noisy timings rather
  than a claimed aggregate speedup.

### Fixed

- **Portrait-aspect images rendered blank under `.logPolar` (found during ASTSK-47).** The
  thumbnail decode cap bounded the image's longest side at `max(columns, rows) × oversample`, so a
  portrait input's width fell below `columns × 2`, cells truncated to 1 px wide, the log-polar
  histogram's radius gate excluded every pixel, and the zero descriptor exact-matched the space
  glyph — every cell rendered blank (a 1000×1000 face filled 2493/2584 cells; the same face at
  750×1000 filled 0/3496). The cap is now derived from the width budget
  (`columns × oversample × height/width`) for portrait inputs; square and landscape outputs are
  byte-identical.
- **Rotated video orientation follow-up (ASTSK-38).** Fixed the vertical-flip bug that remained in the
  `v0.5.0` rotated/portrait decode path by applying `preferredTransform` through the Core Image/Core
  Graphics coordinate-space conversion and verifying decoded frames against
  `AVAssetImageGenerator(appliesPreferredTrackTransform: true)`.
- **Full-gate reliability (ASTSK-40).** `just check` now keeps the video deadlock sentinels in the
  comprehensive gate by running the complementary suite first, then the two load-sensitive video
  sentinels in an isolated shard.

### Documentation

- **Video/GIF DocC coverage.** Added a `Video` DocC article (`<doc:Video>`) and a "Video & GIF" Topics
  group to the catalog so the public streaming-video API — `convertVideo`/`convertGIF`, the
  decoder/encoder halves, and the frame/report types — is discoverable. Corrected the `architecture.md`
  `ShapeData` note to describe the `.bin` v1/v2/v3 format (v3 = structure channels, ASTSK-35), and added a
  quality/effects lever hint to the `AskiVideoLab` example in `AGENTS.md`.

## [0.5.0] — 2026-06-16

Pre-1.0 additive roll-up of every change merged to `main` between `v0.4.0` and `v0.5.0`. Default rendered
output is unchanged: every new color/shape capability ships as an opt-in knob or research SPI that is
off by default, and the PNG/snapshot baselines are byte-identical to `v0.4.0`.

### Added

- **HDR/EDR emissive render path (ASTSK-10).** New `@_spi(AskiResearch)` `ASCIIGrid.renderExtendedRangeImage(...)`
  renders an SDR base plus a linear-domain per-cell emission gain in a 16-bit half-float extended-linear
  context and authors a gain-map Adaptive HDR HEIC (system SDR fallback by delegation). The default render
  path is byte-identical; this is opt-in research surface.
- **Video pipeline.** Streaming MP4 → ASCII → MP4 loop (ASTSK-3); animated-GIF ingest and GIF export with
  per-frame delays and loop count, promoting `ASCIIGIFEncoder` and adding `ASCIIGIFDecoder` to the library
  (ASTSK-13); target-FPS resampling for both MP4 and GIF (ASTSK-19); one-shot `convertVideo`/`convertGIF`
  carriers.
- **Faithful aspect-ratio image rendering.** New `preserveSourceAspect` parameter on the image renderer
  reproduces the source image's aspect ratio (`glyphWidth * 2.2`). Default `false` keeps the historical
  2.0 glyph aspect — all existing PNG snapshot baselines are unchanged. `AskiDemo` defaults to the faithful
  ratio via `--preserve-aspect`.
- **Helmlab palette-matching policies (ASTSK-2).** `PaletteMatchingPolicy.helmlabEuclidean` and
  `.helmlabCompressed`, backed by a full Helmlab MetricSpace transform + inverse ported from Helmlab v21.
  Opt-in; the default remains `.oklabEuclidean`.
- **Per-cell shape residual.** The discarded 60D log-polar match distance is surfaced via a
  `convertWithResidual` SPI plus shape-structure channels on the descriptor.
- **Character-set `.bin` format updates.** `.bin` v2 adds a raw ink-density block exposed as
  `rawDensityValues` (ASTSK-28); `.bin` v3 adds shape-structure channels (ASTSK-35). Both stay
  backward-compatible with prior versions.
- **Default-off research knobs.** Ink-fraction color pre-compensation (ASTSK-29); `chromaShapeAssist`
  isoluminant rescue via mass-normalized chroma-gradient shape assist (ASTSK-30); `occupancyMatching`
  composited-tone glyph matching (ASTSK-7); `shapeStructureAssist` basis augmentation (ASTSK-35). Each
  defaults to off. `shapeStructureAssist` ships as a **documented negative result** and is not recommended
  for production use.

### Changed

- **All CLI tools migrated to swift-argument-parser (ASTSK-21/22).** `--help` and `--version` (build SHA)
  now work uniformly across every tool.
- **`AskiDemoSupport` renamed to `AskiToolSupport` (ASTSK-24).** Internal tool-support target; no library
  API change.

### Fixed

- **Video decode orientation (ASTSK-12).** Decoding now applies the source `preferredTransform`, so
  rotated/portrait sources are no longer mis-oriented.
- **DocC validation gate (ASTSK-25).** Repaired the warm-cache symbol-graph footgun: `validate-docc.sh`
  now regenerates the Aski symbol graph via `swift package dump-symbol-graph` on every run, ending the
  spurious "unresolved reference" failures on a warm `.build`.

### Documentation

- **Research infrastructure.** NASA isoluminant corpus validation (ASTSK-37); λ dose-response via a
  luma-vs-chroma competition ramp (ASTSK-36); regime-appropriate structure oracle re-settling the
  shape-residual verdict (ASTSK-31); Color-Theory Phase 0 composited-cell oracle gate + glyph
  shape-residual field; CAM16/HCT and Color.js gamut reference cross-checks (gamut-mapping doc-comments
  now cite the pinned Color.js reference port); research data/results-store conventions (ASTSK-11);
  generated repo-map source index + orientation docs; tooling/CI preflight hardening.
- **New research harnesses (`swift run` targets, not library API).** `AskiMotionLab`, `AskiVideoLab`,
  `AskiAccessLab`, `AskiDecolorLab`, and `AskiHDRLab`, plus new `AskiColorLab` subcommands.

## [0.4.0] — 2026-05-29

Pre-1.0 default-output release.

### Added

- **`GamutMappingPolicy.rayTrace`** — public gamut-mapping policy for CSS Ray Trace mapping into sRGB or Display P3. `.adaptiveL0` remains public for legacy comparison and A/B testing.

### Changed

- **Ray Trace gamut mapping is now the default.** `ASCIIConverter.gamutMapping` defaults to `.rayTrace` instead of `.adaptiveL0`. The change improves lightness and hue preservation on out-of-gamut OkLCh stress cases, while reducing chroma more aggressively on some boundary colors.
- **`gamut-sweep` now measures shipped Ray Trace behavior.** The lab `rayTrace` policy delegates to production wrappers, and `adaptiveL0` remains the CSV `baseline_policy` for this release.
- **Snapshot baselines regenerated where default-output bytes changed.** See the visual sign-off note for the exact snapshot scope.

### Documentation

- Release notes call out the ColorAide #400 yellow-desaturation caveat and the Color.js counter-signal so the release does not claim ecosystem consensus.
- **Research registry + front-matter discoverability (ASTSK-9).** Every `docs/Research/` note now carries YAML front-matter, a new `BuildResearchIndex` tool generates the README index and a machine-readable `docs/Research/index.json`, and `ResearchRegistryTests` enforces front-matter validity and index sync in `swift test`. No library or rendered-output change.

## [0.3.1] — 2026-05-27

Correctness release after `v0.3.0`.

### Changed

- **Linear-light sampling is now the default.** `ASCIIConverter.colorSampling` defaults to `.linearLightAverage` instead of `.encodedAverageLegacy`. This changes default rendered output for fixtures where encoded-space averaging previously darkened or skewed per-cell color. Callers that need `v0.3.0`-style encoded averaging can pass `colorSampling: .encodedAverageLegacy` explicitly.
- **Snapshot baselines regenerated for the new default.** The actual changed baseline scope was four image snapshots: one mixed-charset render, two circle-mask fallbacks, and one soft-edge mask fixture. Other regenerated snapshot candidates were byte-identical.

### Documentation

- **`PaletteMatchingPolicy.helmlabMetric` promotion paused.** Helmlab is a separate color space with a MetricSpace pipeline, not a one-line distance function on OKLab inputs. A fresh spec is required before any Helmlab implementation is promoted again.

## [0.3.0] — 2026-05-27

Additive color-pipeline release after `v0.2.0`. Defaults remain unchanged and no snapshots were regenerated.

### Added

- **`PaletteMatchingPolicy.oklabHyAB`** — experimental palette-matching policy using city-block lightness plus Euclidean chroma. The default remains `.oklabEuclidean`.
- **`RenderCompositionPolicy`** — public renderer composition policy with `.encodedDisplay8Bit` as the default and `.extendedLinearPerGamut` as an opt-in target-gamut linear-light composition path.
- **Palette matching DocC article** registered under the Aski documentation catalog.

### Fixed

- **Renderer composition propagation.** Animation frame materialization and the effects raster path now preserve `ASCIIGrid.composition` instead of falling back to encoded-display compositing.

### Documentation

- **`cbrtf` production switch reconciled as shipped.** The OKLab cube-root correction already landed before `v0.2.0`; this release updates the deferred-work review docs so the tracked color-pipeline queue matches repo reality.

## [0.2.0] — 2026-05-27

First tagged release after the initial `v0.1.0` (2026-04). Cumulative roll-up of every change merged to `main` between `v0.1.0` and `v0.2.0`.

### Added

- **A1 — Character-mode expansion.** New algorithms (`ASCIIAlgorithm.logPolar`, `.edgeMap`, `.dotMatrix`), seven new built-in character sets, Courier Prime factory, Braille rasterizer, edge-map + dot-matrix kernels, `RenderingOptions` API. The pre-A1 default-output golden is preserved.
- **A2 — Sample-grid aspect + render-time tile modes.** `ASCIITileShape` (sampling-only: `.square`, `.wide`, `.tall`) replaces the earlier `widthRatio` parameter; `.wide` reproduces the historical `widthRatio: 2.2` default bit-identically. Render-time `TileGrid` adds `TileCellShape` (`.square`, `.hex`, `.triangle`, `.diamond`, `.circle`) and `TileGridMode` (`.pixelArt`, `.brick`, `.mosaic(grout:, groutThickness:, cornerRadius:)`).
- **B Phase 1 — Stock effects + `EffectChain`.** Compose renders with backgrounds, lighting, and effect chains.
- **B Phase 2 — Metal effects, actor, async rendering.** Metal-backed effect execution behind an actor; async rendering APIs.
- **D — Raster mask input support.** Source images accept an optional mask raster to constrain conversion.
- **C1 — Algorithmic animation support.** Frame sequences from a single source.
- **Color Pipeline v2 Phase 1.** `PaletteContent` + `PaletteColor(_:colorSpace:)` API. Palette sources declare colors in sRGB or Display P3; Aski resolves into its internal matching space.
- **`AskiColorLab` research harness** with five lab commands: `sampling-ablation`, `palette-match-ablation`, `gamut-sweep`, `linear-composite-ab`, `cuberoot-accuracy`.
- **`ColorSamplingPolicy.linearLightAverage`** — additive opt-in for physically-correct linear-light averaging during per-cell color sampling. The default remains `.encodedAverageLegacy` in v0.2.0; the flip is deferred to a later release.
- **DocC Markdown sidecar emission in CI.** `Scripts/validate-docc.sh` emits per-symbol Markdown and a manifest JSON; CI uploads them as build artifacts. Surfaced at the GitHub Release level as downloadable assets (see § Migration for the manifest URL).
- **`DESIGN.md`** at repo root — algorithm overview + patent-lineage section.
- **`llms.txt`** at repo root — agent-discoverable pointer file pointing at the DocC Markdown manifest.

### Changed

- **Palette source API.** `colorsOKLAB` removed in favor of ``PaletteContent`` + ``PaletteColor(_:colorSpace:)`` with sRGB / Display P3 declared components. See the Color Pipeline v2 section of `Sources/Aski/Aski.docc/Migrating-to-A1.md` for the full migration.
- **OKLab conversion uses `cbrt` instead of `sign · pow(·, 1/3)`** in `linearSRGBToOKLAB` and `linearP3ToOKLAB`. Canonical round-trip tolerances unchanged. ANSI16 and Display P3 primaries pinned-OKLab regressions installed as silent-drift gates.
- **OKLab matrices `FUSED_LINEAR_SRGB_TO_LMS`, `FUSED_LINEAR_P3_TO_LMS`, `LMS_PRIME_TO_OKLAB`** lifted from `private` to module-internal access for tests and the lab harness.

### Removed

- **`ASCIIConverter.widthRatio`** — replaced by ``ASCIITileShape``. The old `widthRatio: 2.2` default maps to `.wide` (bit-identical).
- **Dead `sign(_:)` helper** in `ColorConversion.swift` — eliminated as part of the cbrt swap.

### Migration

For step-by-step migration from `v0.1.0`, see [`Sources/Aski/Aski.docc/Migrating-to-A1.md`](Sources/Aski/Aski.docc/Migrating-to-A1.md) — specifically the *Migrating from v0.1.0 → v0.2.0* section.

### Deferred (not in v0.2.0)

- `PaletteMatchingPolicy.oklabHyAB` (experimental HyAB metric)
- `PaletteMatchingPolicy.helmlabMetric` (experimental Helmlab metric)
- `RenderColorSpacePolicy.extendedLinear` (per-gamut working space)
- Linear-light sampling as the default (the flip)
- Ray Trace gamut policy as the default

## [0.1.0] — 2026-05-04

Initial release. The conversion pipeline with the original character-mode set, OKLab color pipeline v1, DocC catalog, shape-vector resource layer (`Resources/ShapeData/standard_vectors.bin`, Courier Prime font), and benchmark harness. (Tag commit: `4f61348`, *"Initial commit: Aski v0.1.0"*, tagged 2026-05-04.) The A1 character-mode expansion (algorithms, charsets, kernels) landed in `v0.2.0` and brought the Metal kernel resource layer (`Resources/Kernels/default.metallib`) with it; do not back-attribute either to v0.1.0.
