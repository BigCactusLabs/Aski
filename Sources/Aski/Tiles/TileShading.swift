import CoreGraphics
import Foundation

internal enum TileShading {

    static func drawStud(
        center: CGPoint,
        diameter: CGFloat,
        baseColor: CGColor,
        in context: CGContext,
        colorSpace: CGColorSpace
    ) {
        let radius = diameter / 2
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: diameter,
            height: diameter
        )

        context.saveGState()
        context.setFillColor(baseColor)
        context.fillEllipse(in: rect)
        context.restoreGState()

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0.5, height: 0.5),
            blur: 0.5,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25)
        )
        context.setFillColor(baseColor)
        context.fillEllipse(in: rect)
        context.restoreGState()

        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        let colors =
            [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.08),
                CGColor(red: 0, green: 0, blue: 0, alpha: 0.05),
            ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(
                    x: rect.minX + diameter * 0.25,
                    y: rect.minY + diameter * 0.25
                ),
                startRadius: 0,
                endCenter: CGPoint(x: rect.maxX, y: rect.maxY),
                endRadius: diameter,
                options: []
            )
        }
        context.restoreGState()
    }

    static func drawBevel(
        path: CGPath,
        bounds: CGRect,
        in context: CGContext
    ) {
        let bbox = path.boundingBoxOfPath

        let upperLeftTriangle = CGMutablePath()
        upperLeftTriangle.move(to: CGPoint(x: bbox.minX, y: bbox.minY))
        upperLeftTriangle.addLine(to: CGPoint(x: bbox.maxX, y: bbox.minY))
        upperLeftTriangle.addLine(to: CGPoint(x: bbox.minX, y: bbox.maxY))
        upperLeftTriangle.closeSubpath()

        let lowerRightTriangle = CGMutablePath()
        lowerRightTriangle.move(to: CGPoint(x: bbox.maxX, y: bbox.minY))
        lowerRightTriangle.addLine(to: CGPoint(x: bbox.maxX, y: bbox.maxY))
        lowerRightTriangle.addLine(to: CGPoint(x: bbox.minX, y: bbox.maxY))
        lowerRightTriangle.closeSubpath()

        context.saveGState()
        context.addPath(upperLeftTriangle)
        context.clip()
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.addPath(lowerRightTriangle)
        context.clip()
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.12))
        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }
}
