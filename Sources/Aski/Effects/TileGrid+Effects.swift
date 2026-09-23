import CoreGraphics
import CoreImage
import os

public extension TileGrid {
    func renderImage(
        mode: TileGridMode = .pixelArt,
        cellShape: TileCellShape = .square,
        scale: CGFloat = 1,
        backgroundColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) -> CGImage {
        guard scale > 0, scale.isFinite else {
            return TileGrid.emptyImage()
        }
        if isDefaultComposition(composition), lighting == nil, effects.effects.isEmpty {
            return renderImage(
                mode: mode,
                cellShape: cellShape,
                scale: scale,
                backgroundColor: backgroundColor
            )
        }

        let resolvedBackground: Background = {
            if case .transparent = composition.background {
                return .solid(backgroundColor)
            }
            ASCIIBEffectsLogger.warnOnceMixedBackground()
            return composition.background
        }()
        let resolvedComposition = CompositionOptions(
            background: resolvedBackground,
            characterBlendMode: composition.characterBlendMode,
            colorOverlay: composition.colorOverlay,
            perCharacter: composition.perCharacter
        )

        return EffectsRenderEngine.renderTileGridSync(
            self,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            composition: resolvedComposition,
            lighting: lighting,
            effects: effects
        )
    }

    func renderImage(
        mode: TileGridMode = .pixelArt,
        cellShape: TileCellShape = .square,
        scale: CGFloat = 1,
        backgroundColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) async throws -> CGImage {
        guard scale > 0, scale.isFinite else {
            throw EffectError.degenerateOutput
        }
        let resolvedComposition = resolveComposition(composition, backgroundColor: backgroundColor)
        try validateComposition(resolvedComposition)
        return try await EffectsRenderEngine.renderTileGridAsync(
            self,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            composition: resolvedComposition,
            lighting: lighting,
            effects: effects
        )
    }

    func renderCIImage(
        mode: TileGridMode = .pixelArt,
        cellShape: TileCellShape = .square,
        scale: CGFloat = 1,
        backgroundColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) -> CIImage {
        guard scale > 0, scale.isFinite else {
            return EffectsRenderEngine.emptyCIImage()
        }
        let resolvedComposition = resolveComposition(composition, backgroundColor: backgroundColor)
        return EffectsRenderEngine.renderTileGridCISync(
            self,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            composition: resolvedComposition,
            lighting: lighting,
            effects: effects
        )
    }

    func renderCIImage(
        mode: TileGridMode = .pixelArt,
        cellShape: TileCellShape = .square,
        scale: CGFloat = 1,
        backgroundColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) async throws -> CIImage {
        guard scale > 0, scale.isFinite else {
            throw EffectError.degenerateOutput
        }
        let resolvedComposition = resolveComposition(composition, backgroundColor: backgroundColor)
        try validateComposition(resolvedComposition)
        return try await EffectsRenderEngine.renderTileGridCIAsync(
            self,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            composition: resolvedComposition,
            lighting: lighting,
            effects: effects
        )
    }
}

extension EffectsRenderEngine {
    static func makeTileMaskInput(
        grid: TileGrid,
        mode: TileGridMode,
        cellShape: TileCellShape,
        scale: CGFloat,
        extent: CGRect
    ) -> MaskRenderInput? {
        if let groundColor = effectiveMaskGroundColor(grid.maskGroundColor) {
            let coverage = CoverageImageBuilder.makeTile(
                grid: grid,
                mode: mode,
                shape: cellShape,
                scale: scale,
                extent: extent,
                useHardEdges: grid.maskUsesHardEdges
            )
            let fallbackImage = grid.maskFallback.flatMap { fallback in
                MaskFallbackImageFactory.makeTile(
                    fallback,
                    extent: extent,
                    colorSpace: grid.colorSpace
                )
            }
            return MaskRenderInput(
                coverage: coverage,
                fallback: fallbackImage,
                activeGround: MaskFallbackImageFactory.makeGround(
                    groundColor,
                    extent: extent,
                    colorSpace: grid.colorSpace
                )
            )
        }

        guard maskContainsCoverageBelowOne(grid) else { return nil }

        let isMosaic: Bool
        if case .mosaic = mode.representation {
            isMosaic = true
        } else {
            isMosaic = false
        }

        let fallbackIsUseful = maskHasNonTransparentFallback(grid.maskFallback)
        guard isMosaic || fallbackIsUseful else { return nil }

        let coverage = CoverageImageBuilder.makeTile(
            grid: grid,
            mode: mode,
            shape: cellShape,
            scale: scale,
            extent: extent,
            useHardEdges: grid.maskUsesHardEdges
        )
        let fallbackImage = grid.maskFallback.flatMap { fallback in
            MaskFallbackImageFactory.makeTile(
                fallback,
                extent: extent,
                colorSpace: grid.colorSpace
            )
        }
        return MaskRenderInput(coverage: coverage, fallback: fallbackImage)
    }

    static func pregateMosaicRasterIfNeeded(
        _ raster: CellRaster,
        mode: TileGridMode,
        mask: MaskRenderInput?
    ) -> CellRaster {
        guard case .mosaic = mode.representation, let mask, !mask.usesGroupedComposition else { return raster }
        let extent = outputExtent(for: raster)
        let blended = MaskCompositor.blendWithMask(
            source: raster.image,
            background: CIImage(color: .clear).cropped(to: extent),
            mask: mask.coverage,
            extent: extent
        )
        return CellRaster(image: blended, pixelWidth: raster.pixelWidth, pixelHeight: raster.pixelHeight)
    }

