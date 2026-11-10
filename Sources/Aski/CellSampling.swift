import CoreGraphics
import Foundation
import simd

internal struct CellCoord: Hashable, Sendable {
    let column: Int
    let row: Int
}

/// Per-cell aggregate produced once by the converter, before kernel dispatch.
/// Centralizes the color + alpha + L pipeline so kernels never recompute it.
internal struct CellStats: Sendable {
    let displayColor: SIMD3<Float>
    let alpha: Float
    let adjustedL: Float
    /// Pre-options L (== `oklab.x`). Preserved for research and color-sampling
    /// validation; matching kernels should consume `adjustedL`.
    let rawL: Float
}

/// First half of the per-cell pipeline: the source aggregate before palette
/// matching and gamut mapping. Shared conversion paths finalize it once after
/// sampling so they use the same brightness, alpha, and color inputs.
internal struct CellSourceStats: Sendable {
    /// Source-cell aggregate in OKLab (pre brightness/contrast).
    let oklab: SIMD3<Float>
    /// `oklab.x` run through the brightness/contrast knobs, clamped 0...1.
    let adjustedL: Float
    let alpha: Float
}

internal struct ConversionContext: Sendable {
    let pixels: [UInt8]
    let pixelWidth: Int
    let pixelHeight: Int
    let cellWidth: Int
    let cellHeight: Int
    let columns: Int
    let rows: Int
    let palette: ResolvedPalette
    let options: ResolvedRenderingOptions
    let colorSpace: RenderColorSpace
    let colorSampling: ColorSamplingPolicy
    let paletteMatching: PaletteMatchingPolicy
    let gamutMapping: GamutMappingPolicy
    let composition: RenderCompositionPolicy

    /// Whether the resolved cell footprint can carry a log-polar shape
    /// descriptor at all. Resolved once per conversion, as a pure function of
    /// `(cellWidth, cellHeight)` — no pixel is consulted.
    ///
    /// `ShapeContext.histogram60` early-returns all zeros when
    /// `min(width, height) <= 1` (`ShapeContext.swift:23`): a one-pixel axis
    /// leaves no radius inside the half-open `[0.5, min/2]` admission band, so
    /// every pixel is rejected on geometry alone. Squared-L2 from an all-zero
    /// query to a candidate is that candidate's own squared norm, and the space
    /// glyph is the only zero-norm reference in the set — so it sits at
    /// distance 0 and wins outright wherever the pre-filter admits it, and the
    /// shape term describes only the candidates, never the cell. Kernels that
    /// consume the descriptor must take an explicit fallback when this is
    /// `false` rather than let the degenerate match stand.
    ///
    /// The trigger is deliberately the *footprint*, not "the histogram summed
    /// to zero": a dark cell legitimately produces an all-zero histogram at any
    /// footprint, because every pixel sits under the 0.05 weight gate
    /// (`ShapeContext.swift:32`), and treating that as degenerate would rewrite
    /// every dark region of every render.
    let cellSupportsShapeDescriptor: Bool

    init(
        pixels: [UInt8],
        pixelWidth: Int,
        pixelHeight: Int,
        cellWidth: Int,
        cellHeight: Int,
        columns: Int,
        rows: Int,
        palette: ResolvedPalette = .passThrough,
        options: ResolvedRenderingOptions,
        colorSpace: RenderColorSpace,
        colorSampling: ColorSamplingPolicy = .encodedAverageLegacy,
        paletteMatching: PaletteMatchingPolicy = .oklabEuclidean,
        gamutMapping: GamutMappingPolicy = .rayTrace,
        composition: RenderCompositionPolicy = .encodedDisplay8Bit
    ) {
        self.pixels = pixels
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.cellSupportsShapeDescriptor = min(cellWidth, cellHeight) > 1
        self.columns = columns
        self.rows = rows
        self.palette = palette
        self.options = options
        self.colorSpace = colorSpace
        self.colorSampling = colorSampling
        self.paletteMatching = paletteMatching
        self.gamutMapping = gamutMapping
        self.composition = composition
    }
}

