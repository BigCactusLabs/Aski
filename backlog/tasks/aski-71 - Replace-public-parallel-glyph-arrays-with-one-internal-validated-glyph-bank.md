---
id: ASKI-71
title: Replace public parallel glyph arrays with one internal validated glyph bank
status: Done
assignee:
  - '@codex'
created_date: '2026-09-04 03:45'
updated_date: '2026-09-04 13:03'
labels:
  - architecture
  - glyphs
dependencies:
  - ASKI-51
  - ASKI-68
  - ASKI-69
references:
  - docs/Research/2026-09-03-future-direction-and-architecture.md
modified_files:
  - Sources/Aski/ASCIICharacterSet.swift
  - Sources/Aski/ASCIIConverter.swift
  - Sources/Aski/ASCIIConverter+Research.swift
  - Sources/Aski/ASCIIConverter+Animation.swift
  - Sources/Aski/Animation/ASCIIConverter+Temporal.swift
  - Sources/Aski/Algorithms/AlgorithmKernel.swift
  - Sources/Aski/Algorithms/DotMatrixKernel.swift
  - Sources/Aski/Algorithms/LogPolarKernel.swift
  - Sources/Aski/CharacterSets/GlyphBank.swift
  - Sources/Aski/CharacterSets/StandardCharacterSet.swift
  - Sources/Aski/CharacterSets/RasterizedCharacterSet.swift
  - Tests/AskiTests/GlyphBankConversionGoldenTests.swift
  - Tests/AskiTests/GlyphBankTests.swift
  - Tests/AskiTests/StandardCharacterSetV2ParseTests.swift
  - Sources/Aski/Aski.docc/CharacterSets.md
  - docs/architecture.md
  - docs/repo-map.generated.md
priority: medium
type: enhancement
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASCIICharacterSet exposes characters plus several independently indexed data arrays. The converter now validates alignment at its boundary (ASKI-53), but ownership and provenance remain distributed across built-in binary assets and runtime Core Text rasterization. Introduce one internal immutable owner only after ASKI-51 settles raster drift and ASKI-69 settles which masks or matching metadata the surviving matcher needs.

GlyphBank is an internal working name, not a public abstraction. Start with a validated snapshot or adapter over the surviving structure-of-arrays representation and require exact behavioral parity. Each constructed named, runtime, or external character set owns one validated bank; there is no global per-font cache or subset indirection. Do not commit a new mask format or change ShapeData .bin until evidence requires it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Define one internal immutable owner per constructed character set for glyph identity, density, surviving matcher metadata, raster geometry, placement/baseline, font provenance, antialiasing/color-space convention, and asset format version; do not add a global per-font cache or subset indirection.
- [x] #2 Built-in committed data and runtime user-font data use explicit deterministic and dynamic paths consistent with ASKI-51; a bank does not claim Core Text stability.
- [x] #3 Migrate construction and conversion boundaries without changing required public ASCII* type names, glyph ordering, default picks, rendered bytes, or frozen goldens.
- [x] #4 Remove obsolete channel arrays and duplicate invariant checks instead of wrapping them indefinitely; report the net production line and field count.
- [x] #5 Canonical masks or a ShapeData format bump land only if ASKI-69 and ASKI-51 show they are required, with drift, regeneration, migration, memory, and selection-parity coverage.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Freeze 20 pre-migration conversion digests for ten built-ins across log-polar and dot-matrix, and prove the frozen test passes on untouched production code.
2. Add one immutable internal GlyphBank reference owner with conservative provenance and migrate StandardCharacterSet, RasterizedCharacterSet, ASCIIConverter, and matcher kernels without changing the public four-array protocol or loop order.
3. Add validation for shared bank identity, storage sharing, provenance, malformed sets, ShapeData byte identity, conversion goldens, parity, and temporal paths.
4. Update architecture documentation and the generated repository map, then report field, line, and memory deltas.
5. Run focused serial checks, stage the complete tree, run the authoritative full gate, finalize ASKI-71 through Backlog CLI, and commit locally without pushing.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Pre-edit parity: froze and passed 20 built-in-by-algorithm conversion digests on untouched 27b8cec before production changes; record mode was removed. Implementation: one immutable checked-Sendable four-array GlyphBank reference with discriminated committed/runtime/external provenance; StandardCharacterSet and RasterizedCharacterSet hold one pointer and project the public four-array protocol through it; library sets and their converters share exact bank identity; custom conformers get one validated bank at converter initialization or reassignment. Ordinary, ranked, residual, research, animation, and temporal paths reuse that bank without per-conversion or per-cell bank allocation. Committed v1-v3 parsing, raw density, v3 retired-byte skips, ShapeMatching guards, and CharacterSetSnapshot remain intact; no CTFont, masks, ShapeData v4, subset indirection, or Package.swift changes. Focused serial validation after the reference-owner change: 74 tests in 14 suites passed, including malformed boundary subprocesses, v1/v2/v3 decoding, provenance, bank identity and four-buffer pointer identity, stable identity across repeated conversions, valid reassignment, 20 digests, both kernels, ranked/residual, serial/parallel, and temporal parity. All 10 ShapeData binaries are byte-identical to 27b8cec. arm64 value sizes: StandardCharacterSet 32 to 8 bytes, RasterizedCharacterSet 32 to 8 bytes, DefaultConverter 81 to 65 bytes. Production Swift delta: +130 lines. Parallel-array declarations: 8 to 4; concrete charset stored fields: 8 to 2; total bank-related stored declarations including provenance and converter cache: 8 to 8.

Authoritative validation: full just check passed on the exact staged tree after the final focused run. The gate completed format, one strict build, research and repository-map drift checks, 1,400 core tests in 213 suites, the serial media partition, both isolated deadlock sentinels, and DocC with exit 0.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architectural review
created: 2026-09-04 13:03
---
Post-refactor review accepts the internal `GlyphBank` result as the long-term invariant owner; do not reopen ASKI-71 to chase a different internal storage abstraction. The remaining concern is only the pre-1.0 public extension boundary: `ASCIICharacterSet` still exposes matcher-representation arrays even though converters now snapshot them into the bank. ASKI-76 owns the explicit KEEP-or-REPLACE decision and the small `ShapeQueryPolarity` public/SPI cleanup. Any ASKI-76 implementation should preserve this task's single-bank ownership and parity guarantees rather than expose `GlyphBank` publicly.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced duplicated concrete character-set array storage with one internal immutable checked-Sendable GlyphBank reference shared by library sets, converters, and matcher kernels. Preserved the public ASCII protocol projections, glyph order, all ten ShapeData binaries, v1-v3 parsing, raw density, and every frozen conversion/render path. Verified with the pre-edit 20-case digest, 74 focused tests, identity and COW buffer checks, exact memory measurements, independent architecture review, and a clean full just check.
<!-- SECTION:FINAL_SUMMARY:END -->
