import Foundation

// MARK: - Frozen oriented battery (ASTSK-42)

/// Frozen oriented fixtures reused by sampling-lattice and matcher research:
/// diagonal gratings at the pre-registered angles, plus multi-orientation spokes
/// and curved arcs. Every synthetic member is a pure function of its constructor
/// (no RNG) so the luma is byte-identical across builds, built through the shared
/// `StructuredFixture.build` / `ResidualFixture.fromGrayBytes` path so `image` ↔
/// `luma` stay pixel-aligned. The natural pool is loaded separately from the new
/// ≥3072 px NASA corpus.
///
/// **Sizing (gate integrity).** `oracleCellSize = 24` and the sweep runs to 120
/// columns, so every fixture's short side must be ≥ `120 × 24 = 2880`. The
/// synthetic battery is generated at `side = 3072` (3072/120 = 25.6 px/cell ≥ 24).
/// Grating/ring spacing is held at an **absolute** pixel period (not scaled with
/// `side`) so each native cell block carries real local orientation — a
/// side-relative period would make every cell nearly flat at 3072 px.
enum SteerableBattery {
    /// Synthetic generation side (px). See the sizing note above.
    static let side = 3072

    /// Absolute period (px) of the oriented gratings and ring spacing. Held
    /// constant across `side` so a 24-px native cell block sees ≳1 cycle of
    /// oriented structure. Frozen (pre-registration): not tuned on the battery.
    static let periodPx = 12.0

    /// The pre-registered diagonal angles (degrees, gradient/across-edge
    /// orientation). Off-axis, deliberately avoiding 0/45/90 so the descriptor
    /// is exercised at angles the log-polar basis is weakest on.
    static let diagonalAnglesDeg: [Double] = [15, 30, 60, 75]

    // MARK: - Battery assembly

    /// spokes (1) + diagonals (4) + arcs (1) = 6 synthetic fixtures, in a
    /// deterministic order. Naturals are loaded separately (`naturals(...)`).
    static func all(side: Int = side) -> [ResidualFixture] {
        [spokes(side: side)] + diagonals(side: side) + [arcs(side: side)]
    }

    // MARK: - Diagonals (single-orientation gratings)

    /// Single-orientation sinusoidal gratings at the frozen `diagonalAnglesDeg`.
    /// The intensity varies along the wave-vector `(cos α, sin α)`, so the
    /// gradient (across-edge) orientation equals `α`.
    static func diagonals(side: Int = side) -> [ResidualFixture] {
        diagonalAnglesDeg.map { angle in
            let alpha = angle * .pi / 180
            let ca = cos(alpha), sa = sin(alpha)
            return StructuredFixture.build(id: "diag-\(Int(angle))deg", side: side) { x, y in
                let u = Double(x) * ca + Double(y) * sa
                return Int((0.5 + 0.5 * cos(2 * .pi * u / periodPx)) * 255)
            }
        }
    }

    // MARK: - Spokes (multi-orientation)

    /// Twelve lines through the centre at 15° increments on a dark field —
    /// every orientation present, each cell near a spoke sees that spoke's
    /// local orientation. Bright ink (240) on a dark ground (15).
    static func spokes(side: Int = side) -> ResidualFixture {
        let cx = Double(side - 1) / 2, cy = Double(side - 1) / 2
        let halfWidthPx = 1.5
        return StructuredFixture.build(id: "spokes", side: side) { x, y in
            let dx = Double(x) - cx, dy = Double(y) - cy
            let r = (dx * dx + dy * dy).squareRoot()
            if r < 2 { return 240 }
            var deg = atan2(dy, dx) * 180 / .pi
            if deg < 0 { deg += 180 }
            deg = deg.truncatingRemainder(dividingBy: 180)
            let nearest = (deg / 15).rounded() * 15
            // Perpendicular pixel offset from the nearest spoke line.
            let offset = r * abs(sin((deg - nearest) * .pi / 180))
            return offset < halfWidthPx ? 240 : 15
        }
    }

    // MARK: - Arcs (curved, multi-orientation)

    /// Concentric rings about the centre — curved structure whose local
    /// orientation rotates with position, the "most isotropic" member. Bright
    /// rings (230) on a dark ground (30), ring spacing `periodPx`.
    static func arcs(side: Int = side) -> ResidualFixture {
        let cx = Double(side - 1) / 2, cy = Double(side - 1) / 2
        return StructuredFixture.build(id: "arcs", side: side) { x, y in
            let dx = Double(x) - cx, dy = Double(y) - cy
            let r = (dx * dx + dy * dy).squareRoot()
            return Int(r / periodPx) % 2 == 0 ? 230 : 30
        }
    }

    // MARK: - Naturals (held-out NASA corpus)

    /// Default ≥3072 px steerable corpus, relative to the package root.
    static let defaultCorpusRelativePath = "docs/Research/Corpus/nasa-steerable-v1/assets"

    /// Loads the held-out natural pool from the new ≥3072 px NASA corpus (or an
    /// explicit directory). Delegates to `RealFixture.load`, which decodes each
    /// PNG at native size and **throws loudly** (`corpusAssetUnreadable`) if the
    /// directory is missing, empty, or any asset fails to decode — so a gate run
    /// fails rather than silently dropping the naturals condition.
    static func naturals(corpusDirectory: String? = nil) throws -> [ResidualFixture] {
        try RealFixture.load(corpusDirectory: corpusDirectory ?? resolveDefaultCorpus())
    }

    /// Walks up to the package root (the dir holding `Package.swift`) and appends
    /// the steerable corpus path. Falls back to the relative path if no root is
    /// found (the loader then throws on the unreadable directory).
    private static func resolveDefaultCorpus() -> String {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
                return url.appending(path: defaultCorpusRelativePath).path
            }
            url.deleteLastPathComponent()
        }
        return defaultCorpusRelativePath
    }
}
