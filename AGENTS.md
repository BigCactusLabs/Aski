# Agent guide

Aski is a public, pre-1.0 Swift library and macOS CLI for image-to-character-art
conversion. The default matcher is 60D log-polar; the default color path uses OKLab.
[Package.swift](Package.swift) defines Swift 6.3+, strict Swift 6 concurrency, and
Apple platform minimums (iOS 18, macOS 15, visionOS 2).

## Start here

1. Inspect `git status --short --branch` and the current diff before editing.
2. Use the [task-to-code map](docs/agents/navigation.md) to find the owning source,
   nearby tests, and the relevant user guide. Read that slice first.
3. Select checks from the [validation guide](docs/agents/validation.md). Use the
   [research guide](docs/agents/research.md) before starting or reviving an experiment.

| Need | Canonical entry point |
| --- | --- |
| Setup and contribution workflow | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Source ownership, search recipes, and task routing | [Navigation](docs/agents/navigation.md) |
| Pipeline, defaults, and boundaries | [Architecture](docs/architecture.md) |
| Commands, labs, generators, and compatibility shims | [Tooling](docs/agents/tooling.md) |
| Public library and CLI recipes | [DocC catalog](Sources/Aski/Aski.docc/Aski.md), [CLI guide](Sources/Aski/Aski.docc/CommandLine.md) |
| Documentation discovery and where to edit it | [Docs hub](docs/README.md) |
| Task state and task edits | [Backlog workflow](docs/agents/backlog.md) |

## Commands

Run from the repository root. [justfile](justfile) owns recipes; `Makefile` forwards
the same names and still requires `just`.

```bash
just --list                    # discover recipes
just docs-check                # portable documentation paths, images, and anchors
just check-fast                # native inner loop; not the acceptance gate
just check                     # authoritative full local gate
just test-infra                # portable script tests; no Apple runtime coverage
just doctor --check toolchain  # targeted environment diagnostic
```

`just check` runs format → one build → structural checks → core tests → serial media
tests → isolated deadlock sentinels → DocC. Keep the build-once ordering and
`ASKI_SKIP_BUILD=1` reuse. Full `just doctor` also resolves, validates, and checks
regenerated artifacts; it is more than a toolchain probe. See
[validation](docs/agents/validation.md) for commands, generated files, and limitations.

Run the full local `just check` before committing or opening a PR. If the environment
cannot run it, state exactly which checks ran and which did not. Portable checks do
not establish Apple rendering or snapshot parity. There is no hosted CI workflow.

## Hard rules

- **Preserve `ASCII*` API names.** The brand is Aski; ASCII names describe the medium.
- **Public does not mean API-frozen.** Useful source/output breaks are acceptable
  pre-1.0. Explain them in [CHANGELOG.md](CHANGELOG.md) and migration guidance.
- **Keep strict concurrency warning-free.** Upstream `package-benchmark` plugin
  `Path`→`URL` deprecation warnings under `.build/checkouts/` are an accepted exception;
  do not change dependencies just to silence those warnings.
- **Regenerate changed Metal kernels.** Run `just regen-kernels` and commit
  [default.metallib](Sources/Aski/Resources/Kernels/default.metallib).
- **Preserve benchmark budgets.** Do not loosen thresholds in
  [AskiBenchmarks](Benchmarks/AskiBenchmarks/) without a justified performance reason
  in the commit message. Valid benchmark evidence is not a passing budget.
- **Changed frozen-reference goldens need a no-harm census in the same PR.** Run
  selection-ceiling before/after (MAE and GMSD), commit the CSV with re-recorded goldens,
  and retain the pre-change build until measured. The reference recipe is
  [FrozenRenderReference.swift](Tools/AskiToolSupport/FrozenRenderReference.swift).
  See [research methodology](docs/agents/research-methodology.md).
- **A KILL verdict must leave production.** Preserve the rule, note, results, and Git
  history; remove the production branch after named replay dependencies close.
  Pending or inconclusive arms stay lab-only or behind `@_spi(AskiResearch)`.
- **Literature can open an arm; Aski evidence promotes it.** Freeze the control and
  decision rule. A replacement should remove old complexity unless a concrete product
  use justifies keeping both. Do not infer a universal benefit from a fixture result.
- **Keep abstractions tied to current needs.** No speculative SDK layers, compatibility
  scaffolding, or public APIs without a concrete app use or pipeline simplification.
- **Document the current surface.** Distinguish ordinary APIs, experimental policies,
  labs, and research SPI. Link canonical detail; retain research caveats and attribution.
  Add new entry points to the [docs hub](docs/README.md) and [llms.txt](llms.txt).
- **Respect the package layout.** Auxiliary targets live in `Tools/`, `Benchmarks/`,
  and `Tests/`; inspect `Package.swift` before assuming a `Sources/<target>` path.
- **Record releases before tags.** Commit the matching changelog and
  `docs/release-notes/<tag>.md` before a `v*` tag. Evidence belongs to the revision
  actually checked, not later commits.
- **Edit tasks through `backlog`, never by hand.** Follow the
  [backlog guide](docs/agents/backlog.md); the checked-in task state is authoritative.
- **Keep Blotter public and append-only.** No secrets or absolute paths in the ledger.

## Repo map

Use [Navigation](docs/agents/navigation.md) for subsystem roles and task-to-code/test
routes. The [generated source map](docs/repo-map.generated.md) indexes top-level
Swift declarations under `Sources/Aski/`; it does not index tools or tests. Regenerate
it with `just regen-repo-map`, never by hand.

## Tools

Use `aski render` / `aski inspect` for ordinary still-image work and `aski lab …`
for research. [Tooling](docs/agents/tooling.md) owns the full inventory and canonical
invocations. Historical `Aski*Lab` names are shims only for surviving commands.
Removed runners require their recorded revisions; they are not current entry points.

## Blotter

Run `blotter list` before work. The committed `.blotter.jsonl` is a public v2 ledger,
managed with [blotter](https://github.com/BigCactusLabs/blotter) (`cargo install
blotter-cli`, version 1.0+). Read the ledger directly if the CLI is unavailable;
do not fabricate ledger records.

File a cut when friction is transferable, consequential, recurring, misleading, or
systemic. Skip typos, quoting slips, ordinary compiler feedback, and one-off mistakes.
Record findings with `blotter dogear`; use `blotter resolve` or `blotter promote` when
addressed. `blotter schema` documents fields and `blotter --help` lists commands.
Attach `--cmd`, `--exit`, or `--stderr-file` for relevant tool failures, without raw
environment dumps. Do not file system or internal friction. Run
`blotter doctor --leaks` before pushing when the CLI is available.
