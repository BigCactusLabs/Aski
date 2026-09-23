import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Shared bound on derived raster geometry (ASKI-17).
///
/// Every raster path derives a pixel extent from `columns/rows * glyph size *
/// scale` and converts it with `Int(ceil(...))`. That conversion traps for any
/// value that is not finite or does not fit in `Int`, which made the renderers'
/// documented degenerate fallback unreachable at the top of the accepted range
/// while it worked fine at the bottom. Bounding the derived geometry here keeps
/// the fallback reachable: out-of-range geometry yields `nil`, and each caller
/// then takes the same empty-image / empty-raster path it already takes for a
/// zero-size grid. All four raster sites share this one rule so they cannot
/// drift.
///
/// ASKI-34 adds the companion rule for *measured* CoreImage extents
/// (`finiteExtent`), which live here for the same reason: one place, so the
/// two rules cannot drift apart.
internal enum RenderPixelBounds {
    /// Largest pixel extent accepted on either axis — a 1,048,576-pixel side,
    /// far above any real render, and small enough that the derived per-row
    /// byte count (`extent * 4`) and the context allocation cannot overflow.
    static let maxPixelExtent = 1 << 20

    /// `Int(ceil(points))` when that is a representable, in-bounds pixel
    /// extent; `nil` when `points` is NaN, infinite, or beyond
    /// `maxPixelExtent`. In-bounds non-positive values are returned unchanged
    /// so the callers' existing `pixelWidth > 0` guards keep their behaviour.
    static func pixelExtent(_ points: CGFloat) -> Int? {
        guard points.isFinite else { return nil }
        let ceiled = ceil(points)
        let limit = CGFloat(maxPixelExtent)
        guard ceiled <= limit, ceiled >= -limit else { return nil }
        return Int(ceiled)
    }

    /// Whether `rect` can back a raster measurement at all: no NaN or
    /// floating-point infinity in any component, not `CGRect.null`, and not
    /// CoreImage's `CGRectInfinite`.
    ///
    /// `CGRectInfinite` is the trap that `isFinite` misses. CoreImage spells
    /// "unbounded" as origin `-8.99e307` / size `1.80e308`: every component is
    /// a *finite* `Double`, so component-wise `isFinite` says yes, while
    /// `Int(ceil(1.80e308))` still traps. `rect.isInfinite` is the only check
    /// that catches it, so both checks are needed.
    static func isMeasurableRect(_ rect: CGRect) -> Bool {
        guard !rect.isNull, !rect.isInfinite else { return false }
        return rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
    }

    /// Degradation rule for an unbounded CoreImage extent (ASKI-34).
    ///
    /// CoreImage returns `CGRectInfinite` for generator and tiled filters, so
    /// an extent that reaches a raster site can legitimately be unbounded.
    /// Such an extent is **clamped to `reference`** — the finite rect the call
    /// site already knows — rather than thrown away, because the image
    /// genuinely exists and is merely unbounded: `reference` is the region the
    /// caller was going to draw anyway, so clamping preserves the picture
    /// instead of deleting it. Returns `nil` only when neither rect is usable;
    /// the caller then takes the ASKI-17 empty-image fallback, because with no
    /// finite reference there is no region left to draw.
    ///
    /// Relation to ASKI-17's `pixelExtent`: that rule bounds geometry
    /// *derived* from caller input (`columns * glyph * scale`), where no
    /// reference rect exists, so it degrades straight to empty. This rule runs
    /// upstream of it on a *measured* CoreImage extent, where a reference does
    /// exist. The two never disagree — both refuse to let a non-representable
    /// value reach `Int(ceil(...))`; they differ only in having, or not
    /// having, something finite to fall back to.
    static func finiteExtent(_ extent: CGRect, clampedTo reference: CGRect) -> CGRect? {
        if isMeasurableRect(extent) { return extent }
        guard isMeasurableRect(reference), !reference.isEmpty else { return nil }
        return reference
    }
}

/// Per-cell emission parameters for the extended-range (HDR) render. The default
/// bloom gain is `1 + k * smoothstep(threshold, 1, cell.brightness)`; authored
/// mode uses `1 + k * glyphBoost` instead. Both modes clamp boosted linear
/// channels to `maxHeadroom`. Research-only (`@_spi(AskiResearch)`): consumed by
/// `renderExtendedRangeImage`; the SDR `renderImage` path never sees it.
@_spi(AskiResearch)
public struct GlyphEmissionSpec: Sendable, Hashable {
    private let boosts: [Character: Float]

    public init(_ boosts: [Character: Float]) {
        self.boosts = boosts
    }

    public var glyphBoosts: [Character: Float] { boosts }

    public subscript(_ character: Character) -> Float? {
        boosts[character]
    }
}

/// Optional SPI for palettes that can vend authored glyph emission. Renderers
/// still receive the resolved spec explicitly; `ASCIIGrid` does not retain its
/// source palette.
@_spi(AskiResearch)
public protocol EmissivePalette: ASCIIPalette {
    var emissionSpec: GlyphEmissionSpec { get }
}

/// Optional SPI for character sets that can vend authored glyph emission.
/// Renderers still receive the resolved spec explicitly; `ASCIIGrid` does not
/// retain its source character set.
@_spi(AskiResearch)
public protocol EmissiveCharacterSet: ASCIICharacterSet {
    var emissionSpec: GlyphEmissionSpec { get }
}

