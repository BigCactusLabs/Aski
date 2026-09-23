import Foundation
#if canImport(Metal)
    import Metal
#endif

internal enum MetalSupport {
    private static let cachedSupports: Bool = {
        #if canImport(Metal)
            guard let device = MTLCreateSystemDefaultDevice() else { return false }
            return device.supportsFamily(.apple6)
        #else
            return false
        #endif
    }()

    private static let cachedFamily: MTLGPUFamily? = {
        #if canImport(Metal)
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            let families: [MTLGPUFamily] = [
                .apple9, .apple8, .apple7, .apple6,
                .apple5, .apple4, .apple3, .apple2, .apple1,
            ]
            return families.first { device.supportsFamily($0) }
        #else
            return nil
        #endif
    }()

    @TaskLocal static var testOverride: Bool? = nil

    static func withTestOverride<T>(_ value: Bool?, _ body: () throws -> T) rethrows -> T {
        try $testOverride.withValue(value, operation: body)
    }

    static func withTestOverride<T>(_ value: Bool?, _ body: () async throws -> T) async rethrows -> T {
        try await $testOverride.withValue(value, operation: body)
    }

    static func supportsStitchableKernels() -> Bool { testOverride ?? cachedSupports }
    static func currentDeviceFamily() -> MTLGPUFamily? { cachedFamily }
}
