import CoreGraphics
import Foundation

internal enum TriangleOrientation: Sendable, Hashable {
    case up
    case down
}

internal func cellOrigin(column: Int, row: Int, shape: TileCellShape, scale: CGFloat) -> CGPoint {
    switch shape {
    case .square, .circle:
        return CGPoint(x: CGFloat(column) * scale, y: CGFloat(row) * scale)
    case .hex:
        let xOffset = row.isMultiple(of: 2) ? scale * 0.5 : 0
        return CGPoint(
            x: CGFloat(column) * scale + xOffset,
            y: CGFloat(row) * scale * 0.866
        )
    case .triangle:
        return CGPoint(
            x: CGFloat(column) * scale * 0.5,
            y: CGFloat(row) * scale * 0.866
        )
    case .diamond:
        let xOffset = row.isMultiple(of: 2) ? scale * 0.5 : 0
        return CGPoint(
            x: CGFloat(column) * scale + xOffset,
            y: CGFloat(row) * scale * 0.5
        )
    }
}

internal func cellSize(shape: TileCellShape, scale: CGFloat) -> CGSize {
    switch shape {
    case .square, .circle, .diamond:
        return CGSize(width: scale, height: scale)
    case .hex:
        return CGSize(width: scale, height: scale * 2 / sqrt(3))
    case .triangle:
        return CGSize(width: scale, height: scale * sqrt(3) / 2)
    }
}

internal func cellBounds(column: Int, row: Int, shape: TileCellShape, scale: CGFloat) -> CGRect {
    CGRect(
        origin: cellOrigin(column: column, row: row, shape: shape, scale: scale),
        size: cellSize(shape: shape, scale: scale)
    )
}

internal func cellPath(shape: TileCellShape, in rect: CGRect, column: Int) -> CGPath {
    switch shape {
    case .square:
        return CGPath(rect: rect, transform: nil)
    case .circle:
        return CGPath(ellipseIn: rect, transform: nil)
    case .hex:
        return hexPath(in: rect)
    case .triangle:
        let orientation: TriangleOrientation = column.isMultiple(of: 2) ? .up : .down
        return trianglePath(in: rect, orientation: orientation)
    case .diamond:
        return diamondPath(in: rect)
    }
}

