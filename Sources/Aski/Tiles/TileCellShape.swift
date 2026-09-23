/// Render-time cell shape for a `TileGrid`. A closed geometric set; stays an
/// `enum` so it can be `@frozen` post-1.0. Distinct from `ASCIITileShape`,
/// which controls the sample-grid aspect ratio on the converter.
///
/// `Hashable` is required by `MosaicPathCache.Key` and is otherwise useful for
/// consumers building shape-to-config dictionaries.
public enum TileCellShape: Sendable, Hashable {
    case square
    case hex
    case triangle
    case diamond
    case circle
}
