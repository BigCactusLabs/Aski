import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Aski

@Suite struct VideoOrientationPreparationTests {
    // ASKI-2 frozen rule: exact lattice geometry and every premultiplied RGBA8
    // byte must match the retained path. A mismatch vetoes this arm before
    // cell/render tests or production integration. Run this test explicitly.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASKI2_ORIENTATION_RASTER"] == "1"))
    func rawAxisResamplingMatchesRetainedLattice() throws {
        let ciContext = CIContext()
        var failures = 0

        for (width, height, columns) in [(1280, 720, 80), (64, 46, 36)] {
            for sourceSpace in [RenderColorSpace.sRGB, .displayP3] {
                for mixedAlpha in [false, true] {
                    let image = try Self.fixture(width: width, height: height, space: sourceSpace, mixedAlpha: mixedAlpha)
                    for orientation in Orientation.allCases {
                        let retained = try Self.retainedOrientation(image, orientation: orientation.transform, context: ciContext)
                        for target in [RenderColorSpace.sRGB, .displayP3] {
                            var converter = DefaultConverter()
                            converter.colorSpace = target
                            let control = try #require(converter.prepareConversion(retained, columns: columns, mask: nil)).context
                            let (geometry, candidate) = try Self.candidateLattice(
                                image, orientation: orientation.transform, columns: columns, converter: converter
                            )
                            let displayMatches = retained.width == geometry.displayWidth && retained.height == geometry.displayHeight
                            let geometryMatches =
                                displayMatches
                                && control.columns == geometry.columns && control.rows == geometry.rows
                                && control.cellWidth == geometry.cellWidth && control.cellHeight == geometry.cellHeight
                                && control.pixelWidth == geometry.width && control.pixelHeight == geometry.height
                            let delta = Self.difference(expected: control.pixels, actual: candidate)
                            let passed = geometryMatches && delta.differingBytes == 0 && control.pixels.count == candidate.count
                            if !passed { failures += 1 }
                            print(
                                "ASKI2_RASTER input=\(width)x\(height) source=\(sourceSpace) mixedAlpha=\(mixedAlpha) "
                                    + "orientation=\(orientation.rawValue) target=\(target) columns=\(columns) "
                                    + "display=\(geometry.displayWidth)x\(geometry.displayHeight) grid=\(geometry.columns)x\(geometry.rows) "
                                    + "pitch=\(geometry.cellWidth)x\(geometry.cellHeight) lattice=\(geometry.width)x\(geometry.height) "
                                    + "controlDisplay=\(retained.width)x\(retained.height) controlGrid=\(control.columns)x\(control.rows) "
                                    + "controlPitch=\(control.cellWidth)x\(control.cellHeight) controlLattice=\(control.pixelWidth)x\(control.pixelHeight) "
                                    + "geometryExact=\(geometryMatches) controlBytes=\(control.pixels.count) candidateBytes=\(candidate.count) "
                                    + "differingPixels=\(delta.differingPixels) differingBytes=\(delta.differingBytes) "
                                    + "channelCounts=\(delta.channelCounts) signedMin=\(delta.minima) signedMax=\(delta.maxima) passed=\(passed)"
                            )
                            if orientation == .mirrorHorizontal {
                                let unmirrored = try #require(converter.prepareConversion(image, columns: columns, mask: nil)).context
                                let wrong = Self.difference(expected: control.pixels, actual: unmirrored.pixels)
                                #expect(control.pixels.count == unmirrored.pixels.count && wrong.differingPixels > 0)
                                print(
                                    "ASKI2_NEGATIVE input=\(width)x\(height) source=\(sourceSpace) mixedAlpha=\(mixedAlpha) "
                                        + "target=\(target) differingPixels=\(wrong.differingPixels)"
                                )
                            }
                        }
                    }
                }
            }
        }
        #expect(failures == 0, "Exact ASKI-2 raster parity failed in \(failures) cases; see ASKI2_RASTER rows")
    }

    private enum Orientation: String, CaseIterable {
        case identity, rotate90, rotate180, rotate270
        case mirrorHorizontal, mirrorVertical, transpose, transverse

