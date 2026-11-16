# ASKI-103 composition policy decision rule

Register this protocol and the Swift instrument in Git before the first enabled capture. The production baseline is `7cee774f81736616619454453d0af12ebe4b7ef3`. An independent review must check the source paths, references, controls, tolerances, and capture command before measurement.

**KEEP** the current per-stage behavior if every registered product row and calibration control passes. Interpret the grid policy as the color space of the ASCII CGContext raster. Describe any later composition in its own space, including a deferred Core Image consumer. A failed control, unexplained row, incomplete CSV, or geometry mismatch makes the affected claim **INCONCLUSIVE**. Leave the task open on an inconclusive result. Freeze all thresholds before capture. This decision concerns compatibility of these stages for the registered fixtures. Forcing every CI graph into encoded working space would change filter math and is outside this run. Keep production source and frozen reference goldens unchanged and verify the existing snapshots in the full local gate.

## Matrix

Use the 18 entry points and overload selections in `MaskColorContractTests.Path`, with sRGB and Display P3 grids. The four cross-gamut engine paths use the opposite destination gamut. Apply both `encodedDisplay8Bit` and `extendedLinearPerGamut` to all ASCII cases. TileGrid's CGContext is always encoded and TileGrid has no policy property. Record policy `N/A` once per tile case, with `raster_space=encoded`. Tiles have no glyph AA. Record their glyph rows as `N/A`.

For each of the six CI-returning paths, evaluate the graph once per explicit consumer working space. Use the encoded destination gamut for `encoded` and extended-linear sRGB for `linear`. Both consumers emit the same encoded destination gamut. `N/A` for consumer denotes a CGImage entry point, which owns any CI evaluation internally.

The matrix contains 72 path/gamut/policy/consumer groups. Each group has six mask rows and one glyph row, including 24 tile glyph placeholders. Expect 504 matrix rows and 16 controls (520 data rows), plus the header.

## Opaque branch blend

Render one cell with zero-alpha white foreground over opaque black sRGB canvas. `fallback` supplies an opaque white sRGB fallback with no ground. `ground` supplies an opaque white sRGB ground and no fallback. Render each fixture at 0.25, 0.5, and 0.75 coverage with the default soft mask. Expected white fraction is `q=1-c` for fallback and `q=c` for ground. White and black of the declared space give neutral endpoints in the two destination gamuts. This experiment uses neutral colors to discriminate the transfer laws. The existing ASKI-98 mask contract supplies the chromatic declared-space probes.

Let `E` and `D` be the standard sRGB transfer and its inverse. The encoded RGB prediction is `255q` for an encoded blend, and `255E(q)` for a linear blend. sRGB and Display P3 use this transfer. Select the prediction from the source route before capture.

| Entry point or route | Fallback blend | Positive ground blend |
| --- | --- | --- |
| Direct scale and target-width ASCII | ASCII policy dictates the CGContext blend. Target width then averages a uniform interior in linear light. | Draw both branches in the policy's CGContext. Select between them in the shared linear CI context. |
| Direct tile pixel art | Encoded CGContext. | Route to shared linear CI context. |
| Direct tile mosaic | Soft coverage routes to shared linear CI context. | Route to shared linear CI context. |
| Sync effects, async, and same/cross-gamut engine CGImage paths | Shared linear CI context. | Shared linear CI context. |
| Sync, async, and cross-engine CIImage paths | Consumer working space for deferred `CIBlendWithMask`. | Consumer working space for deferred `CIBlendWithMask`. |

Read each channel in the center 3×3 pixel patch. Every RGB residual from the registered model must be at most 4 code values, every alpha within 1 of 255, and RGB MAE from the other transfer law at least 20. Up to four code values allow coverage-byte quantization, CGContext or Core Image blend rounding, and the final profile normalization. The alternative is at least 33 code values from the mathematical prediction at the three fixed coverages before rounding.

## Glyph edges

Render an opaque white system-font “S” at 40 points, full coverage, no fallback, no ground, and no effects. For each ASCII arm compare white over black with the same path, policy, consumer, and geometry over transparent. Use the transparent render's alpha as a per-pixel coverage reference. Verify equal width and height. Use every pixel with a reference alpha byte in [48, 208] to examine intermediate coverage and leave room for quantization at both endpoints. Require at least twelve such pixels and compare all three channels. Require opaque alpha within 1 throughout the output and transparent-reference premultiplied RGB within 2 of the reference alpha at eligible pixels.

- Plain scale ASCII predicts `a` for an encoded CGContext and `255E(a/255)` for a linear CGContext, with `a` the reference alpha byte.
- Sync effects, async, engine, and the CI-returning ASCII paths build the glyph raster in the grid-policy CGContext, then use the source-over kernel with an explicit extended-linear sRGB blend space. The prediction for an eligible pixel is `255E(a/255)` for either deferred consumer and either raster policy.
- Public target width is 96 pixels with 4× supersampling. Alpha reference uses the public target-width render over transparent, with a supplemental transparent direct research render at width 384. One cell at 40 points has an exact integer geometry at both widths. The research arm uses the same subpixel-positioning flags and only omits reduction. Require each target reference alpha to be within 1 code value of the average of its sixteen high-resolution alphas. For encoded CG blending followed by linear reduction use `255E(mean(D(a_i/255)))`. For linear CG blending followed by linear reduction use `255E(mean(a_i/255))`. These glyph rows are consistency checks against the source-selected model. They do not establish discrimination between the reducer transfer laws.

