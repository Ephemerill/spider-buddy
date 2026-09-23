import AppKit
import QuartzCore

// MARK: - Thumbnails

extension SpiderRenderer {
    /// A standing pose with every leg at rest, for thumbnails and previews.
    static func restPose(look: SpiderLook, yaw: CGFloat, scale: CGFloat) -> SpiderPose {
        var p = SpiderPose()
        p.outfit = look
        p.facing = yaw
        p.scale = scale
        let profile = profileAmount(yaw: yaw)
        p.legs = (0..<legCount).map { i in
            let r = rig(i, profile: profile, look: look)
            return LegPose(hip: r.hip, knee: knee(leg: i, hip: r.hip, foot: r.foot, lift: 0, profile: profile, look: look),
                           foot: r.foot, lift: 0)
        }
        return p
    }

    /// Renders the spider standing still into a square image. `closeUp`
    /// frames the face instead of the whole animal.
    static func thumbnail(look: SpiderLook, side: CGFloat, front: Bool, closeUp: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let scale = closeUp ? side / 62 : side / 118
            let pose = restPose(look: look, yaw: front ? 0 : 1, scale: scale)
            // Body origin sits a little below centre so hats have headroom;
            // a close-up centres the head instead.
            let hc = front ? frontHead.c : head.c
            let box = closeUp
                ? CGRect(x: -hc.x * scale, y: -(hc.y + 2) * scale, width: side, height: side)
                : CGRect(x: 0, y: -side * 0.08, width: side, height: side)
            draw(pose, in: ctx, bounds: box)
            return true
        }
        return img
    }
}

// MARK: - Option cell

/// One choice in a grid: a thumbnail with its name under it. Selected cells
/// get the accent ring, like the Mii maker's part picker.
final class OptionCell: NSControl {
    var image: NSImage? { didSet { needsDisplay = true } }
    var label = "" { didSet { needsDisplay = true } }
    var isSelected = false { didSet { needsDisplay = true } }
    var swatch: NSColor?
    var onPick: (() -> Void)?
    private var hovered = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2.5
            path.stroke()
        } else {
            (hovered ? NSColor.quaternaryLabelColor.withAlphaComponent(0.25) : NSColor.quaternaryLabelColor.withAlphaComponent(0.08)).setFill()
            path.fill()
        }
        if let swatch {
            let d: CGFloat = min(r.width, r.height) * 0.5
            let c = CGRect(x: r.midX - d / 2, y: r.midY - d / 2 + 8, width: d, height: d)
            swatch.setFill()
            NSBezierPath(ovalIn: c).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            NSBezierPath(ovalIn: c).stroke()
        } else if let image {
            let s = min(r.width, r.height) - 24
            image.draw(in: CGRect(x: r.midX - s / 2, y: r.minY + 20, width: s, height: s))
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.minY + 5))
    }
}

/// A fixed-column grid of option cells; sized to its content.
final class OptionGrid: NSView {
    private(set) var cells: [OptionCell] = []
    let columns: Int
    let cellSize: CGSize

    init(count: Int, columns: Int = 4, cellSize: CGSize = CGSize(width: 96, height: 106)) {
        self.columns = columns
        self.cellSize = cellSize
        let rows = (count + columns - 1) / columns
        super.init(frame: CGRect(x: 0, y: 0, width: cellSize.width * CGFloat(columns),
                                 height: cellSize.height * CGFloat(rows)))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: frame.width).isActive = true
        heightAnchor.constraint(equalToConstant: frame.height).isActive = true
        for i in 0..<count {
            let col = i % columns, row = i / columns
            let cell = OptionCell(frame: CGRect(x: CGFloat(col) * cellSize.width,
                                                y: frame.height - CGFloat(row + 1) * cellSize.height,
                                                width: cellSize.width, height: cellSize.height))
            addSubview(cell)
            cells.append(cell)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { false }
}

// MARK: - Live preview

/// A little terrarium: the spider lives on the walls of the box and a ledge
/// in the middle, so every part can be seen moving. It is a real `Spider`
/// on a real `SurfaceMap`, so what you see is what you get.
final class StudioPreview: NSView {
    let map = SurfaceMap()
    let spider: Spider
    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0
    private let previewScale: CGFloat = 1.55
    private var ledge = CGRect.zero
    private var dragging = false
    private var samples: [(V2, TimeInterval)] = []

