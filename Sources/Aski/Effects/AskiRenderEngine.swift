import CoreGraphics
import CoreImage

public actor AskiRenderEngine {
    private let colorSpace: RenderColorSpace
    private let _deviceCapability: DeviceCapability

    public init(colorSpace: RenderColorSpace = .sRGB) {
        self.colorSpace = colorSpace
        self._deviceCapability =
            MetalSupport.supportsStitchableKernels()
            ? .full
            : .reducedQuality(.metallibUnsupported)
    }

    public var deviceCapability: DeviceCapability { _deviceCapability }

    public func flushCaches() {
        EffectsRenderEngine.shared.context.clearCaches()
    }

    public func render(
        _ grid: ASCIIGrid,
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) async throws -> CGImage {
        try await applyingEngineColorSpace(to: grid).renderImage(
            font: font,
            backgroundColor: backgroundColor,
            scale: scale,
            composition: composition,
            lighting: lighting,
            effects: effects
        )
    }

    public func render(
        _ grid: TileGrid,
        mode: TileGridMode = .pixelArt,
        cellShape: TileCellShape = .square,
        scale: CGFloat = 1,
        backgroundColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) async throws -> CGImage {
        try await applyingEngineColorSpace(to: grid).renderImage(
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            backgroundColor: backgroundColor,
            composition: composition,
            lighting: lighting,
            effects: effects
        )
    }

    public func renderCIImage(
        _ grid: ASCIIGrid,
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) async throws -> CIImage {
        try await applyingEngineColorSpace(to: grid).renderCIImage(
            font: font,
            backgroundColor: backgroundColor,
            scale: scale,
            composition: composition,
            lighting: lighting,
            effects: effects
        )
    }

    public func renderCIImage(
        _ grid: TileGrid,
        mode: TileGridMode = .pixelArt,
        cellShape: TileCellShape = .square,
        scale: CGFloat = 1,
        backgroundColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) async throws -> CIImage {
        try await applyingEngineColorSpace(to: grid).renderCIImage(
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            backgroundColor: backgroundColor,
            composition: composition,
            lighting: lighting,
            effects: effects
        )
    }

    private func applyingEngineColorSpace(to grid: ASCIIGrid) -> ASCIIGrid {
        guard grid.colorSpace != colorSpace else { return grid }
        var colors: [SIMD3<Float>: SIMD3<Float>] = [:]
        let cells = grid.cells.map { row in
            row.map { cell in
                ASCIICell(
                    character: cell.character,
                    displayColor: convertedDisplayColor(cell.displayColor, from: grid.colorSpace, cache: &colors),
                    alpha: cell.alpha,
                    brightness: cell.brightness,
                    coverage: cell.coverage
                )
            }
        }
        return ASCIIGrid(
            cells: cells,
            colorSpace: colorSpace,
            composition: grid.composition,
            maskFallback: pinLiteralMaskFallback(grid.maskFallback, to: grid.colorSpace),
            maskGroundColor: grid.maskGroundColor.map { pinLiteralMaskColor($0, to: grid.colorSpace) },
            maskUsesHardEdges: grid.maskUsesHardEdges
        )
    }

    private func applyingEngineColorSpace(to grid: TileGrid) -> TileGrid {
        guard grid.colorSpace != colorSpace else { return grid }
        var colors: [SIMD3<Float>: SIMD3<Float>] = [:]
        let cells = grid.cells.map { row in
            row.map { cell in
                TileCell(
                    displayColor: convertedDisplayColor(cell.displayColor, from: grid.colorSpace, cache: &colors),
                    alpha: cell.alpha,
                    brightness: cell.brightness,
                    coverage: cell.coverage
                )
            }
        }
        return TileGrid(
            cells: cells,
            colorSpace: colorSpace,
            maskFallback: pinLiteralMaskFallback(grid.maskFallback, to: grid.colorSpace),
            maskGroundColor: grid.maskGroundColor.map { pinLiteralMaskColor($0, to: grid.colorSpace) },
            maskUsesHardEdges: grid.maskUsesHardEdges
        )
    }

    private func convertedDisplayColor(
        _ rgb: SIMD3<Float>,
        from source: RenderColorSpace,
        cache: inout [SIMD3<Float>: SIMD3<Float>]
    ) -> SIMD3<Float> {
        if let converted = cache[rgb] { return converted }
        guard
            let converted = source.encodedColor(rgb, alpha: 1).converted(
                to: colorSpace.encodedCGColorSpace, intent: .perceptual, options: nil
            ), let components = converted.components, components.count >= 3
        else {
            preconditionFailure("Known RGB color spaces must support color matching")
        }
        let result = SIMD3<Float>(
            Float(max(0, min(1, components[0]))),
            Float(max(0, min(1, components[1]))),
            Float(max(0, min(1, components[2])))
        )
        cache[rgb] = result
        return result
    }

    private func pinLiteralMaskFallback(_ fallback: MaskFallback?, to source: RenderColorSpace) -> MaskFallback? {
        guard let fallback else { return nil }
        guard case .solid(let color) = fallback else { return fallback }
        return .solid(pinLiteralMaskColor(color, to: source))
    }

    private func pinLiteralMaskColor(_ color: CGColor, to source: RenderColorSpace) -> CGColor {
        // The mask factory interprets Generic RGB and unnamed RGB components
        // literally in the grid gamut. Preserve that original meaning when the
        // engine changes the grid gamut; named caller colors keep their tags.
        guard color.alpha.isFinite, color.colorSpace?.model == .rgb,
            let components = color.components, components.count >= 3
        else { return color }
        if let name = color.colorSpace?.name, (name as String) != "kCGColorSpaceGenericRGB" {
            return color
        }
        guard
            let pinned = CGColor(
                colorSpace: source.encodedCGColorSpace,
                components: [
                    max(0, min(1, components[0])),
                    max(0, min(1, components[1])),
                    max(0, min(1, components[2])),
                    color.alpha,
                ]
            )
        else {
            preconditionFailure("Known RGB color spaces must accept RGBA components")
        }
        return pinned
    }
}