For the selected glyph model require RGB MAE ≤ 3 and max absolute RGB error ≤ 8 code values. These margins allow alpha quantization, inverse transfer at dark edges, per-channel ColorSync rounding, and target reduction rounding. For non-target paths the wrong-model MAE must be at least 20. In target-width renders a block of binary coverage has the same prediction under both equations. Report both residuals with the model selected from source. Only the synthetic raster control below establishes a discriminating reducer check.

## Readback and calibration

Copy each tagged result at 1:1 into an 8-bit RGBA bitmap in the encoded destination gamut, with CGContext copy mode, no geometric interpolation, and premultiplied alpha. In particular, a linear-tagged 8-bit result must pass through the color transform before comparison to encoded predictions. Compare opaque RGB directly and use alpha as the transparent reference. The source tag is recorded in the CSV.

In each output gamut require these controls before interpreting product results:

1. Equal opaque gray bytes at 128 tagged as encoded or linear must normalize to their respective transfer predictions. This separates reading linear-tagged bytes as encoded from correctly normalizing them.
2. A standalone untagged 128/255 mask between white and black CI constants must select the relevant transfer in encoded and linear consumer contexts.
3. A standalone explicit-linear source-over kernel applied to white at 0.5 alpha over black must read linear in both consumer contexts.
4. Build a 12×12 raster from nine 4×4 blocks, each with eight zero and eight byte-128 samples. Pass the opaque RGB raster through the actual `ASCIIGrid.downsampleTargetWidthImage`, reducing by four to 3×3. Run once with encoded source tag and `sourceIsLinear=false`, and once with linear source tag and `sourceIsLinear=true`. Normalize each tagged output to encoded readback. A matched white premultiplied transparent raster carries the same bytes in alpha and feeds the instrument's `sourceAlpha` and shared `targetPrediction` functions. The exact byte-based predictions are `255E(D(128/255)/2)` for the encoded source and `255E((128/255)/2)` for the linear source: half the samples are zero, so their mean decoded coverage is `D(128/255)/2` and their mean coverage is `(128/255)/2`. Compare all 27 RGB channels of the 3×3 output to the selected model and the other model. This exercises the same alpha extraction and prediction selection as the target-width glyph rows, plus the real reducer.

All four control types use the patch metric with max error ≤ 2, alternative-model MAE ≥ 20, and opaque alpha within 1. These controls supply known differences independently of the product render dispatch. The source-over color-space overload is documented in the selected SDK's Core Image `CIKernel.h`. [Core Image working color space](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace.md) and [Core Image performance guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_performance/ci_performance.html).

Before capture, a standalone Core Text calibration on macOS 27.0.1 (26A434), arm64, Xcode 27 (27A266a), Swift 6.4 found max opaque RGB versus clear alpha difference 0 in all four arms: 1× and 16×, encoded and linear sRGB. The font was `.AppleSystemUIFontMonospaced-Regular`, with 167 and 2641 partial pixels respectively; the `AppleFontSmoothing` preference was absent. This is host-specific calibration, not a guarantee on other hosts. No rasterization workaround is applied. A failed reference check elsewhere remains INCONCLUSIVE under the frozen rule.

## Replay and evidence

Run from the root of the registered revision on macOS with the selected Aski Xcode toolchain. Use a fresh output directory. The regular test gate executes the suite without capturing data unless `ASKI_103_CSV` names a file. The diagnostic refuses to overwrite an existing file.

```bash
capture_dir="$(mktemp -d "${TMPDIR:-/tmp}/aski103.XXXXXXXX")"
{
  git rev-parse HEAD
  git status --porcelain
  sw_vers
  xcodebuild -version
  xcrun swift --version
  uname -m
  sysctl -n machdep.cpu.brand_string
} > "$capture_dir/provenance.txt"
if GIT_CONFIG_PARAMETERS="'safe.bareRepository=all'" xcrun swift build --build-tests > "$capture_dir/build.log" 2>&1; then
  printf '%s\n' 0 > "$capture_dir/build-exit-status.txt"
  if ASKI_103_CSV="$capture_dir/composition.csv" \
    xcrun swift test --skip-build --no-parallel --filter MaskCompositionPolicyDiagnosticTests \
      > "$capture_dir/test.log" 2>&1; then
    printf '%s\n' 0 > "$capture_dir/exit-status.txt"
  else
    capture_status=$?
    printf '%s\n' "$capture_status" > "$capture_dir/exit-status.txt"
  fi
else
  capture_status=$?
  printf '%s\n' "$capture_status" > "$capture_dir/build-exit-status.txt"
fi
```

Retain the capture commit, toolchain identity, test exit status, and CSV. A numeric assertion failure records a failed test and its residuals remain in the CSV if the matrix completes. A precondition failure can prevent CSV publication. The unique row key is `(path, grid_gamut, output_gamut, policy, raster_space, consumer, fixture, coverage)`. Check unique row keys, all 18 path names, total rows, and every applicable `passed` field. CSV residuals are in encoded 8-bit code values. Mask and image controls report the patch's center RGBA, theoretical predictions, and errors across the patch. Glyph rows report the frame's center RGBA for inspection and per-pixel residual statistics over eligible edges for the gate. Glyph `samples` counts channels, which is three times the eligible pixel count. `alpha_max` includes the target-width reference alpha alignment check when applicable.
