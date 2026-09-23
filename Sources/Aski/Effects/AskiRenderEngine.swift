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
        return ASCIIGrid(
            cells: grid.cells,
            colorSpace: colorSpace,
            composition: grid.composition,
            maskFallback: grid.maskFallback,
            maskGroundColor: grid.maskGroundColor,
            maskUsesHardEdges: grid.maskUsesHardEdges
        )
    }

    private func applyingEngineColorSpace(to grid: TileGrid) -> TileGrid {
        guard grid.colorSpace != colorSpace else { return grid }
        return TileGrid(
            cells: grid.cells,
            colorSpace: colorSpace,
            maskFallback: grid.maskFallback,
            maskGroundColor: grid.maskGroundColor,
            maskUsesHardEdges: grid.maskUsesHardEdges
        )
    }
}
