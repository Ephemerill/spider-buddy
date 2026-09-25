import AppKit

// MARK: - The tank's window

/// The habitat as a window: a terrarium with a lid along the top (where
/// its buttons are), a dark frame round the glass and a base under it,
/// and — while decorating — a panel of scenery and furniture to the side.
final class HabitatController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    let window: NSWindow
    let scene = HabitatSceneView(frame: CGRect(x: 0, y: 0, width: 860, height: 516))
    private let root = HabitatRootView()
    private let panel = DecorPanel()
    private let titleView = HabitatTitleView()
    private let decorateButton = HabitatButton(title: "Decorate", symbol: "paintbrush.pointed")
    private let feedButton = HabitatButton(title: "Feed", symbol: "fork.knife", menu: true)
    private let letOutButton = HabitatButton(title: "Let Out", symbol: "door.left.hand.open")

    /// The user asked for it to come out (the Let Out button, or the
    /// window's close button).
    var onLetOut: (() -> Void)?
    var onFeed: ((PreyKind) -> Void)?
    /// Whether another creature may be let loose now.
    var canFeed: () -> Bool = { true }

    private(set) var decorating = false
    private var undoStack: [Habitat] = []
    private var redoStack: [Habitat] = []
    private var name: String

    static let tankWidthKey = "habitatTankWidth"
    private var tankWidth: CGFloat {
        didSet { root.tankWidth = tankWidth }
    }

    init(spiderName: String) {
        name = spiderName
        let saved = CGFloat(UserDefaults.standard.double(forKey: HabitatController.tankWidthKey))
        tankWidth = saved > 400 ? saved : 880
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 880, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = HabitatController.title(for: spiderName)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.1, alpha: 1)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone]
        window.tabbingMode = .disallowed
        window.delegate = self
        root.tankWidth = tankWidth
        window.contentView = root
        root.addSubview(scene)
        root.addSubview(panel)
        root.scene = scene
        root.panel = panel
        panel.isHidden = true

        let toolbar = NSToolbar(identifier: "habitat")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        if #available(macOS 13.0, *) { toolbar.centeredItemIdentifiers = [.habitatTitle] }
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        titleView.set(title: HabitatController.title(for: spiderName), status: nil)
        decorateButton.target = self
        decorateButton.action = #selector(toggleDecorate)
        decorateButton.toolTip = "Change the scenery and move the furniture about"
        feedButton.target = self
        feedButton.action = #selector(showFeedMenu)
        feedButton.toolTip = "Let something loose in the tank for it to hunt"
        letOutButton.target = self
        letOutButton.action = #selector(letOut)
        letOutButton.toolTip = "Close the habitat — it drops back onto your desktop"

        scene.onEdit = { [weak self] before, after in self?.edited(from: before, to: after) }
        scene.onSelect = { [weak self] _ in self?.panel.refresh() }
        scene.onCommand = { [weak self] c in
            switch c {
            case .undo: self?.undo()
            case .redo: self?.redo()
            case .done: if self?.decorating == true { self?.toggleDecorate() }
            }
        }
        panel.controller = self
        scene.setHabitat(Habitat.load())
        panel.build()
        window.setContentSize(size(forTank: tankWidth))
        window.minSize = size(forTank: HabitatController.minTank)
        root.needsLayout = true
    }

    static func title(for name: String) -> String {
        "\(name.isEmpty ? "Your Spider" : name)’s Habitat"
    }

    func rename(_ spiderName: String) {
        name = spiderName
        window.title = HabitatController.title(for: spiderName)
        titleView.set(title: window.title, status: titleView.status)
    }

    /// A few words under the title, or none.
    func setStatus(_ s: String?) {
        titleView.set(title: window.title, status: s)
    }

    // MARK: Sizes

    static let minTank: CGFloat = 620
    static let sidebarWidth: CGFloat = 300

    /// The height of the lid: the title bar and toolbar, which the content
    /// runs up under.
    private var lidHeight: CGFloat {
        let h = window.frame.height - window.contentLayoutRect.height
        return h > 20 ? h : 52
    }

    /// The whole window for a tank this wide.
    func size(forTank w: CGFloat) -> CGSize {
        let sceneW = w - HabitatRootView.rim * 2
        let h = HabitatRootView.base + sceneW * HabitatLayout.aspect + HabitatRootView.topRim + lidHeight
        return CGSize(width: w + (decorating ? HabitatController.sidebarWidth : 0), height: h.rounded())
    }

    /// The window frame that puts the tank's glass at `sceneOrigin` on
    /// the screen, for a tank this wide.
    func frame(forTank w: CGFloat, sceneOrigin o: CGPoint) -> CGRect {
        let s = size(forTank: w)
        return CGRect(x: o.x - HabitatRootView.rim, y: o.y - HabitatRootView.base, width: s.width, height: s.height)
    }

    /// Where the scene's glass would be for a window frame.
    func sceneRect(forFrame f: CGRect) -> CGRect {
        let w = tankWidth - HabitatRootView.rim * 2
        return CGRect(x: f.minX + HabitatRootView.rim, y: f.minY + HabitatRootView.base, width: w, height: w * HabitatLayout.aspect)
    }

    var tankSize: CGSize { size(forTank: tankWidth) }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // The tank keeps its shape: height follows width.
        let extra = decorating ? HabitatController.sidebarWidth : 0
        let fromWidth = frameSize.width - extra
        let fromHeight = (frameSize.height - HabitatRootView.base - HabitatRootView.topRim - lidHeight) / HabitatLayout.aspect + HabitatRootView.rim * 2
        // Whichever edge is being dragged more.
        let w = abs(fromWidth - tankWidth) >= abs(fromHeight - tankWidth) ? fromWidth : fromHeight
        let limit = (sender.screen?.visibleFrame.width ?? 2000) - extra
        tankWidth = min(max(w, HabitatController.minTank), limit).rounded()
        return size(forTank: tankWidth)
    }

    func windowDidResize(_ notification: Notification) {
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        UserDefaults.standard.set(Double(tankWidth), forKey: HabitatController.tankWidthKey)
    }

    func windowDidMove(_ notification: Notification) {
        scene.syncToScreen()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        scene.setAnimating(window.occlusionState.contains(.visible))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // The red button lets it out, the same as the Let Out button: the
        // window goes when the spider has dropped out of it.
        onLetOut?()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {}

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .habitatTitle, .flexibleSpace, .habitatFeed, .habitatDecorate, .habitatLetOut]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case .habitatTitle: item.view = titleView
        case .habitatFeed: item.view = feedButton; item.label = "Feed"
        case .habitatDecorate: item.view = decorateButton; item.label = "Decorate"
        case .habitatLetOut: item.view = letOutButton; item.label = "Let Out"
        default: return nil
        }
        return item
    }

    // MARK: Actions

    @objc func toggleDecorate() {
        decorating.toggle()
        decorateButton.isOn = decorating
        decorateButton.set(title: decorating ? "Done" : "Decorate", symbol: decorating ? "checkmark" : "paintbrush.pointed")
        scene.editing = decorating
        panel.refresh()
        // The window grows to the right for the panel (or to the left if
        // there is no room), and the tank stays exactly where it is.
        var f = window.frame
        let dw = decorating ? HabitatController.sidebarWidth : -HabitatController.sidebarWidth
        f.size.width += dw
        if decorating, let vis = window.screen?.visibleFrame, f.maxX > vis.maxX {
            f.origin.x = max(vis.minX, vis.maxX - f.width)
        }
        panel.isHidden = false
        root.decorating = decorating
        window.minSize = size(forTank: HabitatController.minTank)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(f, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.isHidden = !self.decorating
            self.scene.syncToScreen()
            if self.decorating { self.window.makeFirstResponder(self.scene) }
        })
    }

    @objc private func showFeedMenu() {
        let menu = NSMenu()
        for kind in PreyKind.allCases {
            let item = NSMenuItem(title: "A \(kind.label)", action: #selector(feed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.isEnabled = canFeed()
            menu.addItem(item)
        }
        if !canFeed() {
            menu.addItem(.separator())
            let full = NSMenuItem(title: "That’s plenty loose for now", action: nil, keyEquivalent: "")
            full.isEnabled = false
            menu.addItem(full)
        }
        menu.autoenablesItems = false
        let below = feedButton.isFlipped ? feedButton.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: below), in: feedButton)
    }

    @objc private func feed(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? Int, let kind = PreyKind(rawValue: raw) else { return }
        onFeed?(kind)
    }

    @objc func letOut() { onLetOut?() }

    /// Tools only: the decorating panel at a tab.
    func debugShowTab(_ i: Int) { panel.debugShowTab(i) }

    // MARK: Editing

    /// An edit made quietly, piece by piece (a slide of the size slider),
    /// recorded once it is done.
    func noteEdit(from before: Habitat, to after: Habitat) {
        guard before != after else { return }
        edited(from: before, to: after)
    }

    private func edited(from before: Habitat, to after: Habitat) {
        undoStack.append(before)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack = []
        after.save()
        panel.refresh()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append(scene.habitat)
        scene.setHabitat(prev, fade: prev.biome != scene.habitat.biome)
        prev.save()
        panel.refresh()
    }

    func redo() {
        guard let next = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append(scene.habitat)
        scene.setHabitat(next, fade: next.biome != scene.habitat.biome)
        next.save()
        panel.refresh()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func setBiome(_ b: Biome) {
        var h = scene.habitat
        guard h.biome != b else { return }
        h.biome = b
        scene.replace(with: h, fade: true)
    }

    func loadPreset(_ p: Habitat.Preset) {
        scene.replace(with: Habitat.preset(p), fade: true)
    }

    func shuffle() {
        scene.replace(with: Habitat.surprise(), fade: true)
    }

    func clearAll() {
        var h = scene.habitat
        h.items = []
        scene.replace(with: h, fade: true)
    }
}

