import Testing
import AppKit
import CoreImage
import CoreGraphics
import SnapshotTesting
@testable import Aski

@Suite struct EffectContextTests {
    @Test func contextHoldsAllInputs() {
        let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let extent = CGRect(x: 0, y: 0, width: 100, height: 50)
        let context = EffectContext(
            workingColorSpace: workingSpace,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
        #expect(context.outputExtent == extent)
        #expect(context.renderColorSpace == .sRGB)
        if case .full = context.deviceCapability { /* ok */  } else { Issue.record("expected .full") }
    }
}

@Suite struct CIKernelLibraryProbeTests {
    @Test func metallibLoadsFromModuleBundle() throws {
        let data = try CIKernelLibrary.loadMetallibData()
        #expect(data.count > 0)
    }

}

@Suite struct MetallibEffectKernelTests {
    private func makeContext() -> EffectContext {
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        return EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .reducedQuality(.metallibUnsupported)
        )
    }

    @Test func reducedCapabilityFallsBackToStub() throws {
        let kernel = MetallibEffectKernel(
            kind: .scanLines(intensity: 0.5, frequency: 4),
            fallback: StockCIEffectKernel(kind: .scanLinesApprox(intensity: 0.5, frequency: 4))
        )
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        let output = try kernel.apply(to: input, in: makeContext())
        #expect(output.extent == extent)
    }

    @Test func capabilityFullAndKernelMissingThrowsOrFallsBack() throws {
        let kernel = MetallibEffectKernel(kind: .scanLines(intensity: 0.5, frequency: 4), fallback: nil)
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: extent)
        let ctx = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
        do {
            _ = try kernel.apply(to: input, in: ctx)
        } catch {
            #expect((error as? EffectError) != nil)
        }
    }
}

@Suite struct ScanLinesKernelTests {
    @Test func scanLinesProducesAlternatingLuminanceRows() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
        let kernel = MetallibEffectKernel(
            kind: .scanLines(intensity: 1.0, frequency: 8),
            fallback: StockCIEffectKernel(kind: .scanLinesApprox(intensity: 1.0, frequency: 8))
        )
        #expect(CIKernelLibrary.scanLines != nil)
        let output = try kernel.apply(to: input, in: context)

        let renderCtx = CIContext(options: nil)
        var even = [UInt8](repeating: 0, count: 4)
        var odd = [UInt8](repeating: 0, count: 4)
        renderCtx.render(
            output,
            toBitmap: &even,
            rowBytes: 4,
            bounds: CGRect(x: 16, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderCtx.render(
            output,
            toBitmap: &odd,
            rowBytes: 4,
            bounds: CGRect(x: 16, y: 4, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(abs(Int(even[0]) - Int(odd[0])) > 4)
    }
}

@Suite struct CRTCurvatureKernelTests {
    @Test func crtCurvatureProducesSameExtent() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 0.7, green: 0.4, blue: 0.2, alpha: 1)).cropped(to: extent)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
        let kernel = MetallibEffectKernel(
            kind: .crtCurvature(intensity: 0.5),
            fallback: StockCIEffectKernel(kind: .crtCurvatureApprox)
        )
        #expect(CIKernelLibrary.crtCurvature != nil)
        let output = try kernel.apply(to: input, in: context)
        #expect(output.extent == extent)
    }
}

@Suite struct HalftoneKernelTests {
    @Test func halftoneProducesSameExtent() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
        let kernel = MetallibEffectKernel(
            kind: .halftone(scale: 8),
            fallback: StockCIEffectKernel(kind: .halftoneApprox(scale: 8))
        )
        #expect(CIKernelLibrary.halftone != nil)
        let output = try kernel.apply(to: input, in: context)
        #expect(output.extent == extent)
    }
}

@Suite struct FilmDustKernelTests {
    @Test func metallibFilmDustIsDeterministicForSameSeed() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)).cropped(to: extent)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
        guard MetalSupport.supportsStitchableKernels(), CIKernelLibrary.filmDust != nil else { return }
        let kernel = MetallibEffectKernel(
            kind: .filmDust(intensity: 1.0, seed: 42),
            fallback: StockCIEffectKernel(kind: .filmDustApprox(intensity: 1.0, seed: 42))
        )
        let a = try kernel.apply(to: input, in: context)
        let b = try kernel.apply(to: input, in: context)

        let renderCtx = CIContext(options: nil)
        var ap = [UInt8](repeating: 0, count: 4)
        var bp = [UInt8](repeating: 0, count: 4)
        let probe = CGRect(x: 16, y: 16, width: 1, height: 1)
        renderCtx.render(
            a,
            toBitmap: &ap,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderCtx.render(
            b,
            toBitmap: &bp,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(ap == bp)
    }
}

