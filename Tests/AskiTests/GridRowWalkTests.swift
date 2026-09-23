import Synchronization
import Testing
@testable import Aski

struct GridRowWalkTests {
    @Test(arguments: [GridRowWalk.Mode.forcedSerial, .forcedParallel, .auto])
    func visitsEveryRowExactlyOnce(mode: GridRowWalk.Mode) {
        let rows = 37
        let counts = Mutex([Int](repeating: 0, count: rows))
        // threshold: 1 makes .auto resolve parallel too — all three modes get
        // exercised through their real dispatch path.
        GridRowWalk.forEachRow(rows: rows, columns: 80, mode: mode, threshold: 1) { row in
            counts.withLock { $0[row] += 1 }
        }
        #expect(counts.withLock { $0 } == [Int](repeating: 1, count: rows))
    }

    @Test func zeroAndSingleRowDegenerate() {
        GridRowWalk.forEachRow(rows: 0, columns: 80, mode: .forcedParallel) { _ in
            Issue.record("body must not run for zero rows")
        }
        let visited = Mutex(0)
        GridRowWalk.forEachRow(rows: 1, columns: 80, mode: .forcedParallel) { _ in
            visited.withLock { $0 += 1 }
        }
        #expect(visited.withLock { $0 } == 1)
    }

    @Test func autoGateRespectsThreshold() {
        // Pure gate function — both sides of the threshold are provable without
        // touching dispatch. rows*cols = 20 in the first two cases.
        #expect(!GridRowWalk.resolvesParallel(rows: 5, columns: 4, mode: .auto, threshold: 21))
        #expect(GridRowWalk.resolvesParallel(rows: 5, columns: 4, mode: .auto, threshold: 20))
        #expect(!GridRowWalk.resolvesParallel(rows: 1, columns: 1000, mode: .auto, threshold: 10))
        #expect(!GridRowWalk.resolvesParallel(rows: 10, columns: 10, mode: .forcedSerial, threshold: 1))
        #expect(GridRowWalk.resolvesParallel(rows: 2, columns: 1, mode: .forcedParallel, threshold: .max))
    }
}
