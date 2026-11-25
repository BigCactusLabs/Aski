# ASKI-112 replay harness (2026-11-25)

Research harness for the Core Image decode-path switch found while investigating
ASKI-112. It is not part of the gate. [ASKI112ReplayTests.swift](ASKI112ReplayTests.swift)
is a Swift Testing suite that runs only when `ASKI112_OUT` and `ASKI112_MODE` are set.

Two separate findings must not be merged:

1. **The 256-read switch (product defect, reproduced).** In one process, once about
   256 Core Image reads of ImageIO-backed JPEG `CGImage`s are alive at once, Core Image
   stops using its first decode path for new reads, and the same source renders
   differently.
2. **The one-pixel gate flake in ASKI-112 (not reproduced).** The 2026-11-24 failure
   differed from the golden in one pixel by 1. No run here produced that signature.

## Run

Run each mode from the repository root, one run per gate-lock hold, then remove the copy:

```bash
cp Scripts/research/aski112-2026-11-25/ASKI112ReplayTests.swift Tests/AskiTests/
xcrun swift build --build-tests
ASKI112_MODE=d1 ASKI112_RETAIN=2 ASKI112_N=300 ASKI112_OUT=/path/to/new/output-dir \
  xcrun swift test --skip-build --filter ASKI112ReplayTests
rm Tests/AskiTests/ASKI112ReplayTests.swift
```

- `ASKI112_MODE`: `d1` default ImageIO decode; `d2` adds
  `kCGImageSourceShouldCacheImmediately`; `d3false` / `d3true` pass the private ImageIO
  key `kCGImageSourceUseHardwareAcceleration` (experiment only, never production);
  `d4` reuses one `CGImage` for every read.
- `ASKI112_RETAIN`: `0` releases everything per iteration; `1` keeps each decoded
  `CGImage`; `2` also keeps each read's `CIImage` and output `CGImage`.
- `ASKI112_N`: iterations, capped at 300.

Each iteration decodes the corpus JPEG
(`docs/Research/Corpus/nasa-occupancy-v1/assets/james-lovell-portrait.jpg`, 975x1280),
renders the test's background (`Background.original(_, sizing: .fill)`, 288x336) through
`BackgroundResolver` and the shared `EffectsRenderEngine` `CIContext`, and hashes the
RGBA8 output (FNV-1a 64). Iteration 0 also renders an owned bitmap copy of the
decoded bytes. Each iteration runs in an `autoreleasepool`; the run aborts above a
4 GB `phys_footprint`. Output: `replay-<mode>[-retainN].txt` and raw `.bin` outputs
in `ASKI112_OUT`. Use a fresh output directory outside the repository.

## Results

Host: Apple M5 Max, macOS 27.2.1 (26B8132), Xcode 27.2 (27B52), Apple Swift 6.4.2.
Tree: base 99fc4c7 plus this harness. Each mode ran once with N = 300.

| Run | Retain | Decoded-byte digest | Bitmap-copy output | JPEG output, reads 0-256 | JPEG output from read 257 | Peak footprint |
| --- | --- | --- | --- | --- | --- | --- |
| d1 | 0 | db534f0130c791af | 9737703e2156d3a2 | cf8052480590ba83 | no switch | 178 MB |
| d1 | 1 | db534f0130c791af | 9737703e2156d3a2 | cf8052480590ba83 | no switch | 184 MB |
| d1 | 2 | db534f0130c791af | 9737703e2156d3a2 | cf8052480590ba83 | c038c925b3ff4c1b | 729 MB at read 250 |
| d3false | 2 | 2b13553ccfd0d2bd | **c038c925b3ff4c1b** | cf8052480590ba83 | c038c925b3ff4c1b | 729 MB at read 250 |

Byte comparisons of the d1 retain-2 outputs (`cmp -l` counts): pre-switch vs
bitmap copy 126,954 bytes; post-switch vs bitmap copy 140,392 bytes; pre vs post 86,477
bytes, max 22 levels. The d1 retain-0 and retain-2 pre-switch outputs are identical.

Reading:

- The switch needs live reads, not a read count: with each read's `CIImage` and
  output released (retain 0 or 1), 300 reads never switched; with them kept (retain 2),
  the output switched at read 257 (after 256 kept reads). Keeping only the decoded
  `CGImage`s does not trigger it.
- Pre-switch output (`cf80…`, the path the committed golden was recorded on) matches
  no bitmap-backed render: it is Core Image's own read of the ImageIO-backed image,
  whatever decode options the `CGImage` was created with.
- Post-switch output (`c038…`) equals the render of a bitmap holding ImageIO's
  decode with the hardware key set to false, so after the switch Core Image reads a
  software decode. The default `CGImage` bytes (`db53…`) are a third decode whose
  bitmap copy renders as `9737…`.
- So three decodes of one file render three ways, and which one Core Image uses
  depends on how many reads are alive in the process. The 256 limit and its owner
  (ImageIO or Core Image surface pool) are inferred, not observed in Apple code.

Not run (budget of four runs): d2, d3true, d4. Run 1 (before the per-iteration
`autoreleasepool` rule) saw the same switch in loops without a pool: background-only
at read 257, the full test render (two reads) at iteration 128, unaffected by a
brand-new `CIContext` or by 8,002 interleaved non-JPEG renders. Those loops grew
to 22.8 GB and caused out-of-memory alerts; do not run without the pool and guard.
