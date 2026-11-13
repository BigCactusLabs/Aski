import Aski
import Dispatch
import Foundation
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// Diagnostic only: timed histogram batches, including one map preparation per
/// batch. Not an Aski conversion benchmark, allocation profile, or adoption gate.
@main
private enum ShapeContextTiming {
    static func main() throws {
        let arguments = CommandLine.arguments.dropFirst()
        guard arguments.count <= 1,
            let passes = Int(arguments.first ?? "5"), (5...20).contains(passes)
        else {
            throw NSError(domain: "ShapeContextTiming: expected 5...20 passes", code: 64)
        }
        print("pass,order,width,height,cells_per_batch,batches,field,arm,wall_ns,cpu_seconds,checksum")
        for (width, height) in [(2, 3), (3, 3), (8, 12), (16, 24)] {
            for cells in [1, 32, 2400] {
                let batches = max(8, 24_000 / cells)
                for field in ["mixed", "zero"] {
                    var state: UInt64 = 0x87
                    let inputs = (0..<17).map { _ in
                        (0..<(width * height)).map { _ -> Float in
                            state = state &* 6_364_136_223_846_793_005 &+ 1
                            return field == "zero" ? 0 : Float((state >> 32) & 0xffff) / 65535
                        }
                    }
                    // Untimed warmup; all timed map preparations still occur in
                    // runPrepared, not here or in retained process-wide state.
                    let warmScalar = runScalar(inputs, width: width, height: height, cells: cells, batches: 1)
                    let warmPrepared = runPrepared(inputs, width: width, height: height, cells: cells, batches: 1)
                    precondition(warmScalar == warmPrepared, "Control/candidate checksum mismatch")
                    for pass in 0..<passes {
                        var checksums: [UInt64] = []
                        let order = pass.isMultiple(of: 2) ? [false, true] : [true, false]
                        for (position, prepared) in order.enumerated() {
                            let cpuStart = clock()
                            let wallStart = DispatchTime.now().uptimeNanoseconds
                            let checksum =
                                prepared
                                ? runPrepared(inputs, width: width, height: height, cells: cells, batches: batches)
                                : runScalar(inputs, width: width, height: height, cells: cells, batches: batches)
                            let wallNS = DispatchTime.now().uptimeNanoseconds - wallStart
                            let cpuSeconds = Double(clock() - cpuStart) / Double(CLOCKS_PER_SEC)
                            let arm = prepared ? "prepared" : "scalar"
                            print("\(pass + 1),\(position + 1),\(width),\(height),\(cells),\(batches),\(field),\(arm),\(wallNS),\(cpuSeconds),\(checksum)")
                            checksums.append(checksum)
                        }
                        precondition(checksums[0] == checksums[1], "Control/candidate checksum mismatch")
                    }
                }
            }
        }
    }

    @inline(never)
    private static func runScalar(_ inputs: [[Float]], width: Int, height: Int, cells: Int, batches: Int) -> UInt64 {
        var checksum: UInt64 = 0
        for batch in 0..<batches {
            for cell in 0..<cells {
                let histogram = ShapeContext.histogram60(inputs[(cell + batch) % inputs.count], width: width, height: height)
                checksum &+= UInt64(histogram[(cell + batch) % ShapeContext.dimension].bitPattern)
            }
        }
        return checksum
    }

    @inline(never)
    private static func runPrepared(_ inputs: [[Float]], width: Int, height: Int, cells: Int, batches: Int) -> UInt64 {
        var checksum: UInt64 = 0
        for batch in 0..<batches {
            let footprint = ShapeContext.Footprint(width: width, height: height)
            for cell in 0..<cells {
                let histogram = footprint.histogram60(inputs[(cell + batch) % inputs.count])
                checksum &+= UInt64(histogram[(cell + batch) % ShapeContext.dimension].bitPattern)
            }
        }
        return checksum
    }
}
