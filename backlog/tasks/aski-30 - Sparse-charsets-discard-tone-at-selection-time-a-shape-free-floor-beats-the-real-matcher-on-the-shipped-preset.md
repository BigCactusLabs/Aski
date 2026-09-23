---
id: ASKI-30
title: >-
  Sparse charsets discard tone at selection time; a shape-free floor beats the
  real matcher on the shipped preset
status: Done
assignee: []
created_date: '2026-08-19 06:07'
updated_date: '2026-08-27 03:40'
labels: []
dependencies:
  - ASKI-32
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
findBestScored prunes to the topK brightness-nearest candidates and then takes argmin of shape distance within that pool, with brightness surviving only as a tie-break in the (distance, brightnessDelta, index) ordering. topK is 12 at the default density, and eight of the ten built-in charsets hold 12 glyphs or fewer - including blocks, the charset frozen into the canonical shipping preset by ASTSK-47. On those sets the pruning step is a no-op, so tone information is discarded at selection time and the pick is decided purely by a shape descriptor that carries 2 to 3 of 60 bins at the shipping sampling regime. Measured consequence at columns=80, oversample=2, exhaustive 8640-cell census on nasa-steerable-v1: a shape-free floor that picks purely by ink coverage, in the matcher's own polarity convention, BEATS production under all three oracles - GMSD 0.20278 vs 0.33993 (40 percent better), MAE 0.24637 vs 0.56329 (2.3x), HaarPSI 0.38673 vs 0.09480 (4.1x, higher is better). Under MAE the production pick on blocks averages rank 7.22 of 8, second worst available. Production wins on standard and braille, but by only 0.6 to 3.2 percent, where the pre-filter is still doing the tone work. This is a comparison of two realizable selectors rather than a selector against a metric argmin, so it does not depend on the contested definition of an optimal pick (see ASKI-27). These figures are a re-measurement: the first version scored an equal row-by-column partition of the native image rather than the rectangle the converter sampled, and the correction made the blocks margin larger (17 percent to 40 percent under GMSD) while shrinking production's dense-charset margin, so the sparse-versus-dense split is sharper than first reported. Direction: replace prune-then-shape-argmin with a combined score of shape distance plus a weighted tone term for sparse charsets. The machinery exists - occupancyMatching already applies toneWeight = occupancyMatching * 50 in findBestOccupancyScored - so this needs a gate, not new math. Evidence: docs/Research/2026-08-19-selection-optimality-gap.md section 3b.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A tone-weighted selection score is measured against both the current matcher and the shape-free tone-only floor, on sparse and dense charsets separately
- [x] #2 The frozen rule is set before the decisive run and requires the tone-weighted arm to beat BOTH baselines, not just production
- [x] #3 Any default change is confirmed by a perceptual check rather than by reconstruction metrics alone, per ASKI-27
- [ ] #4 If the tone-weighted arm cannot beat the shape-free floor on blocks, record whether the shape term should simply be disabled for sparse charsets
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24 (deep pass): Dependency ASKI-32 is Done (PR #27) — ready to start. ASKI-32 scored glyph pictures, not photographic cells, so nothing there pre-empts this run. OVERLAP: consider running jointly with ASKI-28 (same census battery, same corpus, same pre-filter code path).

2026-08-24: PR #29 MERGED to main (1a889ac). Instrument + frozen rule landed: docs/Research/2026-08-24-aski-30-28-decisive-rule.md, @_spi cellQueryDescriptors (sole Sources change), SelectionCeiling arms P/F/T/K + exploratory lex/z-norm, CSV emitter with effective-topK recording. Codex review (4 findings) and PR-bot timing finding all fixed. AC#2 done: rule frozen before any decisive number. Next: run battery per rule §4 — calibrate on nasa-structure-v1, verdict on held-out nasa-steerable-v1, apply §5 mechanically.

ASKI-56 arbiter update 2026-08-27: the required perceptual discriminator now exists and is validated. Its D family put T(w*=2) vs F in front of the blinded owner on all 6 sources: 1/4 decided trials for T, 2 ties, VLM order-inconsistency 0.50 — the 0.09% SSIM objection behaves like a genuine perceptual near-tie leaning toward F. Non-gating (decided n=4 < 30): verdict stays INCONCLUSIVE. Re-opening path: a dedicated D-focused arbiter run to decided n ≥ 30 (docs/Research/2026-08-27-aski56-arbiter-verdict.md).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Verdict: INCONCLUSIVE, applied mechanically from the frozen rule (docs/Research/2026-08-24-aski-30-28-battery-verdict.md). At calibrated w*=2 on blocks the tone-weighted arm clears every MAE gate decisively (0.4186 vs production, 0.8935 vs the rebuilt tone-only floor, no-harm passed, RMSE agreeing) but single-scale SSIM inverts direction against the floor by 0.00026 raw (-0.09%), and the pre-committed demotion clause carries no epsilon. Blocker named: SSIM inversion vs floor. KILL nowhere near firing (T beats both baselines at every w>=1). Re-opening requires the perceptual discriminator (ASKI-56 or owner-signed contact sheet), not another reconstruction run. AC#3 vacuous — no default change proposed. Exploratory lift (lex shapeK=6, z-norm w=10) split to its own task per rule section 9. Sources/Aski untouched.
<!-- SECTION:FINAL_SUMMARY:END -->
