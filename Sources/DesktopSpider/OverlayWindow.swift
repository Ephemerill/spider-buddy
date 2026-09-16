import AppKit
import QuartzCore

// MARK: - Spider layer

/// Small layer that rasterises just the critter. Positioned every frame; the
/// rest of the overlay never redraws.
final class SpiderLayer: CALayer {
    var pose = SpiderPose()

    override func draw(in ctx: CGContext) {
        SpiderRenderer.draw(pose, in: ctx, bounds: bounds)
    }

    override func action(forKey event: String) -> CAAction? {
        // No implicit animations: we drive everything ourselves.
        nil
    }
}

// MARK: - View

/// A small window that follows the spider. Keeping the composited surface tiny
/// instead of screen-sized is the difference between a few percent of a core
/// and a quarter of one.
final class SpiderView: NSView {
    private let spiderLayer = SpiderLayer()

    var spider: Spider?
    /// World-space origin of this view, i.e. the window's origin.
    var worldOrigin = CGPoint.zero

    private var dragSamples: [(p: V2, t: TimeInterval)] = []
    private var dragging = false
    private var pressedAt = V2.zero
    private var pressTime: TimeInterval = 0

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        spiderLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        spiderLayer.bounds = CGRect(x: 0, y: 0, width: 160, height: 160)
        spiderLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        spiderLayer.needsDisplayOnBoundsChange = true
        layer?.addSublayer(spiderLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        spiderLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// The layer is only as big as the spider itself, because every pixel of
    /// it is re-rasterised when the pose changes. The window around it is
    /// larger, so it only has to be repositioned now and then.
    func resize(sprite: CGFloat, window: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: window, height: window)
        spiderLayer.bounds = CGRect(x: 0, y: 0, width: sprite, height: sprite)
    }

    private var drawn: SpiderPose?
    private var sinceDraw: CFTimeInterval = 0
    /// Whether the last `apply` actually had to re-rasterise anything.
    private(set) var didRedraw = false

    func apply(_ pose: SpiderPose) {
        spiderLayer.position = CGPoint(x: pose.pos.x - worldOrigin.x, y: pose.pos.y - worldOrigin.y)
        spiderLayer.pose = pose
        didRedraw = false

        // Moving the layer costs nothing; re-rasterising it does. The picture
        // only depends on the spider's *shape*, so a spider that is standing
        // still — or asleep, or gliding along a straight edge — is nearly free.
        let now = CACurrentMediaTime()
        if let old = drawn, now - sinceDraw < 0.5, SpiderView.shapeDelta(old, pose) < 0.22 {
            return
        }
        drawn = pose
        sinceDraw = now
        didRedraw = true
        spiderLayer.setNeedsDisplay()
    }

    /// Roughly "how many points of outline moved", so the threshold is in
    /// units a person could actually see.
    private static func shapeDelta(_ a: SpiderPose, _ b: SpiderPose) -> CGFloat {
        if a.emote != b.emote || a.legs.count != b.legs.count { return .infinity }
        // Partly behind a window: the cut-out moves with it, so every move
        // is a new picture.
        if a.hiddenBy != b.hiddenBy || (!b.hiddenBy.isEmpty && (a.pos - b.pos).length > 0.3) { return .infinity }
        var d = abs(angleDelta(a.heading, b.heading)) * 45
        d += (abs(a.stretch - b.stretch) + abs(a.fatten - b.fatten)) * 40
        d += (a.look - b.look).length * 7
        d += (abs(a.blink - b.blink) + abs(a.happy - b.happy)) * 9
        d += abs(a.startled - b.startled) * 7
        d += abs(a.abdomenSway - b.abdomenSway) * 14
        if a.emote != .none { d += abs(a.emoteT - b.emoteT) * 40 }
        for (l, r) in zip(a.legs, b.legs) {
            d += (l.foot - r.foot).length + (l.knee - r.knee).length * 0.6
        }
        return d * a.scale
    }