extension NSToolbarItem.Identifier {
    static let habitatTitle = NSToolbarItem.Identifier("habitat.title")
    static let habitatFeed = NSToolbarItem.Identifier("habitat.feed")
    static let habitatDecorate = NSToolbarItem.Identifier("habitat.decorate")
    static let habitatLetOut = NSToolbarItem.Identifier("habitat.letOut")
}

// MARK: - The frame

/// The terrarium round the glass: a lid under the toolbar, a dark frame,
/// a base with a vent in it. Lays out the scene and the decorating panel.
final class HabitatRootView: NSView {
    static let rim: CGFloat = 12
    static let topRim: CGFloat = 10
    static let base: CGFloat = 30

    var tankWidth: CGFloat = 880 { didSet { needsLayout = true; needsDisplay = true } }
    var decorating = false { didSet { needsLayout = true; needsDisplay = true } }
    weak var scene: NSView?
    weak var panel: NSView?

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    private var sceneFrame: CGRect {
        let w = tankWidth - HabitatRootView.rim * 2
        return CGRect(x: HabitatRootView.rim, y: HabitatRootView.base, width: w, height: (w * HabitatLayout.aspect).rounded())
    }

    override func layout() {
        super.layout()
        scene?.frame = sceneFrame
        let lidTop = sceneFrame.maxY + HabitatRootView.topRim
        panel?.frame = CGRect(x: tankWidth, y: 0, width: HabitatController.sidebarWidth, height: lidTop)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { HabitatArt.c(r, g, b, a) }
        let glass = sceneFrame
        let lidBottom = glass.maxY + HabitatRootView.topRim
        // The lid: brushed dark metal with a mesh.
        let lid = CGRect(x: 0, y: lidBottom, width: bounds.width, height: bounds.height - lidBottom)
        HabitatArt.linear(ctx, [c(0.2, 0.2, 0.22), c(0.13, 0.13, 0.15)], from: CGPoint(x: 0, y: lid.maxY), to: CGPoint(x: 0, y: lid.minY))
        ctx.saveGState()
        ctx.clip(to: lid)
        ctx.setStrokeColor(c(1, 1, 1, 0.035))
        ctx.setLineWidth(1)
        var x: CGFloat = -lid.height
        while x < lid.maxX {
            ctx.move(to: CGPoint(x: x, y: lid.minY)); ctx.addLine(to: CGPoint(x: x + lid.height, y: lid.maxY))
            ctx.move(to: CGPoint(x: x + lid.height, y: lid.minY)); ctx.addLine(to: CGPoint(x: x, y: lid.maxY))
            x += 5
        }
        ctx.strokePath()
        ctx.restoreGState()
        // The body of the tank.
        let body = CGRect(x: 0, y: 0, width: tankWidth, height: lidBottom)
        HabitatArt.linear(ctx, [c(0.2, 0.2, 0.22), c(0.12, 0.12, 0.13)], from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: 0))
        // A lip of light between lid and body.
        ctx.setFillColor(c(0, 0, 0, 0.5))
        ctx.fill(CGRect(x: 0, y: lidBottom - 1, width: bounds.width, height: 1))
        ctx.setFillColor(c(1, 1, 1, 0.07))
        ctx.fill(CGRect(x: 0, y: lidBottom, width: bounds.width, height: 1))
        // The base: a slightly lighter band with a row of vent slots.
        let base = CGRect(x: 0, y: 0, width: tankWidth, height: HabitatRootView.base - 4)
        HabitatArt.linear(ctx, [c(0.17, 0.17, 0.19), c(0.1, 0.1, 0.11)], from: CGPoint(x: 0, y: base.maxY), to: CGPoint(x: 0, y: 0))
        ctx.setFillColor(c(1, 1, 1, 0.06))
        ctx.fill(CGRect(x: 0, y: base.maxY - 1, width: tankWidth, height: 1))
        let slots = 9
        let slotW: CGFloat = 16, gap: CGFloat = 6
        let total = CGFloat(slots) * slotW + CGFloat(slots - 1) * gap
        for k in 0..<slots {
            let r = CGRect(x: tankWidth / 2 - total / 2 + CGFloat(k) * (slotW + gap), y: base.midY - 2, width: slotW, height: 4)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.setFillColor(c(0, 0, 0, 0.55))
            ctx.fillPath()
            ctx.setFillColor(c(1, 1, 1, 0.05))
            ctx.fill(CGRect(x: r.minX + 1, y: r.minY - 1, width: r.width - 2, height: 1))
        }
        // The glass sits in a groove.
        let groove = glass.insetBy(dx: -3, dy: -3)
        ctx.addPath(CGPath(roundedRect: groove, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.setFillColor(c(0.03, 0.03, 0.04))
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: groove.insetBy(dx: -1, dy: -1), cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.setStrokeColor(c(1, 1, 1, 0.06))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }
}

// MARK: - Buttons

/// A clear, roomy toolbar button: an icon and a word, on a soft pill that
/// lights up under the pointer and fills with the accent while it is on.
final class HabitatButton: NSButton {
    var isOn = false { didSet { needsDisplay = true; updateTint() } }
    var destructive = false { didSet { updateTint() } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private let hasMenu: Bool
    private var tracking: NSTrackingArea?
    private var label = ""

    init(title: String, symbol: String, menu: Bool = false) {
        hasMenu = menu
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageLeading
        imageHugsTitle = true
        font = .systemFont(ofSize: 12.5, weight: .semibold)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        set(title: title, symbol: symbol)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(title t: String, symbol s: String) {
        label = t
        let img = NSImage(systemSymbolName: s, accessibilityDescription: t) ?? NSImage(systemSymbolName: "circle", accessibilityDescription: t)
        image = img?.withSymbolConfiguration(.init(pointSize: 12.5, weight: .semibold))
        setAccessibilityLabel(t)
        updateTint()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let s = super.intrinsicContentSize
        return NSSize(width: s.width + 24, height: 30)
    }

    private func updateTint() {
        let col: NSColor = isOn ? .white : (destructive ? .systemRed : NSColor(white: 1, alpha: 0.9))
        contentTintColor = col
        // A menu button carries a small chevron after its word.
        attributedTitle = NSAttributedString(string: " " + label + (hasMenu ? "  ▾" : ""), attributes: [
            .font: font ?? .systemFont(ofSize: 12.5),
            .foregroundColor: col,
        ])
    }

    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.4 } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        super.mouseDown(with: event)
        pressed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        if isOn {
            NSColor.controlAccentColor.withAlphaComponent(pressed ? 0.8 : (hovering ? 1 : 0.92)).setFill()
            path.fill()
        } else {
            NSColor(white: 1, alpha: pressed ? 0.2 : (hovering ? 0.14 : 0.08)).setFill()
            path.fill()
            NSColor(white: 1, alpha: 0.1).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        super.draw(dirtyRect)
    }
}

/// The name in the middle of the lid, and a line of what is happening under it.
final class HabitatTitleView: NSView {
    private let title = NSTextField(labelWithString: "")
    private let sub = NSTextField(labelWithString: "")
    private(set) var status: String?

