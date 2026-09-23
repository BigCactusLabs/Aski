# Architecture

Technical reference for the Aski Swift package — products, targets, pipeline, key files, testing setup, and dependencies. Load-bearing when changing the conversion pipeline or adding a supporting target.

## Products, targets, and layout

The package publishes the `Aski` library, the first-class `aski` executable, and historical lab replay products. The executable is a thin reference client over the library; supporting generator, importable lab, replay-runner, benchmark, and test targets are also declared in `Package.swift`. Note the non-default layout — supporting targets do not live under `Sources/`:

- `Sources/Aski/` — library
- `Tools/BuildStandardVectors/` — read-only Core Text drift audit and per-charset shape-vector generator
- `Tools/BuildKernelLibrary/` — stitchable Metal kernel library generator
- `Tools/BuildResearchIndex/` — research front-matter, corpus, and results index generator
- `Tools/BuildRepoMap/` — source-scanned top-level-declaration index generator (`docs/repo-map.generated.md`)
- `Tools/AskiCLI/`, `Tools/AskiCLIRunner/` — importable command composition and the async-correct `aski` executable entry point
- `Tools/AskiDemo/`, `Tools/AskiToolSupport/` — the historical demo executable plus shared CLI parsing, argument bounds, source-thumbnail loading, stable JSON, async command launch, and tool helpers
- `Tools/AskiTileMatrix/` — tile-grid render matrix harness
- `Tools/AskiColorLab/` — internal color-pipeline research harness (`sampling-ablation`, `palette-match-ablation`, `gamut-sweep`, `linear-composite-ab`, `cuberoot-accuracy`, `cam16-hct-reference`, `helmlab-reference`, `shape-residual-map`, `render-matcher-challenge`, `inter-cell-smoothing`, `lattice-support`, `lattice-phase`, `selection-ceiling`, `reference-recovery`, `convention-ablation`, `polarity-gate`, `target-width-gate`), plus the `Arbiter/` human-arbitrated perceptual instrument (`arbiter stimuli`/`judge`/`score`; protocol frozen in `docs/Research/2026-08-25-aski56-arbiter-protocol.md`). ASKI-68 removed closed experiment-specific runners; their frozen notes, result artifacts, and Git commits remain the replay record. The ASKI-69 matcher challenge remains a fixed one-shot instrument, not a product option.
- `Tools/AskiMotionLab/` — animation frame materialization, motion presets, GIF export (via the library `ASCIIGIFEncoder`), and flicker metrics, and the temporal-coherence research gates (`temporal-prior`, `source-tether`)
- `Tools/AskiVideoLab/` — MP4 or animated-GIF decode -> ASCII -> re-encode throughput and memory harness, with per-frame quality levers, a time-modulated `--pattern` overlay, and opt-in cosmetic post-render effects (`--bloom`/`--scanlines`/`--vignette`, time-invariant, applied via the `renderImage(…, effects:)` overload)
- `Tools/AskiAccessLab/` — palette and rendered-grid CVD distinguishability audit harness
- `Tools/AskiDecolorLab/` — composited-cell perceptual oracle (`evaluate`, `check`)
- `Tools/AskiHDRLab/` — HDR/EDR emissive-spike artifact writer and fail-fast gate (`evaluate`, `check`)
- `Tools/AskiPresetLab/` — Vesper lab: the charset × columns A/B that froze the built-in preset (`ab`), plus ASKI-73's lab-local `probe-stimuli`/`probe-score` instrument. The product probe writes a public blinded three-arm set and a separately located private key, binds the schema-v2 pair and every referenced media file with SHA-256, reuses the existing center reveal, validates private response CSVs, and emits aggregate gates only. Its frozen protocol is `docs/Research/2026-09-04-aski73-vesper-product-probe-rule.md`; its source, generated-pair, and score schemas are under `docs/assets/schemas/`
- `Tools/Aski*LabRunner/` — one-file historical replay entry points; all implementation and command definitions stay in the corresponding importable `Tools/Aski*Lab/` module
- `Benchmarks/AskiBenchmarks/` — `package-benchmark` target
- `Tests/AskiTests/` — Swift Testing suite

## Command-line product

Aski has two product layers with one rendering engine:

1. the `Aski` Swift library, which owns conversion, grids, rendering, masking,
   animation, video, and effects; and
2. the `aski` executable, a reference client for repeatable file-based workflows and the canonical owner of the research command tree.

The command is intentionally thin. It composes public library behavior, owns
filesystem and serialization concerns, and does not introduce a second image
pipeline.

`render` is both explicit and the default subcommand:

