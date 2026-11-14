# ASKI-2 raw-axis preparation experiment

The exact-lattice experiment rejects this arm before production integration. All 128 cases have identical geometry and byte lengths; 40 match every byte and 88 do not. All 16 intentionally unmirrored controls detect the wrong orientation. Identity passes 16/16, mirrors and 180-degree rotation each pass 8/16, and the four transposed orientations fail all 16. Both source sizes have 44 mismatches. These results do not reject every possible fused preparation design.

[Results](raster-results.json), [per-case CSV](raster-rows.csv), and [provenance](provenance.json) retain the complete readout. The largest observed signed channel differences range from -107 to +23 for red, -46 to +9 for green, -39 to +9 for blue, and -9 to +13 for alpha. This is not an accepted tolerance. Source inputs cover sRGB/P3, opaque/mixed alpha, 1280×720 downscaling and 64×46 no-budget-downscale geometry.

The opt-in [test-only prototype](../../../Tests/AskiTests/VideoOrientationPreparationTests.swift) freezes the retained `DecodeSession.reorient` arithmetic and uses production sizing/read/resample helpers. Its rule was declared before execution, but was not a committed preregistration. The native capture compiled successfully, emitted all expected rows, then returned nonzero because parity failed. No second run, relaxed assertion, production decoder change, golden re-record, or performance measurement was made.

Reproduce the **expected rejection** from the repository root:

```bash
ASKI2_ORIENTATION_RASTER=1 xcrun swift test --no-parallel --filter 'VideoOrientationPreparationTests/rawAxisResamplingMatchesRetainedLattice'
```

Ordinary test runs skip this experiment. ASKI-2 remains open. A next arm must first isolate retained Core Image color/alpha conversion and orientation/resize sampling order; it must pass the frozen exact rule or obtain a separately justified output-change decision with Aski quality evidence before adoption. The current video path remains unchanged.