    init() {
        super.init(frame: .zero)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = NSColor(white: 1, alpha: 0.92)
        title.alignment = .center
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = NSColor(white: 1, alpha: 0.55)
        sub.alignment = .center
        let stack = NSStackView(views: [title, sub])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            heightAnchor.constraint(equalToConstant: 34),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    func set(title t: String, status s: String?) {
        title.stringValue = t
        status = s
        sub.stringValue = s ?? ""
        sub.isHidden = s == nil
    }
}

// MARK: - The decorating panel

/// Down the side while decorating: the scenery, things to add, ready-made
/// layouts, and — when something in the tank is picked — what can be done
/// to it.
final class DecorPanel: NSView {
    weak var controller: HabitatController?
    private let tabs = NSSegmentedControl(labels: ["Scenery", "Add", "Layouts"], trackingMode: .selectOne, target: nil, action: nil)
    private let scroll = NSScrollView()
    private var pages: [NSView] = []
    private var biomeTiles: [TileButton] = []
    private let undoButton = HabitatIconButton(symbol: "arrow.uturn.backward", tip: "Undo (⌘Z)")
    private let redoButton = HabitatIconButton(symbol: "arrow.uturn.forward", tip: "Redo (⇧⌘Z)")
    private let inspector = NSStackView()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let selName = NSTextField(labelWithString: "")
    private let selKind = NSTextField(labelWithString: "")
    private let selThumb = NSImageView()
    private let sizeSlider = NSSlider(value: 1, minValue: 0.35, maxValue: 3, target: nil, action: nil)
    private let sizeValue = NSTextField(labelWithString: "")
    private let layerButton = InspectorButton(title: "In Front", symbol: "square.2.layers.3d.top.filled")
    private let flipButton = InspectorButton(title: "Flip", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right")
    private let copyButton = InspectorButton(title: "Duplicate", symbol: "plus.square.on.square")
    private let removeButton = InspectorButton(title: "Remove", symbol: "trash")
    private var sizeEditBefore: Habitat?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.13, alpha: 1).setFill()
        bounds.fill()
        NSColor(white: 0, alpha: 0.6).setFill()
        CGRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        NSColor(white: 1, alpha: 0.05).setFill()
        CGRect(x: 1, y: 0, width: 1, height: bounds.height).fill()
    }