@_spi(AskiResearch)
public struct EmissionOptions: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        case brightnessCurve
        case authored(GlyphEmissionSpec)
    }

    /// Emission strength — the peak multiplicative boost above 1.0 reached as a
    /// cell's brightness approaches 1.0, or the scale applied to authored glyph
    /// boosts when `source` is `.authored`.
    public var k: Float
    /// Brightness (adjusted source OKLAB L) below which a cell does not emit.
    /// Ignored when `source` is `.authored`.
    public var threshold: Float
    /// Upper clamp on the boosted linear channel value (the headroom ceiling).
    public var maxHeadroom: Float
    /// Brightness-keyed emission by default; authored mode keys only on glyph.
    public var source: Source

    public init(k: Float, threshold: Float, maxHeadroom: Float, source: Source = .brightnessCurve) {
        self.k = k
        self.threshold = threshold
        self.maxHeadroom = maxHeadroom
        self.source = source
    }
}

/// Research-only selection between the exact-target-width rendering arms.
@_spi(AskiResearch)
public enum TargetWidthResample {
    case direct
    case supersample(factor: Int)

    /// Largest output extent on either axis that this arm can still back with
    /// an in-bounds context: the supersampled bitmap must itself fit inside
    /// `RenderPixelBounds.maxPixelExtent`. `nil` for a degenerate factor.
    internal var maxPixelExtent: Int? {
        switch self {
        case .direct:
            return RenderPixelBounds.maxPixelExtent
        case .supersample(let factor):
            guard factor >= 2 else { return nil }
            return RenderPixelBounds.maxPixelExtent / factor
        }
    }
}

public extension ASCIIGrid {
    /// Largest `targetPixelWidth` accepted by
    /// ``renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:)``.
    /// The public path renders at 4× the target, so the bound is a quarter of
    /// the renderer's pixel-extent ceiling on either axis; a wider request, or a
    /// grid whose derived height exceeds the same bound, returns the 1×1
    /// fallback image. Command-line validation mirrors this value.
    static let maxTargetPixelWidth = RenderPixelBounds.maxPixelExtent / 4
}

