import Foundation
import Testing
@testable import Aski

@Suite struct MetallibArtifactTests {
    @Test func metallibIsUnderSizeCap() throws {
        let data = try CIKernelLibrary.loadMetallibData()
        #expect(data.count > 0, "metallib must be non-empty")
        #expect(data.count <= 100 * 1024, "metallib exceeds 100 KB cap (was \(data.count) bytes)")
    }

    @Test func metallibLoadsAllSevenKernels() throws {
        guard MetalSupport.supportsStitchableKernels() else { return }
        #expect(CIKernelLibrary.scanLines != nil)
        #expect(CIKernelLibrary.crtCurvature != nil)
        #expect(CIKernelLibrary.halftone != nil)
        #expect(CIKernelLibrary.filmDust != nil)
        #expect(CIKernelLibrary.glitch != nil)
        #expect(CIKernelLibrary.rgbSplit != nil)
        #expect(CIKernelLibrary.filmGrain != nil)
    }
}