    func build() {
        let pad: CGFloat = 16
        let inner = HabitatController.sidebarWidth - pad * 2

        tabs.segmentDistribution = .fillEqually
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Decorate")
        heading.font = .systemFont(ofSize: 15, weight: .bold)
        heading.textColor = .white
        undoButton.target = controller
        undoButton.action = #selector(HabitatController.undoAction)
        redoButton.target = controller
        redoButton.action = #selector(HabitatController.redoAction)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let head = NSStackView(views: [heading, spacer, undoButton, redoButton])
        head.spacing = 6

        pages = [scenePage(width: inner), addPage(width: inner), layoutPage(width: inner)]
        let doc = FlippedStack()
        doc.orientation = .vertical
        doc.alignment = .leading
        doc.spacing = 0
        doc.translatesAutoresizingMaskIntoConstraints = false
        for p in pages { doc.addArrangedSubview(p) }
        scroll.documentView = doc
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        doc.widthAnchor.constraint(equalToConstant: inner).isActive = true
        doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor).isActive = true
        doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor).isActive = true

        buildInspector(width: inner)

        let col = NSStackView(views: [head, tabs, scroll, inspector])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 12
        col.translatesAutoresizingMaskIntoConstraints = false
        addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            col.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
            col.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            col.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            head.widthAnchor.constraint(equalToConstant: inner),
            tabs.widthAnchor.constraint(equalToConstant: inner),
            scroll.widthAnchor.constraint(equalToConstant: inner),
            inspector.widthAnchor.constraint(equalToConstant: inner),
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        showPage(0)
        refresh()
    }

