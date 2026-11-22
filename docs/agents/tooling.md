# Tool inventory

Run Swift tools from the repository root through the selected Xcode toolchain.
[Package.swift](../../Package.swift) defines products, targets, and their non-default
paths. [justfile](../../justfile) defines build/test/docs recipes; use `just --list`
for that inventory and the [validation guide](validation.md) to choose checks.

## Discover the current command surface

```bash
xcrun swift run aski --help
xcrun swift run aski render --help
xcrun swift run aski metadata
xcrun swift run aski lab --help
```

`aski metadata` emits the versioned command inventory for automation. Use it and the
selected subcommand's `--help` to discover current flags instead of copying an archived
experiment invocation. [`AskiCommand`](../../Tools/AskiCLI/AskiCommand.swift) owns the
root/lab tree; [`AskiMetadataCommand`](../../Tools/AskiCLI/AskiMetadataCommand.swift)
derives metadata from that configuration. [JSON schemas](../assets/schemas/) and the
[command-line architecture](../architecture.md#command-line-product) define the
machine-output boundary.

`--version` probes Git in the **current working directory**. Inside Aski it reports the
checkout's HEAD; outside a Git repository it reports `unknown`; inside another
repository it reports that repository's HEAD. It is not an embedded binary build ID.
The labs' `--aski-git-sha` option overrides recorded provenance only. See
[`ToolVersion`](../../Tools/AskiToolSupport/SharedOptions.swift) and
[`GitSHA`](../../Tools/AskiToolSupport/GitSHA.swift); distributed candidates also carry
the [packaging metadata](../guides/distribution.md).

## Product commands

The following are usage signatures: replace `<placeholders>` before running them.
The [command-line guide](../../Sources/Aski/Aski.docc/CommandLine.md) contains complete
examples for flags, masks, PNG sizing, and manifests.

| Command | Purpose | Implementation |
| --- | --- | --- |
| `xcrun swift run aski render <image> --columns 80` | Image → character art; `render` is also the default subcommand | [AskiDemoCommand.swift](../../Tools/AskiToolSupport/AskiDemoCommand.swift), [ToolImageConversion.swift](../../Tools/AskiToolSupport/ToolImageConversion.swift) |
| `xcrun swift run aski inspect <image> --format json` | Resolved conversion metadata without writing render artifacts | [AskiInspectCommand.swift](../../Tools/AskiToolSupport/AskiInspectCommand.swift) |
| `xcrun swift run aski metadata` | Schema-versioned inventory of commands, defaults, options, and replay mappings | [AskiMetadataCommand.swift](../../Tools/AskiCLI/AskiMetadataCommand.swift) |
| `xcrun swift run AskiTileMatrix <image> <out> --columns 64 --scale 12` | Tile-grid render matrix; separate developer utility | [TileMatrixCommand.swift](../../Tools/AskiToolSupport/TileMatrixCommand.swift), [runner](../../Tools/AskiTileMatrix/) |

Shared argument bounds, image I/O, provenance, rendering helpers, and the frozen render
reference live in [Tools/AskiToolSupport](../../Tools/AskiToolSupport/). They are tooling
support, not another public library product. The `Aski` library remains independent
of ArgumentParser and the labs.

## Research labs

Read the [research navigation](research.md) and the specific protocol before running a
study. A command's presence does not mean its policy is a shipped product feature or
its candidate has been adopted. New automation uses `aski lab …`.

| Canonical invocation | Purpose | Implementation |
| --- | --- | --- |
| `xcrun swift run aski lab color --help` | Color, matching, lattice, polarity, and selection-ceiling experiments | [AskiColorLab](../../Tools/AskiColorLab/) |
| `xcrun swift run -c release aski lab color render-matcher-challenge --output-dir <dir>` | Fixed ASKI-69 matcher challenge; use its frozen protocol | [RenderMatcherChallenge](../../Tools/AskiColorLab/SamplingLattice/RenderMatcherChallenge.swift) |
| `xcrun swift run aski lab motion --output-dir <dir> --preset all --columns 80 --fps 12` | Motion/animation presets and GIF output; additional research subcommands in `--help` | [AskiMotionLab](../../Tools/AskiMotionLab/) |
| `xcrun swift run aski lab video --input <clip.mp4> --output-dir <dir> --columns 80` | MP4/GIF decode, conversion, and re-encoding | [AskiVideoLab](../../Tools/AskiVideoLab/) |
| `xcrun swift run aski lab accessibility audit --output-dir <dir> --columns 80` | Palette/grid color-vision distinguishability audit | [AskiAccessLab](../../Tools/AskiAccessLab/) |
| `xcrun swift run aski lab decolor check --output-dir <dir> --columns 80` | Composited-cell perceptual oracle; a KILL verdict fails the command | [AskiDecolorLab](../../Tools/AskiDecolorLab/) |
| `xcrun swift run aski lab hdr check --output-dir <dir> --columns 80` | Research-only HDR/EDR gates; a KILL verdict fails the command | [AskiHDRLab](../../Tools/AskiHDRLab/) |

Compatibility products map as follows. They preserve surviving command paths, not
every historical experiment:

| Historical executable | Current entry point |
| --- | --- |
| `AskiDemo` | `aski render` (the first-class command adds manifest support) |
| `AskiColorLab` | `aski lab color` |
| `AskiMotionLab` | `aski lab motion` |
| `AskiVideoLab` | `aski lab video` |
| `AskiAccessLab` | `aski lab accessibility` |
| `AskiDecolorLab` | `aski lab decolor` |
| `AskiHDRLab` | `aski lab hdr` |

The former preset lab and removed experiment runners are absent from the current
package. Retained notes describe historical invocations and replay limits. The
package-only [`FrozenRenderReference`](../../Tools/AskiToolSupport/FrozenRenderReference.swift)
holds the frozen research recipe; it is not a public preset API.

## Generators and validation utilities

| Tool / recipe | Purpose | Source and details |
| --- | --- | --- |
| `just docs-check` | Portable documentation navigation check | [check-doc-links.py](../../Scripts/check-doc-links.py) |
| `just regen-kernels` | Regenerate the bundled Metal library | [BuildKernelLibrary](../../Tools/BuildKernelLibrary/) |
| `just regen-vectors` / `just audit-vectors --output-dir <dir>` | Compare raster drift; production regeneration is blocked pending ASKI-78 ([current boundary](research.md#other-decision-routes)) | [BuildStandardVectors](../../Tools/BuildStandardVectors/), [drift policy](../Research/2026-09-04-aski51-core-text-drift-policy.md) |
| `xcrun swift run BuildResearchIndex` / `just research-check` | Generate or validate the research registry, manifests, and lifecycle rules | [BuildResearchIndex](../../Tools/BuildResearchIndex/) |
| `just regen-repo-map` / `just repo-map-check` | Generate or validate the top-level declaration map of `Sources/Aski/` | [BuildRepoMap](../../Tools/BuildRepoMap/) |
| `just docc` | Resolve the public catalog against Aski's symbol graph | [validate-docc.sh](../../Scripts/validate-docc.sh); optional release exports in [CONTRIBUTING](../../CONTRIBUTING.md#pull-requests-and-releases) |
| `just doctor --check toolchain` / `just release-preflight` | Selected diagnostics / full preflight, including Metal byte comparison | [repo-doctor.sh](../../Scripts/repo-doctor.sh), [failure guide](validation.md#diagnose-a-failure) |
| `just package-cli <new-output-dir>` | Build and smoke-test a relocatable CLI archive | [package-cli.sh](../../Scripts/package-cli.sh), [distribution guide](../guides/distribution.md) |
| `just bench` / `just bench --smoke` | Capture complete evidence from `AskiBenchmarks`; no numeric budget verdict | [validate-benchmarks.py](../../Scripts/validate-benchmarks.py), [benchmark definitions](../../Benchmarks/AskiBenchmarks/), [contract](../benchmark-validation.md) |
| `just test-infra` | Portable script regression suite with fake Apple tools | [Scripts/tests](../../Scripts/tests/), [validation limits](validation.md#what-can-run-without-a-mac) |

Task records use the [Backlog workflow](backlog.md). Reusable friction/findings use
[Blotter](../../AGENTS.md#blotter). Task-specific benchmark reproducers and retained
candidate patches live under [Scripts/research](../../Scripts/research/); start from
their README/protocol, not a bare script name. Pre-v0.7.0 SHAs, PRs, and tags refer to
private development and do not imply public replay access.
