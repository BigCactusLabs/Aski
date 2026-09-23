import ArgumentParser
import CoreGraphics
import Foundation

/// `ExpressibleByArgument` background color: `#RRGGBB` hex or a small named set,
/// including `clear`/`transparent` for alpha-zero output.
/// Stores components as `Double` (so the type stays `Equatable`/`Sendable`) and
/// builds the `CGColor` on demand. Defaults to opaque black for back-compat.
public struct BackgroundColor: ExpressibleByArgument, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = BackgroundColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let clear = BackgroundColor(red: 0, green: 0, blue: 0, alpha: 0)

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Canonical uppercase `#RRGGBBAA` serialization for deterministic records.
    public var canonicalRGBAHex: String {
        String(
            format: "#%02X%02X%02X%02X",
            Self.byte(red),
            Self.byte(green),
            Self.byte(blue),
            Self.byte(alpha)
        )
    }

    public init?(argument: String) {
        if let named = Self.named[argument.lowercased()] {
            self = named
            return
        }
        guard let parsed = Self.parseHex(argument) else { return nil }
        self = parsed
    }

    private static let named: [String: BackgroundColor] = [
        "black": .black,
        "clear": .clear,
        "transparent": .clear,
        "white": BackgroundColor(red: 1, green: 1, blue: 1, alpha: 1),
        "red": BackgroundColor(red: 1, green: 0, blue: 0, alpha: 1),
        "green": BackgroundColor(red: 0, green: 1, blue: 0, alpha: 1),
        "blue": BackgroundColor(red: 0, green: 0, blue: 1, alpha: 1),
        "gray": BackgroundColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
        "grey": BackgroundColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
    ]

    private static func parseHex(_ string: String) -> BackgroundColor? {
        var hex = string
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return BackgroundColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func byte(_ component: Double) -> Int {
        guard component.isFinite else { return 0 }
        return Int((min(max(component, 0), 1) * 255).rounded())
    }
}
