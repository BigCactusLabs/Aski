@_spi(AskiResearch) import Aski
import CoreGraphics
import CoreImage
import CryptoKit
import Darwin
import Foundation
import ImageIO
import Testing
@testable import AskiHDRLab

@Suite struct BackendHDRInputParityTests {
    private static let outputVariable = "ASKI_HDR_BOUNDARY_OUTPUT"
    private static let passes = 1...3

    @Test(.enabled(if: ProcessInfo.processInfo.environment[BackendHDRInputParityTests.outputVariable] != nil))
    func captureHDRBoundary() throws {
        let path = try #require(ProcessInfo.processInfo.environment[Self.outputVariable])
        try #require(path.hasPrefix("/"))
        let output = URL(fileURLWithPath: path, isDirectory: true)
        // mkdir is exclusive. A pre-existing directory or symlink cannot become a capture.
        let result = output.path.withCString { mkdir($0, 0o700) }
        try #require(result == 0, "Capture requires a new directory with an existing parent")

        let command = try HDREvaluateCommand.parse(["--output-dir", path])
        let color = try #require(UInt32(command.backgroundHex.dropFirst(), radix: 16))
        try #require(command.backgroundHex.hasPrefix("#") && command.backgroundHex.count == 7)
        // Match HDRLabCLI.cgColor(fromHex:): opaque transfer-encoded sRGB.
        let background = CGColor(
            srgbRed: CGFloat((color >> 16) & 255) / 255, green: CGFloat((color >> 8) & 255) / 255,
            blue: CGFloat(color & 255) / 255, alpha: 1)
        let scale: CGFloat = 1
        let preserveSourceAspect = false
        let font = ASCIIFont.system(size: HDRLabCLI.fontSize)
        let fixtures = HDRFixtures.all(columns: command.columns)
        let context = CIContext()
        let sweep = HDRLabCLI.kSweep
        try #require(fixtures.count == 9 && Set(fixtures.map(\.id)).count == 9)
        try #require(sweep == [0, 1, 2, 4])

        var cases: [[String: Any]] = []
        var measurements = Array(repeating: [HDRMeasurement](), count: Self.passes.count)
        for fixture in fixtures {
            let sdr = fixture.grid.renderImage(font: font, backgroundColor: background, scale: scale, preserveSourceAspect: preserveSourceAspect)
            let gamut = fixture.gamut == .sRGB ? "sRGB" : "displayP3"
            let gamutName = fixture.gamut == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3
            let gamutSpace = CGColorSpace(name: gamutName) ?? CGColorSpaceCreateDeviceRGB()
            for k in sweep {
                let emission = EmissionOptions(
                    k: k, threshold: HDRLabCLI.emissionThreshold, maxHeadroom: HDRLabCLI.emissionMaxHeadroom,
                    source: fixture.emissionSource)
                let hdr = try #require(
                    fixture.grid.renderExtendedRangeImage(
                        font: font, backgroundColor: background, scale: scale, preserveSourceAspect: preserveSourceAspect, emission: emission))
                try #require(hdr.width == sdr.width && hdr.height == sdr.height)
                try #require(sdr.bitsPerComponent == 8 && sdr.bitsPerPixel == 32)
                try #require(hdr.bitsPerComponent == 16 && hdr.bitsPerPixel == 64)

                for pass in Self.passes {
                    let sdrInput = try Self.fingerprint(sdr)
                    let hdrInput = try Self.fingerprint(hdr)
                    let floatStats = HDRArtifacts.floatStats(hdr, maxHeadroom: HDRLabCLI.emissionMaxHeadroom)
                    let file = "\(fixture.id)-k\(Int(k))-r\(pass).heic"
                    let url = output.appendingPathComponent(file)
                    try HDRArtifacts.writeGainMapHEIC(sdr: sdr, hdr: hdr, gamutSpace: gamutSpace, ciContext: context, to: url)
                    let measurement = HDRMeasurement(
                        fixtureID: fixture.id, gamut: gamut, expectation: fixture.expectation.rawValue,
                        k: k, threshold: HDRLabCLI.emissionThreshold, maxHeadroom: HDRLabCLI.emissionMaxHeadroom,
                        contentHeadroom: HDRArtifacts.contentHeadroom(ofHEIC: url),
                        hdrMaxChannel: floatStats.maxChannel,
                        g1MeanDiff: HDRArtifacts.sdrBaseMeanDiff(heic: url, vs: sdr),
                        g2MeanDiff: HDRArtifacts.toneMappedMeanDiff(heic: url, gamutSpace: gamutSpace, ciContext: context, vs: sdr),
                        floatClean: !floatStats.hasNaNOrInf && !floatStats.exceedsCeiling,
                        heicBytes: try Data(contentsOf: url).count)
                    measurements[pass - 1].append(measurement)
                    cases.append([
                        "fixture": fixture.id, "k": k, "repetition": pass, "file": file,
                        "sdr": sdrInput, "hdr": hdrInput,
                        "gamut": gamut, "encoderColorSpace": Self.colorSpace(gamutSpace),
                        "expectation": measurement.expectation,
                        "measurement": [
                            "contentHeadroom": measurement.contentHeadroom, "hdrMaxChannel": measurement.hdrMaxChannel,
                            "g1MeanDiff": measurement.g1MeanDiff, "g2MeanDiff": measurement.g2MeanDiff,
                            "floatClean": measurement.floatClean, "heicBytes": measurement.heicBytes,
                        ],
                    ])
                }
            }
        }

