import CoreGraphics
import Foundation

public extension AnimatedASCIIGrid {
    func renderImage(
        at time: TimeInterval,
        font: ASCIIFont,
        backgroundColor: CGColor,
        scale: CGFloat,
        composition: CompositionOptions = .init(),
        lighting: LightingOptions? = nil,
        effects: EffectChain = .init()
    ) -> CGImage {
        grid(at: time).renderImage(
            font: font,
            backgroundColor: backgroundColor,
            scale: scale,
            composition: composition,
            lighting: lighting,
            effects: effects
        )
    }
}
