/// A normalized reveal origin in grid space: `(0, 0)` is the top-leading cell,
/// `(1, 1)` the bottom-trailing one.
///
/// **Coordinate domain (ASKI-35): finite values outside `0...1` are SUPPORTED,
/// not clamped or rejected.** `PatternEvaluator.radialDistance` — the only
/// consumer — normalizes each cell's distance by the largest distance from the
/// anchor to a grid corner, so an off-grid origin such as `(-1, 0.5)` is
/// meaningful geometry: a flatter wavefront sweeping in from outside the grid.
/// Only a NON-FINITE coordinate has no geometry; it resolves to the centre
/// (`0.5`) at that same single consumption point, so `x`/`y` are stored exactly
/// as given here and no check competes with the one downstream.
public struct AnimationAnchor: Sendable, Hashable {
    public var x: Double
    public var y: Double

    /// Stores `x`/`y` verbatim. See the type's coordinate-domain note: out-of
    /// `0...1` finite coordinates are a supported effect, and the non-finite
    /// rule lives at the consumption point in `PatternEvaluator`.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let center = AnimationAnchor(x: 0.5, y: 0.5)
    public static let topLeading = AnimationAnchor(x: 0, y: 0)
    public static let topTrailing = AnimationAnchor(x: 1, y: 0)
    public static let bottomLeading = AnimationAnchor(x: 0, y: 1)
    public static let bottomTrailing = AnimationAnchor(x: 1, y: 1)
}
