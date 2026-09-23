# Aski

**Pictures, reconsidered as type.**

Aski is a Swift package that converts images to ASCII art with a tone-prefiltered glyph matcher and an
independent OKLab color pipeline. Its current matcher uses a 60-dimensional log-polar descriptor. At the
shipping sampling regime that query reaches only 2-3 of its 60 bins, so the project does not claim that
the current implementation reliably preserves orientation. Replacing or simplifying it is active,
evidence-gated work:

![The Cosmic Cliffs of the Carina Nebula, rendered as 512 columns of colored ASCII text](docs/assets/hero-carina-512.png)

<sub>JWST's Cosmic Cliffs (Carina Nebula) as 512 columns × 133 rows of colored text, rendered to PNG
by Aski's own CGImage renderer — zoom in, every pixel cluster is a character. The source image ships
in this repo's research corpus
([carina-cosmic-cliffs.jpg](docs/Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg),
NASA/ESA/CSA/STScI, public domain).</sub>

## Beyond a brightness ramp

Most image-to-ASCII converters are brightness ramps. Sort a string like `@%#*+=-:. ` by ink
coverage, measure each cell's average luma, print the glyph at the matching index. It works, and it
throws away everything about the cell except one number.

Aski's current default adds a 60-dimensional log-polar histogram of ink density (5 log-spaced radial
bins × 12 angular bins), matched against pre-rasterized glyph descriptors by squared L2 distance after a
brightness top-K prefilter. The architecture is implemented and deterministic, but current research shows
that the shipping 2×4 source footprint populates only 2-3 bins while candidate glyphs average about 28.
On the frozen sparse `blocks` preset, a tone-only floor also beats the production matcher under all three
recorded oracles. The open question is which representation wins on Aski's real lattices and corpora, not
whether a more elaborate shape descriptor is better in principle. The evidence and next experiment are in
[the 2026-09-03 direction decision](docs/Research/2026-09-03-future-direction-and-architecture.md).

Color is a second, deliberately independent pass: per-cell average → OKLab → nearest palette entry.
The cube root is `cbrt`, not a sign-corrected `pow(x, 1.0/3.0)`, and out-of-gamut colors are
projected back by Ottosson's adaptive-L₀ straight-line method rather than clamped per channel.
Shape selection and ink color never contaminate each other.

Full algorithm write-up, with the citation trail back to Belongie–Malik–Puzicha shape contexts:
[DESIGN.md](DESIGN.md).

## Install

```swift
dependencies: [
    .package(url: "https://github.com/BigCactusLabs/Aski.git", from: "0.6.0"),
]
```

The manifest is `swift-tools-version: 6.3`, so the binding requirement is a **Swift 6.3 or newer
toolchain** — any Xcode shipping one will build the package. Platforms: iOS 18, macOS 15, visionOS 2
or newer. Strict Swift 6 concurrency throughout.

## Use

```swift
import CoreGraphics
import Aski

let grid = DefaultConverter().convert(image, columns: 80)

grid.renderPlainText()          // String
grid.renderAttributedString()   // AttributedString, per-cell color
grid.renderImage(               // CGImage
    font: .system(size: 12),
    backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    scale: 2
)
```

One conversion produces an `ASCIIGrid`; renderers are cheap and independent, so the same grid can go
to a terminal, a `Text` view, and a share sheet without reconverting.

There is also exactly one frozen render preset — deliberately *one* recipe rather than a preset
system. Its charset, column count, and duotone colors were settled by A/B evidence over real
portraits and are now locked behind a golden snapshot test, so the look cannot drift. It is one call,
and the DocC catalog documents it.

## Command line

The package also publishes a first-class executable product named `aski`. The explicit command is
`render`, and it is also the default so the short one-shot form stays available:

```bash
swift run aski input.jpg --columns 80
swift run aski render input.jpg --output output.txt --render-png output.png
swift run aski render input.jpg --charset blocks --background clear
swift run aski render input.jpg --render-png output.png --width 1600 --write-manifest render.json
swift run aski render photo.jpg --render-png dissolve.png --mask mask.png --mask-fallback original --mask-ground "#080808"
```

`--width` sets the exact output pixel width for `--render-png`; the render scale is derived from that
width and the grid, so the pixel size no longer depends on `--font-size`. `--mask` composites through
a raster mask with transparent, solid-color, or original-photo fallbacks; `--write-manifest` records a
deterministic render manifest alongside the artifacts.

`inspect` runs that same thumbnail and conversion path without writing render artifacts. Human text
is the default; `--format json` emits a deterministic, versioned report suitable for scripts:

```bash
swift run aski inspect input.jpg --columns 80
swift run aski inspect input.jpg --format json --output inspection.json
```

