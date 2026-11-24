# Contributing to Aski

Start with [AGENTS.md](AGENTS.md) for repository rules, then use the
[task-to-code map](docs/agents/navigation.md) to find the implementation and tests.
The same engineering rules apply to human-written and agent-assisted changes.
For using the package, start with the [README](README.md).

## Start with the smallest useful change

Check the [open issues](https://github.com/BigCactusLabs/Aski/issues),
[pull requests](https://github.com/BigCactusLabs/Aski/pulls), and
[Backlog](docs/agents/backlog.md) before starting overlapping work. A typo or broken
example can go straight to a PR. For a new matcher, public API, dependency, or large
behavior change, open an issue describing the use case and proposed scope first.

Bug reports should include the tag or commit, macOS/Xcode/Swift versions, exact command
or minimal Swift example, expected behavior, and actual output. Include a small input
image and mask only when you have permission to redistribute them; a synthetic fixture
often makes reproduction easier. Keep private images, participant responses,
credentials, and environment dumps out of public reports. CLI manifests can contain
caller-supplied paths, so review them before attaching them.

## Toolchain and snapshot baseline

[Package.swift](Package.swift) requires **Swift 6.3+**, Swift 6 language mode, and
deployment minimums of **iOS 18, macOS 15, and visionOS 2**. Library builds, the CLI,
render tests, and DocC validation use a Mac with full Xcode and its command-line tools
selected. A standalone Swift compiler does not supply the Apple frameworks and Metal
tools required by this package.

Install [just](https://github.com/casey/just) for the task runner and Python 3 for the
portable documentation check. Benchmark capture needs Python 3.8+ and just 1.29+;
task-management tools are needed only when changing their records. The
[Makefile](Makefile) forwards to `just` and still requires it.

```bash
git clone https://github.com/BigCactusLabs/Aski.git
cd Aski
xcode-select -p
xcrun swift --version
just --list
just doctor --check toolchain
```

Use `xcrun swift` to keep builds on the selected Xcode toolchain. Mixing it with another
`swift` on `PATH` can invalidate `.build` artifacts. Default `just doctor` runs the full
release preflight, including dependency resolution, DocC, and a Metal regeneration
comparison; use `--check toolchain` for the initial environment check.

If you build inside a fresh `git worktree` and SwiftPM fails Git's `safe.bareRepository`
check while resolving package checkouts, scope the override to the build command instead
of changing global Git config:

```bash
GIT_CONFIG_PARAMETERS="'safe.bareRepository=all'" xcrun swift build --build-tests
```

**Snapshot reproduction has a narrower baseline than deployment.** The v0.7.0 release
recorded macOS 27.0 / Xcode 27.0 / Swift 6.4. The ASKI-3 goldens were re-recorded on
macOS 27.0.1 / Xcode 27.0 / Swift 6.4. The checked-in goldens also reproduce on an
Apple M3 Max with macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), and Swift 6.4. Another
host with the same OS/Xcode builds produced 16 one-step RGB differences; macOS 26 is
also known to differ. See the [render-drift evidence](docs/Research/Results/2026-11-05-aski97-render-drift/README.md).
Record the host as well as the toolchain. Verify a golden re-record on a second host,
or on the original recording host, before treating it as an OS-version baseline: a
re-baseline checked on one host has broken the gate on another. These are reproduction
constraints, not a macOS 27 deployment requirement or a cross-host raster guarantee.
[ASKI-78](docs/Research/2026-11-24-aski78-rasterizer-options.md#owner-decision-2026-11-24)
adopted a split policy on 2026-11-24: CPU-only outputs stay exact, and the Core Image suites
will accept several recorded digests per snapshot, one per host variant that reproduces. Until
that helper lands, every snapshot compares exactly.

## Verification

Run from the repository root:

```bash
just docs-check       # portable Markdown paths, images, and heading links
just check-fast       # inner loop: format, filtered tests, docs/structural checks
just check            # full acceptance gate before committing or submitting a PR
```

The [validation guide](docs/agents/validation.md) maps change types to focused checks,
explains the full gate, and covers generated files, snapshots, and failures. Use
[tooling.md](docs/agents/tooling.md) for executable and script entry points.

**There is no hosted CI workflow.** Report actual local results and the commit/toolchain
checked. Name any gate you could not run. Linux can check documentation and portable
script behavior; it cannot establish an Apple-framework build, DocC symbol validity,
Metal correctness, or render parity. Portable checks do not replace `just check`.

## Documentation that earns its place

| Material | Canonical home |
| --- | --- |
| What Aski does and the shortest working start | [README.md](README.md) |
| User recipes, public API, and capability limits | [DocC catalog](Sources/Aski/Aski.docc/Aski.md) |
| Repository rules and task-to-code routes | [AGENTS.md](AGENTS.md), [navigation](docs/agents/navigation.md) |
| Document discovery | [docs/README.md](docs/README.md) |
| Pipeline and implementation decisions | [architecture](docs/architecture.md), [DESIGN.md](DESIGN.md) |
| Checks and tools | [validation](docs/agents/validation.md), [tooling](docs/agents/tooling.md) |
| Research decisions and retained evidence | [research navigation](docs/agents/research.md), [registry](docs/Research/README.md) |
| Per-release changes | [CHANGELOG.md](CHANGELOG.md), [release notes](docs/release-notes/) |

Lead with what the reader can do, explain prerequisites before commands, and label
placeholders. Link canonical detail instead of keeping a second copy. Separate shipping
APIs, experimental policies, lab commands, and research SPI. Scope performance and
quality claims to their evidence. Record the exact command and build next to any
showcase image, and keep its caption true to that command. Preserve the `ASCII*` API names.

Update the docs hub and [llms.txt](llms.txt) when adding an entry point. Place new agent
guides under `docs/agents/`; the `docs/` root has an explicit allowlist in
[IndexCheck.swift](Tools/BuildResearchIndex/IndexCheck.swift). Use DocC symbol links only
for existing public symbols; removed APIs belong in ordinary code spans and migration
sections. Regenerate the research index and source map with their tools, never by hand.

## Research and project records

Literature can motivate an experiment; promotion requires Aski-specific evidence
against a frozen control and decision rule. Keep methods, inputs, limitations, negative
results, corrections, and retractions. A KILL verdict does not remain a production
option after its named replay dependencies close. Unsettled work belongs in a lab or
behind `@_spi(AskiResearch)`. Follow the [research methodology](docs/agents/research-methodology.md)
and [note format](docs/Research/README.md).

Manage `backlog/tasks/` through the [Backlog CLI](docs/agents/backlog.md), not direct
edits. Use [Blotter](AGENTS.md#blotter) selectively for reusable friction or findings.
Its committed ledger is public; run `blotter doctor --leaks` before pushing ledger
changes. Private stimuli and participant-level logs stay outside the repository.

## Pull requests and releases

Explain the problem, the change, how it was verified, and any source/output compatibility
impact. Include before/after renders for visual changes and representative measurements
for performance claims. Keep unrelated formatting and unexplained generated drift out
of the PR. Use a branch in your fork when you do not have push access. Deleting a branch that is
the base of an open PR closes that PR instead of retargeting it, so run
`gh pr list --base <branch>` before deleting any merged branch. To recover, re-push the
base ref, run `gh pr reopen`, then `gh pr edit --base main`.

Aski is pre-1.0: source-breaking changes can be justified, but need migration guidance.
During v0.8.0 preparation, `swift package diagnose-api-breaking-changes v0.7.0` could
not build its baseline: under Swift Build the package-benchmark plugin input was missing,
and `--build-system native` failed on module redefinitions. The source-break inventory
came from a diff of public and open declarations and enum cases in `Sources/Aski`. Retry
the tool before falling back to that diff.
Before creating any `v*` tag, commit the matching changelog entry and
`docs/release-notes/<tag>.md`. Verify that exact commit:

```bash
just check
just release-preflight
./Scripts/validate-docc.sh --emit-markdown
```

The last command emits optional DocC Markdown sidecars and a manifest in a unique,
retained directory printed as `DocC Markdown output: ...`. To choose a location, pass
`--output-dir .build/release-markdown`: the destination must be new and its parent must
exist. Relative paths resolve from the caller's working directory. Failed exports
remove only their own output; remove successful exports when no longer needed.
Current checkouts no longer use the shared `/tmp/aski-docc-markdown` location recorded
in the historical v0.7.0 notes.

For a relocatable CLI candidate, run `just package-cli /tmp/aski-cli-candidate` from a
clean checkout after those gates, using a new destination. The
[distribution guide](docs/guides/distribution.md) covers resource packaging, the extracted
smoke test, metadata, Swift Package Index configuration, and remaining release steps.
These commands do not publish a release. Packaging and earlier commits' checks do not
establish that the current commit passed the acceptance gate.

The public release history begins at v0.7.0. Earlier tags, PR numbers, and SHAs in
retained notes refer to private development and are not available in this history.

## Licensing and attribution

Keep [LICENSE](LICENSE), [NOTICE](NOTICE), bundled-font notices, and corpus attribution
intact. Submit only material you are entitled to share under the applicable terms.
Research assets and bundled fonts retain their own licenses.
