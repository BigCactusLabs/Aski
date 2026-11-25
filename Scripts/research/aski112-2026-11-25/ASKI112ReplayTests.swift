// ASKI-112 replay harness (research only, not part of the gate).
// Copy into Tests/AskiTests/ for a run, then remove it. See README.md in this directory.
import AskiToolSupport
import CoreGraphics
import CoreImage
import Darwin
import Foundation
import ImageIO
import Testing
@testable import Aski

@Suite struct ASKI112ReplayTests {
    static let env = ProcessInfo.processInfo.environment
    static let outDir = env["ASKI112_OUT"]
    static let mode = env["ASKI112_MODE"] ?? ""
    static let iterations = min(Int(env["ASKI112_N"] ?? "") ?? 300, 300)
    static let footprintLimit: UInt64 = 4 << 30
    /// ASKI112_RETAIN=1 keeps every decoded CGImage alive until the test ends.
    /// ASKI112_RETAIN=2 also keeps each read's CIImage and output CGImage alive, which
    /// run 1's loops (no autoreleasepool) did implicitly.
    static let retainLevel = Int(env["ASKI112_RETAIN"] ?? "") ?? 0
    static var retain: Bool { retainLevel > 0 }
    static var label: String { mode + (retainLevel > 0 ? "-retain\(retainLevel)" : "") }

    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    static var jpegPath: String {
        root.appending(path: "docs/Research/Corpus/nasa-occupancy-v1/assets/james-lovell-portrait.jpg").path
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    /// Decodes the corpus JPEG with the mode's ImageIO options. The hardware key is
    /// private ImageIO SPI, passed by string for this experiment only.
    static func decode() throws -> CGImage {
        var options: [CFString: Any] = [:]
        switch mode {
        case "d2": options[kCGImageSourceShouldCacheImmediately] = true
        case "d3false": options["kCGImageSourceUseHardwareAcceleration" as CFString] = false
        case "d3true": options["kCGImageSourceUseHardwareAcceleration" as CFString] = true
        default: break
        }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: jpegPath) as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        else { throw DemoRuntimeError.inputUnavailable(jpegPath) }
        return image
    }

    static func raw(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data else { return [] }
        return [UInt8](data as Data)
    }

    /// An owned bitmap with the decoded bytes and the same layout as the JPEG image.
    static func bitmapCopy(_ image: CGImage) -> CGImage {
        let copied = CFDataCreateCopy(nil, image.dataProvider!.data!)!
        return CGImage(
            width: image.width, height: image.height, bitsPerComponent: image.bitsPerComponent,
            bitsPerPixel: image.bitsPerPixel, bytesPerRow: image.bytesPerRow, space: image.colorSpace!,
            bitmapInfo: image.bitmapInfo, provider: CGDataProvider(data: copied)!, decode: nil,
            shouldInterpolate: image.shouldInterpolate, intent: image.renderingIntent)!
    }

    /// One Core Image read of the source: the test's background (.original, .fill) at
    /// 288x336 through the production BackgroundResolver and shared CIContext.
    static func background(_ image: CGImage, keep: ((CIImage, CGImage) -> Void)? = nil) -> [UInt8] {
        let extent = CGRect(x: 0, y: 0, width: 288, height: 336)
        let ci = BackgroundResolver().resolve(.original(image, sizing: .fill), outputExtent: extent)!
        let out = EffectsRenderEngine.shared.context.createCGImage(
            ci, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        keep?(ci, out)
        return raw(out)
    }

    static func digest(_ bytes: [UInt8]) -> String {
        // FNV-1a 64; stable across processes.
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in bytes { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return String(h, radix: 16)
    }

    static func compare(_ a: [UInt8], _ b: [UInt8]) -> String {
        guard a.count == b.count else { return "size \(a.count) vs \(b.count)" }
        var n = 0, maxDiff = 0
        for i in 0..<a.count where a[i] != b[i] { n += 1; maxDiff = max(maxDiff, abs(Int(a[i]) - Int(b[i]))) }
        return n == 0 ? "equal" : "\(n) bytes differ, max \(maxDiff)"
    }

    @Test(.enabled(if: outDir != nil && !mode.isEmpty)) func replay() throws {
        let dir = Self.outDir!
        var lines: [String] = ["mode=\(Self.label) n=\(Self.iterations)"]
        func emit(_ s: String) {
            lines.append(s)
            try? lines.joined(separator: "\n").write(toFile: dir + "/replay-\(Self.label).txt", atomically: true, encoding: .utf8)
        }
        let reused = Self.mode == "d4" ? try Self.decode() : nil
        var first: [UInt8] = []
        var previous = ""
        var switches: [String] = []
        var last: [UInt8] = []
        var decodedDigests = Set<String>()
        var kept: [CGImage] = []
        var keptReads: [(CIImage, CGImage)] = []
        for i in 0..<Self.iterations {
            try autoreleasepool {
                let image = try reused ?? Self.decode()
                if Self.retain { kept.append(image) }
                if i == 0 {
                    // The bitmap copy is read once, before any switch; bitmap-backed reads did not advance the count in run 1.
                    let copyOut = Self.background(Self.bitmapCopy(image))
                    try Data(copyOut).write(to: URL(fileURLWithPath: dir + "/\(Self.label)-copy.bin"))
                    emit("copy digest \(Self.digest(copyOut))")
                }
                let out = Self.background(image, keep: Self.retainLevel >= 2 ? { keptReads.append(($0, $1)) } : nil)
                if Self.mode == "d2" || i == 0 || i == Self.iterations - 1 { decodedDigests.insert(Self.digest(Self.raw(image))) }
                let d = Self.digest(out)
                if i == 0 { first = out; try Data(out).write(to: URL(fileURLWithPath: dir + "/\(Self.label)-pre.bin")) }
                if d != previous { switches.append("iter \(i): \(d)"); emit("iter \(i): output \(d)"); previous = d }
                last = out
            }
            let fp = Self.footprint()
            if fp > Self.footprintLimit { emit("ABORT: footprint \(fp >> 20) MB at iter \(i)"); Issue.record("footprint guard"); return }
            if i % 50 == 0 { emit("iter \(i): footprint \(fp >> 20) MB") }
        }
        try Data(last).write(to: URL(fileURLWithPath: dir + "/\(Self.label)-post.bin"))
        emit("decoded-byte digests seen: \(decodedDigests.sorted())")
        emit("first vs last output: \(Self.compare(first, last))")
        emit("output changes: \(switches.count - 1)")
        emit("kept images: \(kept.count), kept reads: \(keptReads.count)")
        emit("done")
    }
}
