@_spi(AskiResearch) import Aski  // SPI: HelmlabMetric. (No internal Aski symbols here, so no @testable needed for Aski.)
import Foundation
import Testing
import simd
@testable import AskiColorLab

@Suite struct HelmlabRecoveryOracleTests {
    @Test func recoveryRatesAreComputableForAllFourPolicies() {
        let oklab = HelmlabRecoveryFixtures.recoveryRate(
            resolve: { SIMD3<Double>(PaletteMatchPolicies.resolveToOKLab($0)) },
            distance: { simd_length($0 - $1) }
        )
        let helmlabEuclidean = HelmlabRecoveryFixtures.recoveryRate(
            resolve: PaletteMatchPolicies.resolveToHelmlab,
            distance: HelmlabMetric.euclideanDistance
        )
        let helmlabCompressed = HelmlabRecoveryFixtures.recoveryRate(
            resolve: PaletteMatchPolicies.resolveToHelmlab,
            distance: HelmlabMetric.compressedDeltaE
        )
        for rate in [oklab, helmlabEuclidean, helmlabCompressed] {
            #expect(rate >= 0 && rate <= 1)
        }
        // Small perturbations should mostly recover the source entry under a
        // reasonable metric.
        #expect(oklab > 0.5)
    }
}
