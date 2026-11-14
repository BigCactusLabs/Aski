# ASKI-74 HDR encoder input parity

The existing qualification compared CLI artifacts made from the same package graph. Its HDR inputs were not measured directly. Lossless TIFFs matched and existing HDR gates passed, but some HEICs and their decoded pixels differed. One native repeat did not establish a variability bound.

Commit this capture and [decision rule](preregistration.json) before collecting measurements. The test is disabled unless `ASKI_HDR_BOUNDARY_OUTPUT` is set. It takes the defaults from `HDREvaluateCommand.parse`. The canonical command and legacy runner dispatch to the same evaluate/check types, both of which default to 80 columns and opaque sRGB `#101010`. The diagnostic takes the font and emission constants from `HDRLabCLI`. It uses the production fixture source, renders SDR once per fixture, and renders HDR once per fixture and k. The scale is 1 with source aspect preservation disabled.

Each of the three passes records SHA-256 of the active pixel bytes in row order from the immutable CGImage providers immediately before the production encoder call. The fingerprint excludes undefined row padding. Interpretation metadata includes row stride, component and pixel widths, alpha and bitmap flags, rendering intent, interpolation, decode array, content headroom, and color-space name, model and ICC profile bytes when available. The contract is a default CIContext making an RGBA8 HEIF representation in the fixture's encoder gamut with the HDR CIImage supplied through `.hdrImage`. One encode/measurement context is reused throughout each capture. G1–G4 come from the unchanged `HDRGates.evaluate`, called once on each complete set of 36 measurements.

After the encodes and gates finish, the test records the actual HEIC hashes, ImageIO properties and image counts. A separate diagnostic context decodes the SDR base with ImageIO and the HDR image with Core Image `.expandToHDR`. It hashes the exact four-channel binary32 raster in extended linear sRGB and records both decoded dimensions. `completion.json` is published atomically only after all checks, encodes and decodes succeed. Incomplete captures retain any HEICs and gate results already written.

## Commands

Use separate clean scratch paths, one for each backend. Build both from the same committed diagnostic source. Keep the builds and the four processes serial. Set the variables below to the selected backend and absolute paths. The output parent must exist and the capture directory must be new. The test creates it with owner-only permissions. Use two different capture directories for each backend.

```sh
xcrun swift build --build-system "$backend" --scratch-path "$scratch" --build-tests
ASKI_HDR_BOUNDARY_OUTPUT="$capture" xcrun swift test --build-system "$backend" \
    --scratch-path "$scratch" --skip-build --no-parallel --filter BackendHDRInputParityTests
```

Keep the command logs and record the test binary hash for each invocation. Supply the comparator a lead-owned JSON array with one receipt per invocation. Each receipt contains the following fields.

| Field | Value |
|---|---|
| `backend` | The explicit `native` or `swiftbuild` backend |
| `argv` | The exact test command arguments, represented as a string array |
| `exitCode` | The test command's actual exit code |
| `sourceCommit` | Diagnostic source commit checked out for the run |
| `testBinarySHA256` | SHA-256 of the built test executable used by the run |
| `output` | The absolute directory supplied as `ASKI_HDR_BOUNDARY_OUTPUT` |
| `completionSHA256` | SHA-256 of that invocation's completion manifest |

```sh
python3 Scripts/research/aski74-hdr-boundary-2026-11-13/compare.py "$receipts"
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/research/aski74-hdr-boundary-2026-11-13/test_compare.py -v
```

The comparator uses the receipts to bind the runs and checks all 432 encode records. Exit 1 rejects failed or incomplete evidence. Exit 2 reports exact inputs and passing gates with at least one output field that changed only across backends. Exit 0 reports exact inputs, passing gates, and either identical outputs or observed same-binary variation for every differing field. The JSON describes each affected fixture, k and output field separately. It includes observed output diversity and the count of values shared by both backends. Same-binary variation establishes that the framework path can vary at identical inputs in that case. The limited sample does not bound future variability, establish statistical equivalence, or rule out a concurrent backend effect. Use the results only for this host, toolchain, frameworks, corpus and configuration.
