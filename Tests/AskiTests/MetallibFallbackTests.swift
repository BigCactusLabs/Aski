import Testing
import CoreGraphics
@testable import Aski

struct MetallibFallbackTests {
    @Test func reducedCapabilityRoutesScanLinesToFallback() {
        MetalSupport.withTestOverride(false) {
            let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
            let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 8), count: 8), colorSpace: .sRGB)
            let img = grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                scale: 1,
                composition: CompositionOptions(background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1))),
                effects: EffectChain([.scanLines(intensity: 1, frequency: 4)])
            )
            #expect(img.width > 0)
        }
    }

    @Test func reducedCapabilitySurfacedViaActor() async {
        await MetalSupport.withTestOverride(false) {
            let engine = AskiRenderEngine()
            let cap = await engine.deviceCapability
            if case .reducedQuality(.metallibUnsupported) = cap {
                return
            }
            Issue.record("expected reducedQuality(.metallibUnsupported); got \(cap)")
        }
    }
}
