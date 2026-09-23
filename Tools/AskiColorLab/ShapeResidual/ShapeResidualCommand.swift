@_spi(AskiResearch) import Aski
import AskiToolSupport
import CoreGraphics
import Foundation

/// Parser-agnostic invocation context for `shape-residual-map`. Constructed by
/// the SAP subcommand wrapper and directly by tests (mirrors
/// `DecolorLabArguments` — a value type the test can build without a process).
public struct ShapeResidualArguments: Equatable, Sendable {
    public let outputDirectory: String
    /// Column counts to sweep (repeatable `--columns`). Each is analysed
    /// independently; the per-cell CSV and `spearman_summary.csv` carry the column
    /// count, and heatmaps are emitted only at the canonical column.
    public let columns: [Int]
    /// Native side (px) at which the fixture battery is rendered. Larger sizes
    /// keep each source block ≥ the oracle footprint at canonical column counts
    /// (no sub-cell upsampling). Defaults to the canonical 256px battery.
    public let fixtureSize: Int
    /// Escape hatch: when true, the oracle-native validity guard is bypassed and
    /// the run is stamped EXPLORATORY in the manifest (an upsampled-block run is
    /// non-decisive by definition and cannot feed the pre-registered verdict rule).
    public let allowUpsampledOracleBlocks: Bool
    /// Which fixture battery to run (default `.synthetic`).
    public let battery: BatterySelection
    /// Optional override for the natural-pool corpus directory (nil → the
    /// committed `nasa-structure-v1` corpus via the package-root walk-up).
    public let corpusDirectory: String?
    public let gitShaOverride: String?

    public init(
        outputDirectory: String,
        columns: [Int],
        fixtureSize: Int = ShapeResidualCommand.defaultFixtureSize,
        allowUpsampledOracleBlocks: Bool = false,
        battery: BatterySelection = .synthetic,
        corpusDirectory: String? = nil,
        gitShaOverride: String? = nil
    ) {
        self.outputDirectory = outputDirectory
        self.columns = columns
        self.fixtureSize = fixtureSize
        self.allowUpsampledOracleBlocks = allowUpsampledOracleBlocks
        self.battery = battery
        self.corpusDirectory = corpusDirectory
        self.gitShaOverride = gitShaOverride
    }
}

/// Mutable accumulator for one population's paired oracle vectors (per pool, and
/// concatenated for the grand pooled). All five arrays stay index-aligned.
private struct PooledVectors {
    var residual: [Double] = []
    var oneMinusFull: [Double] = []
    var oneMinusStructure: [Double] = []
    var gmsd: [Double] = []
    var oneMinusHaar: [Double] = []
    /// Basis-augmentation channels (ASTSK-31 Phase 6), aligned with `residual`.
    var dOrient: [Double] = []
    var dRadial: [Double] = []
    var totalCells = 0
}

/// Which fixture battery the instrument runs (ASTSK-31 Phase 5). `synthetic` is
/// the default (the pre-Phase-5 behaviour); the decisive run uses `all`.
public enum BatterySelection: String, Sendable, CaseIterable {
    /// The 5 procedural fixtures only (synthetic pool).
    case synthetic
    /// Real-content fixtures: the procedural glyph sheet (line-art pool) + the
    /// NASA photo corpus (natural pool).
    case real
    /// Every fixture: synthetic ++ real.
    case all
}

/// B5: the **fair** shape-residual instrument. Surfaces the per-cell logPolar
/// shape residual (`convertWithResidual`, real 60D squared-L2 distance) and
/// scores it against FOUR independent, pixel-only oracles computed at a FIXED
/// resolution, over a DIVERSE 5-fixture battery, then rank-correlates per
/// fixture and pooled.
///
/// **Why this shape.** The B4 instrument used one oracle (full SSIM,
/// luminance-confounded for binary-glyph-vs-tone) at a *column-dependent* block
/// size (degenerate 2×2 windows at high columns), over a *single* periodic
/// checkerboard — a combination that produced a sign-flipping Spearman that was
/// an instrument artifact. The fix: structure-focused oracles (GMSD + SSIM
/// structure term + HaarPSI, the ASTSK-31 diagonal/radial arbiter) at
/// `oracleCellSize`, over the non-periodic battery, with full SSIM retained only
/// as a contrast oracle. All four oracles read PIXELS ONLY (rasterized chosen
/// glyph vs resampled source-cell block) and never the residual, which is what
/// makes the rank correlation meaningful.
public enum ShapeResidualCommand {
    public static let commandName = "shape-residual-map"
    public static let csvFileName = "shape_residual.csv"
    /// The per-(fixture|pool, column, oracle) Spearman summary — the SOLE source for
    /// every number in the verdict tables (ASTSK-31 Phase 7).
    public static let summaryCsvFileName = "spearman_summary.csv"
    public static let csvHeader = [
        "columns",
        "fixture_id", "row", "col", "character",
        "residual", "ssim_full", "ssim_structure", "gmsd", "haarpsi",
        "d_orient", "d_radial",
    ]
    /// `spearman_summary.csv` header: one row per (battery, pool/fixture, columns,
    /// oracle). `fixture` is `POOLED` for per-pool rows.
    ///
    /// The three trailing columns are the sampling regime the ρ was measured at
    /// (ASKI-29 AC#2). They live here and not only in the printed table because
    /// this CSV is the SOLE source for every verdict number, and a verdict read
    /// at 48 of 60 reachable bins does not transfer to a preset that reaches 2–3.
    /// A pooled row whose fixtures resolved different footprints reports `mixed`.
    public static let summaryCsvHeader = [
        "battery", "pool", "fixture", "columns", "oracle", "rho",
        "included_cells", "excluded_cells",
        "cell_width", "cell_height", "reachable_bins",
    ]
    /// Committed corpus path recorded in the manifest `datasets` for any
    /// natural-pool run (repo-root-relative; `BuildResearchIndex` IndexCheck requires
    /// the `docs/Research/Corpus/` prefix and that the path exists).
    public static let naturalCorpusDataset = "docs/Research/Corpus/nasa-structure-v1/assets"

    /// Fixed oracle footprint (square). Every cell's chosen glyph is rasterized
    /// to `oracleCellSize × oracleCellSize` and the fixture's source-cell block
    /// is resampled to the same size before any oracle runs. This DECOUPLES the
    /// oracle from `columns` — the key degeneracy fix. 24px is large enough for
    /// Prewitt gradients and meaningful SSIM windows, small enough to stay
    /// glyph-scale.
    public static let oracleCellSize = 24

    /// The canonical native fixture side (px) the battery renders at by default.
    /// Larger sizes (via `--fixture-size`) keep each source block ≥ the oracle
    /// footprint at canonical column counts, eliminating sub-cell upsampling.
    public static let defaultFixtureSize = StructuredFixture.side

