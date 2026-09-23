---
id: ASKI-20
title: Mask rasters escape an inout array pointer into a retained CGContext
status: Done
assignee: []
created_date: '2026-08-19 05:22'
updated_date: '2026-08-24 15:36'
labels:
  - correctness
  - masking
  - memory-safety
dependencies: []
references:
  - Sources/Aski/Masking/MaskSampler.swift
  - Sources/Aski/Masking/CoverageImageBuilder.swift
  - Sources/Aski/CellSampling.swift
  - Tools/AskiHDRLab/HDRArtifacts.swift
priority: medium
type: bug
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Three production sites build a CGContext over a Swift array with `CGContext(data: &bytes, ...)` and then keep using the context after that call returns:

- Sources/Aski/Masking/MaskSampler.swift:55 — context created, then `context.draw(options.image, ...)` writes through the pointer, then `bytes` is read back to build the coverage array.
- Sources/Aski/Masking/CoverageImageBuilder.swift:21 and :68 — `bytes` is filled, the context is created over it, then `context.makeImage()` reads through the pointer.
- (Also Tools/AskiHDRLab/HDRArtifacts.swift:157.)

Swift's inout-to-pointer conversion only guarantees the pointer is valid for the duration of the call it is passed to. CGContext stores `data` and dereferences it later, so every write and read after construction is undefined behaviour: the compiler is free to hand the callee a temporary buffer and copy back, in which case the mask silently comes out all zeros (or all 255) rather than crashing. It happens to work on the current toolchain, which is exactly what makes it a latent defect rather than a visible one.

The correct pattern is already used elsewhere in the same module: `readRGBA8` in CellSampling.swift wraps the whole context lifetime in `pixels.withUnsafeMutableBytes { ... }`, and `CellRasterBuilder` passes `data: nil` and lets CoreGraphics own the buffer.

Silent-corruption class, not a crash class: if it ever bites, masks and coverage images degrade to a constant with no error, so the failure surfaces as 'the mask did nothing' rather than as a diagnosable fault. That is the reason to fix it before it can be triggered by a toolchain change.

The 13 test-only occurrences share the pattern; converting them is optional, but leaving them makes the rule harder to hold.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 MaskSampler.sample and both CoverageImageBuilder builders own their pixel buffer for the full context lifetime — via withUnsafeMutableBytes, a manually allocated buffer, or data: nil — with no inout-to-pointer conversion escaping its call
- [x] #2 Tools/AskiHDRLab/HDRArtifacts.swift is corrected the same way
- [x] #3 Mask coverage, soft/hard edges, invert, and fallback rendering produce byte-identical output before and after; existing mask tests and snapshots pass unchanged
- [x] #4 A short note in the masking source records the rule and points at readRGBA8 as the reference pattern, so the fix does not regress
- [x] #5 just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24: implemented and merged to main in PR #28 (batch-validation wave, merge b835160); all ACs were already checked — status flip only.
<!-- SECTION:NOTES:END -->
