import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

let args = CommandLine.arguments
precondition(args.count == 3)
let url = URL(fileURLWithPath: args[1])
let expected = Int(args[2])!
let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
let count = CGImageSourceGetCount(source)
precondition(count == expected)
var hashes: [String] = []
for index in 0..<count {
    let digest = autoreleasepool { () -> String in
        let image = CGImageSourceCreateImageAtIndex(source, index, nil)!
        precondition(image.width == 640 && image.height == 360)
        let context = CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8,
                                bytesPerRow: 2560, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 640, height: 360))
        let data = Data(bytes: context.data!, count: 2560 * 360)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    hashes.append(digest)
}
let unique = Set(hashes).count
let result: [String: Any] = ["frame_count": count, "unique_decoded_rgba_frames": unique,
                           "width": 640, "height": 360, "bytes_per_row": 2560, "sha256_by_frame": hashes]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]))
precondition(unique == expected)
