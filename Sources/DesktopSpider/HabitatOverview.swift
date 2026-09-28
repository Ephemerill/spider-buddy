import AppKit
import QuartzCore

// MARK: - The overview

/// The whole habitat at once, small, laid over the glass: a map of the
/// tank for finding your way about it and arranging it, not a view into
/// it (in the tank itself everything is always life size). It shows where
/// the glass is looking — a frame you can drag about — where the spider is
/// and anything loose; a click anywhere takes the glass there. Decorating,
/// the furniture can be picked up and moved anywhere in the world from
/// here, which is the easy way to rearrange a tank bigger than its window.
final class HabitatOverviewView: NSView {
    private weak var scene: HabitatSceneView?
    private let panel = CALayer()
    private let picture = CALayer()
    private let itemsLayer = CALayer()
    private var itemLayers: [Int: CALayer] = [:]
    private let dimOutside = CAShapeLayer()
    private let frameLayer = CAShapeLayer()
    private let pickLayer = CAShapeLayer()
    private let spiderRing = CAShapeLayer()
    private let spiderDot = CALayer()
    private var preyDots: [CALayer] = []
    private let heading = NSTextField(labelWithString: "Overview")
    private let hint = NSTextField(labelWithString: "")
    private let doneButton = HabitatButton(title: "Back to the Tank", symbol: "arrow.down.right.and.arrow.up.left")

    /// Where the world is drawn in here, and how small (points here to a
    /// world point).
    private var map = CGRect.zero
    private var k: CGFloat = 1
    private var paintedKey = ""
    private var itemsKey = ""

    private enum Press { case none, frame(moved: Bool), item(id: Int, grab: V2, moved: Bool), spider }
    private var press = Press.none
    private var pressAt = CGPoint.zero

