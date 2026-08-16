import AVFoundation
import Cocoa
import UniformTypeIdentifiers

let inURL = URL(fileURLWithPath: "/Users/dusky/Desktop/LuckyDangle/media/demo.mov")
let outURL = URL(fileURLWithPath: "/Users/dusky/Desktop/LuckyDangle/media/demo.gif")

let asset = AVURLAsset(url: inURL)
let dur = CMTimeGetSeconds(asset.duration)

let fps: Double = 10
let width: CGFloat = 560
let frameCount = Int(dur * fps)

let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.maximumSize = CGSize(width: width, height: width * 2)   // cap width, keep aspect
gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

guard let dest = CGImageDestinationCreateWithURL(
    outURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
    print("no dest"); exit(1)
}
CGImageDestinationSetProperties(dest, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
] as CFDictionary)

let frameProps = [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 1.0 / fps]
] as CFDictionary

var written = 0
for i in 0..<frameCount {
    let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
    if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
        CGImageDestinationAddImage(dest, cg, frameProps)
        written += 1
    }
}
if CGImageDestinationFinalize(dest) {
    let size = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
    print(String(format: "gif: %d frames, %.1f MB", written, Double(size ?? 0) / 1_048_576))
} else {
    print("finalize failed"); exit(1)
}
