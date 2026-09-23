import Dispatch

/// Threshold-gated parallel row walk for the per-cell conversion loops (ASTSK-51,
/// audit finding #1). `logPolar` cells are fully independent, so rows can be
/// scored on multiple cores; `dotMatrix` diffuses Floyd–Steinberg error in
/// cell order and must always resolve `.forcedSerial` (callers enforce this).
///
/// Bounded concurrency (AC#6): `concurrentPerform` runs at most one GCD worker
/// per core and the calling thread participates — no unbounded task creation,
/// and no nesting: the video/animation frame loop stays serial per frame.
package enum GridRowWalk {
    package enum Mode: Sendable, Equatable {
        /// Threshold-gated: parallel iff rows > 1 && rows * columns >= threshold.
        case auto
        /// Serial walk. Required for dotMatrix; used by parity tests.
        case forcedSerial
        /// Parallel walk regardless of grid size. Tests and benchmarks only.
        case forcedParallel
    }

    /// Minimum cell count (`rows * columns`) before parallel dispatch pays for
    /// itself. Measured crossover (ASTSK-51 Task 6, 10 P-core + 4 E-core Apple
    /// Silicon, 2026-07-10): across 5 alternating `crossover-*` benchmark runs,
    /// parallel loses/neutral at ≤520 cells (0.98–1.03× serial) and wins with a
    /// consistent ≥10% p50 margin (non-inverting p90) from 1344 cells up
    /// (64-col landscape 1.14×, 76-col portrait 1.33×, 120-col 1.38×). 1200 is a
    /// conservative round-up: above the neutral zone and the single marginal
    /// sub-1000 win (960 cells / 1.12×, cheap to leave serial), below the first
    /// solid win — so every decisive win and the product's 76-col portrait hot
    /// path (ASTSK-47, 3496 cells) parallelize while small grids and the ASTSK-40
    /// video sentinels (~80 cells) stay serial. Single-machine measurement; iOS
    /// crossover is unvalidated and the conservative rounding is the mitigation.
    /// Full matrix + protocol recorded in the private development archive.
    package static let parallelCellThreshold = 1200

    /// Pure gate — split out so tests and benchmarks can prove both sides of
    /// the threshold without touching dispatch. `threshold` is injectable for
    /// tests; production callers use the default.
    package static func resolvesParallel(
        rows: Int,
        columns: Int,
        mode: Mode,
        threshold: Int = parallelCellThreshold
    ) -> Bool {
        switch mode {
        case .forcedSerial: return false
        case .forcedParallel: return rows > 1
        case .auto: return rows > 1 && rows * columns >= threshold
        }
    }

    package static func forEachRow(
        rows: Int,
        columns: Int,
        mode: Mode,
        threshold: Int = parallelCellThreshold,
        _ body: @Sendable (Int) -> Void
    ) {
        guard rows > 0 else { return }
        if resolvesParallel(rows: rows, columns: columns, mode: mode, threshold: threshold) {
            DispatchQueue.concurrentPerform(iterations: rows, execute: body)
        } else {
            for row in 0..<rows { body(row) }
        }
    }
}
