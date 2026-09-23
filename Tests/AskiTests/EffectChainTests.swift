import CoreImage
import Testing
@testable import Aski

@Suite struct EffectErrorTests {
    @Test func errorCasesAreSendable() {
        let cases: [EffectError] = [
            .metallibUnavailable,
            .unsupportedOnDevice(.scanLines(intensity: 1, frequency: 4)),
            .degenerateOutput,
            .unsupportedBlendMode(.normal),
        ]
        // Compile-time check via Array<EffectError> conformance to Sendable.
        #expect(cases.count == 4)
    }

    @Test func errorEquatabilityFromSourceCases() {
        #expect(EffectError.metallibUnavailable as Error is EffectError)
    }
}

@Suite struct EffectChainTests {
    @Test func defaultChainIsEmpty() {
        let chain = EffectChain()
        #expect(chain.effects.isEmpty)
    }

    @Test func chainPreservesOrder() {
        let chain = EffectChain([
            .vignette(intensity: 0.5),
            .bloom(intensity: 0.5, radius: 8),
            .filmGrain(intensity: 0.2, seed: 42),
        ])
        #expect(chain.effects.count == 3)
        guard case .vignette = chain.effects[0] else { Issue.record("expected vignette"); return }
        guard case .bloom = chain.effects[1] else { Issue.record("expected bloom"); return }
        guard case .filmGrain = chain.effects[2] else { Issue.record("expected filmGrain"); return }
    }

    @Test func everyEffectCaseConstructs() {
        // Compile-time enumeration: every case from the spec must be representable.
        let _: [Effect] = [
            .vignette(intensity: 0.5),
            .scanLines(intensity: 0.5, frequency: 4),
            .crtCurvature(intensity: 0.3),
            .chromaticAberration(intensity: 0.4),
            .bloom(intensity: 0.5, radius: 8),
            .filmGrain(intensity: 0.2, seed: 1),
            .glitch(intensity: 0.3, seed: 2),
            .rgbSplit(intensity: 0.2),
            .blur(radius: 4),
            .pixelate(scale: 4),
            .halftone(scale: 8),
            .filmDust(intensity: 0.3, seed: 3),
        ]
    }

    @Test func syncTailCompletesWhileCancelledAsyncTailRethrows() async {
        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let image = CIImage(color: .clear).cropped(to: extent)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .reducedQuality(.metallibUnsupported)
        )
        let effects = EffectChain([.vignette(intensity: 0.5)])

        #expect(EffectsRenderEngine.runEffectChainSync(image, effects: effects, in: context).extent == extent)

        let task = Task {
            try await EffectsRenderEngine.runEffectChainAsync(image, effects: effects, in: context)
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected: the async tail propagates cancellation while the sync tail is best effort.
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
    }
}