    // MARK: Hit testing / input

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let spider else { return nil }
        let world = V2(point.x + worldOrigin.x, point.y + worldOrigin.y)
        return spider.hitTest(world) ? self : nil
    }

    private func world(_ event: NSEvent) -> V2 {
        let p = convert(event.locationInWindow, from: nil)
        return V2(p.x + worldOrigin.x, p.y + worldOrigin.y)
    }

    override func mouseDown(with event: NSEvent) {
        guard let spider else { return }
        let w = world(event)
        pressedAt = w
        pressTime = event.timestamp
        dragSamples = [(w, event.timestamp)]
        dragging = false
        if event.clickCount >= 2 {
            spider.celebrate()
        } else {
            spider.beginGrab(at: w)
            dragging = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let spider, dragging else { return }
        let w = world(event)
        spider.moveGrab(to: w)
        dragSamples.append((w, event.timestamp))
        if dragSamples.count > 8 { dragSamples.removeFirst(dragSamples.count - 8) }
    }

    override func mouseUp(with event: NSEvent) {
        guard let spider else { return }
        let w = world(event)
        defer { dragging = false; dragSamples = [] }
        guard dragging else { return }

        // Velocity from the recent samples, so a flick actually throws it.
        var v = V2.zero
        if let first = dragSamples.first, dragSamples.count > 1 {
            if event.timestamp - first.t < 0.22 {
                v = (w - first.p) / CGFloat(max(event.timestamp - first.t, 0.008))
            } else if let recent = dragSamples.last(where: { event.timestamp - $0.t > 0.04 }) {
                v = (w - recent.p) / CGFloat(max(event.timestamp - recent.t, 0.008))
            }
        }
        let travelled = w.distance(to: pressedAt)
        if travelled < 4 && event.timestamp - pressTime < 0.35 {
            spider.endGrab(throwVelocity: .zero)
            spider.poke()
        } else {
            spider.endGrab(throwVelocity: v)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        spider?.scroll(event.scrollingDeltaY)
    }

    override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .spiderContextMenu, object: event)
    }
}

// MARK: - Silk

/// Screen-sized, click-through, and ordered out whenever there is no silk to
/// draw — which is most of the time.
final class SilkView: NSView {
    private let silkLayer = CAShapeLayer()

    var worldOrigin = CGPoint.zero
    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for l in [silkLayer] {
            l.fillColor = nil
            l.lineCap = .round
            l.contentsScale = scale
            l.actions = ["path": NSNull(), "opacity": NSNull(), "hidden": NSNull()]
            layer?.addSublayer(l)
        }
        silkLayer.strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.62)
        silkLayer.lineWidth = 1.1
        silkLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)
        silkLayer.shadowOffset = CGSize(width: 0.5, height: -0.5)
        silkLayer.shadowRadius = 1.2
        silkLayer.shadowOpacity = 1
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Returns true if anything is visible, so the window can be hidden when not.
    @discardableResult
    func apply(_ pose: SpiderPose) -> Bool {
        var anything = false

        if let web = pose.web {
            silkLayer.path = SpiderRenderer.silkPath(pose, origin: V2(worldOrigin.x, worldOrigin.y))
            silkLayer.opacity = Float(web.alpha)
            silkLayer.isHidden = false
            anything = true
        } else if !silkLayer.isHidden {
            silkLayer.isHidden = true
            silkLayer.path = nil
        }

        return anything
    }

}


// MARK: - Window

final class OverlayWindow: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        isFloatingPanel = true
        // Above every app window, below the Dock (20) and the menu bar (24),
        // so it never sits on top of either. (Set after `isFloatingPanel`,
        // which resets the level to floating itself.)
        level = .floating
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Hammock

/// The silk hammock: a sling strung across a top corner from the wall to the
/// underside of the menu bar. Longitudinal strands sag between the two
/// anchors, cross-ties hold them together, and the sheet fills in between.
/// Drawn in its own small window, above the spider, so the spider asleep in
/// it is seen through the silk.
final class HammockView: NSView {
    var hammock: Hammock? { didSet { if hammock != oldValue { needsDisplay = true } } }
    /// 1 while it is being wiped away, fading to 0.
    var tear: CGFloat = 0 { didSet { needsDisplay = true } }
    private var lastDrawn: Hammock?

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard let h0 = hammock ?? lastDrawn else { return }
        if hammock != nil { lastDrawn = hammock }
        let alive = hammock != nil
        let fade: CGFloat = alive ? 1 : max(0, tear)
        guard fade > 0.01 else { return }

