import CoreImage
import Foundation

internal enum CIKernelLibrary {
    static func loadMetallibData() throws -> Data {
        // Resources are copied via .copy("Resources/Kernels"), so the metallib
        // lives under the "Kernels" subdirectory in Bundle.module.
        if let url = Bundle.module.url(forResource: "default", withExtension: "metallib", subdirectory: "Kernels") {
            return try Data(contentsOf: url)
        }
        if let bundle = Bundle(identifier: "com.bigcactuslabs.Aski"),
            let url = bundle.url(forResource: "default", withExtension: "metallib", subdirectory: "Kernels")
        {
            return try Data(contentsOf: url)
        }
        throw EffectError.metallibUnavailable
    }

    private static func kernel(named name: String) -> CIKernel? {
        guard let data = try? loadMetallibData(), data.count > 0 else { return nil }
        return try? CIKernel(functionName: name, fromMetalLibraryData: data)
    }

    static let scanLines: CIKernel? = kernel(named: "ascii_b_scanLines")
    static let crtCurvature: CIKernel? = kernel(named: "ascii_b_crtCurvature")
    static let halftone: CIKernel? = kernel(named: "ascii_b_halftone")
    static let filmDust: CIKernel? = kernel(named: "ascii_b_filmDust")
    static let glitch: CIKernel? = kernel(named: "ascii_b_glitch")
    static let rgbSplit: CIKernel? = kernel(named: "ascii_b_rgbSplit")
    static let filmGrain: CIKernel? = kernel(named: "ascii_b_filmGrain")
}
