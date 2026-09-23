# Aski docs — discovery hub

Single entry point for finding the right document or tool in one hop. For the codebase
layout itself (subsystem roles, root-file groupings), see the **Repo map** in
[../AGENTS.md](../AGENTS.md); for a full top-level-declaration index, see
[repo-map.generated.md](repo-map.generated.md).

This is the public documentation hub. Use it to find product, research, and contributor guidance.

## Know X → read Y

| You want to know… | Read |
| --- | --- |
| Architecture, pipeline stages, key files | [architecture.md](architecture.md) |
| Command-line product, compatibility, and automation boundary | [architecture.md#command-line-product](architecture.md#command-line-product) |
| Machine-readable CLI schemas, including additive render-mask manifest state | [assets/schemas/](assets/schemas/) |
| Algorithm research (OKLAB, shape-context, frontier scans) | [Research/README.md](Research/README.md) |
| Cross-cutting discoveries queued for triage | [Research/Discoveries.md](Research/Discoveries.md) |
| Code layout — subsystems & root files | [../AGENTS.md](../AGENTS.md) (Repo map) |
| Full symbol/file index (generated) | [repo-map.generated.md](repo-map.generated.md) |
| The historical color-theory plan (evidence, not ordering) | [research-plan.md](research-plan.md) |
| Release notes per tag (required before any `v*` tag) | [release-notes/](release-notes/) |
| Backlog workflow (CLI usage, `--plain`, hard rules) | [agents/backlog.md](agents/backlog.md) |
| Research methodology (standing rules learned by past batteries) | [agents/research-methodology.md](agents/research-methodology.md) |
| README hero renders and other repo imagery | [assets/](assets/) |
| API docs source (DocC catalog) | [../Sources/Aski/Aski.docc/](../Sources/Aski/Aski.docc/) |
| Algorithm lineage & design notes | [../DESIGN.md](../DESIGN.md) |

## Tool inventory

Runnable commands under `Tools/` (`AskiToolSupport`, `AskiCLI`, and the lab implementations are
importable modules, not standalone implementations), plus the benchmark target under `Benchmarks/`.
Full invocation examples live in the [../AGENTS.md](../AGENTS.md) Commands block.

| Tool | Purpose | Canonical run |
| --- | --- | --- |
| `aski` | First-class image → ASCII rendering, resolved human/JSON inspection, and the unified research tree | `swift run aski [render] <image>` · `swift run aski inspect <image> --format json` · `swift run aski lab --help` |
| `AskiTileMatrix` | Tile-grid render matrix harness | `swift run AskiTileMatrix <image> <out> --columns 64` |
| `aski lab color` (`AskiColorLab` compatibility shim) | Color-pipeline research harness; hosts ASKI-69 `render-matcher-challenge` and [arbiter v2](Research/2026-09-04-aski62-arbiter-v2-protocol.md), a human-arbitrated `stimuli`/`judge`/`score` instrument with selection- and converter-level arms | `swift run aski lab color <subcommand> --output-dir …` · `swift run -c release aski lab color render-matcher-challenge --output-dir …` · `swift run -c release aski lab color arbiter <stimuli\|judge\|score>` |
| `aski lab motion` (`AskiMotionLab` replay) | Animation frame materialization, motion presets, GIF export; temporal-coherence research gates (`temporal-prior`, `source-tether` subcommands) | `swift run aski lab motion [<subcommand>] --output-dir …` |
| `aski lab video` (`AskiVideoLab` replay) | MP4/GIF decode → ASCII → re-encode harness; quality, `--pattern` overlay, and cosmetic `--bloom`/`--scanlines`/`--vignette` levers | `swift run aski lab video --input <clip> --output-dir …` |
| `aski lab accessibility` (`AskiAccessLab` replay) | Palette / rendered-grid CVD distinguishability audit | `swift run aski lab accessibility audit --output-dir …` |
| `aski lab decolor` (`AskiDecolorLab` replay) | Composited-cell perceptual oracle (FAIL-FAST `check`) | `swift run aski lab decolor check --output-dir …` |
| `aski lab hdr` (`AskiHDRLab` replay) | HDR/EDR emissive-spike artifact and gate harness | `swift run aski lab hdr check --output-dir …` |
| `aski lab preset` (`AskiPresetLab` replay) | Vesper A/B and product-probe harness: `ab` preserves the ASTSK-47 charset × columns adjudication; `probe-stimuli` makes ASKI-73's blinded matched three-arm stills and center-reveal GIFs with a SHA-256-bound schema-v2 key; `probe-score` verifies the exact manifest/media pair before it validates private response logs and applies the frozen gates | `swift run aski lab preset <ab\|probe-stimuli\|probe-score> …` |
| `BuildKernelLibrary` | Regenerate the Metal kernel library | `just regen-kernels` |
| `BuildStandardVectors` | Audit or regenerate built-in charset shape vectors | `just audit-vectors --output-dir <dir>` / `just regen-vectors` |
| `BuildResearchIndex` | Validate the research registry + docs lifecycle (`--check`); run bare to regenerate `index.json` | validate: `just research-check` · regen: `xcrun swift run BuildResearchIndex` |
| `BuildRepoMap` | Regenerate the repo source map | `just regen-repo-map` |
| `AskiBenchmarks` | `package-benchmark` perf suite; budgets/thresholds live inline in `Benchmarks/AskiBenchmarks/*Benchmarks.swift` | `just bench` |
