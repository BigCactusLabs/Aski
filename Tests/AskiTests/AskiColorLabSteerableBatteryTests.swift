import Testing
@testable import AskiColorLab

@Suite struct AskiColorLabSteerableBatteryTests {
    @Test func spokesAndArcsAreNonDegenerate() {
        let spokes = SteerableBattery.spokes(side: 64)
        let arcs = SteerableBattery.arcs(side: 64)
        #expect(spokes.luma.contains { $0 > 0.5 } && arcs.luma.contains { $0 > 0.5 })
    }

    @Test func allBundlesEverySubBattery() {
        let all = SteerableBattery.all(side: 64)
        // spokes (1) + diagonals (4: 15/30/60/75°) + arcs (1) = 6, all synthetic.
        #expect(all.count == 6)
        #expect(all.allSatisfy { $0.pool == .synthetic })
        #expect(all.contains { $0.id == "spokes" } && all.contains { $0.id == "arcs" })
    }
}
