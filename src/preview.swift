import Cocoa

// Renders the real charm artwork through the SAME flipped-view draw path the app
// uses, so we can confirm orientation, proportions and the garland layout.

let base = "/Users/dusky/Desktop/LuckyDangle/charms"
func img(_ f: String) -> NSImage? { NSImage(contentsOfFile: "\(base)/\(f)") }

func drawImg(_ f: String, w: CGFloat, h: CGFloat, at p: CGPoint, angle: CGFloat = 0, flip: Bool = false) {
    guard let im = img(f) else { return }
    NSGraphicsContext.current?.saveGraphicsState()
    let x = NSAffineTransform(); x.translateX(by: p.x, yBy: p.y); x.rotate(byRadians: -angle); x.concat()
    if flip { let m = NSAffineTransform(); m.scaleX(by: -1, yBy: 1); m.concat() }
    im.draw(in: NSRect(x: -w/2, y: -h/2, width: w, height: h), from: .zero,
            operation: .sourceOver, fraction: 1, respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.current?.restoreGraphicsState()
}

final class Preview: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) {
        NSColor(calibratedRed: 0.06, green: 0.075, blue: 0.13, alpha: 1).setFill(); bounds.fill()

        func label(_ t: String, _ x: CGFloat) {
            NSAttributedString(string: t, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.6, alpha: 1)])
                .draw(at: NSPoint(x: x, y: 250))
        }
        func rope(_ x: CGFloat) {
            let p = NSBezierPath(); p.move(to: CGPoint(x: x, y: 8)); p.line(to: CGPoint(x: x, y: 70))
            p.lineWidth = 2.2; NSColor(calibratedRed: 0.72, green: 0.58, blue: 0.35, alpha: 1).setStroke(); p.stroke()
        }

        let charms: [(String, String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            // file, label, w, h, attach, x
            ("hamsa.png","Hamsa",64,84,0.12,90),
            ("drishti-bommai.png","Drishti",64,84,0.13,230),
            ("daruma.png","Daruma",64,64,0.14,370),
            ("maneki-neko.png","Maneki",64,84,0.13,510),
            ("horseshoe.png","Horseshoe",64,84,0.12,650),
            ("scarab.png","Scarab",140.5,107,0.227,830),
        ]
        for (file,name,w,h,attach,x) in charms {
            rope(x)
            let center = CGPoint(x: x, y: 70 + h*(0.5-attach))
            drawImg(file, w: w, h: h, at: center)
            label(name, x - 24)
        }

        // garland (nimbu-mirchi)
        let gx: CGFloat = 1020
        let slots: [CGFloat] = [0.61,0.65,0.69,0.73,0.77,0.81,0.85]
        let sprite = [1,4,2,6,0,3,5]
        let sizes: [(CGFloat,CGFloat)] = [(65.2,16.2),(66,8.2),(55.6,11.3),(57.8,12.1),(42.3,11.3),(56.8,10.1),(59.1,9)]
        let jit: [CGFloat] = [0.08,-0.12,0.05,-0.08,0.13,-0.05,0.1]
        let ropeTop: CGFloat = 8, ropeLen: CGFloat = 190
        let rp = NSBezierPath(); rp.move(to: CGPoint(x: gx, y: ropeTop)); rp.line(to: CGPoint(x: gx, y: ropeTop+ropeLen))
        rp.lineWidth = 2.2; NSColor(calibratedRed: 0.72, green: 0.58, blue: 0.35, alpha: 1).setStroke(); rp.stroke()
        for (r, s) in slots.enumerated() {
            let sp = sprite[r]; let (cw,ch) = sizes[sp]
            let y = ropeTop + ropeLen * s
            drawImg("nimbu-chili-\(sp+1).png", w: cw, h: ch, at: CGPoint(x: gx, y: y), angle: jit[r], flip: r % 2 != 0)
        }
        let end = CGPoint(x: gx, y: ropeTop+ropeLen)
        drawImg("nimbu-coal.png", w: 21, h: 18.8, at: CGPoint(x: gx, y: end.y+28))
        drawImg("nimbu-lemon.png", w: 44, h: 48.6, at: end)
        label("Nimbu-mirchi", gx - 30)
    }
}

let size = NSSize(width: 1140, height: 270)
let view = Preview(frame: NSRect(origin: .zero, size: size))
let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
view.cacheDisplay(in: view.bounds, to: rep)
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "/Users/dusky/Desktop/LuckyDangle/preview.png"))
print("wrote preview.png")
