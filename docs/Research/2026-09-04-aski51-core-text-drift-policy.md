---
title: "ASKI-51 - Core Text ShapeData drift audit and regeneration policy"
slug: "2026-09-04-aski51-core-text-drift-policy"
date: "2026-09-04"
status: "complete"
summary: "The pre-registered read-only audit regenerated all ten ShapeData v3 binaries in memory on macOS 26.6.2, Xcode 26.5, and Swift 6.3.2. All 414 glyphs and every stored channel were byte-identical, the brightness sort order was unchanged, and the escalation trigger did not fire."
subsystem: ["shape-context", "meta"]
related_specs: ["Tools/BuildStandardVectors/BuildStandardVectors.swift", "Tools/BuildStandardVectors/VectorDriftAudit.swift", "docs/agents/research-methodology.md"]
datasets: []
runners: ["BuildStandardVectors"]
results: ["docs/Research/Results/2026-09-04-aski51-core-text-drift-audit"]
---

# ASKI-51 - Core Text ShapeData drift audit and regeneration policy

## Decision before measurement

The audit generates each selected built-in character set in memory through the same encoder as
`regen-vectors`. It compares the fresh v3 binary with the committed binary by Unicode scalar. It
records byte identity, the largest absolute delta in each stored channel, and the brightness-sorted
scalar order. It writes reports only to the requested result directory. It does not rewrite the
shipping resources.

The pre-registered escalation trigger is unchanged from the 2026-06-10 discovery:

1. any component delta is strictly greater than `0.001`;
2. the brightness sort permutation changes; or
3. an authorized regeneration changes a snapshot or selection golden.

Conditions 1 and 2 are mechanical outputs of `audit-vectors`. Condition 3 is checked only after a
human explicitly authorizes regeneration. Byte drift at or below the tolerance is recorded, but is
not itself a behavior-change trigger.

## Detection strategy

Run the audit on demand after a macOS, Xcode, or Swift toolchain change and before any ShapeData
regeneration:

```bash
just audit-vectors --output-dir <result-directory>
```

The result records the Git commit, macOS version, Xcode version, Swift version, exact command,
per-set summary, and per-glyph channel deltas. The audit exits nonzero when a mechanical trigger
fires. This is intentionally on demand rather than scheduled: hosted runners do not define the
shipping rasterizer environment, and a recurring job would detect runner-image churn rather than
an authorized local toolchain change.

## Regeneration policy

Do not regenerate committed `ShapeData/*.bin` only to remove sub-tolerance byte drift. Regeneration
is allowed when the binary schema, raster construction, glyph inventory, or an accepted matching
change requires it. Before regeneration, preserve this audit from the old bytes. After regeneration,
run the full snapshot and selection-golden suites and commit the toolchain provenance with the new
bytes.

If any trigger fires, stop the regeneration. Open a follow-up task to either vendor a deterministic
text glyph rasterizer or define and validate explicit per-OS golden rasters. Do not normalize away a
sort change or raise the tolerance to make the gate pass.

## Planned one-shot measurement

After the instrument and this rule are committed, run it once on all ten built-in sets. Add that
result directory to this note and close ASKI-51 only if the result is complete and the trigger is
applied exactly as written.

## Result

The one-shot audit ran from instrument commit `ef1c08e3e6581c313266a4368a36b5739ab89593` on
macOS 26.6.2 (build 25G83), Xcode 26.5 (17F42), and Swift 6.3.2. It compared 414 glyphs across all
ten sets. Every generated binary was byte-identical to its committed v3 resource. Every per-glyph
component delta was zero. The brightness sort permutation was unchanged.

Disposition: **NO_TRIGGER**. No resource regeneration or deterministic-rasterizer follow-up is
required. The on-demand audit and regeneration policy remain in force for the next toolchain change.
