import CoreGraphics
import Foundation
import simd

internal struct RankedConversionResult: Sendable {
    let grid: ASCIIGrid
    let candidates: ContiguousArray<UInt16>
    let candidateStride: Int
    let candidateCounts: ContiguousArray<UInt16>
}

internal struct PreparedConversion: Sendable {
    let context: ConversionContext
    let sampledCoverage: [Float]?
    let maskFallback: MaskFallback?
    let maskGroundColor: CGColor?
    let maskUsesHardEdges: Bool
}

/// The main image-to-ASCII converter.
///
/// The converter is generic over its character set and palette types to avoid
/// Swift 6 existential `Sendable` ambiguity. For the common case, use
/// `DefaultConverter`.
public struct ASCIIConverter<C: ASCIICharacterSet, P: ASCIIPalette>: Sendable {
    public var characterSet: C {
        didSet {
            glyphBank = GlyphBank.adapting(characterSet)
        }
    }
    internal private(set) var glyphBank: GlyphBank
    public var palette: P
    public var algorithm: ASCIIAlgorithm
    public var tileShape: ASCIITileShape
    public var options: RenderingOptions
    public var colorSpace: RenderColorSpace
    public var colorSampling: ColorSamplingPolicy
    public var paletteMatching: PaletteMatchingPolicy
    public var gamutMapping: GamutMappingPolicy
    public var composition: RenderCompositionPolicy
    /// Multiplier on the per-cell pixel budget. Default `2`. Set `4` (or higher)
    /// to raise cell size enough for `LogPolarKernel`'s `edgeEmphasis` Sobel path
    /// to fire. See <doc:Algorithms> "Oversampling".
    public var oversample: Int {
        didSet {
            oversample = max(1, oversample)
        }
    }

    /// Test/benchmark override for the ASTSK-51 parallel row walk. `.auto` in
    /// production; parity tests set `.forcedSerial`/`.forcedParallel` to compare
    /// byte-identity; benchmarks (separate target — hence `package`, not
    /// `internal`) force both sides of the crossover. dotMatrix ignores this
    /// and always walks serially.
    package var rowWalkMode: GridRowWalk.Mode = .auto

    public init(
        characterSet: C,
        palette: P,
        algorithm: ASCIIAlgorithm = .logPolar,
        tileShape: ASCIITileShape = .wide,
        options: RenderingOptions = .default,
        colorSpace: RenderColorSpace = .sRGB,
        oversample: Int = 2,
        colorSampling: ColorSamplingPolicy = .linearLightAverage,
        paletteMatching: PaletteMatchingPolicy = .oklabEuclidean,
        gamutMapping: GamutMappingPolicy = .rayTrace,
        composition: RenderCompositionPolicy = .encodedDisplay8Bit
    ) {
        let glyphBank = GlyphBank.adapting(characterSet)
        self.characterSet = characterSet
        self.glyphBank = glyphBank
        self.palette = palette
        self.algorithm = algorithm
        self.tileShape = tileShape
        self.options = options
        self.colorSpace = colorSpace
        self.oversample = max(1, oversample)
        self.colorSampling = colorSampling
        self.paletteMatching = paletteMatching
        self.gamutMapping = gamutMapping
        self.composition = composition
    }

    /// Converts `image` into a grid with the requested number of columns.
    ///
    /// For `logPolar` the per-cell walk runs row-parallel through
    /// `GridRowWalk` once the grid reaches `GridRowWalk.parallelCellThreshold`
    /// cells (`dotMatrix` stays serial); the result is byte-identical to a
    /// serial walk. See `rowWalkMode` and `docs/architecture.md`.
    public func convert(_ image: CGImage, columns: Int, mask: MaskOptions? = nil) -> ASCIIGrid {
        guard columns > 0, let preparation = prepareConversion(image, columns: columns, mask: mask) else {
            return ASCIIGrid(cells: [], colorSpace: colorSpace)
        }
        let outputRows: [[ASCIICell]]
        switch algorithm {
        case .logPolar:
            outputRows = ConversionEngine.renderRows(
                preparation: preparation,
                mode: rowWalkMode,
                capture: PlainCellCapture(kernel: LogPolarKernel(glyphBank: glyphBank))
            )
        case .dotMatrix:
            let context = preparation.context
            outputRows = ConversionEngine.renderRows(
                preparation: preparation,
                mode: .forcedSerial,
                capture: PlainCellCapture(
                    kernel: makeDotMatrixKernel(context: context)
                )
            )
        }
        return makeGrid(cells: outputRows, preparation: preparation)
    }

