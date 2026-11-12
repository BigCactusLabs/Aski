---
id: ASKI-5
title: Enforce representative conversion and media performance budgets
status: In Progress
assignee: []
created_date: 2026-08-18 18:01
updated_date: '2026-10-27T15:59:00Z'
labels:
  - performance
  - benchmarks
  - tooling
dependencies:
  - ASKI-1
  - ASKI-2
  - ASKI-4
priority: medium
type: task
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The benchmark suite contains broad measurement coverage, but only a minority of cases have enforceable thresholds and the full repository gate does not run benchmarks. Establish stable regression budgets for the optimized conversion and media paths, and provide a canonical offline gate that fails when those representative budgets regress.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Representative static conversion, large-image conversion, image rendering, identity and rotated video, and long-GIF cases have explicit wall-time, CPU-time, allocation, or resident-memory budgets appropriate to each workload.
- [ ] #2 Thresholds are based on repeated isolated and contended measurements with recorded headroom and do not hide regressions by loosening an existing budget.
- [ ] #3 Cases that remain measurement-only have a documented variance or signal-quality reason instead of being silently unenforced.
- [ ] #4 A documented canonical offline command runs the enforced performance subset and exits nonzero on a breached budget.
- [ ] #5 The chosen gate placement protects release work without making check-fast flaky or unexpectedly adding the complete benchmark-suite runtime to every edit loop.
- [ ] #6 just check and just bench pass with the new enforcement enabled.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Groundwork 2026-10-27: add a portable paired-run readout for complete ASKI-86 evidence, preserving workload/metric identities, provenance, and repeated-run noise. Use it to prepare future budgets; do not select or enforce numeric performance budgets from synthetic tests. Existing preparation/media dependencies remain open.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `Benchmarks/AskiBenchmarks/Benchmarks.swift` registers `convert-gradient-800x600-80cols`, `convert-gradient-2400x1800-120cols`, and `render-image-gradient-80cols`; the default configuration measures wall time, malloc count, and allocated resident memory, but supplies no thresholds. Enforceable examples are concentrated in `AnimationBenchmarks.swift`, `HelmlabBenchmarks.swift`, and `EffectChainBenchmarks.swift`. The animation static-convert budget is wall p50/p90 8 ms, CPU 26 ms, and malloc 36,000; its comments tie the values to five isolated/full-suite/contended runs from 2026-07-13 with headroom.

Start here: `Benchmarks/AskiBenchmarks/VideoPipelineBenchmarks.swift` already registers identity and rotated 720p decode, conversion, encode, serial end-to-end, and one-shot/pipelined end-to-end cases. Its configuration measures wall time, throughput, CPU time, peak resident-memory delta, and malloc count, with one warmup, a three-second duration, and five maximum iterations, but no budget thresholds. `GIFMetadataBenchmarks.swift` measures two metadata scans and a no-op decode over a 120-frame fixture with wall/throughput/CPU/malloc metrics; it has no threshold, resident-memory metric, or full GIF convert/render workload.

Constraints and dependencies: the backlog graph makes ASKI-1 and ASKI-2 (with ASKI-2 depending on ASKI-1) and ASKI-4 prerequisites. Current `Sources/Aski/ImageIOThumbnail.swift` still serializes oversized direct `CGImage` input through PNG, `Sources/Aski/Video/ASCIIVideoDecoder.swift` still materializes a full-resolution oriented image before conversion, and `Sources/Aski/Video/ASCIIGIFConverter.swift` plus `ASCIIGIFEncoder.swift` retain batch rendered GIF frames. Baselines should settle after those path changes while preserving existing threshold headroom and output/fidelity contracts. `Package.swift` declares `AskiBenchmarks` with package-benchmark 1.31..<1.36. The landed media partition in `justfile` serializes GIF/video/motion tests inside `just check`.

Validation to run: the verified full benchmark command is `just bench`, which runs the complete `AskiBenchmarks` target. `just check` and `just check-fast` currently do not invoke it; hosted CI has no benchmark job and is manual-only. Future work must record repeated isolated and contended measurements, document any measurement-only cases, add an enforced subset command, then run `just check` and `just bench` without loosening existing budgets.

First step: freeze the representative fixture matrix and capture current p50/p90 wall, CPU, allocation, and resident-memory results for static, render, identity/rotated video, and long-GIF paths before selecting thresholds or gate placement.

Source map: `Benchmarks/AskiBenchmarks/AnimationBenchmarks.swift`, `Benchmarks/AskiBenchmarks/GIFMetadataBenchmarks.swift`.

### Groundwork delivered — 2026-10-27

Added `Scripts/research/compare-benchmarks.py`, portable regression coverage, and `docs/agents/paired-benchmarks.md`. The reader validates complete ASKI-86 reports and sample hashes, rejects incompatible/missing/reused evidence, and reports per-workload paired changes and run-to-run spread. At least five complete pairs are required for a reviewable numeric series. Budget/adoption verdicts remain explicitly unevaluated; synthetic fixtures do not set thresholds. Existing media/preparation dependencies and every acceptance criterion remain open.
<!-- SECTION:NOTES:END -->
