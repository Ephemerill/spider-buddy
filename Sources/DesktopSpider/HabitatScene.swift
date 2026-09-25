import AppKit
import QuartzCore

// MARK: - The inside of the tank

/// Everything behind the glass, as a stack of layers: the painted backdrop,
/// the things that drift and glow in its air, the furniture, the spider
/// and anything loose in there, foliage in front of it, and the glass.
/// All the movement is Core Animation's; the spider is placed each frame
/// by the app's clock like it is on the desktop, but drawn in here, so the
/// tank's furniture can be in front of it and other windows can cover it.
///
/// Decorating, the furniture takes the mouse instead of the spider: click
/// to pick a thing up, drag it, pull a corner to size it.
final class HabitatSceneView: NSView {
    let map = SurfaceMap()
    weak var spider: Spider?
    private(set) var habitat = Habitat()

    /// A change made here by hand, finished: what it was before, and now.
    var onEdit: ((Habitat, Habitat) -> Void)?
    var onSelect: ((Int?) -> Void)?
    /// Keys the tank passes up: undo, redo, done.
    var onCommand: ((Command) -> Void)?
    enum Command { case undo, redo, done }

    var editing = false {
        didSet {
            guard editing != oldValue else { return }
            if !editing { select(nil) }
            refreshSelection()
            window?.invalidateCursorRects(for: self)
        }
    }
    private(set) var selected: Int?

    // The layers, back to front.
    private let world = CALayer()
    private let sky = CALayer()
    private var airBack = CALayer()
    private let scenery = CALayer()
    private var airMid = CALayer()
    private let ground = CALayer()
    private let backItems = CALayer()
    private let creatures = CALayer()
    private let silk = CAShapeLayer()
    private let spiderLayer = SpiderLayer()
    private var preyLayers: [ObjectIdentifier: PreyLayer] = [:]
    private let frontItems = CALayer()
    private var airFront = CALayer()
    private let glass = CALayer()
    private let editLayer = CALayer()
    private let selectionOutline = CAShapeLayer()
    private let hoverOutline = CAShapeLayer()
    private var handles: [CALayer] = []