    override init(frame: NSRect) {
        spider = Spider(map: map)
        super.init(frame: frame)
        wantsLayer = true
        spider.config.scale = previewScale
        spider.config.webs = true
        spider.config.followCursor = true
        map.standoff = -SpiderRenderer.ground * previewScale
        rebuildMap()
        spider.debugAttach(loopID: "win:1", segIdx: 0, t: 40, dir: 1)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuildMap() {
        let b = bounds.insetBy(dx: 4, dy: 4)
        ledge = CGRect(x: b.midX - 80, y: b.minY + 70, width: 160, height: 70)
        map.debugRebuild(screen: b, menuBarHeight: 0,
                         windows: [TrackedWindow(id: 1, frame: ledge, depth: 0, owner: "Studio")])
    }

    override func layout() {
        super.layout()
        rebuildMap()
    }

    func start() {
        guard timer == nil else { return }
        lastTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastTime, 1.0 / 240.0), 1.0 / 20.0))
        lastTime = now
        // What is behind its body in here: the white card when its body is
        // over it (hanging under the ledge, or on its side), the box
        // otherwise — so a camouflaged coat can be seen changing.
        let body = spider.worldPos + spider.standingNormal * (4 * spider.config.scale)
        spider.surroundings = ledge.contains(body.point) ? RGB(1, 1, 1) : RGB(0.98, 0.96, 0.92)
        spider.update(dt: dt)
        needsDisplay = true
    }

    func show(_ activity: String) {
        spider.debugActivity(activity, for: activity == "sleep" ? 6 : 2.0)
    }

    // Pointer play, just like on the desktop.
    private func local(_ e: NSEvent) -> V2 { V2(convert(e.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { spider.setCursor(local(event)) }
    override func mouseExited(with event: NSEvent) { spider.setCursor(V2(-9e4, -9e4)) }
    override func mouseDown(with event: NSEvent) {
        let p = local(event)
        if event.clickCount >= 2 { spider.celebrate(); return }
        if spider.hitTest(p) {
            spider.beginGrab(at: p)
            dragging = true
            samples = [(p, event.timestamp)]
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let p = local(event)
        spider.moveGrab(to: p)
        samples.append((p, event.timestamp))
        if samples.count > 8 { samples.removeFirst() }
    }
    override func mouseUp(with event: NSEvent) {
        guard dragging else {
            if spider.hitTest(local(event)) { spider.poke() }
            return
        }
        dragging = false
        var v = V2.zero
        if let a = samples.first, let b = samples.last, b.1 - a.1 > 0.01 {
            v = (b.0 - a.0) / CGFloat(b.1 - a.1)
        }
        if v.length < 120 { v = .zero }
        spider.endGrab(throwVelocity: v)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // The box.
        let box = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        NSColor(calibratedRed: 0.93, green: 0.90, blue: 0.84, alpha: 1).setFill()
        box.fill()
        let inner = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 13, yRadius: 13)
        NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.92, alpha: 1).setFill()
        inner.fill()
        NSColor(calibratedRed: 0.80, green: 0.72, blue: 0.60, alpha: 1).setStroke()
        inner.lineWidth = 1
        inner.stroke()

        // The ledge in the middle, drawn as a tiny window.
        let card = NSBezierPath(roundedRect: ledge, xRadius: 8, yRadius: 8)
        NSColor.white.setFill()
        card.fill()
        NSColor(white: 0.75, alpha: 1).setStroke()
        card.stroke()
        let bar = CGRect(x: ledge.minX, y: ledge.maxY - 16, width: ledge.width, height: 16)
        ctx.saveGState()
        card.addClip()
        NSColor(white: 0.92, alpha: 1).setFill()
        bar.fill()
        for (i, c) in [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: CGRect(x: ledge.minX + 7 + CGFloat(i) * 11, y: bar.midY - 3.5, width: 7, height: 7)).fill()
        }
        ctx.restoreGState()

        let pose = spider.pose()
        // Silk.
        if let web = pose.web, let path = SpiderRenderer.silkPath(pose) {
            ctx.setStrokeColor(CGColor(gray: 0.55, alpha: Double(web.alpha) * 0.7))
            ctx.setLineWidth(1)
            ctx.beginPath()
            ctx.addPath(path)
            ctx.strokePath()
        }
        let side = SpiderRenderer.spriteSide(for: previewScale)
        SpiderRenderer.draw(pose, in: ctx, bounds: CGRect(x: pose.pos.x - side / 2, y: pose.pos.y - side / 2,
                                                          width: side, height: side))
    }
}

/// Scroll content that starts at the top instead of the bottom.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Studio window

