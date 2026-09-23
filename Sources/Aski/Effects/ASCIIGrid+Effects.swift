import CoreGraphics
import CoreImage
import Foundation
import os

internal let effectsLog = OSLog(subsystem: "com.bigcactuslabs.aski", category: "Effects")

public extension ASCIIGrid {
    /// Renders this grid as a `CGImage` with the requested composition and effects.
    ///
    /// This non-throwing overload falls back to `CIBlendKernel.sourceOver` when
    /// `composition.characterBlendMode` or `composition.colorOverlay?.blendMode`
    /// is unknown to this version of Aski.
    func renderImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) -> CGImage {
        guard scale > 0, scale.isFinite else {
            return ASCIIGrid.emptyImageFallback()
        }
        if isDefaultComposition(composition), lighting == nil, effects.effects.isEmpty {
            return renderImage(font: font, backgroundColor: backgroundColor, scale: scale)
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

        return EffectsRenderEngine.renderASCIIGridSync(
            self,
            font: font,
            scale: scale,
            composition: resolvedComposition,
            lighting: lighting,
            effects: effects
        )
    }

    /// Renders this grid asynchronously as a `CGImage` with the requested composition and effects.
    ///
    /// Unknown `composition.characterBlendMode` and
    /// `composition.colorOverlay?.blendMode` values fall back to
    /// `CIBlendKernel.sourceOver` instead of throwing.
    func renderImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) async throws -> CGImage {
        guard scale > 0, scale.isFinite else {
            throw EffectError.degenerateOutput
        }
        let resolvedComposition = resolveComposition(composition, backgroundColor: backgroundColor)
        return try await EffectsRenderEngine.renderASCIIGridAsync(
            self,
            font: font,
            scale: scale,
            composition: resolvedComposition,
            lighting: lighting,
            effects: effects
        )
    }

    func renderCIImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) -> CIImage {
        guard scale > 0, scale.isFinite else {
            return EffectsRenderEngine.emptyCIImage()
        }
        let resolvedComposition = resolveComposition(composition, backgroundColor: backgroundColor)
        return EffectsRenderEngine.renderASCIIGridCISync(
            self,
            font: font,
            scale: scale,
            composition: resolvedComposition,
            lighting: lighting,
            effects: effects
        )
    }

    func renderCIImage(
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) async throws -> CIImage {
        guard scale > 0, scale.isFinite else {
            throw EffectError.degenerateOutput
        }
        let resolvedComposition = resolveComposition(composition, backgroundColor: backgroundColor)
        try validateComposition(resolvedComposition)
        return try await EffectsRenderEngine.renderASCIIGridCIAsync(
            self,
            font: font,
            scale: scale,
            composition: resolvedComposition,
            lighting: lighting,
            effects: effects
        )
    }
}

internal func isDefaultComposition(_ options: CompositionOptions) -> Bool {
    guard case .transparent = options.background else {
        return false
    }
    return options.characterBlendMode == .normal
        && options.colorOverlay == nil
        && options.perCharacter.bloom == nil
        && options.perCharacter.chromaticAberration == nil
}

internal func resolveComposition(_ composition: CompositionOptions, backgroundColor: CGColor) -> CompositionOptions {
    let resolvedBackground: Background = {
        if case .transparent = composition.background {
            return .solid(backgroundColor)
        }
        ASCIIBEffectsLogger.warnOnceMixedBackground()
        return composition.background
    }()
    return CompositionOptions(
        background: resolvedBackground,
        characterBlendMode: composition.characterBlendMode,
        colorOverlay: composition.colorOverlay,
        perCharacter: composition.perCharacter
    )
}

internal func validateComposition(_ composition: CompositionOptions) throws {
    guard BlendModeMapping.isKnown(composition.characterBlendMode) else {
        throw EffectError.unsupportedBlendMode(composition.characterBlendMode)
    }
    if let overlay = composition.colorOverlay, !BlendModeMapping.isKnown(overlay.blendMode) {
        throw EffectError.unsupportedBlendMode(overlay.blendMode)
    }
}

internal enum ASCIIBEffectsLogger {
    private static let warned = OSAllocatedUnfairLock<Bool>(initialState: false)

    static func warnOnceMixedBackground() {
        warned.withLock { flag in
            if !flag {
                os_log(
                    "ASCIIGrid.renderImage: both backgroundColor parameter and composition.background are non-default; composition.background wins",
                    log: effectsLog,
                    type: .info
                )
                flag = true
            }
        }
    }
}

