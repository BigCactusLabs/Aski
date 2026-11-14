---
id: ASKI-49
title: 'Versioned machine-readable CLI discovery: aski metadata'
status: Done
assignee: []
created_date: 2026-08-21 02:15
updated_date: '2026-11-14T17:10:00Z'
labels: []
dependencies:
  - ASKI-48
references:
  - 'Source tracker issue #24 (not migrated)'
priority: low
type: enhancement
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Migrated from GitHub issue #24 (harvested from closed PR #21). A deterministic versioned aski metadata command emitting the command tree — paths, aliases, visible arguments, defaults, stable/research classification, replay mappings, checkout revision — in the spirit of cargo metadata. Complements inspect (one conversion) and the render manifest (one render). Reuse the schemaVersion/deterministic-JSON conventions from PR #20 (sorted keys, trailing newline, additive-only v1, Draft 2020-12 schema in the governed docs subtree, sync test against the live tree). Sequenced after the lab tree (ASKI-48) so the contract describes the final vocabulary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Deterministic v1 output with committed schema and sync test against the live command tree
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Freeze a small additive-v1 projection of the live ArgumentParser tree: paths, aliases, visible arguments and help defaults, stability, default edges, replay prefix mappings and current checkout revision.
2. Add aski metadata, schema and independent live-tree/output sync tests; preserve render as the default command and avoid public Aski SDK additions.
3. Document the contract and record the intentional command-surface change through the existing native recorder.
4. Run targeted artifact tests and the full unchanged local gate, then integrate only the verified source.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

**Current state:** ASKI-49 is To Do and follows completed ASKI-48. The current one-package manifest has 8 explicitly declared executable products plus the `Aski` library (26 target declarations), with additional executable targets for the demo, tile matrix, and generators; ASKI-48 kept seven importable lab modules and byte-thin replay runners in that root package. The live root command is `aski` with `render` (also the default), `inspect`, and `lab`. `lab` has exactly `color`, `motion`, `video`, `accessibility`, `decolor`, `hdr`, and `preset`. Current child vocabulary is: color’s 18 research commands including `arbiter`; motion’s `animate`, `temporal-prior`, `source-tether`; video as one command; accessibility `audit`; decolor and hdr each `evaluate`/`check`; preset `ab`, `probe-stimuli`, `probe-score`.

**Start here:** Use `Tools/AskiCLI/AskiCommand.swift` plus each lab command configuration as the live source of truth. `Tests/AskiTests/UnifiedLabCommandTests.swift` hard-codes the seven namespace names and seven replay products, checks built help/version/bare-exit parity, runner thinness, and Bash/Zsh/Fish completion. `Tests/AskiTests/CommandSurfaceGoldenTests.swift` maps canonical/replay surfaces to ArgumentParser `_dumpHelp()` JSON and byte-compares `Tests/AskiTests/Goldens/command-surface.json`; a new metadata sync test must derive from the same live configurations rather than a second hand-maintained command list.

**Constraints and dependencies:** ASKI-48 is Done and its ASKI-70 decision keeps the importable labs, generators, `AskiToolSupport`, CLI, and tests in one package. Reuse `StableJSON`: pretty printed, sorted keys, unescaped slashes, one trailing newline. Existing versioned machine records are `AskiInspectionReport` and `AskiRenderManifest`, with Draft 2020-12 schemas under `docs/assets/schemas/`; both use additive v1 compatibility and schema-version bumps for changed meaning. `ToolVersion.current` resolves the checkout SHA through `GitSHA.resolve` in the current working directory. Keep timestamps, hostnames, absolute environment paths, and network-derived values out of deterministic metadata.

**Validation to run:** Add a committed Draft 2020-12 metadata schema and a test that emits the same bytes twice, checks one newline/sorted-key output and schemaVersion 1, and compares the command tree, visible arguments/defaults, aliases, stable/research classification, replay mappings, and checkout revision against live configurations and manifest products. Run the canonical `just test-artifacts` selection and `just check`; update prose/golden coverage only for intentional surface changes and preserve the one-build full-gate recipe.

**First step:** Freeze the metadata field vocabulary and replay/alias policy from the current `AskiCommand` configurations, then implement the producer and sync test in the existing tool-support/CLI boundary. No metadata schema or producer exists yet.

Source map: `Tools/AskiColorLab/AskiColorLabCommand.swift`, `Tools/AskiToolSupport/StableJSON.swift`, `docs/assets/schemas/aski-inspect-v1.schema.json`, `Tests/AskiTests/AskiInspectCommandTests.swift`.

Audit 2026-11-12: PR #20, closed PR #21 and issue #24 cited here are private-history numbers; public #20 is the v0.8.0 release and #21 is ASKI-98..100.

2026-11-14: Implemented deterministic additive-v1 aski metadata with the live visible command tree, help defaults, default subcommands, stability and seven replay mappings; render remains the default. Independent CLI/tree/replay tests and the Draft 2020-12 schema validate 47 commands. Six invalid schema variants were rejected. Native check-fast passed 942 tests; metadata/unified 10 and artifact selection 45 passed. Full unchanged just check passed on base 186e36d plus the final eleven metadata files: 1543 core, 178 media, two sentinels and DocC. Only the intentional 52-line metadata command golden changed; production render goldens and dependency pins are unchanged. Lead verified integrated files byte-for-byte against the tested snapshot. Prior cross-family source review remained unavailable; lead review and local gates passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added versioned machine-readable CLI discovery with deterministic output, schema, live-tree synchronization tests and current public documentation. Full local gate and actual schema validation pass.
<!-- SECTION:FINAL_SUMMARY:END -->
