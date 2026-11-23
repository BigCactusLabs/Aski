# Navigate the repository

Start with [AGENTS.md](../../AGENTS.md) for rules. This page maps a requested change
to source, tests, and docs; [architecture](../architecture.md) explains how those
parts work together. Follow one route before searching the full research archive.

## Find the owner of a change

Paths are relative to this checkout. Tests below are starting points, not an
exhaustive acceptance set; select the full required checks in
[validation](validation.md).

| Change or question | Start in source | Nearby tests | User or design contract |
| --- | --- | --- | --- |
| CLI commands, options, or JSON discovery | [AskiCommand](../../Tools/AskiCLI/AskiCommand.swift), [SharedOptions](../../Tools/AskiToolSupport/SharedOptions.swift), [metadata](../../Tools/AskiCLI/AskiMetadataCommand.swift) | [CommandSurfaceTests](../../Tests/AskiTests/CommandSurfaceTests.swift), [AskiMetadataCommandSurfaceTests](../../Tests/AskiTests/AskiMetadataCommandSurfaceTests.swift) | [CLI guide](../../Sources/Aski/Aski.docc/CommandLine.md), [JSON schemas](../assets/schemas/) |
| Input loading, render output, or inspect records | [AskiDemoCommand](../../Tools/AskiToolSupport/AskiDemoCommand.swift), [AskiInspectCommand](../../Tools/AskiToolSupport/AskiInspectCommand.swift), [ImageIOThumbnail](../../Sources/Aski/ImageIOThumbnail.swift) | [ConversionThumbnailLoaderTests](../../Tests/AskiTests/ConversionThumbnailLoaderTests.swift), [AskiInspectCommandTests](../../Tests/AskiTests/AskiInspectCommandTests.swift), [AskiRenderManifestTests](../../Tests/AskiTests/AskiRenderManifestTests.swift) | [CLI guide](../../Sources/Aski/Aski.docc/CommandLine.md) |
| Conversion, sampling, or geometry | [ASCIIConverter](../../Sources/Aski/ASCIIConverter.swift), [CellSampling](../../Sources/Aski/CellSampling.swift), [ConversionEngine](../../Sources/Aski/ConversionEngine.swift) | [ConverterEngineGoldenTests](../../Tests/AskiTests/ConverterEngineGoldenTests.swift), [CellSamplingRefactorTests](../../Tests/AskiTests/CellSamplingRefactorTests.swift) | [Architecture](../architecture.md), [Algorithms](../../Sources/Aski/Aski.docc/Algorithms.md) |
| Glyph matching or brightness shortlist | [ShapeMatching](../../Sources/Aski/ShapeMatching.swift), [ShapeContext](../../Sources/Aski/Algorithms/ShapeContext.swift), [LogPolarKernel](../../Sources/Aski/Algorithms/LogPolarKernel.swift) | [BrightnessPoolContractTests](../../Tests/AskiTests/BrightnessPoolContractTests.swift), [ShapeContextFootprintTests](../../Tests/AskiTests/ShapeContextFootprintTests.swift) | [DESIGN](../../DESIGN.md), [research decisions](research.md) |
| Character sets or cached glyph data | [ASCIICharacterSet](../../Sources/Aski/ASCIICharacterSet.swift), [GlyphBank](../../Sources/Aski/CharacterSets/GlyphBank.swift), [RasterizedCharacterSet](../../Sources/Aski/CharacterSets/RasterizedCharacterSet.swift) | [ASCIICharacterSetBoundaryTests](../../Tests/AskiTests/ASCIICharacterSetBoundaryTests.swift), [GlyphBankTests](../../Tests/AskiTests/GlyphBankTests.swift) | [Character Sets](../../Sources/Aski/Aski.docc/CharacterSets.md) |
| Palette, color conversion, or gamut | [ColorConversion](../../Sources/Aski/ColorConversion.swift), [ResolvedPalette](../../Sources/Aski/ResolvedPalette.swift), [GamutMapping](../../Sources/Aski/GamutMapping.swift) | [ColorConversionTests](../../Tests/AskiTests/ColorConversionTests.swift), [ResolvedPaletteTests](../../Tests/AskiTests/ResolvedPaletteTests.swift), [RenderColorSemanticsTests](../../Tests/AskiTests/RenderColorSemanticsTests.swift) | [Palette Matching](../../Sources/Aski/Aski.docc/PaletteMatching.md), [Rendering](../../Sources/Aski/Aski.docc/Rendering.md) |
| Plain text, attributed text, PNG, or aspect | [Renderers](../../Sources/Aski/Renderers/), [GridDisplayProtocol](../../Sources/Aski/GridDisplayProtocol.swift) | [ImageRendererTargetWidthTests](../../Tests/AskiTests/ImageRendererTargetWidthTests.swift), [ImageRendererAspectTests](../../Tests/AskiTests/ImageRendererAspectTests.swift), [PlainTextRendererTests](../../Tests/AskiTests/PlainTextRendererTests.swift) | [Rendering](../../Sources/Aski/Aski.docc/Rendering.md) |
| Masks, grounds, fallback images, or soft edges | [Masking](../../Sources/Aski/Masking/), [ImageRenderer](../../Sources/Aski/Renderers/ImageRenderer.swift) | [MaskSamplerTests](../../Tests/AskiTests/MaskSamplerTests.swift), [MaskColorContractTests](../../Tests/AskiTests/MaskColorContractTests.swift), [MaskSnapshotTests](../../Tests/AskiTests/MaskSnapshotTests.swift) | [Masking](../../Sources/Aski/Aski.docc/Masking.md) |
| Effects, lighting, Metal, or composition | [Effects](../../Sources/Aski/Effects/), [AskiRenderEngine](../../Sources/Aski/Effects/AskiRenderEngine.swift), [effect internals](../../Sources/Aski/Effects/Internal/) | [CompositionTests](../../Tests/AskiTests/CompositionTests.swift), [EffectKernelSnapshotTests](../../Tests/AskiTests/EffectKernelTests.swift), [RenderCompositionPolicyTests](../../Tests/AskiTests/RenderCompositionPolicyTests.swift) | [Effects](../../Sources/Aski/Aski.docc/Effects.md) |
| Animation, cycling, or ongoing patterns | [ASCIIConverter+Animation](../../Sources/Aski/ASCIIConverter+Animation.swift), [Animation](../../Sources/Aski/Animation/) | [AnimationDeterminismTests](../../Tests/AskiTests/AnimationDeterminismTests.swift), [ASCIIGridPatternOverlayTests](../../Tests/AskiTests/ASCIIGridPatternOverlayTests.swift) | [Animation](../../Sources/Aski/Aski.docc/Animation.md) |
| MP4/GIF decode, resampling, selection, or encode | [Video](../../Sources/Aski/Video/), [VideoFrameSelectionPump](../../Sources/Aski/Video/VideoFrameSelectionPump.swift) | [VideoFrameSelectionContractTests](../../Tests/AskiTests/VideoFrameSelectionContractTests.swift), [VideoPipelineTests](../../Tests/AskiTests/VideoPipelineTests.swift), [AskiGIFEncoderTests](../../Tests/AskiTests/AskiGIFEncoderTests.swift) | [Video and GIF](../../Sources/Aski/Aski.docc/Video.md), [media validation](validation.md) |
| Tile, brick, or mosaic conversion/rendering | [Tiles](../../Sources/Aski/Tiles/), [TileGridConverter](../../Sources/Aski/Tiles/TileGridConverter.swift) | [TileGridRenderingTests](../../Tests/AskiTests/TileGridRenderingTests.swift), [TileGridConverter+MaskTests](../../Tests/AskiTests/TileGridConverter+MaskTests.swift) | [Tiles](../../Sources/Aski/Aski.docc/Tiles.md) |
| Build gates, packaging, or docs infrastructure | [justfile](../../justfile), [Scripts](../../Scripts/), [Package.swift](../../Package.swift) | [Script tests](../../Scripts/tests/), [DocumentationLinkTests](../../Tests/AskiTests/DocumentationLinkTests.swift), [RepoMapRegistryTests](../../Tests/AskiTests/RepoMapRegistryTests.swift) | [Validation](validation.md), [distribution](../guides/distribution.md) |
| Benchmark evidence, research runners, or a proposed optimization | [AskiBenchmarks](../../Benchmarks/AskiBenchmarks/), [research scripts](../../Scripts/research/), [lab inventory](tooling.md) | [Benchmark validator tests](../../Scripts/tests/test_benchmark_validation.py), [comparison tests](../../Scripts/tests/test_benchmark_comparison.py) | [Research navigation](research.md), [benchmark validation](../benchmark-validation.md) |

