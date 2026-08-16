import Cocoa
import QuartzCore
import Carbon.HIToolbox

// MARK: - Charm model

enum Art {
    case emoji(fontSize: CGFloat)
    case image(file: String, w: CGFloat, h: CGFloat, attach: CGFloat)
    case garland
}

struct Charm {
    let name: String
    let slug: String
    let menuIcon: String            // emoji shown in the menu list
    let art: Art
    let hangOffset: CGFloat         // distance from the last rope node to the charm's centre
}

// Frames / attach points / hang offsets are taken verbatim from luckydangle.app.
let CHARMS: [Charm] = [
    Charm(name: "Nazar boncuğu", slug: "nazar",          menuIcon: "🧿", art: .emoji(fontSize: 52), hangOffset: 22.4),
    Charm(name: "Hamsa",         slug: "hamsa",          menuIcon: "🪬", art: .image(file: "hamsa.png",          w: 64,    h: 84,  attach: 0.12),  hangOffset: 32),
    Charm(name: "Nimbu-mirchi",  slug: "nimbu-mirchi",   menuIcon: "🍋", art: .garland,                                                          hangOffset: 0),
    Charm(name: "Drishti bommai",slug: "drishti-bommai", menuIcon: "🪆", art: .image(file: "drishti-bommai.png", w: 64,    h: 84,  attach: 0.13),  hangOffset: 31.1),
    Charm(name: "Daruma",        slug: "daruma",         menuIcon: "🎎", art: .image(file: "daruma.png",         w: 64,    h: 64,  attach: 0.14),  hangOffset: 23),
    Charm(name: "Maneki-neko",   slug: "maneki-neko",    menuIcon: "🐱", art: .image(file: "maneki-neko.png",    w: 64,    h: 84,  attach: 0.13),  hangOffset: 31.1),
    Charm(name: "Horseshoe",     slug: "horseshoe",      menuIcon: "🧲", art: .image(file: "horseshoe.png",      w: 64,    h: 84,  attach: 0.12),  hangOffset: 31.9),
    Charm(name: "Scarab",        slug: "scarab",         menuIcon: "🪲", art: .image(file: "scarab.png",         w: 140.5, h: 107, attach: 0.227), hangOffset: 29.2),
]

// nimbu-mirchi garland layout, also from the site
enum Garland {
    static let slots:      [CGFloat] = [0.61, 0.65, 0.69, 0.73, 0.77, 0.81, 0.85]
    static let slotSprite: [Int]     = [1, 4, 2, 6, 0, 3, 5]
    static let slotJitter: [CGFloat] = [0.08, -0.12, 0.05, -0.08, 0.13, -0.05, 0.1]
    static let chiliSizes: [(CGFloat, CGFloat)] =
        [(65.2,16.2),(66,8.2),(55.6,11.3),(57.8,12.1),(42.3,11.3),(56.8,10.1),(59.1,9)]
    static let lemon: (CGFloat, CGFloat) = (44, 48.6)
    static let coal:  (CGFloat, CGFloat) = (21, 18.8)
    static let coalDrop: CGFloat = 28
}

// MARK: - Image loading (from the app bundle's Resources/charms)

enum CharmImages {
    static var basePath = Bundle.main.resourcePath.map { $0 + "/charms" } ?? "charms"
    private static var cache: [String: NSImage] = [:]
    static func image(_ file: String) -> NSImage? {
        if let c = cache[file] { return c }
        guard let img = NSImage(contentsOfFile: basePath + "/" + file) else { return nil }
        cache[file] = img
        return img
    }
}

// MARK: - Physics view (12-node Verlet rope, ported from luckydangle.app)

final class CharmView: NSView {

    private let N = 12
    private let seg: CGFloat = 15.5
    private var rest: CGFloat { seg * CGFloat(N - 1) }
    private let gravity: CGFloat = 0.125
    private let velDamp: CGFloat = 0.98
    private let solveIters = 5
    private let substep: CGFloat = 1.0 / 120.0

    private struct Node { var x: CGFloat; var y: CGFloat; var px: CGFloat; var py: CGFloat }
    private var nodes: [Node] = []

