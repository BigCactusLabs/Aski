import Foundation
@_spi(AskiResearch) import Aski
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

// Diagnostic shortlist timing only; not package-benchmark or allocation/RSS.
@inline(never)
func evaluate(_ arm: Int, query: Float, values: [Float], limit: Int) -> [Int] {
    switch arm {
    case 0: return ShapeMatching.poolIndices(queryBrightness: query, candidateBrightness: values, topK: limit)
    case 1: return PoolSelectionArms.insertion(query: query, values: values, limit: limit)
    default: return PoolSelectionArms.heap(query: query, values: values, limit: limit)
    }
}

func measure(_ arm: Int, values: [Float], limit: Int, queries: [Float], iterations: Int) -> (UInt64, Double, UInt64) {
    var checksum: UInt64 = 0
    let cpuStart = clock()
    let start = DispatchTime.now().uptimeNanoseconds
    for iteration in 0..<iterations {
        let indices = evaluate(arm, query: queries[iteration % queries.count], values: values, limit: limit)
        // Every output position affects the observable checksum; never time an
        // unused pure result. Hash work is identical for equal outputs.
        for index in indices { checksum = checksum &* 31 &+ UInt64(index + 1) }
    }
    let wall = DispatchTime.now().uptimeNanoseconds - start
    let cpu = Double(clock() - cpuStart) * 1_000_000_000 / Double(CLOCKS_PER_SEC)
    return (wall, cpu, checksum)
}

let passes = Int(CommandLine.arguments[1])!
let iterations = Int(CommandLine.arguments[2])!
let names = ["full-sort", "insertion", "heap"]
var state: UInt64 = 88
let queries: [Float] = (0..<127).map { _ in
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Float((state >> 32) % 1025) / 1024
}
print("pass,order,n,k,distribution,arm,wall_ns,cpu_ns,checksum,queries")
for pass in 0..<passes {
    for count in [8, 95, 256] {
        var generator = UInt64(count)
        let shuffled: [Float] = (0..<count).map { _ in
            generator = generator &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float((generator >> 32) % 129) / 128
        }
        let fixtures: [(String, [Float])] = [
            ("shuffled", shuffled), ("ascending", shuffled.sorted()),
            ("descending", shuffled.sorted(by: >)), ("equal", Array(repeating: 0.5, count: count)),
        ]
        for (distribution, values) in fixtures {
            for limit in [1, 12, 24, 36, count, count + 1] {
                // Rotate first arm; reverse each alternate pass. Retain order.
                let rotation = pass % 3
                var order = (0..<3).map { ($0 + rotation) % 3 }
                if pass % 2 == 1 { order.reverse() }
                var expected: UInt64?
                for (position, arm) in order.enumerated() {
                    _ = measure(arm, values: values, limit: limit, queries: queries, iterations: 32)
                    let (wall, cpu, checksum) = measure(arm, values: values, limit: limit, queries: queries, iterations: iterations)
                    if let expected { precondition(checksum == expected, "timed arms disagree") } else { expected = checksum }
                    print("\(pass + 1),\(position + 1),\(count),\(limit),\(distribution),\(names[arm]),\(wall),\(cpu),\(checksum),\(iterations)")
                }
            }
        }
    }
}