        // Work in the hammock's own frame: its rect maps onto our bounds.
        var h = h0
        h.rect = CGRect(origin: .zero, size: h0.rect.size)
        let progress = h.progress
        let damage = alive ? h.damage : 1
        let drop = damage * h.rect.height * 0.25        // sags further as it tears

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShadow(offset: CGSize(width: 0.5, height: -0.5), blur: 1.5,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))

        func tornAt(_ seed: Int) -> Bool {
            let f = CGFloat((seed * 7919) % 97) / 97
            return damage > 0.12 + f * 0.85
        }
        // A small deterministic wobble per strand and place, so the silk
        // never looks ruled.
        func noise(_ i: Int, _ u: CGFloat, _ k: CGFloat = 1) -> CGFloat {
            let sd = CGFloat((h.seed + i * 131) % 1000) / 1000
            return sin(u * (5.5 + sd * 4) * k + sd * 6.28) * 0.6 + sin(u * (11 + sd * 5) + sd * 3) * 0.4
        }
        let style = h.style
        let strands = style.strands
        let thickness = h.rect.height * (style == .pouch ? 0.30 : 0.22)
        /// Strand `i` runs a little above the centre line: 0 is the lowest.
        /// Each hangs a little slack in its own way.
        func strandPoint(_ i: Int, _ u: CGFloat) -> CGPoint {
            let lift = CGFloat(i) / CGFloat(max(strands - 1, 1)) * thickness
            let sd = CGFloat((h.seed + i * 17) % 100) / 100
            let slack = (2 + sd * 6) * sin(u * .pi)               // hangs lower in the middle
            let wob = noise(i, u) * (1.2 + sd * 1.6)
            let full = h.point(at: u, drop: drop) + V2(0, lift * sin(u * .pi) - slack + wob)
            // A strand just stuck down is the taut line it was walked out
            // as; it sinks into its sag from there.
            let d = i < h.drape.count ? h.drape[i] : 1
            if d >= 1 { return full.point }
            let chord = V2.lerp(h.wallAnchor, h.ceilingAnchor, u)
            let k = 1 - (1 - d) * (1 - d)                        // quick to start, settling slowly
            return V2.lerp(chord, full, k).point
        }
        func strandPath(_ i: Int, upTo: CGFloat = 1) -> CGPath {
            let p = CGMutablePath()
            p.move(to: strandPoint(i, 0))
            for k in 1...28 { p.addLine(to: strandPoint(i, CGFloat(k) / 28 * upTo)) }
            return p
        }

        let alpha = fade * (1 - damage * 0.3)
        // A faint sheet where the strands lie close: the bed.
        if progress > 0.5, style != .tangle {
            let sheet = CGMutablePath()
            sheet.move(to: strandPoint(0, 0))
            for k in 1...28 { sheet.addLine(to: strandPoint(0, CGFloat(k) / 28)) }
            for k in stride(from: 28, through: 0, by: -1) { sheet.addLine(to: strandPoint(strands - 1, CGFloat(k) / 28)) }
            sheet.closeSubpath()
            let a = remap(progress, 0.5, 1, 0, style == .pouch ? 0.16 : 0.10) * alpha * (1 - damage * 0.6)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: a))
            ctx.addPath(sheet)
            ctx.fillPath()
        }

        // Longitudinal strands, laid one at a time as it is spun — the
        // first at the fastening, the rest across the middle of the build.
        let strandsShown = Hammock.strandsLaid(progress: progress, of: strands)
        for i in 0..<strandsShown where !tornAt(i) {
            let sd = CGFloat((h.seed + i * 53) % 100) / 100
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: (0.45 + sd * 0.35) * alpha))
            ctx.setLineWidth(0.7 + sd * 0.5)
            // The first thread grows out from the wall as it is walked to
            // the ceiling.
            let upTo: CGFloat = i == 0 && progress < 0.30 ? clamp((progress - 0.10) / 0.20, 0.02, 1) : 1
            ctx.addPath(strandPath(i, upTo: upTo))
            ctx.strokePath()
        }

        // Loose loops of silk drooping from the lower strands — the stringy
        // look of real silk, and the cradle is mostly made of them.
        if strandsShown > 0 {
            let loops = style == .cradle ? 12 : (style == .pouch ? 7 : 5)
            let shown = Int(remap(progress, 0.36, 1, 0, CGFloat(loops)).rounded(.down))
            ctx.setLineWidth(0.7)
            for k in 0..<min(loops, shown) where !tornAt(20 + k) {
                let sd = CGFloat((h.seed + k * 71) % 100) / 100
                let u = 0.12 + (CGFloat(k) + 0.5) / CGFloat(loops) * 0.76
                let from = strandPoint(k % max(strandsShown, 1), u)
                let depth = (6 + sd * 12) * (style == .cradle ? 1.5 : 1)
                let to = strandPoint((k + 1) % max(strandsShown, 1), min(u + 0.06 + sd * 0.05, 1))
                let p = CGMutablePath()
                p.move(to: from)
                p.addCurve(to: to,
                           control1: CGPoint(x: from.x + 2 - sd * 4, y: from.y - depth),
                           control2: CGPoint(x: to.x - 2 + sd * 3, y: to.y - depth * 0.8))
                ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: (0.35 + sd * 0.3) * alpha))
                ctx.addPath(p)
                ctx.strokePath()
            }
        }

        // The tangle: extra strands slung between random points of the
        // sling, criss-crossing.
        if style == .tangle, strandsShown > 1 {
            let cross = 9
            let shown = Int(remap(progress, 0.5, 1, 0, CGFloat(cross)).rounded(.down))
            for k in 0..<min(cross, shown) where !tornAt(30 + k) {
                let s1 = CGFloat((h.seed + k * 37) % 100) / 100, s2 = CGFloat((h.seed + k * 89) % 100) / 100
                let a = strandPoint(k % strandsShown, 0.1 + s1 * 0.8)
                let b = strandPoint((k * 3 + 1) % strandsShown, 0.1 + s2 * 0.8)
                let p = CGMutablePath()
                p.move(to: a)
                p.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2 + (s1 - 0.5) * 8, y: (a.y + b.y) / 2 - 5 - s2 * 8))
                ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: (0.3 + s1 * 0.3) * alpha))
                ctx.setLineWidth(0.6 + s2 * 0.4)
                ctx.addPath(p)
                ctx.strokePath()
            }
        }

        // Cross-ties, tied off at the end: slack little bridges.
        if progress > 0.86, strandsShown > 1 {
            let ties = style == .tangle ? 5 : 9
            let tiesShown = Int(remap(progress, 0.86, 1, 0, CGFloat(ties)).rounded(.down))
            ctx.setLineWidth(0.7)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5 * alpha))
            for k in 0..<min(ties, tiesShown) where !tornAt(40 + k) {
                let sd = CGFloat((h.seed + k * 23) % 100) / 100
                let u = (CGFloat(k) + 0.5) / CGFloat(ties)
                let a = strandPoint(0, u), b = strandPoint(strandsShown - 1, min(u + (sd - 0.5) * 0.08, 1))
                let p = CGMutablePath()
                p.move(to: a)
                p.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2 + (sd - 0.5) * 6, y: (a.y + b.y) / 2 - 3 - sd * 3))
                ctx.addPath(p)
                ctx.strokePath()
            }
        }

        // Clews: the strands gather to each anchor, with a tuft on the wall
        // and the ceiling where the silk is stuck down. Nothing is stuck
        // down until the first thread is fastened.
        ctx.setLineWidth(0.9)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8 * alpha * min(progress * 12, 1)))
        for (anchor, seed, on) in [(h.wallAnchor, 70, progress > 0.03), (h.ceilingAnchor, 71, progress > 0.30)] where !tornAt(seed) && on {
            let a = anchor.point
            for i in 0..<4 {
                let ang = CGFloat(i) * 1.6 + 0.3 + CGFloat((h.seed + i) % 7) * 0.1
                ctx.beginPath()
                ctx.move(to: a)
                ctx.addLine(to: CGPoint(x: a.x + cos(ang) * (4 + CGFloat(i % 2) * 3), y: a.y + sin(ang) * 3.5))
                ctx.strokePath()
            }
        }

        // Loose ends drifting as it is torn.
        if damage > 0.12 && damage < 1 {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5 * fade))
            ctx.setLineWidth(0.9)
            for i in 0..<strands where tornAt(i) {
                let u: CGFloat = 0.3 + CGFloat(i) * 0.07
                let a = strandPoint(i, u)
                let p = CGMutablePath()
                p.move(to: a)
                p.addQuadCurve(to: CGPoint(x: a.x + 6, y: a.y - 14 - CGFloat(i) * 2),
                               control: CGPoint(x: a.x + 8, y: a.y - 4))
                ctx.addPath(p)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }
}