    /// The minimum converter `oversample` that keeps the matcher from
    /// thumbnailing (downscaling) the fixture before the residual is computed.
    ///
    /// The residual MUST be sampled from the same pixels the oracle reads
    /// (`fixture.lumaBlock` native blocks). With the default `oversample = 2`,
    /// `convertWithResidual` thumbnails a 256px fixture to
    /// `max(cols,rows)·2 = 160px` at `columns=80` — a downscale, which would let
    /// ImageIO resampling loss masquerade as glyph residual. We instead pick an
    /// oversample large enough that the thumbnail ≥ the fixture's longest side,
    /// so `ImageIOThumbnail.decode` returns the **native** image (no resampling)
    /// and the residual + oracle are pixel-aligned. Mirrors AskiDecolorLab's
    /// no-downscale invariant. Dynamic (per `columns`) so the whole column sweep
    /// stays no-downscale — e.g. `columns=80 → 4`, `columns=32 → 8`. Raising
    /// `oversample` changes resolution only; the matcher algorithm is unchanged
    /// (`LogPolarKernel`'s Sobel path is gated on `options.edgeEmphasis > 0`,
    /// which this lab never sets).
    ///
    /// `fixtureHeight` defaults to `fixtureSide` (square); pass it for non-square
    /// corpus PNGs (the `--corpus-dir` loader accepts arbitrary sizes). The grid's
    /// row count is driven by HEIGHT, so a width-only computation underestimates the
    /// oversample for tall images and the no-downscale guard would throw spuriously —
    /// we size from both dimensions (longest side over the real `.wide` grid).
    static func noDownscaleOversample(
        columns: Int, fixtureSide: Int = StructuredFixture.side, fixtureHeight: Int? = nil
    ) -> Int {
        let height = fixtureHeight ?? fixtureSide
        let maxGridSide = ToolArgumentBounds.thumbnailMaxPixelSize(
            imageWidth: fixtureSide, imageHeight: height,
            columns: columns, tileShape: .wide, oversample: 1
        )
        let needed = Int((Double(max(fixtureSide, height)) / Double(max(1, maxGridSide))).rounded(.up))
        return max(ToolArgumentBounds.defaultOversample, needed)
    }

    /// Pure predicate: would the converter downscale a `fixtureSide`-px fixture
    /// at this `columns`/`oversample`? The guard in `analyze` enforces the
    /// negation on the real grid; a regression test pins the original bug here
    /// (`columns=80, oversample=2 → true`; the fix's `oversample=4 → false`).
    static func wouldDownscale(columns: Int, fixtureSide: Int, oversample: Int) -> Bool {
        ToolArgumentBounds.thumbnailMaxPixelSize(
            imageWidth: fixtureSide, imageHeight: fixtureSide,
            columns: columns, tileShape: .wide, oversample: oversample
        ) < fixtureSide
    }

    /// Pure predicate: would ANY source-cell block be smaller than `oracleCellSize`
    /// px NATIVELY at this grid, forcing `LumaResample` to UPSAMPLE a sub-footprint
    /// block into the oracle? Blocks partition the native grid (`Fixture.lumaBlock`),
    /// so the minimum block is `fixtureSide / gridColumns` wide and
    /// `(fixtureHeight ?? fixtureSide) / gridRows` tall (integer floor). Width binds
    /// under `.wide` for a square fixture (`gridColumns ≥ gridRows`), but both are
    /// checked — `fixtureHeight` defaults to `fixtureSide` (square) and must be passed
    /// for non-square corpus PNGs, else the row-block height is mis-derived from the
    /// width. The `analyze` guard enforces the negation on the real grid; tests pin the
    /// violating 256px configs and the native 2048px decisive sweep.
    static func oracleBlockWouldUpsample(
        fixtureSide: Int, gridRows: Int, gridColumns: Int, fixtureHeight: Int? = nil
    ) -> Bool {
        guard gridRows > 0, gridColumns > 0 else { return true }
        let height = fixtureHeight ?? fixtureSide
        return (fixtureSide / gridColumns) < oracleCellSize
            || (height / gridRows) < oracleCellSize
    }

    // MARK: - Battery composition (ASTSK-31 Phase 5)

    /// Composes the ordered fixture battery for a `--battery` selection. Order is
    /// deterministic and load-bearing for CSV rows, heatmap filenames, and the
    /// per-pool ρ:
    /// - `.synthetic` → the 5 procedural fixtures (`.synthetic` pool).
    /// - `.real` → `glyphSheet` (line-art pool) then the natural photos (sorted).
    /// - `.all` → `.synthetic` ++ `.real`.
    ///
    /// `glyphSheet` and the synthetic fixtures render at `side`; the natural
    /// photos load at their native size (no resampling). The natural/line-art
    /// arms are only loaded when the selection needs them, so a `.synthetic` run
    /// never touches the corpus.
    ///
    /// - Throws: `ShapeResidualError.corpusAssetUnreadable` if a natural-pool
    ///   selection cannot read the corpus.
    public static func makeBattery(
        selection: BatterySelection, side: Int, corpusDirectory: String?
    ) throws -> [ResidualFixture] {
        switch selection {
        case .synthetic:
            return StructuredFixture.makeBattery(side: side)
        case .real:
            return [GlyphSheetFixture.make(side: side)]
                + (try RealFixture.load(corpusDirectory: corpusDirectory))
        case .all:
            return StructuredFixture.makeBattery(side: side)
                + [GlyphSheetFixture.make(side: side)]
                + (try RealFixture.load(corpusDirectory: corpusDirectory))
        }
    }

    /// Heatmap filename for a fixture's residual field.
    public static func heatmapFileName(for fixtureID: String) -> String {
        "shape_residual_heatmap_\(fixtureID).png"
    }

    /// The column the residual heatmaps are rendered at: `80` when it is in the
    /// sweep, else the largest swept column (heatmaps are emitted at one column only,
    /// to keep the results dir bounded).
    public static func canonicalColumn(_ columns: [Int]) -> Int {
        columns.contains(80) ? 80 : (columns.max() ?? 80)
    }

    /// The manifest `datasets` list: the committed corpus for any natural-pool
    /// battery (so `BuildResearchIndex` can resolve the source assets), empty for the
    /// synthetic-only battery. A `corpusDirectory` override is recorded verbatim.
    public static func manifestDatasets(battery: BatterySelection, corpusDirectory: String?) -> [String] {
        battery == .synthetic ? [] : [corpusDirectory ?? naturalCorpusDataset]
    }

    /// The deterministic outputs list: the per-cell CSV, the Spearman summary CSV,
    /// then one heatmap per fixture (battery order) at the canonical column.
    public static func emittedOutputs(canonicalFixtureIDs: [String]) -> [String] {
        [csvFileName, summaryCsvFileName] + canonicalFixtureIDs.map { heatmapFileName(for: $0) }
    }

