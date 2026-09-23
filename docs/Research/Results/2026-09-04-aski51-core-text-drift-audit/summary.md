# Core Text vector drift audit

- Disposition: **NO_TRIGGER**
- Tolerance: `0.00100000005` (strictly greater fires)
- Maximum observed component delta: `0`
- Brightness sort permutation changed: **no**
- Byte-identical sets: 10 of 10
- Sets with byte drift: none

The audit generated every selected v3 binary in memory. It did not write to `Sources/Aski/Resources/ShapeData/`.
A trigger fires if any recorded component delta is greater than `0.001` or if the brightness-sorted scalar order changes.
A snapshot or selection-golden change during an authorized regeneration is a separate trigger.

## Toolchain provenance

- Aski commit: `ef1c08e3e6581c313266a4368a36b5739ab89593`
- macOS: `Version 26.6.2 (Build 25G83)`
- Xcode: `Xcode 26.5; Build version 17F42`
- Swift: `swift-driver version: 1.148.6 Apple Swift version 6.3.2 (swiftlang-6.3.2.1.108 clang-2100.1.1.101); Target: arm64-apple-macosx26.0`
- Command: `BuildStandardVectors --audit --output-dir docs/Research/Results/2026-09-04-aski51-core-text-drift-audit`

## Files

- `set-summary.csv`: per-set byte identity, maximum delta, and order result.
- `glyph-drift.csv`: per-glyph deltas for all stored v3 channels.
