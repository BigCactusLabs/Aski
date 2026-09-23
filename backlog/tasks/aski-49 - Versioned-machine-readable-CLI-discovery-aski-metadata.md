---
id: ASKI-49
title: 'Versioned machine-readable CLI discovery: aski metadata'
status: To Do
assignee: []
created_date: '2026-08-21 02:15'
updated_date: '2026-09-10 04:38'
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
- [ ] #1 Deterministic v1 output with committed schema and sync test against the live command tree
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

**Current state:** ASKI-49 is To Do and follows completed ASKI-48. The current one-package manifest has 8 explicitly declared executable products plus the `Aski` library (26 target declarations), with additional executable targets for the demo, tile matrix, and generators; ASKI-48 kept seven importable lab modules and byte-thin replay runners in that root package. The live root command is `aski` with `render` (also the default), `inspect`, and `lab`. `lab` has exactly `color`, `motion`, `video`, `accessibility`, `decolor`, `hdr`, and `preset`. Current child vocabulary is: color’s 18 research commands including `arbiter`; motion’s `animate`, `temporal-prior`, `source-tether`; video as one command; accessibility `audit`; decolor and hdr each `evaluate`/`check`; preset `ab`, `probe-stimuli`, `probe-score`.

**Start here:** Use `Tools/AskiCLI/AskiCommand.swift` plus each lab command configuration as the live source of truth. `Tests/AskiTests/UnifiedLabCommandTests.swift` hard-codes the seven namespace names and seven replay products, checks built help/version/bare-exit parity, runner thinness, and Bash/Zsh/Fish completion. `Tests/AskiTests/CommandSurfaceGoldenTests.swift` maps canonical/replay surfaces to ArgumentParser `_dumpHelp()` JSON and byte-compares `Tests/AskiTests/Goldens/command-surface.json`; a new metadata sync test must derive from the same live configurations rather than a second hand-maintained command list.

**Constraints and dependencies:** ASKI-48 is Done and its ASKI-70 decision keeps the importable labs, generators, `AskiToolSupport`, CLI, and tests in one package. Reuse `StableJSON`: pretty printed, sorted keys, unescaped slashes, one trailing newline. Existing versioned machine records are `AskiInspectionReport` and `AskiRenderManifest`, with Draft 2020-12 schemas under `docs/assets/schemas/`; both use additive v1 compatibility and schema-version bumps for changed meaning. `ToolVersion.current` resolves the checkout SHA through `GitSHA.resolve` in the current working directory. Keep timestamps, hostnames, absolute environment paths, and network-derived values out of deterministic metadata.

**Validation to run:** Add a committed Draft 2020-12 metadata schema and a test that emits the same bytes twice, checks one newline/sorted-key output and schemaVersion 1, and compares the command tree, visible arguments/defaults, aliases, stable/research classification, replay mappings, and checkout revision against live configurations and manifest products. Run the canonical `just test-artifacts` selection and `just check`; update prose/golden coverage only for intentional surface changes and preserve the one-build full-gate recipe.

**First step:** Freeze the metadata field vocabulary and replay/alias policy from the current `AskiCommand` configurations, then implement the producer and sync test in the existing tool-support/CLI boundary. No metadata schema or producer exists yet.

Source map: `Tools/AskiColorLab/AskiColorLabCommand.swift`, `Tools/AskiToolSupport/StableJSON.swift`, `docs/assets/schemas/aski-inspect-v1.schema.json`, `Tests/AskiTests/AskiInspectCommandTests.swift`.
<!-- SECTION:NOTES:END -->