```bash
swift run aski render input.jpg --columns 80
swift run aski input.jpg --columns 80
swift run aski render input.jpg --output output.txt --render-png output.png
swift run aski render photo.jpg --render-png dissolve.png --mask mask.png --mask-fallback original --mask-ground "#080808"
swift run aski render input.jpg --write-manifest render.json
```

The render surface matches the historical `AskiDemo` workflow: `--columns`,
`--output`, `--render-png`, `--width`, `--font-size`, `--charset`,
`--background`, and `--[no-]preserve-aspect`, plus `--mask`,
fallback/color/sizing, ground, hard-edge, and inversion options. `--width` sets
the exact output pixel width for `--render-png`: the render scale is derived
from that width and the grid, so the pixel size no longer depends on
`--font-size`. It requires `--render-png` and is bound by
`ASCIIGrid.maxTargetPixelWidth`. The CLI never writes the library's 1x1 fallback:
an out-of-range width is refused up front as a validation error (exit 64), and a
width whose derived height exceeds the ceiling is caught after the render and
refused as a runtime error (exit 70). A mask alone can constrain plain-text output;
raster-only fallback and ground choices require `--render-png`. `--write-manifest`
is available only on `render`. `AskiDemoCommand` and its executable target remain
available for historical callers. The published product and root command are both
named `aski`; `AskiCLIRunner` owns only the async process entry point.

`inspect` resolves the same ImageIO thumbnail, converter, grid, and plain-text
render without writing render artifacts:

```bash
swift run aski inspect input.jpg --columns 80
swift run aski inspect input.jpg --format json --output inspection.json
```

Human text is the default. JSON is opt-in and byte-deterministic for the same
checkout, invocation, and input: keys are sorted, slashes are unescaped, and the
file ends with one newline. Version 1 records the tool SHA, source path as
supplied, normalized input pixel dimensions, resolved grid dimensions, charset,
total/non-whitespace cell counts, and plain-text UTF-8 bytes. Its Draft 2020-12
schema is [`assets/schemas/aski-inspect-v1.schema.json`](assets/schemas/aski-inspect-v1.schema.json).
Readers must ignore additive fields; removing, renaming, or changing the meaning
of a field requires a new `schemaVersion`.

`render --write-manifest <path>` writes an unsigned deterministic render record
from the same in-memory thumbnail, grid, text, and optional rendered PNG. Version
1 records the tool SHA, command, source path and normalized dimensions, resolved
grid and charset, render settings, text/PNG artifact metadata, and an additive
optional resolved-mask block when `--mask` is supplied. When `--width` is used,
the render block additionally carries the additive `targetPixelWidth`,
`derivedScale`, `cellAdvancePixels`, and `resampleSpace` fields
(`linear-srgb-area-average-4x` for the shipped supersample arm). It does not
establish source or output authenticity. Its Draft 2020-12 schema is
[`assets/schemas/aski-render-manifest-v1.schema.json`](assets/schemas/aski-render-manifest-v1.schema.json).
It follows the same additive compatibility rule.

Research commands are grouped under one canonical namespace:

```bash
swift run aski lab color --help
swift run aski lab motion --help
swift run aski lab video --help
swift run aski lab accessibility --help
swift run aski lab decolor --help
swift run aski lab hdr --help
swift run aski lab preset --help
```

The seven lab implementations are regular importable targets. The historical
`AskiColorLab`, `AskiMotionLab`, `AskiVideoLab`, `AskiAccessLab`, `AskiDecolorLab`,
`AskiHDRLab`, and `AskiPresetLab` executable products contain no command logic:
each delegates to the same command type through a one-file runner. Surviving
commands therefore have identical help, usage, and exit behavior on both paths;
removed experiments remain in Git history, with their invocations captured by
the dated notes and artifacts.
New workflows use `aski lab …`. ArgumentParser generates Bash, Zsh,
and Fish completion scripts from the complete canonical tree with
`aski --generate-completion-script <shell>`.

Future commands may make the engine easier to automate and reproduce. They must
reuse the same decoded thumbnail, conversion, grid, and render paths; filesystem
or serialization concerns stay in `AskiToolSupport`, not the library. Human
output may evolve for clarity. Timestamps, hostnames, absolute environment paths,
and network-derived values stay out of deterministic records unless a future
format explicitly makes them part of its contract.

## Pipeline (CGImage → ASCIIGrid)

1. ImageIO thumbnail decoding (`ImageIOThumbnail.swift`)
2. OKLAB color conversion with fused matrix transforms (`ColorConversion.swift`)
3. 60D log-polar shape-context character matching (`ShapeMatching.swift`, with kernels in `Sources/Aski/Algorithms/`)
4. Ray Trace gamut mapping for display output (`GamutMapping.swift`; `.adaptiveL0` remains available for legacy comparison)
5. Renderers produce plain text, AttributedString, or CGImage (`Sources/Aski/Renderers/`)

