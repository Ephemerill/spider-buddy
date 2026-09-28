import AppKit
import QuartzCore

// MARK: - The inside of the tank

/// Everything behind the glass. The glass is a window onto a world bigger
/// than it (see HabitatCamera.swift): the view is the glass, and behind it
/// are three stacks of layers —
///
///  • the backdrop: the painted sky and scenery and what drifts in them,
///    moving half as far as the world does as the camera moves, the way
///    a far view does;
///  • the world: the substrate, the furniture, the spider and anything
///    loose in there, foliage in front of it, the tank's own air — all at
///    one to one with the screen, placed where they are in the world, and
///    moved as one by the camera;
///  • the glass itself, and what is right on it: its reflections, the
///    light, rain streaming past.
///
/// All the movement is Core Animation's; the spider is placed each frame
/// by the app's clock like it is on the desktop, but drawn in here, so the
/// tank's furniture can be in front of it and other windows can cover it.
/// Whatever is well out of sight is left out, and not drawn.
///
/// Dragging the bare glass looks round the tank; decorating, the furniture
/// takes the mouse instead of the spider: click to pick a thing up, drag
/// it, pull a corner to size it.
final class HabitatSceneView: NSView {
    let map = SurfaceMap()
    weak var spider: Spider?
    private(set) var habitat = Habitat()
    /// What part of the world the glass shows.
    let camera = HabitatCamera()

    /// A change made here by hand, finished: what it was before, and now.
    var onEdit: ((Habitat, Habitat) -> Void)?
    var onSelect: ((Int?) -> Void)?
    /// Keys the tank passes up: undo, redo, done.
    var onCommand: ((Command) -> Void)?
    enum Command { case undo, redo, done }

    /// The spider's name, for the button that finds it.
    var spiderName = "" { didSet { findButton.set(title: HabitatSceneView.findTitle(spiderName), symbol: findSymbol) } }

    var editing = false {
        didSet {
            guard editing != oldValue else { return }
            if !editing { select(nil) }
            refreshSelection()
            window?.invalidateCursorRects(for: self)
        }
    }
    private(set) var selected: Int?

    /// How far the backdrop moves for each point the world does.
    static let parallax: CGFloat = 0.5

    // The layers, back to front.
    private let world = CALayer()
    private let backdrop = CALayer()
    private let sky = CALayer()
    private var airBack = CALayer()
    private let scenery = CALayer()
    private var airMid = CALayer()
    private let content = CALayer()
    private let ground = CALayer()
    private let backItems = CALayer()
    private let creatures = CALayer()
    private let silk = CAShapeLayer()
    private let spiderLayer = SpiderLayer()
    private var preyLayers: [ObjectIdentifier: PreyLayer] = [:]
    private let frontItems = CALayer()
    private var airFront = CALayer()
    /// The tank's own ends and lid, in the world: the corners of the
    /// glass, where the world stops.
    private let tankEnds = CALayer()
    private let glass = CALayer()
    /// Decorating: outlines and handles, in the world.
    private let editLayer = CALayer()
    /// Taps on the glass, on the glass.
    private let tapLayer = CALayer()
    /// Developer only: the physical shape of things (see "Debug: shapes").
    private let geometryLayer = CALayer()
    private let geometryFooting = CAShapeLayer()
    private let geometryHUD = CATextLayer()
    private let selectionOutline = CAShapeLayer()
    private let hoverOutline = CAShapeLayer()
    private var handles: [CALayer] = []

    private var itemLayers: [Int: ItemLayer] = [:]
    /// What the backdrop, the ground, the glass and the air were last made for.
    private var backdropKey = "", groundKey = "", glassKey = "", atmosphereKey = ""
    /// The backdrop as it was painted.
    private var backdropSize = CGSize.zero
    private var atmos = HabitatAtmosphere.Built()

    /// The weather, drawn: its layers go in among the scene's own (see
    /// HabitatWeather.swift).
    let weatherFX = WeatherLayers()
    private var weatherDue: CGFloat = 0
    /// Tools only: it keeps moving even out of sight.
    var debugKeepAnimating = false
    /// Thunder, a moment after the lightning: where it came down, in the
    /// world, and how loud (1: right overhead).
    var onThunder: ((V2, CGFloat) -> Void)?

    /// Round the edge of the glass when the spider is out of sight: "Find
    /// it", pointing the way; it brings the camera back to it.
    private let findButton = HabitatButton(title: "Find", symbol: "scope")
    private var findSymbol = "scope"
    private var findShown = false
    /// The whole world, small: decorating it, and going anywhere in it.
    private(set) var overview: HabitatOverviewView?
    var overviewOpen: Bool { overview?.isHidden == false }
    var onOverviewChange: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let root = layer else { return }
        root.masksToBounds = true
        root.backgroundColor = CGColor(gray: 0.1, alpha: 1)
        world.masksToBounds = true
        root.addSublayer(world)
        let wx = weatherFX
        for l in [backdrop, content, wx.shade, wx.front, wx.flash, glass] { world.addSublayer(l) }
        for l in [sky, airBack, wx.back, scenery, airMid, wx.mid] { backdrop.addSublayer(l) }
        for l in [ground, wx.ground, backItems, wx.caps, creatures, frontItems, airFront, wx.fall, tankEnds, geometryLayer] { content.addSublayer(l) }
        for l in [backdrop, content, editLayer, tapLayer, sky, scenery, ground] { l.anchorPoint = .zero }
        wx.onThunder = { [weak self] p, loud in self?.thundered(at: p, loud: loud) }
        root.addSublayer(editLayer)
        root.addSublayer(tapLayer)
        root.addSublayer(geometryHUD)
        geometryLayer.isHidden = true
        geometryHUD.isHidden = true
        showsGeometry = ProcessInfo.processInfo.environment["SPIDER_HABITAT_GEOMETRY"] == "1"
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
        findButton.translatesAutoresizingMaskIntoConstraints = true
        findButton.target = self
        findButton.action = #selector(findSpider)
        findButton.alphaValue = 0
        findButton.isHidden = true
        findButton.wantsLayer = true
        findButton.layer?.shadowColor = CGColor(gray: 0, alpha: 1)
        findButton.layer?.shadowOpacity = 0.45
        findButton.layer?.shadowRadius = 6
        findButton.layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(findButton)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: Coordinate spaces
    //
    // The only conversions between the screen, the glass and the world
    // (see the top of HabitatCamera.swift). `shown` is the camera as it is
    // drawn — to the pixel — so a click lands on exactly what is under it.

    private var shown = V2.zero

    /// The glass's bottom-left, on the screen.
    private(set) var screenOrigin = CGPoint.zero

    /// The glass, on the screen.
    var glassOnScreen: CGRect { CGRect(origin: screenOrigin, size: bounds.size) }
    /// What the glass shows of the world.
    var visibleWorld: CGRect { CGRect(origin: shown.point, size: bounds.size) }

    func worldPoint(fromView p: CGPoint) -> V2 { V2(p.x + shown.x, p.y + shown.y) }
    func viewPoint(fromWorld p: V2) -> CGPoint { CGPoint(x: p.x - shown.x, y: p.y - shown.y) }
    func worldPoint(fromScreen p: V2) -> V2 { V2(p.x - screenOrigin.x + shown.x, p.y - screenOrigin.y + shown.y) }
    func screenPoint(fromWorld p: V2) -> V2 { V2(p.x - shown.x + screenOrigin.x, p.y - shown.y + screenOrigin.y) }
    /// How far a point moves going from the world out onto the screen.
    var worldToScreen: V2 { V2(screenOrigin.x - shown.x, screenOrigin.y - shown.y) }

