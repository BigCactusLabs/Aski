import CoreGraphics
import Testing

@testable import AskiMotionLab

@Suite struct SyntheticMotionTests {
    @Test func frameCountAndRenderSizeAreFrozen() {
        #expect(SyntheticMotion.frameCount == 48)
        #expect(SyntheticMotion.renderSize == 512)
    }

    @Test func groundTruthIsDeterministic() {
        for stimulus in TemporalStimulus.allCases {
            let a = SyntheticMotion.groundTruthLuma(stimulus, frame: 7, width: 32, height: 24)
            let b = SyntheticMotion.groundTruthLuma(stimulus, frame: 7, width: 32, height: 24)
            #expect(a == b)
            #expect(a.count == 32 * 24)
            #expect(a.allSatisfy { $0 >= 0 && $0 <= 1 })
        }
    }

    @Test func inputImageHasRenderSizeDimensions() {
        let image = SyntheticMotion.inputImage(.s1, frame: 0)
        #expect(image.width == SyntheticMotion.renderSize)
        #expect(image.height == SyntheticMotion.renderSize)
    }

    @Test func inputImagePixelsAreDeterministicAndMatchSceneLuma() throws {
        let frame = 7
        let samplePoints = [
            (x: 0, y: 0),
            (x: SyntheticMotion.renderSize / 2, y: SyntheticMotion.renderSize / 2),
            (x: SyntheticMotion.renderSize - 1, y: SyntheticMotion.renderSize - 1),
        ]

        for stimulus in TemporalStimulus.allCases {
            let imageA = SyntheticMotion.inputImage(stimulus, frame: frame)
            let imageB = SyntheticMotion.inputImage(stimulus, frame: frame)
            let pixelsA = try #require(rgba8Pixels(from: imageA))
            let pixelsB = try #require(rgba8Pixels(from: imageB))

            #expect(pixelsA == pixelsB)
            for point in samplePoints {
                let offset = (point.y * SyntheticMotion.renderSize + point.x) * 4
                let u = (Double(point.x) + 0.5) / Double(SyntheticMotion.renderSize)
                let v = (Double(point.y) + 0.5) / Double(SyntheticMotion.renderSize)
                let expectedByte = Self.byte(for: SyntheticMotion.sceneLuma(stimulus, frame: frame, u: u, v: v))

                #expect(pixelsA[offset] == expectedByte)
                #expect(pixelsA[offset + 1] == expectedByte)
                #expect(pixelsA[offset + 2] == expectedByte)
                #expect(pixelsA[offset + 3] == 255)
            }
        }
    }

    @Test func s1SceneConstantsAreFrozen() {
        #expect(SyntheticMotion.sceneLuma(.s1, frame: 0, u: 0.32, v: 0.40) == 1.0)
        expectApprox(SyntheticMotion.sceneLuma(.s1, frame: 0, u: 0.0, v: 0.0), 0.10)
        expectApprox(SyntheticMotion.sceneLuma(.s1, frame: 0, u: 1.0, v: 0.0), 0.60)

        let outsideRadiusU = 0.32 + 0.181
        let outsideRadius = SyntheticMotion.sceneLuma(.s1, frame: 0, u: outsideRadiusU, v: 0.40)
        #expect(outsideRadius < 0.9)
        expectApprox(outsideRadius, 0.10 + 0.50 * outsideRadiusU)
    }

    @Test func s1VelocityConstantsAreFrozen() {
        let expectedU = 0.32 + 10.0 * 0.7 / 512.0
        let expectedV = 0.40 + 10.0 * 0.4 / 512.0
        #expect(SyntheticMotion.sceneLuma(.s1, frame: 10, u: expectedU, v: expectedV) == 1.0)

        let c0 = centerOfMass(.s1, frame: 0)
        let cN = centerOfMass(.s1, frame: SyntheticMotion.frameCount - 1)
        let expectedDx = 47.0 * 0.7 / 512.0
        let expectedDy = 47.0 * 0.4 / 512.0
        expectApprox(cN.x - c0.x, expectedDx, tolerance: 0.02)
        expectApprox(cN.y - c0.y, expectedDy, tolerance: 0.02)
    }

    @Test func s2SceneConstantsAreFrozen() {
        #expect(SyntheticMotion.sceneLuma(.s2, frame: 0, u: 0.1, v: 0.5) == 1.0)
        expectApprox(SyntheticMotion.sceneLuma(.s2, frame: 0, u: 0.5, v: 0.5 + 0.061), 0.15)

        #expect(SyntheticMotion.sceneLuma(.s2, frame: 45, u: 0.5, v: 0.1) == 1.0)
        expectApprox(SyntheticMotion.sceneLuma(.s2, frame: 45, u: 0.5 + 0.061, v: 0.5), 0.15)
    }

    @Test func discTranslatesBetweenFrames() {
        let c0 = centerOfMass(.s1, frame: 0)
        let cN = centerOfMass(.s1, frame: SyntheticMotion.frameCount - 1)
        let dx = cN.x - c0.x
        let dy = cN.y - c0.y
        #expect((dx * dx + dy * dy).squareRoot() > 0.02, "disc did not translate: \(c0) -> \(cN)")
    }

    @Test func barRotatesBetweenFrames() {
        let a = SyntheticMotion.groundTruthLuma(.s2, frame: 0, width: 48, height: 48)
        let b = SyntheticMotion.groundTruthLuma(.s2, frame: 20, width: 48, height: 48)
        var diff = 0.0
        for i in 0..<a.count {
            diff += abs(Double(a[i] - b[i]))
        }
        #expect(diff > 1.0, "rotating bar produced no change between frames")
    }

    private func centerOfMass(_ stimulus: TemporalStimulus, frame: Int) -> (x: Double, y: Double) {
        let width = 64
        let height = 64
        let luma = SyntheticMotion.groundTruthLuma(stimulus, frame: frame, width: width, height: height)
        var sx = 0.0
        var sy = 0.0
        var mass = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let m = Double(luma[y * width + x] > 0.9 ? 1.0 : 0.0)
                sx += Double(x) * m
                sy += Double(y) * m
                mass += m
            }
        }
        guard mass > 0 else { return (0, 0) }
        return (sx / mass / Double(width), sy / mass / Double(height))
    }

    private static func byte(for luma: Float) -> UInt8 {
        UInt8(min(255, max(0, Int((luma * 255).rounded()))))
    }

    private func rgba8Pixels(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { rawBuffer in
            guard
                let context = CGContext(
                    data: rawBuffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                )
            else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return didDraw ? pixels : nil
    }

    private func expectApprox(
        _ actual: Float,
        _ expected: Double,
        tolerance: Double = 1e-5,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        expectApprox(Double(actual), expected, tolerance: tolerance, sourceLocation: sourceLocation)
    }

    private func expectApprox(
        _ actual: Double,
        _ expected: Double,
        tolerance: Double = 1e-5,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            abs(actual - expected) <= tolerance,
            "\(actual) is not within \(tolerance) of \(expected)",
            sourceLocation: sourceLocation
        )
    }
}