/// Compute (cols, rows) for a converter grid, given image aspect and the
/// converter's source-cell aspect ratio. Returns `nil` when the inputs cannot
/// produce representable grid dimensions.
internal func gridDimensions(
    imageWidth: Int,
    imageHeight: Int,
    columns: Int,
    tileShape: ASCIITileShape
) -> (cols: Int, rows: Int)? {
    guard imageWidth > 0, imageHeight > 0, columns > 0 else {
        return nil
    }

    let denominator = Double(tileShape.sourceCellHeightOverWidth)
    guard denominator.isFinite, denominator > 0 else {
        return nil
    }

    let aspectRatio = Double(imageHeight) / Double(imageWidth)
    let projectedRows = (Double(columns) * aspectRatio) / denominator
    guard projectedRows.isFinite, projectedRows > 0, projectedRows < Double(Int.max) else {
        return nil
    }

    // `projectedRows` is the named representable-row bound: it is finite and
    // in `0..<Double(Int.max)` before this conversion.
    let rows = max(1, Int(projectedRows))
    return (columns, rows)
}

/// Draws `image` into an 8-bit-per-component RGBA backing store at the image's
/// own size. See the `width:height:` overload for the general case.
internal func readRGBA8(_ image: CGImage, targetColorSpace: RenderColorSpace) -> [UInt8]? {
    readRGBA8(image, width: image.width, height: image.height, targetColorSpace: targetColorSpace)
}

/// Draws `image` into an 8-bit-per-component RGBA backing store of exactly
/// `width × height` using the caller's target color space, returning the raw
/// `[UInt8]` pixel buffer in premultiplied-last layout. Returns `nil` if the
/// requested size is not positive or CGContext creation fails.
///
/// The converter passes the **sampling lattice** size here, not the thumbnail's
/// own size, so the drawn raster is an exact multiple of the grid and every
/// source pixel lands inside some cell (ASKI-65). The rescale is at most one
/// cell pitch on each axis and is anisotropic by up to that much; `.high`
/// interpolation makes it an area-weighted fold of the remainder rather than a
/// nearest-neighbour drop.
internal func readRGBA8(
    _ image: CGImage,
    width: Int,
    height: Int,
    targetColorSpace: RenderColorSpace
) -> [UInt8]? {
    guard width > 0, height > 0 else {
        return nil
    }

    let colorSpace: CGColorSpace
    switch targetColorSpace {
    case .sRGB:
        colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    case .displayP3:
        colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
    }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    let didDraw = pixels.withUnsafeMutableBytes { rawBuffer in
        guard
            let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            return false
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }

    return didDraw ? pixels : nil
}

/// The converter's sampling lattice for a decoded `thumbnail` at `columns × rows`.
///
/// The cell pitch stays the floored integer quotient of the thumbnail size by
/// the grid size — a uniform pitch, so the cell-height parity split that made
/// the fractional lattice unusable (ASKI-25 phase B2) cannot fire. The raster
/// the samplers read is then drawn at exactly `columns*cellWidth ×
/// rows*cellHeight`, so `pixelWidth`/`pixelHeight` are exact multiples of the
/// grid, the origin-anchored walk covers the whole raster, and no source row or
/// column goes unread (ASKI-65). The scale from thumbnail to lattice is at most
/// one cell pitch per axis.
///
/// Returns `nil` when the grid is non-positive or the pitch degenerates to zero
/// on either axis — the branches where every caller already bails.
internal func samplingLattice(
    thumbnail: CGImage,
    columns: Int,
    rows: Int,
    colorSpace: RenderColorSpace
) -> (pixels: [UInt8], cellWidth: Int, cellHeight: Int, pixelWidth: Int, pixelHeight: Int)? {
    guard columns > 0, rows > 0 else {
        return nil
    }
    let cellWidth = thumbnail.width / columns
    let cellHeight = thumbnail.height / rows
    guard cellWidth > 0, cellHeight > 0 else {
        return nil
    }
    let pixelWidth = columns * cellWidth
    let pixelHeight = rows * cellHeight
    guard
        let pixels = readRGBA8(
            thumbnail,
            width: pixelWidth,
            height: pixelHeight,
            targetColorSpace: colorSpace
        )
    else {
        return nil
    }
    return (pixels, cellWidth, cellHeight, pixelWidth, pixelHeight)
}

