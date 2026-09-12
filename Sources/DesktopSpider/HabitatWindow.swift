import AppKit

// MARK: - The scene

/// The tank: scenery, furniture, and the spider living in it. Draws every
/// frame it is on screen. In build mode the furniture can be picked up,
/// moved, resized, flipped and removed.
final class HabitatView: NSView {
    let map = SurfaceMap()
    var spider: Spider?
    var habitat = Habitat() { didSet { if habitat != oldValue { rebuildMap(); needsDisplay = true } } }
    var onChange: ((Habitat) -> Void)?

    /// Build mode: the furniture takes the mouse instead of the spider.
    var building = false { didSet { selected = nil; needsDisplay = true } }
    var selected: Int? { didSet { needsDisplay = true; onSelect?(selected) } }
    var onSelect: ((Int?) -> Void)?

    private var time: CGFloat = 0
    /// Tools only: how long the tank's clock has run.
    var clockTime: CGFloat { time }
    private var dragging = false
    private var samples: [(V2, TimeInterval)] = []
    private var dragItem: Int?
    private var dragOffset = CGPoint.zero
    private var resizing = false
    private var resizeFrom = CGRect.zero
    private var resizeStart = CGPoint.zero
    private var pressedAt = CGPoint.zero
    private var pressTime: TimeInterval = 0

