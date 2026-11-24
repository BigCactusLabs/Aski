# Validation guide

Use this page to choose a focused check, diagnose a failure, and report what was
actually verified. [CONTRIBUTING.md](../../CONTRIBUTING.md#toolchain-and-snapshot-baseline)
owns setup and the recorded snapshot baseline. [justfile](../../justfile) owns the
commands and exact test filters; [tooling](tooling.md) maps executables to source.

## Choose checks by change

Focused checks shorten the edit loop. Run the full `just check` before committing or
submitting a PR, and explicitly report when the native gate could not run.

| Change | Focused checks and required evidence |
| --- | --- |
| Markdown navigation, README, or agent guide | `just docs-check`; review linked paths and current behavior |
| DocC recipes or public symbols | `just docs-check`, `just docc`; `just test-artifacts` for documentation and command contracts |
| Conversion, palettes, geometry, or other Swift implementation | A named suite with `xcrun swift test --filter 'SuiteName'`, then `just check-fast` |
| Render output, masks, effects, or snapshots | `just test-snapshots`; explain changed goldens and include the frozen-reference no-harm census when applicable |
| GIF/video or motion | `ASKI_SERIAL_MEDIA=1 just test-media`, then `just test-video-deadlock` for the isolated sentinels |
| CLI parsing, metadata, or manifest schema | `just test-artifacts`; read the [command-line contract](../architecture.md#command-line-product) |
| Research note, corpus/result manifest, or lifecycle record | `just research-check`; regenerate the index when its inputs change |
| Declarations in `Sources/Aski/` or the source-map generator | `just regen-repo-map`, then `just repo-map-check` |
| Metal kernel sources | `just regen-kernels`, commit the resulting metallib, then `just release-preflight --check metallib` and the relevant render tests |
| Charset shape vectors | `just audit-vectors --output-dir /tmp/aski-vector-audit`; production regeneration is blocked pending ASKI-78; see [glyph-asset policy](research.md#other-decision-routes) |
| Shell/Python infrastructure or CLI packaging script | `just test-infra`, plus the corresponding real macOS check; fake Apple tools do not validate native behavior |
| Performance claim | `just bench` or a declared subset; retain complete evidence and use [paired comparisons](paired-benchmarks.md) for a candidate decision |
| Release candidate | `just check`, `just release-preflight`, then the [distribution workflow](../guides/distribution.md) |

`SuiteName` is a placeholder. Find the actual suite/test declaration in
[Tests/AskiTests](../../Tests/AskiTests/) before running a filtered command; a successful
empty selection is not useful evidence. Choose a new output directory for retained
benchmark captures and packaging candidates.

## What the full gate does

`just check` runs the following in fail-fast order:

1. Full-tree Swift formatting.
2. One explicit `xcrun swift build --build-tests`.
3. Portable documentation validation, then research lifecycle/index and source-map
   drift checks, reusing the build for Swift tools.
4. Core tests, excluding media, the deadlock sentinels, and four registry tests already
   covered by the preceding tools. `docsRootMatchesAllowlist` remains in this phase.
5. Media tests matching `GIF|Video|MotionLab`, serialized to avoid media-engine contention.
6. The two video deadlock sentinels, serialized and isolated from the other phases.
7. DocC validation with warnings treated as errors.

The drift checks and test phases use `ASKI_SKIP_BUILD=1` / `--skip-build`. Preserve
that reuse when editing the recipe. The DocC script caches the Aski public symbol graph
under `.build/aski-docc-symbols-cache`, keyed by Aski Swift sources, package configuration,
and the selected toolchain/SDK. A cache miss runs SwiftPM symbol-graph extraction;
every invocation validates the current catalog Markdown, even with a warm graph.

`just check-fast` runs formatting, `test-fast`, then documentation and both drift
checks against that build. Its filter excludes snapshots, media, the named research,
registry, and artifact suites in `justfile`; it does not skip every lab test. It also
omits DocC. `just test` is an unpartitioned Swift test invocation; it does not include
formatting, the structural tools, or DocC and is not the acceptance gate.

The portable docs check needs Python 3. `just test-infra` is separate from `just check`:
run it when changing infrastructure. `just bench` is also separate. Its
`budget_verdict` is `not_evaluated`; a complete capture does not prove a speedup or
satisfy numeric budgets. See [benchmark validation](../benchmark-validation.md).

## What can run without a Mac

The ordinary package, rendering tests, and DocC workflow depend on Apple frameworks
and Xcode. In a Linux environment, these commands provide useful, limited evidence:

```bash
python3 -B Scripts/check-doc-links.py
python3 -B -m unittest discover -s Scripts/tests -p 'test_*.py' -v
git diff --check
```

The Python suite uses the standard library and ordinary shell tools, including Bash,
Git, and tar. It exercises script behavior with disposable repositories and fake Apple
tools, as well as benchmark validation/comparison and probe contracts. It does not
compile the real Swift package, resolve DocC public symbols, execute a Metal kernel,
or measure render quality/performance. Report these checks by name without calling
them a native `just check` pass.

## Generated files

| Input changes | Regenerate | Committed output / follow-up |
| --- | --- | --- |
| Top-level declarations in `Sources/Aski/` | `just regen-repo-map` | [repo-map.generated.md](../repo-map.generated.md); `just repo-map-check` |
| Research-note front matter, corpus/result manifests | `xcrun swift run BuildResearchIndex` | Generated block in [Research/README.md](../Research/README.md) and [index.json](../Research/index.json); `just research-check` |
| [Metal kernels](../../Sources/Aski/Effects/Kernels/) | `just regen-kernels` | [default.metallib](../../Sources/Aski/Resources/Kernels/default.metallib); native byte comparison |
| Built-in glyph raster/vector inputs | `just regen-vectors` after the ASKI-78 policy decision; audit only while blocked | [Resources/ShapeData](../../Sources/Aski/Resources/ShapeData/); review the [drift policy](../Research/2026-09-04-aski51-core-text-drift-policy.md) |
| Intended render output | Existing snapshot-recording workflow for the affected suite | [__Snapshots__](../../Tests/AskiTests/__Snapshots__/); explain each change and attach required quality evidence |

Do not hand-edit generated indexes or silently re-record failing goldens. The
[`FrozenRenderReference`](../../Tools/AskiToolSupport/FrozenRenderReference.swift)
requires a before/after selection-ceiling MAE and GMSD no-harm census in the same PR
when its goldens move. Preserve access to the pre-change build until the comparison
is captured. Deterministic new goldens alone do not establish quality. Follow the
[standing methodology](research-methodology.md).

The docs root allowlist lives in
[IndexCheck.docsRootFailures](../../Tools/BuildResearchIndex/IndexCheck.swift).
New navigation guides belong in `docs/agents/`; adding a new root-level document also
requires registering that path. The existing Swift
[DocumentationLinkTests](../../Tests/AskiTests/DocumentationLinkTests.swift) check local
Markdown file targets; the portable docs check adds navigation coverage without
requiring a Swift build.

## Diagnose a failure

| Symptom | Inspect next |
| --- | --- |
| `xcrun`/Xcode unavailable or wrong Swift minimum | `just doctor --check toolchain`; compare with [Package.swift](../../Package.swift) |
| Snapshot mismatch with unchanged source | Record OS/Xcode/Swift/host and compare the [baseline](../../CONTRIBUTING.md#toolchain-and-snapshot-baseline); do not loosen thresholds to hide drift |
| Research registry or map is stale | Run the matching generator, review its diff, then repeat its check |
| DocC reports a missing public symbol | Confirm the symbol exists and is public; removed APIs use ordinary code spans in historical migration text |
| A Swift Testing test in an async context fails to compile when it calls `ASCIIGrid.renderImage(font:backgroundColor:scale:)` for the plain path | The call resolves to the async throwing effects overload. Pass an argument only the plain overload has, such as `preserveSourceAspect:`, to select the synchronous renderer |
| Formatter warning in project code | Fix it with the selected formatter/configuration; full-tree lint covers `Package.swift`, `Sources`, `Tools`, `Benchmarks`, and `Tests` |
| `package-benchmark` plugin deprecation under `.build/checkouts/` | Known upstream `Path`→`URL` warning; do not rewrite project code to silence it |
| Doctor/DocC reports an active lock | Wait for the active operation; after a forced kill, verify no process is running before removing only the named lock |
| Benchmark exited zero with missing evidence | Read the retained `report.json` and logs; completeness depends on exports and required metrics, not exit status alone |

`just doctor` and `just release-preflight` call the same
[repo-doctor.sh](../../Scripts/repo-doctor.sh). Default checks are `toolchain`,
`package-resolved`, `swift-format`, `research-index`, `repo-map`, `docc`, `metallib`,
`workflow-refs`, and `dirty`. `--check NAME` selects a check; `--skip NAME` removes one.
Both flags are repeatable. A selected/partial check is not a full release preflight.

Doctor resolves dependencies and compares a freshly regenerated Metal library, restoring
the checked-in library afterward. Ordinary interruptions stop the regeneration process
group before restoration; SIGKILL and machine failure cannot be trapped. Doctor and
DocC use per-invocation temporary files and per-checkout locks. Do not clean `.build`,
regenerate kernels, or run overlapping mutations of those outputs during these checks.
Separate worktrees isolate locks and build outputs.

## Report evidence

Record the checked commit, dirty-tree state if relevant, host/toolchain, commands,
results, and anything not run. Visual or performance claims also need their input set,
control, and retained outputs. Verification belongs to the commit actually checked;
later edits need appropriate revalidation. Release packaging, a historical successful
run, or passing portable tests alone cannot establish that a new revision passed the
native acceptance gate.
