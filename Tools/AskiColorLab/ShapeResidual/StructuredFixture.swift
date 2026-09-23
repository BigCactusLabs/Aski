import CoreGraphics
import Foundation

// MARK: - Deterministic fixture battery (B5 fair instrument)

/// A battery of five deterministic 256×256 grayscale fixtures. The earlier B4
/// instrument scored a *single* periodic checkerboard, whose one spatial
/// frequency aliases against the cell grid — a column sweep produced a
/// sign-flipping Spearman that was an instrument artifact, not a verdict. The
/// fix (frontier-grounded) is a *diverse, mostly non-periodic* battery so no
/// single frequency dominates, scored by structure-focused oracles at a fixed
/// resolution. See `ShapeResidualCommand` for the oracle wiring.
///
/// Every fixture is a pure function of its constructor (no RNG, no seed) so the
/// luma is byte-identical across builds. Each carries a stable `id`.
enum StructuredFixture {
    static let side = 256

    /// The ordered fixture battery at the canonical 256px side. Order is
    /// deterministic and load-bearing for the CSV row order, the heatmap
    /// filenames, and the pooled-ρ table. Every member is the `.synthetic` pool.
    static let battery: [ResidualFixture] = makeBattery(side: side)

    /// The ordered fixture battery at a given native `side`. `side` scales every
    /// fixture self-similarly (same number of periods/rings/strokes, just higher
    /// native resolution) so each source block fed to the oracle can be ≥ the
    /// oracle footprint — eliminating the sub-cell upsampling that aliased the
    /// residual↔structure correlation at small (256px) fixtures.
    static func makeBattery(side: Int = side) -> [ResidualFixture] {
        [
            makeChecker(side: side),
            makeDiagonal(side: side),
            makeRadial(side: side),
            makeStrokes(side: side),
            makeMixedFrequency(side: side),
        ]
    }

    // MARK: - Fixture constructors

    /// `checker` — coarse 32px checkerboard. The known PERIODIC case, retained
    /// for contrast. The period is coarse so the structure survives the
    /// downscale to `oracleCellSize`.
    static func makeChecker(side: Int = side) -> ResidualFixture {
        let period = max(1, 32 * (side / 256))
        return build(id: "checker", side: side) { x, y in
            ((x / period) + (y / period)) % 2 == 0 ? 235 : 20
        }
    }

    /// `diagonal` — non-axis-aligned bands at 45°. `(x + y)` mod a coarse period
    /// yields diagonal stripes whose edges are oriented diagonally, so no
    /// horizontal/vertical frequency aligns with the cell grid.
    static func makeDiagonal(side: Int = side) -> ResidualFixture {
        let period = max(1, 24 * (side / 256))
        return build(id: "diagonal", side: side) { x, y in
            ((x + y) / period) % 2 == 0 ? 220 : 35
        }
    }

    /// `radial` — concentric rings about the center. Curved, multi-orientation
    /// structure: every cell sees a different edge orientation, so this is the
    /// most "isotropic" member.
    static func makeRadial(side: Int = side) -> ResidualFixture {
        let cx = Double(side) / 2.0
        let cy = Double(side) / 2.0
        let spacing = 14.0 * Double(max(1, side / 256))
        return build(id: "radial", side: side) { x, y in
            let dx = Double(x) - cx
            let dy = Double(y) - cy
            let r = (dx * dx + dy * dy).squareRoot()
            // ~14px ring spacing at 256px (scaled with side) → several rings
            // across the image, with crisp bright/dark transitions.
            return Int(r / spacing) % 2 == 0 ? 230 : 30
        }
    }

    /// `strokes` — a deterministic set of cross marks on a regular grid, on a
    /// dark field. Glyph-scale, text-like subject matter: sparse high-contrast
    /// ink against background, so some cells land on a stroke and some don't.
    static func makeStrokes(side: Int = side) -> ResidualFixture {
        // Cross marks centred on a 32px lattice, 3px stroke half-width, arms
        // 9px long (at 256px; all scaled with side). Pure function of (x,y).
        let f = max(1, side / 256)
        let pitch = 32 * f
        let half = max(1, f)  // stroke half-width (→ 3px strokes at 256)
        let arm = 9 * f  // arm half-length
        return build(id: "strokes", side: side) { x, y in
            let mx = x % pitch
            let my = y % pitch
            // Distance from the nearest lattice centre (pitch/2, pitch/2).
            let dx = abs(mx - pitch / 2)
            let dy = abs(my - pitch / 2)
            let onHorizontalArm = dy <= half && dx <= arm
            let onVerticalArm = dx <= half && dy <= arm
            return (onHorizontalArm || onVerticalArm) ? 240 : 15
        }
    }

    /// `mixedFrequency` — a low-frequency horizontal luminance ramp with
    /// embedded higher-frequency square patches of fine checker. The ramp makes
    /// many cells nearly FLAT (low structure), while the patches inject
    /// high-variance structured cells — so the oracle has real range within a
    /// single fixture (a test asserts both extremes exist).
    static func makeMixedFrequency(side: Int = side) -> ResidualFixture {
        let f = max(1, side / 256)
        let tile = 64 * f
        let lo = 16 * f
        let hi = 48 * f
        let fine = max(1, 4 * f)
        return build(id: "mixedFrequency", side: side) { x, y in
            // Embedded fine-checker patches on a 64px lattice (scaled with side),
            // occupying the central 32px of each tile.
            let tx = x % tile
            let ty = y % tile
            if tx >= lo && tx < hi && ty >= lo && ty < hi {
                // High-frequency fine checker patch (4px at 256).
                return ((x / fine) + (y / fine)) % 2 == 0 ? 245 : 10
            }
            // Smooth low-frequency horizontal ramp elsewhere (≈ flat per cell).
            return 40 + (x * 160) / side
        }
    }

    // MARK: - Builder

    /// Builds a `.synthetic`-pool grayscale `ResidualFixture` from a deterministic
    /// per-pixel luma byte closure. The closure returns a value in 0...255
    /// (clamped defensively). Delegates to the shared `fromGrayBytes` constructor
    /// so synthetic, line-art, and natural fixtures share one image↔luma path.
    static func build(id: String, side: Int = side, _ value: (_ x: Int, _ y: Int) -> Int) -> ResidualFixture {
        let n = side
        var gray = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                gray[y * n + x] = UInt8(max(0, min(255, value(x, y))))
            }
        }
        return ResidualFixture.fromGrayBytes(id: id, width: n, height: n, pool: .synthetic, gray: gray)
    }
}
