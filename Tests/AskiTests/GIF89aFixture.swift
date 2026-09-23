import CoreGraphics
import Foundation
import ImageIO
import Testing

/// A minimal GIF89a writer used ONLY by tests, so no binary fixtures are checked
/// in. Supports the three things `CGImageDestination` will NOT emit and our
/// decoder tests need: per-frame sub-rect placement + offset, per-frame disposal
/// method, and an explicit OR ABSENT Netscape loop extension.
struct GIF89aFixture {
    struct Frame {
        var left: Int
        var top: Int
        var width: Int
        var height: Int
        /// Row-major (top-left origin) color indices into `colorTable`.
        var indices: [UInt8]
        /// Per-frame delay in GIF units (1/100 s).
        var delayCentiseconds: Int
        /// GIF disposal method: 1 = do-not-dispose, 2 = restore-to-background.
        var disposal: Int
    }

    /// Composed canvas (Logical Screen) size.
    var canvasWidth: Int
    var canvasHeight: Int
    /// Up to 256 RGB entries; padded internally to a power-of-two table.
    var colorTable: [(r: UInt8, g: UInt8, b: UInt8)]
    /// Background color index recorded in the Logical Screen Descriptor.
    var backgroundColorIndex: UInt8
    /// nil = write NO Netscape extension (ImageIO reports loopCount == 1).
    /// Otherwise the RAW Netscape iteration count: 0 = infinite; a raw value N
    /// reads back as N+1 total plays (the documented read quirk).
    var netscapeLoop: Int?
    var frames: [Frame]

    func encode() -> Data {
        var out = Data()
        out.append(contentsOf: Array("GIF89a".utf8))

        // Color-table sizing. GIF's minimum LZW code size is 2 (floor `bits` at 2).
        let entryCount = max(2, colorTable.count)
        var bits = 1
        while (1 << bits) < entryCount { bits += 1 }
        bits = max(2, bits)
        let tableEntries = 1 << bits
        let minCodeSize = bits
        let sizeField = bits - 1  // table holds 2^(sizeField + 1) entries

        // Logical Screen Descriptor.
        appendUInt16LE(&out, canvasWidth)
        appendUInt16LE(&out, canvasHeight)
        out.append(UInt8(0x80 | (sizeField << 4) | sizeField))  // GCT present | colorRes | sort=0 | size
        out.append(backgroundColorIndex)
        out.append(0x00)  // pixel aspect ratio

        // Global Color Table (padded to a power of two).
        for i in 0..<tableEntries {
            if i < colorTable.count {
                out.append(colorTable[i].r)
                out.append(colorTable[i].g)
                out.append(colorTable[i].b)
            } else {
                out.append(contentsOf: [0, 0, 0])
            }
        }

        // Netscape looping extension (optional).
        if let loop = netscapeLoop {
            out.append(contentsOf: [0x21, 0xFF, 0x0B])
            out.append(contentsOf: Array("NETSCAPE2.0".utf8))
            out.append(contentsOf: [0x03, 0x01])
            appendUInt16LE(&out, loop)
            out.append(0x00)
        }

        for frame in frames {
            // Graphic Control Extension: disposal method + delay. No transparency.
            out.append(contentsOf: [0x21, 0xF9, 0x04])
            out.append(UInt8((frame.disposal & 0x07) << 2))
            appendUInt16LE(&out, frame.delayCentiseconds)
            out.append(0x00)  // transparent color index (unused)
            out.append(0x00)  // block terminator

            // Image Descriptor (no local color table, no interlace).
            out.append(0x2C)
            appendUInt16LE(&out, frame.left)
            appendUInt16LE(&out, frame.top)
            appendUInt16LE(&out, frame.width)
            appendUInt16LE(&out, frame.height)
            out.append(0x00)

            // Image Data: min code size + LZW sub-blocks + terminator.
            out.append(UInt8(minCodeSize))
            let lzw = Self.lzwEncode(frame.indices, minCodeSize: minCodeSize)
            var offset = 0
            while offset < lzw.count {
                let chunk = min(255, lzw.count - offset)
                out.append(UInt8(chunk))
                out.append(contentsOf: lzw[offset..<(offset + chunk)])
                offset += chunk
            }
            out.append(0x00)  // image data block terminator
        }

        out.append(0x3B)  // trailer
        return out
    }

    private func appendUInt16LE(_ data: inout Data, _ value: Int) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    /// GIF-variant LZW. The widen rule is load-bearing (addendum §Open risks):
    /// widen AFTER assigning the entry whose code value == 2^codeSize, checked on
    /// the value being assigned BEFORE the next-code counter increments. Widening
    /// on the post-increment value desyncs the bitstream one code early.
    static func lzwEncode(_ indices: [UInt8], minCodeSize: Int) -> [UInt8] {
        let clearCode = 1 << minCodeSize
        let endCode = clearCode + 1
        var codeSize = minCodeSize + 1
        var dictionary: [Int: Int] = [:]
        var next = clearCode + 2

        var bitBuffer = 0
        var bitCount = 0
        var bytes: [UInt8] = []
        func emit(_ code: Int) {
            bitBuffer |= code << bitCount
            bitCount += codeSize
            while bitCount >= 8 {
                bytes.append(UInt8(bitBuffer & 0xFF))
                bitBuffer >>= 8
                bitCount -= 8
            }
        }
        func flush() {
            if bitCount > 0 {
                bytes.append(UInt8(bitBuffer & 0xFF))
                bitBuffer = 0
                bitCount = 0
            }
        }

        emit(clearCode)
        guard let first = indices.first else {
            emit(endCode)
            flush()
            return bytes
        }
        var prefix = Int(first)
        for index in indices.dropFirst() {
            let k = Int(index)
            let key = (prefix << 8) | k
            if let combined = dictionary[key] {
                prefix = combined
            } else {
                emit(prefix)
                if next < 4096 {
                    let assigned = next  // value being assigned (pre-increment)
                    dictionary[key] = assigned
                    next += 1
                    if assigned == (1 << codeSize) && codeSize < 12 { codeSize += 1 }
                } else {
                    // Table full (4095 assigned): emit clear and reset. Not reached
                    // by the tiny fixtures here, but kept for correctness.
                    emit(clearCode)
                    dictionary.removeAll(keepingCapacity: true)
                    codeSize = minCodeSize + 1
                    next = clearCode + 2
                }
                prefix = k
            }
        }
        emit(prefix)
        emit(endCode)
        flush()
        return bytes
    }
}