    private func sectionLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s.uppercased())
        l.font = .systemFont(ofSize: 10.5, weight: .semibold)
        l.textColor = NSColor(white: 1, alpha: 0.5)
        return l
    }

    private func note(_ s: String, width: CGFloat) -> NSTextField {
        let n = NSTextField(wrappingLabelWithString: s)
        n.font = .systemFont(ofSize: 11.5)
        n.textColor = NSColor(white: 1, alpha: 0.6)
        n.translatesAutoresizingMaskIntoConstraints = false
        n.widthAnchor.constraint(equalToConstant: width).isActive = true
        return n
    }

    /// Tiles in rows of `columns`.
    private func grid(_ tiles: [NSView], columns: Int, width: CGFloat, spacing: CGFloat = 8) -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = spacing
        let w = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var i = 0
        while i < tiles.count {
            let row = NSStackView()
            row.spacing = spacing
            for t in tiles[i..<min(i + columns, tiles.count)] {
                t.translatesAutoresizingMaskIntoConstraints = false
                t.widthAnchor.constraint(equalToConstant: w).isActive = true
                row.addArrangedSubview(t)
            }
            rows.addArrangedSubview(row)
            i += columns
        }
        return rows
    }

    private func page(_ views: [NSView]) -> NSStackView {
        let p = NSStackView(views: views)
        p.orientation = .vertical
        p.alignment = .leading
        p.spacing = 10
        p.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 12, right: 0)
        return p
    }

    private func scenePage(width: CGFloat) -> NSView {
        let tileW = (width - 8) / 2
        let thumb = CGSize(width: tileW - 12, height: ((tileW - 12) * HabitatLayout.aspect).rounded())
        biomeTiles = Biome.allCases.map { b in
            let t = TileButton(image: HabitatArt.biomeThumbnail(b, size: thumb), title: b.label, subtitle: b.blurb, imageSize: thumb)
            t.onClick = { [weak self] in self?.controller?.setBiome(b) }
            return t
        }
        return page([note("The backdrop behind the glass. Everything in it moves — clouds, leaves, snow, fireflies.", width: width),
                     grid(biomeTiles, columns: 2, width: width)])
    }

    private func addPage(width: CGFloat) -> NSView {
        func tiles(_ kinds: [HabitatItemKind]) -> [NSView] {
            kinds.map { k in
                let t = TileButton(image: HabitatArt.thumbnail(k, side: 56), title: k.label, subtitle: nil, imageSize: CGSize(width: 56, height: 56))
                t.onClick = { [weak self] in self?.controller?.scene.add(k) }
                t.toolTip = "Add \(k.label.lowercased())"
                return t
            }
        }
        return page([note("Click something to put it in the tank, then drag it wherever you like.", width: width),
                     sectionLabel("Perches — it can climb these"),
                     grid(tiles(HabitatItemKind.allCases.filter(\.climbable)), columns: 3, width: width),
                     sectionLabel("Plants & details"),
                     grid(tiles(HabitatItemKind.allCases.filter { !$0.climbable }), columns: 3, width: width)])
    }

    private func layoutPage(width: CGFloat) -> NSView {
        let tileW = (width - 8) / 2
        let thumb = CGSize(width: tileW - 12, height: ((tileW - 12) * HabitatLayout.aspect).rounded())
        let tiles = Habitat.Preset.allCases.map { p -> NSView in
            let t = TileButton(image: HabitatArt.habitatThumbnail(Habitat.preset(p), size: thumb), title: p.label, subtitle: nil, imageSize: thumb)
            t.onClick = { [weak self] in self?.controller?.loadPreset(p) }
            return t
        }
        let shuffle = HabitatButton(title: "Surprise Me", symbol: "dice")
        shuffle.target = self
        shuffle.action = #selector(shuffleTapped)
        let clear = HabitatButton(title: "Clear All", symbol: "trash")
        clear.destructive = true
        clear.target = self
        clear.action = #selector(clearTapped)
        let row = NSStackView(views: [shuffle, clear])
        row.distribution = .fillEqually
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return page([note("Start from a ready-made tank. You can undo it if you liked yours better.", width: width),
                     grid(tiles, columns: 2, width: width), row])
    }

    private func buildInspector(width: CGFloat) {
        inspector.orientation = .vertical
        inspector.alignment = .leading
        inspector.spacing = 8
        inspector.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        inspector.wantsLayer = true
        inspector.layer?.backgroundColor = CGColor(gray: 1, alpha: 0.06)
        inspector.layer?.cornerRadius = 12
        inspector.layer?.borderColor = CGColor(gray: 1, alpha: 0.08)
        inspector.layer?.borderWidth = 1

        selThumb.imageScaling = .scaleProportionallyUpOrDown
        selThumb.translatesAutoresizingMaskIntoConstraints = false
        selThumb.widthAnchor.constraint(equalToConstant: 30).isActive = true
        selThumb.heightAnchor.constraint(equalToConstant: 30).isActive = true
        selName.font = .systemFont(ofSize: 13, weight: .semibold)
        selName.textColor = .white
        selKind.font = .systemFont(ofSize: 11)
        selKind.textColor = NSColor(white: 1, alpha: 0.55)
        let names = NSStackView(views: [selName, selKind])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = 1
        let top = NSStackView(views: [selThumb, names])
        top.spacing = 10

        let sizeLabel = NSTextField(labelWithString: "Size")
        sizeLabel.font = .systemFont(ofSize: 12)
        sizeLabel.textColor = NSColor(white: 1, alpha: 0.75)
        sizeValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        sizeValue.textColor = NSColor(white: 1, alpha: 0.55)
        sizeSlider.controlSize = .small
        sizeSlider.isContinuous = true
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let sizeRow = NSStackView(views: [sizeLabel, sizeSlider, sizeValue])
        sizeRow.spacing = 8
        sizeRow.translatesAutoresizingMaskIntoConstraints = false
        sizeRow.widthAnchor.constraint(equalToConstant: width - 24).isActive = true
        sizeValue.widthAnchor.constraint(equalToConstant: 38).isActive = true

        flipButton.target = self
        flipButton.action = #selector(flipTapped)
        flipButton.toolTip = "Mirror it (F)"
        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.toolTip = "Another one just like it (⌘D)"
        layerButton.target = self
        layerButton.action = #selector(layerTapped)
        removeButton.destructive = true
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.toolTip = "Take it out of the tank (⌫)"
        let r1 = NSStackView(views: [flipButton, copyButton, layerButton, removeButton])
        r1.distribution = .fillEqually
        r1.spacing = 6
        r1.translatesAutoresizingMaskIntoConstraints = false
        r1.widthAnchor.constraint(equalToConstant: width - 24).isActive = true
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = NSColor(white: 1, alpha: 0.55)
        hint.stringValue = "Click anything in the tank to move it. Drag a corner to resize it. ⌘Z undoes."
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.widthAnchor.constraint(equalToConstant: width - 24).isActive = true
        for v in [top, sizeRow, r1, hint] as [NSView] { inspector.addArrangedSubview(v) }
    }

    @objc private func tabChanged() { showPage(tabs.selectedSegment) }

    /// Tools only: shows a tab.
    func debugShowTab(_ i: Int) {
        tabs.selectedSegment = i
        showPage(i)
    }

    private func showPage(_ i: Int) {
        for (k, p) in pages.enumerated() { p.isHidden = k != i }
        scroll.documentView?.scroll(.zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Back in step with the tank.
    func refresh() {
        guard let c = controller else { return }
        let h = c.scene.habitat
        for (b, t) in zip(Biome.allCases, biomeTiles) { t.selected = b == h.biome }
        undoButton.isEnabled = c.canUndo
        redoButton.isEnabled = c.canRedo
        let item = c.scene.selected.flatMap { id in h.items.first { $0.id == id } }
        for v in inspector.arrangedSubviews where v !== hint { v.isHidden = item == nil }
        hint.isHidden = item != nil
        guard let it = item else { return }
        selName.stringValue = it.kind.label
        selKind.stringValue = it.kind.climbable ? "A perch — it can climb this" : "Scenery"
        selThumb.image = HabitatArt.thumbnail(it.kind, side: 30)
        let k = it.w / it.kind.defaultSize.width
        if abs(sizeSlider.doubleValue - Double(k)) > 0.005 { sizeSlider.doubleValue = Double(k) }
        sizeValue.stringValue = "\(Int((k * 100).rounded()))%"
        layerButton.isEnabled = it.kind.canGoInFront
        layerButton.set(title: it.inFront ? "In Front" : "Behind", symbol: it.inFront ? "square.2.layers.3d.top.filled" : "square.2.layers.3d.bottom.filled")
        layerButton.toolTip = it.kind.canGoInFront
            ? (it.inFront ? "In front of the spider — click to put it behind" : "Behind the spider — click to put it in front, so the spider walks behind it")
            : "It climbs this, so it always stands behind the spider"
    }

    @objc private func sizeChanged() {
        guard let c = controller else { return }
        let k = CGFloat(sizeSlider.doubleValue)
        // One edit for the whole slide, however many steps it takes.
        if sizeEditBefore == nil { sizeEditBefore = c.scene.habitat }
        c.scene.updateSelected(silently: true) { it in
            let base = it.kind.defaultSize
            it.w = base.width * k
            it.h = base.height * k
        }
        sizeValue.stringValue = "\(Int((k * 100).rounded()))%"
        if NSApp.currentEvent?.type != .leftMouseDragged, let before = sizeEditBefore {
            sizeEditBefore = nil
            c.noteEdit(from: before, to: c.scene.habitat)
        }
    }

    @objc private func flipTapped() { controller?.scene.updateSelected { $0.flipped.toggle() } }
    @objc private func copyTapped() { controller?.scene.duplicateSelected() }
    @objc private func removeTapped() { controller?.scene.removeSelected() }
    @objc private func layerTapped() { controller?.scene.updateSelected { $0.front.toggle() } }
    @objc private func shuffleTapped() { controller?.shuffle() }
    @objc private func clearTapped() { controller?.clearAll() }
}

extension HabitatController {
    @objc func undoAction() { undo() }
    @objc func redoAction() { redo() }
}

final class FlippedStack: NSStackView {
    override var isFlipped: Bool { true }
}

/// One of the row of things to do to the chosen piece: an icon over a
/// short word.
final class InspectorButton: NSButton {
    var destructive = false { didSet { update() } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var label = ""

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageAbove
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 46).isActive = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        set(title: title, symbol: symbol)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(title t: String, symbol s: String) {
        label = t
        image = NSImage(systemSymbolName: s, accessibilityDescription: t)?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        setAccessibilityLabel(t)
        update()
    }

    private func update() {
        let col: NSColor = destructive ? .systemRed : NSColor(white: 1, alpha: 0.88)
        contentTintColor = col
        attributedTitle = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .medium), .foregroundColor: col])
    }

    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.35 } }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        NSColor(white: 1, alpha: isHighlighted ? 0.18 : (hovering && isEnabled ? 0.12 : 0.06)).setFill()
        path.fill()
        super.draw(dirtyRect)
    }
}