    private var dragging = false
    private var target = CGPoint.zero
    private var dragDistance: CGFloat = 0
    private var dragStart = CGPoint.zero
    private var pointer: CGPoint?            // cursor in view coords (for hover repulsion)
    private var lastPointer: CGPoint?
    private var pW: CGFloat = 0              // smoothed pointer velocity
    private var pQ: CGFloat = 0
    private var simTime: CGFloat = 0
    private var accumulator: CGFloat = 0
    private var lastFrame: TimeInterval = 0

    var charm: Charm = CHARMS[0] { didSet { needsDisplay = true } }
    var customEmoji: String = "🍀"          // used when charm.slug == "custom"
    var anchorFraction: CGFloat = 0.68

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        resetRope()
        startClock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.flick() }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() { super.layout(); if nodes.isEmpty { resetRope() } }

    private var anchor: CGPoint { CGPoint(x: bounds.width * anchorFraction, y: 8) }

    private func resetRope() {
        let a = anchor
        nodes = (0..<N).map { i in
            let y = a.y + CGFloat(i) * seg
            return Node(x: a.x, y: y, px: a.x, py: y)
        }
    }

    private var tangent: CGFloat {
        let a = nodes[N - 2], b = nodes[N - 1]
        return atan2(b.x - a.x, b.y - a.y)
    }
    private var charmPoint: CGPoint {
        let u = nodes[N - 1], t = tangent, o = charm.hangOffset
        return CGPoint(x: u.x + o * sin(t), y: u.y + o * cos(t))
    }
    private var hitRadius: CGFloat {
        switch charm.art {
        case .emoji: return 30
        case .image(_, let w, let h, _): return max(w, h) * 0.5
        case .garland: return 30
        }
    }

    // point along the rope at 0…1 (used for garland chillies)
    private func pointAlong(_ frac: CGFloat) -> (p: CGPoint, angle: CGFloat) {
        let f = min(max(frac, 0), 1) * CGFloat(N - 1)
        let i = min(Int(f), N - 2)
        let n = f - CGFloat(i)
        let a = nodes[i], b = nodes[i + 1]
        return (CGPoint(x: a.x + (b.x - a.x) * n, y: a.y + (b.y - a.y) * n),
                atan2(b.x - a.x, b.y - a.y))
    }

    // MARK: clock + physics

    private func startClock() {
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.frame(now: CACurrentMediaTime())
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func frame(now: TimeInterval) {
        guard nodes.count == N else { return }
        let dt = lastFrame == 0 ? substep : min(CGFloat(now - lastFrame), 0.1)
        lastFrame = now
        accumulator += dt
        var stepped = false
        while accumulator >= substep { physicsStep(); accumulator -= substep; stepped = true }
        if stepped { needsDisplay = true }
    }

    private func physicsStep() {
        simTime += substep
        let a = anchor
        let wind = 0.0035 * sin(simTime * 0.55) + 0.002 * sin(simTime * 1.3 + 0.8)

        for i in 1..<N {
            var n = nodes[i]
            let vx = (n.x - n.px) * velDamp
            let vy = (n.y - n.py) * velDamp
            n.px = n.x; n.py = n.y
            n.x += vx + wind * (CGFloat(i) / CGFloat(N - 1))
            n.y += vy + gravity
            nodes[i] = n
        }

        // Hover repulsion: the cursor pushes the charm and rope away, with a
        // little of the cursor's own velocity mixed in. (Ported from the site;
        // applies whenever the pointer is present and we're not dragging.)
        if let ptr = pointer, !dragging {
            if let last = lastPointer {
                pW = pW * 0.75 + (ptr.x - last.x) * 0.25
                pQ = pQ * 0.75 + (ptr.y - last.y) * 0.25
            }
            lastPointer = ptr
            let t = tangent
            let cx = nodes[N - 1].x + charm.hangOffset * sin(t)
            let cy = nodes[N - 1].y + charm.hangOffset * cos(t)
            let ix = cx - ptr.x, ry = cy - ptr.y
            let s = hypot(ix, ry), h: CGFloat = 40
            if s < h && s > 0.5 {
                let l = (h - s) / h
                let d = l * l * 0.4, p = l * 0.1
                nodes[N - 1].x += ix / s * d + max(-14, min(14, pW)) * p
                nodes[N - 1].y += (ry / s * d + max(-14, min(14, pQ)) * p) * 0.35
            }
            for l in 1..<(N - 2) {
                let dx = nodes[l].x - ptr.x, dy = nodes[l].y - ptr.y
                let e = dx * dx + dy * dy
                if e < 1600 && e > 1 {
                    let ct = sqrt(e), kt = (40 - ct) / 40 * 0.8
                    nodes[l].x += dx / ct * kt
                    nodes[l].y += dy / ct * kt
                }
            }
        } else {
            lastPointer = nil; pW = 0; pQ = 0
        }

        for _ in 0..<solveIters {
            nodes[0].x = a.x; nodes[0].y = a.y
            if dragging { nodes[N - 1].x = target.x; nodes[N - 1].y = target.y }
            for k in 0..<(N - 1) {
                let dx = nodes[k + 1].x - nodes[k].x
                let dy = nodes[k + 1].y - nodes[k].y
                let d = max(hypot(dx, dy), 0.0001)
                let diff = (d - seg) / d / 2
                let ox = dx * diff, oy = dy * diff
                if k == 0 { nodes[k + 1].x -= ox * 2; nodes[k + 1].y -= oy * 2 }
                else if dragging && k == N - 2 { nodes[k].x += ox * 2; nodes[k].y += oy * 2 }
                else { nodes[k].x += ox; nodes[k].y += oy; nodes[k + 1].x -= ox; nodes[k + 1].y -= oy }
            }
        }
    }

    private func flick() {
        let kick = (18 + CGFloat.random(in: 0...8)) * (Bool.random() ? 1 : -1)
        nodes[N - 1].px += kick
    }

    // MARK: interaction

    func isPointOnCharm(_ p: CGPoint) -> Bool {
        guard nodes.count == N else { return false }
        let c = charmPoint
        return hypot(p.x - c.x, p.y - c.y) <= hitRadius
    }
    var isDragging: Bool { dragging }
    func setPointer(_ p: CGPoint?) { pointer = p }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard nodes.count == N else { return nil }
        let local = superview != nil ? convert(point, from: superview) : point
        return isPointOnCharm(local) ? self : nil
    }

    private func setTarget(from p: CGPoint) {
        let a = anchor
        let dx = p.x - a.x, dy = p.y - a.y
        let d = max(hypot(dx, dy), 1)
        let clamped = min(max(d, charm.hangOffset), rest * 1.4)
        target = CGPoint(x: a.x + dx / d * clamped, y: a.y + dy / d * clamped)
    }

    override func mouseDown(with event: NSEvent) {
        dragging = true; dragDistance = 0
        dragStart = convert(event.locationInWindow, from: nil)
        setTarget(from: dragStart)
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragDistance = max(dragDistance, hypot(p.x - dragStart.x, p.y - dragStart.y))
        setTarget(from: p)
    }
    override func mouseUp(with event: NSEvent) {
        dragging = false
        if dragDistance < 6 { flick() }
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard nodes.count == N else { return }
        drawRope()

        // anchor bead
        let a = anchor, beadR: CGFloat = 4
        NSColor(calibratedRed: 0.85, green: 0.66, blue: 0.27, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: a.x - beadR, y: a.y - beadR, width: beadR*2, height: beadR*2)).fill()

        switch charm.art {
        case .emoji(let fontSize):
            let glyph = charm.slug == "custom" ? customEmoji : charm.menuIcon
            drawEmoji(glyph, fontSize: fontSize, at: charmPoint, angle: tangent)
        case .image(let file, let w, let h, _):
            drawImage(file, w: w, h: h, at: charmPoint, angle: tangent)
        case .garland:
            drawGarland()
        }
    }

    private func drawRope() {
        let rope = NSBezierPath()
        rope.move(to: CGPoint(x: nodes[0].x, y: nodes[0].y))
        for i in 1..<(N - 1) {
            let mid = CGPoint(x: (nodes[i].x + nodes[i + 1].x) / 2,
                              y: (nodes[i].y + nodes[i + 1].y) / 2)
            rope.curve(to: mid,
                       controlPoint1: CGPoint(x: nodes[i].x, y: nodes[i].y),
                       controlPoint2: CGPoint(x: nodes[i].x, y: nodes[i].y))
        }
        rope.line(to: CGPoint(x: nodes[N - 1].x, y: nodes[N - 1].y))
        rope.lineWidth = 2.2
        rope.lineCapStyle = .round
        NSColor(calibratedRed: 0.72, green: 0.58, blue: 0.35, alpha: 0.95).setStroke()
        rope.stroke()
    }

    private func withTransform(at p: CGPoint, angle: CGFloat, _ body: () -> Void) {
        NSGraphicsContext.current?.saveGraphicsState()
        let x = NSAffineTransform()
        x.translateX(by: p.x, yBy: p.y)
        x.rotate(byRadians: -angle)
        x.concat()
        body()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawEmoji(_ glyph: String, fontSize: CGFloat, at p: CGPoint, angle: CGFloat) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        let s = NSAttributedString(string: glyph,
                                   attributes: [.font: NSFont.systemFont(ofSize: fontSize), .shadow: shadow])
        let size = s.size()
        withTransform(at: p, angle: angle) {
            s.draw(at: NSPoint(x: -size.width / 2, y: -size.height / 2))
        }
    }

    private func drawImage(_ file: String, w: CGFloat, h: CGFloat, at p: CGPoint, angle: CGFloat) {
        guard let img = CharmImages.image(file) else {
            // fall back to the menu emoji if art is missing
            drawEmoji(charm.menuIcon, fontSize: 46, at: p, angle: angle); return
        }
        withTransform(at: p, angle: angle) {
            img.draw(in: NSRect(x: -w/2, y: -h/2, width: w, height: h),
                     from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
    }

    private func drawGarland() {
        // chillies threaded along the lower rope
        for (r, slot) in Garland.slots.enumerated() {
            let sprite = Garland.slotSprite[r]
            let (cw, ch) = Garland.chiliSizes[sprite]
            let at = pointAlong(slot)
            guard let img = CharmImages.image("nimbu-chili-\(sprite + 1).png") else { continue }
            let flip = r % 2 != 0
            withTransform(at: at.p, angle: at.angle + Garland.slotJitter[r]) {
                if flip {
                    let m = NSAffineTransform(); m.scaleX(by: -1, yBy: 1); m.concat()
                }
                img.draw(in: NSRect(x: -cw/2, y: -ch/2, width: cw, height: ch),
                         from: .zero, operation: .sourceOver, fraction: 1,
                         respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
        }
        // lemon (+ coal) at the very end
        let u = CGPoint(x: nodes[N - 1].x, y: nodes[N - 1].y)
        withTransform(at: u, angle: tangent) {
            let (lw, lh) = Garland.lemon
            let (kw, kh) = Garland.coal
            if let coal = CharmImages.image("nimbu-coal.png") {
                coal.draw(in: NSRect(x: -kw/2, y: Garland.coalDrop - kh/2, width: kw, height: kh),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            if let lemon = CharmImages.image("nimbu-lemon.png") {
                lemon.draw(in: NSRect(x: -lw/2, y: -lh/2, width: lw, height: lh),
                           from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
        }
    }
}

// MARK: - Overlay window

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {

    static weak var shared: AppDelegate?

    private var window: OverlayWindow!
    private var charmView: CharmView!
    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    private var currentSlug = "nazar"
    private var visible = true

    func applicationDidFinishLaunching(_ note: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        buildWindow()
        installMouseMonitors()
        buildStatusItem()
        registerHotKey()
        restoreCharm()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: window

    private func buildWindow() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let height: CGFloat = 380
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                           width: screen.frame.width, height: height)

        window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        charmView = CharmView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = charmView
        window.orderFrontRegardless()
    }

    @objc private func screensChanged() {
        guard let screen = NSScreen.main else { return }
        let height = window.frame.height
        window.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                               width: screen.frame.width, height: height), display: true)
        charmView.frame = NSRect(origin: .zero, size: window.frame.size)
    }

    // MARK: click-through gating

    private func installMouseMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.updatePassthrough()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] ev in
            self?.updatePassthrough(); return ev
        }
        updatePassthrough()
    }

    private func updatePassthrough() {
        guard visible, window != nil, window.isVisible else { return }
        let screenPt = NSEvent.mouseLocation
        let f = window.frame
        let inWindow = CGPoint(x: screenPt.x - f.minX, y: screenPt.y - f.minY)
        let viewPt = CGPoint(x: inWindow.x, y: f.height - inWindow.y)
        charmView.setPointer(viewPt)                 // feeds the hover-repulsion field
        if charmView.isDragging { window.ignoresMouseEvents = false; return }
        window.ignoresMouseEvents = !charmView.isPointOnCharm(viewPt)
    }

    // MARK: status bar menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🧿"
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Lucky Dangle", action: nil, keyEquivalent: ""); header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let ch = NSMenuItem(title: "Charm", action: nil, keyEquivalent: ""); ch.isEnabled = false
        menu.addItem(ch)

        for (i, charm) in CHARMS.enumerated() {
            let item = NSMenuItem(title: "\(charm.menuIcon)  \(charm.name)",
                                  action: #selector(pickCharm(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (charm.slug == currentSlug) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let custom = NSMenuItem(title: "Hang custom emoji…", action: #selector(hangCustom), keyEquivalent: "e")
        custom.target = self; menu.addItem(custom)

        let toggle = NSMenuItem(title: visible ? "Hide charm" : "Show charm",
                                action: #selector(toggleVisibility), keyEquivalent: "l")
        toggle.keyEquivalentModifierMask = [.command, .option]; toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Lucky Dangle", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
    }

    // MARK: charm selection

    @objc private func pickCharm(_ sender: NSMenuItem) {
        let charm = CHARMS[sender.tag]
        currentSlug = charm.slug
        charmView.charm = charm
        updateStatusIcon(for: charm)
        rebuildMenu()
        UserDefaults.standard.set(charm.slug, forKey: "charmSlug")
    }

    @objc private func hangCustom() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Hang a custom charm"
        alert.informativeText = "Type or paste any emoji to hang from the top of your screen."
        alert.addButton(withTitle: "Hang it")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = charmView.customEmoji
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty {
                charmView.customEmoji = v
                let custom = Charm(name: "Emoji", slug: "custom", menuIcon: v,
                                   art: .emoji(fontSize: 52), hangOffset: 22.4)
                currentSlug = "custom"
                charmView.charm = custom
                statusItem.button?.image = nil
                statusItem.button?.title = v
                rebuildMenu()
                UserDefaults.standard.set("custom", forKey: "charmSlug")
                UserDefaults.standard.set(v, forKey: "charmEmoji")
            }
        }
    }

    private func updateStatusIcon(for charm: Charm) {
        switch charm.art {
        case .image(let file, _, _, _):
            if let img = CharmImages.image(file) {
                let icon = NSImage(size: NSSize(width: 20, height: 20))
                icon.lockFocus()
                img.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20))
                icon.unlockFocus()
                statusItem.button?.image = icon
                statusItem.button?.title = ""
                return
            }
            fallthrough
        default:
            statusItem.button?.image = nil
            statusItem.button?.title = charm.menuIcon
        }
    }

    private func restoreCharm() {
        let d = UserDefaults.standard
        let slug = d.string(forKey: "charmSlug") ?? "nazar"
        if slug == "custom", let e = d.string(forKey: "charmEmoji"), !e.isEmpty {
            charmView.customEmoji = e
            let custom = Charm(name: "Emoji", slug: "custom", menuIcon: e,
                               art: .emoji(fontSize: 52), hangOffset: 22.4)
            currentSlug = "custom"; charmView.charm = custom
            statusItem.button?.image = nil; statusItem.button?.title = e
        } else if let charm = CHARMS.first(where: { $0.slug == slug }) {
            currentSlug = charm.slug; charmView.charm = charm
            updateStatusIcon(for: charm)
        }
        rebuildMenu()
    }

    // MARK: visibility

    @objc func toggleVisibility() {
        visible.toggle()
        if visible { window.orderFrontRegardless(); updatePassthrough() }
        else { window.ignoresMouseEvents = true; window.orderOut(nil) }
        rebuildMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: global hotkey (⌥⌘L)

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            AppDelegate.shared?.toggleVisibility(); return noErr
        }, 1, &eventType, nil, nil)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C554B59), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(cmdKey | optionKey),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

// MARK: - Launch

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