    private var itemLayers: [Int: ItemLayer] = [:]
    /// What the backdrop was last painted for.
    private var paintedKey = ""
    private var atmosphereKey = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let root = layer else { return }
        root.masksToBounds = true
        root.backgroundColor = CGColor(gray: 0.1, alpha: 1)
        world.masksToBounds = true
        root.addSublayer(world)
        for l in [sky, airBack, scenery, airMid, ground, backItems, creatures, frontItems, airFront, glass] { world.addSublayer(l) }
        root.addSublayer(editLayer)
        creatures.addSublayer(silk)
        creatures.addSublayer(spiderLayer)
        silk.fillColor = nil
        silk.lineCap = .round
        silk.strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.62)
        silk.lineWidth = 1.1
        silk.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)
        silk.shadowOffset = CGSize(width: 0.5, height: -0.5)
        silk.shadowRadius = 1.2
        silk.shadowOpacity = 1
        silk.isHidden = true
        spiderLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        spiderLayer.needsDisplayOnBoundsChange = true
        spiderLayer.isHidden = true
        for l in [sky, scenery, ground, glass] { l.contentsGravity = .resize }
        // The editing overlay: an outline round the chosen thing, handles
        // at its corners, a fainter outline round whatever is under the
        // pointer.
        for o in [selectionOutline, hoverOutline] {
            o.fillColor = nil
            o.lineJoin = .round
            editLayer.addSublayer(o)
        }
        selectionOutline.strokeColor = NSColor.controlAccentColor.cgColor
        selectionOutline.lineWidth = 2
        selectionOutline.lineDashPattern = [6, 4]
        selectionOutline.shadowColor = CGColor(gray: 0, alpha: 0.5)
        selectionOutline.shadowRadius = 2
        selectionOutline.shadowOpacity = 1
        selectionOutline.shadowOffset = .zero
        hoverOutline.strokeColor = CGColor(gray: 1, alpha: 0.55)
        hoverOutline.lineWidth = 1.5
        hoverOutline.lineDashPattern = [4, 4]
        for _ in 0..<4 {
            let h = CALayer()
            h.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
            h.cornerRadius = 6
            h.backgroundColor = CGColor(gray: 1, alpha: 1)
            h.borderColor = NSColor.controlAccentColor.cgColor
            h.borderWidth = 2
            h.shadowColor = CGColor(gray: 0, alpha: 0.4)
            h.shadowRadius = 2
            h.shadowOpacity = 1
            h.shadowOffset = CGSize(width: 0, height: -1)
            h.isHidden = true
            editLayer.addSublayer(h)
            handles.append(h)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: Where it is

    /// The scene is the view's bounds; these map the 900 × 540 scene onto it.
    private var sx: CGFloat { bounds.width / HabitatLayout.width }
    private var sy: CGFloat { bounds.height / HabitatLayout.height }
    func toView(_ r: CGRect) -> CGRect { CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy) }
    func toScene(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / max(sx, 0.001), y: p.y / max(sy, 0.001)) }
    var groundY: CGFloat { HabitatLayout.ground * sy }

    /// Where the scene sits on the screen, as last taken note of — the
    /// spider (which lives in screen coordinates) and everything drawn of
    /// it are kept in step with this, not with the window as it moves
    /// between one notice and the next.
    private(set) var screenOrigin = CGPoint.zero

    var screenScene: CGRect { CGRect(origin: screenOrigin, size: bounds.size) }
    /// The ground line, on the screen.
    var screenGroundY: CGFloat { screenOrigin.y + groundY }

    private func liveScreenOrigin() -> CGPoint {
        guard let w = window else { return .zero }
        return w.convertToScreen(convert(bounds, to: nil)).origin
    }

    /// The window moved or the scene was resized: the spider goes along
    /// with the scenery, and the surfaces are laid out afresh.
    func syncToScreen() {
        let was = CGRect(origin: screenOrigin, size: lastSize)
        let now = CGRect(origin: liveScreenOrigin(), size: bounds.size)
        screenOrigin = now.origin
        lastSize = now.size
        if let spider, spider.inHabitat, spider.map === map, was.width > 50 {
            if was.size == now.size {
                let d = V2(now.minX - was.minX, now.minY - was.minY)
                if d.length > 0.01 { spider.teleportQuietly(to: spider.worldPos + d) }
            } else {
                let u = (spider.worldPos.x - was.minX) / max(was.width, 1), v = (spider.worldPos.y - was.minY) / max(was.height, 1)
                spider.teleportQuietly(to: V2(now.minX + u * now.width, now.minY + v * now.height))
            }
        }
        rebuildMap()
    }
    private var lastSize = CGSize.zero

    func rebuildMap() {
        guard bounds.width > 100 else { return }
        let built = habitat.surfaces(in: screenScene, standoff: map.standoff)
        map.rebuild(habitat: built.air, loops: built.loops)
        if let spider, spider.inHabitat, spider.map === map { spider.mapChanged() }
    }

    func setStandoff(_ s: CGFloat) {
        guard abs(map.standoff - s) > 0.01 else { return }
        map.standoff = s
        rebuildMap()
    }

    /// Spots along the open ground, left to right, on the screen: the body
    /// line, where it would stand.
    func groundSpots() -> [V2] {
        let floor = screenGroundY + map.standoff
        return map.sampleSpots(spacing: 24).filter { $0.loop.id == "screen:0" && $0.seg.facing == .up && abs($0.point.y - floor) < 1 }.map(\.point)
    }

    // MARK: Laying out

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        world.frame = bounds
        editLayer.frame = bounds
        for l in [sky, airBack, scenery, airMid, backItems, creatures, frontItems, airFront, glass] { l.frame = bounds }
        let f = HabitatArt.Frame(rect: bounds)
        ground.frame = CGRect(x: 0, y: 0, width: bounds.width, height: f.groundY + HabitatArt.groundOverhang(f))
        placeItems()
        CATransaction.commit()
        if !inLiveResize { repaint() }
        if abs(bounds.width - lastSize.width) > 0.5 || abs(bounds.height - lastSize.height) > 0.5 || screenOrigin != liveScreenOrigin() {
            syncToScreen()
        }
        refreshSelection()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        repaint()
        syncToScreen()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        paintedKey = ""
        for l in itemLayers.values { l.paintedKey = "" }
        repaint()
    }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    /// Paints whatever is out of date: the backdrop for this biome and
    /// size, the furniture, and the moving air.
    private func repaint() {
        guard bounds.width > 100 else { return }
        let key = "\(habitat.biome.rawValue)-\(Int(bounds.width))x\(Int(bounds.height))-\(scale)"
        if key != paintedKey {
            paintedKey = key
            let b = habitat.biome
            let r = CGRect(origin: .zero, size: bounds.size)
            let f = HabitatArt.Frame(rect: r)
            // The sky is soft all over: half the pixels do.
            let skyImg = HabitatArt.image(r.size, scale: max(1, scale / 2)) { HabitatArt.paintSky(b, in: r, $0) }
            let sceneryImg = HabitatArt.image(r.size, scale: scale) { HabitatArt.paintScenery(b, in: r, $0) }
            let gh = f.groundY + HabitatArt.groundOverhang(f)
            let groundImg = HabitatArt.image(CGSize(width: r.width, height: gh), scale: scale) { HabitatArt.paintGround(b, in: r, $0) }
            let glassImg = HabitatArt.image(r.size, scale: max(1, scale / 2)) { HabitatArt.paintGlass(in: r, $0, dark: b == .night || b == .cave) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sky.contents = skyImg
            scenery.contents = sceneryImg
            ground.contents = groundImg
            glass.contents = glassImg
            CATransaction.commit()
        }
        let akey = "\(habitat.biome.rawValue)-\(Int(bounds.width))x\(Int(bounds.height))"
        if akey != atmosphereKey {
            atmosphereKey = akey
            buildAtmosphere()
        }
        paintItems()
    }

    // MARK: The habitat

    /// Shows `h`. A new scenery fades in over the old.
    func setHabitat(_ h: Habitat, fade: Bool = false) {
        guard h != habitat else { return }
        if fade {
            let t = CATransition()
            t.type = .fade
            t.duration = 0.45
            world.add(t, forKey: "fade")
        }
        habitat = h
        if let s = selected, !h.items.contains(where: { $0.id == s }) { select(nil) }
        syncItemLayers()
        repaint()
        rebuildMap()
        refreshSelection()
    }

    /// One layer per thing, in the right container, in order.
    private func syncItemLayers() {
        let ids = Set(habitat.items.map(\.id))
        for (id, l) in itemLayers where !ids.contains(id) {
            l.removeFromSuperlayer()
            itemLayers[id] = nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, it) in habitat.items.enumerated() {
            let l = itemLayers[it.id] ?? {
                let n = ItemLayer()
                itemLayers[it.id] = n
                return n
            }()
            l.item = it
            let parent = it.inFront ? frontItems : backItems
            if l.superlayer !== parent { l.removeFromSuperlayer(); parent.addSublayer(l) }
            l.zPosition = CGFloat(i)
        }
        placeItems()
        CATransaction.commit()
    }

    /// Frames for every thing's layer: its rectangle and the room round it.
    private func placeItems() {
        for l in itemLayers.values { place(l) }
    }

    private func place(_ l: ItemLayer) {
        let it = l.item
        let r = toView(it.rect)
        let pad = HabitatArt.itemPad(r.size)
        let full = r.insetBy(dx: -pad, dy: -pad)
        // It sways about its foot (or, hanging, the top it hangs from).
        let anchor = CGPoint(x: 0.5, y: it.kind.hangs ? (full.height - pad) / full.height : pad / full.height)
        l.anchorPoint = anchor
        l.bounds = CGRect(origin: .zero, size: full.size)
        l.position = CGPoint(x: full.minX + full.width * anchor.x, y: full.minY + full.height * anchor.y)
    }

    private func paintItems() {
        for l in itemLayers.values { l.paint(biome: habitat.biome, scale: scale, size: toView(l.item.rect).size) }
    }

    // MARK: The moving air

    private func buildAtmosphere() {
        for old in [airBack, airMid, airFront] { old.removeFromSuperlayer() }
        airBack = CALayer(); airMid = CALayer(); airFront = CALayer()
        world.insertSublayer(airBack, above: sky)
        world.insertSublayer(airMid, above: scenery)
        world.insertSublayer(airFront, above: frontItems)
        for l in [airBack, airMid, airFront] { l.frame = bounds }
        HabitatAtmosphere.build(habitat.biome, size: bounds.size, back: airBack, mid: airMid, front: airFront)
    }

    /// Stops everything moving while no part of the tank can be seen.
    func setAnimating(_ on: Bool) {
        if on, world.speed == 0 {
            let paused = world.timeOffset
            world.speed = 1
            world.timeOffset = 0
            world.beginTime = 0
            world.beginTime = world.convertTime(CACurrentMediaTime(), from: nil) - paused
        } else if !on, world.speed != 0 {
            let now = world.convertTime(CACurrentMediaTime(), from: nil)
            world.speed = 0
            world.timeOffset = now
        }
    }

    // MARK: The spider, and what is loose in here

    private var drawn: SpiderPose?
    private var drawnAt: CFTimeInterval = 0
    private(set) var didRedraw = false

    /// Places the spider (nil: it is not in here to be seen — out, or in
    /// your hand), its line, and anything loose, for this frame.
    func showCreatures(_ pose: SpiderPose?, sprite: CGFloat, prey: [Prey]) {
        didRedraw = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let o = V2(screenOrigin)
        if let pose {
            if spiderLayer.isHidden { spiderLayer.isHidden = false; drawn = nil }
            if spiderLayer.bounds.width != sprite {
                spiderLayer.bounds = CGRect(x: 0, y: 0, width: sprite, height: sprite)
                spiderLayer.contentsScale = scale
                drawn = nil
            }
            spiderLayer.position = CGPoint(x: pose.pos.x - o.x, y: pose.pos.y - o.y)
            spiderLayer.pose = pose
            let now = CACurrentMediaTime()
            let hold: CFTimeInterval = pose.outfit.isAnimated ? 1.0 / 30.0 : 0.5
            if drawn == nil || now - drawnAt >= hold || drawn!.outfit != pose.outfit || SpiderView.shapeDelta(drawn!, pose) >= 0.04 {
                drawn = pose
                drawnAt = now
                didRedraw = true
                spiderLayer.setNeedsDisplay()
            }
            if pose.web != nil, let path = SpiderRenderer.silkPath(pose, origin: o) {
                silk.path = path
                silk.opacity = Float(pose.web?.alpha ?? 1)
                silk.isHidden = false
            } else if !silk.isHidden {
                silk.isHidden = true
                silk.path = nil
            }
        } else {
            spiderLayer.isHidden = true
            silk.isHidden = true
        }
        // The creatures.
        var live = Set<ObjectIdentifier>()
        for p in prey {
            let id = ObjectIdentifier(p)
            live.insert(id)
            let l = preyLayers[id] ?? {
                let n = PreyLayer()
                n.contentsScale = scale
                creatures.insertSublayer(n, below: silk)
                preyLayers[id] = n
                return n
            }()
            l.prey = p
            let side = 52 * p.drawScale
            if l.bounds.width != side { l.bounds = CGRect(x: 0, y: 0, width: side, height: side) }
            l.position = CGPoint(x: p.pos.x - o.x, y: p.pos.y - o.y)
            l.setNeedsDisplay()
            didRedraw = true
        }
        for (id, l) in preyLayers where !live.contains(id) {
            l.removeFromSuperlayer()
            preyLayers[id] = nil
        }
    }

    /// The colour behind a point on the screen, for a camouflaged coat:
    /// the backdrop at that spot.
    func colourBehind(_ p: V2) -> RGB? {
        func image(_ any: Any?) -> CGImage? {
            guard let any, CFGetTypeID(any as CFTypeRef) == CGImage.typeID else { return nil }
            return (any as! CGImage)
        }
        guard let img = image(scenery.contents), let skyImg = image(sky.contents) else { return nil }
        let local = CGPoint(x: p.x - screenOrigin.x, y: p.y - screenOrigin.y)
        guard bounds.contains(local) else { return nil }
        let r: CGFloat = 30
        let patch = CGRect(x: local.x - r, y: local.y - r, width: r * 2, height: r * 2).intersection(bounds)
        // Sky and scenery both: draw the two over each other in a patch.
        guard let merged = HabitatArt.image(patch.size, scale: 0.5, { ctx in
            ctx.translateBy(x: -patch.minX, y: -patch.minY)
            ctx.draw(skyImg, in: bounds)
            ctx.draw(img, in: bounds)
        }) else { return nil }
        return AppDelegate.dominant(of: merged)
    }

    // MARK: Mouse: the spider

    private var dragSamples: [(p: V2, t: TimeInterval)] = []
    private var holdingSpider = false
    private var pressedAt = V2.zero
    private var pressTime: TimeInterval = 0
    private var grabbedPrey: Prey?

    private func world(_ e: NSEvent) -> V2 {
        let p = convert(e.locationInWindow, from: nil)
        return V2(p.x + screenOrigin.x, p.y + screenOrigin.y)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if editing { editMouseDown(event); return }
        guard let spider else { return }
        let w = world(event)
        pressedAt = w
        pressTime = event.timestamp
        dragSamples = [(w, event.timestamp)]
        if spider.inHabitat, spider.hitTest(w) {
            if event.clickCount >= 2 {
                spider.celebrate()
            } else {
                spider.beginGrab(at: w)
                holdingSpider = true
                NSCursor.closedHand.push()
            }
        } else if spider.inHabitat, let p = spider.preyHit(w) {
            grabbedPrey = p
            spider.beginPreyGrab(p, at: w)
        } else {
            tapGlass(at: convert(event.locationInWindow, from: nil))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if editing { editMouseDragged(event); return }
        guard let spider else { return }
        let w = world(event)
        dragSamples.append((w, event.timestamp))
        if dragSamples.count > 8 { dragSamples.removeFirst(dragSamples.count - 8) }
        if holdingSpider { spider.moveGrab(to: w) }
        if let p = grabbedPrey { spider.movePreyGrab(p, to: w) }
    }

    override func mouseUp(with event: NSEvent) {
        if editing { editMouseUp(event); return }
        guard let spider else { return }
        let w = world(event)
        defer { holdingSpider = false; grabbedPrey = nil; dragSamples = [] }
        var v = V2.zero
        if let first = dragSamples.first, dragSamples.count > 1 {
            if event.timestamp - first.t < 0.22 {
                v = (w - first.p) / CGFloat(max(event.timestamp - first.t, 0.008))
            } else if let recent = dragSamples.last(where: { event.timestamp - $0.t > 0.04 }) {
                v = (w - recent.p) / CGFloat(max(event.timestamp - recent.t, 0.008))
            }
        }
        if let p = grabbedPrey { spider.endPreyGrab(p, throwVelocity: v) }
        guard holdingSpider else { return }
        NSCursor.pop()
        if w.distance(to: pressedAt) < 4 && event.timestamp - pressTime < 0.35 {
            spider.endGrab(throwVelocity: .zero)
            spider.poke()
        } else {
            spider.endGrab(throwVelocity: v)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard !editing, let spider, spider.inHabitat else { return }
        spider.scroll(event.scrollingDeltaY)
    }

    override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .spiderContextMenu, object: event)
    }

    /// A tap on the glass: a little ring where it was tapped.
    private func tapGlass(at p: CGPoint) {
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -14, y: -14, width: 28, height: 28), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = CGColor(gray: 1, alpha: 0.7)
        ring.lineWidth = 1.5
        ring.position = p
        editLayer.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [grow, fade]
        g.duration = 0.45
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.opacity = 0
        ring.add(g, forKey: "tap")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ring.removeFromSuperlayer() }
    }

    // MARK: Decorating

    private enum Drag { case none, move(id: Int, offset: CGPoint), resize(id: Int, from: HabitatItem, anchor: CGPoint, startDist: CGFloat) }
    private var drag = Drag.none
    private var before: Habitat?
    private var hovered: Int?

    /// The thing at a point in the view, front first.
    private func itemAt(_ p: CGPoint) -> HabitatItem? {
        let ordered = habitat.items.enumerated().sorted { a, b in
            if a.element.inFront != b.element.inFront { return a.element.inFront }
            return a.offset > b.offset
        }
        // A tight box first — its drawn body — then the looser one.
        for (_, it) in ordered where toView(Habitat.solidRect(it) ?? it.rect).insetBy(dx: -6, dy: -6).contains(p) { return it }
        for (_, it) in ordered where toView(it.rect).insetBy(dx: -4, dy: -4).contains(p) { return it }
        return nil
    }

    private func handleRects(_ it: HabitatItem) -> [CGRect] {
        let r = toView(it.rect).insetBy(dx: -5, dy: -5)
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            .map { CGRect(x: $0.x - 9, y: $0.y - 9, width: 18, height: 18) }
    }

    func select(_ id: Int?) {
        guard id != selected else { return }
        selected = id
        refreshSelection()
        onSelect?(id)
    }

    private func refreshSelection() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let item = selected.flatMap { id in habitat.items.first { $0.id == id } }
        if editing, let it = item, let l = itemLayers[it.id] {
            // Follow the layer, which leads the model while it is dragged.
            let r = liveRect(it, layer: l).insetBy(dx: -5, dy: -5)
            selectionOutline.path = CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)
            selectionOutline.isHidden = false
            let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            for (h, p) in zip(handles, corners) { h.position = p; h.isHidden = false }
        } else {
            selectionOutline.isHidden = true
            for h in handles { h.isHidden = true }
        }
        if editing, let id = hovered, id != selected, let it = habitat.items.first(where: { $0.id == id }) {
            hoverOutline.path = CGPath(roundedRect: toView(it.rect).insetBy(dx: -4, dy: -4), cornerWidth: 6, cornerHeight: 6, transform: nil)
            hoverOutline.isHidden = false
        } else {
            hoverOutline.isHidden = true
        }
    }

    /// Where a thing is drawn right now, from its layer.
    private func liveRect(_ it: HabitatItem, layer l: ItemLayer) -> CGRect {
        let pad = HabitatArt.itemPad(toView(it.rect).size)
        let f = l.frame
        return f.insetBy(dx: pad * f.width / max(l.bounds.width, 1), dy: pad * f.height / max(l.bounds.height, 1))
    }

    override func mouseMoved(with event: NSEvent) {
        guard editing else { return }
        let p = convert(event.locationInWindow, from: nil)
        let id = itemAt(p)?.id
        if id != hovered { hovered = id; refreshSelection() }
        updateCursor(at: p)
    }

    override func mouseExited(with event: NSEvent) {
        if hovered != nil { hovered = nil; refreshSelection() }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    private func updateCursor(at p: CGPoint) {
        guard editing else { NSCursor.arrow.set(); return }
        if let id = selected, let it = habitat.items.first(where: { $0.id == id }), handleRects(it).contains(where: { $0.contains(p) }) {
            NSCursor.crosshair.set()
        } else if itemAt(p) != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func editMouseDown(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        before = habitat
        if let id = selected, let it = habitat.items.first(where: { $0.id == id }), handleRects(it).contains(where: { $0.contains(p) }) {
            let r = toView(it.rect)
            let anchor = CGPoint(x: r.midX, y: it.kind.hangs ? r.maxY : r.minY)
            drag = .resize(id: id, from: it, anchor: anchor, startDist: max(hypot(p.x - anchor.x, p.y - anchor.y), 8))
            return
        }
        if let it = itemAt(p) {
            select(it.id)
            // Where on it it was taken hold of, so it does not jump to the pointer.
            let sp = toScene(p)
            drag = .move(id: it.id, offset: CGPoint(x: it.x - sp.x, y: it.y - (sp.y - HabitatLayout.ground)))
            NSCursor.closedHand.set()
        } else {
            select(nil)
            drag = .none
        }
    }

    private func editMouseDragged(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .none:
            return
        case .move(let id, let offset):
            guard let i = habitat.items.firstIndex(where: { $0.id == id }) else { return }
            var it = habitat.items[i]
            let sp = toScene(p)
            it.x = sp.x + offset.x
            if it.kind.hangs {
                it.y = HabitatLayout.height
            } else if HabitatSceneView.liftable(it.kind) {
                let y = sp.y - HabitatLayout.ground + offset.y
                // Near the ground it sits on it.
                it.y = y < 12 ? 0 : y
            } else {
                it.y = 0
            }
            Habitat.clamp(&it)
            habitat.items[i] = it
            moveLayer(it)
        case .resize(let id, let from, let anchor, let startDist):
            guard let i = habitat.items.firstIndex(where: { $0.id == id }) else { return }
            let d = hypot(p.x - anchor.x, p.y - anchor.y)
            let base = from.kind.defaultSize
            var k = d / startDist
            // Between a third and three times its usual size.
            k = min(max(k, 0.35 * base.width / from.w), 3 * base.width / from.w)
            var it = from
            it.w = from.w * k
            it.h = from.h * k
            Habitat.clamp(&it)
            habitat.items[i] = it
            moveLayer(it)
        }
    }

    private func editMouseUp(_ event: NSEvent) {
        defer { drag = .none; before = nil }
        switch drag {
        case .none:
            return
        case .move(let id, _):
            settle(id)
            commit()
            updateCursor(at: convert(event.locationInWindow, from: nil))
        case .resize:
            commit()
            updateCursor(at: convert(event.locationInWindow, from: nil))
        }
    }

    /// Let go of up in the air, a thing comes to rest on whatever it is
    /// over — the top of a log or a stone, or the ground. (A branch stays
    /// where it is put: it is wedged there.)
    private func settle(_ id: Int) {
        guard let i = habitat.items.firstIndex(where: { $0.id == id }) else { return }
        var it = habitat.items[i]
        guard !it.kind.hangs, it.kind != .branch, it.y > 0 else { return }
        let lo = it.x - it.w * 0.25, hi = it.x + it.w * 0.25
        var rest: CGFloat = 0
        for o in habitat.items where o.id != id && !o.kind.hangs {
            guard let s = Habitat.solidRect(o), s.maxX > lo, s.minX < hi else { continue }
            let top = s.maxY - HabitatLayout.ground
            if top <= it.y + 8 { rest = max(rest, top) }
        }
        guard abs(rest - it.y) > 0.5 else { return }
        let fromY = itemLayers[id]?.position.y
        it.y = rest
        Habitat.clamp(&it)
        habitat.items[i] = it
        moveLayer(it)
        if let l = itemLayers[id], let fromY {
            let drop = CASpringAnimation(keyPath: "position.y")
            drop.fromValue = fromY
            drop.toValue = l.position.y
            drop.damping = 14
            drop.stiffness = 260
            drop.duration = drop.settlingDuration
            l.add(drop, forKey: "settle")
        }
    }

    /// Moves a thing's layer to where the model now has it, without
    /// painting it again (a resize is painted afresh when it is let go).
    private func moveLayer(_ it: HabitatItem) {
        guard let l = itemLayers[it.id] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.item = it
        place(l)
        CATransaction.commit()
        refreshSelection()
    }

    /// An edit is finished: paint what changed, lay the surfaces out again,
    /// and pass it on to be saved.
    private func commit() {
        guard let before, before != habitat else { return }
        syncItemLayers()
        paintItems()
        rebuildMap()
        refreshSelection()
        onEdit?(before, habitat)
    }

    /// Things that may be put up off the ground: what is propped or rests
    /// on other things. Rocks and pots and the like stand on the ground.
    static func liftable(_ kind: HabitatItemKind) -> Bool {
        switch kind {
        case .branch, .driftwood, .log, .moss, .mushrooms, .leafPile, .pebbles, .twigs, .flower, .fern, .grass, .succulent, .crystal: return true
        default: return false
        }
    }

    // MARK: Editing from outside

    /// Changes the chosen thing, as one edit — or `silently`, as part of
    /// one the caller will record when it is done.
    func updateSelected(silently: Bool = false, _ f: (inout HabitatItem) -> Void) {
        guard let id = selected, let i = habitat.items.firstIndex(where: { $0.id == id }) else { return }
        let was = habitat
        var it = habitat.items[i]
        f(&it)
        Habitat.clamp(&it)
        habitat.items[i] = it
        guard was != habitat else { return }
        syncItemLayers()
        paintItems()
        rebuildMap()
        refreshSelection()
        if silently { habitat.save() } else { onEdit?(was, habitat) }
    }

    /// Replaces the whole habitat as one edit (a layout, the scenery,
    /// clearing it out).
    func replace(with h: Habitat, fade: Bool) {
        let was = habitat
        setHabitat(h, fade: fade)
        if was != h { onEdit?(was, h) }
    }

    /// Puts a new thing in, somewhere with room for it, dropping it in
    /// from a little above.
    func add(_ kind: HabitatItemKind) {
        var h = habitat
        let size = kind.defaultSize
        // The most open stretch of ground: furthest from everything else.
        var bestX: CGFloat = HabitatLayout.width / 2
        var best: CGFloat = -1
        for step in 0..<40 {
            let x = size.width / 2 + 20 + CGFloat(step) / 39 * (HabitatLayout.width - size.width - 40)
            let gap = h.items.filter { $0.kind.hangs == kind.hangs }.map { max(0, abs($0.x - x) - ($0.w + size.width) / 2) }.min() ?? 900
            let score = min(gap, 300) + CGFloat.random(in: 0...20) - abs(x - HabitatLayout.width / 2) * 0.05
            if score > best { best = score; bestX = x }
        }
        let it = h.add(kind, at: CGPoint(x: bestX, y: kind.hangs ? HabitatLayout.height : 0))
        let was = habitat
        setHabitat(h)
        onEdit?(was, h)
        select(it.id)
        // In it drops, with a little bounce.
        if let l = itemLayers[it.id] {
            let fall = CASpringAnimation(keyPath: "position.y")
            fall.fromValue = l.position.y + (kind.hangs ? 60 : 80)
            fall.toValue = l.position.y
            fall.damping = 12
            fall.stiffness = 220
            fall.mass = 1
            fall.duration = fall.settlingDuration
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.2
            l.add(fall, forKey: "drop")
            l.add(fade, forKey: "appear")
        }
    }

    func removeSelected() {
        guard let id = selected else { return }
        let was = habitat
        var h = habitat
        h.items.removeAll { $0.id == id }
        select(nil)
        setHabitat(h)
        onEdit?(was, h)
    }

    func duplicateSelected() {
        guard let id = selected, let it = habitat.items.first(where: { $0.id == id }) else { return }
        let was = habitat
        var h = habitat
        var copy = it
        copy.id = h.nextID
        h.nextID += 1
        copy.x = it.x + (it.x > HabitatLayout.width - 120 ? -1 : 1) * max(40, it.w * 0.6)
        copy.seed = Int.random(in: 1...9999)
        Habitat.clamp(&copy)
        h.items.append(copy)
        setHabitat(h)
        onEdit?(was, h)
        select(copy.id)
    }

    /// Brings the chosen thing to the very front of its layer.
    func bringToFront() {
        guard let id = selected, let i = habitat.items.firstIndex(where: { $0.id == id }) else { return }
        let was = habitat
        var h = habitat
        let it = h.items.remove(at: i)
        h.items.append(it)
        setHabitat(h)
        onEdit?(was, h)
    }

    func sendToBack() {
        guard let id = selected, let i = habitat.items.firstIndex(where: { $0.id == id }) else { return }
        let was = habitat
        var h = habitat
        let it = h.items.remove(at: i)
        h.items.insert(it, at: 0)
        setHabitat(h)
        onEdit?(was, h)
    }

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if cmd, chars == "z" { onCommand?(event.modifierFlags.contains(.shift) ? .redo : .undo); return }
        guard editing else { super.keyDown(with: event); return }
        if cmd, chars == "d" { duplicateSelected(); return }
        switch event.keyCode {
        case 51, 117: removeSelected()                       // delete, forward delete
        case 53: if selected != nil { select(nil) } else { onCommand?(.done) }   // escape
        case 123, 124, 125, 126:                             // arrows
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 2
            let d: CGPoint = [123: CGPoint(x: -step, y: 0), 124: CGPoint(x: step, y: 0), 125: CGPoint(x: 0, y: -step), 126: CGPoint(x: 0, y: step)][event.keyCode]!
            updateSelected { it in
                it.x += d.x
                if !it.kind.hangs, HabitatSceneView.liftable(it.kind) { it.y = max(0, it.y + d.y) }
            }
        default:
            if chars == "f", selected != nil { updateSelected { $0.flipped.toggle() }; return }
            super.keyDown(with: event)
        }
    }
}

