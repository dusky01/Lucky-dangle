import AVFoundation
import Cocoa

let inURL = URL(fileURLWithPath: "/Users/dusky/Desktop/LuckyDangle/media/demo.mov")
let mp4URL = URL(fileURLWithPath: "/Users/dusky/Desktop/LuckyDangle/media/demo.mp4")
let posterURL = URL(fileURLWithPath: "/Users/dusky/Desktop/LuckyDangle/media/poster.png")

let asset = AVURLAsset(url: inURL)
let dur = CMTimeGetSeconds(asset.duration)
let track = asset.tracks(withMediaType: .video).first
let natural = track?.naturalSize ?? .zero
print(String(format: "source: %.1fs  %.0fx%.0f", dur, natural.width, natural.height))

// poster frame at ~1.2s
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.maximumSize = CGSize(width: 1400, height: 1400)
if let cg = try? gen.copyCGImage(at: CMTime(seconds: min(1.2, dur * 0.3), preferredTimescale: 600), actualTime: nil) {
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])?.write(to: posterURL)
    print("poster: \(cg.width)x\(cg.height)")
}

// transcode to H.264 mp4 (720p box), for broad browser support + smaller size
try? FileManager.default.removeItem(at: mp4URL)
guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
    print("no export session"); exit(1)
}
export.outputURL = mp4URL
export.outputFileType = .mp4
export.shouldOptimizeForNetworkUse = true

let sem = DispatchSemaphore(value: 0)
export.exportAsynchronously { sem.signal() }
sem.wait()

if export.status == .completed {
    let size = (try? FileManager.default.attributesOfItem(atPath: mp4URL.path)[.size] as? Int) ?? 0
    print(String(format: "mp4 done: %.1f MB", Double(size ?? 0) / 1_048_576))
} else {
    print("export failed: \(export.error?.localizedDescription ?? "unknown")")
    exit(1)
}
