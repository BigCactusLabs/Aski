@_spi(AskiResearch) import Aski
import AskiToolSupport
import Foundation

/// Runs the ASTSK-41 temporal-prior gate over deterministic synthetic motion.
public enum TemporalPriorExperiment {
    /// Composite footprint per cell for the source-fidelity oracle.
    public static let cellPx = 24
    /// Per-cell pixel budget for conversion.
    public static let oversample = 8

    static func converter() -> DefaultConverter {
        ASCIIConverter(
            characterSet: .standard,
            palette: .fullColor,
            colorSpace: .sRGB,
            oversample: oversample
        )
    }

    /// Composite one converted frame's chosen glyphs into luma at the oracle footprint.
    public static func compositeLuma(grid: ASCIIGrid) -> (pixels: [Float], w: Int, h: Int)? {
        var rasterCache: [Character: [Float]] = [:]
        return compositeLuma(grid: grid, rasterCache: &rasterCache)
    }

    private static func compositeLuma(
        grid: ASCIIGrid,
        rasterCache: inout [Character: [Float]]
    ) -> (pixels: [Float], w: Int, h: Int)? {
        guard grid.rows > 0, grid.columns > 0 else { return nil }

        let characters = grid.cells.map { $0.map(\.character) }
        let (pixels, width, height) = GridComposite.compose(characters: characters, cellPx: cellPx) {
            if let cached = rasterCache[$0] {
                return cached
            }
            let raster = GlyphRaster.luma(character: $0, width: cellPx, height: cellPx)
            rasterCache[$0] = raster
            return raster
        }
        guard width > 0, height > 0 else { return nil }
        return (pixels, width, height)
    }

    /// One stimulus/column cell: per-frame baseline plus the full alpha/tau grid.
    public static func measureCell(stimulus: TemporalStimulus, columns: Int) -> GateCell {
        let conv = converter()
        let frameCount = SyntheticMotion.frameCount
        let inputs = (0..<frameCount).map { SyntheticMotion.inputImage(stimulus, frame: $0) }
        var rasterCache: [Character: [Float]] = [:]

        var baselineGrids: [ASCIIGrid] = []
        var baselineComposites = Array<(pixels: [Float], w: Int, h: Int)?>(repeating: nil, count: frameCount)
        var sourceLuma = Array<(pixels: [Float], w: Int, h: Int)?>(repeating: nil, count: frameCount)
        var baselineGMSD: [Double] = []
        var baselineHaarPSI: [Double] = []
        baselineGrids.reserveCapacity(frameCount)
        baselineGMSD.reserveCapacity(frameCount)
        baselineHaarPSI.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            let grid = conv.convert(inputs[frame], columns: columns)
            baselineGrids.append(grid)

            guard let composite = compositeLuma(grid: grid, rasterCache: &rasterCache) else { continue }
            baselineComposites[frame] = composite
            let source = SyntheticMotion.groundTruthLuma(
                stimulus,
                frame: frame,
                width: composite.w,
                height: composite.h
            )
            sourceLuma[frame] = (source, composite.w, composite.h)
            baselineGMSD.append(GMSD.gmsd(composite.pixels, source, width: composite.w, height: composite.h))
            baselineHaarPSI.append(HaarPSI.haarPSI(composite.pixels, source, width: composite.w, height: composite.h))
        }

        let baselineFlicker = FlickerMetrics.compute(frames: baselineGrids)
        let baseline = CellMeasurement(
            alpha: 1,
            tau: 0,
            meanGlyphChurn: baselineFlicker.meanGlyphChurn,
            meanAlphaChurn: baselineFlicker.meanAlphaChurn,
            gmsd: mean(baselineGMSD),
            haarpsi: mean(baselineHaarPSI),
            perFrameGMSD: baselineGMSD,
            meanDriftVsBaseline: .nan
        )

        var points: [CellMeasurement] = []
        points.reserveCapacity(TemporalGate.alphaGrid.count * TemporalGate.tauGrid.count)

        for alpha in TemporalGate.alphaGrid {
            for tau in TemporalGate.tauGrid {
                var grids: [ASCIIGrid] = []
                var perFrameGMSD: [Double] = []
                var perFrameHaarPSI: [Double] = []
                var drifts: [Double] = []
                var state: TemporalPriorState?
                grids.reserveCapacity(frameCount)
                perFrameGMSD.reserveCapacity(frameCount)
                perFrameHaarPSI.reserveCapacity(frameCount)
                drifts.reserveCapacity(frameCount)

                for frame in 0..<frameCount {
                    let (grid, nextState) = conv.convertTemporalFrame(
                        inputs[frame],
                        columns: columns,
                        prior: state,
                        alpha: alpha,
                        tau: tau
                    )
                    state = nextState
                    grids.append(grid)

                    guard let composite = compositeLuma(grid: grid, rasterCache: &rasterCache) else { continue }
                    let source =
                        if let cached = sourceLuma[frame], cached.w == composite.w, cached.h == composite.h {
                            cached.pixels
                        } else {
                            SyntheticMotion.groundTruthLuma(
                                stimulus,
                                frame: frame,
                                width: composite.w,
                                height: composite.h
                            )
                        }
                    perFrameGMSD.append(GMSD.gmsd(composite.pixels, source, width: composite.w, height: composite.h))
                    perFrameHaarPSI.append(HaarPSI.haarPSI(composite.pixels, source, width: composite.w, height: composite.h))

                    if let baselineComposite = baselineComposites[frame] {
                        if baselineComposite.w == composite.w, baselineComposite.h == composite.h {
                            drifts.append(
                                GMSD.gmsd(
                                    composite.pixels,
                                    baselineComposite.pixels,
                                    width: composite.w,
                                    height: composite.h
                                ))
                        }
                    }
                }

                let flicker = FlickerMetrics.compute(frames: grids)
                points.append(
                    CellMeasurement(
                        alpha: alpha,
                        tau: tau,
                        meanGlyphChurn: flicker.meanGlyphChurn,
                        meanAlphaChurn: flicker.meanAlphaChurn,
                        gmsd: mean(perFrameGMSD),
                        haarpsi: mean(perFrameHaarPSI),
                        perFrameGMSD: perFrameGMSD,
                        meanDriftVsBaseline: mean(drifts)
                    ))
            }
        }