## Repository layout

| Location | What belongs here |
| --- | --- |
| [Sources/Aski](../../Sources/Aski/) | Shipping library. The root holds entry points, shared types, sampling, and color code; subsystem directories own specialized behavior. |
| [Sources/Aski/Aski.docc](../../Sources/Aski/Aski.docc/) | Public API articles and DocC symbol links. |
| [Tools](../../Tools/) | CLI, shared tool support, labs, generators, and small compatibility runners. Paths are explicitly set in `Package.swift`. |
| [Tests/AskiTests](../../Tests/AskiTests/) | Library, tool, snapshot, contract, and registry tests in one SwiftPM test target. |
| [Benchmarks/AskiBenchmarks](../../Benchmarks/AskiBenchmarks/) | Registered workloads and performance budgets. |
| [Scripts](../../Scripts/) | Local checks, benchmark validation, packaging, and retained replay instruments. |
| [Vendor](../../Vendor/) | Reviewed vendored dependency sources; follow benchmark provenance rules before changing them. |
| [backlog](../../backlog/) | Branch-local task records. Query/edit through the [backlog workflow](backlog.md). |
| [docs](../README.md) | Maintained guides plus research evidence and release history, with different update rules. |

The [generated source map](../repo-map.generated.md) covers **top-level declarations
under `Sources/Aski/` only**. It omits nested members, tools, tests, and scripts. Use
it to locate a type, then read its implementation and callers; use the table above
for cross-cutting work.