The command uses the same ImageIO thumbnail, converter, grid, and renderers as direct library calls;
it does not maintain a parallel implementation. The historical `AskiDemo` target and
`AskiDemoCommand` type remain as compatibility scaffolding around that shared render path. The
command hierarchy, JSON compatibility policy, and schema link are documented in
[docs/architecture.md#command-line-product](docs/architecture.md#command-line-product).

## What's in the box

Everything below ships in the one package; nothing is a stub with a roadmap attached.

| | |
| --- | --- |
| **Algorithms** | `logPolar` (default) and stateful `dotMatrix`; the failed `edgeMap` experiment was removed by [ASKI-16](<backlog/tasks/aski-16 - edgeMap-orientation-matching-does-not-select-orientation-appropriate-glyphs.md>) — [Algorithms](Sources/Aski/Aski.docc/Algorithms.md) |
| **Character sets** | `standard`, `minimal`, `blocks`, `dots`, `lines`, `diagonal`, `cross`, `diamond`, `mixed`, `braille`, plus runtime rasterization of any font — [Character Sets](Sources/Aski/Aski.docc/CharacterSets.md) |
| **Palettes** | Full-color pass-through, ANSI-16, monochrome, or your own in sRGB / Display P3 — [Palette Matching](Sources/Aski/Aski.docc/PaletteMatching.md) |
| **Tile grids** | Colored pixel-art, brick, and mosaic output in five cell shapes — [Tiles](Sources/Aski/Aski.docc/Tiles.md) |
| **Effects** | Backgrounds, lighting, blending, composable `EffectChain`, Metal-backed — [Effects](Sources/Aski/Aski.docc/Effects.md) |
| **Masking** | Raster masks with soft edges and transparent / solid / original-image / replacement-character fallbacks — [Masking](Sources/Aski/Aski.docc/Masking.md) |
| **Animation** | Time-based frame synthesis from a single conversion pass, entrance and ongoing patterns — [Animation](Sources/Aski/Aski.docc/Animation.md) |
| **Video** | MP4 and animated-GIF decode → ASCII → re-encode round-trip, with frame budgets — [Video](Sources/Aski/Aski.docc/Video.md) |
| **HDR** | Opt-in emissive spikes via gain-map Adaptive HDR — [HDR Rendering](Sources/Aski/Aski.docc/HDRRendering.md) |

Start at [Getting Started](Sources/Aski/Aski.docc/GettingStarted.md); coming from an early tag, read
[Migrating from v0.1.0](Sources/Aski/Aski.docc/Migrating-to-A1.md).

## Receipts

ASKI-68 removed five settled public experiments and their default-off production branches:
`occupancyMatching`, `chromaShapeAssist`, `shapeStructureAssist`, `steerableShapeAssist`, and
`inkPreCompensation` (including its floor and background controls). Occupancy, structure, steerable
shape, and ink pre-compensation closed KILL. The former chroma PASS was retracted after its sampling
lattice proved invalid; ASKI-66's bounded exact-lattice redesign found no responsive candidate, so the
synthetic dose question closed INCONCLUSIVE and the production control was deleted.

The durable record is the rule, note, result artifact, and Git history, not an accumulating set of
default-off production branches. `rawDensityValues` remains part of `ASCIICharacterSet` because the
composited-cell oracle and historical vector format still use absolute ink coverage.
The [ASKI-68 cleanup record](docs/Research/2026-09-04-aski68-production-experiment-cleanup.md)
maps each removed consumer to its retained evidence. [docs/Research/](docs/Research/) holds the indexed verdicts;
cross-cutting findings that outgrew one note land in [Discoveries.md](docs/Research/Discoveries.md).

The research harnesses that produced those verdicts ship under one discoverable command tree:
`aski lab {color,motion,video,accessibility,decolor,hdr,preset}`. Each takes `--help`; `--version`
prints the git SHA of the checkout that built it. Historical `Aski*Lab` products remain thin
compatibility shims for surviving commands; removed experiment runners remain in Git history, with
their invocations captured by the dated notes and artifacts. Inventory and canonical invocations:
[docs/README.md](docs/README.md).

## Research

Research lives alongside the code: dated notes, the discoveries log, and a generated index under
[docs/Research/](docs/Research/), with runnable experiments kept beside the corresponding tools,
tests, benchmarks, and redistributable fixtures.

Worthwhile research explains a decision, tests an idea, helps reproduce a result, or prevents someone
from repeating a dead end. Negative results, corrections, and clearly labeled hypotheses are welcome;
publication does not imply production readiness or a stable experimental API.

Add research through ordinary commits and pull requests. State the question, sources, method,
observations, limitations, and next decision. Keep the existing note format and update the index with
the note. Short cross-cutting findings can go in the discoveries log rather than becoming a new report.
Distinguish proposed work from executed experiments, say when a historical result cannot be
reproduced from the available code or data, and keep useful corrections and retractions instead of
presenting only successful outcomes. Share only data and assets appropriate for public
redistribution; sensitive inputs stay outside the repository.

## Built in the open

Everything happens on `main`: work lands there through short-lived branches and PRs, and releases
are tags.

Two habits are checked into the repo:

- **Backlog** — the live task queue under [`backlog/`](backlog/), managed with the
  [Backlog.md CLI](https://github.com/MrLesk/Backlog.md). Conventions in
  [docs/agents/backlog.md](docs/agents/backlog.md).
- **Blotter** — `.blotter.jsonl`, an append-only ledger of engineering friction and findings, written
  by [blotter](https://github.com/BigCactusLabs/blotter) (v2 log format). It starts empty and is
  written as things happen — public from the moment they are committed. Filing rules are in
  [AGENTS.md](AGENTS.md#blotter).

Both are as public as the code, because the process is part of the product.

## Verifying a checkout

```bash
just --list          # every target
just check-fast      # inner loop: format + filtered tests + structural checks
just check           # full gate — run this before a commit or a PR
just release-preflight
```

`make <target>` forwards to the same names. Targets invoke `xcrun swift` so local runs use the
selected Xcode toolchain, not whatever `swift` happens to be first on `PATH` — the two are routinely
different versions, and mixing them poisons `.build`.

`just check` is ordered fail-fast: cheap gates, then a single `swift build --build-tests`, then
drift checks, then the test suite, with DocC validation last. That one build is reused by every
later step. The suite runs in three phases — the core tests in parallel, then the media tests
(GIF, video, motion) serially, then the two video-encoder deadlock sentinels on their own. Media
work contends for the machine's media engine and I/O, so running it serially trades a little wall
time for a gate that does not flake. The gate is authoritative **locally**; this repository ships
no hosted CI workflow.

Two warnings you can ignore: SwiftPM emits `Path`→`URL` plugin-API deprecations from the third-party
`package-benchmark` plugins under `.build/checkouts/`. They are not ours and clear when upstream
adopts the new API.

## On the `ASCII*` prefix

`ASCIIConverter`, `ASCIIGrid`, `ASCIIPalette`, `ASCIICharacterSet`, `ASCIICell`, and `ASCIIFont` keep
their prefix on purpose. ASCII is the technical medium the package operates on, not a leftover brand
— the same reasoning behind Apple's `CG*` and `CI*` types — and it keeps `ASCIICharacterSet` clear of
Foundation's `CharacterSet`. `import Aski` followed by `ASCIIConverter` reads as "Aski's ASCII
converter."

## Stability

Pre-1.0, and honest about it. Per SemVer §4, anything may change while the major version is `0`;
minor bumps here can and do carry source-breaking changes when they buy real output quality. Pin an
exact version (`exact: "0.6.0"`) if that matters to you. Changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## Where else to look

| | |
| --- | --- |
| Docs discovery hub, tool inventory | [docs/README.md](docs/README.md) |
| Command-line product and automation boundary | [docs/architecture.md#command-line-product](docs/architecture.md#command-line-product) |
| Architecture and pipeline stages | [docs/architecture.md](docs/architecture.md) |
| Algorithm lineage and design notes | [DESIGN.md](DESIGN.md) |
| Generated symbol index | [docs/repo-map.generated.md](docs/repo-map.generated.md) |
| Conventions for AI coding agents | [AGENTS.md](AGENTS.md) |
| Machine-readable entry point | [llms.txt](llms.txt) |

## References

- Ottosson, B. — [A perceptual color space for image processing (OKLab)](https://bottosson.github.io/posts/oklab/)
- Ottosson, B. — [Gamut clipping in OKLab and OKLCh](https://bottosson.github.io/posts/gamutclipping/)
- Belongie, S., Malik, J., Puzicha, J. (2002) — *Shape matching and object recognition using shape contexts*, IEEE TPAMI
- Xu, X., Zhang, L., Wong, T.-T. (2010) — [Structure-based ASCII art](https://cse.cuhk.edu.hk/~ttwong/papers/asciiart/asciiart.html), ACM TOG
- WWDC 2018 Session 219 — *Image and Graphics Best Practices*

## License

Apache 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Courier Prime Regular is bundled for attribution and downstream rendering experiments. Courier Prime
is copyright 2015 The Courier Prime Project Authors, licensed under the
[SIL Open Font License 1.1](Sources/Aski/Resources/Fonts/OFL.txt).
