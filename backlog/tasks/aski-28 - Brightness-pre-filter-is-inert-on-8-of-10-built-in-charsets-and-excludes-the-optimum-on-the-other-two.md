---
id: ASKI-28
title: >-
  Brightness pre-filter is inert on 8 of 10 built-in charsets and excludes the
  optimum on the other two
status: Done
assignee: []
created_date: '2026-08-19 05:57'
updated_date: '2026-08-24 17:54'
labels: []
dependencies: []
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The matcher prunes candidates to topK = 12 + round(density*24) nearest by ink brightness before any shape scoring, and topK is 12 at the default density of 0. Built-in glyph counts are diagonal 4, diamond 4, cross 5, blocks 8, dots 8, minimal 10, lines 12, mixed 12, standard 95, braille 256 - so on eight of ten sets the pre-filter admits the whole charset and is a no-op, and selection is already exhaustive. On the two dense sets it binds. Measured at columns=80, oversample=2, on the nasa-steerable-v1 naturals with an exhaustive 8640-cell census: on standard the globally optimal glyph falls outside the pool in 58.5 percent of cells under GMSD and 53.3 percent under HaarPSI, and pool exclusion accounts for 16.45 of the 18.71 percent total optimality gap under GMSD; on braille the optimum is in the pool 37.3 percent of the time and pool exclusion is 16.46 of an 18.99 percent gap. Under MAE, the luminance-aware oracle, both totals fall to 3.6 to 4.7 percent - at the pre-registered 3 percent bar - so the headroom a pool-width sweep is competing for is small and oracle-dependent. PRIORITY NOTE: these figures replace a first measurement that scored an equal row-by-column partition of the native image rather than the rectangle the converter sampled; the corrected gaps are 2 to 6 times smaller, which lowers this task's expected value. The pre-filter has still never been studied and its width has never been swept. Note the inverse finding for sparse sets: on blocks the pool is inert and the entire gap is ranking, so pool widening cannot help the frozen preset. Evidence: docs/Research/2026-08-19-selection-optimality-gap.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 topK is swept from 12 toward the full charset on standard and braille and pick quality plus cost are reported against at least two oracles including a luminance-aware one
- [x] #2 Result is reported per charset, since the pre-filter is provably inert on the eight sparse built-ins
- [x] #3 Any promotion carries a frozen PASS/KILL rule set before the decisive run and a perceptual check, per the standing rule that reconstruction-metric wins do not license a default change
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24 (deep pass): OVERLAP: shares instrument, evidence doc, and the LogPolarKernel.swift:69 pre-filter with ASKI-30; the decisive runs are the same census battery over the same corpus — running 28+30 as one experiment costs about what either costs alone.

2026-08-24: PR #29 MERGED to main (1a889ac). Shared instrument with ASKI-30 landed; frozen rule docs/Research/2026-08-24-aski-30-28-decisive-rule.md covers this task's pool-width arm K (per-charset topK grids, effective width recorded in CSV) and states the expected KILL in advance (pool gaps 2.73-2.85 percent < 3.0 percent bar). Next: battery run per rule §4.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Verdict: KILL on both dense charsets, applied mechanically from the frozen rule (docs/Research/2026-08-24-aski-30-28-battery-verdict.md). standard: best held-out ratio 0.9775 at topK=64, never <=0.97; the calibration point's 0.9590 did not transfer across corpora (the pre-registered corpus-straddle warning fired). braille: flat at 0.9999 (topK=18), monotone degradation to 1.1428 at the full 256 pool. Cost never gated (all quality-relevant points <2.0x). topK=12 stands; no knob change licensed. AC#3's perceptual-check clause is vacuous under KILL — no promotion occurred.
<!-- SECTION:FINAL_SUMMARY:END -->
