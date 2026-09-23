import Foundation

extension StandardCharacterSet {
    public static let standard: StandardCharacterSet = loadOrFatal(name: "standard")
    public static let minimal: StandardCharacterSet = loadOrFatal(name: "minimal")
    public static let blocks: StandardCharacterSet = loadOrFatal(name: "blocks")
    public static let dots: StandardCharacterSet = loadOrFatal(name: "dots")
    public static let lines: StandardCharacterSet = loadOrFatal(name: "lines")
    public static let diagonal: StandardCharacterSet = loadOrFatal(name: "diagonal")
    public static let cross: StandardCharacterSet = loadOrFatal(name: "cross")
    public static let diamond: StandardCharacterSet = loadOrFatal(name: "diamond")
    public static let mixed: StandardCharacterSet = loadOrFatal(name: "mixed")
    public static let braille: StandardCharacterSet = loadOrFatal(name: "braille")
}