/// Returns the OKLab of the palette color in `palette` nearest to `query` under
/// `policy`. For Helmlab policies the query is converted to MetricSpace at match
/// time and distance is measured there, but the matched entry's OKLab is still
/// returned (downstream is OKLab→display). Caller guarantees `palette` is
/// non-empty; Helmlab policies require each entry's `.helmlab` to be populated.
internal func nearestPaletteMatch(
    _ query: SIMD3<Float>,
    palette: [ResolvedPaletteColor],
    policy: PaletteMatchingPolicy = .oklabEuclidean
) -> SIMD3<Float> {
    switch policy.kind {
    case .oklabEuclidean:
        var nearest = palette[0].oklab
        var nearestDistance = Float.infinity
        for color in palette {
            let distance = simd_length_squared(color.oklab - query)
            if distance < nearestDistance {
                nearest = color.oklab
                nearestDistance = distance
            }
        }
        return nearest
    case .oklabHyAB:
        // |ΔL| + √(Δa² + Δb²) — ported verbatim from Tools/AskiColorLab/
        // PaletteMatching/PaletteMatchPolicies.swift:16-19. Unlike Euclidean,
        // HyAB is not monotonic in its squared form, so the full distance is
        // computed each iteration.
        var nearest = palette[0].oklab
        var nearestDistance = Float.infinity
        for color in palette {
            let delta = color.oklab - query
            let distance = abs(delta.x) + simd_length(SIMD2<Float>(delta.y, delta.z))
            if distance < nearestDistance {
                nearest = color.oklab
                nearestDistance = distance
            }
        }
        return nearest
    case .helmlabEuclidean, .helmlabCompressed:
        // Convert the query OKLab → linRGB → XYZ → MetricSpace once. The
        // OKLab→linRGB→XYZ composition is gamut-invariant, so the sRGB pair is
        // canonical regardless of the converter's target gamut. The matched
        // entry's OKLab is still returned (downstream is OKLab→display).
        let queryLinRGB = ColorConversion.oklabToLinearSRGB(query)
        let queryXYZ = ColorConversion.linearSRGBToXYZ(SIMD3<Double>(queryLinRGB))
        let queryHelmlab = HelmlabMetric.xyzToHelmlabMetric(queryXYZ)

        var nearest = palette[0].oklab
        var nearestDistance = Double.infinity
        for color in palette {
            guard let candidateHelmlab = color.helmlab else {
                preconditionFailure("Helmlab policy requires ResolvedPaletteColor.helmlab to be populated; resolve the palette with needsHelmlab: true")
            }
            let distance =
                policy.kind == .helmlabEuclidean
                ? HelmlabMetric.euclideanDistance(queryHelmlab, candidateHelmlab)
                : HelmlabMetric.compressedDeltaE(queryHelmlab, candidateHelmlab)
            if distance < nearestDistance {
                nearest = color.oklab
                nearestDistance = distance
            }
        }
        return nearest
    }
}

internal func nearestPaletteOKLAB(
    _ query: SIMD3<Float>,
    palette: [SIMD3<Float>]
) -> SIMD3<Float> {
    var nearest = palette[0]
    var nearestDistance = Float.infinity
    for color in palette {
        let distance = simd_length_squared(color - query)
        if distance < nearestDistance {
            nearest = color
            nearestDistance = distance
        }
    }
    return nearest
}

