import Testing
@testable import Aski

@Suite struct DeviceCapabilityTests {
    @Test func capabilityCasesAreSendable() {
        let cases: [DeviceCapability] = [
            .full,
            .reducedQuality(.metallibUnsupported),
        ]
        #expect(cases.count == 2)
    }

    @Test func reducedReasonIsHashable() {
        let set: Set<ReducedReason> = [.metallibUnsupported, .metallibUnsupported]
        #expect(set.count == 1)
    }
}

@Suite struct MetalSupportTests {
    @Test func supportsStitchableKernelsReturnsBoolWithoutCrashing() {
        let first = MetalSupport.supportsStitchableKernels()
        let second = MetalSupport.supportsStitchableKernels()
        #expect(first == second)
    }

    @Test func currentDeviceFamilyMaybeNil() {
        let family = MetalSupport.currentDeviceFamily()
        _ = family
    }
}
