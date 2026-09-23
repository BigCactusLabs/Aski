import CoreGraphics

/// A 2D grid of colored tile cells, the output of `TileGridConverter.convert(_:columns:)`.
/// Carries no rendering state; mode and cell-shape are render-time parameters
/// on `renderImage` so a single grid can be re-rendered with different visual
/// styles without re-running the expensive converter pipeline.
public struct TileGrid: Sendable {
    public let cells: [[TileCell]]
    public let columns: Int
    public let rows: Int
    public let colorSpace: RenderColorSpace
    public let maskFallback: MaskFallback?
    public let maskGroundColor: CGColor?
    public let maskUsesHardEdges: Bool

    public init(
        cells: [[TileCell]],
        colorSpace: RenderColorSpace,
        maskFallback: MaskFallback? = nil,
        maskGroundColor: CGColor? = nil,
        maskUsesHardEdges: Bool = false
    ) {
        self.cells = cells
        self.rows = cells.count
        // Use the widest row, not just the first. The renderer tolerates
        // per-row variation; first-row reporting would misrepresent ragged input.
        self.columns = cells.map(\.count).max() ?? 0
        self.colorSpace = colorSpace
        self.maskFallback = maskFallback
        self.maskGroundColor = maskGroundColor
        self.maskUsesHardEdges = maskUsesHardEdges
    }

    /// 1x1 transparent fallback used when inputs are degenerate.
    internal static func emptyImage() -> CGImage {
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

    /// CGColorSpace appropriate for the grid's `RenderColorSpace`.
    internal var cgColorSpace: CGColorSpace {
        switch colorSpace {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        }
    }
}
