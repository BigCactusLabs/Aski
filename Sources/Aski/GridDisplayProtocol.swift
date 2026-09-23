import simd

internal protocol DisplayCell: Sendable {
    var displayColor: SIMD3<Float> { get }
    var alpha: Float { get }
    var brightness: Float { get }
    var coverage: Float { get }
}

extension ASCIICell: DisplayCell {}
extension TileCell: DisplayCell {}

internal protocol DisplayGrid: Sendable {
    associatedtype Cell: DisplayCell

    var cells: [[Cell]] { get }
    var columns: Int { get }
    var rows: Int { get }
    var colorSpace: RenderColorSpace { get }
}

extension ASCIIGrid: DisplayGrid {}
extension TileGrid: DisplayGrid {}

internal struct GridDisplayMetrics: Equatable, Sendable {
    let rows: Int
    let columns: Int
    let nonEmptyCellCount: Int
    let averageAlpha: Float
    let averageBrightness: Float
}

internal func displayColor<C: DisplayCell>(of cell: C) -> SIMD3<Float> {
    cell.displayColor
}

internal func displayAlpha<C: DisplayCell>(of cell: C) -> Float {
    cell.alpha
}

internal func displayBrightness<C: DisplayCell>(of cell: C) -> Float {
    cell.brightness
}

internal func displayCoverage<C: DisplayCell>(of cell: C) -> Float {
    cell.coverage
}

internal func gridDisplayMetrics<G: DisplayGrid>(_ grid: G) -> GridDisplayMetrics {
    var alphaSum: Float = 0
    var brightnessSum: Float = 0
    var count = 0

    for row in grid.cells {
        for cell in row {
            alphaSum += cell.alpha
            brightnessSum += cell.brightness
            count += 1
        }
    }

    return GridDisplayMetrics(
        rows: grid.rows,
        columns: grid.columns,
        nonEmptyCellCount: count,
        averageAlpha: count == 0 ? 0 : alphaSum / Float(count),
        averageBrightness: count == 0 ? 0 : brightnessSum / Float(count)
    )
}