    private func viewPoint(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
    private func worldPoint(_ e: NSEvent) -> V2 { worldPoint(fromView: viewPoint(e)) }
    private func screenPoint(_ e: NSEvent) -> V2 {
        let v = viewPoint(e)
        return V2(v.x + screenOrigin.x, v.y + screenOrigin.y)
    }
    /// A point where the spider is: the world while it is in here, the
    /// screen once it has been carried out through the glass.
    private func spiderPoint(fromScreen p: V2) -> V2 { spider?.map === map ? worldPoint(fromScreen: p) : p }

    /// Well within what the glass shows.
    func isInView(_ p: V2, margin: CGFloat = 0) -> Bool { visibleWorld.insetBy(dx: margin, dy: margin).contains(p.point) }

    /// The backdrop's bottom-left, on the glass, for the camera at `o`: it
    /// moves half as far as the world does, lined up with the world's middle
    /// across and with the ground at the bottom.
    private func backdropOrigin(_ o: V2) -> CGPoint {
        let k = HabitatSceneView.parallax, W = habitat.size, V = bounds.size, B = backdropSize
        return CGPoint(x: V.width / 2 - B.width / 2 - (o.x + V.width / 2 - W.width / 2) * k, y: -o.y * k)
    }

    private func liveScreenOrigin() -> CGPoint {
        guard let w = window else { return .zero }
        return w.convertToScreen(convert(bounds, to: nil)).origin
    }

    /// The window moved, or the glass was resized. Moved, the whole tank
    /// goes with it, and nothing in the world changes. Resized, the world
    /// stays where it is on the screen and the glass shows more or less of
    /// it: grown on the left, it shows more to the left.
    func syncToScreen() {
        let now = CGRect(origin: liveScreenOrigin(), size: bounds.size)
        let was = CGRect(origin: screenOrigin, size: lastSize)
        screenOrigin = now.origin
        if was.width > 50, now.size != was.size {
            camera.setView(now.size, shift: V2(now.minX - was.minX, now.minY - was.minY))
        } else {
            camera.setView(now.size)
        }
        lastSize = now.size
        applyCamera(force: true)
    }
    private var lastSize = CGSize.zero

    /// The surfaces, laid out afresh for the furniture as it stands — once
    /// for each change to it; the camera moving changes nothing.
    func rebuildMap() {
        map.rebuild(habitat: habitat.surfaces(standoff: map.standoff))
        if let spider, spider.inHabitat, spider.map === map { spider.mapChanged() }
        refreshGeometryOverlay()
    }

    func setStandoff(_ s: CGFloat) {
        guard abs(map.standoff - s) > 0.01 else { return }
        map.standoff = s
        rebuildMap()
    }

    /// Spots along the open ground, left to right, in the world (in `r`,
    /// if given): the body line, where it would stand.
    func groundSpots(in r: CGRect? = nil) -> [V2] {
        let floor = HabitatLayout.ground + map.standoff
        return map.sampleSpots(spacing: 24).filter {
            $0.loop.id.hasPrefix("screen:") && $0.seg.facing == .up && abs($0.point.y - floor) < 1 && (r?.contains($0.point.point) ?? true)
        }.map(\.point)
    }

    /// The top of the ground, on the screen, where the glass shows it —
    /// the lip it climbs in over. Nil if the ground is out of sight below.
    var groundLipOnScreen: CGFloat? {
        let y = HabitatLayout.ground - shown.y
        return y > 8 ? screenOrigin.y + y : nil
    }

    /// Open ground the glass shows, on the screen: where it can climb in.
    func visibleGroundSpotsOnScreen() -> [V2] {
        groundSpots(in: visibleWorld.insetBy(dx: 30, dy: -40)).map(screenPoint(fromWorld:))
    }

    // MARK: The camera

    /// The spider, as it was last given to the camera (nil: not in here to follow).
    private var lastSpider: V2?
    /// Decorating, the furniture being dragged is taken along to the edge
    /// of the glass: where the pointer last was on the glass.
    private var dragView: CGPoint?

    /// Each frame while the tank is open: the camera moves on (after the
    /// spider, if it is in here to follow and not in your hand), a thing
    /// dragged to the edge of the glass takes the camera with it, and what
    /// has come into sight is shown. True if anything moved.
    @discardableResult
    func tick(dt: CGFloat, spider s: V2?) -> Bool {
        lastSpider = s
        var moved = false
        if let v = dragView, isDraggingItem {
            let m: CGFloat = 44
            var d = V2.zero
            if v.x < m { d.x = -(m - max(v.x, -40)) } else if v.x > bounds.width - m { d.x = min(v.x, bounds.width + 40) - (bounds.width - m) }
            if v.y < m { d.y = -(m - max(v.y, -40)) } else if v.y > bounds.height - m { d.y = min(v.y, bounds.height + 40) - (bounds.height - m) }
            if d.lengthSquared > 0.01 {
                let before = camera.origin
                camera.pan(by: d * (11 * dt))
                if (camera.origin - before).lengthSquared > 1e-4 {
                    applyCamera()
                    dragItem(at: v)
                    moved = true
                }
            }
        }
        if camera.update(dt: dt, spider: s, follows: !editing && !overviewOpen) { moved = true }
        let wasShown = shown
        applyCamera()
        if (shown - wasShown).lengthSquared > 1e-6 { moved = true }
        if moved, camera.resting { camera.save() }
        updateFindButton()
        overview?.refreshMarkers(spider: s, prey: spider?.inHabitat == true ? spider?.prey ?? [] : [])
        return moved || !camera.resting
    }

    /// Where the camera is, drawn: the world and the edit marks moved
    /// under the glass, the backdrop moved half as far, and the weather and
    /// the air kept on what shows.
    private func applyCamera(force: Bool = false) {
        let s = max(scale, 1)
        let o = V2((camera.origin.x * s).rounded() / s, (camera.origin.y * s).rounded() / s)
        guard force || o.x != shown.x || o.y != shown.y else { return }
        shown = o
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = CGRect(x: o.x, y: o.y, width: bounds.width, height: bounds.height)
        content.bounds = r
        content.position = .zero
        editLayer.bounds = r
        editLayer.position = .zero
        var b = backdropOrigin(o)
        b = CGPoint(x: (b.x * s).rounded() / s, y: (b.y * s).rounded() / s)
        backdrop.position = b
        CATransaction.commit()
        weatherFX.follow(visible: r, backdrop: CGRect(x: -b.x, y: -b.y, width: bounds.width, height: bounds.height))
        HabitatAtmosphere.follow(atmos, visible: r)
        cull()
    }

    /// Only what is near the glass is shown (and painted, the first time
    /// it comes near); the rest is left out — still there, not drawn.
    private func cull() {
        let near = visibleWorld.insetBy(dx: -160, dy: -160)
        let soon = visibleWorld.insetBy(dx: -bounds.width, dy: -bounds.height * 0.8)
        let far = visibleWorld.insetBy(dx: -bounds.width * 2.5, dy: -bounds.height * 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in itemLayers.values {
            let f = l.frame
            if f.intersects(soon) {
                l.paint(biome: habitat.biome, scale: scale, size: l.item.rect.size)
            } else if !f.intersects(far) {
                // Well away: its picture goes, until it comes near again.
                l.unpaint()
            }
            let out = !f.intersects(near)
            if l.isHidden != out { l.isHidden = out }
        }
        weatherFX.showCaps(near: near)
        CATransaction.commit()
    }

    /// Straight to a spot (opening the tank): `p` in the middle of the glass.
    func lookAt(_ p: V2) {
        camera.jump(to: camera.centring(p))
        applyCamera(force: true)
    }

    /// Back to the spider, gliding.
    @objc func findSpider() {
        guard let s = lastSpider ?? (spider?.inHabitat == true ? spider?.worldPos : nil) else { return }
        camera.recall(to: s)
    }

    private static func findTitle(_ name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty || n.count > 16 ? "Find Your Spider" : "Find \(n)"
    }

    /// Shows the way back to the spider while it is out of sight — at the
    /// edge of the glass nearest to it, pointing to it.
    private func updateFindButton() {
        let want: Bool
        var toward = V2.zero
        if let s = lastSpider, !overviewOpen, bounds.width > 200 {
            let v = visibleWorld.insetBy(dx: -12, dy: -12)
            want = !v.contains(s.point)
            toward = s - V2(visibleWorld.midX, visibleWorld.midY)
        } else {
            want = false
        }
        if want {
            // Which way: one of eight.
            let a = atan2(toward.y, toward.x)
            let names = ["arrow.right", "arrow.up.right", "arrow.up", "arrow.up.left", "arrow.left", "arrow.down.left", "arrow.down", "arrow.down.right"]
            let i = (Int((a / (.pi / 4)).rounded()) % 8 + 8) % 8
            if names[i] != findSymbol {
                findSymbol = names[i]
                findButton.set(title: HabitatSceneView.findTitle(spiderName), symbol: findSymbol)
            }
            let size = CGSize(width: findButton.intrinsicContentSize.width, height: 30)
            // Along the edge, where a line from the middle toward it meets it.
            let inner = bounds.insetBy(dx: 16 + size.width / 2, dy: 16 + size.height / 2)
            let d = toward.normalized
            let tx = abs(d.x) > 1e-3 ? (inner.width / 2) / abs(d.x) : .greatestFiniteMagnitude
            let ty = abs(d.y) > 1e-3 ? (inner.height / 2) / abs(d.y) : .greatestFiniteMagnitude
            let t = min(tx, ty)
            let c = CGPoint(x: inner.midX + d.x * t, y: inner.midY + d.y * t)
            let frame = CGRect(x: (c.x - size.width / 2).rounded(), y: (c.y - size.height / 2).rounded(), width: size.width, height: size.height)
            if abs(findButton.frame.minX - frame.minX) > 2 || abs(findButton.frame.minY - frame.minY) > 2 || findButton.frame.width != frame.width {
                findButton.frame = frame
            }
        }
        guard want != findShown else { return }
        findShown = want
        if want { findButton.isHidden = false }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            findButton.animator().alphaValue = want ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self, !self.findShown else { return }
            self.findButton.isHidden = true
        })
    }

