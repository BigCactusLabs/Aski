import CoreImage

internal struct SharedCIContext: @unchecked Sendable {
    let context: CIContext

    static func makeDefault() -> SharedCIContext {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            .cacheIntermediates: true,
        ]
        return SharedCIContext(context: CIContext(options: options))
    }
}
