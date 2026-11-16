---
id: ASKI-76
title: >-
  Decide pre-1.0 ASCIICharacterSet extension boundary and close residual public
  research API
status: Done
assignee:
  - '@codex'
created_date: 2026-09-04 13:00
updated_date: '2026-11-15T19:45:00Z'
labels:
  - api
  - architecture
  - glyphs
  - pre-1.0
dependencies:
  - ASKI-68
  - ASKI-71
references:
  - Sources/Aski/ASCIICharacterSet.swift
  - Sources/Aski/CharacterSets/GlyphBank.swift
  - Sources/Aski/RenderingOptions.swift
  - Sources/Aski/Aski.docc/CharacterSets.md
priority: medium
type: enhancement
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-71 fixed the important internal problem: converters and library-owned character sets now share one immutable validated `GlyphBank`, while external `ASCIICharacterSet` conformers are snapshotted once at the converter boundary. The remaining question is public API shape, not production correctness. `ASCIICharacterSet` still exposes the parallel matcher representation (`brightnessValues`, `rawDensityValues`, and `shapeVectorLanes`) even though the new bank owns those invariants internally, and `rawDensityValues` is retained primarily for research/historical replay rather than the current production matcher.

There is also one small experiment-surface leak left after ASKI-68: `RenderingOptions.shapeQueryPolarity` is SPI-only, but its `ShapeQueryPolarity` type is an ordinary public enum. Before 1.0, decide intentionally whether third-party charset authors are supposed to supply Aski's matcher representation forever. Breaking change is allowed in this task if it produces a materially cleaner long-term contract. Do not start another broad glyph/refactor campaign: keep the current internal `GlyphBank` unless a narrower public boundary demonstrably removes exposed representation without reintroducing duplicate ownership.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Inventory the complete public charset/research surface and all in-repo consumers at a named commit. State explicitly which fields are product extension points, which exist only for current matcher implementation, and which survive only for research/replay.
- [x] #2 Remove the ordinary-public `ShapeQueryPolarity` leak by making the type research SPI or otherwise ensuring no normal public API references it; preserve the SPI experiment behavior and default bytes.
- [x] #3 Make an explicit KEEP or REPLACE decision for the public `ASCIICharacterSet` matcher arrays before 1.0. KEEP means documenting them as an intentional expert-level low-level extension contract with construction/snapshot invariants. REPLACE means introducing the smallest public charset input contract that does not require callers to manufacture Aski's internal matching representation.
- [x] #4 If REPLACE, use the pre-1.0 breaking-change window: migrate built-ins and tests in one change, provide a concise migration note, and delete the superseded public representation rather than carrying two extension APIs indefinitely. Do not expose `GlyphBank` or add a public primitive framework as the replacement.
- [x] #5 Preserve glyph ordering, built-in ShapeData bytes, runtime charset behavior, external-set conversion parity, public rendering defaults, and full `just check`. Any new abstraction must reduce public representation or stored ownership; neutral reshuffling is a KILL.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Inventory the current public charset and research surface at 7cee774. 2. Keep the existing low-level arrays as the expert extension contract and document construction/snapshot invariants. 3. Mark ShapeQueryPolarity as AskiResearch SPI and verify ordinary/SPI clients and symbols. 4. Run focused charset checks, full just check, and record migration and decision evidence.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15: KEEP the expert matcher-array extension contract; scope ShapeQueryPolarity to AskiResearch SPI and package-scope tool helpers that return it. Native check-fast passed 919 tests. Full check passed 1518 core, 178 media, 2 sentinel tests and DocC on base 7cee774 plus the reviewed batch. Ordinary and SPI consumer probes passed expected outcomes; normal graph retains charset arrays among 483 symbols and excludes enum/property. ShapeData and golden files unchanged. AC4 is conditional: REPLACE was rejected, so no alternate representation or migration of arrays was introduced. Source migration for explicitly named research enum is documented.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Kept ASCIICharacterSet arrays as the documented expert contract and RasterizedCharacterSet as font/glyph input. Closed the ordinary-public polarity enum leak without changing defaults, assets or matcher behavior. Full native gate, consumer compilation and symbol-graph checks passed; the dated decision records scope and evidence.
<!-- SECTION:FINAL_SUMMARY:END -->
