import Testing
import CoreGraphics
import CoreImage
@testable import Aski

@Suite struct LightingOptionsTests {
    @Test func pointLightConstructs() {
        let light = PointLight(
            position: CGPoint(x: 0.5, y: 0.5),
            radius: 0.4,
            intensity: 1,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        )
        #expect(light.radius == 0.4)
    }

    @Test func defaultAmbientIsHalf() {
        let opts = LightingOptions(lights: [])
        #expect(opts.ambient == 0.5)
    }
}

@Suite struct LightingApplicatorTests {
    private func makeContext(width: Int, height: Int) -> EffectContext {
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        return EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )
    }

    @Test func emptyLightsReturnsImageUnchangedExtent() {
        let applicator = LightingApplicator()
        let context = makeContext(width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: context.outputExtent)
        let result = applicator.apply(LightingOptions(lights: []), to: input, in: context)
        #expect(result.extent == input.extent)
    }

    @Test func tooManyLightsAreTruncatedToFour() {
        let applicator = LightingApplicator()
        let context = makeContext(width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)).cropped(to: context.outputExtent)
        let many = (0..<8).map { index in
            PointLight(
                position: CGPoint(x: 0.5, y: 0.5),
                radius: 0.4,
                intensity: 1,
                color: CGColor(red: Double(index) / 8, green: 0, blue: 0, alpha: 1)
            )
        }
        let result = applicator.apply(LightingOptions(lights: many, ambient: 0.5), to: input, in: context)
        #expect(result.extent == input.extent)
    }

    @Test func singleCenterLightBrightensCenterPixel() {
        let applicator = LightingApplicator()
        let context = makeContext(width: 32, height: 32)
        let input = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)).cropped(to: context.outputExtent)
        let light = PointLight(
            position: CGPoint(x: 0.5, y: 0.5),
            radius: 0.5,
            intensity: 1,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        )
        let result = applicator.apply(LightingOptions(lights: [light], ambient: 0), to: input, in: context)

        let renderContext = CIContext(options: nil)
        var center = [UInt8](repeating: 0, count: 4)
        var corner = [UInt8](repeating: 0, count: 4)
        renderContext.render(
            result,
            toBitmap: &center,
            rowBytes: 4,
            bounds: CGRect(x: 16, y: 16, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        renderContext.render(
            result,
            toBitmap: &corner,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(center[0] > corner[0], "center should be brighter than corner")
    }
}
