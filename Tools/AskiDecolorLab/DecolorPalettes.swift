import Aski

/// A lab palette: a `BuiltInPalette` content payload with a stable `id` so the
/// oracle rows and CSV can attribute every cell to a palette by name.
///
/// `fullColor` is the converter's pass-through palette — its
/// `content.isPassThrough == true`, so the resolved palette keeps the adjusted
/// source color (FG is not quantized). `monochrome` and `ansi16` reuse the
/// matching `BuiltInPalette` presets.
public struct DecolorPalette: ASCIIPalette, Sendable {
    public let id: String
    public let content: PaletteContent

    public init(id: String, content: PaletteContent) {
        self.id = id
        self.content = content
    }
}

/// The three lab palettes, in increasing color cardinality:
/// `monochrome` (1 ink) → `ansi16` (16 quantized) → `fullColor` (pass-through).
public enum DecolorPalettes {
    public static let monochrome = DecolorPalette(
        id: "monochrome",
        content: BuiltInPalette.monochrome.content
    )

    public static let ansi16 = DecolorPalette(
        id: "ansi16",
        content: BuiltInPalette.ansi16.content
    )

    /// Pass-through palette: FG is the adjusted source color, not quantized.
    /// `ResolvedPalette(content:).isPassThrough == true`.
    public static let fullColor = DecolorPalette(
        id: "fullColor",
        content: BuiltInPalette.fullColor.content
    )

    public static let all: [DecolorPalette] = [monochrome, ansi16, fullColor]
}