internal func mapToDisplayColor(
    for oklab: SIMD3<Float>,
    colorSpace: RenderColorSpace,
    policy: GamutMappingPolicy
) -> SIMD3<Float> {
    let linearRGB: SIMD3<Float>
    switch policy.kind {
    case .adaptiveL0:
        switch colorSpace {
        case .sRGB:
            linearRGB = GamutMapping.adaptiveL0ToSRGB(oklab)
        case .displayP3:
            linearRGB = GamutMapping.adaptiveL0ToDisplayP3(oklab)
        }
    case .rayTrace:
        switch colorSpace {
        case .sRGB:
            linearRGB = GamutMapping.rayTraceToSRGB(oklab)
        case .displayP3:
            linearRGB = GamutMapping.rayTraceToDisplayP3(oklab)
        }
    case .clip:
        switch colorSpace {
        case .sRGB:
            linearRGB = ColorConversion.oklabToLinearSRGB(oklab)
        case .displayP3:
            linearRGB = ColorConversion.oklabToLinearP3(oklab)
        }
    }

    return simd_clamp(
        SIMD3(
            ColorConversion.sRGBEncode(linearRGB.x),
            ColorConversion.sRGBEncode(linearRGB.y),
            ColorConversion.sRGBEncode(linearRGB.z)
        ),
        SIMD3<Float>(0, 0, 0),
        SIMD3<Float>(1, 1, 1)
    )
}

private struct SampledCellColor {
    let linearRGB: SIMD3<Float>
    let alpha: Float
}

internal extension ConversionContext {
    private static let sRGBDecodeLUT = (0...255).map {
        ColorConversion.sRGBDecode(Float($0) / 255)
    }

    /// Both samplers below index `baseX = column * cellWidth`,
    /// `baseY = row * cellHeight` and walk exactly `cellWidth × cellHeight`
    /// pixels. The raster is drawn at exactly `columns*cellWidth ×
    /// rows*cellHeight` (`samplingLattice`), so the origin-anchored walk tiles
    /// it exactly: every pixel of the raster belongs to one cell and none is
    /// left over. See `ASCIIConverter.prepareConversion` and
    /// `SamplingLatticeContractTests`.
    private func sampledCellColor(at coord: CellCoord) -> SampledCellColor {
        switch colorSampling.kind {
        case .encodedAverageLegacy:
            return encodedAverageLegacy(at: coord)
        case .linearLightAverage:
            return linearLightAverage(at: coord)
        }
    }

    private func encodedAverageLegacy(at coord: CellCoord) -> SampledCellColor {
        var redSum: Float = 0
        var greenSum: Float = 0
        var blueSum: Float = 0
        var alphaSum: Float = 0
        let count = Float(cellWidth * cellHeight)
        let baseX = coord.column * cellWidth
        let baseY = coord.row * cellHeight

        pixels.withUnsafeBufferPointer { pixels in
            for dy in 0..<cellHeight {
                var offset = ((baseY + dy) * pixelWidth + baseX) * 4
                for _ in 0..<cellWidth {
                    let alpha = Float(pixels[offset + 3]) / 255
                    let red = Float(pixels[offset]) / 255
                    let green = Float(pixels[offset + 1]) / 255
                    let blue = Float(pixels[offset + 2]) / 255
                    if alpha > 0 {
                        redSum += min(red / alpha, 1)
                        greenSum += min(green / alpha, 1)
                        blueSum += min(blue / alpha, 1)
                    }
                    alphaSum += alpha
                    offset += 4
                }
            }
        }

        let encodedRGB = SIMD3(redSum / count, greenSum / count, blueSum / count)
        return SampledCellColor(
            linearRGB: SIMD3(
                ColorConversion.sRGBDecode(encodedRGB.x),
                ColorConversion.sRGBDecode(encodedRGB.y),
                ColorConversion.sRGBDecode(encodedRGB.z)
            ),
            alpha: alphaSum / count
        )
    }

