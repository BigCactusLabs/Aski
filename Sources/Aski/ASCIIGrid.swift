import CoreGraphics

/// A 2D grid of matched ASCII cells, the output of `ASCIIConverter.convert(_:columns:)`.
/// Renderers (plain text, attributed string, image) are methods on this type.
public struct ASCIIGrid: Sendable {
    public let cells: [[ASCIICell]]
    public let columns: Int
    public let rows: Int
    public let colorSpace: RenderColorSpace
    public let composition: RenderCompositionPolicy
    public let maskFallback: MaskFallback?
    public let maskGroundColor: CGColor?
    public let maskUsesHardEdges: Bool

    public init(
        cells: [[ASCIICell]],
        colorSpace: RenderColorSpace,
        composition: RenderCompositionPolicy = .encodedDisplay8Bit,
        maskFallback: MaskFallback? = nil,
        maskGroundColor: CGColor? = nil,
        maskUsesHardEdges: Bool = false
    ) {
        self.cells = cells
        self.rows = cells.count
        self.columns = cells.first?.count ?? 0
        self.colorSpace = colorSpace
        self.composition = composition
        self.maskFallback = maskFallback
        self.maskGroundColor = maskGroundColor
        self.maskUsesHardEdges = maskUsesHardEdges
    }
}
