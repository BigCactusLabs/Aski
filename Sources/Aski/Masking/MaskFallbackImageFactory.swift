import CoreGraphics
import CoreImage
import simd

internal enum MaskFallbackImageFactory {
    static func makeGround(
        _ color: CGColor,
        extent: CGRect,
        colorSpace: RenderColorSpace
    ) -> CIImage {
        solidColorImage(color, extent: extent, colorSpace: colorSpace)
    }

    static func makeASCII(
        _ fallback: MaskFallback,
        grid: ASCIIGrid,
        font: ASCIIFont,
        scale: CGFloat,
        extent: CGRect,
        colorSpace: RenderColorSpace
    ) -> CIImage? {
        switch fallback {
        case .transparent:
            return nil
        case .solid(let color):
            return solidColorImage(color, extent: extent, colorSpace: colorSpace)
        case .originalImage(let image, let sizing):
            return BackgroundResolver().resolve(.original(image, sizing: sizing), outputExtent: extent)
        case .character(let character, let color):
            return makeCharacterFallback(
                character: character,
                color: color,
                grid: grid,
                font: font,
                scale: scale
            )?.cropped(to: extent)
        }
    }

    static func makeTile(
        _ fallback: MaskFallback,
        extent: CGRect,
        colorSpace: RenderColorSpace
    ) -> CIImage? {
        switch fallback {
        case .transparent:
            return nil
        case .solid(let color):
            return solidColorImage(color, extent: extent, colorSpace: colorSpace)
        case .originalImage(let image, let sizing):
            return BackgroundResolver().resolve(.original(image, sizing: sizing), outputExtent: extent)
        case .character:
            MaskLogger.warnOnceTileCharacterFallbackIgnored()
            return nil
        }
    }

    private static func solidColorImage(
        _ color: CGColor,
        extent: CGRect,
        colorSpace: RenderColorSpace
    ) -> CIImage {
        let target = EffectsRenderEngine.renderColorSpaceCG(colorSpace)
        let ci: CIColor
        if let literalRGB = literalRGBColor(color) {
            ci = literalRGB
        } else if let converted = color.converted(to: target, intent: .perceptual, options: nil) {
            ci = CIColor(cgColor: converted)
        } else if color.colorSpace?.model == .monochrome, let white = color.components?.first {
            ci = CIColor(red: white, green: white, blue: white, alpha: color.alpha)
        } else if color.colorSpace?.model == .rgb,
            let components = color.components,
            components.count >= 3
        {
            ci = CIColor(
                red: CGFloat(components[0]),
                green: CGFloat(components[1]),
                blue: CGFloat(components[2]),
                alpha: color.alpha
            )
        } else {
            ci = CIColor(cgColor: color)
        }
        let normalized = CIColor(
            red: max(0, min(1, ci.red)),
            green: max(0, min(1, ci.green)),
            blue: max(0, min(1, ci.blue)),
            alpha: max(0, min(1, ci.alpha))
        )
        let tagged =
            CIColor(
                red: normalized.red,
                green: normalized.green,
                blue: normalized.blue,
                alpha: normalized.alpha,
                colorSpace: target
            ) ?? normalized
        return CIImage(color: tagged).cropped(to: extent)
    }

    private static func literalRGBColor(_ color: CGColor) -> CIColor? {
        guard color.colorSpace?.model == .rgb,
            let components = color.components,
            components.count >= 3,
            shouldTreatAsLiteralRGB(color.colorSpace)
        else {
            return nil
        }
        return CIColor(
            red: CGFloat(components[0]),
            green: CGFloat(components[1]),
            blue: CGFloat(components[2]),
            alpha: color.alpha
        )
    }

    private static func shouldTreatAsLiteralRGB(_ colorSpace: CGColorSpace?) -> Bool {
        guard let colorSpace else { return true }
        guard let name = colorSpace.name else { return true }
        return (name as String) == "kCGColorSpaceGenericRGB"
    }

    private static func makeCharacterFallback(
        character: Character,
        color: CGColor?,
        grid: ASCIIGrid,
        font: ASCIIFont,
        scale: CGFloat
    ) -> CIImage? {
        let syntheticRows = grid.cells.map { row in
            row.map { cell in
                let resolved = resolveCharacterColor(color, fallbackCell: cell, colorSpace: grid.colorSpace)
                return ASCIICell(
                    character: character,
                    displayColor: resolved.rgb,
                    alpha: resolved.alpha,
                    brightness: 1,
                    coverage: 1
                )
            }
        }
        let syntheticGrid = ASCIIGrid(
            cells: syntheticRows,
            colorSpace: grid.colorSpace,
            maskFallback: nil,
            maskUsesHardEdges: false
        )
        let raster = CellRasterBuilder.makeASCIIRaster(grid: syntheticGrid, font: font, scale: scale)
        guard raster.pixelWidth > 0, raster.pixelHeight > 0 else { return nil }
        return raster.image
    }

    private static func resolveCharacterColor(
        _ color: CGColor?,
        fallbackCell: ASCIICell,
        colorSpace: RenderColorSpace
    ) -> (rgb: SIMD3<Float>, alpha: Float) {
        guard let color else {
            return (fallbackCell.displayColor, 1)
        }

        let target = EffectsRenderEngine.renderColorSpaceCG(colorSpace)
        guard let converted = color.converted(to: target, intent: .perceptual, options: nil) else {
            MaskLogger.warnOnceFallbackColorConversionFailed()
            return (SIMD3<Float>(1, 1, 1), 1)
        }

        let ci = CIColor(cgColor: converted)
        return (
            SIMD3<Float>(
                Float(max(0, min(1, ci.red))),
                Float(max(0, min(1, ci.green))),
                Float(max(0, min(1, ci.blue)))
            ),
            Float(max(0, min(1, ci.alpha)))
        )
    }
}