**Sampling lattice (between steps 1 and 3).** `prepareConversion` takes a floored integer
cell pitch (`thumbnail.width / cols`, `thumbnail.height / rows`) — uniform across the grid —
and then draws the decoded thumbnail into a lattice raster of exactly
`cols * cellWidth × rows * cellHeight` (`samplingLattice`, `CellSampling.swift`). Every
sampler indexes from the origin and walks whole cells, so the lattice is tiled exactly and no
source row or column goes unread; the fold costs a rescale of at most one cell pitch per axis.
Earlier versions sampled the thumbnail at its decoded size and dropped the bottom/right
remainder — up to 10% of image height — which stretched the render downward against the
full-aspect grid (ASKI-65, issue #36). The lattice contract is pinned by
`SamplingLatticeContractTests` and mirrored in the AskiColorLab `SampledSource` accessor. A
footprint with a one-pixel axis (reachable at `oversample: 1`) carries no
log-polar support at all, so `logPolar` detects it from the pitch alone and falls back to a
tone-only pick instead of collapsing to the space glyph (ASKI-25).

**Exact target-width render (step 5).** The public `ASCIIGrid.renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:)`
renders to an exact output pixel width instead of a font-size-derived scale. It
draws the grid at 4x the requested width and area-averages back down in linear light
(`ImageRenderer.swift`), which the ASKI-63 gate selected over direct rendering (SHIP-B, run 2;
verdict `docs/Research/2026-09-01-aski63-target-width-verdict.md`, rule
`docs/Research/2026-09-01-aski63-target-width-rule.md`). Because the supersampled bitmap must
itself fit the renderer's pixel-extent ceiling, `ASCIIGrid.maxTargetPixelWidth` is a quarter of
that ceiling; a wider request, or a grid whose derived height exceeds the same bound, returns
the 1x1 fallback image as the scale renderer does. The direct arm stays reachable through the
`@_spi(AskiResearch)` `TargetWidthResample` overload for research comparison only.

When `MaskOptions` is supplied, mask sampling supplies per-cell coverage that the
render/compositing stage (`Sources/Aski/Effects/`, `Sources/Aski/Masking/`) uses to gate
what's shown (fallback modes, soft edges) — conversion itself runs unconditionally per
cell; time-based animation synthesis
(`Sources/Aski/Animation/`, `ASCIIConverter+Animation.swift`) ranks per-cell character
candidates in a single conversion pass, then synthesizes each frame's grid by selecting
among those candidates on a schedule — not by rerunning the pipeline per frame, and
without adding pipeline stages.

**Per-cell parallelism (step 3).** The `logPolar` per-cell walk runs row-parallel through
`GridRowWalk` (`DispatchQueue.concurrentPerform`) once the grid is at or above
`GridRowWalk.parallelCellThreshold` (1200 cells); smaller grids stay serial, where the dispatch overhead
would outweigh the work. Each row writes into pre-sized storage at proven-disjoint indices, so the output
is **byte-identical** to the serial walk (a serial↔parallel parity suite and a frozen pre-change golden
enforce this). `dotMatrix` always walks serially — its Floyd–Steinberg error diffusion is
cell-order-dependent. Ordinary, ranked, and residual conversion dispatch once by algorithm into the same
generic row-walk engine; concrete captures keep ranked and residual buffers out of the plain path and avoid
an existential call or algorithm switch inside the cell loop. Temporal conversion remains separate. This
is the only parallelism in the conversion pipeline: video and animation
parallelize *within* each frame's cell walk, never by fanning out across frames. The measured crossover
threshold, the ~18–40% default-convert speedup, and the three adjacent micro-optimizations that were
measured and **rejected** — existential→generic kernel dispatch (dispatch cost negligible), per-cell scratch
reuse (`inout`-threading overhead exceeded the allocation saving), and a per-conversion log-polar bin table
(within measurement noise) — were recorded in the private development archive (ASTSK-51). The
common thread: the 60-D log-polar descriptor compute dominates per-cell cost, so only spreading it across
cores paid off. ASKI-72 later adopted static dispatch only as part of a 62-line maintenance consolidation;
its [pre/post measurements](Research/2026-09-04-aski72-converter-engine-consolidation.md) show neutral-or-better
cost and do not make a descriptor-speed claim.

**Video pipeline overlap.** `ASCIIVideoDecoder.grids(...)` retains its original
one-pull/one-decode semantics. The sibling `pipelinedGrids(...)` sequence owns one
ordered prefetch task, and `convertVideo(...)` opts into it so decode + per-cell
conversion of frame N+1 can overlap rendering + encoding of frame N. The consumer
owns the current frame and the producer can hold one next frame: two frames in
flight, regardless of clip length. There is still no inter-frame conversion
fan-out. Exact PTS order, cancellation/failure propagation, early termination,
and rotated-grid parity are test-enforced. The stage profile, resident-memory
measurements, and rejected GIF metadata/orientation candidates were recorded in
the private development archive (ASTSK-52).

CLI image tools that start from file paths (`aski`/the `AskiDemo` target,
`AskiTileMatrix`, and `aski lab motion --image`) use the shared tool-support target
to decode a conversion-sized thumbnail from the source `CGImageSource` before
handing the image to the converter, avoiding full-raster materialization for
oversized inputs. `aski render` and `aski inspect` share one `ToolImageConversion`
snapshot so metadata describes the exact in-memory grid and text being rendered.
Direct library callers still pass a `CGImage` and the converter performs its own
ImageIO thumbnail step.

## Key files

- `Sources/Aski/ASCIIConverter.swift` — main converter struct + `DefaultConverter` typealias
- `Sources/Aski/ConversionEngine.swift` — shared statically specialized ordinary-conversion row walk and concrete output captures
- `Sources/Aski/ASCIIGrid.swift` — output grid type
- `Sources/Aski/Algorithms/` — pipeline kernels: `LogPolarKernel`, `DotMatrixKernel`, `ShapeContext`
- `Sources/Aski/CharacterSets/GlyphBank.swift` — immutable validated internal reference owner of the four per-glyph arrays, shared by library-owned character sets and their converters. Built-ins reuse committed v1/v2/v3 bytes and record only the asset tag and format version; runtime Core Text sets record observed font and raster conventions; external conformers are snapshotted when a converter initializes or its `characterSet` is assigned.
- `Sources/Aski/CharacterSets/StandardCharacterSet.swift`, `Sources/Aski/CharacterSets/StandardCharacterSet+Builtins.swift` — public projections over built-in character sets backed by `Resources/ShapeData/*.bin` (format v1/v2/v3: v1 = normalized brightness + 60D lanes; v2 adds absolute raw density; v3 carries a retired structure-channel block that the parser validates and skips. `Tools/BuildStandardVectors/LegacyShapeChannels.swift` preserves byte-stable regeneration without carrying the killed experiment in the library target. Older versions still load; audited without resource writes by `just audit-vectors --output-dir <dir>` and rebuilt only under the ASKI-51 policy by `just regen-vectors`), plus `CharacterSets/Braille/` rasterizer
- `Sources/Aski/CharacterSets/RasterizedCharacterSet.swift` — runtime-built character sets projected from the same immutable bank
- `Sources/Aski/Tiles/` — tile-grid conversion and rendering
- `Sources/Aski/Effects/` — Core Image composition/effects, render engine, and stitchable Metal kernel integration
- `Sources/Aski/Masking/` — raster mask sampling, fallback modes, soft edges
- `Sources/Aski/Animation/` — time-based ASCII frame synthesis (`ASCIIConverter+Animation.swift` at root is its entry point)
- `Sources/Aski/Video/` — streaming MP4 and animated-GIF decode, ASCII frame conversion, and MP4/GIF encode support (`ASCIIGIFDecoder`/`ASCIIGIFEncoder`/`convertGIF` for the GIF round-trip)
- `Sources/Aski/Resources/Fonts/` — bundled Courier Prime Regular (OFL)
- `Sources/Aski/Resources/Kernels/` — compiled Metal libraries (rebuilt by `just regen-kernels`)
- `Sources/Aski/Aski.docc/` — DocC catalog
- `docs/Research/` — algorithm-level deep dives (OKLAB color science, shape-context oversampling, frontier scans); load-bearing context when changing the matching pipeline

## Testing notes

- Tests live in `Tests/AskiTests/`; uses Swift Testing (not XCTest)
- Snapshot tests live under `Tests/AskiTests/__Snapshots__/` (excluded from package build)
- Property-based tests use `swift-property-based`
- Benchmark target runs against `package-benchmark`
- Root verification commands live in `justfile`; run `just --list` for the canonical build/test/docs/research/benchmark/release surface.

## Dependencies

- `swift-property-based` — test-only
- `swift-snapshot-testing` — test-only
- `swift-numerics` — test-only
- `package-benchmark` — benchmarks-only
- `swift-argument-parser` — executable and research-tool targets only
- The `Aski` library has no third-party runtime dependencies
- Library runtime imports are Apple system modules only: Foundation, CoreGraphics, CoreImage, CoreText, ImageIO, UniformTypeIdentifiers, Metal, os, simd, and platform text/color modules (`UIKit` where available, otherwise `AppKit`)
