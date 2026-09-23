import Foundation
#if canImport(UIKit)
    import UIKit
    typealias PlatformColor = UIColor
#elseif canImport(AppKit)
    import AppKit
    typealias PlatformColor = NSColor
#endif

public extension ASCIIGrid {
    /// Renders this grid as an `AttributedString` with foreground colors batched
    /// into runs of identical color for efficiency.
    func renderAttributedString() -> AttributedString {
        var result = AttributedString()
        let fallback = Self.attributedMaskFallback(from: maskFallback, in: colorSpace)

        for (rowIndex, row) in cells.enumerated() {
            let rendered = row.map { Self.renderedAttributedCell($0, fallback: fallback) }
            var runStart = 0
            while runStart < rendered.count {
                let runColor = rendered[runStart].color.rgb
                let runAlpha = rendered[runStart].color.alpha
                var runEnd = runStart + 1
                while runEnd < rendered.count,
                    rendered[runEnd].color.rgb == runColor,
                    rendered[runEnd].color.alpha == runAlpha
                {
                    runEnd += 1
                }

                let runText = String(rendered[runStart..<runEnd].map(\.character))
                var run = AttributedString(runText)
                #if canImport(UIKit)
                    run.uiKit.foregroundColor = Self.platformColor(
                        for: runColor,
                        alpha: CGFloat(runAlpha),
                        in: colorSpace
                    )
                #elseif canImport(AppKit)
                    run.appKit.foregroundColor = Self.platformColor(
                        for: runColor,
                        alpha: CGFloat(runAlpha),
                        in: colorSpace
                    )
                #endif
                result += run
                runStart = runEnd
            }

            if rowIndex < cells.count - 1 {
                result += AttributedString("\n")
            }
        }

        return result
    }

    private static func attributedMaskFallback(
        from fallback: MaskFallback?,
        in colorSpace: RenderColorSpace
    ) -> AttributedMaskFallback {
        guard case .character(let character, let color) = fallback else {
            return AttributedMaskFallback(character: nil, color: nil)
        }
        let resolvedColor = color.map { Self.resolvedColor(for: $0, in: colorSpace) }
        return AttributedMaskFallback(character: character, color: resolvedColor)
    }

    private static func renderedAttributedCell(
        _ cell: ASCIICell,
        fallback: AttributedMaskFallback
    ) -> RenderedAttributedCell {
        if cell.coverage >= 0.5 {
            return RenderedAttributedCell(
                character: cell.character,
                color: ResolvedTextColor(rgb: cell.displayColor, alpha: Self.effectiveCellAlpha(cell))
            )
        }

        let inverseCoverage = max(0, min(1, 1 - cell.coverage))
        return RenderedAttributedCell(
            character: fallback.character ?? " ",
            color: fallback.color?.withAlphaMultiplier(inverseCoverage)
                ?? ResolvedTextColor(rgb: cell.displayColor, alpha: inverseCoverage)
        )
    }

    private static func effectiveCellAlpha(_ cell: ASCIICell) -> Float {
        max(0, min(1, cell.alpha * cell.coverage))
    }

    private static func resolvedColor(for color: CGColor, in colorSpace: RenderColorSpace) -> ResolvedTextColor {
        let target = cgColorSpace(for: colorSpace)
        guard let converted = color.converted(to: target, intent: .perceptual, options: nil),
            let components = converted.components,
            components.count >= 3
        else {
            MaskLogger.warnOnceFallbackColorConversionFailed()
            return ResolvedTextColor(rgb: SIMD3<Float>(1, 1, 1), alpha: 1)
        }

        return ResolvedTextColor(
            rgb: SIMD3<Float>(
                Float(max(0, min(1, components[0]))),
                Float(max(0, min(1, components[1]))),
                Float(max(0, min(1, components[2])))
            ),
            alpha: Float(max(0, min(1, converted.alpha)))
        )
    }

    private static func cgColorSpace(for colorSpace: RenderColorSpace) -> CGColorSpace {
        switch colorSpace {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        }
    }

    private static func platformColor(
        for rgb: SIMD3<Float>,
        alpha: CGFloat = 1,
        in colorSpace: RenderColorSpace
    ) -> PlatformColor {
        #if canImport(UIKit)
            switch colorSpace {
            case .sRGB:
                return UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: alpha)
            case .displayP3:
                return UIColor(displayP3Red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: alpha)
            }
        #elseif canImport(AppKit)
            switch colorSpace {
            case .sRGB:
                return NSColor(srgbRed: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: alpha)
            case .displayP3:
                return NSColor(displayP3Red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: alpha)
            }
        #endif
    }
}

private struct AttributedMaskFallback {
    let character: Character?
    let color: ResolvedTextColor?
}

private struct RenderedAttributedCell {
    let character: Character
    let color: ResolvedTextColor
}

private struct ResolvedTextColor: Equatable {
    let rgb: SIMD3<Float>
    let alpha: Float

    func withAlphaMultiplier(_ multiplier: Float) -> ResolvedTextColor {
        ResolvedTextColor(rgb: rgb, alpha: max(0, min(1, alpha * multiplier)))
    }
}
