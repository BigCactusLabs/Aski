import CoreGraphics
import CoreImage

internal struct MaskRenderInput: Sendable {
    let coverage: CIImage
    let fallback: CIImage?
    let activeGround: CIImage?
    let presence: CIImage?

    var usesGroupedComposition: Bool { activeGround != nil }

    init(coverage: CIImage, fallback: CIImage?, activeGround: CIImage? = nil, presence: CIImage? = nil) {
        self.coverage = coverage
        self.fallback = fallback
        self.activeGround = activeGround
        self.presence = presence
    }
}

internal func effectiveMaskGroundColor(_ color: CGColor?) -> CGColor? {
    guard let color, color.alpha.isFinite, color.alpha > 0 else { return nil }
    return color
}

internal func maskContainsCoverageBelowOne(_ grid: ASCIIGrid) -> Bool {
    grid.cells.contains { row in
        row.contains { cell in cell.coverage < 1 }
    }
}

internal func maskContainsCoverageBelowOne(_ grid: TileGrid) -> Bool {
    grid.cells.contains { row in
        row.contains { cell in cell.coverage < 1 }
    }
}

internal func maskHasNonTransparentFallback(_ fallback: MaskFallback?) -> Bool {
    guard let fallback else { return false }
    return !fallback.isTransparentFallback
}
