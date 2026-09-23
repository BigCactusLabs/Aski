/// Mirrors the arm the public target-width entry point routes to after the
/// ASKI-63 SHIP-B verdict: `linear-srgb-area-average-4x` for the supersample arm.
enum TargetWidthRenderRecord {
    static let resampleSpace = "linear-srgb-area-average-4x"
}