    private func linearLightAverage(at coord: CellCoord) -> SampledCellColor {
        var linearSum = SIMD3<Float>(0, 0, 0)
        var alphaSum: Float = 0
        let count = Float(cellWidth * cellHeight)
        let baseX = coord.column * cellWidth
        let baseY = coord.row * cellHeight

        pixels.withUnsafeBufferPointer { pixels in
            for dy in 0..<cellHeight {
                var offset = ((baseY + dy) * pixelWidth + baseX) * 4
                for _ in 0..<cellWidth {
                    let alphaByte = pixels[offset + 3]
                    let alpha = Float(alphaByte) / 255
                    if alphaByte == 255 {
                        let linearRGB = SIMD3<Float>(
                            Self.sRGBDecodeLUT[Int(pixels[offset])],
                            Self.sRGBDecodeLUT[Int(pixels[offset + 1])],
                            Self.sRGBDecodeLUT[Int(pixels[offset + 2])]
                        )
                        linearSum += linearRGB
                        alphaSum += 1
                    } else if alphaByte > 0 {
                        let encodedRGB = SIMD3<Float>(
                            min((Float(pixels[offset]) / 255) / alpha, 1),
                            min((Float(pixels[offset + 1]) / 255) / alpha, 1),
                            min((Float(pixels[offset + 2]) / 255) / alpha, 1)
                        )
                        let linearRGB = SIMD3<Float>(
                            ColorConversion.sRGBDecode(encodedRGB.x),
                            ColorConversion.sRGBDecode(encodedRGB.y),
                            ColorConversion.sRGBDecode(encodedRGB.z)
                        )
                        linearSum += linearRGB * alpha
                        alphaSum += alpha
                    }
                    offset += 4
                }
            }
        }

        let linearRGB = alphaSum > 0 ? linearSum / alphaSum : SIMD3<Float>(0, 0, 0)
        return SampledCellColor(linearRGB: linearRGB, alpha: alphaSum / count)
    }

    /// Compute the per-cell aggregate for `coord` - averaged unpremultiplied RGB
    /// in source space, converted to OKLAB, brightness/contrast adjusted, palette
    /// matched, then gamut-mapped back to display RGB.
    func cellStats(at coord: CellCoord) -> CellStats {
        finalizeColor(source: cellSourceStats(at: coord))
    }

    /// Source aggregate only: sample, matrix to OKLab, apply brightness/contrast.
    /// Stops before the palette match so callers can finalize color more than once.
    func cellSourceStats(at coord: CellCoord) -> CellSourceStats {
        let sampled = sampledCellColor(at: coord)
        let linearRGB = sampled.linearRGB
        let oklab: SIMD3<Float>
        switch colorSpace {
        case .sRGB: oklab = ColorConversion.linearSRGBToOKLAB(linearRGB)
        case .displayP3: oklab = ColorConversion.linearP3ToOKLAB(linearRGB)
        }
        let rawL = oklab.x
        let adjustedL = simd_clamp(
            ((rawL - 0.5) * (1 + options.contrast) + 0.5) + options.brightness,
            0,
            1
        )
        return CellSourceStats(oklab: oklab, adjustedL: adjustedL, alpha: sampled.alpha)
    }

    /// Second half: palette match on the adjusted query, gamut-map to display.
    /// Identical math to the pre-split `cellStats` tail.
    func finalizeColor(source: CellSourceStats) -> CellStats {
        let queryOKLAB = SIMD3(source.adjustedL, source.oklab.y, source.oklab.z)
        let matchedOKLAB =
            palette.isPassThrough
            ? queryOKLAB
            : nearestPaletteMatch(queryOKLAB, palette: palette.colors, policy: paletteMatching)
        let displayColor = mapToDisplayColor(
            for: matchedOKLAB,
            colorSpace: colorSpace,
            policy: gamutMapping
        )

        return CellStats(
            displayColor: displayColor,
            alpha: source.alpha,
            adjustedL: source.adjustedL,
            rawL: source.oklab.x
        )
    }
}