        return GateCell(stimulus: stimulus, columns: columns, baseline: baseline, points: points)
    }

    /// Run selected cells. Only the exact four-cell grid invokes the frozen gate.
    public static func run(
        stimuli: [TemporalStimulus],
        columns: [Int]
    ) -> (cells: [GateCell], verdict: TemporalVerdict?, sharedPoint: (alpha: Float, tau: Float)?) {
        var cells: [GateCell] = []
        cells.reserveCapacity(stimuli.count * columns.count)

        for stimulus in stimuli {
            for column in columns {
                cells.append(measureCell(stimulus: stimulus, columns: column))
            }
        }

        let isDecisive =
            Set(stimuli) == Set(TemporalStimulus.allCases)
            && Set(columns) == Set([64, 80])
            && stimuli.count == TemporalStimulus.allCases.count
            && columns.count == 2
        guard isDecisive else { return (cells, nil, nil) }

        let decision = TemporalGate.decide(cells: cells)
        return (cells, decision.verdict, decision.sharedPoint)
    }

    /// Human-readable gate table for stdout and `temporal-prior-report.txt`.
    public static func format(
        cells: [GateCell],
        verdict: TemporalVerdict?,
        sharedPoint: (alpha: Float, tau: Float)?
    ) -> String {
        func rounded(_ value: Double) -> String {
            value.isFinite ? String(format: "%.4f", value) : "nan"
        }

        var out =
            "ASTSK-41 temporal-prior gate -- cellPx=\(cellPx), oversample=\(oversample), N=\(SyntheticMotion.frameCount)\n"
        if let sharedPoint {
            out += "shared_pass_point = (alpha=\(sharedPoint.alpha), tau=\(sharedPoint.tau))\n"
        }

        for cell in cells {
            out +=
                "\n[\(cell.stimulus.rawValue) / cols=\(cell.columns)] baseline churn=\(rounded(cell.baseline.meanGlyphChurn)) alphachurn=\(rounded(cell.baseline.meanAlphaChurn)) GMSD=\(rounded(cell.baseline.gmsd)) HaarPSI=\(rounded(cell.baseline.haarpsi))\n"
            for point in cell.points {
                let qualified = TemporalGate.qualifies(point, baseline: cell.baseline) ? "  pass" : ""
                out +=
                    "  alpha=\(point.alpha) tau=\(point.tau)  churn=\(rounded(point.meanGlyphChurn)) alphachurn=\(rounded(point.meanAlphaChurn)) GMSD=\(rounded(point.gmsd)) HaarPSI=\(rounded(point.haarpsi)) drift=\(rounded(point.meanDriftVsBaseline))\(qualified)\n"
            }
        }

        switch verdict {
        case .pass(let alpha, let tau)?:
            out += "\nVERDICT: PASS (alpha*=\(alpha), tau*=\(tau))\n"
        case .kill(let reason)?:
            out += "\nVERDICT: KILL -- \(reason)\n"
        case .rerun(let reason)?:
            out += "\nVERDICT: RERUN (instrument) -- \(reason)\n"
        case nil:
            out += "\nVERDICT: (diagnostic only -- full four-cell grid not run)\n"
        }

        if let sharedPoint {
            out += "\nWorst per-frame GMSD regression at shared point (T-B, by frame):\n"
            for cell in cells {
                guard
                    let point = cell.points.first(where: {
                        $0.alpha == sharedPoint.alpha && $0.tau == sharedPoint.tau
                    })
                else {
                    continue
                }

                var worst = -Double.infinity
                var worstFrame = -1
                for frame in 0..<min(point.perFrameGMSD.count, cell.baseline.perFrameGMSD.count) {
                    let delta = point.perFrameGMSD[frame] - cell.baseline.perFrameGMSD[frame]
                    if delta > worst {
                        worst = delta
                        worstFrame = frame
                    }
                }

                if worstFrame >= 0 {
                    out +=
                        "  [\(cell.stimulus.rawValue)/cols=\(cell.columns)] frame \(worstFrame): deltaGMSD=\(rounded(worst))\n"
                }
            }
        }

        return out
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? .nan : values.reduce(0, +) / Double(values.count)
    }
}