/// A small round icon-only button (undo, redo).
final class HabitatIconButton: NSButton {
    init(symbol: String, tip: String) {
        super.init(frame: .zero)
        isBordered = false
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        imagePosition = .imageOnly
        contentTintColor = NSColor(white: 1, alpha: 0.85)
        toolTip = tip
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.35 } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.08).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        super.draw(dirtyRect)
    }
}

/// A picture with a name under it: a biome, a thing to add, a layout.
final class TileButton: NSView {
    var onClick: (() -> Void)?
    var selected = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let sub = NSTextField(wrappingLabelWithString: "")

    init(image: NSImage, title: String, subtitle: String?, imageSize: CGSize) {
        super.init(frame: .zero)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = subtitle == nil && imageSize.width < 80 ? 0 : 6
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = title
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = NSColor(white: 1, alpha: 0.9)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        sub.stringValue = subtitle ?? ""
        sub.font = .systemFont(ofSize: 10)
        sub.textColor = NSColor(white: 1, alpha: 0.5)
        sub.alignment = .center
        sub.isHidden = subtitle == nil
        sub.maximumNumberOfLines = 2
        let stack = NSStackView(views: [imageView, label, sub])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            imageView.widthAnchor.constraint(equalToConstant: imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: imageSize.height),
            label.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            sub.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
        NSColor(white: 1, alpha: pressed ? 0.16 : (hovering ? 0.11 : 0.05)).setFill()
        path.fill()
        if selected {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        } else {
            NSColor(white: 1, alpha: 0.07).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}
