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
    private let draglineLayer = CAShapeLayer()

    var worldOrigin = CGPoint.zero
    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for l in [silkLayer, draglineLayer] {
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
        draglineLayer.strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.34)
        draglineLayer.lineWidth = 0.9
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Returns true if anything is visible, so the window can be hidden when not.
    @discardableResult
    func apply(_ pose: SpiderPose) -> Bool {
        let body = CGPoint(x: pose.silkAttach.x - worldOrigin.x, y: pose.silkAttach.y - worldOrigin.y)
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

        if let dl = pose.dragline {
            let a = CGPoint(x: dl.from.x - worldOrigin.x, y: dl.from.y - worldOrigin.y)
            let p = CGMutablePath()
            p.move(to: a)
            // Trailing silk droops behind the spider.
            p.addQuadCurve(to: body, control: CGPoint(x: (a.x + body.x) / 2,
                                                      y: (a.y + body.y) / 2 - 14))
            draglineLayer.path = p
            draglineLayer.opacity = Float(dl.alpha * 0.8)
            draglineLayer.isHidden = false
            anything = true
        } else if !draglineLayer.isHidden {
            draglineLayer.isHidden = true
            draglineLayer.path = nil
        }
        return anything
    }

}

extension Notification.Name {
    static let spiderContextMenu = Notification.Name("spiderContextMenu")
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
        // Above the dock (20) and the menu bar (24), below open menus.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        isFloatingPanel = true
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
        let strands = 7
        let thickness = h.rect.height * 0.22
        /// Strand `i` runs a little above the centre line: 0 is the lowest.
        func strandPoint(_ i: Int, _ u: CGFloat) -> CGPoint {
            let lift = CGFloat(i) / CGFloat(strands - 1) * thickness
            // Strands meet at the anchors, so the lift tapers to nothing there.
            let p = h.point(at: u, drop: drop) + V2(0, lift * sin(u * .pi))
            return p.point
        }
        func strandPath(_ i: Int) -> CGPath {
            let p = CGMutablePath()
            p.move(to: strandPoint(i, 0))
            for k in 1...24 { p.addLine(to: strandPoint(i, CGFloat(k) / 24)) }
            return p
        }

        let alpha = fade * (1 - damage * 0.3)
        // The sheet between the lowest and highest strands.
        if progress > 0.5 {
            let sheet = CGMutablePath()
            sheet.move(to: strandPoint(0, 0))
            for k in 1...24 { sheet.addLine(to: strandPoint(0, CGFloat(k) / 24)) }
            for k in stride(from: 24, through: 0, by: -1) { sheet.addLine(to: strandPoint(strands - 1, CGFloat(k) / 24)) }
            sheet.closeSubpath()
            let a = remap(progress, 0.5, 1, 0, 0.26) * alpha * (1 - damage * 0.6)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: a))
            ctx.addPath(sheet)
            ctx.fillPath()
        }

        // Longitudinal strands, laid one at a time as it is built.
        let strandsShown = Int((progress * 1.6 * CGFloat(strands)).rounded(.down))
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75 * alpha))
        ctx.setLineWidth(1.1)
        for i in 0..<min(strands, strandsShown) where !tornAt(i) {
            ctx.addPath(strandPath(i))
            ctx.strokePath()
        }

        // Cross-ties, once the strands are down.
        if progress > 0.6 {
            let ties = 11
            let tiesShown = Int(remap(progress, 0.6, 1, 0, CGFloat(ties)).rounded(.down))
            ctx.setLineWidth(0.8)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6 * alpha))
            for k in 0..<min(ties, tiesShown) where !tornAt(40 + k) {
                let u = (CGFloat(k) + 0.5) / CGFloat(ties)
                let p = CGMutablePath()
                p.move(to: strandPoint(0, u))
                // A gentle zigzag rather than a straight rung.
                let mid = strandPoint(strands / 2, u)
                p.addLine(to: CGPoint(x: mid.x + (k % 2 == 0 ? 2 : -2), y: mid.y))
                p.addLine(to: strandPoint(strands - 1, u))
                ctx.addPath(p)
                ctx.strokePath()
            }
        }

        // Clews: the strands gather to each anchor, with a tuft on the wall
        // and the ceiling where the silk is stuck down.
        ctx.setLineWidth(1.0)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8 * alpha))
        for (anchor, seed) in [(h.wallAnchor, 70), (h.ceilingAnchor, 71)] where !tornAt(seed) {
            let a = anchor.point
            for i in 0..<3 {
                let ang = CGFloat(i) * 2.1 + 0.4
                ctx.beginPath()
                ctx.move(to: a)
                ctx.addLine(to: CGPoint(x: a.x + cos(ang) * 5, y: a.y + sin(ang) * 3.5))
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
