# ASKI-108 near-white transition inspection

Commit this protocol and instrument before capture. Inspect these three assets from the
`nasa-occupancy-v1` corpus, with provenance in the corpus manifest and asset list.

| Fixture | NASA ID |
| --- | --- |
| `rcs-function-diagram.jpg` | s64-03506 |
| `spacecraft-attitude-diagram.jpg` | s64-03507 |
| `james-lovell-portrait.jpg` | S70-34268 |

Use the source JPEGs as the original side of the pairs. Decode each at its full
stored raster with ImageIO and pass that CGImage to `VesperPreset.canonical.render`.
Keep the PNG at the preset's returned pixel dimensions with its native color
profile. The preset uses 76 columns, the blocks character set, log-polar with the
wide tile, Display P3, 2× sampling, and 14 point Courier Prime at @2x with
source-aspect preservation on charcoal. No input crop, output resizing, or
preset override enters the inspection. The inspection PNG always comes from the
preset render. Independently re-render the SPI grid with the same render
parameters and compare PNG bytes and provider bytes with matching pixel layout
and color space. Report either difference and retain the re-render when its PNG
differs. If pixel layouts or provider bytes disagree, qualify alignment from
the reflected grid and do not make a boundary-attributed verdict from it.

## What the instrument observes

`Sources/Aski/ASCIIConverter+Research.swift:32` exposes public SPI
`samplingGeometry`, and `:119` exposes public SPI `cellQueryDescriptors`.
`CellQueryDescriptors` at `:167` gives the real descriptor lanes, adjusted
OKLab L, and the converter grid. `SamplingGeometry` at `:194` gives the exact
sampling lattice. Require both paths to report matching rows and columns,
shape-descriptor support, and zero dropped rows and columns. Trace how a cell
is sampled using its integer footprint in the reported lattice. Both the grid
and lattice use zero-based coordinates from the top left. To locate the
footprint in a native source, scale the lattice bounds by native source size
divided by lattice size on each axis. This locates the region for visual
inspection. Resampling can draw contributions from outside those bounds.

At `Sources/Aski/Algorithms/LogPolarKernel.swift:301–315`, the canonical
inverted shape query uses weight `1 - (0.299 R + 0.587 G + 0.114 B)` from the
resolved RGBA8 raster. `ShapeContext.swift:89–117` selects the in-footprint
samples and drops weights strictly below 0.05 before accumulation. The
nominal 0.95 boundary applies per admitted sample, with the implementation's
Float arithmetic. The SPI gives the exact post-histogram query, including
zeros. It does not give the pre-histogram raster, which sample crossed, or the
margin to the cutoff. A cell need not be uniformly near white to produce a
zero query. Other routes to zero include lack of admitted footprint samples,
especially at degenerate geometry. The 2D requirement rules out the
one-pixel-axis tone fallback. Adjusted OKLab L is the brightness pre-filter
input. It is not luma at the cutoff.

For every cell, record its all-components-equal-to-zero state and whether the
grid emits U+0020 in a one-pixel-per-cell PNG. White is zero/space, red is
zero/glyph, blue is nonzero/space, and black is nonzero/glyph. Use nearest
neighbor if enlarging the diagnostic mask. Enumerate each horizontal and
vertical zero↔nonzero adjacency once in CSV, with the zero endpoint first.
Include row, column, lattice origin, space flag, and adjusted-L bit pattern
for both endpoints, followed by both 60-component query vectors in lane order
as space-separated hexadecimal Float32 bit patterns. The logged cell pitch
defines the exact extent of each footprint. These are candidate edges, not
pre-threshold luma estimates or reports of a visible artifact. A nonzero-space
neighbor remains in the CSV so the relation between a query transition and a
glyph transition is inspectable.

## Positive diagnostic

Generate one 152×152 opaque Display P3 gray ramp with every row equal and
sample byte `224 + floor(31 × x / 151)`. Capture its source and canonical
render first. The middle row must have nonzero-query ink, followed by a
contiguous run of zero-query spaces through the right edge, and the CSV
must expose the query transition. If this fails, stop and investigate the
instrument or environment before drawing a fixture verdict. The ramp checks
transition detection through the same converter. Only the three NASA pairs
count toward the fixture verdict.

## Visual inspection and decision

For each fixture, first view the original and canonical output at native pixel
resolution and mark candidate abrupt edges on the canonical image. Then open
the mask and CSV to check whether the same edges follow a zero/nonzero query
transition, preferably zero/space next to nonzero/glyph. Follow each candidate
back to its source neighborhood and decide whether there is a gradual approach
to white at that location or a hard source contour, text, or other feature
that could explain the edge. Inspect candidate transitions even when the
first unmarked pass finds no cliff. Treat crops or enlarged masks as labeled
diagnostics and retain all native outputs. Record each inspection by fixture,
region, cell coordinates if relevant, and what the original and render show.
This is a scoped visual judgment by the reviewer. Detection in the mask and
CSV is neither a visibility score nor a substitute for inspecting the render.

Support a visible cliff only when a named fixture shows an abrupt extra
transition in the unmodified canonical render, along a corresponding candidate
boundary where the source visibly grades into white. Mark difficult
attribution or disagreement as inconclusive. If all three pairs are assessable
and the reviewer sees no supported cliff, record scoped absence in these pairs.
Keep assessment and evidence by fixture when confidence differs.

If a fixture supports a cliff, propose a future lab arm. Freeze the shipping
0.05 admitted-weight rule as control and vary only the weight ramp immediately
below nominal luma 0.95, for example a continuous transition in the admitted
weights over luma 0.92–0.95 with exactly zero weight at and above 0.95, all
preset/render knobs held fixed. A proposal must account for histogram
normalization, which can erase uniform amplitude changes, before claiming the
treatment could fade glyph output. Pre-register its exact rule and an
independent known-difference diagnostic before any treatment measurement.
Require a visible reduction at named sites under paired native inspection,
no regression on held-out occupancy fixtures under blinded review, and a
no-near-white-ink veto from the opaque gray and flat white ground contracts.
If the arm could turn a formerly zero-query near-white region into ink, it is
ineligible. Use the project's MAE/GMSD and no-harm census requirements before
any proposed promotion that would move frozen-preset goldens. Do not implement,
run, or ship the proposed arm in ASKI-108.

## Capture

From the repository root with the selected full Xcode toolchain, in an
available native slot, run the following once against a reviewed committed
instrument and a new output directory.

```bash
bash Scripts/research/aski108-2026-11-14/capture.sh \
  "$PWD/docs/Research/Results/2026-11-14-aski108-near-white"
```

The wrapper builds a release executable from a local dependency archived at
the recorded HEAD into a fresh directory under `/private/tmp`. The running
checkout can have unrelated changes because none of them enters the build.
The output directory contains the original JPEG copies, the diagnostic source,
canonical PNGs, mask PNGs, adjacency CSVs, toolchain, exact argv, source and
fixture hashes, build log, capture readout, and SHA-256 manifest. If a build
or capture fails, preserve its logs and use a new output directory for a retry.