    /// Scale of the design coordinates (a 900×540 scene) onto this view.
    private(set) var sceneRect = CGRect.zero
    /// The backdrop is expensive and still: painted once per biome and size
    /// and reused; only the things in the air are drawn live.
    private var backdrop: CGImage?
    private var backdropKey = ""
    /// Furniture behind and in front of the spider, likewise cached until it changes.
    private var backImage: CGImage?
    private var furnitureKey = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        let old = sceneRect
        sceneRect = bounds.insetBy(dx: 14, dy: 14)
        if old != sceneRect {
            // Everything stretches with the window: the spider along with it —
            // when it is actually in here.
            if let spider, spider.inHabitat, spider.map === map, old.width > 50 {
                let was = map.worldBounds
                let u = (spider.worldPos.x - was.minX) / max(was.width, 1), v = (spider.worldPos.y - was.minY) / max(was.height, 1)
                rebuildMap()
                let now = screenScene
                spider.teleportQuietly(to: V2(now.minX + u * now.width, now.minY + v * now.height))
                spider.mapChanged()
            } else {
                rebuildMap()
            }
        }
    }

    /// The scene as it sits on the screen. The spider lives in screen
    /// coordinates whichever side of the glass it is on: it is the one
    /// desktop spider, drawn by the desktop overlay, moved into the tank's
    /// part of the screen.
    var screenScene: CGRect {
        guard let w = window else { return sceneRect }
        return w.convertToScreen(convert(sceneRect, to: nil))
    }
    private var screenOffset: CGPoint {
        let s = screenScene
        return CGPoint(x: s.minX - sceneRect.minX, y: s.minY - sceneRect.minY)
    }

    /// Item coordinates are stored for a 900×540 scene and stretched to
    /// whatever size the window is.
    private var sx: CGFloat { sceneRect.width / 900 }
    private var sy: CGFloat { sceneRect.height / 540 }
    func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: sceneRect.minX + p.x * sx, y: sceneRect.minY + p.y * sy) }
    func toScene(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - sceneRect.minX) / sx, y: (p.y - sceneRect.minY) / sy) }
    private func viewRect(_ it: HabitatItem) -> CGRect {
        let r = it.rect
        return CGRect(x: sceneRect.minX + r.minX * sx, y: sceneRect.minY + r.minY * sy, width: r.width * sx, height: r.height * sy)
    }
    private func viewItem(_ it: HabitatItem) -> HabitatItem {
        var v = it
        let r = viewRect(it)
        v.x = r.midX; v.y = it.kind.hangs ? r.maxY : r.minY; v.w = r.width; v.h = r.height
        return v
    }

    func rebuildMap() {
        guard sceneRect.width > 50 else { return }
        let off = screenOffset
        var loops: [SurfaceLoop] = []
        let placed = Habitat(biome: habitat.biome, items: habitat.items.map { it in
            var v = viewItem(it)
            v.x += off.x; v.y += off.y
            return v
        }, nextID: habitat.nextID)
        loops = placed.loops(standoff: map.standoff)
        map.rebuild(scene: screenScene, loops: loops)
        if let spider, spider.inHabitat, spider.map === map { spider.mapChanged() }
    }

    /// The window moved: the scene, and the spider in it, go with it.
    func windowMoved(by d: CGPoint) {
        if let spider, spider.inHabitat, spider.map === map {
            spider.teleportQuietly(to: spider.worldPos + V2(d))
        }
        rebuildMap()
    }

    override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .spiderContextMenu, object: event)
    }

    // MARK: Ticking

    /// The tank keeps its own clock: the desktop's display link is tied to
    /// the desktop overlay, which is put away while the spider is in here,
    /// and a display link on a hidden window does not fire.
    var onFrame: ((CGFloat) -> Void)?
    private var clock: Any?
    private var lastFrame: CFTimeInterval = 0

    func startClock() {
        guard clock == nil else { return }
        lastFrame = CACurrentMediaTime()
        if #available(macOS 14.0, *), let screen = window?.screen ?? NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(clockFrame))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            clock = link
        } else {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.clockFrame() }
            RunLoop.main.add(t, forMode: .common)
            clock = t
        }
    }

    func stopClock() {
        if #available(macOS 14.0, *), let link = clock as? CADisplayLink { link.invalidate() }
        if let t = clock as? Timer { t.invalidate() }
        clock = nil
    }

    @objc private func clockFrame() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastFrame, 1.0 / 240.0), 1.0 / 20.0))
        lastFrame = now
        onFrame?(dt)
        time += dt
        needsDisplay = true
    }

    /// Tools only: a frame without the clock.
    func tick(dt: CGFloat) {
        time += dt
        needsDisplay = true
    }

    // MARK: Drawing

    /// Renders a layer of the scene into an image the size of the view.
    private func layerImage(_ paint: (CGContext) -> Void) -> CGImage? {
        let scale = window?.backingScaleFactor ?? 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        paint(ctx)
        return ctx.makeImage()
    }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // The room behind the tank.
        ctx.setFillColor(CGColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1))
        ctx.fill(bounds)
        guard sceneRect.width > 50 else { return }
        ctx.saveGState()
        ctx.clip(to: sceneRect)
        // The still backdrop, from cache.
        let bkey = "\(habitat.biome.rawValue)-\(Int(bounds.width))x\(Int(bounds.height))"
        if backdropKey != bkey || backdrop == nil {
            backdropKey = bkey
            backdrop = layerImage { c in HabitatPainter.drawBackground(self.habitat.biome, in: self.sceneRect, ctx: c, time: 0, still: true) }
        }
        if let bg = backdrop { ctx.draw(bg, in: bounds) }
        HabitatPainter.drawAir(habitat.biome, in: sceneRect, ctx: ctx, time: time)
        // The furniture: the plants sway, so those are drawn live; the rest
        // comes from cache.
        let fkey = "\(bkey)-\(habitat.items.map { "\($0.id):\(Int($0.x)):\(Int($0.y)):\(Int($0.w)):\(Int($0.h)):\($0.flipped):\($0.front):\($0.seed)" }.joined())-\(building)-\(selected ?? -1)"
        if furnitureKey != fkey || backImage == nil {
            furnitureKey = fkey
            backImage = layerImage { c in
                for it in self.habitat.items where !it.kind.animated {
                    HabitatPainter.draw(self.viewItem(it), biome: self.habitat.biome, time: 0, selected: self.building && self.selected == it.id, ctx: c)
                }
            }
        }
        if let bi = backImage { ctx.draw(bi, in: bounds) }
        for it in habitat.items where it.kind.animated {
            HabitatPainter.draw(viewItem(it), biome: habitat.biome, time: time, selected: building && selected == it.id, ctx: ctx)
        }
        // The spider, its silk and any creatures are drawn by the desktop
        // overlays, above this window, as everywhere else.
        ctx.restoreGState()
        HabitatPainter.drawGlass(in: sceneRect, ctx: ctx)
        if building {
            // A hint along the bottom.
            let hint = "Build mode — click to select, drag to move, drag the corner to resize, ⌫ to remove" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 1, alpha: 0.85)]
            let size = hint.size(withAttributes: attrs)
            let pill = CGRect(x: sceneRect.midX - size.width / 2 - 10, y: sceneRect.minY + 6, width: size.width + 20, height: size.height + 8)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
            ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
            hint.draw(at: CGPoint(x: pill.minX + 10, y: pill.minY + 4), withAttributes: attrs)
        }
    }

    // MARK: Mouse

    private func local(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    private func itemAt(_ p: CGPoint) -> HabitatItem? {
        // Frontmost first: later items, and front items over back ones.
        let ordered = habitat.items.enumerated().sorted { a, b in
            if a.element.front != b.element.front { return a.element.front && !b.element.front }
            return a.offset > b.offset
        }
        for (_, it) in ordered where viewRect(it).insetBy(dx: -4, dy: -4).contains(p) { return it }
        return nil
    }

    private func resizeHandle(_ it: HabitatItem) -> CGRect {
        let r = viewRect(it)
        return CGRect(x: r.maxX - 6, y: r.maxY - 6, width: 16, height: 16)
    }


    override func mouseDown(with event: NSEvent) {
        let p = local(event)
        window?.makeFirstResponder(self)
        pressedAt = p
        pressTime = event.timestamp
        if building {
            if let id = selected, let it = habitat.items.first(where: { $0.id == id }), resizeHandle(it).contains(p) {
                resizing = true
                resizeFrom = it.rect
                resizeStart = toScene(p)
                dragItem = id
                return
            }
            if let it = itemAt(p) {
                selected = it.id
                dragItem = it.id
                let sp = toScene(p)
                dragOffset = CGPoint(x: it.x - sp.x, y: it.y - sp.y)
            } else {
                selected = nil
                dragItem = nil
            }
            return
        }
        // Not building: the spider and its creatures take their own clicks
        // through the desktop overlays; a click on the scenery is nothing.
    }

    override func mouseDragged(with event: NSEvent) {
        let p = local(event)
        if building {
            guard let id = dragItem, let idx = habitat.items.firstIndex(where: { $0.id == id }) else { return }
            var it = habitat.items[idx]
            let sp = toScene(p)
            if resizing {
                let dx = sp.x - resizeStart.x, dy = sp.y - resizeStart.y
                let k = max(0.35, min(3.5, max((resizeFrom.width + dx) / resizeFrom.width, (resizeFrom.height + dy) / resizeFrom.height)))
                it.w = resizeFrom.width * k
                it.h = resizeFrom.height * k
            } else {
                it.x = max(10, min(890, sp.x + dragOffset.x))
                var y = sp.y + dragOffset.y
                // Things stand on the floor unless lifted well clear; hanging
                // things stay on the ceiling unless pulled well down.
                if it.kind.hangs { y = y > 500 ? 540 : y } else { y = y < 30 ? 0 : y }
                it.y = max(0, min(540, y))
            }
            habitat.items[idx] = it
            needsDisplay = true
            return
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = local(event)
        if building {
            if dragItem != nil { onChange?(habitat) }
            dragItem = nil
            resizing = false
            return
        }
        _ = p
    }

    override func keyDown(with event: NSEvent) {
        guard building, let id = selected else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 51, 117:   // delete, forward delete
            habitat.items.removeAll { $0.id == id }
            selected = nil
            onChange?(habitat)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Editing

    func add(_ kind: HabitatItemKind) {
        var h = habitat
        let x = CGFloat.random(in: 120...780)
        let it = h.add(kind, at: CGPoint(x: x, y: kind.hangs ? 540 : 0))
        habitat = h
        selected = it.id
        onChange?(habitat)
    }

    func updateSelected(_ f: (inout HabitatItem) -> Void) {
        guard let id = selected, let idx = habitat.items.firstIndex(where: { $0.id == id }) else { return }
        var it = habitat.items[idx]
        f(&it)
        habitat.items[idx] = it
        onChange?(habitat)
    }

    func removeSelected() {
        guard let id = selected else { return }
        habitat.items.removeAll { $0.id == id }
        selected = nil
        onChange?(habitat)
    }

    func duplicateSelected() {
        guard let id = selected, let it = habitat.items.first(where: { $0.id == id }) else { return }
        var h = habitat
        var copy = it
        copy.id = h.nextID
        h.nextID += 1
        copy.x = min(880, it.x + 40)
        copy.seed = Int.random(in: 1...9999)
        h.items.append(copy)
        habitat = h
        selected = copy.id
        onChange?(habitat)
    }

    /// Where it arrives when it climbs in: on the floor, in the middle, in
    /// screen coordinates.
    var entryPoint: V2 { let s = screenScene; return V2(s.midX, s.minY + map.standoff + 2) }
}

// MARK: - Window and builder

final class HabitatController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let view: HabitatView
    private let sidebar = NSView()
    private var sidebarShown = false
    private var biomePopup: NSPopUpButton!
    private var presetPopup: NSPopUpButton!
    private var selectionBox: NSStackView!
    private var sizeSlider: NSSlider!
    var onLeave: (() -> Void)?

    init(spider: Spider) {
        let frame = CGRect(x: 0, y: 0, width: 960, height: 600)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "\(spider.name.isEmpty ? "Spider" : spider.name)'s Habitat"
        // Closing the window (the red button) must not free it: the
        // controller keeps it for next time.
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 700, height: 460)
        window.center()
        view = HabitatView(frame: frame)
        view.spider = spider
        super.init()
        window.delegate = self
        buildChrome()
        view.habitat = Habitat.load()
        view.onChange = { h in h.save() }
        view.onSelect = { [weak self] _ in self?.refreshSelection() }
        window.contentView = view
        view.layout()
        window.setFrameAutosaveName("habitat")
    }

    private func buildChrome() {
        // Two small buttons in the top-right corner of the tank.
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.translatesAutoresizingMaskIntoConstraints = false
        let build = NSButton(title: "Build", target: self, action: #selector(toggleBuild))
        build.bezelStyle = .rounded
        build.controlSize = .small
        let leave = NSButton(title: "Leave Habitat", target: self, action: #selector(leave))
        leave.bezelStyle = .rounded
        leave.controlSize = .small
        bar.addArrangedSubview(build)
        bar.addArrangedSubview(leave)
        view.addSubview(bar)
        bar.topAnchor.constraint(equalTo: view.topAnchor, constant: 22).isActive = true
        bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22).isActive = true

        // The builder: a panel down the right-hand side, hidden until asked for.
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = CGColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 0.94)
        sidebar.layer?.cornerRadius = 10
        sidebar.isHidden = true
        view.addSubview(sidebar)
        sidebar.widthAnchor.constraint(equalToConstant: 236).isActive = true
        sidebar.topAnchor.constraint(equalTo: view.topAnchor, constant: 52).isActive = true
        sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -22).isActive = true
        sidebar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22).isActive = true

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        sidebar.addSubview(scroll)
        scroll.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 8).isActive = true
        scroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -8).isActive = true
        scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8).isActive = true
        scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8).isActive = true

        let col = NSStackView()
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 6
        col.translatesAutoresizingMaskIntoConstraints = false
        col.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 8, right: 6)

        col.addArrangedSubview(label("Scenery", bold: true))
        biomePopup = NSPopUpButton()
        for b in Biome.allCases { biomePopup.addItem(withTitle: b.label) }
        biomePopup.target = self
        biomePopup.action = #selector(biomePicked)
        col.addArrangedSubview(biomePopup)

        col.addArrangedSubview(label("Start from", bold: true))
        presetPopup = NSPopUpButton()
        presetPopup.addItem(withTitle: "Choose a layout…")
        for p in Habitat.Preset.allCases { presetPopup.addItem(withTitle: p.label) }
        presetPopup.target = self
        presetPopup.action = #selector(presetPicked)
        col.addArrangedSubview(presetPopup)
        let surprise = NSButton(title: "Surprise me", target: self, action: #selector(surpriseMe))
        surprise.controlSize = .small
        col.addArrangedSubview(surprise)

        col.addArrangedSubview(label("Add", bold: true))
        let climb = label("Things to climb", bold: false)
        col.addArrangedSubview(climb)
        col.addArrangedSubview(grid(HabitatItemKind.allCases.filter { $0.climbable }))
        col.addArrangedSubview(label("Scenery", bold: false))
        col.addArrangedSubview(grid(HabitatItemKind.allCases.filter { !$0.climbable }))

        col.addArrangedSubview(label("Selected", bold: true))
        selectionBox = NSStackView()
        selectionBox.orientation = .vertical
        selectionBox.alignment = .leading
        selectionBox.spacing = 6
        sizeSlider = NSSlider(value: 1, minValue: 0.4, maxValue: 3, target: self, action: #selector(sizeChanged))
        sizeSlider.translatesAutoresizingMaskIntoConstraints = false
        sizeSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        selectionBox.addArrangedSubview(label("Size", bold: false))
        selectionBox.addArrangedSubview(sizeSlider)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        let flip = NSButton(title: "Flip", target: self, action: #selector(flipSelected)); flip.controlSize = .small
        let dup = NSButton(title: "Duplicate", target: self, action: #selector(duplicateSelected)); dup.controlSize = .small
        let del = NSButton(title: "Remove", target: self, action: #selector(removeSelected)); del.controlSize = .small
        row.addArrangedSubview(flip); row.addArrangedSubview(dup); row.addArrangedSubview(del)
        selectionBox.addArrangedSubview(row)
        let order = NSStackView()
        order.orientation = .horizontal
        order.spacing = 6
        let back = NSButton(title: "Send back", target: self, action: #selector(sendBack)); back.controlSize = .small
        let fwd = NSButton(title: "Bring forward", target: self, action: #selector(bringForward)); fwd.controlSize = .small
        order.addArrangedSubview(back); order.addArrangedSubview(fwd)
        selectionBox.addArrangedSubview(order)
        col.addArrangedSubview(selectionBox)

        col.addArrangedSubview(label(" ", bold: false))
        let clear = NSButton(title: "Clear everything", target: self, action: #selector(clearAll))
        clear.controlSize = .small
        col.addArrangedSubview(clear)

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(col)
        col.topAnchor.constraint(equalTo: doc.topAnchor).isActive = true
        col.leadingAnchor.constraint(equalTo: doc.leadingAnchor).isActive = true
        col.trailingAnchor.constraint(equalTo: doc.trailingAnchor).isActive = true
        col.bottomAnchor.constraint(equalTo: doc.bottomAnchor).isActive = true
        doc.widthAnchor.constraint(equalToConstant: 212).isActive = true
        scroll.documentView = doc
        refreshSelection()
    }

    private func label(_ text: String, bold: Bool) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = bold ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 11)
        l.textColor = bold ? .white : NSColor(white: 0.75, alpha: 1)
        return l
    }

    /// Buttons for each kind of thing, three to a row.
    private func grid(_ kinds: [HabitatItemKind]) -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 4
        var row: NSStackView?
        for (i, k) in kinds.enumerated() {
            if i % 2 == 0 {
                row = NSStackView()
                row!.orientation = .horizontal
                row!.spacing = 4
                rows.addArrangedSubview(row!)
            }
            let b = NSButton(title: k.label, target: self, action: #selector(addItem(_:)))
            b.controlSize = .small
            b.bezelStyle = .rounded
            b.tag = HabitatItemKind.allCases.firstIndex(of: k) ?? 0
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 98).isActive = true
            row!.addArrangedSubview(b)
        }
        return rows
    }

    private func refreshSelection() {
        biomePopup?.selectItem(at: Biome.allCases.firstIndex(of: view.habitat.biome) ?? 0)
        guard let box = selectionBox else { return }
        if let id = view.selected, let it = view.habitat.items.first(where: { $0.id == id }) {
            box.isHidden = false
            let base = it.kind.defaultSize
            sizeSlider.doubleValue = Double(it.w / base.width)
        } else {
            box.isHidden = true
        }
    }

    // MARK: Actions

    @objc private func toggleBuild() {
        sidebarShown.toggle()
        sidebar.isHidden = !sidebarShown
        view.building = sidebarShown
        refreshSelection()
    }

    @objc private func leave() { onLeave?() }

    @objc private func biomePicked() {
        view.habitat.biome = Biome.allCases[biomePopup.indexOfSelectedItem]
        view.onChange?(view.habitat)
    }

    @objc private func presetPicked() {
        let i = presetPopup.indexOfSelectedItem
        guard i > 0 else { return }
        view.habitat = Habitat.preset(Habitat.Preset.allCases[i - 1])
        view.onChange?(view.habitat)
        presetPopup.selectItem(at: 0)
        refreshSelection()
    }

    @objc private func surpriseMe() {
        let presets = Habitat.Preset.allCases.filter { $0 != .empty }
        var h = Habitat.preset(presets.randomElement()!)
        // Shuffle things about a little so no two are the same.
        for i in h.items.indices {
            h.items[i].x = max(40, min(860, h.items[i].x + CGFloat.random(in: -60...60)))
            h.items[i].seed = Int.random(in: 1...9999)
            let k = CGFloat.random(in: 0.85...1.2)
            h.items[i].w *= k; h.items[i].h *= k
        }
        view.habitat = h
        view.onChange?(h)
        refreshSelection()
    }

    @objc private func addItem(_ b: NSButton) {
        view.add(HabitatItemKind.allCases[b.tag])
    }

    @objc private func sizeChanged() {
        let k = CGFloat(sizeSlider.doubleValue)
        view.updateSelected { it in
            let base = it.kind.defaultSize
            it.w = base.width * k
            it.h = base.height * k
        }
    }

    @objc private func flipSelected() { view.updateSelected { $0.flipped.toggle() } }
    @objc private func duplicateSelected() { view.duplicateSelected() }
    @objc private func removeSelected() { view.removeSelected() }

    @objc private func sendBack() {
        guard let id = view.selected, let i = view.habitat.items.firstIndex(where: { $0.id == id }), i > 0 else { return }
        var h = view.habitat
        h.items.swapAt(i, i - 1)
        view.habitat = h
        view.onChange?(h)
    }

    @objc private func bringForward() {
        guard let id = view.selected, let i = view.habitat.items.firstIndex(where: { $0.id == id }), i < view.habitat.items.count - 1 else { return }
        var h = view.habitat
        h.items.swapAt(i, i + 1)
        view.habitat = h
        view.onChange?(h)
    }

    @objc private func clearAll() {
        var h = view.habitat
        h.items = []
        view.habitat = h
        view.onChange?(h)
    }

    func windowWillClose(_ notification: Notification) {
        onLeave?()
    }

    private var lastOrigin = CGPoint.zero
    func windowDidMove(_ notification: Notification) {
        let o = window.frame.origin
        let d = CGPoint(x: o.x - lastOrigin.x, y: o.y - lastOrigin.y)
        lastOrigin = o
        if abs(d.x) + abs(d.y) > 0.5, abs(d.x) + abs(d.y) < 4000 { view.windowMoved(by: d) }
    }
    func windowDidResize(_ notification: Notification) {
        lastOrigin = window.frame.origin
    }
    func noteOrigin() { lastOrigin = window.frame.origin }
}