/// Pixel-reading helpers shared by the GIF decoder/lab tests.
enum GIFPixelReader {
    /// Composites `image` over opaque black into a top-left-origin RGBA8 buffer,
    /// matching how a player (and the §Verification probe) sees a decoded frame:
    /// transparent / restored regions read as opaque black.
    static func rgba(_ image: CGImage) -> (pixels: [UInt8], width: Int, height: Int) {
        let w = image.width
        let h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        pixels.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (pixels, w, h)
    }

    /// RGBA at top-left-origin (x, y). This bitmap context lays out buffer row 0 as
    /// the TOP scanline — validated against a known-orientation CGImage (data row 0
    /// = top) round-tripped through `rgba` — so the row index is `y` directly, with
    /// NO vertical flip. (A `height - 1 - y` flip silently inverts placement; it
    /// passes only on vertically symmetric fixtures, which masked it initially.)
    static func pixel(
        _ buffer: (pixels: [UInt8], width: Int, height: Int),
        x: Int,
        y: Int
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let row = y
        let i = (row * buffer.width + x) * 4
        return (buffer.pixels[i], buffer.pixels[i + 1], buffer.pixels[i + 2], buffer.pixels[i + 3])
    }
}

/// Asserts the composited pixel at top-left (x, y) is approximately (r, g, b).
func expectColor(
    _ image: CGImage,
    x: Int,
    y: Int,
    _ r: UInt8,
    _ g: UInt8,
    _ b: UInt8,
    tolerance: Int = 24
) {
    let buffer = GIFPixelReader.rgba(image)
    let p = GIFPixelReader.pixel(buffer, x: x, y: y)
    #expect(abs(Int(p.r) - Int(r)) <= tolerance, "R@(\(x),\(y))=\(p.r) expected ~\(r)")
    #expect(abs(Int(p.g) - Int(g)) <= tolerance, "G@(\(x),\(y))=\(p.g) expected ~\(g)")
    #expect(abs(Int(p.b) - Int(b)) <= tolerance, "B@(\(x),\(y))=\(p.b) expected ~\(b)")
}

/// Standard 4-entry palette used by the fixtures: 0=red, 1=green, 2=blue, 3=black.
enum GIFFixturePalette {
    static let table: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (255, 0, 0), (0, 255, 0), (0, 0, 255), (0, 0, 0),
    ]
}

@Suite struct GIF89aFixtureTests {
    /// A 2-frame fixture proves placement/composition + LZW correctness + that
    /// ImageIO reads the UNCLAMPED delays we wrote (2cs and 20cs, not clamped to
    /// 0.1s). Frame 0: full 4x4 red. Frame 1: 2x2 green at offset (1,1).
    @Test func writesGifImageIODecodesCompositedFramesAndUnclampedDelays() throws {
        let fixture = GIF89aFixture(
            canvasWidth: 4,
            canvasHeight: 4,
            colorTable: GIFFixturePalette.table,
            backgroundColorIndex: 3,
            netscapeLoop: nil,
            frames: [
                .init(
                    left: 0, top: 0, width: 4, height: 4,
                    indices: [UInt8](repeating: 0, count: 16),
                    delayCentiseconds: 2, disposal: 1),
                .init(
                    left: 1, top: 1, width: 2, height: 2,
                    indices: [UInt8](repeating: 1, count: 4),
                    delayCentiseconds: 20, disposal: 1),
            ]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GIF89aFixtureTests-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: url) }
        try fixture.encode().write(to: url)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)

        let frame0 = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(frame0.width == 4 && frame0.height == 4)
        expectColor(frame0, x: 0, y: 0, 255, 0, 0)
        expectColor(frame0, x: 3, y: 3, 255, 0, 0)

        let frame1 = try #require(CGImageSourceCreateImageAtIndex(source, 1, nil))
        #expect(frame1.width == 4 && frame1.height == 4)  // composed full canvas
        expectColor(frame1, x: 0, y: 0, 255, 0, 0)  // prior canvas content
        expectColor(frame1, x: 1, y: 1, 0, 255, 0)  // green sub-rect at its offset
        expectColor(frame1, x: 3, y: 3, 255, 0, 0)

        // Unclamped delays survive (2cs => 0.02s would clamp to 0.1s if misread).
        for (index, expected) in [(0, 0.02), (1, 0.2)] {
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
            let gif = try #require(props[kCGImagePropertyGIFDictionary] as? [CFString: Any])
            let unclamped = try #require(gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            #expect(abs(unclamped - expected) < 0.005)
        }
    }
}
