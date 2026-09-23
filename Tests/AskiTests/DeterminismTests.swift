import Testing
import CoreImage
import CoreGraphics
@testable import Aski

@Suite struct DeterminismTests {
    private func sampleHash(_ image: CGImage) -> UInt64 {
        let w = image.width
        let h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(
            data: &bytes,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes.reduce(UInt64(0xcbf29ce484222325)) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x100000001b3
        }
    }

    private func makeGrid() -> ASCIIGrid {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        return ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 16), count: 16), colorSpace: .sRGB)
    }

    @Test func filmGrainSameSeedSameOutput() {
        guard MetalSupport.supportsStitchableKernels(), CIKernelLibrary.filmGrain != nil else { return }
        let grid = makeGrid()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let render = { (seed: UInt64) -> CGImage in
            grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: bg,
                scale: 1,
                composition: CompositionOptions(background: .solid(bg)),
                effects: EffectChain([.filmGrain(intensity: 0.5, seed: seed)])
            )
        }
        let a = render(7)
        let b = render(7)
        #expect(sampleHash(a) == sampleHash(b))
    }

    @Test func filmGrainDifferentSeedsDifferOutput() {
        guard MetalSupport.supportsStitchableKernels(), CIKernelLibrary.filmGrain != nil else { return }
        let grid = makeGrid()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let render = { (seed: UInt64) -> CGImage in
            grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: bg,
                scale: 1,
                composition: CompositionOptions(background: .solid(bg)),
                effects: EffectChain([.filmGrain(intensity: 1.0, seed: seed)])
            )
        }
        let a = render(7)
        let b = render(42)
        #expect(sampleHash(a) != sampleHash(b))
    }

    @Test func filmGrainHighBitsAffectOutput() {
        guard MetalSupport.supportsStitchableKernels(), CIKernelLibrary.filmGrain != nil else { return }
        let grid = makeGrid()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let render = { (seed: UInt64) -> CGImage in
            grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: bg,
                scale: 1,
                composition: CompositionOptions(background: .solid(bg)),
                effects: EffectChain([.filmGrain(intensity: 1.0, seed: seed)])
            )
        }
        let lowSeed: UInt64 = 1
        let highSeed: UInt64 = (1 << 40) | 1
        #expect(sampleHash(render(lowSeed)) != sampleHash(render(highSeed)))
    }

    @Test func filmDustSameSeedSameOutput() {
        guard MetalSupport.supportsStitchableKernels(), CIKernelLibrary.filmDust != nil else { return }
        let grid = makeGrid()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let render = { (seed: UInt64) -> CGImage in
            grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: bg,
                scale: 1,
                composition: CompositionOptions(background: .solid(bg)),
                effects: EffectChain([.filmDust(intensity: 1.0, seed: seed)])
            )
        }
        #expect(sampleHash(render(13)) == sampleHash(render(13)))
    }

    @Test func filmDustDifferentSeedsDifferOutput() {
        guard MetalSupport.supportsStitchableKernels(), CIKernelLibrary.filmDust != nil else { return }
        let grid = makeGrid()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let render = { (seed: UInt64) -> CGImage in
            grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: bg,
                scale: 1,
                composition: CompositionOptions(background: .solid(bg)),
                effects: EffectChain([.filmDust(intensity: 1.0, seed: seed)])
            )
        }
        #expect(sampleHash(render(13)) != sampleHash(render(42)))
    }

    @Test func glitchHighBitsAffectOutput() {
        guard MetalSupport.supportsStitchableKernels(), CIKernelLibrary.glitch != nil else { return }
        let grid = makeGrid()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let render = { (seed: UInt64) -> CGImage in
            grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: bg,
                scale: 1,
                composition: CompositionOptions(background: .solid(bg)),
                effects: EffectChain([.glitch(intensity: 1.0, seed: seed)])
            )
        }
        #expect(sampleHash(render(1)) != sampleHash(render((1 << 40) | 1)))
    }

    @Test func glitchSeedIsDeterministic() {
        let grid = makeGrid()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let render = { (seed: UInt64) -> CGImage in
            grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: bg,
                scale: 1,
                composition: CompositionOptions(background: .solid(bg)),
                effects: EffectChain([.glitch(intensity: 0.5, seed: seed)])
            )
        }
        #expect(sampleHash(render(99)) == sampleHash(render(99)))
    }

    @Test func filmGrainFallbackPathRunsWithoutCrashing() {
        MetalSupport.withTestOverride(false) {
            let grid = makeGrid()
            let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            let img = grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: bg,
                scale: 1,
                composition: CompositionOptions(background: .solid(bg)),
                effects: EffectChain([.filmGrain(intensity: 0.5, seed: 1)])
            )
            #expect(img.width > 0)
        }
    }

    @Test func filmGrainFallbackDifferentSeedsDifferOutput() {
        MetalSupport.withTestOverride(false) {
            let grid = makeGrid()
            let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            let render = { (seed: UInt64) -> CGImage in
                grid.renderImage(
                    font: ASCIIFont.system(size: 12),
                    backgroundColor: bg,
                    scale: 1,
                    composition: CompositionOptions(background: .solid(bg)),
                    effects: EffectChain([.filmGrain(intensity: 1.0, seed: seed)])
                )
            }
            #expect(sampleHash(render(7)) != sampleHash(render(42)))
        }
    }

    @Test func filmDustFallbackDifferentSeedsDifferOutput() {
        MetalSupport.withTestOverride(false) {
            let grid = makeGrid()
            let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            let render = { (seed: UInt64) -> CGImage in
                grid.renderImage(
                    font: ASCIIFont.system(size: 12),
                    backgroundColor: bg,
                    scale: 1,
                    composition: CompositionOptions(background: .solid(bg)),
                    effects: EffectChain([.filmDust(intensity: 1.0, seed: seed)])
                )
            }
            #expect(sampleHash(render(13)) != sampleHash(render(42)))
        }
    }

    @Test func seededNoiseFallbackProducesPinnedBytes() throws {
        let extent = CGRect(x: 0, y: 0, width: 2, height: 2)
        let input = CIImage(color: .clear).cropped(to: extent)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .reducedQuality(.metallibUnsupported)
        )
        let output = try StockCIEffectKernel(kind: .filmGrainApprox(intensity: 1, seed: 0x1234_5678_9ABC_DEF0))
            .apply(to: input, in: context)
        let image = try #require(
            CIContext(options: nil).createCGImage(output, from: extent)
        )

        #expect(
            TestImages.deviceRGBBytes(image) == [
                3, 3, 3, 38,
                26, 26, 26, 38,
                8, 8, 8, 38,
                10, 10, 10, 38,
            ]
        )
    }

    @Test func glitchFallbackRemainsDeterministicForSameSeed() {
        MetalSupport.withTestOverride(false) {
            let grid = makeGrid()
            let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            let render = { (seed: UInt64) -> CGImage in
                grid.renderImage(
                    font: ASCIIFont.system(size: 12),
                    backgroundColor: bg,
                    scale: 1,
                    composition: CompositionOptions(background: .solid(bg)),
                    effects: EffectChain([.glitch(intensity: 0.5, seed: seed)])
                )
            }
            #expect(sampleHash(render(11)) == sampleHash(render(11)))
        }
    }
}