/// The Spider Studio: pick parts, colours, character and gait, and name it.
/// Every change goes straight to the spider on the desktop.
final class StudioController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv === phrasesView else { return }
        design.customPhrases = tv.string.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        preview.spider.apply(design: design)
        onChange?(design)
    }

    private(set) var design: SpiderDesign
    var onChange: ((SpiderDesign) -> Void)?
    /// The window has come on screen or gone; the desktop spider treats it
    /// as furniture while it is up.
    var onVisibility: ((_ windowNumber: CGWindowID, _ shown: Bool) -> Void)?

    private var window: NSWindow!
    private var preview: StudioPreview!
    private var nameField: NSTextField!
    private var tabs: NSTabView!
    /// The tab strip, in two rows: ten tabs' names do not fit in one.
    private var tabRows: [NSSegmentedControl] = []
    /// Every option grid, with the tab it lives in: only the grids on the
    /// tab that is showing are re-thumbnailed on a change, the rest when
    /// their tab next comes up.
    private var grids: [(grid: OptionGrid, tab: Int, refresh: () -> Void)] = []
    private var dirtyTabs = Set<Int>()
    private var buildingTab = 0
    private var currentTab = 0
    /// Controls that mirror the draft and are re-read on every change.
    private var syncers: [() -> Void] = []
    private var sliders: [(NSSlider, () -> CGFloat)] = []
    private var presetPopup: NSPopUpButton!
    private var stylePopup: NSPopUpButton!
    private var sizeSlider: NSSlider!
    var scale: CGFloat = 0.95
    var onScale: ((CGFloat) -> Void)?

    init(design: SpiderDesign) {
        self.design = design
        super.init()
        build()
    }

    func show() {
        preview.spider.apply(design: design)
        syncControls()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        preview.start()
        onVisibility?(CGWindowID(window.windowNumber), true)
    }

    func windowWillClose(_ notification: Notification) {
        preview.stop()
        onVisibility?(CGWindowID(window.windowNumber), false)
    }

    /// Writes the window's contents to a PNG — the app's own drawing, so it
    /// needs no screen-recording permission. Used by tooling.
    /// For studio snapshots: every hand-shaped part selected, so its
    /// sliders show. Only the studio's draft: nothing is saved.
    func debugSelectCustom() {
        design.look.body = .custom
        design.look.eyes = .custom
        design.look.legs = .custom
        preview.spider.apply(design: design)
        syncControls()
    }

    func snapshot(to path: String, tab: Int) {
        showTab(tab)
        window.contentView?.layoutSubtreeIfNeeded()
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        window.backgroundColor.setFill()
        view.bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        // And the whole of the tab's contents, however far it scrolls.
        if let scroll = tabs.tabViewItem(at: tab).view as? NSScrollView, let doc = scroll.documentView,
           let full = doc.bitmapImageRepForCachingDisplay(in: doc.bounds) {
            doc.cacheDisplay(in: doc.bounds, to: full)
            let fullPath = path.replacingOccurrences(of: ".png", with: "_full.png")
            try? full.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: fullPath))
        }
    }

    // MARK: Building

    private func build() {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Spider Studio"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let root = NSStackView()
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false

        // Left: preview, name, pose, buttons.
        let left = NSStackView()
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 10

        preview = StudioPreview(frame: CGRect(x: 0, y: 0, width: 330, height: 320))
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 330).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 320).isActive = true
        left.addArrangedSubview(preview)

        let nameRow = NSStackView()
        nameRow.orientation = .horizontal
        nameRow.spacing = 8
        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameField = NSTextField(string: design.name)
        nameField.placeholderString = "What's it called?"
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let dice = NSButton(title: "🎲", target: self, action: #selector(randomName))
        dice.bezelStyle = .rounded
        dice.toolTip = "Pick a name for me"
        nameRow.addArrangedSubview(nameLabel)
        nameRow.addArrangedSubview(nameField)
        nameRow.addArrangedSubview(dice)
        left.addArrangedSubview(nameRow)

        let poseRow = NSStackView()
        poseRow.orientation = .horizontal
        poseRow.spacing = 8
        let poseLabel = NSTextField(labelWithString: "Show me")
        poseLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let poses = NSPopUpButton()
        for (title, key) in StudioController.poses {
            let item = NSMenuItem(title: title, action: #selector(showPose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            poses.menu?.addItem(item)
        }
        poses.selectItem(at: 0)
        poseRow.addArrangedSubview(poseLabel)
        poseRow.addArrangedSubview(poses)
        left.addArrangedSubview(poseRow)

        let hint = NSTextField(wrappingLabelWithString: "Click, drag and throw it in the box. Everything you change here happens on your desktop straight away.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.widthAnchor.constraint(equalToConstant: 330).isActive = true
        left.addArrangedSubview(hint)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 4).isActive = true
        left.addArrangedSubview(spacer)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let random = NSButton(title: "Surprise Me", target: self, action: #selector(randomize))
        random.bezelStyle = .rounded
        let reset = NSButton(title: "Start Over", target: self, action: #selector(resetDesign))
        reset.bezelStyle = .rounded
        let done = NSButton(title: "Done", target: self, action: #selector(close))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        buttons.addArrangedSubview(random)
        buttons.addArrangedSubview(reset)
        buttons.addArrangedSubview(done)
        left.addArrangedSubview(buttons)
        root.addArrangedSubview(left)

        // Right: the part pickers. The tab names go in two rows of their
        // own above a tabless tab view — one row for how it looks, one for
        // how it acts — since ten of them do not fit across one strip.
        let right = NSStackView()
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 6
        tabs = NSTabView()
        tabs.tabViewType = .noTabsBezelBorder
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.widthAnchor.constraint(equalToConstant: 530).isActive = true
        tabs.heightAnchor.constraint(equalToConstant: 500).isActive = true
        let builders: [[(String, () -> NSView)]] = [
            [("Body", buildBodyTab), ("Face", buildFaceTab), ("Legs", buildLegsTab),
             ("Colours", buildColourTab), ("Markings", buildMarkingsTab), ("Hats", buildHatTab), ("Extras", buildExtrasTab)],
            [("Personality", buildPersonalityTab), ("Gait", buildGaitTab),
             ("Habits", buildHabitsTab), ("Thoughts", buildThoughtsTab)],
        ]
        var rows: [[(String, NSView)]] = []
        for row in builders {
            rows.append(row.map { name, build in
                let v = build()
                buildingTab += 1
                return (name, v)
            })
        }
        for (r, row) in rows.enumerated() {
            let seg = NSSegmentedControl(labels: row.map(\.0), trackingMode: .selectOne,
                                         target: self, action: #selector(tabRowPicked(_:)))
            seg.tag = r
            seg.segmentDistribution = .fillEqually
            seg.translatesAutoresizingMaskIntoConstraints = false
            seg.widthAnchor.constraint(equalToConstant: 530).isActive = true
            right.addArrangedSubview(seg)
            tabRows.append(seg)
            for (title, view) in row { tabs.addTabViewItem(tab(title, view)) }
        }
        right.addArrangedSubview(tabs)
        root.addArrangedSubview(right)
        showTab(0)

        window.contentView = root
        refreshGrids()
    }

    /// Shows tab `index` (counting across both rows) and lights its name.
    private func showTab(_ index: Int) {
        currentTab = index
        if dirtyTabs.contains(index) {
            dirtyTabs.remove(index)
            for g in grids where g.tab == index { g.refresh() }
        }
        tabs.selectTabViewItem(at: index)
        var offset = 0
        for seg in tabRows {
            let local = index - offset
            seg.selectedSegment = local >= 0 && local < seg.segmentCount ? local : -1
            offset += seg.segmentCount
        }
    }

    @objc private func tabRowPicked(_ seg: NSSegmentedControl) {
        let offset = tabRows.prefix(seg.tag).reduce(0) { $0 + $1.segmentCount }
        showTab(offset + seg.selectedSegment)
    }

    private static let poses: [(String, String)] = [
        ("Just being itself", ""), ("Walk", "walk"), ("Scurry", "scurry"), ("Sneak", "sneak"),
        ("Turn around", "turn"), ("Wave", "wave"), ("Arms up", "armsUp"), ("Dance", "dance"),
        ("Roll", "roll"), ("Spin", "spin"), ("Swing on a line", "swing"), ("Stretch", "stretch"), ("Groom", "groom"),
        ("Push-ups", "pushup"), ("Peer over", "peer"), ("Curious", "curious"), ("Rest", "rest"), ("Sleep", "sleep"),
    ]

    private func tab(_ title: String, _ content: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        content.topAnchor.constraint(equalTo: doc.topAnchor).isActive = true
        content.leadingAnchor.constraint(equalTo: doc.leadingAnchor).isActive = true
        content.trailingAnchor.constraint(equalTo: doc.trailingAnchor).isActive = true
        content.bottomAnchor.constraint(equalTo: doc.bottomAnchor).isActive = true
        scroll.documentView = doc
        doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor).isActive = true
        doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor).isActive = true
        doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        item.view = scroll
        return item
    }

    private func column() -> NSStackView {
        let v = NSStackView()
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 8
        v.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        return v
    }

    private func header(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        return l
    }

    /// A grid for one enum-valued part. `get`/`set` read and write the draft;
    /// `preview` builds the look to thumbnail for a given option.
    private func partGrid<T: CaseIterable & Equatable>(
        _ type: T.Type, front: Bool = false, closeUp: Bool = false, columns: Int = 4,
        label: @escaping (T) -> String,
        get: @escaping () -> T, set: @escaping (T) -> Void,
        selected: ((T) -> Bool)? = nil,
        preview: @escaping (T) -> SpiderLook
    ) -> OptionGrid {
        let all = Array(type.allCases)
        let grid = OptionGrid(count: all.count, columns: columns)
        for (i, opt) in all.enumerated() {
            let cell = grid.cells[i]
            cell.label = label(opt)
            cell.onPick = { [weak self] in
                set(opt)
                self?.changed()
            }
        }
        grids.append((grid, buildingTab, {
            let cur = get()
            for (i, opt) in all.enumerated() {
                let cell = grid.cells[i]
                cell.isSelected = selected?(opt) ?? (opt == cur)
                cell.image = SpiderRenderer.thumbnail(look: preview(opt), side: 72, front: front, closeUp: closeUp)
            }
        }))
        return grid
    }

    /// A single option cell standing on its own, for "your own" choices.
    private func soloCell(_ title: String, isOn: @escaping () -> Bool, pick: @escaping () -> Void,
                          preview: @escaping () -> SpiderLook) -> OptionGrid {
        let grid = OptionGrid(count: 1, columns: 1)
        let cell = grid.cells[0]
        cell.label = title
        cell.onPick = { [weak self] in pick(); self?.changed() }
        grids.append((grid, buildingTab, {
            cell.isSelected = isOn()
            cell.image = SpiderRenderer.thumbnail(look: preview(), side: 72, front: false)
        }))
        return grid
    }

    private func note(_ text: String, width: CGFloat = 470) -> NSTextField {
        let n = NSTextField(wrappingLabelWithString: text)
        n.font = .systemFont(ofSize: 11)
        n.textColor = .secondaryLabelColor
        n.translatesAutoresizingMaskIntoConstraints = false
        n.widthAnchor.constraint(equalToConstant: width).isActive = true
        return n
    }

    private func subheader(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12, weight: .medium)
        return l
    }

    /// A labelled colour well. Changing it writes straight to the draft.
    private var wellSetters: [ObjectIdentifier: (RGB) -> Void] = [:]
    private func well(_ title: String, get: @escaping () -> RGB, set: @escaping (RGB) -> Void) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        let w = NSColorWell()
        w.colorWellStyle = .minimal
        w.isContinuous = true
        w.color = get().ns
        w.target = self
        w.action = #selector(wellChanged(_:))
        w.translatesAutoresizingMaskIntoConstraints = false
        w.widthAnchor.constraint(equalToConstant: 44).isActive = true
        w.heightAnchor.constraint(equalToConstant: 26).isActive = true
        wellSetters[ObjectIdentifier(w)] = set
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 12)
        row.addArrangedSubview(w)
        row.addArrangedSubview(l)
        syncers.append { [weak w] in
            guard let w else { return }
            let c = get()
            if RGB(w.color) != c { w.color = c.ns }
        }
        return row
    }

    @objc private func wellChanged(_ w: NSColorWell) {
        wellSetters[ObjectIdentifier(w)]?(RGB(w.color))
        changed()
    }

    private func checkbox(_ title: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxToggled(_:)))
        b.state = get() ? .on : .off
        checkSetters[ObjectIdentifier(b)] = set
        syncers.append { [weak b] in b?.state = get() ? .on : .off }
        return b
    }
    private var checkSetters: [ObjectIdentifier: (Bool) -> Void] = [:]
    @objc private func checkboxToggled(_ b: NSButton) {
        checkSetters[ObjectIdentifier(b)]?(b.state == .on)
        changed()
    }

    private func slider(_ title: String, low: String, high: String,
                        get: @escaping () -> CGFloat, set: @escaping (CGFloat) -> Void) -> NSView {
        let col = NSStackView()
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 2
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 12, weight: .medium)
        col.addArrangedSubview(t)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let l = NSTextField(labelWithString: low)
        l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor
        l.alignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 86).isActive = true
        let s = NSSlider(value: Double(get()), minValue: 0, maxValue: 1, target: self, action: #selector(sliderMoved(_:)))
        s.isContinuous = true
        s.translatesAutoresizingMaskIntoConstraints = false
        s.widthAnchor.constraint(equalToConstant: 250).isActive = true
        let h = NSTextField(labelWithString: high)
        h.font = .systemFont(ofSize: 11); h.textColor = .secondaryLabelColor
        h.translatesAutoresizingMaskIntoConstraints = false
        h.widthAnchor.constraint(equalToConstant: 86).isActive = true
        row.addArrangedSubview(l)
        row.addArrangedSubview(s)
        row.addArrangedSubview(h)
        col.addArrangedSubview(row)
        sliderSetters[ObjectIdentifier(s)] = set
        sliders.append((s, get))
        return col
    }
    private var sliderSetters: [ObjectIdentifier: (CGFloat) -> Void] = [:]

    /// A slider over a real range, for a measurement rather than a weight.
    private func tuneSlider(_ title: String, low: String, high: String, range: ClosedRange<CGFloat>,
                            get: @escaping () -> CGFloat, set: @escaping (CGFloat) -> Void) -> NSView {
        let span = range.upperBound - range.lowerBound
        return slider(title, low: low, high: high,
                      get: { (get() - range.lowerBound) / span },
                      set: { set(range.lowerBound + $0 * span) })
    }

    /// The sliders for a part shaped by hand, shown only while that part is
    /// set to Custom; the grid's Custom cell shows what they make.
    private func tuneBox(_ intro: String, shown: @escaping () -> Bool, _ rows: [NSView]) -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 6
        box.addArrangedSubview(note(intro))
        for r in rows { box.addArrangedSubview(r) }
        syncers.append { [weak box] in box?.isHidden = !shown() }
        return box
    }

    // MARK: Tabs

    private func buildBodyTab() -> NSView {
        let col = column()
        col.addArrangedSubview(header("Shape"))
        col.addArrangedSubview(partGrid(BodyShape.self, label: { $0.label },
                                        get: { self.design.look.body }, set: { self.design.look.body = $0 },
                                        preview: { var l = self.design.look; l.body = $0; return l }))
        col.addArrangedSubview(tuneBox("Shape it yourself: how wide and how tall the abdomen is, and how big the head.",
                                       shown: { self.design.look.body == .custom }, [
            tuneSlider("Abdomen width", low: "Narrow", high: "Wide", range: BodyTune.widthRange,
                       get: { self.design.look.bodyTune.width }, set: { self.design.look.bodyTune.width = $0 }),
            tuneSlider("Abdomen height", low: "Flat", high: "Tall", range: BodyTune.heightRange,
                       get: { self.design.look.bodyTune.height }, set: { self.design.look.bodyTune.height = $0 }),
            tuneSlider("Head size", low: "Small", high: "Big", range: BodyTune.headRange,
                       get: { self.design.look.bodyTune.head }, set: { self.design.look.bodyTune.head = $0 }),
        ]))
        col.addArrangedSubview(header("Fuzz"))
        let fuzzGrid = OptionGrid(count: 3, columns: 4)
        for (i, name) in ["Sleek", "Fuzzy", "Very Fuzzy"].enumerated() {
            fuzzGrid.cells[i].label = name
            fuzzGrid.cells[i].onPick = { [weak self] in self?.design.look.fuzz = i; self?.changed() }
        }
        grids.append((fuzzGrid, buildingTab, { [weak self] in
            guard let self else { return }
            for i in 0..<3 {
                var l = self.design.look; l.fuzz = i
                fuzzGrid.cells[i].isSelected = self.design.look.fuzz == i
                fuzzGrid.cells[i].image = SpiderRenderer.thumbnail(look: l, side: 72, front: false)
            }
        }))
        col.addArrangedSubview(fuzzGrid)
        col.addArrangedSubview(header("Size"))
        let sizeRow = NSStackView()
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 8
        let small = NSTextField(labelWithString: "Tiny")
        small.font = .systemFont(ofSize: 11); small.textColor = .secondaryLabelColor
        sizeSlider = NSSlider(value: Double(scale), minValue: 0.6, maxValue: 1.6, target: self, action: #selector(sizeMoved(_:)))
        sizeSlider.isContinuous = true
        sizeSlider.translatesAutoresizingMaskIntoConstraints = false
        sizeSlider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        let big = NSTextField(labelWithString: "Chonky")
        big.font = .systemFont(ofSize: 11); big.textColor = .secondaryLabelColor
        sizeRow.addArrangedSubview(small)
        sizeRow.addArrangedSubview(sizeSlider)
        sizeRow.addArrangedSubview(big)
        col.addArrangedSubview(sizeRow)
        return col
    }

    private func buildFaceTab() -> NSView {
        let col = column()
        col.addArrangedSubview(header("Eyes"))
        col.addArrangedSubview(checkbox("Draw the face in front of the front legs",
                                        get: { self.design.look.faceOverLegs }, set: { self.design.look.faceOverLegs = $0 }))
        col.addArrangedSubview(note("The leg that reaches ahead crosses the face. Ticked, the eyes show over it; unticked, the leg passes in front of them. The far legs are always behind."))
        col.addArrangedSubview(partGrid(EyeStyle.self, front: true, closeUp: true, label: { $0.label },
                                        get: { self.design.look.eyes }, set: { self.design.look.eyes = $0 },
                                        preview: { var l = self.design.look; l.eyes = $0; return l }))
        col.addArrangedSubview(tuneBox("Shape the eyes yourself: how big, how tall, how far apart, and how heavy the lids.",
                                       shown: { self.design.look.eyes == .custom }, [
            tuneSlider("Size", low: "Beady", high: "Huge", range: EyeTune.sizeRange,
                       get: { self.design.look.eyeTune.size }, set: { self.design.look.eyeTune.size = $0 }),
            tuneSlider("Shape", low: "Wide", high: "Tall", range: EyeTune.heightRange,
                       get: { self.design.look.eyeTune.height }, set: { self.design.look.eyeTune.height = $0 }),
            tuneSlider("Spacing", low: "Close", high: "Far apart", range: EyeTune.spreadRange,
                       get: { self.design.look.eyeTune.spread }, set: { self.design.look.eyeTune.spread = $0 }),
            tuneSlider("Lids", low: "Open", high: "Sleepy", range: EyeTune.lidsRange,
                       get: { self.design.look.eyeTune.lids }, set: { self.design.look.eyeTune.lids = $0 }),
        ]))
        col.addArrangedSubview(header("Brows"))
        col.addArrangedSubview(partGrid(BrowStyle.self, front: true, closeUp: true, label: { $0.label },
                                        get: { self.design.look.brows }, set: { self.design.look.brows = $0 },
                                        preview: { var l = self.design.look; l.brows = $0; return l }))
        col.addArrangedSubview(header("Mouth"))
        col.addArrangedSubview(partGrid(FangStyle.self, front: true, closeUp: true, label: { $0.label },
                                        get: { self.design.look.fangs }, set: { self.design.look.fangs = $0 },
                                        preview: { var l = self.design.look; l.fangs = $0; return l }))
        return col
    }

    private func buildLegsTab() -> NSView {
        let col = column()
        col.addArrangedSubview(header("Legs"))
        col.addArrangedSubview(partGrid(LegStyle.self, label: { $0.label },
                                        get: { self.design.look.legs }, set: { self.design.look.legs = $0 },
                                        preview: { var l = self.design.look; l.legs = $0; return l }))
        col.addArrangedSubview(tuneBox("Shape the legs yourself: how thick they are, how far they reach, and how high the knees stand.",
                                       shown: { self.design.look.legs == .custom }, [
            tuneSlider("Thickness", low: "Spindly", high: "Chunky", range: LegTune.widthRange,
                       get: { self.design.look.legTune.width }, set: { self.design.look.legTune.width = $0 }),
            tuneSlider("Reach", low: "Stubby", high: "Long", range: LegTune.reachRange,
                       get: { self.design.look.legTune.reach }, set: { self.design.look.legTune.reach = $0 }),
            tuneSlider("Knees", low: "Low", high: "High", range: LegTune.kneeRange,
                       get: { self.design.look.legTune.knee }, set: { self.design.look.legTune.knee = $0 }),
        ]))
        return col
    }

    private func buildColourTab() -> NSView {
        let col = column()
        col.addArrangedSubview(header("Coat"))
        col.addArrangedSubview(partGrid(Coat.self, columns: 5, label: { $0.label },
                                        get: { self.design.look.coat },
                                        set: { self.design.look.skin = .coat; self.design.look.coat = $0 },
                                        selected: { self.design.look.skin == .coat && self.design.look.coat == $0 },
                                        preview: { var l = self.design.look; l.skin = .coat; l.coat = $0; return l }))

        col.addArrangedSubview(header("Gradients"))
        col.addArrangedSubview(partGrid(GradientCoat.self, columns: 5, label: { $0.label },
                                        get: { self.design.look.gradient },
                                        set: { self.design.look.skin = .gradient; self.design.look.gradient = $0 },
                                        selected: { self.design.look.skin == .gradient && self.design.look.gradient == $0 },
                                        preview: { var l = self.design.look; l.skin = .gradient; l.gradient = $0; return l }))

        col.addArrangedSubview(header("Living coats"))
        col.addArrangedSubview(note("These move. Colours slide, pulse and shift while it goes about its day; Camouflage takes on the colour of whatever is behind it."))
        col.addArrangedSubview(partGrid(LivingCoat.self, columns: 5, label: { $0.label },
                                        get: { self.design.look.living },
                                        set: { self.design.look.skin = .living; self.design.look.living = $0 },
                                        selected: { self.design.look.skin == .living && self.design.look.living == $0 },
                                        preview: { var l = self.design.look; l.skin = .living; l.living = $0; return l }))
        let camoRow = NSStackView()
        camoRow.orientation = .horizontal
        camoRow.spacing = 8
        camoRow.alignment = .centerY
        let camoNote = note("Camouflage matches the wallpaper and window colours it can work out on its own. To match exactly what is on screen behind it, let it see the screen.", width: 330)
        camoRow.addArrangedSubview(camoNote)
        let camoButton = NSButton(title: "Let it see the screen…", target: self, action: #selector(requestScreenAccess))
        camoButton.bezelStyle = .rounded
        camoRow.addArrangedSubview(camoButton)
        syncers.append { [weak camoButton, weak camoNote] in
            let ok = CGPreflightScreenCaptureAccess()
            camoButton?.isHidden = ok
            camoNote?.stringValue = ok
                ? "Camouflage can see the screen, so it matches exactly what is behind it."
                : "Camouflage matches the wallpaper and window colours it can work out on its own. To match exactly what is on screen behind it, let it see the screen."
        }
        col.addArrangedSubview(camoRow)

        col.addArrangedSubview(header("Your own colours"))
        col.addArrangedSubview(note("Pick a body colour and a leg colour. Choosing either puts them on."))
        let customRow = NSStackView()
        customRow.orientation = .horizontal
        customRow.spacing = 14
        customRow.alignment = .centerY
        customRow.addArrangedSubview(soloCell("Yours", isOn: { self.design.look.skin == .custom },
                                              pick: { self.design.look.skin = .custom },
                                              preview: { var l = self.design.look; l.skin = .custom; return l }))
        let wells = NSStackView()
        wells.orientation = .vertical
        wells.alignment = .leading
        wells.spacing = 6
        wells.addArrangedSubview(well("Body", get: { self.design.look.custom.body },
                                      set: { self.design.look.custom.body = $0; self.design.look.skin = .custom }))
        wells.addArrangedSubview(well("Legs", get: { self.design.look.custom.legs },
                                      set: { self.design.look.custom.legs = $0; self.design.look.skin = .custom }))
        let matchLegs = NSButton(title: "Legs to match", target: self, action: #selector(matchLegsToBody))
        matchLegs.bezelStyle = .rounded
        matchLegs.controlSize = .small
        matchLegs.font = .systemFont(ofSize: 11)
        wells.addArrangedSubview(matchLegs)
        customRow.addArrangedSubview(wells)
        col.addArrangedSubview(customRow)

        col.addArrangedSubview(header("Your own gradient"))
        col.addArrangedSubview(note("Two or three colours blended across it, whichever way you like. Shimmer makes it drift slowly back and forth."))
        let gradRow = NSStackView()
        gradRow.orientation = .horizontal
        gradRow.spacing = 14
        gradRow.alignment = .centerY
        gradRow.addArrangedSubview(soloCell("Yours", isOn: { self.design.look.skin == .customGradient },
                                            pick: { self.design.look.skin = .customGradient },
                                            preview: { var l = self.design.look; l.skin = .customGradient; return l }))
        let gwells = NSStackView()
        gwells.orientation = .vertical
        gwells.alignment = .leading
        gwells.spacing = 6
        let stops = NSStackView()
        stops.orientation = .horizontal
        stops.spacing = 12
        stops.addArrangedSubview(well("First", get: { self.design.look.customGradient.a },
                                      set: { self.design.look.customGradient.a = $0; self.design.look.skin = .customGradient }))
        stops.addArrangedSubview(well("Second", get: { self.design.look.customGradient.b },
                                      set: { self.design.look.customGradient.b = $0; self.design.look.skin = .customGradient }))
        stops.addArrangedSubview(well("Third", get: { self.design.look.customGradient.c },
                                      set: { self.design.look.customGradient.c = $0; self.design.look.customGradient.threeColours = true; self.design.look.skin = .customGradient }))
        gwells.addArrangedSubview(stops)
        let opts = NSStackView()
        opts.orientation = .horizontal
        opts.spacing = 12
        opts.addArrangedSubview(checkbox("Use the third", get: { self.design.look.customGradient.threeColours },
                                         set: { self.design.look.customGradient.threeColours = $0; self.design.look.skin = .customGradient }))
        opts.addArrangedSubview(checkbox("Shimmer", get: { self.design.look.customGradient.shimmer },
                                         set: { self.design.look.customGradient.shimmer = $0; self.design.look.skin = .customGradient }))
        let dir = NSPopUpButton()
        for d in GradientDirection.allCases { dir.addItem(withTitle: d.label) }
        dir.target = self
        dir.action = #selector(directionPicked(_:))
        syncers.append { [weak dir] in
            dir?.selectItem(at: GradientDirection.allCases.firstIndex(of: self.design.look.customGradient.direction) ?? 0)
        }
        opts.addArrangedSubview(dir)
        gwells.addArrangedSubview(opts)
        gradRow.addArrangedSubview(gwells)
        col.addArrangedSubview(gradRow)
        return col
    }

    @objc private func directionPicked(_ p: NSPopUpButton) {
        design.look.customGradient.direction = GradientDirection.allCases[max(0, p.indexOfSelectedItem)]
        design.look.skin = .customGradient
        changed()
    }

    @objc private func matchLegsToBody() {
        design.look.custom.legs = design.look.custom.body.darker(0.18)
        design.look.skin = .custom
        changed()
    }

    @objc private func requestScreenAccess() {
        // Asks the system; the first time this shows the Screen Recording
        // prompt, after that it opens System Settings.
        CGRequestScreenCaptureAccess()
        syncControls()
    }

    private func buildMarkingsTab() -> NSView {
        let col = column()
        col.addArrangedSubview(header("Markings"))
        col.addArrangedSubview(partGrid(Pattern.self, columns: 5, label: { $0.label },
                                        get: { self.design.look.pattern }, set: { self.design.look.pattern = $0 },
                                        preview: { var l = self.design.look; l.pattern = $0; return l }))
        col.addArrangedSubview(header("Accent colour"))
        col.addArrangedSubview(note("The colour of the markings, and of leg bands, socks, hats, scarves and the rest."))
        let accents = Array(Accent.allCases)
        let grid = OptionGrid(count: accents.count, columns: 5, cellSize: CGSize(width: 96, height: 80))
        for (i, a) in accents.enumerated() {
            let cell = grid.cells[i]
            cell.label = a.label
            cell.swatch = a.rgb.ns
            cell.onPick = { [weak self] in self?.design.look.accent = a; self?.design.look.customAccent = nil; self?.changed() }
        }
        grids.append((grid, buildingTab, { [weak self] in
            guard let self else { return }
            for (i, a) in accents.enumerated() {
                grid.cells[i].isSelected = self.design.look.customAccent == nil && self.design.look.accent == a
            }
        }))
        col.addArrangedSubview(grid)
        col.addArrangedSubview(subheader("Or one of your own"))
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 14
        row.alignment = .centerY
        let yours = OptionGrid(count: 1, columns: 1, cellSize: CGSize(width: 96, height: 80))
        yours.cells[0].label = "Yours"
        yours.cells[0].onPick = { [weak self] in
            guard let self else { return }
            if self.design.look.customAccent == nil { self.design.look.customAccent = self.design.look.accent.rgb }
            self.changed()
        }
        grids.append((yours, buildingTab, { [weak self] in
            guard let self else { return }
            yours.cells[0].swatch = (self.design.look.customAccent ?? self.design.look.accent.rgb).ns
            yours.cells[0].isSelected = self.design.look.customAccent != nil
        }))
        row.addArrangedSubview(yours)
        row.addArrangedSubview(well("Accent", get: { self.design.look.customAccent ?? self.design.look.accent.rgb },
                                    set: { self.design.look.customAccent = $0 }))
        col.addArrangedSubview(row)
        return col
    }

    private func buildHatTab() -> NSView {
        let col = column()
        col.addArrangedSubview(header("Hats"))
        col.addArrangedSubview(partGrid(Hat.self, label: { $0.label },
                                        get: { self.design.look.hat }, set: { self.design.look.hat = $0 },
                                        preview: { var l = self.design.look; l.hat = $0; return l }))
        return col
    }

    private func buildExtrasTab() -> NSView {
        let col = column()
        col.addArrangedSubview(header("Extras"))
        col.addArrangedSubview(partGrid(Accessory.self, label: { $0.label },
                                        get: { self.design.look.accessory }, set: { self.design.look.accessory = $0 },
                                        preview: { var l = self.design.look; l.accessory = $0; return l }))
        return col
    }

    private func buildPersonalityTab() -> NSView {
        let col = column()
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(header("Temperament"))
        presetPopup = NSPopUpButton()
        presetPopup.addItem(withTitle: "Custom")
        for p in Personality.presets { presetPopup.addItem(withTitle: p.name) }
        presetPopup.target = self
        presetPopup.action = #selector(presetPicked(_:))
        row.addArrangedSubview(presetPopup)
        col.addArrangedSubview(row)
        let note = NSTextField(wrappingLabelWithString: "These weigh what it chooses to do. A shy spider still waves sometimes; a lazy one still leaps.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        note.widthAnchor.constraint(equalToConstant: 470).isActive = true
        col.addArrangedSubview(note)
        col.addArrangedSubview(slider("Energy", low: "Sleepy", high: "Hyper",
                                      get: { self.design.personality.energy }, set: { self.design.personality.energy = $0 }))
        col.addArrangedSubview(slider("Curiosity", low: "Aloof", high: "Nosy",
                                      get: { self.design.personality.curiosity }, set: { self.design.personality.curiosity = $0 }))
        col.addArrangedSubview(slider("Bravery", low: "Skittish", high: "Fearless",
                                      get: { self.design.personality.bravery }, set: { self.design.personality.bravery = $0 }))
        col.addArrangedSubview(slider("Playfulness", low: "Serious", high: "Silly",
                                      get: { self.design.personality.playfulness }, set: { self.design.personality.playfulness = $0 }))
        col.addArrangedSubview(slider("Affection", low: "Grumpy", high: "Adoring",
                                      get: { self.design.personality.affection }, set: { self.design.personality.affection = $0 }))
        col.addArrangedSubview(slider("Laziness", low: "Restless", high: "Nap champion",
                                      get: { self.design.personality.laziness }, set: { self.design.personality.laziness = $0 }))
        return col
    }

    private var packBoxes: [ThoughtPack: NSButton] = [:]
    private var phrasesView: NSTextView!

    private func buildThoughtsTab() -> NSView {
        let col = column()
        col.addArrangedSubview(header("What it thinks about"))
        let note = NSTextField(wrappingLabelWithString: "Now and then a thought bubble appears over its head with a picture or a few words. Tick the packs of words it may use, and add lines of your own below, one per line.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        note.widthAnchor.constraint(equalToConstant: 470).isActive = true
        col.addArrangedSubview(note)
        for pack in ThoughtPack.allCases {
            let box = NSButton(checkboxWithTitle: pack.label, target: self, action: #selector(packToggled(_:)))
            box.state = design.packs.contains(pack) ? .on : .off
            box.tag = ThoughtPack.allCases.firstIndex(of: pack) ?? 0
            packBoxes[pack] = box
            col.addArrangedSubview(box)
            let sample = NSTextField(labelWithString: "e.g. " + (pack.phrases.first ?? ""))
            sample.font = .systemFont(ofSize: 10)
            sample.textColor = .tertiaryLabelColor
            sample.lineBreakMode = .byTruncatingTail
            sample.translatesAutoresizingMaskIntoConstraints = false
            sample.widthAnchor.constraint(equalToConstant: 460).isActive = true
            col.addArrangedSubview(sample)
        }
        col.addArrangedSubview(header("Your own lines"))
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 470).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: CGRect(x: 0, y: 0, width: 470, height: 150))
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 12)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.string = design.customPhrases.joined(separator: "\n")
        tv.delegate = self
        tv.minSize = CGSize(width: 0, height: 150)
        tv.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = CGSize(width: 470, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = tv
        phrasesView = tv
        col.addArrangedSubview(scroll)
        let tryButton = NSButton(title: "Think something now", target: self, action: #selector(thinkNow))
        col.addArrangedSubview(tryButton)
        return col
    }

    @objc private func packToggled(_ box: NSButton) {
        design.packs = ThoughtPack.allCases.filter { packBoxes[$0]?.state == .on }
        changed()
    }

    @objc private func thinkNow() {
        preview.spider.thinkSomething()
    }

    private func buildGaitTab() -> NSView {
        let col = column()
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(header("Walking style"))
        stylePopup = NSPopUpButton()
        for s in GaitPreference.allCases { stylePopup.addItem(withTitle: s.label) }
        stylePopup.target = self
        stylePopup.action = #selector(stylePicked(_:))
        row.addArrangedSubview(stylePopup)
        col.addArrangedSubview(row)
        col.addArrangedSubview(slider("Pace", low: "Ambling", high: "Brisk",
                                      get: { self.design.gait.pace }, set: { self.design.gait.pace = $0 }))
        col.addArrangedSubview(slider("Stride", low: "Short steps", high: "Long steps",
                                      get: { self.design.gait.stride }, set: { self.design.gait.stride = $0 }))
        col.addArrangedSubview(slider("Bounce", low: "Gliding", high: "Bobbing",
                                      get: { self.design.gait.bounce }, set: { self.design.gait.bounce = $0 }))
        col.addArrangedSubview(slider("Stance", low: "Low & flat", high: "On tiptoe",
                                      get: { self.design.gait.stance }, set: { self.design.gait.stance = $0 }))
        return col
    }

    private func buildHabitsTab() -> NSView {
        let col = column()
        let note = NSTextField(wrappingLabelWithString: "How often it gets up to each thing on its own. All the way down, it never does; in the middle, as often as it usually would; all the way up, every chance it gets.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        note.widthAnchor.constraint(equalToConstant: 470).isActive = true
        col.addArrangedSubview(note)
        for (group, dials) in Habits.groups {
            col.addArrangedSubview(header(group))
            for (title, key) in dials {
                col.addArrangedSubview(slider(title, low: "Never", high: "All the time",
                                              get: { self.design.habits[keyPath: key] },
                                              set: { self.design.habits[keyPath: key] = $0 }))
            }
        }
        return col
    }

    // MARK: Changes

    private func refreshGrids() {
        for g in grids {
            if g.tab == currentTab { g.refresh() } else { dirtyTabs.insert(g.tab) }
        }
    }

    private func syncControls() {
        nameField.stringValue = design.name
        for (s, get) in sliders { s.doubleValue = Double(get()) }
        let presetIdx = Personality.presets.firstIndex { $0.p == design.personality }
        presetPopup.selectItem(at: presetIdx.map { $0 + 1 } ?? 0)
        stylePopup.selectItem(at: GaitPreference.allCases.firstIndex(of: design.gait.style) ?? 0)
        sizeSlider.doubleValue = Double(scale)
        for sync in syncers { sync() }
        for (pack, box) in packBoxes { box.state = design.packs.contains(pack) ? .on : .off }
        if let tv = phrasesView, tv.string != design.customPhrases.joined(separator: "\n"), !tv.isFieldEditor {
            if design.customPhrases.joined(separator: "\n") != tv.string.split(separator: "\n").map({ String($0).trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }).joined(separator: "\n") {
                tv.string = design.customPhrases.joined(separator: "\n")
            }
        }
        refreshGrids()
    }

    private func changed() {
        preview.spider.apply(design: design)
        onChange?(design)
        syncControls()
    }

    @objc private func sliderMoved(_ s: NSSlider) {
        sliderSetters[ObjectIdentifier(s)]?(CGFloat(s.doubleValue))
        preview.spider.apply(design: design)
        onChange?(design)
        let presetIdx = Personality.presets.firstIndex { $0.p == design.personality }
        presetPopup.selectItem(at: presetIdx.map { $0 + 1 } ?? 0)
        // The thumbnails follow once the slider comes to rest, not on
        // every tick of the drag.
        gridRefreshTimer?.invalidate()
        gridRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.refreshGrids()
        }
    }
    private var gridRefreshTimer: Timer?

    @objc private func sizeMoved(_ s: NSSlider) {
        scale = CGFloat(s.doubleValue)
        onScale?(scale)
    }

    @objc private func presetPicked(_ p: NSPopUpButton) {
        let i = p.indexOfSelectedItem - 1
        guard i >= 0, i < Personality.presets.count else { return }
        design.personality = Personality.presets[i].p
        changed()
    }

    @objc private func stylePicked(_ p: NSPopUpButton) {
        design.gait.style = GaitPreference.allCases[max(0, p.indexOfSelectedItem)]
        changed()
    }

    @objc private func showPose(_ item: NSMenuItem) {
        guard let key = item.representedObject as? String, !key.isEmpty else { return }
        preview.show(key)
    }

    @objc private func randomName() {
        design.name = SpiderDesign.randomNames.randomElement()!
        changed()
    }

    @objc private func randomize() {
        design = SpiderDesign.random()
        changed()
        preview.spider.celebrate()
    }

    @objc private func resetDesign() {
        design = SpiderDesign()
        changed()
    }

    @objc private func close() {
        window.close()
    }

    func controlTextDidChange(_ obj: Notification) {
        design.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        preview.spider.apply(design: design)
        onChange?(design)
    }
}
