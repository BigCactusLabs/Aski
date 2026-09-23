---
id: ASKI-67
title: >-
  Collapse literal exit-test bodies into parameterized tests now that Swift 6.3
  exit tests capture values
status: To Do
assignee: []
created_date: '2026-09-03 03:32'
updated_date: '2026-09-10 04:38'
labels:
  - testing
  - cleanup
dependencies: []
priority: low
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Swift 6.3 (swift-testing PR 1165) lets #expect(processExitsWith:) bodies capture values via an explicit capture list (Sendable + Codable, explicit as-T annotation for non-argument captures). The repo is on tools-version 6.3 / toolchain 6.3.2, so the pre-6.3 workaround — one explicit @Test per trap case with literal values — is no longer required. Tests/AskiTests has about 59 processExitsWith sites, most of them in ASCIICharacterSetBoundaryTests, AnimationExtremeValueTests and AnimationOngoingPatternContractTests. Mechanical cleanup; must not change which traps are covered. Origin: blotter review 2026-09-02, cut bl_7efebdda17d1 (obsolete).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each family of literal-valued exit tests that varies only in the argument is expressed as one @Test(arguments:) with a capture list; the set of covered trap cases is byte-identical (enumerate before and after in the PR)
- [ ] #2 just check green; no test renamed in a way that breaks the deadlock-sentinel or media-phase filters in justfile
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

**Current state:** ASKI-67 is To Do. A live scan finds 43 `processExitsWith` sites across seven test files, not the description’s approximate 59; treat that count mismatch as a pre-edit inventory issue and enumerate the exact trap set before and after. Every current trap site is inside `#if !SWT_NO_EXIT_TESTS`. The groups are: 5 in `ASCIICharacterSetBoundaryTests` (three individual parallel-array mismatches, one empty set, one post-init assignment); 4 in `AnimationExtremeValueTests` (two out-of-range speeds, two materialize frame-cap cases); 30 in `AnimationOngoingPatternContractTests` (four pulse and four wave values at AnimationOptions, the same 8 at ASCIIGrid, the same 8 at ASCIIVideoFrame, two empty-grid checks, convertVideo-before-decode, two mutated-options ScheduleBuilder checks, and one mutated-options animate check); and one each in `PaletteTests`, `RasterizedCharacterSetTests`, `ResolvedPaletteTests`, and `TilePaletteTests`.

**Start here:** `Sources/Aski/CharacterSets/GlyphBank.swift` owns the character/brightness/raw-density/15-lane invariant; `ASCIIConverter.characterSet` re-adapts on `didSet`. `CyclingOptions.validateSpeed` rejects non-finite, non-positive, and unrepresentable speeds. `AnimatedASCIIGrid.materialize(frameRate:)` guards the 10,000-frame cap. `OngoingPattern.validate()` is required at every accepting boundary, with `PatternEvaluator.ongoingAlpha` retained as a backstop. `convertVideo` calls `pattern?.validate()` before creating the decoder, so the fail-before-side-effect test must remain distinct. Palette fixed constructors, rasterized character sets, and the internal OKLAB initializer all require non-empty input.

**Constraints and dependencies:** Parameterize only literal families that vary by the bad argument. Preserve every trap and its target boundary: malformed parallel arrays, empty inputs, post-construction mutations, empty-grid validation, and conversion rejection before decoding. Keep the explicit `SWT_NO_EXIT_TESTS` guard. Swift 6.3 exit tests need the explicit capture-list form described by the task; captured values must meet the testing API’s Sendable/Codable rule, with an explicit `as-T` annotation where a non-argument capture needs it. Do not rename tests in a way that breaks the `justfile` media/deadlock filters.

**Validation to run:** Enumerate test names and literal values before/after, then run the focused suites and `just check`; the full gate’s `test-without-video-deadlock`, serial `test-media`, and isolated `test-video-deadlock` commands are defined in `justfile`. Verify that the unique convertVideo test still fails before decode and that no covered trap disappears.

**First step:** Make a read-only inventory table from the seven files, mark parameterizable versus unique side-effect/guard cases, and only then collapse duplicated `@Test` bodies.

Source map: `Tests/AskiTests/ASCIICharacterSetBoundaryTests.swift`, `Tests/AskiTests/AnimationExtremeValueTests.swift`, `Tests/AskiTests/AnimationOngoingPatternContractTests.swift`, `Sources/Aski/Animation/OngoingPattern.swift`, `Sources/Aski/Video/ASCIIVideoConverter.swift`, `Sources/Aski/Animation/AnimatedASCIIGrid.swift`.
<!-- SECTION:NOTES:END -->