    // MARK: - Per-fixture analysis

    /// Per-fixture analysis: the cell rows, the residual field (for that
    /// fixture's heatmap), and the three per-fixture Spearman ρ.
    public struct FixtureAnalysis: Sendable {
        public let id: String
        /// The pool this fixture's cells are pooled into for the verdict rule.
        public let pool: FixturePool
        /// Per-cell rows in row-major order (CSV source of truth for this fixture).
        public let rows: [ResidualRow]
        public let gridRows: Int
        public let gridColumns: Int
        /// Raw per-cell residual field, row-major (this fixture's heatmap ramp source).
        public let residualField: [Float]
        public let finiteMin: Float
        public let finiteMax: Float
        /// ρ(residual, 1 − ssim_full) over cells where both are finite.
        public let rhoSSIMFull: Double
        /// ρ(residual, 1 − ssim_structure).
        public let rhoSSIMStructure: Double
        /// ρ(residual, gmsd).
        public let rhoGMSD: Double
        /// ρ(residual, 1 − haarpsi). HaarPSI is the ASTSK-31 diagonal/radial arbiter.
        public let rhoHaarPSI: Double
        /// ρ(residual, consensus): consensus = per-cell median of the three
        /// structure oracles' ranks within THIS fixture (population-relative).
        public let rhoConsensus: Double
        /// ρ(augmented, consensus) for each pre-registered mix in
        /// `BasisAugmentation.mixes` order (ASTSK-31 Phase 6, AC#4). Same
        /// population-relative consensus as `rhoConsensus`; the per-fixture lift is
        /// `augmentedRhos[i] − rhoConsensus`.
        public let augmentedRhos: [Double]
        /// Cells fed into THIS fixture's correlations (residual + all oracles finite).
        public let includedCells: Int
        /// The cell footprint the converter actually resolved for this fixture,
        /// read from its own `samplingGeometry` (ASKI-29 AC#2). Zero when the
        /// geometry could not be resolved.
        public let cellWidth: Int
        public let cellHeight: Int
        /// How many of the 60 log-polar bins that footprint can reach, from the
        /// same census `LatticeSupport` runs.
        ///
        /// Recorded alongside every verdict because it is the number that decides
        /// whether a verdict transfers: the archived descriptor kills all ran at
        /// the no-downscale oversample this harness picks, which reaches 48 of 60
        /// bins, while the shipping preset reaches 2–3. A ρ measured on a basis
        /// the product never populates says nothing about the product.
        public let reachableBins: Int
    }

    /// The sampling regime one row was measured at (ASKI-29 AC#2): the cell
    /// footprint the converter resolved, and how many of the 60 log-polar bins
    /// that footprint can reach.
    public struct Regime: Sendable, Equatable {
        public let cellWidth: Int
        public let cellHeight: Int
        public let reachableBins: Int
    }

    /// The regime shared by every fixture in `fixtures`, or `nil` when they
    /// disagree — a ρ pooled across two regimes cannot be quoted at either, so
    /// the row says `mixed` rather than picking one.
    static func sharedRegime(_ fixtures: [FixtureAnalysis]) -> Regime? {
        guard let first = fixtures.first else { return nil }
        let regime = Regime(
            cellWidth: first.cellWidth, cellHeight: first.cellHeight,
            reachableBins: first.reachableBins)
        let uniform = fixtures.allSatisfy {
            Regime(
                cellWidth: $0.cellWidth, cellHeight: $0.cellHeight,
                reachableBins: $0.reachableBins) == regime
        }
        return uniform ? regime : nil
    }

    /// Pooled ρ for one `FixturePool` — the per-pool statistic the verdict rule
    /// reads (synthetic / natural pools on the general axis). Ranks for the
    /// consensus are computed WITHIN this pool's population (population-relative).
    public struct PoolStats: Sendable {
        public let pool: FixturePool
        public let rhoSSIMFull: Double
        public let rhoSSIMStructure: Double
        public let rhoGMSD: Double
        public let rhoHaarPSI: Double
        public let rhoConsensus: Double
        /// ρ(augmented, consensus) for each pre-registered mix in
        /// `BasisAugmentation.mixes` order, consensus ranks computed WITHIN this pool.
        public let augmentedRhos: [Double]
        public let includedCells: Int
        public let totalCells: Int
        /// The regime this pool's fixtures were measured at, or `nil` when they
        /// did not all resolve the same footprint.
        public let regime: Regime?
    }

    /// Parser-agnostic battery analysis. Carries per-fixture results, the pooled ρ
    /// across all fixtures for each oracle, and the per-pool pooled ρ, so both
    /// `run(...)` and tests can read the statistics without round-tripping
    /// through `result.yaml`.
    public struct Analysis: Sendable {
        public let fixtures: [FixtureAnalysis]
        /// Per-pool pooled ρ, one entry per distinct pool present, in
        /// `FixturePool.allCases` order (synthetic, natural, lineArt).
        public let pools: [PoolStats]
        /// The converter `oversample` used (chosen to avoid any downscale of the
        /// fixtures, so the residual and the oracle are pixel-aligned).
        public let oversample: Int
        /// Pooled ρ(residual, 1 − ssim_full) across every finite cell of every fixture.
        public let pooledRhoSSIMFull: Double
        /// Pooled ρ(residual, 1 − ssim_structure).
        public let pooledRhoSSIMStructure: Double
        /// Pooled ρ(residual, gmsd).
        public let pooledRhoGMSD: Double
        /// Pooled ρ(residual, 1 − haarpsi).
        public let pooledRhoHaarPSI: Double
        /// Pooled ρ(residual, consensus): consensus = per-cell median of the three
        /// structure oracles' ranks across the WHOLE pooled population.
        public let pooledRhoConsensus: Double
        /// Pooled ρ(augmented, consensus) for each pre-registered mix in
        /// `BasisAugmentation.mixes` order (ASTSK-31 Phase 6, AC#4), consensus ranks
        /// over the whole pooled population. Pooled lift is
        /// `pooledAugmentedRhos[i] − pooledRhoConsensus`.
        public let pooledAugmentedRhos: [Double]
        /// Total cells fed into the pooled correlations (all oracles finite).
        public let includedCells: Int
        /// Total cells across the battery (finite + non-finite).
        public let totalCells: Int
        /// Cells dropped because residual or some oracle was non-finite.
        public var excludedCells: Int { totalCells - includedCells }
    }

