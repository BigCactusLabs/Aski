import Aski
import CoreGraphics
import Foundation
import simd

public enum AccessFixtureError: Error, CustomStringConvertible {
    case nonSRGBGrid(RenderColorSpace)
    case emptyGrid(String)

    public var description: String {
        switch self {
        case .nonSRGBGrid(let colorSpace):
            "AccessLab rendered-grid scoring requires .sRGB, got \(colorSpace)"
        case .emptyGrid(let fixtureID):
            "fixture \(fixtureID) produced an empty ASCII grid"
        }
    }
}

public enum AccessFixtures {
    public static func allSamples(columns: Int) throws -> [AccessSample] {
        var samples: [AccessSample] = []
        for palette in AccessLabPalette.all {
            samples.append(contentsOf: paletteSamples(for: palette))
            samples.append(contentsOf: try renderedGridSamples(for: palette, columns: columns))
        }
        return samples
    }

    public static func paletteSamples(for palette: AccessLabPalette) -> [AccessSample] {
        let colors = palette.colors.enumerated().map { index, color in
            (name: "color-\(index)", encoded: color.components)
        }
        var samples: [AccessSample] = []
        for color in colors {
            samples.append(
                sample(
                    role: .colorOnBlack,
                    palette: palette,
                    fixtureID: "palette",
                    sampleA: color.name,
                    sampleB: "black",
                    encodedA: color.encoded,
                    encodedB: .zero
                ))
            samples.append(
                sample(
                    role: .colorOnWhite,
                    palette: palette,
                    fixtureID: "palette",
                    sampleA: color.name,
                    sampleB: "white",
                    encodedA: color.encoded,
                    encodedB: .one
                ))
        }
        if colors.count >= 2 {
            for left in 0..<(colors.count - 1) {
                for right in (left + 1)..<colors.count {
                    samples.append(
                        sample(
                            role: .palettePair,
                            palette: palette,
                            fixtureID: "palette",
                            sampleA: colors[left].name,
                            sampleB: colors[right].name,
                            encodedA: colors[left].encoded,
                            encodedB: colors[right].encoded
                        ))
                }
            }
        }
        return samples
    }

    public static func renderedGridSamples(
        for palette: AccessLabPalette,
        columns: Int
    ) throws -> [AccessSample] {
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: palette,
            colorSpace: .sRGB
        )
        let fixtures: [(id: String, image: CGImage)] = [
            ("hue-stripes", hueStripes()),
            ("neutral-ramp", neutralRamp()),
            ("edge-contrast", edgeContrast()),
        ]
        var samples: [AccessSample] = []
        for fixture in fixtures {
            let grid = converter.convert(fixture.image, columns: columns)
            samples.append(
                contentsOf: try adjacentCellSamples(
                    grid: grid,
                    palette: palette,
                    fixtureID: fixture.id
                ))
        }
        return samples
    }

    public static func adjacentCellSamples(
        grid: ASCIIGrid,
        palette: AccessLabPalette,
        fixtureID: String
    ) throws -> [AccessSample] {
        guard grid.colorSpace == .sRGB else {
            throw AccessFixtureError.nonSRGBGrid(grid.colorSpace)
        }
        guard grid.rows > 0, grid.columns > 1 else {
            throw AccessFixtureError.emptyGrid(fixtureID)
        }
        var samples: [AccessSample] = []
        for rowIndex in 0..<grid.rows {
            let row = grid.cells[rowIndex]
            guard row.count > 1 else { continue }
            for columnIndex in 0..<(row.count - 1) {
                let left = row[columnIndex]
                let right = row[columnIndex + 1]
                let sampleID = "\(fixtureID)-r\(rowIndex)-c\(columnIndex)-to-c\(columnIndex + 1)"
                samples.append(
                    AccessSample(
                        sampleID: sampleID,
                        comparisonRole: .renderedAdjacentCells,
                        surface: .renderedGrid,
                        paletteID: palette.id,
                        candidateID: palette.candidateID,
                        fixtureID: fixtureID,
                        sampleA: "\(left.character)-r\(rowIndex)-c\(columnIndex)",
                        sampleB: "\(right.character)-r\(rowIndex)-c\(columnIndex + 1)",
                        encodedA: left.displayColor,
                        encodedB: right.displayColor,
                        brightnessDelta: Double(abs(left.brightness - right.brightness))
                    ))
            }
        }
        return samples
    }

    private static func sample(
        role: AccessComparisonRole,
        palette: AccessLabPalette,
        fixtureID: String,
        sampleA: String,
        sampleB: String,
        encodedA: SIMD3<Float>,
        encodedB: SIMD3<Float>
    ) -> AccessSample {
        AccessSample(
            sampleID: "\(fixtureID)-\(palette.id)-\(role.rawValue)-\(sampleA)-\(sampleB)",
            comparisonRole: role,
            surface: .palette,
            paletteID: palette.id,
            candidateID: palette.candidateID,
            fixtureID: fixtureID,
            sampleA: sampleA,
            sampleB: sampleB,
            encodedA: encodedA,
            encodedB: encodedB,
            brightnessDelta: Double(
                abs(
                    AccessScoring.relativeLuminance(encodedSRGB: encodedA)
                        - AccessScoring.relativeLuminance(encodedSRGB: encodedB)
                ))
        )
    }

    private static func hueStripes(width: Int = 96, height: Int = 48) -> CGImage {
        let stripes: [SIMD3<UInt8>] = [
            SIMD3<UInt8>(255, 0, 0),
            SIMD3<UInt8>(0, 255, 0),
            SIMD3<UInt8>(0, 0, 255),
            SIMD3<UInt8>(0, 255, 255),
            SIMD3<UInt8>(255, 0, 255),
            SIMD3<UInt8>(255, 255, 0),
        ]
        return image(width: width, height: height) { x, _ in
            stripes[min(stripes.count - 1, x * stripes.count / width)]
        }
    }

    private static func neutralRamp(width: Int = 96, height: Int = 48) -> CGImage {
        image(width: width, height: height) { x, _ in
            let value = UInt8((x * 255) / max(1, width - 1))
            return SIMD3<UInt8>(value, value, value)
        }
    }

    private static func edgeContrast(width: Int = 96, height: Int = 48) -> CGImage {
        image(width: width, height: height) { x, y in
            let checker = ((x / 12) + (y / 12)) % 2 == 0
            return checker ? SIMD3<UInt8>(245, 245, 245) : SIMD3<UInt8>(20, 20, 20)
        }
    }

    private static func image(
        width: Int,
        height: Int,
        colorAt: (Int, Int) -> SIMD3<UInt8>
    ) -> CGImage {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color = colorAt(x, y)
                let offset = (y * width + x) * 4
                buffer[offset + 0] = color.x
                buffer[offset + 1] = color.y
                buffer[offset + 2] = color.z
                buffer[offset + 3] = 255
            }
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(buffer) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