internal enum EffectsRenderEngine {
    static let shared = SharedCIContext.makeDefault()

    static func makeASCIIMaskInput(
        grid: ASCIIGrid,
        font: ASCIIFont,
        scale: CGFloat,
        extent: CGRect
    ) -> MaskRenderInput? {
        if let groundColor = effectiveMaskGroundColor(grid.maskGroundColor) {
            let coverage = CoverageImageBuilder.makeASCII(
                grid: grid,
                extent: extent,
                useHardEdges: grid.maskUsesHardEdges
            )
            let fallbackImage = grid.maskFallback.flatMap { fallback in
                MaskFallbackImageFactory.makeASCII(
                    fallback,
                    grid: grid,
                    font: font,
                    scale: scale,
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
        guard let fallback = grid.maskFallback, !fallback.isTransparentFallback else { return nil }

        let coverage = CoverageImageBuilder.makeASCII(
            grid: grid,
            extent: extent,
            useHardEdges: grid.maskUsesHardEdges
        )
        let fallbackImage = MaskFallbackImageFactory.makeASCII(
            fallback,
            grid: grid,
            font: font,
            scale: scale,
            extent: extent,
            colorSpace: grid.colorSpace
        )
        guard let fallbackImage else { return nil }
        return MaskRenderInput(coverage: coverage, fallback: fallbackImage)
    }

    static func renderASCIIGridSync(
        _ grid: ASCIIGrid,
        font: ASCIIFont,
        scale: CGFloat,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        effects: EffectChain
    ) -> CGImage {
        let coverageMode: CellCoverageMode =
            effectiveMaskGroundColor(grid.maskGroundColor) == nil ? .multiplyCoverage : .intrinsicAlpha
        let raster = CellRasterBuilder.makeASCIIRaster(
            grid: grid,
            font: font,
            scale: scale,
            coverageMode: coverageMode
        )
        guard raster.pixelWidth > 0, raster.pixelHeight > 0 else {
            return ASCIIGrid.emptyImageFallback()
        }
        let extent = outputExtent(for: raster)
        let mask = makeASCIIMaskInput(
            grid: grid,
            font: font,
            scale: scale,
            extent: extent
        )
        let final = computeFinalCIImage(
            cellRaster: raster,
            colorSpace: grid.colorSpace,
            composition: composition,
            lighting: lighting,
            effects: effects,
            mask: mask
        )

        let outputColorSpace = renderColorSpaceCG(grid.colorSpace)
        let cgImage = shared.context.createCGImage(
            final,
            from: extent,
            format: .RGBA8,
            colorSpace: outputColorSpace
        )
        return cgImage ?? ASCIIGrid.emptyImageFallback()
    }

    static func renderASCIIGridAsync(
        _ grid: ASCIIGrid,
        font: ASCIIFont,
        scale: CGFloat,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        effects: EffectChain
    ) async throws -> CGImage {
        try Task.checkCancellation()
        let coverageMode: CellCoverageMode =
            effectiveMaskGroundColor(grid.maskGroundColor) == nil ? .multiplyCoverage : .intrinsicAlpha
        let raster = CellRasterBuilder.makeASCIIRaster(
            grid: grid,
            font: font,
            scale: scale,
            coverageMode: coverageMode
        )
        guard raster.pixelWidth > 0, raster.pixelHeight > 0 else {
            throw EffectError.degenerateOutput
        }
        let extent = outputExtent(for: raster)
        let mask = makeASCIIMaskInput(
            grid: grid,
            font: font,
            scale: scale,
            extent: extent
        )
        let final = try await computeFinalCIImageAsync(
            cellRaster: raster,
            colorSpace: grid.colorSpace,
            composition: composition,
            lighting: lighting,
            effects: effects,
            mask: mask
        )

        let outputColorSpace = renderColorSpaceCG(grid.colorSpace)
        guard
            let cgImage = shared.context.createCGImage(
                final,
                from: extent,
                format: .RGBA8,
                colorSpace: outputColorSpace
            )
        else {
            throw EffectError.degenerateOutput
        }
        return cgImage
    }

    static func renderASCIIGridCISync(
        _ grid: ASCIIGrid,
        font: ASCIIFont,
        scale: CGFloat,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        effects: EffectChain
    ) -> CIImage {
        let coverageMode: CellCoverageMode =
            effectiveMaskGroundColor(grid.maskGroundColor) == nil ? .multiplyCoverage : .intrinsicAlpha
        let raster = CellRasterBuilder.makeASCIIRaster(
            grid: grid,
            font: font,
            scale: scale,
            coverageMode: coverageMode
        )
        guard raster.pixelWidth > 0, raster.pixelHeight > 0 else {
            return emptyCIImage()
        }
        let extent = outputExtent(for: raster)
        let mask = makeASCIIMaskInput(
            grid: grid,
            font: font,
            scale: scale,
            extent: extent
        )
        return computeFinalCIImage(
            cellRaster: raster,
            colorSpace: grid.colorSpace,
            composition: composition,
            lighting: lighting,
            effects: effects,
            mask: mask
        )
    }

    static func renderASCIIGridCIAsync(
        _ grid: ASCIIGrid,
        font: ASCIIFont,
        scale: CGFloat,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        effects: EffectChain
    ) async throws -> CIImage {
        try Task.checkCancellation()
        let coverageMode: CellCoverageMode =
            effectiveMaskGroundColor(grid.maskGroundColor) == nil ? .multiplyCoverage : .intrinsicAlpha
        let raster = CellRasterBuilder.makeASCIIRaster(
            grid: grid,
            font: font,
            scale: scale,
            coverageMode: coverageMode
        )
        guard raster.pixelWidth > 0, raster.pixelHeight > 0 else {
            throw EffectError.degenerateOutput
        }
        let extent = outputExtent(for: raster)
        let mask = makeASCIIMaskInput(
            grid: grid,
            font: font,
            scale: scale,
            extent: extent
        )
        return try await computeFinalCIImageAsync(
            cellRaster: raster,
            colorSpace: grid.colorSpace,
            composition: composition,
            lighting: lighting,
            effects: effects,
            mask: mask
        )
    }

    static func computeFinalCIImage(
        cellRaster: CellRaster,
        colorSpace: RenderColorSpace,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        effects: EffectChain,
        mask renderMask: MaskRenderInput? = nil
    ) -> CIImage {
        let graph = makeEffectGraph(
            cellRaster: cellRaster,
            colorSpace: colorSpace,
            composition: composition,
            lighting: lighting,
            mask: renderMask,
            checkpoint: {},
            applyColorOverlay: { image, overlay, context in
                StockCIEffectKernel(
                    kind: .colorOverlay(
                        color: overlay.color,
                        blendMode: overlay.blendMode,
                        opacity: overlay.opacity
                    )
                ).apply(image, extent: context.outputExtent, in: context)
            }
        )

        // The sync tail deliberately absorbs individual kernel failures.
        return runEffectChainSync(graph.image, effects: effects, in: graph.context)
    }

    static func computeFinalCIImageAsync(
        cellRaster: CellRaster,
        colorSpace: RenderColorSpace,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        effects: EffectChain,
        mask renderMask: MaskRenderInput? = nil
    ) async throws -> CIImage {
        let graph = try makeEffectGraph(
            cellRaster: cellRaster,
            colorSpace: colorSpace,
            composition: composition,
            lighting: lighting,
            mask: renderMask,
            checkpoint: { try Task.checkCancellation() },
            applyColorOverlay: { image, overlay, context in
                try StockCIEffectKernel(
                    kind: .colorOverlay(
                        color: overlay.color,
                        blendMode: overlay.blendMode,
                        opacity: overlay.opacity
                    )
                ).apply(to: image, in: context)
            }
        )

        // The async tail deliberately propagates kernel failures and cancellation.
        return try await runEffectChainAsync(graph.image, effects: effects, in: graph.context)
    }

    private static func makeEffectGraph(
        cellRaster: CellRaster,
        colorSpace: RenderColorSpace,
        composition: CompositionOptions,
        lighting: LightingOptions?,
        mask renderMask: MaskRenderInput?,
        checkpoint: () throws -> Void,
        applyColorOverlay: (CIImage, ColorOverlay, EffectContext) throws -> CIImage
    ) rethrows -> (image: CIImage, context: EffectContext) {
        let extent = outputExtent(for: cellRaster)
        let context = makeEffectContext(
            extent: extent,
            colorSpace: colorSpace
        )

        let perCharacterMask: CIImage?
        if composition.perCharacter.bloom != nil
            || composition.perCharacter.chromaticAberration != nil
        {
            perCharacterMask = CellMaskExtractor.mask(from: cellRaster.image)
        } else {
            perCharacterMask = nil
        }

        try checkpoint()
        let perCharacterApplied =
            if let perCharacterMask {
                PerCharacterEffectApplicator.apply(
                    composition.perCharacter,
                    cellRaster: cellRaster.image,
                    mask: perCharacterMask,
                    in: context
                )
            } else {
                cellRaster.image
            }

        try checkpoint()
        let overlaid: CIImage
        if let overlay = composition.colorOverlay {
            overlaid = try applyColorOverlay(perCharacterApplied, overlay, context)
        } else {
            overlaid = perCharacterApplied
        }

        try checkpoint()
        let resolver = BackgroundResolver()
        let canvas =
            resolver.resolve(composition.background, outputExtent: extent)
            ?? CIImage(color: .clear).cropped(to: extent)
        try checkpoint()
        let composited: CIImage
        if let renderMask, let ground = renderMask.activeGround {
            let activeBackground = MaskCompositor.sourceOver(
                ground,
                background: canvas,
                extent: extent
            )
            let active: CIImage
            if let blendKernel = BlendModeMapping.kernel(for: composition.characterBlendMode) {
                active =
                    blendKernel.apply(
                        foreground: overlaid,
                        background: activeBackground,
                        colorSpace: WorkingColorSpace.extendedLinearSRGB
                    )?.cropped(to: extent) ?? overlaid
            } else {
                active = overlaid
            }
            let inactive =
                if let fallback = renderMask.fallback {
                    MaskCompositor.sourceOver(
                        fallback,
                        background: canvas,
                        extent: extent
                    )
                } else {
                    canvas
                }
            composited = MaskCompositor.blendWithMask(
                source: active,
                background: inactive,
                mask: renderMask.coverage,
                extent: extent
            )
        } else {
            var backgroundImage = canvas
            if let renderMask, let fallback = renderMask.fallback {
                backgroundImage = MaskCompositor.blendWithMask(
                    source: backgroundImage,
                    background: fallback,
                    mask: renderMask.coverage,
                    extent: extent
                )
            }
            if let blendKernel = BlendModeMapping.kernel(for: composition.characterBlendMode) {
                composited =
                    blendKernel.apply(
                        foreground: overlaid,
                        background: backgroundImage,
                        colorSpace: WorkingColorSpace.extendedLinearSRGB
                    )?.cropped(to: extent) ?? overlaid
            } else {
                composited = overlaid
            }
        }

        try checkpoint()
        let lit: CIImage
        if let lighting {
            lit = LightingApplicator().apply(lighting, to: composited, in: context)
        } else {
            lit = composited
        }
        return (lit, context)
    }

    static func emptyCIImage() -> CIImage {
        CIImage(color: .clear).cropped(to: .zero)
    }

    static func outputExtent(for raster: CellRaster) -> CGRect {
        CGRect(x: 0, y: 0, width: raster.pixelWidth, height: raster.pixelHeight)
    }

    private static func makeEffectContext(
        extent: CGRect,
        colorSpace: RenderColorSpace
    ) -> EffectContext {
        EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: colorSpace,
            deviceCapability: MetalSupport.supportsStitchableKernels()
                ? .full
                : .reducedQuality(.metallibUnsupported)
        )
    }

    static func runEffectChainSync(
        _ image: CIImage,
        effects: EffectChain,
        in context: EffectContext
    ) -> CIImage {
        var current = image
        for effect in effects.effects {
            if let stock = stockKernel(for: effect, capability: context.deviceCapability) {
                current = stock.apply(current, extent: context.outputExtent, in: context)
            } else if let metallib = metallibKernel(for: effect) {
                do {
                    current = try metallib.apply(to: current, in: context)
                } catch {
                    os_log(
                        "metallib effect failed (sync absorbed): %{public}@",
                        log: effectsLog,
                        type: .error,
                        String(describing: error)
                    )
                }
            }
        }
        return current
    }

    static func runEffectChainAsync(
        _ image: CIImage,
        effects: EffectChain,
        in context: EffectContext
    ) async throws -> CIImage {
        var current = image
        for effect in effects.effects {
            try Task.checkCancellation()
            if let stock = stockKernel(for: effect, capability: context.deviceCapability) {
                current = try stock.apply(to: current, in: context)
            } else if let metallib = metallibKernel(for: effect) {
                current = try metallib.apply(to: current, in: context)
            }
        }
        return current
    }

    static func stockKernel(for effect: Effect, capability: DeviceCapability) -> StockCIEffectKernel? {
        switch effect {
        case .vignette(let intensity):
            return StockCIEffectKernel(kind: .vignette(intensity: intensity))
        case .bloom(let intensity, let radius):
            return StockCIEffectKernel(kind: .bloom(intensity: intensity, radius: radius))
        case .chromaticAberration(let intensity):
            return StockCIEffectKernel(kind: .chromaticAberration(intensity: intensity))
        case .blur(let radius):
            return StockCIEffectKernel(kind: .blur(radius: radius))
        case .pixelate(let scale):
            return StockCIEffectKernel(kind: .pixelate(scale: scale))
        case .scanLines, .crtCurvature, .halftone, .filmDust, .glitch, .rgbSplit, .filmGrain:
            return nil
        }
    }

    static func metallibKernel(for effect: Effect) -> MetallibEffectKernel? {
        switch effect {
        case .scanLines(let intensity, let frequency):
            return MetallibEffectKernel(
                kind: .scanLines(intensity: intensity, frequency: frequency),
                fallback: StockCIEffectKernel(kind: .scanLinesApprox(intensity: intensity, frequency: frequency))
            )
        case .crtCurvature(let intensity):
            return MetallibEffectKernel(
                kind: .crtCurvature(intensity: intensity),
                fallback: StockCIEffectKernel(kind: .crtCurvatureApprox)
            )
        case .halftone(let scale):
            return MetallibEffectKernel(
                kind: .halftone(scale: scale),
                fallback: StockCIEffectKernel(kind: .halftoneApprox(scale: scale))
            )
        case .filmDust(let intensity, let seed):
            return MetallibEffectKernel(
                kind: .filmDust(intensity: intensity, seed: seed),
                fallback: StockCIEffectKernel(kind: .filmDustApprox(intensity: intensity, seed: seed))
            )
        case .glitch(let intensity, let seed):
            return MetallibEffectKernel(
                kind: .glitch(intensity: intensity, seed: seed),
                fallback: StockCIEffectKernel(kind: .glitchApprox(intensity: intensity, seed: seed))
            )
        case .rgbSplit(let intensity):
            return MetallibEffectKernel(
                kind: .rgbSplit(intensity: intensity),
                fallback: StockCIEffectKernel(kind: .rgbSplitApprox(intensity: intensity))
            )
        case .filmGrain(let intensity, let seed):
            return MetallibEffectKernel(
                kind: .filmGrain(intensity: intensity, seed: seed),
                fallback: StockCIEffectKernel(kind: .filmGrainApprox(intensity: intensity, seed: seed))
            )
        case .vignette, .bloom, .chromaticAberration, .blur, .pixelate:
            return nil
        }
    }

    static func renderColorSpaceCG(_ space: RenderColorSpace) -> CGColorSpace {
        switch space {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        }
    }
}

extension ASCIIGrid {
    static func emptyImageFallback() -> CGImage {
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

extension StockCIEffectKernel {
    func apply(_ image: CIImage, extent: CGRect, in context: EffectContext) -> CIImage {
        do {
            return try apply(to: image, in: context)
        } catch {
            return image
        }
    }
}

internal enum PerCharacterEffectApplicator {
    static func apply(
        _ options: PerCharacterEffects,
        cellRaster: CIImage,
        mask: CIImage,
        in context: EffectContext
    ) -> CIImage {
        var current = cellRaster
        if let bloom = options.bloom {
            let global = StockCIEffectKernel(kind: .bloom(intensity: bloom.intensity, radius: bloom.radius))
                .apply(current, extent: context.outputExtent, in: context)
            current = blendWithMask(
                foreground: global,
                background: current,
                mask: mask,
                extent: context.outputExtent
            )
        }
        if let aberration = options.chromaticAberration {
            let global = StockCIEffectKernel(kind: .chromaticAberration(intensity: aberration.intensity))
                .apply(current, extent: context.outputExtent, in: context)
            current = blendWithMask(
                foreground: global,
                background: current,
                mask: mask,
                extent: context.outputExtent
            )
        }
        return current
    }

    private static func blendWithMask(
        foreground: CIImage,
        background: CIImage,
        mask: CIImage,
        extent: CGRect
    ) -> CIImage {
        let filter = CIFilter(name: "CIBlendWithMask")!
        filter.setValue(foreground, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        filter.setValue(mask, forKey: kCIInputMaskImageKey)
        return (filter.outputImage ?? foreground).cropped(to: extent)
    }
}