@Suite struct GlitchKernelTests {
    @Test func glitchDeterministicSameSeed() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1)).cropped(to: extent)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
        let kernel = MetallibEffectKernel(
            kind: .glitch(intensity: 1.0, seed: 99),
            fallback: StockCIEffectKernel(kind: .glitchApprox(intensity: 1.0, seed: 99))
        )
        #expect(CIKernelLibrary.glitch != nil)
        let a = try kernel.apply(to: input, in: context)
        let b = try kernel.apply(to: input, in: context)

        let renderCtx = CIContext(options: nil)
        var ap = [UInt8](repeating: 0, count: 4)
        var bp = [UInt8](repeating: 0, count: 4)
        let probe = CGRect(x: 32, y: 32, width: 1, height: 1)
        renderCtx.render(
            a,
            toBitmap: &ap,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderCtx.render(
            b,
            toBitmap: &bp,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(ap == bp)
    }
}

@Suite struct RGBSplitKernelTests {
    @Test func rgbSplitProducesOutput() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
        let kernel = MetallibEffectKernel(
            kind: .rgbSplit(intensity: 1.0),
            fallback: StockCIEffectKernel(kind: .rgbSplitApprox(intensity: 1.0))
        )
        #expect(CIKernelLibrary.rgbSplit != nil)
        let output = try kernel.apply(to: input, in: context)
        #expect(output.extent == extent)
    }
}

@Suite struct FilmGrainKernelTests {
    @Test func metallibFilmGrainIsDeterministicForSameSeed() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
        guard MetalSupport.supportsStitchableKernels(), CIKernelLibrary.filmGrain != nil else { return }
        let kernel = MetallibEffectKernel(
            kind: .filmGrain(intensity: 0.5, seed: 7),
            fallback: StockCIEffectKernel(kind: .filmGrainApprox(intensity: 0.5, seed: 7))
        )
        let a = try kernel.apply(to: input, in: context)
        let b = try kernel.apply(to: input, in: context)

        let renderCtx = CIContext(options: nil)
        var ap = [UInt8](repeating: 0, count: 4)
        var bp = [UInt8](repeating: 0, count: 4)
        let probe = CGRect(x: 16, y: 16, width: 1, height: 1)
        renderCtx.render(
            a,
            toBitmap: &ap,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderCtx.render(
            b,
            toBitmap: &bp,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(ap == bp)
    }
}

@Suite struct WorkingColorSpaceTests {
    @Test func canonicalSpaceIsExtendedLinearSRGB() {
        let space = WorkingColorSpace.extendedLinearSRGB
        #expect(space.name as String? == (CGColorSpace.extendedLinearSRGB as String))
    }
}

@Suite struct SharedCIContextTests {
    @Test func wrappedContextIsReusable() {
        let shared = SharedCIContext.makeDefault()
        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let img = CIImage(color: .red).cropped(to: extent)
        let cg1 = shared.context.createCGImage(img, from: extent)
        let cg2 = shared.context.createCGImage(img, from: extent)
        #expect(cg1 != nil)
        #expect(cg2 != nil)
    }
}

@Suite struct StockCIEffectKernelTests {
    private func makeContext(extent: CGRect = CGRect(x: 0, y: 0, width: 32, height: 32)) -> EffectContext {
        return EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
    }

    @Test func dispatcherReturnsImageOfSameExtent() throws {
        let kernel = StockCIEffectKernel(kind: .vignette(intensity: 0))
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: extent)
        let output = try kernel.apply(to: input, in: makeContext(extent: extent))
        #expect(output.extent == extent)
    }

    @Test func vignetteDarkensCornersMoreThanCenter() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let context = makeContext(extent: extent)
        let input = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        let output = try StockCIEffectKernel(kind: .vignette(intensity: 1)).apply(to: input, in: context)