        let gateResults = measurements.enumerated().map { index, rows in
            let verdict = HDRGates.evaluate(rows)
            return [
                "repetition": index + 1, "rowCount": rows.count,
                "g1Pass": verdict.g1Pass, "g2Pass": verdict.g2Pass, "g3Pass": verdict.g3Pass, "g4Pass": verdict.g4Pass,
                "detail": verdict.detail,
            ] as [String: Any]
        }
        try Self.write(gateResults, to: output.appendingPathComponent("gates.json"))
        for gate in gateResults {
            for name in ["g1Pass", "g2Pass", "g3Pass", "g4Pass"] {
                try #require(gate[name] as? Bool == true, "\(gate["detail"] ?? "")")
            }
        }

        // Decode for diagnosis only, after the production code has finished encoding and grading.
        let decodeSpace = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let decoder = CIContext(options: [.workingColorSpace: decodeSpace])
        for index in cases.indices {
            let file = try #require(cases[index]["file"] as? String)
            let url = output.appendingPathComponent(file)
            cases[index]["encoded"] = try Self.encodedOutput(url, decoder: decoder, space: decodeSpace)
        }
        try Self.write(
            [
                "schemaVersion": 1, "complete": true,
                "captureID": UUID().uuidString, "processID": ProcessInfo.processInfo.processIdentifier,
                "configuration": [
                    "columns": command.columns, "fontSize": HDRLabCLI.fontSize, "scale": scale,
                    "backgroundHex": command.backgroundHex, "backgroundAlpha": background.alpha,
                    "preserveSourceAspect": preserveSourceAspect,
                    "threshold": HDRLabCLI.emissionThreshold, "maxHeadroom": HDRLabCLI.emissionMaxHeadroom,
                    "kSweep": sweep, "repetitions": Self.passes.count,
                    "encoder": "CIContext.heifRepresentation",
                    "encoderFormat": "RGBA8", "encoderOptions": ["hdrImage"],
                    "decodedPixelFormat": "RGBAf", "decodedColorSpace": "extendedLinearSRGB",
                ],
                "gateResults": gateResults, "cases": cases,
            ],
            to: output.appendingPathComponent("completion.json"))
    }

    private static func fingerprint(_ image: CGImage) throws -> [String: Any] {
        let (rowBits, rowOverflow) = image.width.multipliedReportingOverflow(by: image.bitsPerPixel)
        let (strideBytes, strideOverflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        try #require(!rowOverflow && !strideOverflow && image.height > 0 && rowBits > 0 && rowBits.isMultiple(of: 8))
        let activeBytes = rowBits / 8
        try #require(image.bytesPerRow >= activeBytes)
        let data = try #require(image.dataProvider?.data)
        try #require(CFDataGetLength(data) >= strideBytes)
        let base = try #require(CFDataGetBytePtr(data))
        let space = try #require(image.colorSpace)
        var digest = SHA256()
        for y in 0..<image.height {
            // Padding beyond the final active pixel is outside the input fingerprint.
            digest.update(bufferPointer: UnsafeRawBufferPointer(start: base + y * image.bytesPerRow, count: activeBytes))
        }
        var fingerprint: [String: Any] = [
            "activeSHA256": hex(digest.finalize()), "activeBytesPerRow": activeBytes,
            "width": image.width, "height": image.height, "bytesPerRow": image.bytesPerRow,
            "bitsPerComponent": image.bitsPerComponent, "bitsPerPixel": image.bitsPerPixel,
            "alphaInfo": image.alphaInfo.rawValue, "bitmapInfo": image.bitmapInfo.rawValue,
            "renderingIntent": image.renderingIntent.rawValue, "interpolate": image.shouldInterpolate,
            "contentHeadroom": image.contentHeadroom, "shouldToneMap": image.shouldToneMap,
            "pixelFormat": image.pixelFormatInfo.rawValue, "isMask": image.isMask,
            "colorSpace": colorSpace(space),
        ]
        if let decode = image.decode {
            fingerprint["decode"] = Array(UnsafeBufferPointer(start: decode, count: 2 * space.numberOfComponents))
        } else {
            fingerprint["decode"] = NSNull()
        }
        return fingerprint
    }

    private static func colorSpace(_ space: CGColorSpace) -> [String: Any] {
        let name = space.name.map { $0 as String }
        let icc = space.copyICCData().map { ($0 as Data).base64EncodedString() }
        return [
            "model": space.model.rawValue, "components": space.numberOfComponents,
            "name": (name as Any?) ?? NSNull(), "iccBase64": (icc as Any?) ?? NSNull(),
        ]
    }

    private static func encodedOutput(_ url: URL, decoder: CIContext, space: CGColorSpace) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil))
        let sdr = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let hdr = try #require(CIImage(contentsOf: url, options: [.expandToHDR: true]))
        return [
            "sha256": hex(SHA256.hash(data: data)), "imageCount": CGImageSourceGetCount(source),
            "type": (CGImageSourceGetType(source).map { $0 as String } as Any?) ?? NSNull(),
            "properties": try jsonProperty(properties),
            "sdr": try decodedPixels(CIImage(cgImage: sdr), decoder: decoder, space: space),
            "hdr": try decodedPixels(hdr, decoder: decoder, space: space),
        ]
    }

    private static func decodedPixels(_ image: CIImage, decoder: CIContext, space: CGColorSpace) throws -> [String: Any] {
        let extent = image.extent
        let width = try #require(Int(exactly: extent.width))
        let height = try #require(Int(exactly: extent.height))
        let (area, areaOverflow) = width.multipliedReportingOverflow(by: height)
        let (samples, sampleOverflow) = area.multipliedReportingOverflow(by: 4)
        let (byteCount, bytesOverflow) = samples.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        try #require(width > 0 && height > 0 && !areaOverflow && !sampleOverflow && !bytesOverflow)
        var pixels = [Float](repeating: .nan, count: samples)
        pixels.withUnsafeMutableBytes { bytes in
            decoder.render(
                image, toBitmap: bytes.baseAddress!, rowBytes: byteCount / height, bounds: extent,
                format: .RGBAf, colorSpace: space)
        }
        let pixelsAreFinite = pixels.allSatisfy(\.isFinite)
        try #require(pixelsAreFinite)
        let digest = pixels.withUnsafeBytes {
            var hash = SHA256()
            hash.update(bufferPointer: $0)
            return hex(hash.finalize())
        }
        return ["width": width, "height": height, "rgbaFloat32SHA256": digest]
    }

    private static func jsonProperty(_ value: Any) throws -> Any {
        switch value {
        case let properties as [String: Any]: try properties.mapValues(jsonProperty)
        case let array as [Any]: try array.map(jsonProperty)
        case let data as Data: ["dataBase64": data.base64EncodedString()]
        case let date as Date: ["dateSecondsSinceReference": date.timeIntervalSinceReferenceDate]
        case is String, is NSNumber, is NSNull: value
        default: throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Unsupported ImageIO property"))
        }
    }

    private static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func write(_ object: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}