    /// Whether the spider can be seen through the glass just now.
    var spiderInSight: Bool { lastSpider.map { isInView($0, margin: -12) } ?? false }

    // MARK: The overview

    func showOverview(_ on: Bool) {
        if on {
            let o = overview ?? {
                let v = HabitatOverviewView(scene: self)
                v.autoresizingMask = [.width, .height]
                addSubview(v, positioned: .above, relativeTo: nil)
                overview = v
                return v
            }()
            o.frame = bounds
            o.reload()
            o.refreshMarkers(spider: lastSpider, prey: spider?.inHabitat == true ? spider?.prey ?? [] : [])
            o.present()
        } else {
            overview?.dismiss()
        }
        updateFindButton()
        onOverviewChange?(on)
    }

    /// Picked in the overview: the glass goes there (and follows the
    /// spider again if that is where).
    func goTo(_ p: V2, spider: Bool) {
        camera.glide(toCentre: p, thenFollow: spider)
    }

    /// Dragged in the overview: the glass is there, now.
    func jump(toCentre p: V2) {
        camera.beginPan()
        camera.jump(to: camera.centring(p))
        applyCamera()
    }

    // MARK: Laying out

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        world.frame = bounds
        tapLayer.frame = bounds
        glass.frame = bounds
        CATransaction.commit()
        if !inLiveResize { repaint() }
        if abs(bounds.width - lastSize.width) > 0.5 || abs(bounds.height - lastSize.height) > 0.5 || screenOrigin != liveScreenOrigin() {
            syncToScreen()
        }
        overview?.frame = bounds
        refreshSelection()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        repaint()
        syncToScreen()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        backdropKey = ""
        groundKey = ""
        glassKey = ""
        for l in itemLayers.values { l.paintedKey = "" }
        repaint()
    }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    /// The biggest the glass could be: the largest display's worth, and
    /// never more than the world. The backdrop is made wide enough for it,
    /// so resizing the window never has to paint the scenery again.
    private var glassMax: CGSize {
        var w = bounds.width, h = bounds.height
        for s in NSScreen.screens {
            w = max(w, s.visibleFrame.width)
            h = max(h, s.visibleFrame.height)
        }
        return CGSize(width: min(w, habitat.size.width), height: min(h, habitat.size.height))
    }

    /// The backdrop for this world: wide and tall enough that, moving half
    /// as far as the world does, it is behind the glass wherever it is.
    private var backdropWanted: CGSize {
        let k = HabitatSceneView.parallax, W = habitat.size, m = glassMax
        return CGSize(width: (W.width * k + m.width * (1 - k)).rounded(), height: (W.height * k + m.height * (1 - k)).rounded())
    }

    /// Paints whatever is out of date: the backdrop for this scenery and
    /// world, the ground, the glass for its size, the furniture near it,
    /// and the moving air.
    private func repaint() {
        guard bounds.width > 100 else { return }
        let b = habitat.biome, s = scale
        let bs = backdropWanted, ws = habitat.size
        let bkey = "\(b.rawValue)-\(Int(bs.width))x\(Int(bs.height))-\(s)"
        if bkey != backdropKey {
            backdropKey = bkey
            backdropSize = bs
            let f = HabitatArt.Frame(world: CGRect(origin: .zero, size: bs))
            let top = HabitatArt.sceneryTop(b, f)
            // The sky is soft all over: half the pixels do. The scenery is
            // far off, and moves half as far as the world: three-quarters
            // do. (It is a big picture, and the window server keeps a copy
            // of every picture a layer shows.)
            let skyImg = HabitatArt.image(bs, scale: max(1, s / 2)) { HabitatArt.paintSky(b, in: f, $0) }
            let sceneryImg = HabitatArt.image(CGSize(width: bs.width, height: top), scale: max(1, s * 0.75)) {
                HabitatArt.paintScenery(b, in: f, $0)
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            backdrop.bounds = CGRect(origin: .zero, size: bs)
            sky.frame = CGRect(origin: .zero, size: bs)
            scenery.frame = CGRect(x: 0, y: 0, width: bs.width, height: top)
            sky.contents = skyImg
            scenery.contents = sceneryImg
            CATransaction.commit()
        }
        let gkey = "\(b.rawValue)-\(Int(ws.width))-\(s)"
        if gkey != groundKey {
            groundKey = gkey
            let fw = HabitatArt.Frame(world: CGRect(origin: .zero, size: ws))
            let gh = fw.groundY + HabitatArt.groundOverhang(fw)
            let img = HabitatArt.image(CGSize(width: ws.width, height: gh), scale: s) { HabitatArt.paintGround(b, in: fw, $0) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ground.frame = CGRect(x: 0, y: 0, width: ws.width, height: gh)
            ground.contents = img
            for l in [backItems, creatures, frontItems] { l.frame = CGRect(origin: .zero, size: ws) }
            layOutTankEnds(ws)
            CATransaction.commit()
        }
        let dark = b == .night || b == .cave
        let glkey = "\(Int(bounds.width))x\(Int(bounds.height))-\(dark)-\(s)"
        if glkey != glassKey {
            glassKey = glkey
            let r = CGRect(origin: .zero, size: bounds.size)
            glass.contents = HabitatArt.image(r.size, scale: max(1, s / 2)) { HabitatArt.paintGlass(in: r, $0, dark: dark) }
        }
        // (Painting the big pictures leaves a lot of freed memory about.)
        defer { malloc_zone_pressure_relief(nil, 0) }
        let akey = "\(b.rawValue)-\(Int(bs.width))x\(Int(bs.height))-\(Int(ws.width))x\(Int(ws.height))"
        if akey != atmosphereKey {
            atmosphereKey = akey
            buildAtmosphere()
            weatherFX.build(backdrop: bs, world: ws, view: bounds.size, biome: b, groundImage: ground.contents)
            weatherFX.layoutItems(habitat)
        } else {
            weatherFX.layoutView(bounds.size)
        }
        applyCamera(force: true)
    }

    /// The corners of the tank at either end of the world and along its
    /// lid: a shadow in the glass and a line of light down its edge — so
    /// the end of the tank looks like the end of it, and not the edge of
    /// the window.
    private func layOutTankEnds(_ ws: CGSize) {
        tankEnds.sublayers?.forEach { $0.removeFromSuperlayer() }
        tankEnds.frame = CGRect(origin: .zero, size: ws)
        let shadow = CGColor(gray: 0, alpha: 0.32), clear = CGColor(gray: 0, alpha: 0)
        func strip(_ r: CGRect, from a: CGPoint, to b: CGPoint) {
            let g = CAGradientLayer()
            g.frame = r
            g.colors = [shadow, clear]
            g.startPoint = a
            g.endPoint = b
            tankEnds.addSublayer(g)
        }
        let edge: CGFloat = 30
        strip(CGRect(x: 0, y: 0, width: edge, height: ws.height), from: CGPoint(x: 0, y: 0.5), to: CGPoint(x: 1, y: 0.5))
        strip(CGRect(x: ws.width - edge, y: 0, width: edge, height: ws.height), from: CGPoint(x: 1, y: 0.5), to: CGPoint(x: 0, y: 0.5))
        strip(CGRect(x: 0, y: ws.height - edge * 1.2, width: ws.width, height: edge * 1.2), from: CGPoint(x: 0.5, y: 1), to: CGPoint(x: 0.5, y: 0))
        for r in [CGRect(x: 1.5, y: 0, width: 1, height: ws.height), CGRect(x: ws.width - 2.5, y: 0, width: 1, height: ws.height),
                  CGRect(x: 0, y: ws.height - 2.5, width: ws.width, height: 1)] {
            let line = CALayer()
            line.frame = r
            line.backgroundColor = CGColor(gray: 1, alpha: 0.2)
            tankEnds.addSublayer(line)
        }
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
        let resized = h.size != habitat.size
        habitat = h
        camera.setWorld(h.size)
        if resized { applyCamera(force: true) }
        if let s = selected, !h.items.contains(where: { $0.id == s }) { select(nil) }
        syncItemLayers()
        repaint()
        paintItems()
        rebuildMap()
        refreshSelection()
        overview?.reload()
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
                n.isHidden = true
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
        let r = it.rect
        let pad = HabitatArt.itemPad(r.size)
        let full = r.insetBy(dx: -pad, dy: -pad)
        // It sways about its foot (or, hanging, the top it hangs from).
        let anchor = CGPoint(x: 0.5, y: it.kind.hangs ? (full.height - pad) / full.height : pad / full.height)
        l.anchorPoint = anchor
        l.bounds = CGRect(origin: .zero, size: full.size)
        l.position = CGPoint(x: full.minX + full.width * anchor.x, y: full.minY + full.height * anchor.y)
    }

    /// Paints the furniture near the glass (the rest when it comes near),
    /// and lays out the snow on it and the puddles round it.
    private func paintItems() {
        cull()
        if bounds.width > 100, !inLiveResize { weatherFX.layoutItems(habitat) }
        weatherFX.showCaps(near: visibleWorld.insetBy(dx: -160, dy: -160))
    }

    // MARK: The weather

    /// The weather as it is now: the layers turned up or down (a dozen or
    /// so times a second is plenty — Core Animation eases between), and
    /// the plants in sight leaning with the wind.
    func updateWeather(_ c: WeatherConditions, dt: CGFloat) {
        weatherDue += dt
        guard weatherDue >= 1.0 / 15.0, bounds.width > 100 else { return }
        let step = weatherDue
        weatherDue = 0
        weatherFX.update(c, dt: min(step, 0.5))
        let now = CGFloat(CACurrentMediaTime())
        let gust = c.mix.gust * min(abs(c.windNow), 1.5)
        for l in itemLayers.values where !l.isHidden {
            let k = ItemLayer.windLean(l.item.kind)
            guard k > 0 else { continue }
            let s = CGFloat(abs(l.item.seed % 97))
            let flutter = sin(now * (4.5 + s.truncatingRemainder(dividingBy: 3)) + s) * 0.3 * gust
            l.setLean(editing ? 0 : clamp(c.windNow, -1.8, 1.8) * k * (1 + flutter), over: Double(step) * 1.05)
        }
    }

    /// Thunder: the tank shakes with a clap right overhead. `p` is where
    /// the lightning came down, in the backdrop.
    private func thundered(at p: CGPoint, loud: CGFloat) {
        if loud > 0.75 {
            let o = world.position
            let shake = CAKeyframeAnimation(keyPath: "position")
            shake.values = [(0, 0), (2.5, -1.5), (-2, 1.5), (1.5, -1), (-1, 0.5), (0, 0)].map {
                NSValue(point: CGPoint(x: o.x + $0.0, y: o.y + $0.1))
            }
            shake.duration = 0.4
            world.add(shake, forKey: "thunder")
        }
        // From the backdrop to the glass to the world: the world under it.
        let b = backdrop.position
        onThunder?(worldPoint(fromView: CGPoint(x: p.x + b.x, y: p.y + b.y)), loud)
    }

    /// Footprints in the snow, where its feet come down on the floor.
    private func noteFootprints(_ pose: SpiderPose) {
        guard pose.grounded > 0.9, abs(angleDelta(pose.heading, 0)) < 0.35 else { return }
        let mirror: CGFloat = pose.facing >= 0 ? 1 : -1
        let g = SpiderRenderer.ground
        let floor = HabitatLayout.ground
        for leg in pose.legs where leg.lift < 0.05 {
            let local = V2(leg.foot.x * pose.stretch * mirror, g + (leg.foot.y - g) * pose.fatten)
            let w = pose.pos + local.rotated(by: pose.heading) * pose.scale
            guard abs(w.y - floor) < 3 else { continue }
            weatherFX.footDown(at: CGPoint(x: w.x, y: floor))
        }
    }

    // MARK: The moving air

    private func buildAtmosphere() {
        for old in [airBack, airMid, airFront] { old.removeFromSuperlayer() }
        airBack = CALayer(); airMid = CALayer(); airFront = CALayer()
        backdrop.insertSublayer(airBack, above: sky)
        backdrop.insertSublayer(airMid, above: scenery)
        content.insertSublayer(airFront, above: frontItems)
        airBack.frame = CGRect(origin: .zero, size: backdropSize)
        airMid.frame = CGRect(origin: .zero, size: backdropSize)
        airFront.frame = CGRect(origin: .zero, size: habitat.size)
        atmos = HabitatAtmosphere.build(habitat.biome, backdrop: backdropSize, world: habitat.size, view: bounds.size,
                                        back: airBack, mid: airMid, front: airFront)
        HabitatAtmosphere.follow(atmos, visible: visibleWorld)
    }

    /// Stops everything moving while no part of the tank can be seen.
    func setAnimating(_ on: Bool) {
        // (Tools only: pictures taken of it behind other windows.)
        guard on || !debugKeepAnimating else { return }
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
    /// your hand), its line, and anything loose, for this frame — all in
    /// the world. Whatever is out of sight goes on being simulated, but is
    /// not drawn.
    func showCreatures(_ pose: SpiderPose?, sprite: CGFloat, prey: [Prey]) {
        didRedraw = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let seen = visibleWorld.insetBy(dx: -sprite, dy: -sprite)
        if let pose, seen.contains(pose.pos.point) {
            if spiderLayer.isHidden { spiderLayer.isHidden = false; drawn = nil }
            if spiderLayer.bounds.width != sprite {
                spiderLayer.bounds = CGRect(x: 0, y: 0, width: sprite, height: sprite)
                spiderLayer.contentsScale = scale
                drawn = nil
            }
            spiderLayer.position = pose.pos.point
            spiderLayer.pose = pose
            let now = CACurrentMediaTime()
            let hold: CFTimeInterval = pose.outfit.isAnimated || !pose.specks.isEmpty ? 1.0 / 30.0 : 0.5
            if drawn == nil || now - drawnAt >= hold || drawn!.outfit != pose.outfit || SpiderView.shapeDelta(drawn!, pose) >= 0.04 {
                drawn = pose
                drawnAt = now
                didRedraw = true
                spiderLayer.setNeedsDisplay()
            }
            if weatherFX.wantsFootprints { noteFootprints(pose) }
        } else if !spiderLayer.isHidden {
            spiderLayer.isHidden = true
        }
        let inHere = pose != nil && spider?.map === map
        let footing = inHere ? spider?.standingOn : nil
        holdStill(footing.flatMap { map.owner(of: $0) }, near: inHere ? pose?.pos : nil)
        if showsGeometry { showFooting(footing, at: pose?.pos) }
        // Its line, even with it out of sight (the line may not be).
        if let pose, pose.web != nil, let path = SpiderRenderer.silkPath(pose) {
            silk.path = path
            silk.opacity = Float(pose.web?.alpha ?? 1)
            silk.isHidden = false
        } else if !silk.isHidden {
            silk.isHidden = true
            silk.path = nil
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
            guard seen.insetBy(dx: -side, dy: -side).contains(p.pos.point) else {
                if !l.isHidden { l.isHidden = true }
                continue
            }
            if l.isHidden { l.isHidden = false }
            if l.bounds.width != side { l.bounds = CGRect(x: 0, y: 0, width: side, height: side) }
            l.position = p.pos.point
            l.setNeedsDisplay()
            didRedraw = true
        }
        for (id, l) in preyLayers where !live.contains(id) {
            l.removeFromSuperlayer()
            preyLayers[id] = nil
        }
    }

    /// The colour behind a point in the world, for a camouflaged coat: the
    /// backdrop at that spot.
    func colourBehind(_ p: V2) -> RGB? {
        func image(_ any: Any?) -> CGImage? {
            guard let any, CFGetTypeID(any as CFTypeRef) == CGImage.typeID else { return nil }
            return (any as! CGImage)
        }
        guard let img = image(scenery.contents), let skyImg = image(sky.contents) else { return nil }
        // World to glass to backdrop.
        let v = viewPoint(fromWorld: p)
        let b = backdrop.position
        let local = CGPoint(x: v.x - b.x, y: v.y - b.y)
        let whole = CGRect(origin: .zero, size: backdropSize)
        guard whole.contains(local) else { return nil }
        let r: CGFloat = 30
        let patch = CGRect(x: local.x - r, y: local.y - r, width: r * 2, height: r * 2).intersection(whole)
        // Sky and scenery both: draw the two over each other in a patch.
        guard let merged = HabitatArt.image(patch.size, scale: 0.5, { ctx in
            ctx.translateBy(x: -patch.minX, y: -patch.minY)
            ctx.draw(skyImg, in: whole)
            ctx.draw(img, in: self.scenery.frame)
        }) else { return nil }
        return AppDelegate.dominant(of: merged)
    }

    // MARK: Mouse: the spider, and looking round

    /// Recent pointer positions on the screen (the same whichever side of
    /// the glass the spider is on), for how hard it is thrown.
    private var dragSamples: [(p: V2, t: TimeInterval)] = []
    private var holdingSpider = false
    private var pressedAt = V2.zero
    private var pressTime: TimeInterval = 0
    private var grabbedPrey: Prey?
    /// A press on the bare glass: a tap on it if let go where it was, a
    /// look round the tank if dragged.
    private var glassPress: (from: CGPoint, last: CGPoint)?
    private var panning = false
    private var panSamples: [(p: CGPoint, t: TimeInterval)] = []

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        camera.touched()
        if editing { editMouseDown(event); return }
        guard let spider else { beginGlassPress(event); return }
        let s = screenPoint(event)
        let w = worldPoint(fromScreen: s)
        pressedAt = s
        pressTime = event.timestamp
        dragSamples = [(s, event.timestamp)]
        if spider.inHabitat, spider.map === map, spider.hitTest(w) {
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
            beginGlassPress(event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if editing { editMouseDragged(event); return }
        if glassPress != nil { glassDragged(event); return }
        guard let spider else { return }
        let s = screenPoint(event)
        dragSamples.append((s, event.timestamp))
        if dragSamples.count > 8 { dragSamples.removeFirst(dragSamples.count - 8) }
        // (Carried out through the glass mid-drag, it is on the desktop's
        // screen points from then on.)
        if holdingSpider { spider.moveGrab(to: spiderPoint(fromScreen: s)) }
        if let p = grabbedPrey { spider.movePreyGrab(p, to: worldPoint(fromScreen: s)) }
    }

    /// A force press on a creature in hand squashes it.
    override func pressureChange(with event: NSEvent) {
        guard !editing, event.stage >= 2, let p = grabbedPrey, let spider else { return }
        spider.squashPrey(p)
        grabbedPrey = nil
    }

    override func mouseUp(with event: NSEvent) {
        if editing { editMouseUp(event); return }
        if glassPress != nil { glassReleased(event); return }
        guard let spider else { return }
        let s = screenPoint(event)
        defer { holdingSpider = false; grabbedPrey = nil; dragSamples = [] }
        var v = V2.zero
        if let first = dragSamples.first, dragSamples.count > 1 {
            if event.timestamp - first.t < 0.22 {
                v = (s - first.p) / CGFloat(max(event.timestamp - first.t, 0.008))
            } else if let recent = dragSamples.last(where: { event.timestamp - $0.t > 0.04 }) {
                v = (s - recent.p) / CGFloat(max(event.timestamp - recent.t, 0.008))
            }
        }
        if let p = grabbedPrey { spider.endPreyGrab(p, throwVelocity: v) }
        guard holdingSpider else { return }
        NSCursor.pop()
        if s.distance(to: pressedAt) < 4 && event.timestamp - pressTime < 0.35 {
            spider.endGrab(throwVelocity: .zero)
            spider.poke()
        } else {
            spider.endGrab(throwVelocity: v)
        }
    }

    private func beginGlassPress(_ e: NSEvent) {
        let v = viewPoint(e)
        glassPress = (v, v)
        panning = false
        panSamples = [(v, e.timestamp)]
    }

    /// Dragging the bare glass: the world goes with the pointer.
    private func glassDragged(_ e: NSEvent) {
        guard var g = glassPress else { return }
        let v = viewPoint(e)
        if !panning, hypot(v.x - g.from.x, v.y - g.from.y) > 3 {
            panning = true
            camera.beginPan()
            NSCursor.closedHand.push()
        }
        if panning {
            camera.pan(by: V2(g.last.x - v.x, g.last.y - v.y))
            applyCamera()
        }
        g.last = v
        glassPress = g
        panSamples.append((v, e.timestamp))
        if panSamples.count > 6 { panSamples.removeFirst(panSamples.count - 6) }
    }

    /// Let go: a flick coasts on; a click without a drag taps the glass.
    private func glassReleased(_ e: NSEvent) {
        guard let g = glassPress else { return }
        glassPress = nil
        if panning {
            panning = false
            NSCursor.pop()
            let now = e.timestamp
            if let last = panSamples.last, now - last.t < 0.06, let first = panSamples.first(where: { now - $0.t < 0.12 }), last.t - first.t > 0.008 {
                let dt = CGFloat(last.t - first.t)
                camera.endPan(velocity: V2(-(last.p.x - first.p.x) / dt, -(last.p.y - first.p.y) / dt))
            } else {
                camera.endPan(velocity: .zero)
            }
        } else if !editing {
            tapGlass(at: g.from)
        }
        panSamples = []
    }

    /// Two fingers along (or shift and the wheel): along the tank. Up and
    /// down is an order to the spider, as on the desktop — except while
    /// decorating, when it is all looking round.
    override func scrollWheel(with event: NSEvent) {
        let k: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let dx = event.scrollingDeltaX * k, dy = event.scrollingDeltaY * k
        if editing || overviewOpen {
            guard !overviewOpen else { return }
            camera.pan(by: V2(-dx, dy))
            applyCamera()
            return
        }
        if abs(dx) > abs(dy) * 1.5, abs(dx) > 0.3 {
            camera.pan(by: V2(-dx, 0))
            applyCamera()
            return
        }
        guard let spider, spider.inHabitat else { return }
        spider.scroll(event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas, startsGesture: event.startsScrollGesture)
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
        tapLayer.addSublayer(ring)
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

    private var isDraggingItem: Bool {
        if case .none = drag { return false }
        return true
    }

    /// The thing at a point in the world, front first.
    func itemAt(_ p: V2) -> HabitatItem? {
        let q = p.point
        let ordered = habitat.items.enumerated().sorted { a, b in
            if a.element.inFront != b.element.inFront { return a.element.inFront }
            return a.offset > b.offset
        }
        // What is really there first — its solid parts, or its foliage —
        // then the box round it.
        for (_, it) in ordered where it.rect.insetBy(dx: -8, dy: -8).contains(q) && it.geometry.contains(p, slack: 6) { return it }
        for (_, it) in ordered where it.rect.insetBy(dx: -4, dy: -4).contains(q) { return it }
        return nil
    }

    private func handleRects(_ it: HabitatItem) -> [CGRect] {
        let r = it.rect.insetBy(dx: -5, dy: -5)
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
            hoverOutline.path = CGPath(roundedRect: it.rect.insetBy(dx: -4, dy: -4), cornerWidth: 6, cornerHeight: 6, transform: nil)
            hoverOutline.isHidden = false
        } else {
            hoverOutline.isHidden = true
        }
    }

    /// Where a thing is drawn right now, from its layer.
    private func liveRect(_ it: HabitatItem, layer l: ItemLayer) -> CGRect {
        let pad = HabitatArt.itemPad(it.rect.size)
        let f = l.frame
        return f.insetBy(dx: pad * f.width / max(l.bounds.width, 1), dy: pad * f.height / max(l.bounds.height, 1))
    }

    override func mouseMoved(with event: NSEvent) {
        camera.touched()
        guard editing else { return }
        let p = viewPoint(event)
        let id = itemAt(worldPoint(fromView: p))?.id
        if id != hovered { hovered = id; refreshSelection() }
        updateCursor(at: p)
    }

    override func mouseExited(with event: NSEvent) {
        if hovered != nil { hovered = nil; refreshSelection() }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: viewPoint(event))
    }

    private func updateCursor(at v: CGPoint) {
        guard editing else { NSCursor.arrow.set(); return }
        let p = worldPoint(fromView: v)
        if let id = selected, let it = habitat.items.first(where: { $0.id == id }), handleRects(it).contains(where: { $0.contains(p.point) }) {
            NSCursor.crosshair.set()
        } else if itemAt(p) != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func editMouseDown(_ event: NSEvent) {
        let v = viewPoint(event)
        let p = worldPoint(fromView: v).point
        before = habitat
        if let id = selected, let it = habitat.items.first(where: { $0.id == id }), handleRects(it).contains(where: { $0.contains(p) }) {
            let r = it.rect
            let anchor = CGPoint(x: r.midX, y: it.kind.hangs ? r.maxY : r.minY)
            drag = .resize(id: id, from: it, anchor: anchor, startDist: max(hypot(p.x - anchor.x, p.y - anchor.y), 8))
            dragView = v
            return
        }
        if let it = itemAt(V2(p)) {
            select(it.id)
            // Where on it it was taken hold of, so it does not jump to the pointer.
            drag = .move(id: it.id, offset: CGPoint(x: it.x - p.x, y: it.y - (p.y - HabitatLayout.ground)))
            dragView = v
            NSCursor.closedHand.set()
        } else {
            select(nil)
            drag = .none
            before = nil
            // The bare glass: dragged, it looks round the tank.
            beginGlassPress(event)
        }
    }

    private func editMouseDragged(_ event: NSEvent) {
        if glassPress != nil { glassDragged(event); return }
        let v = viewPoint(event)
        dragView = v
        dragItem(at: v)
    }

    /// The thing being dragged, to where the pointer is over the world
    /// (which moves under it as the camera is taken along).
    private func dragItem(at v: CGPoint) {
        let p = worldPoint(fromView: v).point
        switch drag {
        case .none:
            return
        case .move(let id, let offset):
            guard let i = habitat.items.firstIndex(where: { $0.id == id }) else { return }
            var it = habitat.items[i]
            it.x = p.x + offset.x
            if it.kind.hangs {
                it.y = habitat.size.height
            } else if it.kind.liftable {
                let y = p.y - HabitatLayout.ground + offset.y
                // Near the ground it sits on it.
                it.y = y < 12 ? 0 : y
            } else {
                it.y = 0
            }
            Habitat.clamp(&it, in: habitat.size)
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
            Habitat.clamp(&it, in: habitat.size)
            habitat.items[i] = it
            moveLayer(it)
        }
    }

    private func editMouseUp(_ event: NSEvent) {
        if glassPress != nil { glassReleased(event); return }
        defer { drag = .none; before = nil; dragView = nil }
        switch drag {
        case .none:
            return
        case .move(let id, _):
            settle(id)
            commit()
            updateCursor(at: viewPoint(event))
        case .resize:
            commit()
            updateCursor(at: viewPoint(event))
        }
    }

    /// Let go of up in the air, a thing comes to rest on whatever it is
    /// over — the top of a log or a stone, or the ground. (A branch stays
    /// where it is put: it is wedged there.)
    private func settle(_ id: Int) {
        guard let i = habitat.items.firstIndex(where: { $0.id == id }) else { return }
        var it = habitat.items[i]
        guard !it.kind.hangs, it.kind.definition.placement != .wedged, it.y > 0 else { return }
        let lo = it.x - it.w * 0.25, hi = it.x + it.w * 0.25
        var rest: CGFloat = 0
        for o in habitat.items where o.id != id && !o.kind.hangs && o.rect.maxX > lo && o.rect.minX < hi {
            guard let top = Habitat.restingTop(o, from: lo, to: hi).map({ $0 - HabitatLayout.ground }) else { continue }
            if top <= it.y + 8 { rest = max(rest, top) }
        }
        guard abs(rest - it.y) > 0.5 else { return }
        let fromY = itemLayers[id]?.position.y
        it.y = rest
        Habitat.clamp(&it, in: habitat.size)
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
        if l.isHidden { l.paint(biome: habitat.biome, scale: scale, size: it.rect.size); l.isHidden = false }
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
        overview?.reload()
        onEdit?(before, habitat)
    }

    // MARK: Editing from outside

    /// Changes the chosen thing, as one edit — or `silently`, as part of
    /// one the caller will record when it is done.
    func updateSelected(silently: Bool = false, _ f: (inout HabitatItem) -> Void) {
        guard let id = selected else { return }
        update(id, silently: silently, f)
    }

    /// Changes a thing, as one edit (or silently).
    func update(_ id: Int, silently: Bool = false, _ f: (inout HabitatItem) -> Void) {
        guard let i = habitat.items.firstIndex(where: { $0.id == id }) else { return }
        let was = habitat
        var it = habitat.items[i]
        f(&it)
        Habitat.clamp(&it, in: habitat.size)
        habitat.items[i] = it
        guard was != habitat else { return }
        syncItemLayers()
        paintItems()
        rebuildMap()
        refreshSelection()
        overview?.reload()
        if silently { habitat.save() } else { onEdit?(was, habitat) }
    }

    /// Moved in the overview: a thing to a new spot in the world, where it
    /// comes to rest on whatever is under it, as one edit.
    func moveItem(_ id: Int, to p: V2) {
        guard let i = habitat.items.firstIndex(where: { $0.id == id }) else { return }
        before = habitat
        var it = habitat.items[i]
        it.x = p.x
        if it.kind.hangs {
            it.y = habitat.size.height
        } else {
            it.y = it.kind.liftable ? max(0, p.y - HabitatLayout.ground) : 0
        }
        Habitat.clamp(&it, in: habitat.size)
        habitat.items[i] = it
        moveLayer(it)
        settle(id)
        commit()
        before = nil
    }

    /// Replaces the whole habitat as one edit (a layout, the scenery,
    /// clearing it out).
    func replace(with h: Habitat, fade: Bool) {
        let was = habitat
        setHabitat(h, fade: fade)
        if was != h { onEdit?(was, h) }
    }

    /// Puts a new thing in, somewhere with room for it in what the glass
    /// shows, dropping it in from a little above. Something that has to
    /// stand on the ground, or hang from the lid, where the glass doesn't
    /// show it, the camera goes to.
    func add(_ kind: HabitatItemKind) {
        var h = habitat
        let size = kind.defaultSize
        let view = visibleWorld
        let W = h.size.width
        // The most open stretch of what shows: furthest from everything else.
        let lo = max(view.minX + size.width / 2 + 20, size.width / 2 + 20)
        let hi = max(lo, min(view.maxX - size.width / 2 - 20, W - size.width / 2 - 20))
        var bestX: CGFloat = view.midX
        var best: CGFloat = -1
        for step in 0..<40 {
            let x = lo + CGFloat(step) / 39 * (hi - lo)
            let gap = h.items.filter { $0.kind.hangs == kind.hangs }.map { max(0, abs($0.x - x) - ($0.w + size.width) / 2) }.min() ?? 900
            let score = min(gap, 300) + CGFloat.random(in: 0...20) - abs(x - view.midX) * 0.05
            if score > best { best = score; bestX = x }
        }
        // A branch goes where the glass is looking, even up in the air;
        // anything else stands on the ground (or hangs from the lid).
        var y: CGFloat = 0
        if kind.hangs {
            y = h.size.height
        } else if kind == .branch, view.minY > HabitatLayout.ground + 40 {
            y = max(0, view.midY - HabitatLayout.ground - size.height / 2)
        }
        let it = h.add(kind, at: CGPoint(x: bestX, y: y))
        let was = habitat
        setHabitat(h)
        onEdit?(was, h)
        select(it.id)
        if let placed = habitat.items.first(where: { $0.id == it.id }), !view.insetBy(dx: -20, dy: -20).contains(CGPoint(x: placed.x, y: placed.rect.midY)) {
            camera.glide(toCentre: V2(placed.x, placed.kind.hangs ? placed.rect.maxY - view.height * 0.35 : placed.rect.minY + view.height * 0.3), thenFollow: false)
        }
        // In it drops, with a little bounce.
        if let l = itemLayers[it.id] {
            l.paint(biome: habitat.biome, scale: scale, size: l.item.rect.size)
            l.isHidden = false
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
        copy.uid = HabitatItem.newUID()
        h.nextID += 1
        copy.x = it.x + (it.x > h.size.width - 120 ? -1 : 1) * max(40, it.w * 0.6)
        copy.seed = Int.random(in: 1...9999)
        Habitat.clamp(&copy, in: h.size)
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
        // (Developer only, and on no menu: the physical shape of things.)
        if event.modifierFlags.intersection([.command, .control, .option]) == [.command, .control, .option], chars == "g" {
            showsGeometry.toggle()
            return
        }
        if cmd, chars == "z" { onCommand?(event.modifierFlags.contains(.shift) ? .redo : .undo); return }
        if event.keyCode == 53, overviewOpen { showOverview(false); return }
        // With nothing picked, the arrows look round the tank.
        if (!editing || selected == nil), [123, 124, 125, 126].contains(event.keyCode), !cmd {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 0.8 : 0.35
            let d: V2 = [123: V2(-1, 0), 124: V2(1, 0), 125: V2(0, -1), 126: V2(0, 1)][event.keyCode]!
            let c = V2(visibleWorld.midX, visibleWorld.midY) + V2(d.x * bounds.width, d.y * bounds.height) * step
            camera.glide(toCentre: c, thenFollow: false)
            return
        }
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
                if !it.kind.hangs, it.kind.liftable { it.y = max(0, it.y + d.y) }
            }
        default:
            if chars == "f", selected != nil { updateSelected { $0.flipped.toggle() }; return }
            super.keyDown(with: event)
        }
    }

    // MARK: Holding still what it is on

    /// Swaying things held still: what it is on, and any it is close to.
    private var heldStill = Set<Int>()

    /// Something swaying that it can climb — a vine, a leafy plant, bamboo
    /// — goes still while the spider is on it or right by it (its surfaces
    /// are where it stands at rest, and in a gale a long vine's picture can
    /// lean a good way off them), so it has settled upright by the time the
    /// spider steps or jumps onto it; it sways again once it has gone.
    private func holdStill(_ on: Int?, near p: V2?) {
        var want = Set<Int>()
        if let on, itemLayers[on]?.item.kind.sways == true { want.insert(on) }
        if let p {
            for (id, l) in itemLayers where l.item.kind.sways && l.item.kind.climbable
                && l.item.rect.insetBy(dx: -60, dy: -60).contains(p.point) { want.insert(id) }
        }
        guard want != heldStill else { return }
        for id in heldStill.subtracting(want) { itemLayers[id]?.setHeld(false) }
        for id in want.subtracting(heldStill) { itemLayers[id]?.setHeld(true) }
        heldStill = want
    }

    // MARK: Debug: shapes
    //
    // Developer only — ⌃⌥⌘G in the tank, or SPIDER_HABITAT_GEOMETRY=1 — and
    // on no menu: everything the spider's footing is worked out from, drawn
    // over the tank.
    //
    //   thin orange / green   each thing's solid parts: bulk / limbs
    //   red haze              parts only to look at (foliage, flowers)
    //   grey dashes           each thing's box, and its number and kind
    //   yellow                the edges its feet go on
    //   blue / cyan           the line its body follows: round the tank and
    //                         what is run into it / round a thing of its own
    //   magenta dots          junctions: where it can step from one onto
    //                         another
    //   green squares         perches; white rings: places to tie silk;
    //                         orange: a way in, and the hollow inside
    //   white                 the surface it is on now, and where on it
    //
    // With the corner readout: which surface, which thing, which way.

    var showsGeometry = false {
        didSet {
            guard showsGeometry != oldValue else { return }
            refreshGeometryOverlay()
        }
    }

    private func shapeLayer(_ path: CGPath, stroke: CGColor?, width: CGFloat = 1, fill: CGColor? = nil, dash: [NSNumber]? = nil) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.path = path
        l.strokeColor = stroke
        l.fillColor = fill
        l.lineWidth = width
        l.lineDashPattern = dash
        l.lineJoin = .round
        return l
    }

    private func refreshGeometryOverlay() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        geometryLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        geometryLayer.isHidden = !showsGeometry
        geometryHUD.isHidden = !showsGeometry
        footingLoop = nil
        guard showsGeometry else { return }
        geometryLayer.frame = CGRect(origin: .zero, size: habitat.size)
        func poly(_ into: CGMutablePath, _ pts: [V2], closed: Bool = true) {
            guard let f = pts.first else { return }
            into.move(to: f.point)
            for p in pts.dropFirst() { into.addLine(to: p.point) }
            if closed { into.closeSubpath() }
        }
        let boxes = CGMutablePath(), bulk = CGMutablePath(), limbs = CGMutablePath(), visual = CGMutablePath()
        let hollows = CGMutablePath(), perches = CGMutablePath(), ties = CGMutablePath(), ways = CGMutablePath()
        for it in habitat.items {
            boxes.addRect(it.rect)
            let g = it.geometry
            for part in g.parts { poly(part.role == .bulk ? bulk : limbs, part.outline) }
            for v in g.visual { poly(visual, v) }
            for h in g.hollows { poly(hollows, h.cavity) }
            for a in g.anchors {
                let p = a.point
                switch a.kind {
                case .perch: perches.addRect(CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
                case .tie: ties.addEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
                case .entrance:
                    ways.move(to: CGPoint(x: p.x + a.normal.x * 9, y: p.y + 5))
                    ways.addLine(to: CGPoint(x: p.x + a.normal.x * 9, y: p.y - 5))
                    ways.addLine(to: p.point)
                    ways.closeSubpath()
                }
            }
            let label = CATextLayer()
            label.string = "#\(it.id) \(it.kind.label)"
            label.fontSize = 10
            label.foregroundColor = CGColor(gray: 1, alpha: 0.85)
            label.backgroundColor = CGColor(gray: 0, alpha: 0.45)
            label.contentsScale = scale
            label.frame = CGRect(x: it.rect.minX, y: it.rect.maxY + 1, width: 120, height: 13)
            geometryLayer.addSublayer(label)
        }
        let rim = CGMutablePath(), own = CGMutablePath(), edges = CGMutablePath(), dots = CGMutablePath()
        for loop in map.loops {
            let body = loop.kind == .screenBorder ? rim : own
            for seg in loop.segs { body.move(to: seg.a.point); body.addLine(to: seg.b.point) }
            for e in loop.edge { edges.move(to: e.a.point); edges.addLine(to: e.b.point) }
        }
        for j in map.junctions { dots.addEllipse(in: CGRect(x: j.at.x - 3, y: j.at.y - 3, width: 6, height: 6)) }
        let c = { (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) in CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
        for l in [shapeLayer(boxes, stroke: c(1, 1, 1, 0.3), dash: [3, 4]),
                  shapeLayer(visual, stroke: c(1, 0.3, 0.3, 0.45), fill: c(1, 0.2, 0.2, 0.14)),
                  shapeLayer(hollows, stroke: c(1, 0.6, 0.1, 0.9), width: 1.2, dash: [4, 3]),
                  shapeLayer(bulk, stroke: c(1, 0.62, 0.25, 0.9)),
                  shapeLayer(limbs, stroke: c(0.5, 1, 0.4, 0.9)),
                  shapeLayer(edges, stroke: c(1, 0.92, 0.2, 0.95), width: 1.3),
                  shapeLayer(rim, stroke: c(0.35, 0.6, 1, 0.9), width: 1.5),
                  shapeLayer(own, stroke: c(0.3, 0.95, 1, 0.9), width: 1.5),
                  shapeLayer(dots, stroke: nil, fill: c(1, 0.2, 0.9, 1)),
                  shapeLayer(perches, stroke: nil, fill: c(0.4, 1, 0.3, 1)),
                  shapeLayer(ties, stroke: c(1, 1, 1, 1), width: 1.5),
                  shapeLayer(ways, stroke: nil, fill: c(1, 0.6, 0.1, 1)),
                  geometryFooting] {
            geometryLayer.addSublayer(l)
        }
        geometryFooting.strokeColor = c(1, 1, 1, 1)
        geometryFooting.fillColor = nil
        geometryFooting.lineWidth = 3
        geometryFooting.lineJoin = .round
        geometryHUD.fontSize = 11
        geometryHUD.foregroundColor = CGColor(gray: 1, alpha: 1)
        geometryHUD.backgroundColor = CGColor(gray: 0, alpha: 0.6)
        geometryHUD.contentsScale = scale
        geometryHUD.anchorPoint = .zero
        geometryHUD.frame = CGRect(x: 10, y: 10, width: 560, height: 30)
        geometryHUD.string = "shapes: \(map.loops.count) surfaces, \(map.junctions.count / 2) junctions"
    }

    /// The loop last drawn as the one it is on.
    private var footingLoop: String?

    /// Where it is standing, for the overlay: the whole surface it is on,
    /// and a readout of what that is.
    private func showFooting(_ a: Anchor?, at p: V2?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let a, let loop = map.loop(a.loopID) else {
            if footingLoop != nil { footingLoop = nil; geometryFooting.path = nil }
            geometryHUD.string = spider?.map === map ? "in the air · \(spider?.debugState ?? "")" : "not in the tank"
            return
        }
        if footingLoop != a.loopID {
            footingLoop = a.loopID
            let path = CGMutablePath()
            for seg in loop.segs { path.move(to: seg.a.point); path.addLine(to: seg.b.point) }
            geometryFooting.path = path
        }
        let owner = map.owner(of: a).flatMap { habitat.item(id: $0) }
        let what = owner.map { "#\($0.id) \($0.kind.label) (\($0.uid.prefix(8)))" } ?? "the tank"
        let seg = a.segIdx < loop.segs.count ? loop.segs[a.segIdx] : nil
        let vertex = a.dir > 0 ? a.segIdx + 1 : a.segIdx
        let ahead = map.junctions(from: a.loopID, at: vertex).count
        geometryHUD.string = String(format: "%@ seg %d/%d t %.0f %@ · %@ · facing %@ · %d junction%@ ahead",
                                    a.loopID, a.segIdx, loop.segs.count, a.t, a.dir > 0 ? "→" : "←", what,
                                    seg.map { "\($0.facing)" } ?? "?", ahead, ahead == 1 ? "" : "s")
        _ = p
    }

    /// Tools only: the layers, for checking what is shown.
    var debugItemLayers: [Int: CALayer] { itemLayers }
    var debugSpiderShown: Bool { !spiderLayer.isHidden }
    var debugBackdropOrigin: CGPoint { backdrop.position }
    var debugFindShown: Bool { findShown }
}

// MARK: - A thing in the tank

/// One piece of furniture: its picture, and whatever moves on it — a sway,
/// a glow, ripples.
final class ItemLayer: CALayer {
    var item = HabitatItem(id: 0, kind: .rock, x: 0, y: 0, w: 1, h: 1)
    var paintedKey = ""
    private var extras: [CALayer] = []
    private var animatedKey = ""
    /// How far it leans with the wind, as a shear (+: its top to the
    /// right); its own sway goes on on top of that.
    private var lean: CGFloat = 0

    /// How far each kind of thing leans in a gale.
    static func windLean(_ kind: HabitatItemKind) -> CGFloat { kind.definition.windLean }

    private static func shear(_ k: CGFloat) -> CATransform3D {
        var t = CATransform3DIdentity
        t.m21 = k
        return t
    }

    /// Held still (the spider is on it): no sway, no lean.
    private(set) var held = false

    /// Stills it — its sway and lean eased out — or lets it go again.
    func setHeld(_ on: Bool) {
        guard on != held, item.kind.sways else { return }
        held = on
        let now = presentation()?.transform ?? transform
        if on {
            // From however it is leaning this moment, back upright.
            removeAnimation(forKey: "sway")
            removeAnimation(forKey: "lean")
            lean = 0
            transform = CATransform3DIdentity
            let ease = CABasicAnimation(keyPath: "transform")
            ease.fromValue = NSValue(caTransform3D: now)
            ease.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            ease.duration = 0.45
            ease.timingFunction = CAMediaTimingFunction(name: .easeOut)
            add(ease, forKey: "still")
        } else {
            startSway(fromRest: true)
        }
    }

    /// Leans it over to `k`, easing there over `d` seconds.
    func setLean(_ k: CGFloat, over d: CFTimeInterval) {
        let k = held ? 0 : k
        guard abs(k - lean) > 0.0004 else { return }
        let from = lean
        lean = k
        let sign: CGFloat = item.kind.hangs ? -1 : 1
        transform = ItemLayer.shear(sign * k)
        // (Added to the sway, which is added to this.)
        let ease = CABasicAnimation(keyPath: "transform")
        ease.fromValue = NSValue(caTransform3D: ItemLayer.shear(sign * (from - k)))
        ease.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        ease.duration = d
        ease.isAdditive = true
        add(ease, forKey: "lean")
    }

    override init() {
        super.init()
        contentsGravity = .resize
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    override func action(forKey event: String) -> CAAction? { nil }

    /// Lets its picture go (it is far from the glass): painted again when
    /// it comes near.
    func unpaint() {
        guard !paintedKey.isEmpty else { return }
        paintedKey = ""
        contents = nil
    }

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

    /// A gentle lean to and fro, about its foot: bent, not turned, so the
    /// foot stays put. `fromRest`: starting from upright (let go of), eased
    /// in rather than jumping to wherever in its sway it would be.
    private func startSway(fromRest: Bool) {
        let s = CGFloat(abs(item.seed % 997)) / 997
        let amount = item.kind.definition.sway
        let sway = CAKeyframeAnimation(keyPath: "transform")
        func shear(_ k: CGFloat) -> CATransform3D {
            var t = CATransform3DIdentity
            t.m21 = item.kind.hangs ? -k : k
            return t
        }
        sway.values = [shear(-amount), shear(amount * 0.6), shear(-amount * 0.4), shear(amount), shear(-amount)].map { NSValue(caTransform3D: $0) }
        sway.keyTimes = [0, 0.3, 0.5, 0.75, 1]
        sway.duration = CFTimeInterval(4.5 + s * 3)
        sway.repeatCount = .infinity
        sway.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        // (On top of any lean the wind gives it.)
        sway.isAdditive = true
        if fromRest {
            // From the start of its sway, less that much, eased away.
            sway.beginTime = convertTime(CACurrentMediaTime(), from: nil)
            let ease = CABasicAnimation(keyPath: "transform")
            ease.fromValue = NSValue(caTransform3D: shear(amount))
            ease.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            ease.duration = 1.4
            ease.isAdditive = true
            ease.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            add(ease, forKey: "unstill")
        } else {
            sway.timeOffset = CFTimeInterval(s) * sway.duration
        }
        add(sway, forKey: "sway")
    }

    private func animate(biome: Biome, pad: CGFloat) {
        removeAllAnimations()
        for e in extras { e.removeFromSuperlayer() }
        extras = []
        let s = CGFloat(abs(item.seed % 997)) / 997
        if item.kind.sways, !held { startSway(fromRest: false) }
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
        if p.castsShadow {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.14 * p.alpha))
            ctx.fillEllipse(in: CGRect(x: -9 * p.drawScale, y: -p.kind.clearance * p.drawScale - 2, width: 18 * p.drawScale, height: 3.5 * p.drawScale))
        }
        PreyRenderer.draw(p, in: ctx)
    }
}