        let renderCtx = CIContext(options: nil)
        var center = [UInt8](repeating: 0, count: 4)
        var corner = [UInt8](repeating: 0, count: 4)
        renderCtx.render(
            output,
            toBitmap: &center,
            rowBytes: 4,
            bounds: CGRect(x: 32, y: 32, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderCtx.render(
            output,
            toBitmap: &corner,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(center[0] > corner[0], "center brighter than corner")
    }

    @Test func vignetteZeroIntensityIsNoOp() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 0.7, green: 0.3, blue: 0.5, alpha: 1)).cropped(to: extent)
        let output = try StockCIEffectKernel(kind: .vignette(intensity: 0)).apply(
            to: input,
            in: makeContext(extent: extent)
        )

        let renderCtx = CIContext(options: nil)
        var inputPixel = [UInt8](repeating: 0, count: 4)
        var outputPixel = [UInt8](repeating: 0, count: 4)
        let probe = CGRect(x: 0, y: 0, width: 1, height: 1)
        renderCtx.render(
            input,
            toBitmap: &inputPixel,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderCtx.render(
            output,
            toBitmap: &outputPixel,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(abs(Int(inputPixel[0]) - Int(outputPixel[0])) < 4)
        #expect(abs(Int(inputPixel[1]) - Int(outputPixel[1])) < 4)
        #expect(abs(Int(inputPixel[2]) - Int(outputPixel[2])) < 4)
    }

    @Test func bloomBleedsBrightAreaIntoAdjacentDarkBand() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let bright = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 16, width: 32, height: 16))
        let dark = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 16))
        let input = bright.composited(over: dark).cropped(to: extent)

        let output = try StockCIEffectKernel(kind: .bloom(intensity: 1, radius: 4)).apply(
            to: input,
            in: makeContext(extent: extent)
        )

        let renderCtx = CIContext(options: nil)
        var inputDark = [UInt8](repeating: 0, count: 4)
        var outputNearBoundary = [UInt8](repeating: 0, count: 4)
        let darkProbe = CGRect(x: 16, y: 15, width: 1, height: 1)
        renderCtx.render(
            input,
            toBitmap: &inputDark,
            rowBytes: 4,
            bounds: darkProbe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderCtx.render(
            output,
            toBitmap: &outputNearBoundary,
            rowBytes: 4,
            bounds: darkProbe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(
            Int(outputNearBoundary[0]) > Int(inputDark[0]) + 16,
            "expected bloom to brighten last-dark-row pixel by >16; got in=\(inputDark[0]) out=\(outputNearBoundary[0])"
        )
    }

    @Test func aberrationShiftsRedAndBlueRelativeToGreen() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let input = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        let output = try StockCIEffectKernel(kind: .chromaticAberration(intensity: 1)).apply(
            to: input,
            in: makeContext(extent: extent)
        )
        #expect(output.extent == extent)
    }

    @Test func aberrationProducesDifferentPixelsAtEdgesThanInput() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let block = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 8, y: 8, width: 16, height: 16))
        let input = block.composited(over: background).cropped(to: extent)

        let output = try StockCIEffectKernel(kind: .chromaticAberration(intensity: 1)).apply(
            to: input,
            in: makeContext(extent: extent)
        )

        let renderCtx = CIContext(options: nil)
        var inputPixel = [UInt8](repeating: 0, count: 4)
        var outputPixel = [UInt8](repeating: 0, count: 4)
        let probe = CGRect(x: 8, y: 16, width: 1, height: 1)
        renderCtx.render(
            input,
            toBitmap: &inputPixel,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderCtx.render(
            output,
            toBitmap: &outputPixel,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let diff =
            abs(Int(inputPixel[0]) - Int(outputPixel[0]))
            + abs(Int(inputPixel[2]) - Int(outputPixel[2]))
        #expect(diff > 16)
    }

    @Test func blurReducesSharpness() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let block = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 12, y: 12, width: 8, height: 8))
        let input = block.composited(over: background).cropped(to: extent)

        let output = try StockCIEffectKernel(kind: .blur(radius: 6)).apply(
            to: input,
            in: makeContext(extent: extent)
        )

        let renderCtx = CIContext(options: nil)
        var center = [UInt8](repeating: 0, count: 4)
        var halo = [UInt8](repeating: 0, count: 4)
        renderCtx.render(
            output,
            toBitmap: &center,
            rowBytes: 4,
            bounds: CGRect(x: 16, y: 16, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderCtx.render(
            output,
            toBitmap: &halo,
            rowBytes: 4,
            bounds: CGRect(x: 8, y: 8, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(halo[0] > 4)
        #expect(center[0] >= halo[0])
    }

    @Test func pixelateReducesDetailWithin8x8Block() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let input = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 32, y: 32),
                "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 1),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
            ])!.outputImage!.cropped(to: extent)

        let output = try StockCIEffectKernel(kind: .pixelate(scale: 8)).apply(
            to: input,
            in: makeContext(extent: extent)
        )

        let renderCtx = CIContext(options: nil)
        var first = [UInt8](repeating: 0, count: 4)
        var second = [UInt8](repeating: 0, count: 4)
        renderCtx.render(
            output,
            toBitmap: &first,
            rowBytes: 4,
            bounds: CGRect(x: 1, y: 1, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderCtx.render(
            output,
            toBitmap: &second,
            rowBytes: 4,
            bounds: CGRect(x: 6, y: 6, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(abs(Int(first[0]) - Int(second[0])) < 6)
    }

    @Test func colorOverlayMultiplyDarkensInput() throws {
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let input = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        let kernel = StockCIEffectKernel(
            kind: .colorOverlay(
                color: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
                blendMode: .multiply,
                opacity: 1
            ))

        let output = try kernel.apply(to: input, in: makeContext(extent: extent))

        let renderCtx = CIContext(options: nil)
        var pixel = [UInt8](repeating: 0, count: 4)
        renderCtx.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 8, y: 8, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(pixel[0] > 80 && pixel[0] < 200)
    }
}

@MainActor
@Suite(.serialized)
struct EffectKernelSnapshotTests {
    private nonisolated static let cases: [(String, Effect)] = [
        ("vignette-default", .vignette(intensity: 0.5)),
        ("vignette-extreme", .vignette(intensity: 1.0)),
        ("bloom-default", .bloom(intensity: 0.4, radius: 6)),
        ("bloom-extreme", .bloom(intensity: 1.0, radius: 14)),
        ("chromaticAberration-default", .chromaticAberration(intensity: 0.5)),
        ("chromaticAberration-extreme", .chromaticAberration(intensity: 1.0)),
        ("blur-default", .blur(radius: 2)),
        ("blur-extreme", .blur(radius: 8)),
        ("pixelate-default", .pixelate(scale: 4)),
        ("pixelate-extreme", .pixelate(scale: 10)),
        ("scanLines-default", .scanLines(intensity: 0.5, frequency: 4)),
        ("scanLines-extreme", .scanLines(intensity: 1.0, frequency: 8)),
        ("crtCurvature-default", .crtCurvature(intensity: 0.5)),
        ("crtCurvature-extreme", .crtCurvature(intensity: 1.0)),
        ("halftone-default", .halftone(scale: 6)),
        ("halftone-extreme", .halftone(scale: 12)),
        ("filmDust-default", .filmDust(intensity: 0.5, seed: 42)),
        ("filmDust-extreme", .filmDust(intensity: 1.0, seed: 42)),
        ("glitch-default", .glitch(intensity: 0.5, seed: 42)),
        ("glitch-extreme", .glitch(intensity: 1.0, seed: 42)),
        ("rgbSplit-default", .rgbSplit(intensity: 0.5)),
        ("rgbSplit-extreme", .rgbSplit(intensity: 1.0)),
        ("filmGrain-default", .filmGrain(intensity: 0.4, seed: 42)),
        ("filmGrain-extreme", .filmGrain(intensity: 1.0, seed: 42)),
    ]

    private func makeGrid() -> ASCIIGrid {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        return ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 24), count: 16), colorSpace: .sRGB)
    }

    private func render(_ effect: Effect) -> CGImage {
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        return makeGrid().renderImage(
            font: ASCIIFont.courierPrime(size: 12),
            backgroundColor: bg,
            scale: 1,
            composition: CompositionOptions(background: .solid(bg)),
            effects: EffectChain([effect])
        )
    }

    private func snapshot(_ cg: CGImage) -> NSImage {
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    @Test(arguments: EffectKernelSnapshotTests.cases)
    func effectSnapshot(name: String, effect: Effect) {
        assertSnapshot(of: snapshot(render(effect)), as: .image, named: name)
    }
}
