---
id: ASKI-22
title: Sync effects render accepts blend modes the async overload rejects
status: Done
assignee: []
created_date: '2026-08-19 05:24'
updated_date: '2026-08-24 15:36'
labels:
  - correctness
  - effects
  - api-contract
dependencies: []
references:
  - Sources/Aski/Effects/ASCIIGrid+Effects.swift
  - Sources/Aski/Effects/Internal/BlendModeMapping.swift
priority: low
type: bug
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ASCIIGrid.renderImage(font:backgroundColor:scale:composition:lighting:effects:)` exists in a sync and an async throws form that are documented as the same render. They disagree on an unknown `CGBlendMode`.

The async overload calls `validateComposition`, which uses `BlendModeMapping.isKnown` (returns false on `@unknown default`) and throws `EffectError.unsupportedBlendMode`. The sync overload never calls `validateComposition` at all; it goes straight to `makeEffectGraph`, where `BlendModeMapping.kernel(for:)` returns `.sourceOver` on its own `@unknown default`. So the same CompositionOptions throws on one path and silently renders as normal blending on the other. The same asymmetry applies to `colorOverlay.blendMode`.

Reachable because `CGBlendMode` is an imported C enum: `CGBlendMode(rawValue:)` can produce a value outside the 30 known cases, and a future SDK could add one.

The sync path deliberately absorbs individual kernel failures — that is stated in the source and is not in question here. Composition validation is a different thing: it is a caller-input check the async path performs and the sync path skips entirely, so the two overloads are not interchangeable the way the API implies.

Low severity — no crash, no corruption, and the silent fallback is a reasonable behaviour on its own. What needs settling is which of the two behaviours is the contract.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The sync and async overloads agree on how an unknown CGBlendMode is handled — either both fall back to sourceOver or the sync path gains an equivalent documented rejection
- [x] #2 The same rule covers CompositionOptions.characterBlendMode and ColorOverlay.blendMode
- [x] #3 The chosen behaviour is documented on the sync overload, since it cannot throw
- [x] #4 Regression asserts sync and async agree for a CGBlendMode(rawValue:) outside the known set, and all known blend modes render byte-identically
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24: implemented and merged to main in PR #28 (batch-validation wave, merge b835160); all ACs were already checked — status flip only.
<!-- SECTION:NOTES:END -->
