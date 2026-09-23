---
id: ASKI-26
title: >-
  Descriptor query and candidate are computed on mismatched supports (single
  inscribed disc vs square raster)
status: Done
assignee: []
created_date: '2026-08-19 05:57'
updated_date: '2026-08-28 18:13'
labels: []
dependencies: []
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ShapeContext.histogram60 inscribes its sampling disc in the SHORTER cell axis (maxRadius = min(width,height)/2) and hard-rejects everything outside it. The candidate side calls it on a SQUARE 64x64 glyph raster, admitting ~79 percent of the raster. The query side calls it on the raw anisotropic source cell, so on a 1:2 cell the disc admits about 39 percent and excludes the top and bottom quarters of every cell entirely. Query and candidate therefore do not describe the same region, at any oversample. ASCIICharacterSet.swift:8 states the descriptor matches the published Xu/Zhang/Wong SIGGRAPH Asia 2010 baseline: the dimensionality does (5 radial x 12 angular = 60) but the sampling does not. Xu et al. tile N isotropic log-polar windows across a non-square cell and concatenate (their worked example is 72 windows, 4320-D, for a 12x24 glyph); Aski uses N=1. They also apply a 7x7 Gaussian pre-blur on both sides to suppress bin-discretization aliasing, which Aski applies on neither. A minimal fix is a 1x2 stack (upper-half disc plus lower-half disc) restoring full vertical coverage at 120-D. This is plausibly the mechanism behind the documented log-polar orientation degeneracy on radial and diagonal content, since a disc inscribed in the short axis cannot see cell corners. Evidence: docs/Research/2026-08-19-sampling-lattice-support-collapse.md section 3.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Either the query and candidate supports are made to match, or the parity claim in ASCIICharacterSet.swift:8 is corrected to state the divergence
- [ ] #2 If a tiled-window descriptor is built, both sides use the identical sampling pattern and identical pre-blur, and the change is gated on pick quality rather than descriptor-space metrics
- [ ] #3 Decision is recorded against the shipping regime, not only the no-downscale lab regime
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24 (deep pass): AC#1 citation drifted: ASCIICharacterSet.swift:8 is now :7. Caution: selection-optimality-gap §3c measured pick quality flat across 3-48 reachable bins, weakly contradicting this task's closing orientation-degeneracy conjecture. OVERLAP: same defect as ASKI-52 from the opposite end (query support vs candidate vocabulary); both regen the .bin vectors and move each other's baseline — sequence together.

SHIPPED as measurement in PR #32 (merged 2026-08-28, a12daa2/8d5eb1b) as one unit with ASKI-52. Five-arm ladder: tiled arms non-degenerate (72 windows, 4320-D); paper's construction best on text but under the +3.0% bar, better with its pre-blur removed. No promotion. Note: docs/Research/2026-08-28-aski52-26-candidate-convention.md.
<!-- SECTION:NOTES:END -->
