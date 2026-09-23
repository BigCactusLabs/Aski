# AGENTS.md

Aski — a public, pre-1.0 Swift package that converts images to character art, with a macOS CLI. The current default uses 60D log-polar matching and OKLab color processing. Targets iOS 18+, macOS 15+, visionOS 2+. Requires Swift 6.3+ and strict Swift 6 concurrency.

For contributor setup, the recorded snapshot toolchain, and PR expectations, start with [CONTRIBUTING.md](CONTRIBUTING.md). Public user recipes live in the [DocC catalog](Sources/Aski/Aski.docc/Aski.md) and [command-line guide](Sources/Aski/Aski.docc/CommandLine.md).

## Hard rules

- **Do not rename `ASCII*` types** (`ASCIIConverter`, `ASCIIGrid`, `ASCIIPalette`, `ASCIICharacterSet`, `ASCIICell`, `ASCIIFont`). The brand is Aski; the API surface stays ASCII* because ASCII is the technical medium, not a brand artifact.
- **Public, but not API-frozen.** Source-breaking changes are acceptable when they materially improve output quality, app fit, performance, velocity, or maintainability. Aski is pre-1.0; minor releases may change source or rendered output. Explain breaks in the changelog and migration guidance instead of implying either a stable SDK contract or a private-only package.
- **Strict Swift 6 concurrency.** All targets build under strict concurrency; keep new code warning-free.
- **If you change Metal kernel sources, regenerate the library and commit it.** Run `just regen-kernels`, then commit the updated `Sources/Aski/Resources/Kernels/default.metallib`. `just release-preflight` byte-diffs the checked-in file against a fresh regen.
- **Do not loosen benchmark thresholds without a justified perf reason in the commit message.** Thresholds live inline in `Benchmarks/AskiBenchmarks/*Benchmarks.swift` (e.g., `AnimationBenchmarks`, `EffectChainBenchmarks`).
- **A change that moves goldens on the frozen preset carries its no-harm census in the same PR.** Run the selection-ceiling before/after (MAE and GMSD) and commit the CSV alongside the re-recorded goldens. A golden re-record proves determinism, not quality; once the pre-change build is gone from every worktree the measurement costs a detached rebuild (ASKI-31). Standing research rules: [docs/agents/research-methodology.md](docs/agents/research-methodology.md).
- **A KILL verdict does not stay as a production option.** Preserve the pre-registered rule, note, result artifacts, and Git history. Delete the production branch after any named replay dependency closes; keep pending or inconclusive work lab-only or behind `@_spi(AskiResearch)`. ASKI-68 owns the legacy cleanup.
- **Literature can open a research arm; only Aski evidence can promote it.** New matchers, backends, learned models, and visual vocabularies start in a lab with a frozen control and decision rule. A promoted replacement removes old complexity instead of becoming another permanent default-off path unless a concrete product use justifies both.
- **No SDK ceremony.** Don't add generic abstractions, compatibility layers, or public-facing API surface without a concrete app use. Keep abstractions only when they serve current library needs or clearly simplify the conversion pipeline.
- **Public docs describe the current surface.** Separate ordinary features, experimental policies, lab commands, and research SPI. Keep research caveats and asset attribution; do not turn a fixture result into a universal quality or performance claim. Link canonical detail instead of duplicating it. Update the docs hub and `llms.txt` when adding an entry point.
- **Non-default Swift package layout:** auxiliary targets live under `Tools/`, `Benchmarks/`, and `Tests/`, not `Sources/`. See `Package.swift`.
- **Release hygiene before tags.** Before pushing any future `v*` tag, commit the matching `CHANGELOG.md` entry and `docs/release-notes/<tag>.md`. Verification evidence belongs to the commit actually checked, not later documentation or code changes.
- **Do not edit files under `backlog/tasks/` directly.** Use the `backlog` CLI; see [docs/agents/backlog.md](docs/agents/backlog.md).
- **Blotter entries are public.** `.blotter.jsonl` is a committed, append-only public ledger written by [blotter](https://github.com/BigCactusLabs/blotter) v2 (`"v":2` records, `cargo install blotter-cli` ≥ 1.0) — text only, no secrets, no absolute paths. The v1 ledger was retired before this repository's public history began.

## Commands

Canonical commands live in `justfile`; `Makefile` forwards the same target names and still requires `just`.

```bash
just --list            # discover every target
just check             # full pre-commit / release gate (fail-fast order)
just check-fast        # fast inner loop: format + filtered tests + structural checks
just format-check
just test
just docc
just research-check
just bench
just regen-kernels     # also: regen-vectors, audit-vectors, regen-repo-map, repo-map-check
just lifecycle-check   # also: test-research, test-artifacts (targeted suites)
just doctor            # environment/toolchain diagnostics
just release-preflight
make check             # forwards to just check
```

- Use `just check-fast` while iterating; run the full `just check` before committing or opening a PR. State explicitly when a gate could not be run.
- **Gates run locally.** The full local `just check` on developer hardware is the authoritative quality gate. This repository ships no hosted CI workflow. Deployment minimums do not imply cross-OS raster parity; see the [snapshot baseline](CONTRIBUTING.md#toolchain-and-snapshot-baseline).
- `just check` is ordered **fail-fast**: format → one `swift build --build-tests` → drift checks → three test phases → `validate-docc` last. The single build is the only build; every later step consumes it via `--skip-build` (`ASKI_SKIP_BUILD=1`), so do not add a step that builds again. The three test phases are **core** (everything else, parallel), **media** (`GIF|Video|MotionLab`, `--no-parallel` — these contend for the media engine, ASKI-39), and the two **deadlock sentinels** (`--no-parallel`, isolated). The core phase skips the four registry tests the preceding drift tools already cover, and keeps `docsRootMatchesAllowlist`. DocC runs warm here — the Aski symbol graph is cached under `.build/aski-docc-symbols-cache`, keyed on Aski sources + package config + toolchain, and regenerated only on key mismatch (the catalog Markdown is always re-validated live, so broken links still fail on a warm cache; ASKI-42). Local gates validate only; Markdown sidecars are opt-in via `./Scripts/validate-docc.sh --emit-markdown` for release assets. Preserve this ordering when editing the recipe.
- SwiftPM emits benign `package-benchmark` plugin deprecation warnings (a `Path`→`URL` plugin-API change upstream hasn't adopted). Ignore them unless the warning path points outside `.build/checkouts/`; do not "fix" them. Settled as *tolerate* (ASTSK-36).

## Tools

The first-class product command is `aski`; research labs and compatibility tooling share swift-argument-parser. `--help` enumerates subcommands, and `--version` prints the current checkout's git SHA (`unknown` outside a repo). The command/product boundary and machine-output compatibility policy are documented in [docs/architecture.md#command-line-product](docs/architecture.md#command-line-product). Full inventory → [docs/README.md](docs/README.md#tool-inventory); per-tool research provenance and verdicts → [docs/Research/](docs/Research/).

Usage notation below uses `<placeholders>` and `[optional arguments]`, not copy-paste shell commands. Run resolved commands from the repository root through the selected Xcode toolchain:

```text
xcrun swift run aski [render] <image> --columns 80 [--charset blocks] [--background clear] [--output <path>] [--render-png <path> [--width <px>] [--font-size <n>]] \
  [--mask <path> [--mask-fallback transparent|solid|original] [--mask-fallback-color <color>] [--mask-fallback-sizing fill|fit|stretch] [--mask-ground <color>] [--mask-hard-edges] [--mask-invert]] [--no-preserve-aspect] [--write-manifest <path>]  # image → ASCII (render is default; faithful aspect by default)
xcrun swift run aski inspect <image> --columns 80 [--format text|json] [--output <path>]  # resolved conversion metadata; JSON schema v1 under docs/assets/schemas/
xcrun swift run AskiTileMatrix <image> <out> --columns 64 --scale 12                    # tile-grid render matrix
xcrun swift run aski lab color <subcommand> --output-dir <dir>                         # color-pipeline research (many subcommands; see --help)
xcrun swift run -c release aski lab color render-matcher-challenge --output-dir <dir>  # ASKI-69 one-shot fixed-footprint matcher challenge
xcrun swift run aski lab motion --output-dir <dir> --preset all --columns 80 --fps 12   # animation / motion presets, GIF export
xcrun swift run aski lab video --input <clip.mp4|gif> --output-dir <dir> --columns 80    # MP4/GIF decode → ASCII → re-encode (+ quality/effect levers; see --help)
xcrun swift run aski lab accessibility audit --output-dir <dir> --columns 80           # palette / grid CVD distinguishability audit
xcrun swift run aski lab decolor check --output-dir <dir> --columns 80                  # composited-cell perceptual oracle — FAIL-FAST (nonzero exit == KILL)
xcrun swift run aski lab hdr check --output-dir <dir> --columns 80                      # HDR/EDR emissive-spike gates — FAIL-FAST (nonzero exit == KILL)
xcrun swift run aski lab preset ab --input <portrait> --output-dir <dir>                # ASTSK-47 charset×columns A/B → candidate PNGs + contact sheet + manifest (feed it REAL faces)
xcrun swift run -c release aski lab preset probe-stimuli --source-manifest <private.json> --output-dir <public-dir> --key-output <private-key.json>  # ASKI-73 blinded three-arm stills + center reveal
xcrun swift run aski lab preset probe-score --stimuli-manifest <manifest.json> --key <private-key.json> --session-one <private.csv> --repeat-log <private.csv> --output-dir <aggregate-dir>  # validates and scores frozen product gates
```

The historical `Aski*Lab` product names remain thin compatibility shims over the surviving lab commands. Removed experiment runners remain in Git history, with their invocations captured by the dated notes and artifacts. Use `aski lab …` for new commands and automation. Pre-v0.7.0 SHAs, PR numbers, and tags refer to private development; do not promise access to that history from this public checkout.

## Blotter

Run `blotter list` first to see what is already known. Blotter is a selective ledger, not a transcript: file a cut when the friction is transferable (another agent would hit it), consequential (cost real time or produced wrong work), recurring, misleading (the error pointed at the wrong cause), or systemic (doc gap, brittle interface, footgun). Skip typos, quoting slips, a bad first guess, a compiler correctly rejecting fresh code, and one-off mistakes specific to this run. Don't stop working — file it and push through.

```text
blotter add "<what you hit and what would have prevented it>" --tag <area> [--impact low|material|blocking]   # impact = consequence, not admission; low is the default and still a cut
blotter dogear "<one finding, in your own words, that a reader without this repo could follow>" --tag <area>   # findings, not chores or task notes
blotter resolve <id> --disposition fixed|promoted|accepted|invalid [--pr <url>] [--task ASKI-NN]   # dogears: --url / --dropped
blotter promote --source <cut-id>... --artifact-type doc|skill|guard|test|tool|process --artifact-ref <path>   # durable learning: "these cuts became this artifact"
blotter schema                                                                                    # the full machine contract
blotter doctor --leaks                                                                            # run before pushing; the ledger is public
```

Attach `--cmd`, `--exit`, or `--stderr-file` when filing tool failures; never feed raw environment dumps. Do not file global, system, or internal friction.

## Repo map

Orientation for what grep can't infer. A generated, byte-diff-guarded index of every top-level declaration lives at [docs/repo-map.generated.md](docs/repo-map.generated.md) (`just regen-repo-map` to refresh); the discovery hub is [docs/README.md](docs/README.md).

`Sources/Aski/` subsystems (one dir each):

- `Algorithms/` — 60D log-polar descriptor, edge gating, dot-matrix fallback
- `Tiles/` — tile-grid converter, cell shapes, Wu quantizer
- `Effects/` — lighting/composition/blending (public API + `Internal/`, `Kernels/`)
- `Video/` — GIF/MP4 decode + encode round-trip
- `Animation/` — time-based ASCII frame synthesis
- `Masking/` — raster masks, fallback modes, soft edges
- `Renderers/` — CGImage, plain-text, AttributedString output
- `CharacterSets/` — built-in sets + runtime rasterization (`Braille/`)
- `Resources/` — fonts, charset `ShapeData`, Metal `Kernels` (non-Swift)
- `Aski.docc/` — DocC catalog (Markdown)

The 24 root Swift files cluster by domain: **entry** (`ASCIIConverter`, `ASCIIConverter+Animation`, `ASCIIConverter+Research`, `RenderingOptions`, `ASCIIAlgorithm`, `VesperPreset`), **shape/sampling** (`ConversionEngine`, `ShapeMatching`, `CellSampling`, `GridRowWalk`), **color** (`ColorConversion`, `ColorPipelinePolicies`, `RenderColorSpace`, `GamutMapping`, `HelmlabMetric`), **palette** (`ASCIIPalette`, `ResolvedPalette`), **tiles/io** (`ASCIITileShape`, `ImageIOThumbnail`), and **core types/protocols** (`ASCIIGrid`, `ASCIICell`, `ASCIIFont`, `ASCIICharacterSet`, `GridDisplayProtocol`).

## Pointers

- **Public README and contribution workflow** → [README.md](README.md), [CONTRIBUTING.md](CONTRIBUTING.md)
- **User-facing CLI recipes** → [Command-line guide](Sources/Aski/Aski.docc/CommandLine.md)
- **Codebase map** → [Repo map](#repo-map) above; full symbol index → [docs/repo-map.generated.md](docs/repo-map.generated.md)
- **Docs discovery hub and tool inventory** → [docs/README.md](docs/README.md)
- **Command-line product and automation boundary** → [docs/architecture.md#command-line-product](docs/architecture.md#command-line-product)
- **Architecture, pipeline, key files** → [docs/architecture.md](docs/architecture.md)
- **Backlog workflow (CLI usage, `--plain`, hard rules)** → [docs/agents/backlog.md](docs/agents/backlog.md)
- **Research methodology (standing rules: pre-registration, exact lattice, supersampling, no-harm CSV)** → [docs/agents/research-methodology.md](docs/agents/research-methodology.md)
- **Algorithm research (OKLab, shape-context, frontier scans)** → [docs/Research/](docs/Research/)
- **DocC catalog source** → [Sources/Aski/Aski.docc/](Sources/Aski/Aski.docc/)
- **Discoveries log (cross-cutting insights, queued for triage)** → [docs/Research/Discoveries.md](docs/Research/Discoveries.md)