// MARK: - The box

/// Drag out a rectangle on the desktop. Covers every display, takes the
/// mouse, and hands back the rect (or nil on Escape / right-click).
final class BoxDrawView: NSView {
    var worldOrigin = CGPoint.zero
    var onDone: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var rect: CGRect? {
        guard let s = start, let c = current else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(c.x - s.x), height: abs(c.y - s.y))
    }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // A dim wash over everything, cut away inside the box.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.22))
        ctx.fill(bounds)
        if let r = rect {
            ctx.clear(r)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [8, 5])
            ctx.stroke(r.insetBy(dx: 1, dy: 1))
        } else {
            // A hint, top centre of the main screen.
            let text = "Drag out a box for the spider — Esc to cancel" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let size = text.size(withAttributes: attrs)
            let f = NSScreen.main?.frame ?? bounds
            let p = CGPoint(x: f.midX - worldOrigin.x - size.width / 2, y: f.maxY - worldOrigin.y - 80)
            let pill = CGRect(x: p.x - 14, y: p.y - 8, width: size.width + 28, height: size.height + 16)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
            ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.fillPath()
            text.draw(at: p, withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        defer { start = nil; current = nil }
        guard let r = rect, r.width > 120, r.height > 100 else {
            onDone?(nil)
            return
        }
        onDone?(CGRect(x: r.minX + worldOrigin.x, y: r.minY + worldOrigin.y, width: r.width, height: r.height))
    }

    override func rightMouseDown(with event: NSEvent) { onDone?(nil) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDone?(nil) } else { super.keyDown(with: event) }
    }
}

/// The window the box is drawn in: like the overlay, but it takes the keyboard
/// so Escape can cancel.
final class BoxDrawWindow: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A faint outline of the box the spider is kept to.
final class BoxOutlineView: NSView {
    override var isFlipped: Bool { false }
    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.setLineWidth(3)
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.18))
        ctx.addPath(path); ctx.strokePath()
        ctx.setLineWidth(1.2)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        ctx.setLineDash(phase: 0, lengths: [6, 5])
        ctx.addPath(path); ctx.strokePath()
    }
}


// MARK: - Laser dot

/// The red dot of a laser pointer: a bright core with a soft glow, shimmering.
final class LaserView: NSView {
    var phase: CGFloat = 0 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { false }
    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let jitter = CGPoint(x: sin(phase * 37) * 0.6, y: cos(phase * 29) * 0.6)
        let p = CGPoint(x: c.x + jitter.x, y: c.y + jitter.y)
        for (r, a) in [(CGFloat(14), 0.10), (10, 0.22), (7, 0.45)] {
            ctx.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.05, alpha: a))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        ctx.setFillColor(CGColor(red: 1, green: 0.25, blue: 0.15, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.8, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: p.x - 1.6, y: p.y - 1.2, width: 3.2, height: 3.2))
    }
}