    /// Pure analysis core: for each fixture in the battery, runs
    /// `convertWithResidual`, computes the three fixed-resolution pixel oracles
    /// per cell, and rank-correlates the residual against each oracle (per
    /// fixture + pooled). No file I/O.
    ///
    /// - Throws: `ShapeResidualError.converterWouldDownscale` if the converter
    ///   would thumbnail any fixture (the residual would then be computed on
    ///   downsampled pixels while the oracle reads native blocks — see
    ///   `noDownscaleOversample`); `.emptyBattery` if every fixture yields a
    ///   degenerate/empty grid.
    public static func analyze(
        columns: Int, fixtureSize: Int = defaultFixtureSize, allowUpsampledBlocks: Bool = false,
        battery: BatterySelection = .synthetic, corpusDirectory: String? = nil
    ) throws -> Analysis {
        // logPolar is the default algorithm; monochrome palette keeps colour out
        // of it. The residual map runs the real 60D shape distance. `oversample`
        // is raised so the matcher samples at >= native fixture resolution (no
        // downscale), keeping the residual pixel-aligned with the oracle's source
        // blocks. The headline oversample is for the synthetic side; each fixture
        // gets its OWN converter sized from its OWN native side, because a mixed
        // battery (`.all`) holds synthetic fixtures at `fixtureSize` AND natural
        // photos at their native 2048 — one oversample cannot serve both.
        let headlineOversample = noDownscaleOversample(columns: columns, fixtureSide: fixtureSize)

        var fixtureAnalyses: [FixtureAnalysis] = []
        // Per-pool paired vectors, accumulated and read in FixturePool.allCases order.
        var byPool: [FixturePool: PooledVectors] = [:]

        for fixture in try makeBattery(selection: battery, side: fixtureSize, corpusDirectory: corpusDirectory) {
            let fixtureOversample = noDownscaleOversample(
                columns: columns, fixtureSide: fixture.width, fixtureHeight: fixture.height)
            let converter = ASCIIConverter(
                characterSet: StandardCharacterSet.standard,
                palette: BuiltInPalette.monochrome,
                colorSpace: .sRGB,
                oversample: fixtureOversample
            )
            let (grid, residual) = converter.convertWithResidual(fixture.image, columns: columns)
            guard grid.rows > 0, grid.columns > 0 else { continue }
            // The sampling regime this verdict was measured at (ASKI-29 AC#2),
            // taken from the converter's own resolved geometry so it cannot drift
            // from what the matcher saw.
            let regime: (cellWidth: Int, cellHeight: Int, reachableBins: Int) = {
                guard let geometry = converter.samplingGeometry(fixture.image, columns: columns)
                else { return (0, 0, 0) }
                let census = LatticeSupport.census(
                    width: geometry.cellWidth, height: geometry.cellHeight)
                return (geometry.cellWidth, geometry.cellHeight, census.bins.count)
            }()
            guard residual.count == grid.rows * grid.columns else { continue }

            // No-downscale invariant (mirrors AskiDecolorLab): the residual is
            // computed on the converter's thumbnail while the oracle reads the
            // fixture's native blocks. They align only when the converter did
            // NOT thumbnail, i.e. max(cols,rows)·oversample >= the fixture's
            // longest side. `noDownscaleOversample` guarantees this for the
            // battery; this guard enforces it on the REAL grid as a backstop.
            let maxPixelSize = max(grid.columns, grid.rows) * converter.oversample
            let fixtureLongestSide = max(fixture.width, fixture.height)
            guard maxPixelSize >= fixtureLongestSide else {
                throw ShapeResidualError.converterWouldDownscale(
                    fixtureID: fixture.id,
                    maxPixelSize: maxPixelSize,
                    fixtureLongestSide: fixtureLongestSide
                )
            }

            // Oracle-native validity (ASTSK-31): every source-cell block must be ≥
            // the oracle footprint NATIVELY. Otherwise `LumaResample` UPSAMPLES a
            // sub-24px block into the 24×24 oracle and the oracle reads invented
            // pixels — scientifically invalid (ASTSK-27 applied this by hand reading
            // results; this enforces it). Complementary to, and separate from, the
            // matcher-side no-downscale guard above. The escape hatch
            // (`allowUpsampledBlocks`) is for explicitly EXPLORATORY runs only.
            if !allowUpsampledBlocks,
                oracleBlockWouldUpsample(
                    fixtureSide: fixture.width, gridRows: grid.rows, gridColumns: grid.columns,
                    fixtureHeight: fixture.height)
            {
                throw ShapeResidualError.oracleBlockWouldUpsample(
                    fixtureID: fixture.id,
                    blockWidth: fixture.width / grid.columns,
                    blockHeight: fixture.height / grid.rows,
                    oracleCellSize: oracleCellSize
                )
            }

            var rows: [ResidualRow] = []
            rows.reserveCapacity(grid.rows * grid.columns)
            var finiteMin = Float.greatestFiniteMagnitude
            var finiteMax = -Float.greatestFiniteMagnitude

            // This fixture's paired vectors for the per-fixture ρ.
            var fResidual: [Double] = []
            var fOneMinusFull: [Double] = []
            var fOneMinusStructure: [Double] = []
            var fGMSD: [Double] = []
            var fOneMinusHaar: [Double] = []
            // Basis-augmentation channels (ASTSK-31 Phase 6), aligned with fResidual.
            var fDOrient: [Double] = []
            var fDRadial: [Double] = []

            for row in 0..<grid.rows {
                for col in 0..<grid.columns {
                    let character = grid.cells[row][col].character
                    let cellResidual = residual[row * grid.columns + col]
                    if cellResidual.isFinite {
                        finiteMin = min(finiteMin, cellResidual)
                        finiteMax = max(finiteMax, cellResidual)
                    }

                    // Oracle inputs are PIXELS ONLY, at a FIXED resolution:
                    //   (a) the chosen glyph rasterized to oracleCellSize², and
                    //   (b) the fixture's own source block, RESAMPLED to the
                    //       same fixed size. Neither input is the residual /
                    //       shape distance / 60D vector.
                    let block = fixture.lumaBlock(
                        cellRow: row, cellCol: col, rows: grid.rows, cols: grid.columns
                    )
                    let source = LumaResample.resample(
                        block.luma,
                        srcWidth: block.width, srcHeight: block.height,
                        dstWidth: oracleCellSize, dstHeight: oracleCellSize
                    )
                    let glyph = GlyphRaster.luma(
                        character: character, width: oracleCellSize, height: oracleCellSize
                    )

                    let ssimFull = StructuralSimilarity.ssim(
                        glyph, source, width: oracleCellSize, height: oracleCellSize
                    )
                    let ssimStructure = StructuralSimilarity.structure(
                        glyph, source, width: oracleCellSize, height: oracleCellSize
                    )
                    let gmsd = GMSD.gmsd(
                        glyph, source, width: oracleCellSize, height: oracleCellSize
                    )
                    let haarpsi = HaarPSI.haarPSI(
                        glyph, source, width: oracleCellSize, height: oracleCellSize
                    )

                    // Basis-augmentation channels (ASTSK-31 Phase 6): per-cell
                    // distances between the chosen glyph's and the source block's
                    // orientation-energy and radial-frequency descriptors. Same
                    // PIXELS-ONLY inputs as the oracles; both share the residual's
                    // "higher = worse" axis.
                    let dOrient = BasisAugmentation.dOrient(
                        glyph: glyph, source: source, width: oracleCellSize, height: oracleCellSize)
                    let dRadial = BasisAugmentation.dRadial(
                        glyph: glyph, source: source, width: oracleCellSize, height: oracleCellSize)

                    rows.append(
                        ResidualRow(
                            fixtureID: fixture.id,
                            row: row,
                            col: col,
                            character: String(character),
                            residual: cellResidual,
                            ssimFull: ssimFull,
                            ssimStructure: Float(ssimStructure),
                            gmsd: Float(gmsd),
                            haarpsi: Float(haarpsi),
                            dOrient: Float(dOrient),
                            dRadial: Float(dRadial)
                        ))

                    // A cell enters the correlations only when the residual and
                    // ALL THREE oracles are finite — one paired set so the
                    // included-cell count is identical across the three ρ. The basis
                    // channels are always finite, so they ride the same mask.
                    if cellResidual.isFinite, ssimFull.isFinite,
                        ssimStructure.isFinite, gmsd.isFinite, haarpsi.isFinite
                    {
                        let r = Double(cellResidual)
                        fResidual.append(r)
                        fOneMinusFull.append(1 - Double(ssimFull))
                        fOneMinusStructure.append(1 - ssimStructure)
                        fGMSD.append(gmsd)
                        fOneMinusHaar.append(1 - haarpsi)
                        fDOrient.append(dOrient)
                        fDRadial.append(dRadial)
                    }
                }
            }

            var pv = byPool[fixture.pool] ?? PooledVectors()
            pv.residual.append(contentsOf: fResidual)
            pv.oneMinusFull.append(contentsOf: fOneMinusFull)
            pv.oneMinusStructure.append(contentsOf: fOneMinusStructure)
            pv.gmsd.append(contentsOf: fGMSD)
            pv.oneMinusHaar.append(contentsOf: fOneMinusHaar)
            pv.dOrient.append(contentsOf: fDOrient)
            pv.dRadial.append(contentsOf: fDRadial)
            pv.totalCells += rows.count
            byPool[fixture.pool] = pv

            // Population-relative consensus for THIS fixture, reused for both
            // ρ(residual, consensus) and the augmented-mix ρ so they share one
            // ranking population (AC#4 lift is augmented − baseline against it).
            let fConsensus = OracleConsensus.medianRank(
                gmsd: fGMSD, oneMinusStructure: fOneMinusStructure, oneMinusHaar: fOneMinusHaar)

            fixtureAnalyses.append(
                FixtureAnalysis(
                    id: fixture.id,
                    pool: fixture.pool,
                    rows: rows,
                    gridRows: grid.rows,
                    gridColumns: grid.columns,
                    residualField: residual,
                    finiteMin: finiteMin,
                    finiteMax: finiteMax,
                    rhoSSIMFull: Spearman.rho(fResidual, fOneMinusFull),
                    rhoSSIMStructure: Spearman.rho(fResidual, fOneMinusStructure),
                    rhoGMSD: Spearman.rho(fResidual, fGMSD),
                    rhoHaarPSI: Spearman.rho(fResidual, fOneMinusHaar),
                    rhoConsensus: Spearman.rho(fResidual, fConsensus),
                    augmentedRhos: BasisAugmentation.mixes.map {
                        BasisAugmentation.rho(
                            residual: fResidual, dOrient: fDOrient, dRadial: fDRadial,
                            consensus: fConsensus, w: $0)
                    },
                    includedCells: fResidual.count,
                    cellWidth: regime.cellWidth,
                    cellHeight: regime.cellHeight,
                    reachableBins: regime.reachableBins
                ))
        }

        guard !fixtureAnalyses.isEmpty else { throw ShapeResidualError.emptyBattery }

        // Per-pool stats (consensus ranks are population-relative — computed
        // within each pool) plus the grand pooled, concatenated in
        // FixturePool.allCases order. Spearman ρ is order-invariant over the
        // paired set, so the concatenation order does not change any ρ.
        var pools: [PoolStats] = []
        var grand = PooledVectors()
        for pool in FixturePool.allCases {
            guard let pv = byPool[pool] else { continue }
            let poolConsensus = OracleConsensus.medianRank(
                gmsd: pv.gmsd, oneMinusStructure: pv.oneMinusStructure, oneMinusHaar: pv.oneMinusHaar)
            pools.append(
                PoolStats(
                    pool: pool,
                    rhoSSIMFull: Spearman.rho(pv.residual, pv.oneMinusFull),
                    rhoSSIMStructure: Spearman.rho(pv.residual, pv.oneMinusStructure),
                    rhoGMSD: Spearman.rho(pv.residual, pv.gmsd),
                    rhoHaarPSI: Spearman.rho(pv.residual, pv.oneMinusHaar),
                    rhoConsensus: Spearman.rho(pv.residual, poolConsensus),
                    augmentedRhos: BasisAugmentation.mixes.map {
                        BasisAugmentation.rho(
                            residual: pv.residual, dOrient: pv.dOrient, dRadial: pv.dRadial,
                            consensus: poolConsensus, w: $0)
                    },
                    includedCells: pv.residual.count,
                    totalCells: pv.totalCells,
                    regime: sharedRegime(fixtureAnalyses.filter { $0.pool == pool })))
            grand.residual.append(contentsOf: pv.residual)
            grand.oneMinusFull.append(contentsOf: pv.oneMinusFull)
            grand.oneMinusStructure.append(contentsOf: pv.oneMinusStructure)
            grand.gmsd.append(contentsOf: pv.gmsd)
            grand.oneMinusHaar.append(contentsOf: pv.oneMinusHaar)
            grand.dOrient.append(contentsOf: pv.dOrient)
            grand.dRadial.append(contentsOf: pv.dRadial)
            grand.totalCells += pv.totalCells
        }

        let grandConsensus = OracleConsensus.medianRank(
            gmsd: grand.gmsd, oneMinusStructure: grand.oneMinusStructure,
            oneMinusHaar: grand.oneMinusHaar)

        return Analysis(
            fixtures: fixtureAnalyses,
            pools: pools,
            oversample: headlineOversample,
            pooledRhoSSIMFull: Spearman.rho(grand.residual, grand.oneMinusFull),
            pooledRhoSSIMStructure: Spearman.rho(grand.residual, grand.oneMinusStructure),
            pooledRhoGMSD: Spearman.rho(grand.residual, grand.gmsd),
            pooledRhoHaarPSI: Spearman.rho(grand.residual, grand.oneMinusHaar),
            pooledRhoConsensus: Spearman.rho(grand.residual, grandConsensus),
            pooledAugmentedRhos: BasisAugmentation.mixes.map {
                BasisAugmentation.rho(
                    residual: grand.residual, dOrient: grand.dOrient, dRadial: grand.dRadial,
                    consensus: grandConsensus, w: $0)
            },
            includedCells: grand.residual.count,
            totalCells: grand.totalCells
        )
    }

