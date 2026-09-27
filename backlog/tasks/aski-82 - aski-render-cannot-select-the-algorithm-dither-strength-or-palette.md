---
id: ASKI-82
title: 'aski render cannot select the algorithm, dither strength or palette'
status: To Do
assignee: []
created_date: '2026-09-27 17:35'
labels:
  - cli
  - docs
dependencies: []
references:
  - Tools/AskiToolSupport/ToolImageConversion.swift
  - Tools/AskiToolSupport/AskiDemoCommand.swift
  - Sources/Aski/Aski.docc/Algorithms.md
  - Sources/Aski/Aski.docc/CommandLine.md
priority: low
type: enhancement
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found 2026-09-27 from the bcl-web canyon strip (Aski HEAD 6b6d251).

WHAT IS MISSING
`ToolImageConversion` (Tools/AskiToolSupport/ToolImageConversion.swift:18) builds `ASCIIConverter(characterSet:, palette: BuiltInPalette.fullColor)` with the default algorithm (.logPolar) and default `RenderingOptions`. `aski render` exposes `--charset` but no `--algorithm`, `--coverage`, `--palette`, `--brightness` or `--contrast`. The docs recommend dotMatrix for minimal, blocks, dots and braille, but that path, and Floyd–Steinberg dithering, can only be tried through the library. Given ASKI-79 (logPolar blank for minimal/dots) the CLI currently has no working route for those two sets at all.

CONCRETE CONSUMER
bcl-web generates white-on-black glyph masks (monochrome palette) for its canyon strip and had to write a Swift harness to compare algorithms and dither strengths.

RELATED DOCS MISMATCH
Algorithms.md describes dotMatrix as "Brightness-based matching with Floyd–Steinberg dithering", but `coverage` (the FS strength) defaults to 0, so a default dotMatrix conversion does not dither. Measured on the bcl-web photo at 288 columns, minimal/dotMatrix: 76.0% of non-blank cells sit in same-glyph runs of 5 or more at coverage 0, 42.5% at coverage 1 (standard: 33.2% vs 18.9%).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 aski render accepts --algorithm logPolar|dotMatrix and --coverage 0...1 with the same bound validation as other numeric arguments, and --write-manifest records both; the command-surface golden is updated
- [ ] #2 A decision is recorded on whether --palette (at least monochrome and fullColor) belongs on the CLI
- [ ] #3 Algorithms.md states that dotMatrix does not dither at the default coverage of 0, or the default changes under the golden and no-harm rules
- [ ] #4 CommandLine.md documents the new flags
<!-- AC:END -->
