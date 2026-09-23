@_spi(AskiResearch) import Aski
import AskiToolSupport
import Foundation

/// Runs the ASTSK-45 source-tether gate over the same deterministic synthetic motion and
/// instrument as ASTSK-41 (spec §2, inherited wholesale), sweeping the frozen rho grid at
/// α=1 (EMA off) instead of the α×τ grid. Self-contained fork of `TemporalPriorExperiment`;
/// converter config, footprint, oracles, and stimuli are identical so the per-frame-independent
/// baseline matches the ASTSK-41 baseline.
public enum SourceTetherExperiment {
    /// Composite footprint per cell for the source-fidelity oracle (matches ASTSK-41).
    public static let cellPx = 24
    /// Per-cell pixel budget for conversion (matches ASTSK-41).
    public static let oversample = 8

    static func converter() -> DefaultConverter {
        ASCIIConverter(
            characterSet: .standard,
            palette: .fullColor,
            colorSpace: .sRGB,
            oversample: oversample
        )
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

    /// One stimulus/column cell: the per-frame-independent baseline plus the full rho grid.
    public static func measureCell(stimulus: TemporalStimulus, columns: Int) -> SourceTetherCell {
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
                stimulus, frame: frame, width: composite.w, height: composite.h)
            sourceLuma[frame] = (source, composite.w, composite.h)
            baselineGMSD.append(GMSD.gmsd(composite.pixels, source, width: composite.w, height: composite.h))
            baselineHaarPSI.append(HaarPSI.haarPSI(composite.pixels, source, width: composite.w, height: composite.h))
        }

        let baselineFlicker = FlickerMetrics.compute(frames: baselineGrids)
        let baseline = SourceTetherMeasurement(
            rho: SourceTetherGate.baselineRho,
            meanGlyphChurn: baselineFlicker.meanGlyphChurn,
            meanAlphaChurn: baselineFlicker.meanAlphaChurn,
            gmsd: mean(baselineGMSD),
            haarpsi: mean(baselineHaarPSI),
            perFrameGMSD: baselineGMSD,
            meanDriftVsBaseline: .nan
        )

        var points: [SourceTetherMeasurement] = []
        points.reserveCapacity(SourceTetherGate.rhoGrid.count)

        for rho in SourceTetherGate.rhoGrid {
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
                    alpha: 1,
                    tau: 0,
                    sourceTetherRho: rho
                )
                state = nextState
                grids.append(grid)

                guard let composite = compositeLuma(grid: grid, rasterCache: &rasterCache) else { continue }
                let source =
                    if let cached = sourceLuma[frame], cached.w == composite.w, cached.h == composite.h {
                        cached.pixels
                    } else {
                        SyntheticMotion.groundTruthLuma(
                            stimulus, frame: frame, width: composite.w, height: composite.h)
                    }
                perFrameGMSD.append(GMSD.gmsd(composite.pixels, source, width: composite.w, height: composite.h))
                perFrameHaarPSI.append(HaarPSI.haarPSI(composite.pixels, source, width: composite.w, height: composite.h))

                if let baselineComposite = baselineComposites[frame] {
                    if baselineComposite.w == composite.w, baselineComposite.h == composite.h {
                        drifts.append(
                            GMSD.gmsd(
                                composite.pixels, baselineComposite.pixels,
                                width: composite.w, height: composite.h))
                    }
                }
            }

            let flicker = FlickerMetrics.compute(frames: grids)
            points.append(
                SourceTetherMeasurement(
                    rho: rho,
                    meanGlyphChurn: flicker.meanGlyphChurn,
                    meanAlphaChurn: flicker.meanAlphaChurn,
                    gmsd: mean(perFrameGMSD),
                    haarpsi: mean(perFrameHaarPSI),
                    perFrameGMSD: perFrameGMSD,
                    meanDriftVsBaseline: mean(drifts)
                ))
        }

        return SourceTetherCell(stimulus: stimulus, columns: columns, baseline: baseline, points: points)
    }

    /// Run selected cells. Only the exact four-cell grid invokes the frozen gate.
    public static func run(
        stimuli: [TemporalStimulus],
        columns: [Int]
    ) -> (cells: [SourceTetherCell], verdict: SourceTetherVerdict?, sharedRho: Float?) {
        var cells: [SourceTetherCell] = []
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

        let decision = SourceTetherGate.decide(cells: cells)
        return (cells, decision.verdict, decision.sharedRho)
    }

    /// Human-readable gate table for stdout and `source-tether-report.txt`.
    public static func format(
        cells: [SourceTetherCell],
        verdict: SourceTetherVerdict?,
        sharedRho: Float?
    ) -> String {
        func rounded(_ value: Double) -> String {
            value.isFinite ? String(format: "%.4f", value) : "nan"
        }

        var out =
            "ASTSK-45 source-tether gate -- cellPx=\(cellPx), oversample=\(oversample), N=\(SyntheticMotion.frameCount), alpha=1 (EMA off)\n"
        if let sharedRho {
            out += "shared_pass_point = (rho=\(sharedRho))\n"
        }

        for cell in cells {
            out +=
                "\n[\(cell.stimulus.rawValue) / cols=\(cell.columns)] baseline churn=\(rounded(cell.baseline.meanGlyphChurn)) alphachurn=\(rounded(cell.baseline.meanAlphaChurn)) GMSD=\(rounded(cell.baseline.gmsd)) HaarPSI=\(rounded(cell.baseline.haarpsi))\n"
            for point in cell.points {
                let qualified = SourceTetherGate.qualifies(point, baseline: cell.baseline) ? "  pass" : ""
                out +=
                    "  rho=\(point.rho)  churn=\(rounded(point.meanGlyphChurn)) alphachurn=\(rounded(point.meanAlphaChurn)) GMSD=\(rounded(point.gmsd)) HaarPSI=\(rounded(point.haarpsi)) drift=\(rounded(point.meanDriftVsBaseline))\(qualified)\n"
            }
        }

        switch verdict {
        case .pass(let rho)?:
            out += "\nVERDICT: PASS (rho*=\(rho))\n"
        case .kill(let reason)?:
            out += "\nVERDICT: KILL -- \(reason)\n"
        case .rerun(let reason)?:
            out += "\nVERDICT: RERUN (instrument) -- \(reason)\n"
        case nil:
            out += "\nVERDICT: (diagnostic only -- full four-cell grid not run)\n"
        }

        if let sharedRho {
            out += "\nWorst per-frame GMSD regression at shared point (T-B, by frame):\n"
            for cell in cells {
                guard let point = cell.points.first(where: { $0.rho == sharedRho }) else { continue }

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