    /// One swept column count's analysis.
    public struct ColumnAnalysis: Sendable {
        public let columns: Int
        public let analysis: Analysis
    }

    /// Runs `analyze` once per column count, in the order given. Each column is an
    /// independent analysis (the verdict gates per-column), so this is a thin loop
    /// over the single-column core — no cross-column state.
    public static func sweep(
        columns: [Int], fixtureSize: Int = defaultFixtureSize, allowUpsampledBlocks: Bool = false,
        battery: BatterySelection = .synthetic, corpusDirectory: String? = nil
    ) throws -> [ColumnAnalysis] {
        var results: [ColumnAnalysis] = []
        results.reserveCapacity(columns.count)
        for c in columns {
            let analysis = try analyze(
                columns: c, fixtureSize: fixtureSize, allowUpsampledBlocks: allowUpsampledBlocks,
                battery: battery, corpusDirectory: corpusDirectory)
            results.append(ColumnAnalysis(columns: c, analysis: analysis))
        }
        return results
    }

    public static func run(
        arguments: ShapeResidualArguments,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void
    ) -> LabExitCode {
        guard !arguments.columns.isEmpty, arguments.columns.allSatisfy({ $0 > 0 }) else {
            standardError("error: --columns must be > 0 (one or more)\n")
            return .usage
        }
        guard arguments.fixtureSize >= oracleCellSize else {
            standardError("error: --fixture-size must be >= the \(oracleCellSize)px oracle footprint\n")
            return .usage
        }

        let outputDir = URL(fileURLWithPath: arguments.outputDirectory)
        let gitSHA = GitSHA.resolve(override: arguments.gitShaOverride)

        let results: [ColumnAnalysis]
        do {
            results = try sweep(
                columns: arguments.columns, fixtureSize: arguments.fixtureSize,
                allowUpsampledBlocks: arguments.allowUpsampledOracleBlocks,
                battery: arguments.battery, corpusDirectory: arguments.corpusDirectory)
        } catch {
            // Invariant/config failure (e.g. a downscale would mis-attribute
            // ImageIO resampling loss to glyph residual). Mirrors AskiDecolorLab.
            standardError("error: \(error)\n")
            return .failure
        }

        // The B5 readout, per swept column: per-fixture × 4-oracle Spearman table +
        // pooled row, then the AC#4 basis-augmentation lift readout.
        for ca in results {
            standardOutput("=== columns=\(ca.columns) ===\n")
            standardOutput(spearmanTable(ca.analysis))
            standardOutput(augmentationTable(ca.analysis))
        }

        // Per-cell CSV across the whole sweep, leading `columns` column.
        do {
            let writer = try CSVWriter(
                url: outputDir.appendingPathComponent(csvFileName),
                columns: csvHeader
            )
            defer { try? writer.close() }
            for ca in results {
                let columns = String(ca.columns)
                for fixture in ca.analysis.fixtures {
                    for r in fixture.rows {
                        try writer.writeRow([
                            columns,
                            r.fixtureID,
                            String(r.row),
                            String(r.col),
                            csvSafeCharacter(r.character),
                            formatFloat(r.residual),
                            formatFloat(r.ssimFull),
                            formatFloat(r.ssimStructure),
                            formatFloat(r.gmsd),
                            formatFloat(r.haarpsi),
                            formatFloat(r.dOrient),
                            formatFloat(r.dRadial),
                        ])
                    }
                }
            }
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        // The Spearman summary CSV — the SOLE source for every verdict-table number.
        do {
            let writer = try CSVWriter(
                url: outputDir.appendingPathComponent(summaryCsvFileName),
                columns: summaryCsvHeader
            )
            defer { try? writer.close() }
            for row in summaryRows(battery: arguments.battery, results: results) {
                try writer.writeRow(row)
            }
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        // Heatmaps at the canonical column only (80 if swept, else max), to keep the
        // results dir bounded; one PNG per fixture (battery order).
        let canonical = canonicalColumn(arguments.columns)
        let canonicalAnalysis =
            (results.first { $0.columns == canonical } ?? results[results.count - 1]).analysis
        do {
            for fixture in canonicalAnalysis.fixtures {
                let png = ResidualHeatmap.image(
                    residual: fixture.residualField,
                    rows: fixture.gridRows,
                    cols: fixture.gridColumns,
                    finiteMin: fixture.finiteMin,
                    finiteMax: fixture.finiteMax
                )
                try DemoImageIO.writePNG(
                    png,
                    to: outputDir.appendingPathComponent(heatmapFileName(for: fixture.id)).path
                )
            }
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        // Manifest. `outputs` = per-cell CSV + summary CSV + canonical-column heatmaps;
        // `datasets` references the committed corpus for natural-pool batteries.
        do {
            // An escape-hatch run is EXPLORATORY by definition; stamp the manifest
            // (summary + command) so an invalid, upsampled-block run can never
            // masquerade as the decisive run that feeds the pre-registered rule.
            let exploratoryStamp =
                "EXPLORATORY (--allow-upsampled-oracle-blocks: oracle blocks upsampled "
                + "below the \(oracleCellSize)px footprint — NOT a decisive run). "
            let summary =
                arguments.allowUpsampledOracleBlocks
                ? exploratoryStamp + summarySentence(canonicalAnalysis)
                : summarySentence(canonicalAnalysis)
            let columnsFlags = arguments.columns.map { "--columns \($0)" }.joined(separator: " ")
            let commandLine =
                "\(commandName) --output-dir \(arguments.outputDirectory) "
                + "\(columnsFlags) --fixture-size \(arguments.fixtureSize)"
                + " --battery \(arguments.battery.rawValue)"
                + (arguments.corpusDirectory.map { " --corpus-dir \($0)" } ?? "")
                + (arguments.allowUpsampledOracleBlocks ? " --allow-upsampled-oracle-blocks" : "")
            try ShapeResidualResults.writeManifest(
                outputDirectory: outputDir,
                date: ISO8601DateOnly.today(),
                gitSHA: gitSHA,
                command: commandLine,
                summary: summary,
                outputs: emittedOutputs(canonicalFixtureIDs: canonicalAnalysis.fixtures.map(\.id)),
                datasets: manifestDatasets(
                    battery: arguments.battery, corpusDirectory: arguments.corpusDirectory)
            )
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        return .success
    }

    /// Builds the `spearman_summary.csv` rows for a sweep: one row per (battery,
    /// pool/fixture, column, oracle), with included/excluded cell counts. `fixture`
    /// is `POOLED` for per-pool rows. This is the SOLE source for the verdict tables.
    static func summaryRows(battery: BatterySelection, results: [ColumnAnalysis]) -> [[String]] {
        var rows: [[String]] = []
        let batteryName = battery.rawValue
        for ca in results {
            let columns = String(ca.columns)
            for f in ca.analysis.fixtures {
                let excluded = f.rows.count - f.includedCells
                for (oracle, rho) in oracleScores(
                    ssimFull: f.rhoSSIMFull, ssimStructure: f.rhoSSIMStructure, gmsd: f.rhoGMSD,
                    haarpsi: f.rhoHaarPSI, consensus: f.rhoConsensus, augmented: f.augmentedRhos)
                {
                    rows.append(
                        [
                            batteryName, f.pool.rawValue, f.id, columns, oracle,
                            formatRhoCSV(rho), String(f.includedCells), String(excluded),
                        ]
                            + regimeColumns(
                                Regime(
                                    cellWidth: f.cellWidth, cellHeight: f.cellHeight,
                                    reachableBins: f.reachableBins)))
                }
            }
            for p in ca.analysis.pools {
                let excluded = p.totalCells - p.includedCells
                for (oracle, rho) in oracleScores(
                    ssimFull: p.rhoSSIMFull, ssimStructure: p.rhoSSIMStructure, gmsd: p.rhoGMSD,
                    haarpsi: p.rhoHaarPSI, consensus: p.rhoConsensus, augmented: p.augmentedRhos)
                {
                    rows.append(
                        [
                            batteryName, p.pool.rawValue, "POOLED", columns, oracle,
                            formatRhoCSV(rho), String(p.includedCells), String(excluded),
                        ] + regimeColumns(p.regime))
                }
            }
        }
        return rows
    }

    /// The three regime columns for one summary row; `mixed` when the row pools
    /// fixtures that resolved different footprints.
    private static func regimeColumns(_ regime: Regime?) -> [String] {
        guard let regime else { return ["mixed", "mixed", "mixed"] }
        return [
            String(regime.cellWidth), String(regime.cellHeight), String(regime.reachableBins),
        ]
    }

    /// The ordered (oracle-label, ρ) pairs for one population: the four oracles
    /// (ρ vs the residual, each oriented "higher = worse"), the consensus, then the
    /// three pre-registered augmentation mixes.
    private static func oracleScores(
        ssimFull: Double, ssimStructure: Double, gmsd: Double, haarpsi: Double,
        consensus: Double, augmented: [Double]
    ) -> [(String, Double)] {
        var pairs: [(String, Double)] = [
            ("ssim_full", ssimFull),
            ("ssim_structure", ssimStructure),
            ("gmsd", gmsd),
            ("haarpsi", haarpsi),
            ("consensus", consensus),
        ]
        for (w, score) in zip(BasisAugmentation.mixes, augmented) {
            pairs.append(("aug_w\(formatMix(w))", score))
        }
        return pairs
    }

    /// Formats ρ for the summary CSV to six decimals (more precision than the
    /// console table); `nan` rendered verbatim (defensive — `Spearman` returns 0).
    private static func formatRhoCSV(_ value: Double) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.6f", value)
    }

    // MARK: - Reporting helpers

    /// Renders the readable per-fixture × oracle ρ table plus a pooled row and
    /// included-cell counts. This is the controller's key deliverable.
    static func spearmanTable(_ analysis: Analysis) -> String {
        let idWidth = max(
            "fixture".count,
            analysis.fixtures.map { $0.id.count }.max() ?? 0,
            "POOLED".count
        )
        func pad(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
        }
        func col(_ s: String) -> String {
            let w = 16
            return s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
        }

        var out = "Spearman ρ(residual, oracle) — fixed \(oracleCellSize)×\(oracleCellSize) oracle, logPolar 60D residual\n"
        out +=
            pad("fixture", idWidth)
            + col("ρ(1−ssim_full)") + col("ρ(1−ssim_struct)") + col("ρ(gmsd)")
            + col("ρ(1−haarpsi)") + col("ρ(consensus)") + col("cells")
            + col("footprint") + col("bins/60") + "\n"
        for f in analysis.fixtures {
            out +=
                pad(f.id, idWidth)
                + col(formatRho(f.rhoSSIMFull))
                + col(formatRho(f.rhoSSIMStructure))
                + col(formatRho(f.rhoGMSD))
                + col(formatRho(f.rhoHaarPSI))
                + col(formatRho(f.rhoConsensus))
                + col(String(f.includedCells))
                // The regime this row was measured at (ASKI-29 AC#2). A verdict
                // read at 48 of 60 reachable bins does not transfer to a shipping
                // preset that reaches 2–3.
                + col("\(f.cellWidth)×\(f.cellHeight)")
                + col(String(f.reachableBins)) + "\n"
        }
        // The pooled row carries the regime too, or `mixed` when the battery
        // spanned more than one footprint — a short row under a wider header
        // reads as if the pooled ρ had no regime at all.
        let pooledRegime = sharedRegime(analysis.fixtures)
        out +=
            pad("POOLED", idWidth)
            + col(formatRho(analysis.pooledRhoSSIMFull))
            + col(formatRho(analysis.pooledRhoSSIMStructure))
            + col(formatRho(analysis.pooledRhoGMSD))
            + col(formatRho(analysis.pooledRhoHaarPSI))
            + col(formatRho(analysis.pooledRhoConsensus))
            + col(String(analysis.includedCells))
            + col(pooledRegime.map { "\($0.cellWidth)×\($0.cellHeight)" } ?? "mixed")
            + col(pooledRegime.map { String($0.reachableBins) } ?? "mixed") + "\n"
        return out
    }

    /// Renders the AC#4 basis-augmentation readout: the baseline ρ(residual,
    /// consensus) next to ρ(augmented_w, consensus) at each pre-registered mix, per
    /// fixture and pooled. The per-fixture lift (augmented − baseline) is the
    /// statistic the verdict's AC#4 criterion reads.
    static func augmentationTable(_ analysis: Analysis) -> String {
        let idWidth = max(
            "fixture".count,
            analysis.fixtures.map { $0.id.count }.max() ?? 0,
            "POOLED".count
        )
        func pad(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
        }
        func col(_ s: String) -> String {
            let w = 16
            return s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
        }

        var out =
            "\nAugmented residual ρ(·, consensus) — basis channels mixed in at fixed pre-registered w (AC#4 lift)\n"
        out += pad("fixture", idWidth) + col("ρ(residual)")
        for w in BasisAugmentation.mixes { out += col("ρ(aug w=\(formatMix(w)))") }
        out += "\n"
        for f in analysis.fixtures {
            out += pad(f.id, idWidth) + col(formatRho(f.rhoConsensus))
            for rho in f.augmentedRhos { out += col(formatRho(rho)) }
            out += "\n"
        }
        out += pad("POOLED", idWidth) + col(formatRho(analysis.pooledRhoConsensus))
        for rho in analysis.pooledAugmentedRhos { out += col(formatRho(rho)) }
        out += "\n"
        return out
    }

    /// Formats a pre-registered mix weight compactly (`0.25`, `0.5`, `0.75`).
    private static func formatMix(_ w: Double) -> String {
        var s = String(format: "%.2f", w)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func summarySentence(_ analysis: Analysis) -> String {
        let pooled =
            "pooled Spearman ρ(residual, ·) over \(analysis.includedCells)/\(analysis.totalCells) cells: "
            + "1−ssim_full=\(formatRho(analysis.pooledRhoSSIMFull)), "
            + "1−ssim_structure=\(formatRho(analysis.pooledRhoSSIMStructure)), "
            + "gmsd=\(formatRho(analysis.pooledRhoGMSD)), "
            + "1−haarpsi=\(formatRho(analysis.pooledRhoHaarPSI))"
        let ids = analysis.fixtures.map(\.id).joined(separator: ", ")
        return "AskiColorLab scored the per-cell logPolar shape residual against four independent "
            + "pixel-only oracles (full SSIM, SSIM structure term, GMSD, HaarPSI) at a fixed "
            + "\(oracleCellSize)×\(oracleCellSize) footprint over a \(analysis.fixtures.count)-fixture battery "
            + "(\(ids)); \(pooled)."
    }

    /// Formats Spearman ρ to four decimals; `nan` is rendered verbatim (it never
    /// should be, since `Spearman` returns 0 for degenerate input, but be defensive).
    private static func formatRho(_ value: Double) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%+.4f", value)
    }

    /// CSVWriter forbids commas/quotes/newlines. The chosen glyph could be any of
    /// those; map them to stable, non-forbidden tokens so the CSV stays a clean
    /// one-field-per-column grid that B5 can split on commas without quoting.
    private static func csvSafeCharacter(_ value: String) -> String {
        switch value {
        case ",": return "U+002C"
        case "\"": return "U+0022"
        case "\n": return "U+000A"
        case "\r": return "U+000D"
        case " ": return "U+0020"
        default: return value
        }
    }

    private static func formatFloat(_ value: Float) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.6f", value)
    }
}

/// A single CSV row. Value type, `Sendable`. Carries the three oracle scores.
public struct ResidualRow: Equatable, Sendable {
    public var fixtureID: String
    public var row: Int
    public var col: Int
    public var character: String
    public var residual: Float
    public var ssimFull: Float
    public var ssimStructure: Float
    public var gmsd: Float
    public var haarpsi: Float
    /// Basis-augmentation channels (ASTSK-31 Phase 6): per-cell distance between the
    /// chosen glyph's and source block's orientation-energy / radial-frequency
    /// descriptors. Always finite; both share the residual's "higher = worse" axis.
    public var dOrient: Float
    public var dRadial: Float

    public init(
        fixtureID: String,
        row: Int,
        col: Int,
        character: String,
        residual: Float,
        ssimFull: Float,
        ssimStructure: Float,
        gmsd: Float,
        haarpsi: Float,
        dOrient: Float,
        dRadial: Float
    ) {
        self.fixtureID = fixtureID
        self.row = row
        self.col = col
        self.character = character
        self.residual = residual
        self.ssimFull = ssimFull
        self.ssimStructure = ssimStructure
        self.gmsd = gmsd
        self.haarpsi = haarpsi
        self.dOrient = dOrient
        self.dRadial = dRadial
    }
}

/// Errors from the shape-residual analysis core. Mirrors
/// `DecolorFixtureError`: a configuration/invariant failure, not an I/O error.
public enum ShapeResidualError: Error, CustomStringConvertible {
    /// Every fixture in the battery produced a degenerate/empty grid.
    case emptyBattery
    /// The converter would thumbnail (downscale) the fixture before the residual
    /// is computed, breaking residual↔oracle pixel alignment.
    case converterWouldDownscale(fixtureID: String, maxPixelSize: Int, fixtureLongestSide: Int)
    /// A source-cell block is smaller than the oracle footprint natively, so the
    /// oracle would read upsampled (invented) pixels — an invalid, non-native run.
    case oracleBlockWouldUpsample(
        fixtureID: String, blockWidth: Int, blockHeight: Int, oracleCellSize: Int)
    /// A natural-pool corpus asset (or its directory) could not be read, so a
    /// `--battery real|all` run cannot form the natural pool.
    case corpusAssetUnreadable(path: String)
    /// One or more inter-cell-smoothing fixtures produced a degenerate grid and
    /// could not be scored. Dropping them silently can empty a whole pool, whose
    /// all-NaN pooled metrics slip past `InterCellGate`'s washout checks, so a
    /// partial battery must fail loud instead of yielding a one-pool verdict.
    case interCellFixtureUnscored(fixtureIDs: [String], columns: Int)

    public var description: String {
        switch self {
        case .emptyBattery:
            return "shape-residual battery produced an empty or malformed grid for every fixture"
        case let .converterWouldDownscale(fixtureID, maxPixelSize, fixtureLongestSide):
            return """
                fixture \(fixtureID): converter would downscale (maxPixelSize \(maxPixelSize) \
                < longest side \(fixtureLongestSide)). The shape residual must be computed on the \
                same pixels the oracle reads (fixture.lumaBlock native blocks), so the converter \
                must not thumbnail the fixture. Raise --columns or oversample (or shrink the \
                fixture) so max(cols,rows)*oversample >= the fixture's longest side.
                """
        case let .oracleBlockWouldUpsample(fixtureID, blockWidth, blockHeight, oracleCellSize):
            return """
                fixture \(fixtureID): source-cell block \(blockWidth)×\(blockHeight)px is smaller \
                than the \(oracleCellSize)px oracle footprint, so the oracle would read UPSAMPLED \
                (invented) pixels — an invalid, non-native run. Raise --fixture-size (e.g. 2048) or \
                lower --columns so every source block is >= \(oracleCellSize)px native, or pass \
                --allow-upsampled-oracle-blocks for an explicitly EXPLORATORY (non-decisive) run.
                """
        case let .corpusAssetUnreadable(path):
            return """
                could not read natural-pool corpus asset '\(path)'. A --battery real|all run needs \
                the nasa-structure-v1 corpus (PNGs under docs/Research/Corpus/nasa-structure-v1/assets); \
                pass --corpus-dir to point at an explicit assets directory.
                """
        case let .interCellFixtureUnscored(fixtureIDs, columns):
            return """
                inter-cell-smoothing screen could not score \(fixtureIDs.count) fixture(s) at \
                --columns \(columns): \(fixtureIDs.joined(separator: ", ")). Silently dropping a \
                fixture can empty a whole pool, whose all-NaN pooled means slip past the gate's \
                washout checks and yield a verdict from the surviving pool alone. Fix the --corpus \
                or lower --columns so every fixture scores, then re-run.
                """
        }
    }
}