## Search a small surface first

Run these from the repository root. The examples are read-only and work without Xcode:

```bash
# Locate files before searching their entire contents.
rg --files Sources/Aski Tools Tests/AskiTests | rg 'Mask|Composition'

# Trace a symbol through its implementation and tests.
rg -n 'VideoFrameSelectionPump|selectedGrids' Sources/Aski Tools Tests/AskiTests

# Find the command declaration and its public contract.
rg -n 'commandName:|defaultSubcommand:|subcommands:' Tools/AskiCLI Tools/AskiToolSupport

# Find evidence for a task without reading every artifact.
rg -n 'ASKI-94' docs/agents docs/Research/README.md docs/Research/index.json

# View actual changes and scope before selecting checks.
git diff --stat
git diff --name-only
```

Avoid starting a code investigation with an unrestricted search of `docs/Research/`
or `Scripts/research/`: retained results and historical sources can overwhelm current
implementations. Search them when investigating a decision or replaying a study.

## Which source answers which question?

| Question | Authority |
| --- | --- |
| Does this type, option, or behavior exist now? | Current source and its tests; `Package.swift` for products/platforms/dependencies. |
| Which command/check should I run? | `justfile`, the implementing script, and current CLI `--help` / `aski metadata`. |
| Which task is open or complete? | Checked-in `backlog/tasks/` on this branch, viewed with `backlog … --plain`. |
| Why was an experiment adopted or rejected? | The dated protocol, result artifacts, and recorded decision linked from [research navigation](research.md). |
| What changed in a released version? | [CHANGELOG](../../CHANGELOG.md) and the matching [release notes](../release-notes/); `main` can be ahead of a tag. |
| Where should a documentation change go? | [Docs ownership](../README.md#maintaining-documentation). |

A historical plan is not an implementation map. A closed performance task may mean
its candidate was rejected. A surviving probe or parity test does not mean that its
candidate is a shipping option. Check the decision before proposing the same work.
