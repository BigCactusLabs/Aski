---
id: ASKI-76
title: Decide pre-1.0 ASCIICharacterSet extension boundary and close residual public research API
status: To Do
assignee: []
created_date: '2026-09-04 13:00'
updated_date: '2026-09-04 13:00'
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
- [ ] #1 Inventory the complete public charset/research surface and all in-repo consumers at a named commit. State explicitly which fields are product extension points, which exist only for current matcher implementation, and which survive only for research/replay.
- [ ] #2 Remove the ordinary-public `ShapeQueryPolarity` leak by making the type research SPI or otherwise ensuring no normal public API references it; preserve the SPI experiment behavior and default bytes.
- [ ] #3 Make an explicit KEEP or REPLACE decision for the public `ASCIICharacterSet` matcher arrays before 1.0. KEEP means documenting them as an intentional expert-level low-level extension contract with construction/snapshot invariants. REPLACE means introducing the smallest public charset input contract that does not require callers to manufacture Aski's internal matching representation.
- [ ] #4 If REPLACE, use the pre-1.0 breaking-change window: migrate built-ins and tests in one change, provide a concise migration note, and delete the superseded public representation rather than carrying two extension APIs indefinitely. Do not expose `GlyphBank` or add a public primitive framework as the replacement.
- [ ] #5 Preserve glyph ordering, built-in ShapeData bytes, runtime charset behavior, external-set conversion parity, public rendering defaults, and full `just check`. Any new abstraction must reduce public representation or stored ownership; neutral reshuffling is a KILL.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Freeze the current public API inventory and representative external-conformer tests at current main. Include source-compat examples for a minimal custom charset and a runtime rasterized charset.
2. Close the isolated `ShapeQueryPolarity` visibility leak first and verify public-symbol/API output no longer exposes the research-only type outside SPI.
3. Evaluate two bounded charset contracts: KEEP the current low-level arrays intentionally, or REPLACE them with a caller-facing glyph/source description from which the internal bank can be built. Reject designs that expose `GlyphBank`, require a second permanent representation, or create per-conversion reconstruction.
4. Choose KEEP or REPLACE on API longevity, custom-set ergonomics, invariant ownership, performance, and migration cost. If KEEP, strengthen docs/tests and stop. If REPLACE, perform the breaking migration now and remove the old protocol requirements in the same task.
5. Record the decision and migration surface, run focused charset/API/golden tests plus the full local gate, and close without expanding matcher scope or revisiting ASKI-71 internals absent measured need.
<!-- SECTION:PLAN:END -->
