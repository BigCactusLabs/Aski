@_spi(AskiResearch) import Aski
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct InspectionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) { self.message = message }
}

struct Cell {
    let lanes: [SIMD4<Float>]
    let adjustedL: Float
    let glyph: ASCIICell
    var zero: Bool { lanes.allSatisfy { $0 == .zero } }
    var blank: Bool { glyph.character == " " }
}

@main
struct Inspect {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            throw InspectionError("Usage: Inspect <nasa-occupancy-v1/assets> <output-directory>")
        }
        let fixtures = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: arguments[2], isDirectory: true)

        let diagnostic = "diagnostic-ramp"
        let ramp = try makeRamp()
        try png(ramp).write(to: output.appendingPathComponent("\(diagnostic)-source.png"))
        try inspect(ramp, id: diagnostic, output: output, isDiagnostic: true)

        for id in ["rcs-function-diagram", "spacecraft-attitude-diagram", "james-lovell-portrait"] {
            let jpeg = fixtures.appendingPathComponent("\(id).jpg")
            guard let file = CGImageSourceCreateWithURL(jpeg as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(file, 0, nil)
            else {
                throw InspectionError("Cannot decode \(jpeg.lastPathComponent)")
            }
            try FileManager.default.copyItem(
                at: jpeg, to: output.appendingPathComponent("\(id)-source.jpg"))
            try inspect(image, id: id, output: output, isDiagnostic: false)
        }
    }

    private static func inspect(_ source: CGImage, id: String, output: URL, isDiagnostic: Bool) throws {
        let preset = VesperPreset.canonical
        let converter = preset.makeConverter()
        guard let geometry = converter.samplingGeometry(source, columns: preset.columns),
            let query = converter.cellQueryDescriptors(source, columns: preset.columns),
            query.supportsShapeDescriptor, query.columns == geometry.columns, query.rows == geometry.rows,
            query.grid.columns == geometry.columns, query.grid.rows == geometry.rows,
            query.lanesPerCell == 15, geometry.droppedX == 0, geometry.droppedY == 0
        else {
            throw InspectionError("Missing or inconsistent two-dimensional sampling geometry for \(id)")
        }

        let canonical = preset.render(source)
        let reflected = query.grid.renderImage(
            font: preset.font, backgroundColor: preset.backgroundColor, scale: preset.scale,
            preserveSourceAspect: true)
        guard canonical.width > 1, canonical.height > 1 else {
            throw InspectionError("Canonical render returned the fallback image for \(id)")
        }
        let canonicalPNG = try png(canonical)
        let reflectedPNG = try png(reflected)
        let pngEqual = canonicalPNG == reflectedPNG
        let canonicalPixels = canonical.dataProvider?.data as Data?
        let reflectedPixels = reflected.dataProvider?.data as Data?
        let pixelDataEqual =
            canonical.width == reflected.width && canonical.height == reflected.height
            && canonical.bytesPerRow == reflected.bytesPerRow
            && canonical.bitsPerComponent == reflected.bitsPerComponent
            && canonical.bitsPerPixel == reflected.bitsPerPixel
            && canonical.bitmapInfo == reflected.bitmapInfo
            && canonical.colorSpace == reflected.colorSpace
            && canonicalPixels != nil && canonicalPixels == reflectedPixels
        try canonicalPNG.write(to: output.appendingPathComponent("\(id)-canonical.png"))
        if !pngEqual {
            try reflectedPNG.write(to: output.appendingPathComponent("\(id)-grid-rerender.png"))
        }

        let cells = query.grid.cells.enumerated().map { row, glyphs in
            glyphs.enumerated().map { column, glyph in
                Cell(
                    lanes: query.lanes(row: row, column: column),
                    adjustedL: query.adjustedL(row: row, column: column),
                    glyph: glyph)
            }
        }
        var mask: [UInt8] = []
        var edges = "zero_row,zero_col,zero_x,zero_y,zero_blank,zero_adjusted_l_bits,"
        edges += "nonzero_row,nonzero_col,nonzero_x,nonzero_y,nonzero_blank,nonzero_adjusted_l_bits,"
        edges += "zero_lanes_bits,nonzero_lanes_bits\n"
        var edgeCount = 0

        for row in 0..<geometry.rows {
            for column in 0..<geometry.columns {
                let cell = cells[row][column]
                // White: zero/space, red: zero/glyph, blue: nonzero/space, black: nonzero/glyph.
                switch (cell.zero, cell.blank) {
                case (true, true): mask.append(contentsOf: [255, 255, 255, 255])
                case (true, false): mask.append(contentsOf: [255, 0, 0, 255])
                case (false, true): mask.append(contentsOf: [0, 128, 255, 255])
                case (false, false): mask.append(contentsOf: [0, 0, 0, 255])
                }

                for (nextRow, nextColumn) in [(row, column + 1), (row + 1, column)] {
                    guard nextRow < geometry.rows, nextColumn < geometry.columns else { continue }
                    let neighbor = cells[nextRow][nextColumn]
                    guard cell.zero != neighbor.zero else { continue }

                    let a = endpoint(cell, row: row, column: column, geometry: geometry)
                    let b = endpoint(neighbor, row: nextRow, column: nextColumn, geometry: geometry)
                    if cell.zero {
                        edges += "\(a),\(b),\(bits(cell)),\(bits(neighbor))\n"
                    } else {
                        edges += "\(b),\(a),\(bits(neighbor)),\(bits(cell))\n"
                    }
                    edgeCount += 1
                }
            }
        }

        try edges.write(
            to: output.appendingPathComponent("\(id)-edges.csv"), atomically: true, encoding: .utf8)
        let maskImage = try rgba(mask, width: geometry.columns, height: geometry.rows, space: CGColorSpace.sRGB)
        try png(maskImage).write(to: output.appendingPathComponent("\(id)-mask.png"))

        print("\(id): source=\(source.width)x\(source.height) canonical=\(canonical.width)x\(canonical.height)")
        print(
            "  grid=\(geometry.columns)x\(geometry.rows) cell=\(geometry.cellWidth)x\(geometry.cellHeight)"
                + " lattice=\(geometry.thumbnailWidth)x\(geometry.thumbnailHeight) candidate_edges=\(edgeCount)")
        print("  png_equal=\(pngEqual) pixel_layout_and_provider_bytes_equal=\(pixelDataEqual)")
        print("  canonical_png_sha256=\(SHA256.hash(data: canonicalPNG))")
        print("  grid_rerender_png_sha256=\(SHA256.hash(data: reflectedPNG))")

        if isDiagnostic {
            let middle = cells[geometry.rows / 2]
            guard let firstZero = middle.firstIndex(where: { $0.zero }),
                let lastInk = middle.lastIndex(where: { !$0.zero && !$0.blank }),
                lastInk < firstZero,
                middle[firstZero...].allSatisfy({ $0.zero && $0.blank }),
                edgeCount > 0
            else {
                throw InspectionError("Positive diagnostic did not expose the expected transition")
            }
            print("  center_row_last_nonzero_ink=\(lastInk) center_row_first_zero_blank=\(firstZero)")
        }
    }

    private static func endpoint(_ cell: Cell, row: Int, column: Int, geometry: SamplingGeometry) -> String {
        let x = column * geometry.cellWidth
        let y = row * geometry.cellHeight
        return "\(row),\(column),\(x),\(y),\(cell.blank),\(String(cell.adjustedL.bitPattern, radix: 16))"
    }

    private static func bits(_ cell: Cell) -> String {
        cell.lanes.flatMap { [$0.x, $0.y, $0.z, $0.w] }
            .map { String($0.bitPattern, radix: 16) }
            .joined(separator: " ")
    }

    private static func makeRamp() throws -> CGImage {
        let width = 152
        let row: [UInt8] = (0..<width).flatMap { x in
            let gray = UInt8(224 + 31 * x / (width - 1))
            return [gray, gray, gray, 255]
        }
        let pixels = Array(repeating: row, count: width).flatMap { $0 }
        return try rgba(pixels, width: width, height: width, space: CGColorSpace.displayP3)
    }

    private static func rgba(_ pixels: [UInt8], width: Int, height: Int, space: CFString) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: space),
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: [CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), .byteOrder32Big],
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            throw InspectionError("Cannot make \(width)x\(height) RGBA image")
        }
        return image
    }

    private static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else {
            throw InspectionError("Cannot open PNG encoder")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw InspectionError("Cannot encode PNG")
        }
        return data as Data
    }
}
