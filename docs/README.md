# Aski documentation

Use this hub to find the right level of detail. The [project README](../README.md)
introduces the product; [AGENTS.md](../AGENTS.md) is the coding-agent entry point.

## Change the repository

Start with **[task-to-code navigation](agents/navigation.md)**: it maps common changes
to source files, tests, and the corresponding public guide. Read the relevant route,
then use the validation guide to choose checks.

| Need | Start here |
| --- | --- |
| Source ownership, nearby tests, and focused searches | [Repository navigation](agents/navigation.md) |
| Contributor setup and snapshot toolchain | [CONTRIBUTING](../CONTRIBUTING.md#toolchain-and-snapshot-baseline) |
| Commands to verify a change; native and portable limits | [Validation](agents/validation.md) |
| Pipeline, current defaults, ownership, and dependencies | [Architecture](architecture.md) |
| CLI automation contracts | [Command-line architecture](architecture.md#command-line-product), [versioned JSON schemas](assets/schemas/) |
| Commands, lab runners, generators, and compatibility shims | [Tool inventory](agents/tooling.md) |
| An open task or task update | [Backlog workflow](agents/backlog.md) |
| Whether a proposed experiment has already been tried | [Research decisions and next entry points](agents/research.md) |
| A type or file in the library | [Generated source map](repo-map.generated.md) |
| Descriptor lineage, measured limits, and design rationale | [DESIGN](../DESIGN.md) |
| Package a CLI candidate or configure hosted package docs | [Distribution](guides/distribution.md) |
| Machine-readable entry points | [llms.txt](../llms.txt) |

## Use Aski

| Goal | Guide |
| --- | --- |
| Run a first render using a bundled image | [README: Try it](../README.md#try-it) |
| Compare three rendered treatments and their commands | [Character-art examples and recipes](guides/character-art-recipes.md) |
| Convert files, export PNGs, apply masks, or inspect JSON | [Command-line guide](../Sources/Aski/Aski.docc/CommandLine.md) |
| Install the library and make a first conversion | [Installation](../README.md#use-in-swift), [Getting Started](../Sources/Aski/Aski.docc/GettingStarted.md) |
| Choose text, attributed text, or raster output | [Rendering](../Sources/Aski/Aski.docc/Rendering.md) |
| Change the alphabet, matcher, or palette | [Character Sets](../Sources/Aski/Aski.docc/CharacterSets.md), [Algorithms](../Sources/Aski/Aski.docc/Algorithms.md), [Palette Matching](../Sources/Aski/Aski.docc/PaletteMatching.md) |
| Make cutouts or photo-to-type dissolves | [Masking](../Sources/Aski/Aski.docc/Masking.md) |
| Add motion, video, or finishing effects | [Animation](../Sources/Aski/Aski.docc/Animation.md), [Video and GIF](../Sources/Aski/Aski.docc/Video.md), [Effects](../Sources/Aski/Aski.docc/Effects.md) |
| Use tiles or a two-color recipe | [Tiles](../Sources/Aski/Aski.docc/Tiles.md), [Duotone](../Sources/Aski/Aski.docc/Duotone.md) |
| Upgrade an integration | [Migration notes](../Sources/Aski/Aski.docc/Migrating-to-A1.md), [CHANGELOG](../CHANGELOG.md), [release notes](release-notes/) |

The [DocC catalog](../Sources/Aski/Aski.docc/Aski.md) owns API articles and symbol
navigation. GitHub displays DocC symbol links as source; `just docc` resolves and
validates them locally. To export Markdown sidecars, use the explicit output workflow
in [CONTRIBUTING](../CONTRIBUTING.md#pull-requests-and-releases). Swift Package Index
hosts the rendered
[API documentation](https://swiftpackageindex.com/BigCactusLabs/Aski/documentation/aski)
and Aski's [package page](https://swiftpackageindex.com/BigCactusLabs/Aski), which lists
releases and the Swift versions and platforms the package builds with. Release notes do
not by themselves establish that a CLI release archive has been published.

## Research and evidence

[Research navigation](agents/research.md) explains current decision state, including
adopted, rejected, inconclusive, and retired work. The
[research index](Research/README.md) is the complete searchable catalog of notes,
corpora, and result stores; [index.json](Research/index.json) is its generated machine
projection.

| Need | Read |
| --- | --- |
| Standing experiment rules and frozen render reference | [Research methodology](agents/research-methodology.md) |
| Complete benchmark capture, sample validity, or allocator provenance | [Benchmark validation](benchmark-validation.md) |
| Compare repeated baseline/candidate captures | [Paired benchmarks](agents/paired-benchmarks.md) |
| Rendering and fallback experiment contracts | [Rendering groundwork](agents/rendering-groundwork.md), starting with its current status |
| Brightness shortlist contracts and rejected heap selection | [Brightness groundwork](agents/brightness-pool-groundwork.md), starting with its current status |
| Cross-cutting findings awaiting triage | [Discoveries](Research/Discoveries.md) |
| Retained color-theory planning | [Historical research plan](research-plan.md) |

Pre-1.0 APIs and output may change. Ordinary APIs, experimental policies, labs, and
research SPI have different readiness levels; [HDR rendering](../Sources/Aski/Aski.docc/HDRRendering.md)
is research-only. Older SHAs, issue numbers, and tags can refer to private development.
The public release history starts at v0.7.0. A historical runner or proposed pipeline
is not a promise about the current checkout.

## Tool inventory

The canonical inventory is [Tooling](agents/tooling.md). `aski render` and `aski
inspect` are the ordinary still-image workflow; `aski lab …` contains research
harnesses. Use `just --list` for build/test/docs/release recipes and current CLI
`--help` or `aski metadata` for command discovery.

Gates run locally; there is no hosted CI workflow. [Validation](agents/validation.md)
separates the full Apple-platform gate from portable documentation and script checks.

## Maintaining documentation

Keep one owner for each kind of information, then link to it. Avoid duplicating a
long list of labs, toolchain details, or study verdicts in every entry point.

| Information | Edit here |
| --- | --- |
| Product introduction, first render, package installation | [README](../README.md) |
| Agent-wide constraints and startup route | [AGENTS](../AGENTS.md); detailed task routing in [Navigation](agents/navigation.md) |
| Setup, PR expectations, release workflow | [CONTRIBUTING](../CONTRIBUTING.md) |
| Validation commands and generated artifacts | [Validation](agents/validation.md), with [justfile](../justfile) as command authority |
| Public API behavior and examples | [DocC catalog](../Sources/Aski/Aski.docc/); update migration notes for breaking changes |
| Current implementation and design boundaries | [Architecture](architecture.md) and [DESIGN](../DESIGN.md) |
| CLI/lab/generator inventory | [Tooling](agents/tooling.md), verified against [Package.swift](../Package.swift) and command declarations |
| Current research routing | [Research navigation](agents/research.md); the checked-in backlog still owns task state |
| Protocols, measured results, and asset attribution | Dated [research notes](Research/README.md) with front matter; [Corpus](Research/Corpus/) and [Results](Research/Results/) manifests |
| Generated indexes | Edit source inputs, then run the generators listed in [Validation](agents/validation.md). Never hand-edit generated blocks. |

For a new guide, add a link here and in [llms.txt](../llms.txt). Put focused developer
guides in `docs/agents/` and user/distribution guides in `docs/guides/`;
[`IndexCheck.docsRootFailures`](../Tools/BuildResearchIndex/IndexCheck.swift) deliberately
allowlists the `docs/` root. Keep existing useful heading anchors when reorganizing.

Run `just docs-check` (or `python3 -B Scripts/check-doc-links.py`) to check maintained
entry points, guides, ordinary DocC file links, images, heading anchors, and same-repo
links in `llms.txt`. It is offline; external URLs and DocC symbol resolution require
separate checks. Historical research bodies and release notes are not rewritten by
this navigation check. Run `just docc` for resolved DocC symbols and the full local
`just check` as required by the contribution workflow.
