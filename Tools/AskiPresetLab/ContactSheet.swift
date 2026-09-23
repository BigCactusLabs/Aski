import CoreGraphics
import CoreText
import Foundation

/// Composites candidate renders into one labeled grid PNG so the human can
/// compare charset × columns side by side. Because the thumbnails are small,
/// the sheet doubles as the phone-glance legibility test (does the face still
/// read when tiny?). No metric is drawn — the eye decides.
public enum ContactSheet {
    public struct Item: Sendable {
        public let label: String
        public let image: CGImage
        public init(label: String, image: CGImage) {
            self.label = label
            self.image = image
        }
    }

    /// Lay `items` out in a grid `columns` wide (rows wrap). Each thumbnail is
    /// scaled to `thumbWidth` and labeled. Returns `nil` for empty input or a
    /// degenerate bitmap context.
    public static func compose(
        items: [Item],
        columns: Int,
        thumbWidth: Int = 320,
        background: CGColor,
        ink: CGColor
    ) -> CGImage? {
        guard !items.isEmpty, columns > 0, thumbWidth > 0 else { return nil }

        let padding = 16
        let labelHeight = 22
        let cols = min(columns, items.count)
        let rows = (items.count + cols - 1) / cols

        let thumbs: [(image: CGImage, width: Int, height: Int)] = items.map { item in
            let aspect = Double(item.image.height) / Double(max(1, item.image.width))
            let height = max(1, Int((Double(thumbWidth) * aspect).rounded()))
            return (item.image, thumbWidth, height)
        }
        let maxThumbHeight = thumbs.map(\.height).max() ?? thumbWidth
        let cellWidth = thumbWidth + padding
        let cellHeight = maxThumbHeight + labelHeight + padding
        let width = padding + cols * cellWidth
        let height = padding + rows * cellHeight

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Menlo" as CFString, 13, nil)

        // CGContext origin is bottom-left; lay the grid out top-down.
        for (index, item) in items.enumerated() {
            let row = index / cols
            let col = index % cols
            let x = padding + col * cellWidth
            let cellTopFromBottom = height - (padding + row * cellHeight)
            let thumb = thumbs[index]
            let imageY = cellTopFromBottom - labelHeight - thumb.height
            let labelBaselineY = cellTopFromBottom - labelHeight + 6

            context.draw(
                item.image,
                in: CGRect(
                    x: CGFloat(x), y: CGFloat(imageY),
                    width: CGFloat(thumb.width), height: CGFloat(thumb.height)))
            drawLabel(
                item.label, font: font, color: ink,
                at: CGPoint(x: CGFloat(x), y: CGFloat(labelBaselineY)), in: context)
        }

        return context.makeImage()
    }

    private static func drawLabel(
        _ text: String, font: CTFont, color: CGColor, at point: CGPoint, in context: CGContext
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
