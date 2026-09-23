# Contributing to Aski

Bring a good question, a reproducible bug, or an image that makes the renderer sweat.
Small, well-explained improvements are welcome; a new abstraction is not the price of admission.

For using the package, start with the [README](README.md). For repository conventions
and subsystem navigation, read [AGENTS.md](AGENTS.md). The same engineering rules apply
to human-written and agent-assisted changes.

## Start with the smallest useful change

Check the [open issues](https://github.com/BigCactusLabs/Aski/issues),
[pull requests](https://github.com/BigCactusLabs/Aski/pulls), and [Backlog](backlog/) before
starting overlapping work. A typo or a broken example can go straight to a PR. For a
new matcher, public API, dependency, or large behavior change, open an issue describing
the use case and proposed scope first.

Bug reports should include the tag or commit, macOS/Xcode/Swift versions, exact command
or minimal Swift example, expected behavior, and actual output. Include a small input
image and mask only when you have permission to redistribute them. A synthetic fixture
is often better than a personal photo.

Never post credentials, private source images, identifiable participant responses, or
unredacted environment dumps. CLI manifests can contain the paths supplied by the caller;
review them before attaching them to a public issue.

## Toolchain and snapshot baseline

The package manifest requires **Swift 6.3+**. Library deployment minimums are iOS 18,
macOS 15, and visionOS 2. Development and the CLI require a Mac with full Xcode and its
command-line tools selected; a standalone Swift installation is not the complete
Apple-framework/Metal toolchain used by this repository.

**For the v0.7.0 render goldens and checked-in Metal library, use the recorded
macOS 27 / Xcode 27 baseline.** The release branch records successful verification on
macOS 27.0 / Xcode 27.0 / Swift 6.4. Render snapshots are known to differ on macOS 26.
That is a contributor reproduction constraint, not a macOS 27 deployment requirement.
A supported Swift compiler alone does not guarantee identical raster output.

Install [just](https://github.com/casey/just) for the canonical task runner. The
[Makefile](Makefile) forwards to `just`; `make check` is not a way to avoid that dependency.
Research and task-management tools are needed only for their respective workflows.

```bash
git clone https://github.com/BigCactusLabs/Aski.git
cd Aski
xcode-select -p
xcrun swift --version
just --list
just doctor
```

Use a branch in your fork when you do not have push access. Run Swift commands through
`xcrun` to keep builds on the selected Xcode toolchain. Mixing that compiler with a
different `swift` on `PATH` can invalidate `.build` artifacts.

## Verification

From the repository root:

```bash
just check-fast       # inner loop; not the full acceptance gate
just test-artifacts   # command/docs links, registries, and artifact checks
just docc             # public symbol links; warnings are errors
just check            # full gate before submitting a PR
```

`just check` runs formatting, one shared build, drift checks, core tests, serialized
media tests, isolated deadlock sentinels, and DocC validation. Preserve its fail-fast
ordering and build reuse. **There is no hosted CI workflow:** include the actual local
results in your PR, together with the toolchain. Explicitly name checks you could not
run; a documentation review is not a passing Swift build or a render-quality result.

Snapshot changes need an explanation, not just new golden files. On the frozen preset,
changes that move goldens must include the before/after selection-ceiling MAE and GMSD
no-harm census in the same PR. Do not loosen snapshot or benchmark thresholds to make a
failure disappear. See [research methodology](docs/agents/research-methodology.md).

SwiftPM's known `package-benchmark` plugin deprecation warnings under `.build/checkouts/`
are upstream noise; warnings in project code still need attention.

## Documentation that earns its place

| Material | Home |
| --- | --- |
| What Aski does and the shortest working start | [README.md](README.md) |
| User recipes, public API, and capability limits | [DocC catalog](Sources/Aski/Aski.docc/Aski.md) |
| Where to find a document or tool | [docs/README.md](docs/README.md) |
| Pipeline and implementation decisions | [docs/architecture.md](docs/architecture.md), [DESIGN.md](DESIGN.md) |
| Dated experiments and retained evidence | [docs/Research/](docs/Research/) |
| Per-release changes | [CHANGELOG.md](CHANGELOG.md), [release notes](docs/release-notes/) |

Write with some character, but let the examples do the selling. Lead with what the
reader can make, explain prerequisites before commands, and label placeholders.
Separate shipping APIs from experimental policies, lab commands, and research SPI.
Scope quality and performance claims to their evidence; do not turn a single fixture,
hardware run, or attractive screenshot into a general guarantee.

Prefer links to canonical detail over copying a second version of it. Preserve the
`ASCII*` API names; the package brand is Aski, while the types also cover Unicode
character art. Update `llms.txt` and the docs hub when adding an entry point.

Use DocC symbol links only for existing public symbols. Keep removed APIs in ordinary
code spans and historical migration sections. Do not hand-edit generated research-index
blocks, `docs/Research/index.json`, or `docs/repo-map.generated.md`.

## Research: show the work, including the misses

Literature can motivate an experiment; only Aski-specific evidence can promote one.
Start with a frozen control and decision rule. Record sources, sampling geometry,
method, input provenance, observations, limitations, and the next decision. Clearly
separate proposed work from executed experiments.

Keep negative results, corrections, and retractions. A KILL verdict does not remain a
production option after its named replay dependencies close. Unsettled work belongs in
a lab or behind `@_spi(AskiResearch)`, not in the README's ordinary feature list.

Follow the [research note format](docs/Research/README.md) and
[standing methodology](docs/agents/research-methodology.md). Refresh registry outputs
with `xcrun swift run BuildResearchIndex`, then run `just research-check`. Share only
redistributable inputs; private stimuli and participant-level response logs stay outside
the repository. Historical private commits are provenance, not a promise of public replay.

## Generated artifacts and project records

Changes to Metal kernel sources require `just regen-kernels` and the updated
`Sources/Aski/Resources/Kernels/default.metallib` in the same PR. Use `just regen-vectors`
for intentional charset-vector changes and `just regen-repo-map` when the source map
changes; check the corresponding drift gates.

Manage `backlog/tasks/` through the Backlog CLI, not direct file edits. Follow the
[backlog guide](docs/agents/backlog.md). Use [Blotter](AGENTS.md#blotter) selectively for
reusable friction or findings, not a transcript. Its committed ledger is public;
run `blotter doctor --leaks` before pushing ledger changes.

## Pull requests and releases

Keep PRs focused. Explain the problem, the change, how it was verified, and any
source/output compatibility impact. Include before/after renders for visual changes
and representative measurements for performance claims. Do not include unrelated
formatting, private artifacts, or generated files with unexplained drift.

Aski is pre-1.0: source-breaking changes are acceptable when justified, but they still
need migration guidance. For release work, commit the matching changelog entry and
`docs/release-notes/<tag>.md` **before** creating any `v*` tag. Run:

```bash
just check
just release-preflight
./Scripts/validate-docc.sh --emit-markdown
```

The last command emits optional DocC Markdown sidecars and a manifest under
`/tmp/aski-docc-markdown`; it does not itself publish a release. Check the release's
notes for packaging and asset expectations. Do not describe checks from an earlier
commit as verification of a later one.

The public release history begins at v0.7.0. Earlier tags, PR numbers, and commit SHAs
in retained notes refer to private development and are not available in this history.

## Licensing and attribution

Keep [LICENSE](LICENSE), [NOTICE](NOTICE), bundled-font notices, and corpus attribution
intact. Submit only material you are entitled to share under the applicable terms.
Research assets and bundled fonts retain their own licenses.
