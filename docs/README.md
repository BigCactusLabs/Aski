# Aski documentation

Pick a trail: make a render, build an integration, or open the engine. This is the
navigation hub; the [project README](../README.md) is the front door.

## Use Aski

| You want to… | Start here |
| --- | --- |
| Try the package on a bundled image | [README: Try it](../README.md#try-it) |
| Convert files, export PNGs, use masks, or inspect JSON | [Command-line guide](../Sources/Aski/Aski.docc/CommandLine.md) |
| Add the library and make a first conversion | [Installation](../README.md#use-in-swift), [Getting Started](../Sources/Aski/Aski.docc/GettingStarted.md) |
| Choose text, attributed text, or raster output | [Rendering](../Sources/Aski/Aski.docc/Rendering.md) |
| Change the alphabet, matcher, or palette | [Character Sets](../Sources/Aski/Aski.docc/CharacterSets.md), [Algorithms](../Sources/Aski/Aski.docc/Algorithms.md), [Palette Matching](../Sources/Aski/Aski.docc/PaletteMatching.md) |
| Make cutouts and photo-to-type dissolves | [Masking](../Sources/Aski/Aski.docc/Masking.md) |
| Add motion, video, or finishing effects | [Animation](../Sources/Aski/Aski.docc/Animation.md), [Video & GIF](../Sources/Aski/Aski.docc/Video.md), [Effects](../Sources/Aski/Aski.docc/Effects.md) |
| Use tiles or a fixed duotone recipe | [Tile grids](../Sources/Aski/Aski.docc/Tiles.md), [Vesper](../Sources/Aski/Aski.docc/Vesper.md) |
| Upgrade an existing integration | [Migration notes](../Sources/Aski/Aski.docc/Migrating-to-A1.md), [CHANGELOG](../CHANGELOG.md), [checked-in release notes](release-notes/) |

The [DocC catalog](../Sources/Aski/Aski.docc/Aski.md) is the API documentation source.
On GitHub, its symbol links appear in source form; `just docc` validates the resolved
catalog locally. `./Scripts/validate-docc.sh --emit-markdown` additionally emits optional
Markdown sidecars and a manifest in a unique, retained directory printed by the script.
For packaging, pass `--output-dir` with a new directory; see the
[output-path migration](../CONTRIBUTING.md#pull-requests-and-releases). Release notes
describe intended assets; do not assume a hosted API site.

## Understand or contribute

| You want to know… | Read |
| --- | --- |
| Setup, local gates, snapshot baseline, and PR expectations | [CONTRIBUTING.md](../CONTRIBUTING.md) |
| Agent conventions and hard engineering rules | [AGENTS.md](../AGENTS.md) |
| Products, targets, conversion pipeline, and dependencies | [architecture.md](architecture.md) |
| CLI automation contracts and compatibility | [Command-line architecture](architecture.md#command-line-product), [JSON schemas](assets/schemas/) |
| Descriptor lineage and its limitations | [DESIGN.md](../DESIGN.md) |
| Research findings, decisions, and retractions | [Research index](Research/README.md) |
| Cross-cutting discoveries awaiting triage | [Discoveries.md](Research/Discoveries.md) |
| Research protocol and task-management workflow | [Research methodology](agents/research-methodology.md), [Backlog guide](agents/backlog.md) |
| Subsystem roles or the full symbol/file index | [Repo map](../AGENTS.md#repo-map), [generated source map](repo-map.generated.md) |
| Historical color-theory planning—not the current work queue | [research-plan.md](research-plan.md) |
| Machine-readable navigation | [llms.txt](../llms.txt) |

Pre-1.0 APIs and rendered output may change. Public library features, experimental
policies, research SPI, and lab commands have different readiness levels. In particular,
[HDR/emissive rendering](../Sources/Aski/Aski.docc/HDRRendering.md) is research-only.
Older SHAs, issue numbers, and tags in retained notes refer to private development;
the public release history starts at v0.7.0.

## Tool inventory

Run commands from the repository root with the selected Xcode toolchain. `aski render`
and `aski inspect` are the ordinary still-image workflow; `aski lab` contains research
harnesses. Supporting implementations live under `Tools/`, not `Sources/`.

| Tool | Purpose | Canonical run |
| --- | --- | --- |
| `aski` | Image rendering, human/JSON inspection, and lab discovery | `xcrun swift run aski render <image>` · `xcrun swift run aski inspect <image> --format json` · `xcrun swift run aski lab --help` |
| `AskiTileMatrix` | Tile-grid render matrix | `xcrun swift run AskiTileMatrix <image> <out> --columns 64` |
| `aski lab color` | Color/matcher research, including the fixed ASKI-69 challenge and human-arbitrated [arbiter v2](Research/2026-09-04-aski62-arbiter-v2-protocol.md) | `xcrun swift run aski lab color <subcommand> --output-dir <dir>` · `xcrun swift run -c release aski lab color render-matcher-challenge --output-dir <dir>` |
| `aski lab motion` | Animation frames, motion presets, GIF export, and temporal-coherence gates | `xcrun swift run aski lab motion --help` |
| `aski lab video` | MP4/GIF conversion harness and time-invariant cosmetic effects | `xcrun swift run aski lab video --input <clip> --output-dir <dir>` |
| `aski lab accessibility` | Palette/grid color-vision-deficiency audit | `xcrun swift run aski lab accessibility audit --output-dir <dir>` |
| `aski lab decolor` | Composited-cell perceptual oracle; `check` fails on a KILL verdict | `xcrun swift run aski lab decolor check --output-dir <dir>` |
| `aski lab hdr` | Research-only HDR artifacts and fail-fast gates | `xcrun swift run aski lab hdr check --output-dir <dir>` |
| `aski lab preset` | Vesper A/B and blinded product-probe instruments | `xcrun swift run aski lab preset --help` |
| `BuildKernelLibrary` | Regenerate the checked-in Metal library | `just regen-kernels` |
| `BuildStandardVectors` | Audit or regenerate charset shape vectors | `just audit-vectors --output-dir <dir>` · `just regen-vectors` |
| `BuildResearchIndex` | Validate research/lifecycle records or regenerate their index | `just research-check` · `xcrun swift run BuildResearchIndex` |
| `BuildRepoMap` | Validate or regenerate the source map | `just repo-map-check` · `just regen-repo-map` |
| `AskiBenchmarks` | Performance suite; budgets live in `Benchmarks/AskiBenchmarks/` | `just bench` |

Historical `Aski*Lab` executables are compatibility entry points for surviving commands;
new workflows use `aski lab …`. Removed experiments are not promised as runnable commands
in the current checkout. Their notes and retained artifacts document what can be replayed.

`just --list` is the canonical build/test/docs/release task inventory. `make <target>`
forwards to `just` and still requires it. Gates are local; this repository has no hosted
CI workflow. `just test-infra` separately exercises the shell infrastructure with fake
Apple tools and Python 3's standard library, without a Swift build. See
[verification](../CONTRIBUTING.md#verification) before submitting a PR.
