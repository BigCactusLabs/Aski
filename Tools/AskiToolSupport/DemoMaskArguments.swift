import ArgumentParser
import Aski
import CoreGraphics

public enum MaskFallbackArgument: String, CaseIterable, ExpressibleByArgument, Sendable {
    case transparent
    case solid
    case original
}

public enum MaskFallbackSizingArgument: String, CaseIterable, ExpressibleByArgument, Sendable {
    case fill
    case fit
    case stretch

    public var backgroundSizing: BackgroundSizing {
        switch self {
        case .fill: .fill
        case .fit: .fit
        case .stretch: .stretch
        }
    }
}

struct ResolvedDemoMask: Sendable {
    let path: String
    let fallback: MaskFallbackArgument
    let fallbackColor: BackgroundColor?
    let fallbackSizing: MaskFallbackSizingArgument?
    let ground: BackgroundColor?
    let hardEdges: Bool
    let invert: Bool
}

/// Parser arguments and conversion-time resolution for `aski render` masks.
/// Parser optionals intentionally preserve whether a user supplied a value.
public struct DemoMaskArguments: ParsableArguments, Sendable {
    @Option(
        name: .customLong("mask"),
        help: "Raster mask path: white keeps cells, black hides cells, and intermediate values feather coverage."
    )
    public var maskPath: String?

    @Option(
        name: .customLong("mask-fallback"),
        help: "Masked-out raster fallback: transparent, solid, or original. Defaults to transparent with --mask."
    )
    public var fallback: MaskFallbackArgument?

    @Option(
        name: .customLong("mask-fallback-color"),
        help: "Color for --mask-fallback solid. clear and transparent are not allowed."
    )
    public var fallbackColor: BackgroundColor?

    @Option(
        name: .customLong("mask-fallback-sizing"),
        help: "Sizing for --mask-fallback original: fill, fit, or stretch. Defaults to stretch."
    )
    public var fallbackSizing: MaskFallbackSizingArgument?

    @Option(
        name: .customLong("mask-ground"),
        help: "Raster ground behind active cells. Requires --render-png; clear and transparent are not allowed."
    )
    public var ground: BackgroundColor?

    @Flag(name: .customLong("mask-hard-edges"), help: "Threshold mask coverage at 0.5 instead of preserving soft edges.")
    public var hardEdges = false

    @Flag(name: .customLong("mask-invert"), help: "Invert mask coverage after optional hard-edge thresholding.")
    public var invert = false

    public init() {}

    public func validate(renderPNGPath: String?) throws {
        guard maskPath != nil else {
            guard fallback == nil, fallbackColor == nil, fallbackSizing == nil, ground == nil, !hardEdges, !invert else {
                throw ValidationError("--mask is required when using mask-specific options")
            }
            return
        }

        let resolvedFallback = fallback ?? .transparent
        if fallbackColor != nil, resolvedFallback != .solid {
            throw ValidationError("--mask-fallback-color requires --mask-fallback solid")
        }
        if resolvedFallback == .solid {
            guard let fallbackColor else {
                throw ValidationError("--mask-fallback solid requires --mask-fallback-color")
            }
            guard fallbackColor.alpha.isFinite, fallbackColor.alpha > 0 else {
                throw ValidationError(
                    "--mask-fallback-color must not be clear or transparent; use --mask-fallback transparent instead"
                )
            }
        }

        if fallbackSizing != nil, resolvedFallback != .original {
            throw ValidationError("--mask-fallback-sizing requires --mask-fallback original")
        }

        if resolvedFallback == .solid || resolvedFallback == .original {
            guard renderPNGPath != nil else {
                throw ValidationError("--mask-fallback \(resolvedFallback.rawValue) requires --render-png")
            }
        }

        if let ground {
            guard renderPNGPath != nil else {
                throw ValidationError("--mask-ground requires --render-png")
            }
            guard ground.alpha.isFinite, ground.alpha > 0 else {
                throw ValidationError("--mask-ground must not be clear or transparent; omit --mask-ground instead")
            }
        }
    }

    func loadMaskImage(sourceImage: CGImage) throws -> CGImage? {
        guard let maskPath else { return nil }
        return try DemoImageIO.loadThumbnail(
            at: maskPath,
            maxPixelSize: max(sourceImage.width, sourceImage.height)
        )
    }

    public func makeMaskOptions(maskImage: CGImage, sourceImage: CGImage) -> MaskOptions? {
        guard let resolvedMask else { return nil }

        let resolvedFallback: MaskFallback
        switch resolvedMask.fallback {
        case .transparent:
            resolvedFallback = .transparent
        case .solid:
            guard let color = resolvedMask.fallbackColor else { return nil }
            resolvedFallback = .solid(color.cgColor)
        case .original:
            guard let sizing = resolvedMask.fallbackSizing else { return nil }
            resolvedFallback = .originalImage(sourceImage, sizing: sizing.backgroundSizing)
        }

        return MaskOptions(
            image: maskImage,
            fallback: resolvedFallback,
            groundColor: resolvedMask.ground?.cgColor,
            softEdges: !resolvedMask.hardEdges,
            invert: resolvedMask.invert
        )
    }

    var resolvedMask: ResolvedDemoMask? {
        guard let maskPath else { return nil }
        let fallback = fallback ?? .transparent
        return ResolvedDemoMask(
            path: maskPath,
            fallback: fallback,
            fallbackColor: fallback == .solid ? fallbackColor : nil,
            fallbackSizing: fallback == .original ? fallbackSizing ?? .stretch : nil,
            ground: ground,
            hardEdges: hardEdges,
            invert: invert
        )
    }
}
