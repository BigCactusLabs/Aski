import AskiToolSupport
import CoreGraphics
import Foundation

@_spi(AskiResearch) import Aski

/// Characterizes the sampling lattice the converter actually resolves, and how
/// much of the 60D log-polar descriptor is reachable at that footprint
/// (2026-08-19 sampling-lattice support-collapse note).
///
/// `census` is a pure function of the cell footprint — it reproduces
/// `ShapeContext.histogram60`'s admission predicate verbatim — so no arm needs an
/// oracle. The realizable arm feeds that census the footprints the converter
/// resolves across the source-aspect range, read from its own `samplingGeometry`
/// rather than assumed; the corpus arm confirms them on real images.
enum LatticeSupport {

    /// Reproduces `ShapeContext.histogram60`'s pixel admission and bin assignment
    /// for a `width x height` cell. Returns how many pixels survive the radius
    /// gate and which of the 60 bins they can reach.
    ///
    /// Kept as an independent reimplementation rather than a call into Aski: the
    /// point of the census is to state the admission rule explicitly, and a
    /// divergence between this and `histogram60` is itself a finding. The
    /// `latticeSupportCensusMatchesHistogram60` test pins them together.
    static func census(width: Int, height: Int) -> (admitted: Int, total: Int, bins: Set<Int>) {
        var bins = Set<Int>()
        var admitted = 0
        let total = max(0, width * height)
        let minDimension = min(width, height)
        guard minDimension > 1 else { return (0, total, bins) }

        let centerX = Float(width) / 2
        let centerY = Float(height) / 2
        let maxRadius = Float(minDimension) / 2
        let logSpan = logf(Float(minDimension))
        guard maxRadius.isFinite, maxRadius > 0, logSpan.isFinite, logSpan > 0 else {
            return (0, total, bins)
        }

        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                let radius = (dx * dx + dy * dy).squareRoot()
                if radius < 0.5 || radius > maxRadius { continue }
                admitted += 1
                let logRadius = logf(radius / maxRadius)
                let radialPosition = (logRadius + logSpan) / logSpan * 5
                guard radialPosition.isFinite else { continue }
                let radialBin = min(4, max(0, Int(radialPosition)))
                var theta = atan2f(dy, dx)
                if theta < 0 { theta += 2 * .pi }
                let angleBin = min(11, Int(theta / (2 * .pi) * 12))
                bins.insert(radialBin * 12 + angleBin)
            }
        }
        return (admitted, total, bins)
    }

    struct FootprintRow: Sendable {
        let label: String
        let cellWidth: Int
        let cellHeight: Int
        let admitted: Int
        let totalPixels: Int
        let reachableBins: Int
        let radialBins: [Int]
        let angularBins: Int
        let droppedX: Int
        let droppedY: Int
        let distinctGlyphs: Int
        let charsetSize: Int
    }

    struct Report: Sendable {
        let analytic: [FootprintRow]
        let empirical: [FootprintRow]
    }

    /// Source shapes the realizable-footprint sweep probes, as `width:height`
    /// ratios spanning ultrawide through tall portrait.
    ///
    /// `cellWidth == oversample` holds only while the source is landscape or
    /// square — on portrait sources the thumbnail budget binds on the height
    /// instead — so the sweep has to cross that boundary to be a census of what
    /// conversion resolves rather than a sample of one regime.
    static let probeShapes: [(label: String, wide: Int, high: Int)] = [
        ("3:1", 3, 1), ("16:9", 16, 9), ("3:2", 3, 2), ("4:3", 4, 3), ("1:1", 1, 1),
        ("3:4", 3, 4), ("2:3", 2, 3), ("9:16", 9, 16), ("1:3", 1, 3),
    ]

    /// Target longest sides tried, smallest first.
    ///
    /// `ImageIOThumbnail` returns the source **unscaled** when its longest side is
    /// already inside the budget, and then the probe reports a footprint that is
    /// an artifact of the probe's own size rather than a regime conversion
    /// resolves from a real photo. So grow the probe until the thumbnail actually
    /// binds, and take the first size that does. The bind is *detected*, never
    /// predicted, so this cannot drift from `thumbnailMaxPixelSize`.
    ///
    /// Starting small matters: at `columns: 80, oversample: 2` the budget is 160px,
    /// so a 512px probe binds and a 2048px one wastes 16× the pixels on an identical
    /// answer. The high end is still needed — the portrait branch of
    /// `thumbnailMaxPixelSize` scales the cap by the aspect ratio to protect the
    /// width, so a 1:3 source at `oversample: 16` needs a budget near 3840px.
    static let probeTargetSides = [512, 1024, 2048, 4096, 8192]

    /// A uniform mid-gray probe image of the requested shape, whose longest side is
    /// at least `targetSide`. Geometry does not depend on content, so the cheapest
    /// deterministic content is the right one.
    ///
    /// The longest side is snapped **up to a multiple of the ratio's long term**, so
    /// the short side divides exactly and the probe's aspect is precisely `wide:high`
    /// at every size. Without that, `512 * 1 / 3 = 170` gives 3.012:1 while
    /// `2048 * 1 / 3 = 682` gives 3.0029:1, and a probe could resolve a different row
    /// count purely because of its own size — which is exactly the class of artifact
    /// this function exists to avoid.
    private static func probeImage(wide: Int, high: Int, targetSide: Int) -> CGImage? {
        guard wide > 0, high > 0, targetSide > 0 else { return nil }
        let longTerm = max(wide, high)
        let longestSide = ((targetSide + longTerm - 1) / longTerm) * longTerm
        let width: Int, height: Int
        if wide >= high {
            width = longestSide
            height = max(1, longestSide / wide * high)
        } else {
            height = longestSide
            width = max(1, longestSide / high * wide)
        }
        let gray = [UInt8](repeating: 128, count: width * height)
        return ResidualFixture.fromGrayBytes(
            id: "probe", width: width, height: height, pool: .synthetic, gray: gray
        ).image
    }

    /// The geometry conversion resolves for a source of this shape, probed at the
    /// smallest size for which the thumbnail budget actually binds. `nil` when no
    /// probe size in `probeTargetSides` downscales — reported as a gap rather
    /// than as a footprint, because an unbound probe measures the probe.
    private static func resolvedGeometry(
        columns: Int, oversample: Int, wide: Int, high: Int
    ) -> SamplingGeometry? {
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB,
            oversample: oversample
        )
        for targetSide in probeTargetSides {
            guard let image = probeImage(wide: wide, high: high, targetSide: targetSide),
                let geometry = converter.samplingGeometry(image, columns: columns)
            else { continue }
            let thumbnailLongest = max(geometry.thumbnailWidth, geometry.thumbnailHeight)
            if thumbnailLongest < max(image.width, image.height) { return geometry }
        }
        return nil
    }

    /// Every cell footprint `prepareConversion` actually resolves at `oversample`,
    /// swept over source aspect and censused, deduplicated by resolved geometry.
    ///
    /// This replaces a fixed `2...8` height range. The realized `cellHeight`
    /// tracks `oversample * tileShape.sourceCellHeightOverWidth` — ≈4 at
    /// oversample 2, 17 at 8, 35 at 16 — so a hardcoded short range prints only
    /// footprints the higher-oversample arms can never resolve, which is the
    /// opposite of a census. Geometry comes from the converter's own
    /// `samplingGeometry`, so this arm cannot drift from `prepareConversion`.
    static func realizableRows(columns: Int, oversample: Int) -> [FootprintRow] {
        var order: [SamplingGeometry] = []
        var shapes: [SamplingGeometry: [String]] = [:]
        for shape in probeShapes {
            guard
                let geometry = resolvedGeometry(
                    columns: columns, oversample: oversample, wide: shape.wide, high: shape.high)
            else { continue }
            if shapes[geometry] == nil {
                shapes[geometry] = []
                order.append(geometry)
            }
            shapes[geometry]?.append(shape.label)
        }

        return order.map { geometry in
            let c = census(width: geometry.cellWidth, height: geometry.cellHeight)
            return FootprintRow(
                label: "os\(oversample) \(shapes[geometry]?.joined(separator: ",") ?? "")",
                cellWidth: geometry.cellWidth, cellHeight: geometry.cellHeight,
                admitted: c.admitted, totalPixels: c.total, reachableBins: c.bins.count,
                radialBins: Set(c.bins.map { $0 / 12 }).sorted(),
                angularBins: Set(c.bins.map { $0 % 12 }).count,
                droppedX: geometry.droppedX, droppedY: geometry.droppedY,
                distinctGlyphs: 0, charsetSize: 0)
        }
    }

    static func run(
        columns: Int,
        oversamples: [Int],
        corpus: String?
    ) throws -> Report {
        let analytic = oversamples.flatMap { os in
            realizableRows(columns: columns, oversample: os)
        }

        let fixtures = try RealFixture.load(corpusDirectory: corpus)
        let characterSet = StandardCharacterSet.standard
        var empirical: [FootprintRow] = []

        for fixture in fixtures {
            for oversample in oversamples {
                let converter = ASCIIConverter(
                    characterSet: characterSet,
                    palette: BuiltInPalette.monochrome,
                    colorSpace: .sRGB,
                    oversample: oversample
                )
                guard let geometry = converter.samplingGeometry(fixture.image, columns: columns)
                else { continue }
                let c = census(width: geometry.cellWidth, height: geometry.cellHeight)
                let grid = converter.convert(fixture.image, columns: columns)
                let distinct = Set(grid.cells.flatMap { $0 }.map(\.character)).count
                empirical.append(
                    FootprintRow(
                        label: "\(fixture.id)@os\(oversample)",
                        cellWidth: geometry.cellWidth, cellHeight: geometry.cellHeight,
                        admitted: c.admitted, totalPixels: c.total, reachableBins: c.bins.count,
                        radialBins: Set(c.bins.map { $0 / 12 }).sorted(),
                        angularBins: Set(c.bins.map { $0 % 12 }).count,
                        droppedX: geometry.droppedX, droppedY: geometry.droppedY,
                        distinctGlyphs: distinct, charsetSize: characterSet.characters.count))
            }
        }
        return Report(analytic: analytic, empirical: empirical)
    }

    static func format(_ report: Report) -> String {
        var lines: [String] = []
        lines.append("# Sampling-lattice support census")
        lines.append("")
        lines.append("## Realizable footprints (geometries prepareConversion resolves, swept over source aspect)")
        lines.append(
            "oversample / source shapes | cell | admitted/total px | reachable bins | radial | "
                + "angular | dropped")
        for row in report.analytic {
            lines.append(
                "\(row.label) | \(row.cellWidth)x\(row.cellHeight) | "
                    + "\(row.admitted)/\(row.totalPixels) | \(row.reachableBins)/60 | "
                    + "\(row.radialBins) | \(row.angularBins)/12 | \(row.droppedX)x\(row.droppedY)")
        }
        lines.append("")
        lines.append("## Empirical (footprints the converter actually resolved)")
        lines.append("fixture@oversample | cell | admitted/total | bins | dropped | distinct glyphs")
        for row in report.empirical {
            lines.append(
                "\(row.label) | \(row.cellWidth)x\(row.cellHeight) | "
                    + "\(row.admitted)/\(row.totalPixels) | \(row.reachableBins)/60 | "
                    + "\(row.droppedX)x\(row.droppedY) | \(row.distinctGlyphs)/\(row.charsetSize)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Sub-cell lattice-phase sweep (2026-08-19 note, section 6).
///
/// The converter pins the lattice at pixel (0,0), so phase is emulated by
/// cropping the native image. Every arm crops a window of identical dimensions —
/// native size minus one cell pitch on each axis — so every arm resolves the same
/// grid shape and goes through an identical crop/thumbnail/convert path; only the
/// alignment of content to cell boundaries changes. Each arm is scored against
/// its OWN cropped source so content differences are not charged to phase, and a
/// full-pitch null arm gives the content-change floor the phase spread must clear.
///
/// "Its own cropped source" means the pixels the converter *read* from that crop,
/// via `SampledSource` and the arm's own resolved `SamplingGeometry` — not an
/// equal `rows*cols` partition of the crop. Since ASKI-65 the two coincide,
/// but reading the arm's own geometry keeps that a checked property rather than
/// an assumption: a sweep that scored a partition the converter did not sample
/// would charge a fixed misalignment to phase, which is the one thing this
/// instrument exists to isolate.
enum LatticePhase {
    struct Row: Sendable {
        let fixtureID: String
        let oversample: Int
        let pitchX: Int
        let pitchY: Int
        let arms: Int
        let best: Double
        let worst: Double
        let spreadPercent: Double
        let nullArmPercent: Double
    }

    /// Mirrors `RealFixture.fixture(from:id:)`: a native-size DeviceGray redraw so
    /// the cropped window's `image` and `luma` stay consistent by construction and
    /// the oracle scores each phase arm against exactly the pixels that arm was fed.
    private static func fixture(from image: CGImage, id: String) -> ResidualFixture? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
            let context = ResidualFixture.makeGrayContext(width: width, height: height)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let gray = ResidualFixture.grayBytes(from: context, width: width, height: height)
        else { return nil }
        return ResidualFixture.fromGrayBytes(
            id: id, width: width, height: height, pool: .natural, gray: gray)
    }

    static let fractions: [Double] = [0.0, 0.25, 0.5, 0.75]

    static func run(
        columns: Int,
        oversamples: [Int],
        footprint: Int,
        corpus: String?
    ) throws -> [Row] {
        let fixtures = try RealFixture.load(corpusDirectory: corpus)
        let characterSet = StandardCharacterSet.standard
        var rasters: [Character: [Float]] = [:]
        for character in characterSet.characters {
            rasters[character] = GlyphRaster.luma(
                character: character, width: footprint, height: footprint)
        }

        var rows: [Row] = []
        for fixture in fixtures {
            for oversample in oversamples {
                let converter = ASCIIConverter(
                    characterSet: characterSet,
                    palette: BuiltInPalette.monochrome,
                    colorSpace: .sRGB,
                    oversample: oversample
                )
                guard let geometry = converter.samplingGeometry(fixture.image, columns: columns)
                else { continue }
                // Native pitch, not lattice pitch: the crop happens before
                // decode. Derived from the converter's own cell rather than from
                // `width / columns` so the phase tracks whatever lattice the
                // converter resolves. Since ASKI-65 the lattice is an exact
                // multiple of the grid and the two agree; before it the equal
                // partition overstated the cell by 9% at 2048px, `columns: 80`,
                // `oversample: 2`, which put every fractional arm at the wrong
                // phase and left the full-pitch null arm not phase-equivalent to
                // (0,0) — the one property the null arm exists to have.
                let pitchX = geometry.cellWidth * fixture.width / max(1, geometry.thumbnailWidth)
                let pitchY = geometry.cellHeight * fixture.height / max(1, geometry.thumbnailHeight)
                guard pitchX >= 4, pitchY >= 4 else { continue }
                let windowWidth = fixture.width - pitchX
                let windowHeight = fixture.height - pitchY

                func score(fx: Double, fy: Double) -> Double? {
                    let originX = Int(Double(pitchX) * fx)
                    let originY = Int(Double(pitchY) * fy)
                    let rect = CGRect(
                        x: originX, y: originY, width: windowWidth, height: windowHeight)
                    guard let cropped = fixture.image.cropping(to: rect),
                        let window = Self.fixture(from: cropped, id: "\(fixture.id)-phase")
                    else { return nil }
                    let grid = converter.convert(cropped, columns: columns)
                    let gridRows = grid.rows, gridCols = grid.columns
                    guard gridRows > 0, gridCols > 0 else { return nil }
                    // Geometry of THIS arm's cropped window, not of the uncropped
                    // fixture: each arm resolves its own lattice, and only the
                    // converter's own sampled rect keeps the promise that every
                    // arm is scored against the pixels that arm was fed.
                    guard let armGeometry = converter.samplingGeometry(cropped, columns: columns),
                        armGeometry.rows == gridRows, armGeometry.columns == gridCols
                    else { return nil }
                    var sum = 0.0
                    var count = 0
                    for row in 0..<gridRows {
                        for col in 0..<gridCols {
                            guard
                                let block = SampledSource.lumaBlock(
                                    window, cellRow: row, cellCol: col, geometry: armGeometry),
                                block.width >= 2, block.height >= 2,
                                let raster = rasters[grid.cells[row][col].character]
                            else { continue }
                            let source = LumaResample.resample(
                                block.luma, srcWidth: block.width, srcHeight: block.height,
                                dstWidth: footprint, dstHeight: footprint)
                            let value = GMSD.gmsd(
                                raster, source, width: footprint, height: footprint)
                            if value.isFinite {
                                sum += value
                                count += 1
                            }
                        }
                    }
                    return count > 0 ? sum / Double(count) : nil
                }

                var phaseScores: [Double] = []
                for fy in Self.fractions {
                    for fx in Self.fractions {
                        if let value = score(fx: fx, fy: fy) { phaseScores.append(value) }
                    }
                }
                guard let best = phaseScores.min(), let worst = phaseScores.max(), best > 0,
                    let origin = score(fx: 0, fy: 0), let nullArm = score(fx: 1.0, fy: 1.0)
                else { continue }
                rows.append(
                    Row(
                        fixtureID: fixture.id, oversample: oversample,
                        pitchX: pitchX, pitchY: pitchY, arms: phaseScores.count,
                        best: best, worst: worst,
                        spreadPercent: (worst - best) / best * 100,
                        nullArmPercent: abs(nullArm - origin) / best * 100))
            }
        }
        return rows
    }

    static func format(_ rows: [Row]) -> String {
        var lines = ["# Sub-cell lattice-phase sweep"]
        lines.append("fixture | oversample | pitch | arms | best | worst | spread% | nullArm%")
        for row in rows {
            lines.append(
                String(
                    format: "%@ | %d | %dx%d | %d | %.5f | %.5f | %.2f | %.2f",
                    row.fixtureID, row.oversample, row.pitchX, row.pitchY, row.arms,
                    row.best, row.worst, row.spreadPercent, row.nullArmPercent))
        }
        return lines.joined(separator: "\n")
    }
}