        var transform: CGAffineTransform {
            switch self {
            case .identity: .identity
            case .rotate90: .init(a: 0, b: 1, c: -1, d: 0, tx: 720, ty: 0)
            case .rotate180: .init(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
            case .rotate270: .init(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
            case .mirrorHorizontal: .init(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
            case .mirrorVertical: .init(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
            case .transpose: .init(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
            case .transverse: .init(a: 0, b: -1, c: -1, d: 0, tx: -13, ty: 17)
            }
        }
    }

    private struct Geometry {
        let displayWidth: Int
        let displayHeight: Int
        let columns: Int
        let rows: Int
        let cellWidth: Int
        let cellHeight: Int

        var width: Int { columns * cellWidth }
        var height: Int { rows * cellHeight }
    }

    private static func candidateLattice(
        _ image: CGImage,
        orientation: CGAffineTransform,
        columns: Int,
        converter: DefaultConverter
    ) throws -> (Geometry, [UInt8]) {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            .applying(orientation).standardized.integral
        let displayWidth = Int(extent.width)
        let displayHeight = Int(extent.height)
        let (_, rows) = try #require(
            gridDimensions(
                imageWidth: displayWidth, imageHeight: displayHeight, columns: columns, tileShape: converter.tileShape
            ))
        let cap = try #require(converter.thumbnailMaxPixelSize(width: displayWidth, height: displayHeight, columns: columns, rows: rows))
        let prepared = try #require(preparedSize(width: displayWidth, height: displayHeight, maxPixelSize: cap))
        let geometry = Geometry(
            displayWidth: displayWidth, displayHeight: displayHeight, columns: columns, rows: rows,
            cellWidth: prepared.width / columns, cellHeight: prepared.height / rows
        )
        let transposed = orientation.a == 0
        let width = transposed ? geometry.height : geometry.width
        let height = transposed ? geometry.width : geometry.height
        let space = converter.colorSpace
        let raw = try #require(
            max(displayWidth, displayHeight) > cap
                ? resampleRGBA8(image, width: width, height: height, targetColorSpace: space)
                : readRGBA8(image, width: width, height: height, targetColorSpace: space))
        if orientation.isIdentity { return (geometry, raw) }

        // The byte raster has a top-left origin. Signed permutation in raw-axis
        // coordinates followed by zero-origin normalization maps pixel centers.
        let a = Int(orientation.a)
        let b = Int(orientation.b)
        let c = Int(orientation.c)
        let d = Int(orientation.d)
        let xOffset = (a < 0 ? width - 1 : 0) + (c < 0 ? height - 1 : 0)
        let yOffset = (b < 0 ? width - 1 : 0) + (d < 0 ? height - 1 : 0)
        var output = [UInt8](repeating: 0, count: raw.count)
        for y in 0..<height {
            for x in 0..<width {
                let source = (y * width + x) * 4
                let displayX = a * x + c * y + xOffset
                let displayY = b * x + d * y + yOffset
                let destination = (displayY * geometry.width + displayX) * 4
                for channel in 0..<4 {
                    output[destination + channel] = raw[source + channel]
                }
            }
        }
        return (geometry, output)
    }

    // Frozen from DecodeSession.reorient in ASCIIVideoDecoder.swift:326–342 at
    // e9ac79b. Use the supplied context in place of the actor's cached context.
    private static func retainedOrientation(
        _ image: CGImage, orientation: CGAffineTransform, context: CIContext
    ) throws -> CGImage {
        if orientation.isIdentity { return image }
        let naturalExtent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let displayExtent = naturalExtent.applying(orientation).standardized.integral
        let sourceToDisplay = CGAffineTransform(translationX: 0, y: naturalExtent.height)
            .scaledBy(x: 1, y: -1)
            .concatenating(orientation)
            .concatenating(CGAffineTransform(translationX: 0, y: displayExtent.height).scaledBy(x: 1, y: -1))
        let source = CIImage(cgImage: image).transformed(by: sourceToDisplay)
        let extent = source.extent.integral
        let normalized = source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        guard let rotated = context.createCGImage(normalized, from: CGRect(origin: .zero, size: extent.size)) else {
            throw VideoDecodeError.conversionFailed
        }
        return rotated
    }

    private static func fixture(width: Int, height: Int, space: RenderColorSpace, mixedAlpha: Bool) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let alpha = mixedAlpha ? ((x * 3 + y * 7) % 256) : 255
                let red = x < width / 3 ? 255 : (x + 11 * y) % 256
                let green = y < height / 4 ? 232 : (19 * x + y) % 256
                let blue = (x + y) % 2 == 0 ? 24 : 244
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(red * alpha / 255)
                pixels[offset + 1] = UInt8(green * alpha / 255)
                pixels[offset + 2] = UInt8(blue * alpha / 255)
                pixels[offset + 3] = UInt8(alpha)
            }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: space.encodedCGColorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ))
    }

    private struct Difference {
        var differingPixels = 0
        var differingBytes = 0
        var channelCounts = [0, 0, 0, 0]
        var minima = [0, 0, 0, 0]
        var maxima = [0, 0, 0, 0]
    }

    private static func difference(expected: [UInt8], actual: [UInt8]) -> Difference {
        var report = Difference()
        var previousPixel = -1
        for index in 0..<min(expected.count, actual.count) {
            let delta = Int(actual[index]) - Int(expected[index])
            let channel = index % 4
            if index < 4 {
                report.minima[channel] = delta
                report.maxima[channel] = delta
            } else {
                report.minima[channel] = min(report.minima[channel], delta)
                report.maxima[channel] = max(report.maxima[channel], delta)
            }
            if delta == 0 { continue }
            report.differingBytes += 1
            report.channelCounts[channel] += 1
            let pixel = index / 4
            if previousPixel != pixel {
                report.differingPixels += 1
                previousPixel = pixel
            }
        }
        return report
    }
}