    /// Convert while retaining, per cell, the top-ranked candidate glyphs
    /// (stride-sampled) that back the animation/temporal selection. Shares the
    /// same grid-size-gated row-parallel walk as `convert(_:columns:)` and is
    /// byte-identical to a serial walk.
    internal func convertWithRankedCandidates(
        _ image: CGImage,
        columns: Int,
        candidateStride: Int,
        mask: MaskOptions? = nil
    ) -> RankedConversionResult {
        precondition(candidateStride > 0, "candidateStride must be positive")
        guard columns > 0, let preparation = prepareConversion(image, columns: columns, mask: mask) else {
            return RankedConversionResult(
                grid: ASCIIGrid(cells: [], colorSpace: colorSpace),
                candidates: [],
                candidateStride: candidateStride,
                candidateCounts: []
            )
        }

        let context = preparation.context
        let cols = context.columns
        let rows = context.rows

        var candidates = ContiguousArray<UInt16>(repeating: 0, count: rows * cols * candidateStride)
        var candidateCounts = ContiguousArray<UInt16>(repeating: 0, count: rows * cols)
        let outputRows = candidates.withUnsafeMutableBufferPointer { candidatesBuffer in
            candidateCounts.withUnsafeMutableBufferPointer { countsBuffer in
                switch algorithm {
                case .logPolar:
                    return ConversionEngine.renderRows(
                        preparation: preparation,
                        mode: rowWalkMode,
                        capture: RankedLogPolarCapture(
                            kernel: LogPolarKernel(glyphBank: glyphBank),
                            stride: candidateStride,
                            candidatesBase: candidatesBuffer.baseAddress!,
                            countsBase: countsBuffer.baseAddress!
                        )
                    )
                case .dotMatrix:
                    return ConversionEngine.renderRows(
                        preparation: preparation,
                        mode: .forcedSerial,
                        capture: RankedDotMatrixCapture(
                            kernel: makeDotMatrixKernel(context: context),
                            stride: candidateStride,
                            candidatesBase: candidatesBuffer.baseAddress!,
                            countsBase: countsBuffer.baseAddress!
                        )
                    )
                }
            }
        }

        return RankedConversionResult(
            grid: makeGrid(cells: outputRows, preparation: preparation),
            candidates: candidates,
            candidateStride: candidateStride,
            candidateCounts: candidateCounts
        )
    }

    /// Like `convert(_:columns:)`, but additionally returns a per-cell
    /// shape-residual field captured from the selected algorithm.
    ///
    /// The returned `grid` is identical to what `convert(_:columns:)` produces
    /// for the same input (same cells, characters, and colors); this method
    /// differs only by *also* returning the residual array.
    ///
    /// `residual` is **row-major**, length `grid.rows * grid.columns`, where
    /// `residual[row * grid.columns + col]` is the `scoreScored` distance for
    /// the cell at `(row, col)`. Log-polar supplies its real 60D squared-L2
    /// distance; `Float.nan` marks a dot-matrix cell with no shape residual,
    /// and consumers must filter it.
    ///
    /// On the same failure/empty branches where `convert` returns an empty
    /// grid, this returns `(empty grid, [])`.
    ///
    /// Uses the same grid-size-gated row-parallel walk as `convert(_:columns:)`;
    /// both the grid and the residual field are byte-identical to a serial walk.
    @_spi(AskiResearch)
    public func convertWithResidual(
        _ image: CGImage,
        columns: Int
    ) -> (grid: ASCIIGrid, residual: [Float]) {
        guard columns > 0, let preparation = prepareConversion(image, columns: columns, mask: nil) else {
            return (ASCIIGrid(cells: [], colorSpace: colorSpace), [])
        }
        let context = preparation.context
        let cols = context.columns
        let rows = context.rows

        var residual = [Float](repeating: 0, count: rows * cols)
        let outputRows = residual.withUnsafeMutableBufferPointer { residualBuffer in
            switch algorithm {
            case .logPolar:
                return ConversionEngine.renderRows(
                    preparation: preparation,
                    mode: rowWalkMode,
                    capture: ResidualLogPolarCapture(
                        kernel: LogPolarKernel(glyphBank: glyphBank),
                        residualBase: residualBuffer.baseAddress!
                    )
                )
            case .dotMatrix:
                return ConversionEngine.renderRows(
                    preparation: preparation,
                    mode: .forcedSerial,
                    capture: ResidualDotMatrixCapture(
                        kernel: makeDotMatrixKernel(context: context),
                        residualBase: residualBuffer.baseAddress!
                    )
                )
            }
        }

        return (
            makeGrid(cells: outputRows, preparation: preparation),
            residual
        )
    }