    static func renderTileGridSync(
        _ grid: TileGrid,
        mode: TileGridMode,
        cellShape: TileCellShape,
        scale: CGFloat,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        effects: EffectChain
    ) -> CGImage {
        let coverageMode: CellCoverageMode =
            effectiveMaskGroundColor(grid.maskGroundColor) == nil ? .multiplyCoverage : .intrinsicAlpha
        let raster = CellRasterBuilder.makeTileRaster(
            grid: grid,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            coverageMode: coverageMode
        )
        guard raster.pixelWidth > 0, raster.pixelHeight > 0 else {
            return TileGrid.emptyImage()
        }
        let extent = outputExtent(for: raster)
        let mask = makeTileMaskInput(
            grid: grid,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            extent: extent
        )
        let gatedRaster = pregateMosaicRasterIfNeeded(raster, mode: mode, mask: mask)
        let final = computeFinalCIImage(
            cellRaster: gatedRaster,
            colorSpace: grid.colorSpace,
            composition: composition,
            lighting: lighting,
            effects: effects,
            mask: mask
        )

        let cgImage = shared.context.createCGImage(
            final,
            from: extent,
            format: .RGBA8,
            colorSpace: renderColorSpaceCG(grid.colorSpace)
        )
        return cgImage ?? TileGrid.emptyImage()
    }

    static func renderTileGridAsync(
        _ grid: TileGrid,
        mode: TileGridMode,
        cellShape: TileCellShape,
        scale: CGFloat,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        effects: EffectChain
    ) async throws -> CGImage {
        try Task.checkCancellation()
        let coverageMode: CellCoverageMode =
            effectiveMaskGroundColor(grid.maskGroundColor) == nil ? .multiplyCoverage : .intrinsicAlpha
        let raster = CellRasterBuilder.makeTileRaster(
            grid: grid,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            coverageMode: coverageMode
        )
        guard raster.pixelWidth > 0, raster.pixelHeight > 0 else {
            throw EffectError.degenerateOutput
        }
        let extent = outputExtent(for: raster)
        let mask = makeTileMaskInput(
            grid: grid,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            extent: extent
        )
        try Task.checkCancellation()
        let gatedRaster = pregateMosaicRasterIfNeeded(raster, mode: mode, mask: mask)
        let final = try await computeFinalCIImageAsync(
            cellRaster: gatedRaster,
            colorSpace: grid.colorSpace,
            composition: composition,
            lighting: lighting,
            effects: effects,
            mask: mask
        )

        guard
            let cgImage = shared.context.createCGImage(
                final,
                from: extent,
                format: .RGBA8,
                colorSpace: renderColorSpaceCG(grid.colorSpace)
            )
        else {
            throw EffectError.degenerateOutput
        }
        return cgImage
    }

    static func renderTileGridCISync(
        _ grid: TileGrid,
        mode: TileGridMode,
        cellShape: TileCellShape,
        scale: CGFloat,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        effects: EffectChain
    ) -> CIImage {
        let coverageMode: CellCoverageMode =
            effectiveMaskGroundColor(grid.maskGroundColor) == nil ? .multiplyCoverage : .intrinsicAlpha
        let raster = CellRasterBuilder.makeTileRaster(
            grid: grid,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            coverageMode: coverageMode
        )
        guard raster.pixelWidth > 0, raster.pixelHeight > 0 else {
            return emptyCIImage()
        }
        let extent = outputExtent(for: raster)
        let mask = makeTileMaskInput(
            grid: grid,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            extent: extent
        )
        let gatedRaster = pregateMosaicRasterIfNeeded(raster, mode: mode, mask: mask)
        return computeFinalCIImage(
            cellRaster: gatedRaster,
            colorSpace: grid.colorSpace,
            composition: composition,
            lighting: lighting,
            effects: effects,
            mask: mask
        )
    }

    static func renderTileGridCIAsync(
        _ grid: TileGrid,
        mode: TileGridMode,
        cellShape: TileCellShape,
        scale: CGFloat,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        effects: EffectChain
    ) async throws -> CIImage {
        try Task.checkCancellation()
        let coverageMode: CellCoverageMode =
            effectiveMaskGroundColor(grid.maskGroundColor) == nil ? .multiplyCoverage : .intrinsicAlpha
        let raster = CellRasterBuilder.makeTileRaster(
            grid: grid,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            coverageMode: coverageMode
        )
        guard raster.pixelWidth > 0, raster.pixelHeight > 0 else {
            throw EffectError.degenerateOutput
        }
        let extent = outputExtent(for: raster)
        let mask = makeTileMaskInput(
            grid: grid,
            mode: mode,
            cellShape: cellShape,
            scale: scale,
            extent: extent
        )
        try Task.checkCancellation()
        let gatedRaster = pregateMosaicRasterIfNeeded(raster, mode: mode, mask: mask)
        return try await computeFinalCIImageAsync(
            cellRaster: gatedRaster,
            colorSpace: grid.colorSpace,
            composition: composition,
            lighting: lighting,
            effects: effects,
            mask: mask
        )
    }
}
