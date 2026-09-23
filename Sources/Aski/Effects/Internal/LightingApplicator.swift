import CoreGraphics
import CoreImage
import os

internal struct LightingApplicator: Sendable {
    private static let log = OSLog(subsystem: "com.bigcactuslabs.aski", category: "Effects")
    private static let maxLights = 4

    func apply(
        _ lighting: LightingOptions,
        to image: CIImage,
        in context: EffectContext
    ) -> CIImage {
        let lights = capLights(lighting.lights)
        guard !lights.isEmpty else {
            return ambientOnly(image, ambient: lighting.ambient)
        }

        var lightField = CIImage(color: .black).cropped(to: context.outputExtent)
        for light in lights {
            let radial = makeRadial(for: light, extent: context.outputExtent)
            lightField = additive(lightField, with: radial, extent: context.outputExtent)
        }

        let ambientField = constantField(intensity: lighting.ambient, extent: context.outputExtent)
        let combined = additive(lightField, with: ambientField, extent: context.outputExtent)
        return multiply(image, with: combined, extent: context.outputExtent)
    }

    private func capLights(_ lights: [PointLight]) -> [PointLight] {
        if lights.count > Self.maxLights {
            os_log(
                "LightingApplicator: %d lights provided; truncating to first %d",
                log: Self.log,
                type: .info,
                lights.count,
                Self.maxLights
            )
            return Array(lights.prefix(Self.maxLights))
        }
        return lights
    }

    private func makeRadial(for light: PointLight, extent: CGRect) -> CIImage {
        let centerX = extent.minX + extent.width * light.position.x
        let centerY = extent.minY + extent.height * light.position.y
        let radiusInPixels = max(extent.width, extent.height) * CGFloat(light.radius)

        let filter = CIFilter(name: "CIRadialGradient")!
        filter.setValue(CIVector(x: centerX, y: centerY), forKey: "inputCenter")
        filter.setValue(0, forKey: "inputRadius0")
        filter.setValue(radiusInPixels, forKey: "inputRadius1")

        let intensity = CGFloat(light.intensity)
        let color = CIColor(cgColor: light.color)
        filter.setValue(
            CIColor(
                red: color.red * intensity,
                green: color.green * intensity,
                blue: color.blue * intensity,
                alpha: 1
            ),
            forKey: "inputColor0"
        )
        filter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 1), forKey: "inputColor1")
        return (filter.outputImage ?? CIImage(color: .black)).cropped(to: extent)
    }

    private func additive(_ first: CIImage, with second: CIImage, extent: CGRect) -> CIImage {
        let filter = CIFilter(name: "CIAdditionCompositing")!
        filter.setValue(first, forKey: kCIInputImageKey)
        filter.setValue(second, forKey: kCIInputBackgroundImageKey)
        return (filter.outputImage ?? first).cropped(to: extent)
    }

    private func multiply(_ first: CIImage, with second: CIImage, extent: CGRect) -> CIImage {
        let filter = CIFilter(name: "CIMultiplyCompositing")!
        filter.setValue(first, forKey: kCIInputImageKey)
        filter.setValue(second, forKey: kCIInputBackgroundImageKey)
        return (filter.outputImage ?? first).cropped(to: extent)
    }

    private func constantField(intensity: Double, extent: CGRect) -> CIImage {
        let value = CGFloat(max(0, intensity))
        return CIImage(color: CIColor(red: value, green: value, blue: value, alpha: 1)).cropped(to: extent)
    }

    private func ambientOnly(_ image: CIImage, ambient: Double) -> CIImage {
        let extent = image.extent
        return multiply(image, with: constantField(intensity: ambient, extent: extent), extent: extent)
    }
}