    // `internal` (was `private`) so the @_spi research reflection in
    // `ASCIIConverter+Research.swift` can report the resolved sampling geometry
    // without re-deriving the thumbnail/pitch arithmetic. No behavior change.
    internal func prepareConversion(
        _ image: CGImage,
        columns: Int,
        mask: MaskOptions?
    ) -> PreparedConversion? {
        let resolvedOptions = ResolvedRenderingOptions(options)
        let resolvedPalette = ResolvedPalette(
            content: palette.content,
            needsHelmlab: paletteMatching.needsHelmlab
        )
        guard
            let (cols, rows) = gridDimensions(
                imageWidth: image.width,
                imageHeight: image.height,
                columns: columns,
                tileShape: tileShape
            ),
            let maxPixelSize = thumbnailMaxPixelSize(
                image: image,
                columns: cols,
                rows: rows
            )
        else {
            return nil
        }

        let sampledCoverage = mask.flatMap { options in
            MaskSampler.sample(options, columns: cols, rows: rows)
        }
        let maskFallback = sampledCoverage == nil ? nil : mask?.fallback
        let maskGroundColor = sampledCoverage == nil ? nil : mask?.groundColor
        let maskUsesHardEdges = sampledCoverage == nil ? false : !(mask?.softEdges ?? true)

        // Sampling contract (ASKI-25, ASKI-65). The cell pitch is the FLOORED
        // integer quotient, so it stays uniform across the grid, but the raster
        // the samplers read is drawn at exactly `cols*cellWidth ×
        // rows*cellHeight` rather than at the thumbnail's own size. The
        // origin-anchored walk therefore tiles the raster exactly: there is no
        // bottom/right remainder, and the ≤ one-pitch anisotropic rescale folds
        // what used to be the unread edge back into the sampled cells. Pinned by
        // `SamplingLatticeContractTests`; `SamplingGeometry.droppedX`/`droppedY`
        // report the (now always zero) remainder to research callers.
        guard
            let thumbnail = try? ImageIOThumbnail.decode(
                image: image,
                maxPixelSize: maxPixelSize
            ),
            let lattice = samplingLattice(
                thumbnail: thumbnail,
                columns: cols,
                rows: rows,
                colorSpace: colorSpace
            )
        else {
            return nil
        }

        return PreparedConversion(
            context: ConversionContext(
                pixels: lattice.pixels,
                pixelWidth: lattice.pixelWidth,
                pixelHeight: lattice.pixelHeight,
                cellWidth: lattice.cellWidth,
                cellHeight: lattice.cellHeight,
                columns: cols,
                rows: rows,
                palette: resolvedPalette,
                options: resolvedOptions,
                colorSpace: colorSpace,
                colorSampling: colorSampling,
                paletteMatching: paletteMatching,
                gamutMapping: gamutMapping,
                composition: composition
            ),
            sampledCoverage: sampledCoverage,
            maskFallback: maskFallback,
            maskGroundColor: maskGroundColor,
            maskUsesHardEdges: maskUsesHardEdges
        )
    }

    internal func thumbnailMaxPixelSize(image: CGImage, columns: Int, rows: Int) -> Int? {
        let side = max(columns, rows)
        let result = side.multipliedReportingOverflow(by: oversample)
        guard !result.overflow, result.partialValue > 0 else {
            return nil
        }
        // `maxPixelSize` caps the thumbnail's LONGEST side, so for a portrait
        // image the width lands below `columns * oversample`, and once
        // `thumbnail.width / columns` truncates to <2 px the log-polar
        // histogram's radius gate excludes every pixel — a zero descriptor
        // exactly matches the space glyph and the whole render goes blank.
        // Cap the longest side (the height) at exactly what keeps the WIDTH
        // on the `columns * oversample` budget. Derive it from `columns`, not
        // `max(columns, rows)`: for tall sources `rows` already encodes the
        // aspect ratio, and scaling it by height/width again would inflate
        // the cap quadratically (a long screenshot could bypass thumbnail
        // downscaling entirely). Square and landscape inputs are untouched
        // (bit-identical output).
        guard image.height > image.width, image.width > 0 else {
            return result.partialValue
        }
        let widthBudget = columns.multipliedReportingOverflow(by: oversample)
        guard !widthBudget.overflow else { return nil }
        let scaled = (Double(widthBudget.partialValue) * Double(image.height) / Double(image.width))
            .rounded(.up)
        // `scaled` is a derived thumbnail dimension. `Double(Int.max)` rounds
        // to the first unrepresentable 64-bit integer, so stay strictly inside
        // the named `Int` bound before converting.
        guard scaled.isFinite, scaled > 0, scaled < Double(Int.max) else { return nil }
        return Int(scaled)
    }

    private func makeGrid(
        cells: [[ASCIICell]],
        preparation: PreparedConversion
    ) -> ASCIIGrid {
        ASCIIGrid(
            cells: cells,
            colorSpace: colorSpace,
            composition: composition,
            maskFallback: preparation.maskFallback,
            maskGroundColor: preparation.maskGroundColor,
            maskUsesHardEdges: preparation.maskUsesHardEdges
        )
    }

    private func makeDotMatrixKernel(context: ConversionContext) -> DotMatrixKernel {
        DotMatrixKernel(
            glyphBank: glyphBank,
            columns: context.columns,
            rows: context.rows,
            ditherStrength: context.options.coverage
        )
    }
}

/// Type alias for the common case: standard character set plus full-color palette.
public typealias DefaultConverter = ASCIIConverter<StandardCharacterSet, BuiltInPalette>

public extension ASCIIConverter where C == StandardCharacterSet, P == BuiltInPalette {
    /// Zero-argument convenience initializer for the default converter.
    init() {
        self.init(
            characterSet: .standard,
            palette: .fullColor
        )
    }
}
