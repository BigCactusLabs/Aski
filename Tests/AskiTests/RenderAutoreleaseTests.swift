import CoreGraphics
import Foundation
import Testing
@testable import Aski

/// The synchronous render paths create autoreleased Core Text, Core Graphics and
/// Core Image temporaries. A caller that renders in a loop on a thread that does
/// not drain a pool between iterations (a GCD worker, a Swift concurrency
/// thread, a long-lived `Thread`) kept every render's temporaries alive until
/// the loop ended: about 6 MB per plain render and 9 MB per effects render for
/// a 60×80 grid. Each render entry point now drains its own pool.
///
/// These tests render on a thread that is held alive after the render, so the
/// thread's implicit pool cannot drain, and check that the background image
/// the render borrowed is no longer retained. They cover the Core Image paths;
/// the plain Core Text path has no borrowed object to observe and is covered
/// by the footprint measurement recorded in CHANGELOG.md.
@Suite struct RenderAutoreleaseTests {
    private final class ReleaseFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var released = false
        func markReleased() { lock.withLock { released = true } }
        var isReleased: Bool { lock.withLock { released } }
    }

    /// Runs `body` on a new thread and evaluates `check` while that thread is
    /// still alive, before its implicit autorelease pool can drain.
    private func whileRenderThreadIsAlive<T: Sendable>(
        _ body: @escaping @Sendable () -> Void,
        check: () -> T
    ) -> T {
        let rendered = DispatchSemaphore(value: 0)
        let hold = DispatchSemaphore(value: 0)
        let thread = Thread {
            body()
            rendered.signal()
            hold.wait()
        }
        thread.start()
        rendered.wait()
        let result = check()
        hold.signal()
        return result
    }

    private static func gradient(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<width {
            context.setFillColor(gray: CGFloat(x) / CGFloat(width), alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return context.makeImage()!
    }

    /// An image whose backing bytes report their release through `flag`.
    private static func trackedImage(_ flag: ReleaseFlag) -> CGImage {
        let side = 16
        let byteCount = side * side * 4
        let storage = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 1)
        storage.initializeMemory(as: UInt8.self, repeating: 255, count: byteCount)
        let provider = CGDataProvider(
            dataInfo: Unmanaged.passRetained(flag).toOpaque(), data: storage, size: byteCount,
            releaseData: { info, data, _ in
                data.deallocate()
                if let info { Unmanaged<ReleaseFlag>.fromOpaque(info).takeRetainedValue().markReleased() }
            })!
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

    @Test func effectsRenderReleasesItsBackgroundImageBeforeReturning() {
        let grid = DefaultConverter().convert(Self.gradient(width: 64, height: 64), columns: 16)
        let flag = ReleaseFlag()
        let released = whileRenderThreadIsAlive {
            let background = Self.trackedImage(flag)
            _ = grid.renderImage(
                font: .courierPrime(size: 8), backgroundColor: Self.black, scale: 1,
                composition: CompositionOptions(background: .original(background, sizing: .fill)))
        } check: {
            flag.isReleased
        }
        #expect(released)
    }

    @Test func tileEffectsRenderReleasesItsBackgroundImageBeforeReturning() {
        let grid = TileGridConverter().convert(Self.gradient(width: 64, height: 64), columns: 16)
        let flag = ReleaseFlag()
        let released = whileRenderThreadIsAlive {
            let background = Self.trackedImage(flag)
            _ = grid.renderImage(
                scale: 4, composition: CompositionOptions(background: .original(background, sizing: .fill)))
        } check: {
            flag.isReleased
        }
        #expect(released)
    }
}