    init(scene: HabitatSceneView) {
        self.scene = scene
        super.init(frame: scene.bounds)
        wantsLayer = true
        isHidden = true
        alphaValue = 0
        layer?.backgroundColor = CGColor(gray: 0.06, alpha: 0.93)
        panel.cornerRadius = 8
        panel.masksToBounds = true
        panel.borderColor = CGColor(gray: 1, alpha: 0.12)
        panel.borderWidth = 1
        layer?.addSublayer(panel)
        for l in [picture, itemsLayer] { l.anchorPoint = .zero; panel.addSublayer(l) }
        picture.contentsGravity = .resize
        dimOutside.fillRule = .evenOdd
        dimOutside.fillColor = CGColor(gray: 0, alpha: 0.28)
        frameLayer.fillColor = nil
        frameLayer.strokeColor = CGColor(gray: 1, alpha: 0.95)
        frameLayer.lineWidth = 2
        frameLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        frameLayer.shadowOpacity = 0.6
        frameLayer.shadowRadius = 3
        frameLayer.shadowOffset = .zero
        pickLayer.fillColor = nil
        pickLayer.strokeColor = NSColor.controlAccentColor.cgColor
        pickLayer.lineWidth = 2
        pickLayer.lineDashPattern = [4, 3]
        pickLayer.isHidden = true
        spiderRing.fillColor = nil
        spiderRing.strokeColor = CGColor(gray: 1, alpha: 0.9)
        spiderRing.lineWidth = 1.5
        spiderRing.path = CGPath(ellipseIn: CGRect(x: -9, y: -9, width: 18, height: 18), transform: nil)
        spiderDot.bounds = CGRect(x: 0, y: 0, width: 9, height: 9)
        spiderDot.cornerRadius = 4.5
        spiderDot.backgroundColor = NSColor.controlAccentColor.cgColor
        spiderDot.borderColor = CGColor(gray: 1, alpha: 1)
        spiderDot.borderWidth = 1.5
        for l in [dimOutside, pickLayer, frameLayer, spiderRing, spiderDot] as [CALayer] { panel.addSublayer(l) }
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.7
        pulse.toValue = 1.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [pulse, fade]
        g.duration = 1.6
        g.repeatCount = .infinity
        spiderRing.add(g, forKey: "pulse")

        heading.font = .systemFont(ofSize: 15, weight: .bold)
        heading.textColor = .white
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = NSColor(white: 1, alpha: 0.6)
        hint.lineBreakMode = .byTruncatingTail
        doneButton.translatesAutoresizingMaskIntoConstraints = true
        doneButton.target = self
        doneButton.action = #selector(close)
        doneButton.toolTip = "Back to looking into the tank, life size (Esc)"
        for v in [heading, hint, doneButton] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Showing it

    func present() {
        guard isHidden || alphaValue < 1 else { return }
        isHidden = false
        window?.makeFirstResponder(self)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard !isHidden else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.alphaValue < 0.01 else { return }
            self.isHidden = true
            if let s = self.scene { s.window?.makeFirstResponder(s) }
        })
    }

    @objc private func close() { scene?.showOverview(false) }

    override func layout() {
        super.layout()
        reload()
    }

    /// Back in step with the habitat: the picture of the world painted for
    /// this size, and a little picture of each thing in it.
    func reload() {
        guard let scene, bounds.width > 200, bounds.height > 150 else { return }
        let h = scene.habitat
        let top: CGFloat = 50, bottom: CGFloat = 36, side: CGFloat = 20
        let room = CGRect(x: side, y: bottom, width: bounds.width - side * 2, height: bounds.height - top - bottom)
        k = min(room.width / h.size.width, room.height / h.size.height)
        let size = CGSize(width: (h.size.width * k).rounded(), height: (h.size.height * k).rounded())
        map = CGRect(x: (room.midX - size.width / 2).rounded(), y: (room.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        panel.frame = map
        picture.frame = CGRect(origin: .zero, size: size)
        itemsLayer.frame = CGRect(origin: .zero, size: size)
        dimOutside.frame = CGRect(origin: .zero, size: size)
        heading.sizeToFit()
        heading.setFrameOrigin(CGPoint(x: side, y: bounds.height - 34))
        hint.stringValue = scene.editing
            ? "Drag anything to move it anywhere in the tank · click a spot to go there"
            : "Click anywhere to look there · drag the frame to look round"
        hint.frame = CGRect(x: side, y: 10, width: bounds.width - side * 2, height: 18)
        let bw = doneButton.intrinsicContentSize.width
        doneButton.frame = CGRect(x: bounds.width - side - bw, y: bounds.height - 40, width: bw, height: 30)
        let scale = window?.backingScaleFactor ?? 2
        let key = "\(h.biome.rawValue)-\(Int(size.width))x\(Int(size.height))-\(scale)-\(Int(h.size.width))"
        if key != paintedKey {
            paintedKey = key
            var bare = h
            bare.items = []
            picture.contents = HabitatArt.worldPicture(bare, size: size, scale: scale)
            itemsKey = ""
        }
        let ikey = key + h.items.map { "\($0.id):\(Int($0.x)),\(Int($0.y)),\(Int($0.w)),\(Int($0.h)),\($0.flipped),\($0.front),\($0.seed)" }.joined(separator: ";")
        if ikey != itemsKey {
            itemsKey = ikey
            let ids = Set(h.items.map(\.id))
            for (id, l) in itemLayers where !ids.contains(id) { l.removeFromSuperlayer(); itemLayers[id] = nil }
            for (i, it) in h.items.enumerated() {
                let l = itemLayers[it.id] ?? {
                    let n = CALayer()
                    n.contentsGravity = .resize
                    itemsLayer.addSublayer(n)
                    itemLayers[it.id] = n
                    return n
                }()
                let r = mapRect(it.rect)
                // Drawn at life size and shrunk, so it looks like itself.
                let pad = HabitatArt.itemPad(it.rect.size)
                l.contents = HabitatArt.itemImage(it, size: it.rect.size, biome: h.biome, scale: max(k * scale * 1.5, 0.25))
                l.frame = r.insetBy(dx: -pad * k, dy: -pad * k)
                l.zPosition = CGFloat(i) + (it.inFront ? 10_000 : 0)
            }
        }
    }

    /// Where the glass is, the spider, and what is loose.
    func refreshMarkers(spider: V2?, prey: [Prey]) {
        guard !isHidden, let scene, map.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let f = mapRect(scene.visibleWorld)
        frameLayer.path = CGPath(roundedRect: f, cornerWidth: 3, cornerHeight: 3, transform: nil)
        let dim = CGMutablePath()
        dim.addRect(CGRect(origin: .zero, size: map.size))
        dim.addRect(f)
        dimOutside.path = dim
        if let s = spider {
            spiderDot.isHidden = false
            spiderRing.isHidden = false
            spiderDot.position = mapPoint(s)
            spiderRing.position = mapPoint(s)
        } else {
            spiderDot.isHidden = true
            spiderRing.isHidden = true
        }
        while preyDots.count < prey.count {
            let d = CALayer()
            d.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
            d.cornerRadius = 2.5
            d.backgroundColor = CGColor(red: 1, green: 0.62, blue: 0.2, alpha: 1)
            panel.insertSublayer(d, below: spiderRing)
            preyDots.append(d)
        }
        for (i, d) in preyDots.enumerated() {
            d.isHidden = i >= prey.count
            if i < prey.count { d.position = mapPoint(prey[i].pos) }
        }
        refreshPick()
    }

    /// The outline round the thing picked, decorating.
    private func refreshPick() {
        guard let scene else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let id = scene.selected, scene.editing, let it = scene.habitat.items.first(where: { $0.id == id }) {
            pickLayer.path = CGPath(roundedRect: mapRect(it.rect).insetBy(dx: -3, dy: -3), cornerWidth: 3, cornerHeight: 3, transform: nil)
            pickLayer.isHidden = false
        } else {
            pickLayer.isHidden = true
        }
        CATransaction.commit()
    }

    // MARK: Between the map and the world

    private func mapPoint(_ p: V2) -> CGPoint { CGPoint(x: p.x * k, y: p.y * k) }
    private func mapRect(_ r: CGRect) -> CGRect { CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k) }
    /// A point in this view, in the world.
    private func worldPoint(_ v: CGPoint) -> V2 {
        V2((v.x - map.minX) / max(k, 1e-6), (v.y - map.minY) / max(k, 1e-6))
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let scene else { return }
        let v = convert(event.locationInWindow, from: nil)
        pressAt = v
        let w = worldPoint(v)
        scene.camera.touched()
        if let s = spiderDot.isHidden ? nil : spiderDot.position,
           hypot(v.x - map.minX - s.x, v.y - map.minY - s.y) < 12 {
            press = .spider
        } else if scene.editing, map.insetBy(dx: -6, dy: -6).contains(v), let it = scene.itemAt(w) ?? nearItem(w) {
            scene.select(it.id)
            press = .item(id: it.id, grab: V2(it.x, it.kind.hangs ? it.rect.maxY : it.rect.minY) - w, moved: false)
            refreshPick()
        } else if map.insetBy(dx: -30, dy: -30).contains(v) {
            press = .frame(moved: false)
        } else {
            press = .none
        }
    }

    /// Something within a few points of the pointer on the map (they are
    /// small in here).
    private func nearItem(_ w: V2) -> HabitatItem? {
        guard let scene else { return nil }
        let slop = 8 / max(k, 1e-6)
        return scene.habitat.items.last { $0.rect.insetBy(dx: -slop, dy: -slop).contains(w.point) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let scene else { return }
        let v = convert(event.locationInWindow, from: nil)
        let far = hypot(v.x - pressAt.x, v.y - pressAt.y) > 3
        switch press {
        case .frame(let moved):
            guard moved || far else { return }
            press = .frame(moved: true)
            scene.jump(toCentre: worldPoint(v))
        case .item(let id, let grab, let moved):
            guard moved || far, let l = itemLayers[id], let it = scene.habitat.items.first(where: { $0.id == id }) else { return }
            press = .item(id: id, grab: grab, moved: true)
            let at = worldPoint(v) + grab
            let r = it.rect
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let dx = (at.x - it.x) * k
            let dy = it.kind.hangs ? 0 : (it.kind.liftable ? (max(at.y, HabitatLayout.ground) - r.minY) * k : 0)
            let pad = HabitatArt.itemPad(r.size)
            l.frame = mapRect(r).insetBy(dx: -pad * k, dy: -pad * k).offsetBy(dx: dx, dy: dy)
            pickLayer.isHidden = true
            CATransaction.commit()
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let scene else { return }
        let v = convert(event.locationInWindow, from: nil)
        defer { press = .none }
        switch press {
        case .spider:
            if let s = scene.spider, s.inHabitat { scene.goTo(s.worldPos, spider: true) }
            scene.showOverview(false)
        case .frame(let moved):
            // A click: the glass goes there, and it is life size again.
            if !moved {
                scene.goTo(worldPoint(v), spider: false)
                scene.showOverview(false)
            }
        case .item(let id, let grab, let moved):
            if moved {
                scene.moveItem(id, to: worldPoint(v) + grab)
                reload()
                refreshPick()
            } else if let it = scene.habitat.items.first(where: { $0.id == id }) {
                // Picked: off to it, to work on it life size.
                scene.goTo(V2(it.x, it.rect.midY), spider: false)
                scene.showOverview(false)
            }
        case .none:
            break
        }
    }

    override func scrollWheel(with event: NSEvent) {}

    /// Tools only: where a world point is drawn in here, and a click there.
    func debugViewPoint(for w: V2) -> CGPoint { CGPoint(x: map.minX + w.x * k, y: map.minY + w.y * k) }
    func debugClick(at p: CGPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let e = NSEvent.mouseEvent(with: type, location: convert(p, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            if type == .leftMouseDown { mouseDown(with: e) } else { mouseUp(with: e) }
        }
    }
    override func rightMouseDown(with event: NSEvent) { close() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.charactersIgnoringModifiers?.lowercased() == "o" { close(); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            scene?.keyDown(with: event)
            reload()
            return
        }
        super.keyDown(with: event)
    }
}