// MARK: - A thing in the tank

/// One piece of furniture: its picture, and whatever moves on it — a sway,
/// a glow, ripples.
final class ItemLayer: CALayer {
    var item = HabitatItem(id: 0, kind: .rock, x: 0, y: 0, w: 1, h: 1)
    var paintedKey = ""
    private var extras: [CALayer] = []
    private var animatedKey = ""

    override init() {
        super.init()
        contentsGravity = .resize
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    override func action(forKey event: String) -> CAAction? { nil }

    /// Paints its picture if its look has changed, and sets it moving.
    func paint(biome: Biome, scale: CGFloat, size: CGSize) {
        let key = "\(item.kind.rawValue)-\(item.seed)-\(Int(size.width))x\(Int(size.height))-\(item.flipped)-\(biome.rawValue)-\(scale)-\(item.onGround)"
        guard key != paintedKey, size.width > 1 else { return }
        paintedKey = key
        let pad = HabitatArt.itemPad(size)
        contents = HabitatArt.itemImage(item, size: size, biome: biome, scale: scale)
        contentsScale = scale
        let akey = "\(item.kind.rawValue)-\(item.seed)-\(biome.rawValue)-\(Int(bounds.width))"
        if akey != animatedKey {
            animatedKey = akey
            animate(biome: biome, pad: pad)
        }
    }

    private func animate(biome: Biome, pad: CGFloat) {
        removeAllAnimations()
        for e in extras { e.removeFromSuperlayer() }
        extras = []
        let s = CGFloat(abs(item.seed % 997)) / 997
        if item.kind.sways {
            // A gentle lean to and fro, about its foot: bent, not turned,
            // so the foot stays put.
            let amount: CGFloat
            switch item.kind {
            case .bamboo: amount = 0.012
            case .plant: amount = 0.018
            case .vine: amount = 0.05
            default: amount = 0.035
            }
            let sway = CAKeyframeAnimation(keyPath: "transform")
            func shear(_ k: CGFloat) -> NSValue {
                var t = CATransform3DIdentity
                t.m21 = item.kind.hangs ? -k : k
                return NSValue(caTransform3D: t)
            }
            sway.values = [shear(-amount), shear(amount * 0.6), shear(-amount * 0.4), shear(amount), shear(-amount)]
            sway.keyTimes = [0, 0.3, 0.5, 0.75, 1]
            sway.duration = CFTimeInterval(4.5 + s * 3)
            sway.repeatCount = .infinity
            sway.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
            sway.timeOffset = CFTimeInterval(s) * sway.duration
            add(sway, forKey: "sway")
        }
        let r = CGRect(x: pad, y: pad, width: bounds.width - pad * 2, height: bounds.height - pad * 2)
        if let glow = HabitatArt.glowColour(item.kind, seed: item.seed, biome: biome) {
            // A soft light that breathes.
            let g = CALayer()
            let radius = max(r.width, r.height) * 0.75
            g.contents = HabitatArt.softDot(radius, HabitatArt.alpha(glow, 0.55), core: 0.2)
            g.frame = CGRect(x: r.midX - radius, y: r.minY + r.height * 0.45 - radius, width: radius * 2, height: radius * 2)
            g.compositingFilter = "screenBlendMode"
            addSublayer(g)
            extras.append(g)
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 0.45
            breathe.toValue = 1
            breathe.duration = CFTimeInterval(2.2 + s * 1.5)
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timeOffset = CFTimeInterval(s) * breathe.duration
            g.add(breathe, forKey: "breathe")
            // Crystals catch the light now and then: a glint.
            if item.kind == .crystal {
                let glint = CALayer()
                glint.contents = HabitatArt.softDot(6, HabitatArt.c(1, 1, 1, 1), core: 0.15)
                glint.frame = CGRect(x: r.midX - 6 + (item.flipped ? 4 : -4), y: r.minY + r.height * 0.75 - 6, width: 12, height: 12)
                addSublayer(glint)
                extras.append(glint)
                let twinkle = CAKeyframeAnimation(keyPath: "opacity")
                twinkle.values = [0, 0, 1, 0, 0]
                twinkle.keyTimes = [0, 0.6, 0.68, 0.76, 1]
                twinkle.duration = CFTimeInterval(4 + s * 3)
                twinkle.repeatCount = .infinity
                twinkle.timeOffset = CFTimeInterval(s) * twinkle.duration
                glint.opacity = 0
                glint.add(twinkle, forKey: "twinkle")
            }
        }
        if item.kind == .waterDish {
            // Rings spreading on the water.
            let water = CGRect(x: r.minX + r.width * 0.1, y: r.minY + r.height * 0.45, width: r.width * 0.8, height: r.height * 0.36)
            for k in 0..<2 {
                let ring = CAShapeLayer()
                ring.path = CGPath(ellipseIn: CGRect(x: -water.width / 2, y: -water.height / 2, width: water.width, height: water.height), transform: nil)
                ring.fillColor = nil
                ring.strokeColor = CGColor(gray: 1, alpha: 0.7)
                ring.lineWidth = 1
                ring.position = CGPoint(x: water.midX, y: water.midY)
                ring.opacity = 0
                addSublayer(ring)
                extras.append(ring)
                let grow = CABasicAnimation(keyPath: "transform.scale")
                grow.fromValue = 0.15
                grow.toValue = 0.9
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 0.8, 0]
                fade.keyTimes = [0, 0.2, 1]
                let g = CAAnimationGroup()
                g.animations = [grow, fade]
                g.duration = 3.2
                g.repeatCount = .infinity
                g.timeOffset = CFTimeInterval(k) * 1.6 + CFTimeInterval(s)
                ring.add(g, forKey: "ripple")
            }
        }
    }
}

/// A creature loose in the tank.
final class PreyLayer: CALayer {
    var prey: Prey?
    override func action(forKey event: String) -> CAAction? { nil }
    override func draw(in ctx: CGContext) {
        guard let p = prey else { return }
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        if p.onSurface, p.state == .loose {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.14 * p.alpha))
            ctx.fillEllipse(in: CGRect(x: -9 * p.drawScale, y: -p.kind.clearance * p.drawScale - 2, width: 18 * p.drawScale, height: 3.5 * p.drawScale))
        }
        PreyRenderer.draw(p, in: ctx)
    }
}