public extension ASCIIGrid {
    /// Renders this grid as a `CGImage` using Core Text.
    ///
    /// - Parameters:
    ///   - font: Monospaced font for the output glyphs.
    ///   - backgroundColor: Color composited behind each cell.
    ///   - scale: Pixel density multiplier, such as `2` for @2x output.
    ///   - preserveSourceAspect: When `true`, glyph cells are made as
    ///     tall as the `.wide` source-sampling cell ratio (`glyphWidth * 2.2`)
    ///     so the rendered image reproduces the source image's aspect ratio.
    ///     Default `false` keeps the historical 2.0 glyph aspect — all existing
    ///     PNG snapshot baselines are unchanged.
    func renderImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        preserveSourceAspect: Bool = false
    ) -> CGImage {
        guard scale > 0, scale.isFinite else {
            return Self.emptyImage()
        }
        guard
            let geometry = Self.renderGeometry(
                columns: columns,
                rows: rows,
                font: font,
                scale: scale,
                preserveSourceAspect: preserveSourceAspect
            )
        else {
            return Self.emptyImage()
        }

        if let groundColor = effectiveMaskGroundColor(maskGroundColor) {
            return renderImageWithMaskGround(
                font: font,
                backgroundColor: backgroundColor,
                groundColor: groundColor,
                scale: scale,
                geometry: geometry
            )
        }

        let context = CGContext(
            data: nil,
            width: geometry.pixelWidth,
            height: geometry.pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: geometry.pixelWidth * 4,
            space: cgColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else {
            return Self.emptyImage()
        }

        context.scaleBy(x: scale, y: scale)
        let pointWidth = CGFloat(geometry.pixelWidth) / scale
        let pointHeight = CGFloat(geometry.pixelHeight) / scale
        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight))
        context.textMatrix = .identity

        let fontAttribute = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorAttribute = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

        if let fallback = maskFallback,
            !fallback.isTransparentFallback,
            maskContainsCoverageBelowOne(self)
        {
            drawMaskFallbackOverlay(
                fallback,
                font: font,
                scale: scale,
                glyphWidth: geometry.glyphWidth,
                glyphHeight: geometry.glyphHeight,
                baselineOffset: geometry.baselineOffset,
                fontAttribute: fontAttribute,
                colorAttribute: colorAttribute,
                in: context
            )
        }

        // Identity transform: the encoded 8-bit display colour, byte-for-byte
        // what the renderer has always produced.
        drawCells(
            in: context,
            font: font,
            geometry: geometry,
            fontAttribute: fontAttribute,
            colorAttribute: colorAttribute
        ) { cell, effectiveAlpha in
            CGColor(
                red: CGFloat(cell.displayColor.x),
                green: CGFloat(cell.displayColor.y),
                blue: CGFloat(cell.displayColor.z),
                alpha: CGFloat(effectiveAlpha)
            )
        }

        return context.makeImage() ?? Self.emptyImage()
    }

    /// Renders this grid at an exact output pixel width.
    ///
    /// The width is installed directly in the backing context and the scale is
    /// derived from it. The renderer draws at four times the target size, then
    /// reduces each 4×4 block in linear light: under the default
    /// ``RenderCompositionPolicy/encodedDisplay8Bit`` the samples are
    /// sRGB-decoded, premultiplied-alpha averaged, and re-encoded into the
    /// grid's render colour space; under
    /// ``RenderCompositionPolicy/extendedLinearPerGamut`` the supersampled
    /// bitmap is already linear-tagged and is averaged without any transfer
    /// conversion.
    ///
    /// `targetPixelWidth` must not exceed ``maxTargetPixelWidth``, and the
    /// derived height is bound the same way; out-of-range geometry returns the
    /// 1×1 fallback image, as the scale renderer does.
    ///
    /// The ASKI-63 gate selected this supersample arm (SHIP-B, run 2). The
    /// direct arm remains reachable through the `@_spi(AskiResearch)` overload.
    func renderImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        targetPixelWidth: Int,
        preserveSourceAspect: Bool = false
    ) -> CGImage {
        renderTargetWidthImage(
            font: font,
            backgroundColor: backgroundColor,
            targetPixelWidth: targetPixelWidth,
            preserveSourceAspect: preserveSourceAspect,
            resample: .supersample(factor: 4)
        )
    }

    /// Renders this grid through an explicitly selected exact-target-width arm.
    @_spi(AskiResearch)
    func renderImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        targetPixelWidth: Int,
        preserveSourceAspect: Bool = false,
        resample: TargetWidthResample
    ) -> CGImage {
        renderTargetWidthImage(
            font: font,
            backgroundColor: backgroundColor,
            targetPixelWidth: targetPixelWidth,
            preserveSourceAspect: preserveSourceAspect,
            resample: resample
        )
    }

    /// Internal routing seam for the exact-width renderer. Tests use
    /// `subpixelPositioning: false` to bind its geometry to the legacy scale
    /// renderer without changing the new public path's Core Graphics flags.
    internal func renderTargetWidthImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        targetPixelWidth: Int,
        preserveSourceAspect: Bool,
        resample: TargetWidthResample,
        subpixelPositioning: Bool = true
    ) -> CGImage {
        guard
            let maxPixelExtent = resample.maxPixelExtent,
            let targetGeometry = Self.renderGeometry(
                columns: columns,
                rows: rows,
                font: font,
                targetPixelWidth: targetPixelWidth,
                preserveSourceAspect: preserveSourceAspect,
                maxPixelExtent: maxPixelExtent
            )
        else {
            return Self.emptyImage()
        }

        switch resample {
        case .direct:
            return renderTargetWidthDirectImage(
                font: font,
                backgroundColor: backgroundColor,
                scale: targetGeometry.scale,
                geometry: targetGeometry.geometry,
                subpixelPositioning: subpixelPositioning
            )
        case .supersample(let factor):
            return renderTargetWidthSupersampledImage(
                font: font,
                backgroundColor: backgroundColor,
                scale: targetGeometry.scale,
                geometry: targetGeometry.geometry,
                factor: factor,
                subpixelPositioning: subpixelPositioning
            )
        }
    }

    /// The exact-width counterpart to the legacy scale renderer. Its drawing
    /// sequence intentionally mirrors `renderImage(scale:)`; the optional
    /// positioning calls are the only arm-A-specific context state.
    private func renderTargetWidthDirectImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        geometry: RenderGeometry,
        subpixelPositioning: Bool
    ) -> CGImage {
        if let groundColor = effectiveMaskGroundColor(maskGroundColor) {
            return renderImageWithMaskGround(
                font: font,
                backgroundColor: backgroundColor,
                groundColor: groundColor,
                scale: scale,
                geometry: geometry,
                subpixelPositioning: subpixelPositioning
            )
        }

        let context = CGContext(
            data: nil,
            width: geometry.pixelWidth,
            height: geometry.pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: geometry.pixelWidth * 4,
            space: cgColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else {
            return Self.emptyImage()
        }

        context.scaleBy(x: scale, y: scale)
        let pointWidth = CGFloat(geometry.pixelWidth) / scale
        let pointHeight = CGFloat(geometry.pixelHeight) / scale
        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight))
        context.textMatrix = .identity

        if subpixelPositioning {
            context.setAllowsFontSubpixelPositioning(true)
            context.setShouldSubpixelPositionFonts(true)
            context.setAllowsFontSubpixelQuantization(false)
            context.setShouldSubpixelQuantizeFonts(false)
        }

        let fontAttribute = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorAttribute = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

        if let fallback = maskFallback,
            !fallback.isTransparentFallback,
            maskContainsCoverageBelowOne(self)
        {
            drawMaskFallbackOverlay(
                fallback,
                font: font,
                scale: scale,
                glyphWidth: geometry.glyphWidth,
                glyphHeight: geometry.glyphHeight,
                baselineOffset: geometry.baselineOffset,
                fontAttribute: fontAttribute,
                colorAttribute: colorAttribute,
                in: context
            )
        }

        // Identity transform: the encoded 8-bit display colour, byte-for-byte
        // what the renderer has always produced.
        drawCells(
            in: context,
            font: font,
            geometry: geometry,
            fontAttribute: fontAttribute,
            colorAttribute: colorAttribute
        ) { cell, effectiveAlpha in
            CGColor(
                red: CGFloat(cell.displayColor.x),
                green: CGFloat(cell.displayColor.y),
                blue: CGFloat(cell.displayColor.z),
                alpha: CGFloat(effectiveAlpha)
            )
        }

        return context.makeImage() ?? Self.emptyImage()
    }

    /// Renders at an integer multiple of the target geometry, then reduces each
    /// source block in linear light. The explicit supersampled height preserves
    /// the exact integer reduction factor even when the base height was ceiled.
    private func renderTargetWidthSupersampledImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        geometry: RenderGeometry,
        factor: Int,
        subpixelPositioning: Bool
    ) -> CGImage {
        guard
            factor >= 2,
            geometry.pixelWidth <= RenderPixelBounds.maxPixelExtent / factor,
            geometry.pixelHeight <= RenderPixelBounds.maxPixelExtent / factor
        else {
            return Self.emptyImage()
        }

        let factorScale = CGFloat(factor)
        let supersampledScale = scale * factorScale
        guard supersampledScale > 0, supersampledScale.isFinite else {
            return Self.emptyImage()
        }
        let supersampledGeometry = RenderGeometry(
            glyphWidth: geometry.glyphWidth,
            glyphHeight: geometry.glyphHeight,
            pixelWidth: geometry.pixelWidth * factor,
            pixelHeight: geometry.pixelHeight * factor,
            baselineOffset: geometry.baselineOffset
        )
        let supersampledImage = renderTargetWidthDirectImage(
            font: font,
            backgroundColor: backgroundColor,
            scale: supersampledScale,
            geometry: supersampledGeometry,
            subpixelPositioning: subpixelPositioning
        )
        guard
            supersampledImage.width == supersampledGeometry.pixelWidth,
            supersampledImage.height == supersampledGeometry.pixelHeight
        else {
            return Self.emptyImage()
        }

        return Self.downsampleTargetWidthImage(
            supersampledImage,
            factor: factor,
            outputWidth: geometry.pixelWidth,
            outputHeight: geometry.pixelHeight,
            colorSpace: cgColorSpace,
            sourceIsLinear: composition.kind == .extendedLinearPerGamut
        ) ?? Self.emptyImage()
    }

    /// 8-bit sRGB → linear-light lookup used by the supersample reducer.
    private static let targetWidthSRGBDecodeLUT: [Float] = (0...255).map { value in
        ColorConversion.sRGBDecode(Float(value) / 255)
    }

    /// Area-reduces an integer-factor supersampled render. With
    /// `sourceIsLinear == false` the source pixels are un-premultiplied in
    /// encoded sRGB, decoded, re-premultiplied in linear light, averaged, then
    /// returned to 8-bit premultiplied sRGB. With `sourceIsLinear == true` the
    /// bitmap was composited in a linear-tagged space
    /// (``RenderCompositionPolicy/extendedLinearPerGamut``), so its
    /// premultiplied bytes are already linear light and are box-averaged as-is;
    /// running the sRGB transfer on them would write encoded values into a
    /// linear-tagged image and bias every antialiased edge.
    internal static func downsampleTargetWidthImage(
        _ image: CGImage,
        factor: Int,
        outputWidth: Int,
        outputHeight: Int,
        colorSpace: CGColorSpace,
        sourceIsLinear: Bool
    ) -> CGImage? {
        guard
            factor >= 2,
            outputWidth > 0,
            outputHeight > 0,
            outputWidth <= RenderPixelBounds.maxPixelExtent / factor,
            outputHeight <= RenderPixelBounds.maxPixelExtent / factor
        else { return nil }

        let sourceWidth = outputWidth * factor
        let sourceHeight = outputHeight * factor
        guard image.width == sourceWidth, image.height == sourceHeight else { return nil }

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            image.bitsPerComponent == 8,
            image.bitsPerPixel == 32,
            image.bytesPerRow >= sourceWidth * 4,
            let sourceData = image.dataProvider?.data,
            let sourceBytes = CFDataGetBytePtr(sourceData),
            CFDataGetLength(sourceData) >= image.bytesPerRow * sourceHeight,
            let destinationContext = CGContext(
                data: nil,
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bytesPerRow: outputWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else { return nil }

        guard
            let destinationBytes = destinationContext.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }

        let inverseSampleCount = 1 / (Float(factor) * Float(factor))
        let decodeLUT = targetWidthSRGBDecodeLUT

        for outputY in 0..<outputHeight {
            let sourceY = outputY * factor
            for outputX in 0..<outputWidth {
                let sourceX = outputX * factor
                var red: Float = 0
                var green: Float = 0
                var blue: Float = 0
                var alpha: Float = 0

                for offsetY in 0..<factor {
                    for offsetX in 0..<factor {
                        let sourceOffset =
                            (sourceY + offsetY) * image.bytesPerRow + (sourceX + offsetX) * 4
                        let sampleAlpha = Float(sourceBytes[sourceOffset + 3]) / 255
                        alpha += sampleAlpha
                        guard sampleAlpha > 0 else { continue }

                        if sourceIsLinear {
                            // Premultiplied linear bytes: the box average of
                            // premultiplied values is the linear-light average.
                            red += Float(sourceBytes[sourceOffset]) / 255
                            green += Float(sourceBytes[sourceOffset + 1]) / 255
                            blue += Float(sourceBytes[sourceOffset + 2]) / 255
                            continue
                        }

                        let encodedRed = min(max(Float(sourceBytes[sourceOffset]) / 255 / sampleAlpha, 0), 1)
                        let encodedGreen = min(max(Float(sourceBytes[sourceOffset + 1]) / 255 / sampleAlpha, 0), 1)
                        let encodedBlue = min(max(Float(sourceBytes[sourceOffset + 2]) / 255 / sampleAlpha, 0), 1)
                        red += decodeLUT[Int((encodedRed * 255).rounded())] * sampleAlpha
                        green += decodeLUT[Int((encodedGreen * 255).rounded())] * sampleAlpha
                        blue += decodeLUT[Int((encodedBlue * 255).rounded())] * sampleAlpha
                    }
                }

                let averagedAlpha = alpha * inverseSampleCount
                let destinationOffset = (outputY * outputWidth + outputX) * 4
                guard averagedAlpha > 0 else {
                    destinationBytes[destinationOffset] = 0
                    destinationBytes[destinationOffset + 1] = 0
                    destinationBytes[destinationOffset + 2] = 0
                    destinationBytes[destinationOffset + 3] = 0
                    continue
                }

                if sourceIsLinear {
                    destinationBytes[destinationOffset] = targetWidthByte(red * inverseSampleCount)
                    destinationBytes[destinationOffset + 1] = targetWidthByte(green * inverseSampleCount)
                    destinationBytes[destinationOffset + 2] = targetWidthByte(blue * inverseSampleCount)
                    destinationBytes[destinationOffset + 3] = targetWidthByte(averagedAlpha)
                    continue
                }

                let encodedRed = ColorConversion.sRGBEncode(min(max(red * inverseSampleCount / averagedAlpha, 0), 1))
                let encodedGreen = ColorConversion.sRGBEncode(min(max(green * inverseSampleCount / averagedAlpha, 0), 1))
                let encodedBlue = ColorConversion.sRGBEncode(min(max(blue * inverseSampleCount / averagedAlpha, 0), 1))
                destinationBytes[destinationOffset] = targetWidthByte(encodedRed * averagedAlpha)
                destinationBytes[destinationOffset + 1] = targetWidthByte(encodedGreen * averagedAlpha)
                destinationBytes[destinationOffset + 2] = targetWidthByte(encodedBlue * averagedAlpha)
                destinationBytes[destinationOffset + 3] = targetWidthByte(averagedAlpha)
            }
        }

        return destinationContext.makeImage()
    }

    private static func targetWidthByte(_ value: Float) -> UInt8 {
        guard value.isFinite else { return 0 }
        return UInt8((min(max(value, 0), 1) * 255).rounded())
    }

    /// Glyph metrics + output pixel dimensions for a render. Shared by the 8-bit
    /// `renderImage` and the extended-range HDR render so both produce
    /// pixel-aligned output for the same grid/font/scale/`preserveSourceAspect`
    /// (the G1/G2 fallback-fidelity gates depend on identical geometry).
    /// Returns `nil` when the computed pixel size is degenerate.
    internal struct RenderGeometry {
        let glyphWidth: CGFloat
        let glyphHeight: CGFloat
        let pixelWidth: Int
        let pixelHeight: Int
        let baselineOffset: CGFloat
    }

    internal static func renderGeometry(
        columns: Int,
        rows: Int,
        font: ASCIIFont,
        scale: CGFloat,
        preserveSourceAspect: Bool
    ) -> RenderGeometry? {
        let glyphWidth = font.pointSize * 0.6
        let glyphHeight =
            preserveSourceAspect
            ? glyphWidth * CGFloat(ASCIITileShape.wide.sourceCellHeightOverWidth)
            : font.pointSize * 1.2
        guard
            let pixelWidth = RenderPixelBounds.pixelExtent(CGFloat(columns) * glyphWidth * scale),
            let pixelHeight = RenderPixelBounds.pixelExtent(CGFloat(rows) * glyphHeight * scale)
        else { return nil }
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        return RenderGeometry(
            glyphWidth: glyphWidth,
            glyphHeight: glyphHeight,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            baselineOffset: CTFontGetDescent(font.ctFont)
        )
    }

    /// Glyph metrics, direct output width, height, and derived scale for the
    /// exact-target-width renderer. The width must not pass through
    /// `RenderPixelBounds.pixelExtent`, because that rule intentionally rounds
    /// scale-derived extents up. `maxPixelExtent` bounds both axes of the
    /// *output*; a supersampling arm passes its reduced ceiling so the request
    /// fails here, consistently, instead of in the arm's own allocation guard.
    internal static func renderGeometry(
        columns: Int,
        rows: Int,
        font: ASCIIFont,
        targetPixelWidth: Int,
        preserveSourceAspect: Bool,
        maxPixelExtent: Int = RenderPixelBounds.maxPixelExtent
    ) -> (geometry: RenderGeometry, scale: CGFloat)? {
        guard
            maxPixelExtent > 0,
            maxPixelExtent <= RenderPixelBounds.maxPixelExtent,
            targetPixelWidth > 0,
            targetPixelWidth <= maxPixelExtent,
            columns > 0,
            rows > 0
        else { return nil }

        let glyphWidth = font.pointSize * 0.6
        let glyphHeight =
            preserveSourceAspect
            ? glyphWidth * CGFloat(ASCIITileShape.wide.sourceCellHeightOverWidth)
            : font.pointSize * 1.2
        let scale = CGFloat(targetPixelWidth) / (CGFloat(columns) * glyphWidth)
        guard scale > 0, scale.isFinite else { return nil }
        guard let pixelHeight = RenderPixelBounds.pixelExtent(CGFloat(rows) * glyphHeight * scale) else {
            return nil
        }
        guard pixelHeight > 0, pixelHeight <= maxPixelExtent else { return nil }

        return (
            RenderGeometry(
                glyphWidth: glyphWidth,
                glyphHeight: glyphHeight,
                pixelWidth: targetPixelWidth,
                pixelHeight: pixelHeight,
                baselineOffset: CTFontGetDescent(font.ctFont)
            ),
            scale
        )
    }

    /// Draws every visible cell (Core Text glyph or programmatic braille raster)
    /// into an already-prepared context. The `foregroundColor` transform maps a
    /// cell + its effective alpha to the draw colour, so the 8-bit display path
    /// and the extended-range emission path share identical geometry, alpha
    /// gating, and glyph/braille dispatch — only the colour differs.
    ///
    /// The transform is `@noescape` (it is invoked synchronously per cell and
    /// never stored), so the hot 8-bit identity path pays no allocation and only
    /// a thin call per cell — negligible against the per-cell Core Text cost.
    internal func drawCells(
        in context: CGContext,
        font: ASCIIFont,
        geometry: RenderGeometry,
        fontAttribute: NSAttributedString.Key,
        colorAttribute: NSAttributedString.Key,
        coverageMode: CellCoverageMode = .multiplyCoverage,
        foregroundColor: (ASCIICell, _ effectiveAlpha: Float) -> CGColor
    ) {
        let glyphWidth = geometry.glyphWidth
        let glyphHeight = geometry.glyphHeight
        let baselineOffset = geometry.baselineOffset
        for (rowIndex, row) in cells.enumerated() {
            let y = CGFloat(rows - rowIndex - 1) * glyphHeight + baselineOffset
            for (columnIndex, cell) in row.enumerated() {
                let rawAlpha =
                    switch coverageMode {
                    case .multiplyCoverage: cell.alpha * cell.coverage
                    case .intrinsicAlpha: cell.alpha
                    }
                let effectiveAlpha = max(0, min(1, rawAlpha))
                guard effectiveAlpha > 0 else { continue }
                let fg = foregroundColor(cell, effectiveAlpha)

                let codepoint = cell.character.unicodeScalars.first?.value ?? 0
                if (0x2800...0x28FF).contains(codepoint) {
                    // No font is bundled for braille; render the dot pattern
                    // programmatically. The cell rect uses the same baseline
                    // math as the CTLine path: each row's bottom is at
                    // (rows - rowIndex - 1) * glyphHeight.
                    let cellRect = CGRect(
                        x: CGFloat(columnIndex) * glyphWidth,
                        y: CGFloat(rows - rowIndex - 1) * glyphHeight,
                        width: glyphWidth,
                        height: glyphHeight
                    )
                    BrailleRasterizer.draw(
                        codepoint: codepoint,
                        foregroundColor: fg,
                        in: context,
                        rect: cellRect
                    )
                } else {
                    let attributed = NSAttributedString(
                        string: String(cell.character),
                        attributes: [
                            fontAttribute: font.ctFont,
                            colorAttribute: fg,
                        ]
                    )
                    let line = CTLineCreateWithAttributedString(attributed)
                    context.textPosition = CGPoint(x: CGFloat(columnIndex) * glyphWidth, y: y)
                    CTLineDraw(line, context)
                }
            }
        }
    }

    /// Renders this grid as an **extended-range** (HDR-emissive) `CGImage`:
    /// the SDR display colours with a per-cell emission gain applied in the
    /// linear domain, written into a 16-bit half-float, extended-linear context
    /// so bright glyphs exceed 1.0. Research-only (`@_spi(AskiResearch)`); the
    /// stable `renderImage` path and its [0,1] clamp are untouched.
    ///
    /// Geometry (and therefore pixel dimensions) is identical to `renderImage`
    /// for the same `font`/`scale`/`preserveSourceAspect`, so the SDR base and
    /// this extended render are pixel-aligned for gain-map authoring.
    ///
    /// **Scope: opaque, full-coverage content only.** HDR/SDR pixel-alignment (the
    /// gain-map precondition) holds only for opaque cells — an `alpha < 1` cell
    /// composites differently in this extended-linear context than in the 8-bit
    /// sRGB-gamma SDR render, and the gain map `log(HDR/SDR)` would then encode
    /// that mismatch as spurious gain. Masked / sub-1-coverage grids, non-
    /// transparent mask fallbacks (the overlay builds colours independently and
    /// draws outside the shared cell loop), a positive-alpha mask ground, and any
    /// grid containing a translucent cell are therefore **rejected** — the method returns `nil` for every
    /// can't-render-faithfully / failure path. Mask-fallback and translucent
    /// emission are future work.
    @_spi(AskiResearch)
    func renderExtendedRangeImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        preserveSourceAspect: Bool = false,
        emission: EmissionOptions
    ) -> CGImage? {
        guard scale > 0, scale.isFinite else {
            return nil
        }
        // Reject anything that breaks the opaque/full-coverage pixel-alignment
        // contract. The fallback check is constant-time; coverage and alpha share
        // one early-exit grid walk.
        guard
            !maskHasNonTransparentFallback(maskFallback),
            effectiveMaskGroundColor(maskGroundColor) == nil
        else {
            return nil
        }
        for row in cells {
            for cell in row where cell.coverage < 1 || cell.alpha < 1 {
                return nil
            }
        }
        guard
            let geometry = Self.renderGeometry(
                columns: columns,
                rows: rows,
                font: font,
                scale: scale,
                preserveSourceAspect: preserveSourceAspect
            )
        else {
            return nil
        }

        // Resolve the grid's *extended*-linear colour space internally — never via
        // the shared composition policy, whose extended-linear case feeds the
        // 8-bit effects context. Same gamut as the grid, unclamped + linear so
        // emission can exceed 1.0.
        let extendedSpace = Self.extendedLinearColorSpace(for: colorSpace)
        #if !_endian(little)
            #error("renderExtendedRangeImage assumes little-endian Float16 layout (byteOrder16Little + the floatStats reader)")
        #endif
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder16Little.rawValue  // host order on supported Apple platforms
        guard
            let context = CGContext(
                data: nil,
                width: geometry.pixelWidth,
                height: geometry.pixelHeight,
                bitsPerComponent: 16,
                bytesPerRow: geometry.pixelWidth * 8,
                space: extendedSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        let pointWidth = CGFloat(geometry.pixelWidth) / scale
        let pointHeight = CGFloat(geometry.pixelHeight) / scale
        // CoreGraphics colour-matches the (encoded, SDR-tagged) background into the
        // extended-linear space. The backdrop is non-emissive, so it lands ≈ the
        // SDR base and the gain map stays ~1 there (the built-in no-harm property).
        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight))
        context.textMatrix = .identity

        let fontAttribute = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorAttribute = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let maxHeadroom = max(1, emission.maxHeadroom)

        drawCells(
            in: context,
            font: font,
            geometry: geometry,
            fontAttribute: fontAttribute,
            colorAttribute: colorAttribute
        ) { cell, effectiveAlpha in
            Self.emissiveColor(
                for: cell,
                effectiveAlpha: effectiveAlpha,
                emission: emission,
                maxHeadroom: maxHeadroom,
                colorSpace: extendedSpace
            )
        }

        return context.makeImage()
    }

    /// The extended-linear `CGColorSpace` matching the grid's gamut. Extended
    /// (unclamped) so channel values may exceed 1.0; linear so the emission
    /// multiply is physically correct.
    internal static func extendedLinearColorSpace(for renderColorSpace: RenderColorSpace) -> CGColorSpace {
        switch renderColorSpace {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? CGColorSpaceCreateDeviceRGB()
        }
    }

    /// Builds the emissive foreground colour for a cell in the extended-linear
    /// space. Gain keys on `cell.brightness` (adjusted *source* OKLAB L), **not**
    /// `displayColor` luminance: under e.g. `BuiltInPalette.monochrome` every
    /// `displayColor` is white while `brightness` still tracks source luminance,
    /// so display-luminance keying would bloom every cell. Emission is applied in
    /// the linear domain (decode → ×gain → extended-linear), clamped to
    /// `[0, maxHeadroom]`, with NaN/Inf guarded.
    private static func emissiveColor(
        for cell: ASCIICell,
        effectiveAlpha: Float,
        emission: EmissionOptions,
        maxHeadroom: Float,
        colorSpace: CGColorSpace
    ) -> CGColor {
        // Sanitize the consumed inputs here, where they are used: a NaN `threshold`
        // would make `smoothstep` collapse into a silent hard-step at brightness ≥ 1,
        // and a NaN/negative `k` would corrupt the gain. (No `import simd` in this
        // file — local min/max, matching the inline `max(1, emission.maxHeadroom)`.)
        let k = emission.k.isFinite ? max(0, emission.k) : 0
        var gain: Float
        switch emission.source {
        case .brightnessCurve:
            let threshold = emission.threshold.isFinite ? min(max(emission.threshold, 0), 1) : 1
            let s = smoothstep(threshold, 1, cell.brightness)
            gain = 1 + k * s
        case .authored(let spec):
            let glyphBoost = spec[cell.character] ?? 0
            let boost = glyphBoost.isFinite ? max(0, glyphBoost) : 0
            gain = 1 + k * boost
        }
        if !gain.isFinite { gain = 1 }
        gain = max(1, gain)

        func channel(_ encoded: Float) -> CGFloat {
            let linear = ColorConversion.sRGBDecode(encoded)
            var boosted = linear * gain
            if !boosted.isFinite { boosted = 0 }
            return CGFloat(min(max(0, boosted), maxHeadroom))
        }

        let components: [CGFloat] = [
            channel(cell.displayColor.x),
            channel(cell.displayColor.y),
            channel(cell.displayColor.z),
            CGFloat(min(max(0, effectiveAlpha), 1)),
        ]
        return CGColor(colorSpace: colorSpace, components: components)
            ?? CGColor(red: 0, green: 0, blue: 0, alpha: CGFloat(min(max(0, effectiveAlpha), 1)))
    }

    /// Hermite smoothstep on `[edge0, edge1]`. Degenerate edges collapse to a step.
    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func renderImageWithMaskGround(
        font: ASCIIFont,
        backgroundColor: CGColor,
        groundColor: CGColor,
        scale: CGFloat,
        geometry: RenderGeometry,
        subpixelPositioning: Bool = false
    ) -> CGImage {
        guard
            let activeContext = makeBranchContext(
                geometry: geometry,
                scale: scale,
                subpixelPositioning: subpixelPositioning
            ),
            let inactiveContext = makeBranchContext(
                geometry: geometry,
                scale: scale,
                subpixelPositioning: subpixelPositioning
            )
        else {
            return Self.emptyImage()
        }

        let pointWidth = CGFloat(geometry.pixelWidth) / scale
        let pointHeight = CGFloat(geometry.pixelHeight) / scale
        let canvas = CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight)
        let fontAttribute = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorAttribute = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

        activeContext.setFillColor(backgroundColor)
        activeContext.fill(canvas)
        activeContext.setFillColor(groundColor)
        activeContext.fill(canvas)
        drawCells(
            in: activeContext,
            font: font,
            geometry: geometry,
            fontAttribute: fontAttribute,
            colorAttribute: colorAttribute,
            coverageMode: .intrinsicAlpha
        ) { cell, effectiveAlpha in
            CGColor(
                red: CGFloat(cell.displayColor.x),
                green: CGFloat(cell.displayColor.y),
                blue: CGFloat(cell.displayColor.z),
                alpha: CGFloat(effectiveAlpha)
            )
        }

        inactiveContext.setFillColor(backgroundColor)
        inactiveContext.fill(canvas)
        if let fallback = maskFallback, !fallback.isTransparentFallback {
            drawMaskFallbackOverlay(
                fallback,
                font: font,
                scale: scale,
                glyphWidth: geometry.glyphWidth,
                glyphHeight: geometry.glyphHeight,
                baselineOffset: geometry.baselineOffset,
                fontAttribute: fontAttribute,
                colorAttribute: colorAttribute,
                completedBranch: true,
                in: inactiveContext
            )
        }

        guard let activeImage = activeContext.makeImage(), let inactiveImage = inactiveContext.makeImage() else {
            return Self.emptyImage()
        }
        let extent = CGRect(x: 0, y: 0, width: geometry.pixelWidth, height: geometry.pixelHeight)
        let coverage = CoverageImageBuilder.makeASCII(
            grid: self,
            extent: extent,
            useHardEdges: maskUsesHardEdges
        )
        let blended = MaskCompositor.blendWithMask(
            source: CIImage(cgImage: activeImage),
            background: CIImage(cgImage: inactiveImage),
            mask: coverage,
            extent: extent
        )
        return EffectsRenderEngine.shared.context.createCGImage(
            blended,
            from: extent,
            format: .RGBA8,
            colorSpace: cgColorSpace
        ) ?? Self.emptyImage()
    }

    private func makeBranchContext(
        geometry: RenderGeometry,
        scale: CGFloat,
        subpixelPositioning: Bool = false
    ) -> CGContext? {
        let context = CGContext(
            data: nil,
            width: geometry.pixelWidth,
            height: geometry.pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: geometry.pixelWidth * 4,
            space: cgColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.scaleBy(x: scale, y: scale)
        context?.textMatrix = .identity
        if subpixelPositioning {
            context?.setAllowsFontSubpixelPositioning(true)
            context?.setShouldSubpixelPositionFonts(true)
            context?.setAllowsFontSubpixelQuantization(false)
            context?.setShouldSubpixelQuantizeFonts(false)
        }
        return context
    }

    private func drawMaskFallbackOverlay(
        _ fallback: MaskFallback,
        font: ASCIIFont,
        scale _: CGFloat,
        glyphWidth: CGFloat,
        glyphHeight: CGFloat,
        baselineOffset: CGFloat,
        fontAttribute: NSAttributedString.Key,
        colorAttribute: NSAttributedString.Key,
        completedBranch: Bool = false,
        in context: CGContext
    ) {
        let pointWidth = CGFloat(columns) * glyphWidth
        let pointHeight = CGFloat(rows) * glyphHeight
        for (rowIndex, row) in cells.enumerated() {
            let rectY = CGFloat(rows - rowIndex - 1) * glyphHeight
            let baselineY = rectY + baselineOffset
            for (columnIndex, cell) in row.enumerated() {
                let inverse = completedBranch ? 1 : max(0, min(1, 1 - cell.coverage))
                guard inverse > 0 else { continue }
                let rect = CGRect(
                    x: CGFloat(columnIndex) * glyphWidth,
                    y: rectY,
                    width: glyphWidth,
                    height: glyphHeight
                )
                switch fallback {
                case .transparent:
                    break
                case .solid(let color):
                    context.setFillColor(color.copy(alpha: color.alpha * CGFloat(inverse)) ?? color)
                    context.fill(rect)
                case .originalImage(let image, let sizing):
                    context.saveGState()
                    context.clip(to: rect)
                    context.setAlpha(CGFloat(inverse))
                    let drawRect = Self.fallbackImageRect(
                        image: image,
                        sizing: sizing,
                        canvas: CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight)
                    )
                    context.draw(image, in: drawRect)
                    context.restoreGState()
                case .character(let character, let color):
                    let fallbackColor: CGColor
                    if let color {
                        fallbackColor = color.copy(alpha: color.alpha * CGFloat(inverse)) ?? color
                    } else {
                        fallbackColor = CGColor(
                            red: CGFloat(cell.displayColor.x),
                            green: CGFloat(cell.displayColor.y),
                            blue: CGFloat(cell.displayColor.z),
                            alpha: CGFloat(inverse)
                        )
                    }
                    let attributed = NSAttributedString(
                        string: String(character),
                        attributes: [
                            fontAttribute: font.ctFont,
                            colorAttribute: fallbackColor,
                        ]
                    )
                    let line = CTLineCreateWithAttributedString(attributed)
                    context.textPosition = CGPoint(x: rect.minX, y: baselineY)
                    CTLineDraw(line, context)
                }
            }
        }
    }

    internal static func fallbackImageRect(image: CGImage, sizing: BackgroundSizing, canvas: CGRect) -> CGRect {
        let source = CGSize(width: image.width, height: image.height)
        guard source.width > 0, source.height > 0, canvas.width > 0, canvas.height > 0 else {
            return canvas
        }
        switch sizing {
        case .stretch:
            return canvas
        case .fill:
            let factor = max(canvas.width / source.width, canvas.height / source.height)
            let size = CGSize(width: source.width * factor, height: source.height * factor)
            return CGRect(
                x: canvas.midX - size.width / 2,
                y: canvas.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .fit:
            let factor = min(canvas.width / source.width, canvas.height / source.height)
            let size = CGSize(width: source.width * factor, height: source.height * factor)
            return CGRect(
                x: canvas.midX - size.width / 2,
                y: canvas.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    private var cgColorSpace: CGColorSpace {
        composition.cgColorSpace(for: colorSpace)
    }

    private static func emptyImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
