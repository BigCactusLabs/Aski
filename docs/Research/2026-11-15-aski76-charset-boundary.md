---
title: "ASKI-76 — character set extension boundary"
slug: 2026-11-15-aski76-charset-boundary
date: 2026-11-15
status: complete
subsystem: [shape-context, meta]
summary: "Aski keeps the ASCIICharacterSet arrays as the expert contract for supplying precomputed glyph data. RasterizedCharacterSet remains the font and glyph input path. ShapeQueryPolarity joins its setting behind AskiResearch SPI."
related_specs: [Sources/Aski/Aski.docc/CharacterSets.md]
---

# ASKI-76 — character set extension boundary

**Decision: KEEP** the `ASCIICharacterSet` arrays. Audited at
`7cee774f81736616619454453d0af12ebe4b7ef3`.

[`RasterizedCharacterSet`](../../Sources/Aski/CharacterSets/RasterizedCharacterSet.swift)
already accepts a font and a nonempty list of glyphs. Direct conformances let
expert clients supply their own precomputed matcher inputs. Replacing the arrays
would remove that capability or require another public input path.
[`GlyphBank`](../../Sources/Aski/CharacterSets/GlyphBank.swift) already gives
Aski a single immutable owner for its built-in and rasterized data and validates
external array lengths when a converter takes a snapshot. The
[Character Sets guide](../../Sources/Aski/Aski.docc/CharacterSets.md) records the
input and snapshot rules.

## Surface at the audited commit

| Surface | Role and consumers |
| --- | --- |
| `ASCIICharacterSet: Sendable`, `characters` | Product extension point. The array fixes the glyph identity and order used by conversion, ranking and animation. Tests implement external conformances in `CharacterSetProtocolTests`, `GlyphBankTests`, and `ASCIICharacterSetBoundaryTests`. |
| `brightnessValues`, `shapeVectorLanes`, `lanesPerCharacter`, `shapeVectorDimension` | The matcher representation is the expert extension contract. `DotMatrixKernel` and `LogPolarKernel` consume brightness. Log-polar also consumes the packed descriptors. `BuildStandardVectors`, the color labs, and matcher tests use the same data. The descriptor uses one whole-raster histogram of five radial by twelve angular bins. It descends from Xu, Zhang and Wong's tiled descriptor through a simpler construction, as recorded in the [convention study](2026-08-28-aski52-26-candidate-convention.md). |
| `rawDensityValues` and its brightness fallback | Public input and data projection retained for research and replay. It is validated and stored with the other arrays. The production matchers use normalized brightness. Direct readers include `ArbiterCensus`, `SelectionCeiling`, `DecolorFixtures`, and `BuildStandardVectors`. |
| `StandardCharacterSet` and `RasterizedCharacterSet` | Product conformances expose the four arrays and protocol helpers. The ten static built-ins select committed assets. `RasterizedCharacterSet.init(characters:font:)` computes data with Core Text. The CLI and labs resolve built-ins through `AskiToolSupport/Charset.swift`. Runtime sets also serve custom fixtures, vector generation, labs, and tests. |
| `ASCIIConverter<C,P>`, `init(characterSet:palette:…)`, `characterSet`, `DefaultConverter` | Product entry points for installing a set. Still-image conversion and animation both use the converter's snapshot. CLI rendering, lab commands, benchmarks, tests, and the frozen render reference use this path. |
| `ShapeMatching.findBest`, `findRanked`, `findBestScored`, `findRankedScored` | Ordinary public low-level matcher operations over the same packed layout. The log-polar kernel uses the first two and `findBestScored`. Labs and tests use scored matching. The SPI `poolIndices` exposes the brightness prefilter to the kernel, labs, benchmarks, and replay scripts. |
| `samplingGeometry`, `rankedCandidateIndices`, `cellQueryDescriptors`, `convertWithResidual`, `SamplingGeometry`, `CellQueryDescriptors` | `AskiResearch` SPI for the converter's geometry, candidate ordering, descriptors and residuals. Shape and sampling labs, targeted tests, the preparation benchmark, and historical replay scripts use these hooks. |
| `EmissiveCharacterSet`, `GlyphEmissionSpec`, `EmissionOptions`, `renderExtendedRangeImage` | HDR research SPI. `EmissiveCharacterSet.emissionSpec` is an optional extension with no in-repo conformer. HDR tools and tests supply emission explicitly to the renderer. |
| `ShapeQueryPolarity` and `RenderingOptions.shapeQueryPolarity` | The enum was ordinary public. Only the property was SPI. The log-polar kernel reads the setting, with consumers in the color lab, shared CLI options, and ASKI-60 and footprint tests. |

## Migration

Use `@_spi(AskiResearch) import Aski` in source files that name
`ShapeQueryPolarity`. Both the enum and the property use that import in
[`RenderingOptions.swift`](../../Sources/Aski/RenderingOptions.swift). The
enum retains `.inverted` and `.direct`, and the default is `.inverted`.
The Swift compiler documents SPI imports under
[Underscored Attributes](https://github.com/swiftlang/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_spi).

The repair changes visibility and documentation. It introduces no new matching
path or storage, and requires no asset regeneration or snapshot re-record.

## Verification

On macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4, arm64,
the batch passed `just check-fast` (919 tests) and `just check`
(1,518 core tests, 178 serialized media tests, two deadlock sentinels, and
DocC). These checks ran on the base above plus the reviewed visibility,
documentation, and disabled ASKI-103 diagnostic changes, before this evidence
paragraph was added.

Separate ordinary-import probes compiled a direct charset conformance and
runtime-rasterized set, but rejected both naming `ShapeQueryPolarity` and
setting its property. An explicit SPI import compiled both enum cases and the
setting. The ordinary Aski symbol graph retained the charset declarations and
arrays among 483 symbols and contained neither the enum nor the setting.
The ShapeData assets and snapshot files have no diff from the audited base.