internal func cellVertices(shape: TileCellShape, in rect: CGRect, column: Int) -> [CGPoint] {
    switch shape {
    case .square:
        return [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
    case .circle:
        return []
    case .hex:
        return hexVertices(in: rect)
    case .triangle:
        let orientation: TriangleOrientation = column.isMultiple(of: 2) ? .up : .down
        return triangleVertices(in: rect, orientation: orientation)
    case .diamond:
        return diamondVertices(in: rect)
    }
}

internal func cellCentroid(shape: TileCellShape, in rect: CGRect, column: Int) -> CGPoint {
    switch shape {
    case .square, .circle, .diamond, .hex:
        return CGPoint(x: rect.midX, y: rect.midY)
    case .triangle:
        let orientation: TriangleOrientation = column.isMultiple(of: 2) ? .up : .down
        switch orientation {
        case .up:
            return CGPoint(x: rect.midX, y: rect.maxY - rect.height / 3)
        case .down:
            return CGPoint(x: rect.midX, y: rect.minY + rect.height / 3)
        }
    }
}

// MARK: - Polygon vertex builders

private func hexVertices(in rect: CGRect) -> [CGPoint] {
    let centerX = rect.midX
    let centerY = rect.midY
    let width = rect.width
    let height = rect.height
    return [
        CGPoint(x: centerX, y: rect.minY),
        CGPoint(x: centerX + width / 2, y: centerY - height / 4),
        CGPoint(x: centerX + width / 2, y: centerY + height / 4),
        CGPoint(x: centerX, y: rect.maxY),
        CGPoint(x: centerX - width / 2, y: centerY + height / 4),
        CGPoint(x: centerX - width / 2, y: centerY - height / 4),
    ]
}

private func triangleVertices(in rect: CGRect, orientation: TriangleOrientation) -> [CGPoint] {
    switch orientation {
    case .up:
        return [
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
    case .down:
        return [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.maxY),
        ]
    }
}

private func diamondVertices(in rect: CGRect) -> [CGPoint] {
    [
        CGPoint(x: rect.midX, y: rect.minY),
        CGPoint(x: rect.maxX, y: rect.midY),
        CGPoint(x: rect.midX, y: rect.maxY),
        CGPoint(x: rect.minX, y: rect.midY),
    ]
}

// MARK: - Sharp-corner path builders

private func hexPath(in rect: CGRect) -> CGPath {
    polygonPath(vertices: hexVertices(in: rect))
}

private func trianglePath(in rect: CGRect, orientation: TriangleOrientation) -> CGPath {
    polygonPath(vertices: triangleVertices(in: rect, orientation: orientation))
}

private func diamondPath(in rect: CGRect) -> CGPath {
    polygonPath(vertices: diamondVertices(in: rect))
}

private func polygonPath(vertices: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = vertices.first else { return path }
    path.move(to: first)
    for vertex in vertices.dropFirst() {
        path.addLine(to: vertex)
    }
    path.closeSubpath()
    return path
}

// MARK: - Mosaic helpers

internal func insetVertices(
    _ vertices: [CGPoint],
    toward centroid: CGPoint,
    thickness: CGFloat
) -> [CGPoint] {
    let factor = max(0, 1 - 2 * thickness)
    return vertices.map { vertex in
        CGPoint(
            x: centroid.x + (vertex.x - centroid.x) * factor,
            y: centroid.y + (vertex.y - centroid.y) * factor
        )
    }
}

internal func roundedPolygonPath(vertices: [CGPoint], radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let count = vertices.count
    guard count >= 3 else { return path }
    guard radius > 0 else { return polygonPath(vertices: vertices) }

    let firstPrevious = vertices[count - 1]
    let firstCurrent = vertices[0]
    let firstStart = CGPoint(
        x: (firstPrevious.x + firstCurrent.x) / 2,
        y: (firstPrevious.y + firstCurrent.y) / 2
    )
    path.move(to: firstStart)

    for index in 0..<count {
        let previous = vertices[(index + count - 1) % count]
        let current = vertices[index]
        let next = vertices[(index + 1) % count]

        let toCurrentLength = hypot(current.x - previous.x, current.y - previous.y)
        let toNextLength = hypot(next.x - current.x, next.y - current.y)
        let clampedRadius = min(radius, toCurrentLength / 2, toNextLength / 2)

        path.addArc(tangent1End: current, tangent2End: next, radius: clampedRadius)
    }
    path.closeSubpath()
    return path
}

internal func mosaicCellPath(
    shape: TileCellShape,
    in rect: CGRect,
    column: Int,
    thickness: CGFloat,
    cornerRadius: CGFloat
) -> CGPath {
    let cellWidth = rect.width
    let radius = cornerRadius * cellWidth
    switch shape {
    case .circle:
        let inset = thickness * cellWidth
        let shrunk = rect.insetBy(dx: inset, dy: inset)
        return CGPath(ellipseIn: shrunk, transform: nil)
    case .square:
        let inset = thickness * cellWidth
        let shrunk = rect.insetBy(dx: inset, dy: inset)
        return CGPath(
            roundedRect: shrunk,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    case .hex, .triangle, .diamond:
        let centroid = cellCentroid(shape: shape, in: rect, column: column)
        let rawVertices = cellVertices(shape: shape, in: rect, column: column)
        let insetVertices = insetVertices(rawVertices, toward: centroid, thickness: thickness)
        return roundedPolygonPath(vertices: insetVertices, radius: radius)
    }
}

internal struct MosaicPathCache {
    internal struct Key: Hashable {
        let shape: TileCellShape
        let triangleOrientation: TriangleOrientation?
        let thickness: Double
        let cornerRadius: Double
    }

    private var cache: [Key: CGPath] = [:]

    mutating func unitPath(for key: Key) -> CGPath {
        if let cached = cache[key] { return cached }
        let unitSize = cellSize(shape: key.shape, scale: 1)
        let unitRect = CGRect(origin: .zero, size: unitSize)
        let column = key.triangleOrientation == .down ? 1 : 0
        let path = mosaicCellPath(
            shape: key.shape,
            in: unitRect,
            column: column,
            thickness: CGFloat(key.thickness),
            cornerRadius: CGFloat(key.cornerRadius)
        )
        cache[key] = path
        return path
    }

    static func key(
        shape: TileCellShape,
        column: Int,
        thickness: Double,
        cornerRadius: Double
    ) -> Key {
        let orientation: TriangleOrientation? =
            shape == .triangle
            ? (column.isMultiple(of: 2) ? .up : .down)
            : nil
        return Key(
            shape: shape,
            triangleOrientation: orientation,
            thickness: thickness,
            cornerRadius: cornerRadius
        )
    }
}
