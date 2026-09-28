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
    let titleView = HabitatTitleView()
    private let decorateButton = HabitatButton(title: "Decorate", symbol: "paintbrush.pointed")
    private let feedButton = HabitatButton(title: "Feed", symbol: "fork.knife", menu: true)
    private let letOutButton = HabitatButton(title: "Let Out", symbol: "door.left.hand.open")
    private let overviewButton = HabitatButton(title: "Overview", symbol: "map")
    private let weatherButton = HabitatButton(title: "Weather", symbol: "cloud.sun", menu: true)

    /// The tank's weather: what it is doing, and what comes next (see
    /// Weather.swift).
    let weather: WeatherClock
    /// Whether the weather outside can be known (the app is allowed to look
    /// it up), turning that on, and what it is out there, for the controls.
    var outsideAvailable: () -> Bool = { false }
    var enableOutside: (() -> Void)?
    var outsideSummary: () -> String? = { nil }
    /// The kind showing on the button, and what the title last said about
    /// the weather (to take it away again).
    private var shownKind: WeatherKind?
    private var weatherNotice: String?
    private var weatherCheckedAt: CFTimeInterval = 0

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

    /// The size of the glass, kept from one time to the next.
    static let glassKey = "habitatGlass"
    /// (How wide the whole tank was, when its glass kept one shape: read
    /// once, for the glass's first size.)
    static let tankWidthKey = "habitatTankWidth"
    /// The glass: how much of the world the window shows. Any shape, from
    /// small up to the whole world (or the screen, whichever is less).
    private var glass: CGSize {
        didSet { root.glass = glass }
    }

    init(spiderName: String) {
        name = spiderName
        if let a = UserDefaults.standard.array(forKey: HabitatController.glassKey) as? [Double], a.count == 2 {
            glass = CGSize(width: CGFloat(a[0]), height: CGFloat(a[1]))
        } else {
            let saved = CGFloat(UserDefaults.standard.double(forKey: HabitatController.tankWidthKey))
            let w = (saved > 400 ? saved : 880) - HabitatRootView.rim * 2
            glass = CGSize(width: w, height: (w * HabitatLayout.aspect).rounded())
        }
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 880, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        weather = WeatherClock(biome: Habitat.load().biome)
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
        root.glass = glass
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

        titleView.set(title: window.title, status: nil)
        titleView.onRename = { [weak self] typed in self?.named(typed) }
        titleView.onEndEditing = { [weak self] in
            guard let self else { return }
            self.window.makeFirstResponder(self.scene)
        }
        decorateButton.target = self
        decorateButton.action = #selector(toggleDecorate)
        decorateButton.toolTip = "Change the scenery and move the furniture about"
        feedButton.target = self
        feedButton.action = #selector(showFeedMenu)
        feedButton.toolTip = "Let something loose in the tank for it to hunt"
        letOutButton.target = self
        letOutButton.action = #selector(letOut)
        letOutButton.toolTip = "Close the habitat — it drops back onto your desktop"
        overviewButton.target = self
        overviewButton.action = #selector(toggleOverview)
        overviewButton.toolTip = "See the whole habitat at once — and go anywhere in it"
        weatherButton.target = self
        weatherButton.action = #selector(showWeatherMenu)
        weatherButton.toolTip = "Rain, snow, wind, sun and more — change what the weather does in the tank"
        weather.onChange = { [weak self] in self?.panel.refreshWeather() }

        scene.onEdit = { [weak self] before, after in self?.edited(from: before, to: after) }
        scene.onSelect = { [weak self] _ in self?.panel.refresh() }
        scene.onCommand = { [weak self] c in
            switch c {
            case .undo: self?.undo()
            case .redo: self?.redo()
            case .done: if self?.decorating == true { self?.toggleDecorate() }
            }
        }
        scene.onOverviewChange = { [weak self] on in self?.overviewButton.isOn = on }
        scene.spiderName = spiderName
        panel.controller = self
        scene.setHabitat(Habitat.load())
        if let o = HabitatCamera.saved() { scene.camera.jump(to: o) }
        panel.build()
        glass = fitted(glass)
        window.setContentSize(size(forGlass: glass))
        window.minSize = size(forGlass: HabitatController.minGlass)
        root.needsLayout = true
    }

    static let nameKey = "habitatName"

    /// What the user called the tank, if they gave it a name of its own.
    static var customName: String? {
        let s = UserDefaults.standard.string(forKey: nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    /// Named after its spider.
    static func defaultTitle(for name: String) -> String {
        "\(name.isEmpty ? "Your Spider" : name)’s Habitat"
    }

    /// The tank's own name, or else its spider's.
    static func title(for name: String) -> String {
        customName ?? defaultTitle(for: name)
    }

    func rename(_ spiderName: String) {
        name = spiderName
        scene.spiderName = spiderName
        window.title = HabitatController.title(for: spiderName)
        titleView.set(title: window.title, status: titleView.status)
    }

    /// Typed into the title: a name of its own, or — left empty, or the
    /// same as the spider's — back to being named after the spider.
    private func named(_ typed: String) {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == HabitatController.defaultTitle(for: name) {
            UserDefaults.standard.removeObject(forKey: HabitatController.nameKey)
        } else {
            UserDefaults.standard.set(t, forKey: HabitatController.nameKey)
        }
        rename(name)
    }

    /// A few words under the title, or none.
    func setStatus(_ s: String?) {
        titleView.set(title: window.title, status: s)
    }

    // MARK: Sizes

    /// The smallest the glass goes.
    static let minGlass = CGSize(width: 596, height: 300)
    static let sidebarWidth: CGFloat = 300

    /// The height of the lid: the title bar and toolbar, which the content
    /// runs up under.
    private var lidHeight: CGFloat {
        let h = window.frame.height - window.contentLayoutRect.height
        return h > 20 ? h : 52
    }

    /// The whole window for a glass this size.
    func size(forGlass g: CGSize) -> CGSize {
        CGSize(width: g.width + HabitatRootView.rim * 2 + (decorating ? HabitatController.sidebarWidth : 0),
               height: (HabitatRootView.base + g.height + HabitatRootView.topRim + lidHeight).rounded())
    }

    var tankSize: CGSize { size(forGlass: glass) }

    /// A glass no smaller than the least, and no bigger than the world or
    /// than would fit on the screen.
    private func fitted(_ g: CGSize, screen: NSScreen? = nil) -> CGSize {
        let world = scene.habitat.size
        let vis = (screen ?? window.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1400, height: 900)
        let extra = decorating ? HabitatController.sidebarWidth : 0
        let maxW = min(world.width, vis.width - extra - HabitatRootView.rim * 2)
        let maxH = min(world.height, vis.height - HabitatRootView.base - HabitatRootView.topRim - lidHeight)
        return CGSize(width: clamp(g.width, HabitatController.minGlass.width, max(maxW, HabitatController.minGlass.width)).rounded(),
                      height: clamp(g.height, HabitatController.minGlass.height, max(maxH, HabitatController.minGlass.height)).rounded())
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Any shape: the glass shows more or less of the world, never
        // more than there is of it.
        let extra = decorating ? HabitatController.sidebarWidth : 0
        glass = fitted(CGSize(width: frameSize.width - extra - HabitatRootView.rim * 2,
                              height: frameSize.height - HabitatRootView.base - HabitatRootView.topRim - lidHeight), screen: sender.screen)
        return size(forGlass: glass)
    }

    func windowDidResize(_ notification: Notification) {
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        UserDefaults.standard.set([Double(glass.width), Double(glass.height)], forKey: HabitatController.glassKey)
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
        [.flexibleSpace, .habitatTitle, .flexibleSpace, .habitatWeather, .habitatFeed, .habitatOverview, .habitatDecorate, .habitatLetOut]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case .habitatTitle: item.view = titleView
        case .habitatWeather: item.view = weatherButton; item.label = "Weather"
        case .habitatFeed: item.view = feedButton; item.label = "Feed"
        case .habitatOverview: item.view = overviewButton; item.label = "Overview"
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
        scene.overview?.reload()
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
        window.minSize = size(forGlass: HabitatController.minGlass)
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

    /// The whole habitat at once, small — or back to the tank.
    @objc func toggleOverview() {
        scene.showOverview(!scene.overviewOpen)
    }

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
        scene.replace(with: Habitat.preset(p, world: scene.habitat.size), fade: true)
    }

    func shuffle() {
        // Half the time in the scenery it has, half the time somewhere new.
        scene.replace(with: Habitat.surprise(world: scene.habitat.size, biome: Bool.random() ? scene.habitat.biome : nil), fade: true)
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
    static let habitatWeather = NSToolbarItem.Identifier("habitat.weather")
    static let habitatOverview = NSToolbarItem.Identifier("habitat.overview")
}

// MARK: - The weather controls

extension HabitatController {
    /// The weather now, for this frame: the tank shows it, and it is handed
    /// back for the spider to feel. `clock` is any steady time in seconds.
    func tickWeather(dt: CGFloat, clock: CGFloat) -> WeatherConditions {
        weather.biome = scene.habitat.biome
        let c = weather.conditions(clock: clock)
        scene.updateWeather(c, dt: dt)
        let now = CACurrentMediaTime()
        if now - weatherCheckedAt > 0.5 {
            weatherCheckedAt = now
            noteWeather()
        }
        return c
    }

    /// Keeps the button's picture on the weather, and says a word under
    /// the title when something new rolls in.
    private func noteWeather() {
        let k = weather.current
        guard k != shownKind else { return }
        let first = shownKind == nil
        shownKind = k
        weatherButton.set(title: "Weather", symbol: k.symbol)
        weatherButton.toolTip = "\(weather.summary()) — click to change the weather"
        panel.refreshWeather()
        guard !first else { return }
        let line = k.arriving
        if titleView.status == nil || titleView.status == weatherNotice {
            weatherNotice = line
            setStatus(line)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, self.titleView.status == line else { return }
                self.weatherNotice = nil
                self.setStatus(nil)
            }
        }
    }

    @objc func showWeatherMenu() {
        let menu = NSMenu()
        fillWeatherMenu(menu)
        let below = weatherButton.isFlipped ? weatherButton.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: below), in: weatherButton)
    }

    /// The weather's menu: what it is doing; comes and goes, like outside,
    /// or kept to one kind; something now; and the settings.
    func fillWeatherMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let s = weather.settings
        let head = NSMenuItem(title: weather.summary(), action: nil, keyEquivalent: "")
        head.isEnabled = false
        head.image = NSImage(systemSymbolName: weather.current.symbol, accessibilityDescription: nil)
        menu.addItem(head)
        menu.addItem(.separator())

        func item(_ title: String, _ sel: Selector, on: Bool = false, tag: Int = 0, tip: String? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            i.state = on ? .on : .off
            i.tag = tag
            i.toolTip = tip
            menu.addItem(i)
            return i
        }
        _ = item("Comes and Goes", #selector(weatherModeChosen(_:)), on: s.mode == .changing, tag: 0,
                 tip: "Weather rolls in now and then and clears again, from what suits the scenery")
        _ = item("Like the Weather Outside", #selector(weatherModeChosen(_:)), on: s.mode == .outside, tag: 2,
                 tip: "The weather where you are, looked up every twenty minutes (roughly, from your internet connection)")
        let always = NSMenuItem(title: "Always", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, k) in WeatherKind.allCases.enumerated() {
            let it = NSMenuItem(title: k.label, action: #selector(weatherKept(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.image = NSImage(systemSymbolName: k.symbol, accessibilityDescription: nil)
            it.state = s.mode == .always && s.always == k ? .on : .off
            sub.addItem(it)
        }
        always.submenu = sub
        always.state = s.mode == .always ? .on : .off
        menu.addItem(always)
        menu.addItem(.separator())

        let now = NSMenuItem(title: "Right Now", action: nil, keyEquivalent: "")
        let nowMenu = NSMenu()
        for (i, k) in WeatherKind.allCases.enumerated() where k != .clear {
            let it = NSMenuItem(title: k.summon, action: #selector(weatherBrought(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.image = NSImage(systemSymbolName: k.symbol, accessibilityDescription: nil)
            nowMenu.addItem(it)
        }
        now.submenu = nowMenu
        menu.addItem(now)
        if s.mode == .changing {
            _ = item("Something Else", #selector(weatherChangeNow), tip: "What's in clears, and something else comes")
        }
        _ = item("Clear the Sky", #selector(weatherClear))
        menu.addItem(.separator())
        _ = item("Weather Settings…", #selector(showWeatherSettings), tip: "Pick what weather comes to this scenery, and how often")
    }

    @objc private func weatherModeChosen(_ sender: NSMenuItem) {
        setWeatherMode(sender.tag == 2 ? .outside : .changing)
    }

    func setWeatherMode(_ m: WeatherSettings.Mode) {
        if m == .outside, !outsideAvailable() { enableOutside?() }
        weather.settings.mode = m
        panel.refreshWeather()
    }

    @objc private func weatherKept(_ sender: NSMenuItem) {
        guard WeatherKind.allCases.indices.contains(sender.tag) else { return }
        keepWeather(WeatherKind.allCases[sender.tag])
    }

    func keepWeather(_ k: WeatherKind) {
        weather.settings.always = k
        weather.settings.mode = .always
        panel.refreshWeather()
    }

    @objc private func weatherBrought(_ sender: NSMenuItem) {
        guard WeatherKind.allCases.indices.contains(sender.tag) else { return }
        weather.bring(WeatherKind.allCases[sender.tag])
        panel.refreshWeather()
    }

    @objc func weatherChangeNow() {
        weather.changeNow()
        panel.refreshWeather()
    }

    @objc func weatherClear() {
        weather.bring(.clear)
        panel.refreshWeather()
    }

    /// The decorating panel, open at its Weather tab.
    @objc func showWeatherSettings() {
        if !decorating { toggleDecorate() }
        panel.debugShowTab(3)
    }
}

extension WeatherKind {
    /// Said under the tank's name as it rolls in.
    var arriving: String {
        switch self {
        case .clear: return "Clearing up"
        case .sunny: return "The sun’s coming out"
        case .cloudy: return "Clouding over"
        case .fog: return "Fog rolling in"
        case .drizzle: return "Starting to drizzle"
        case .rain: return "Rain on the way"
        case .storm: return "A storm is brewing"
        case .hail: return "Hail!"
        case .snow: return "It’s starting to snow"
        case .blizzard: return "A blizzard is blowing in"
        case .windy: return "The wind’s picking up"
        case .sandstorm: return "A sandstorm is coming"
        case .sunshower: return "A sun shower — look for the rainbow"
        case .starfall: return "Shooting stars tonight"
        case .aurora: return "The northern lights are out"
        }
    }
}

// MARK: - The frame

/// The terrarium round the glass: a lid under the toolbar, a dark frame,
/// a base with a vent in it. Lays out the scene and the decorating panel.
final class HabitatRootView: NSView {
    static let rim: CGFloat = 12
    static let topRim: CGFloat = 10
    static let base: CGFloat = 30

    /// The glass's size: the frame goes round it.
    var glass = CGSize(width: 856, height: 514) { didSet { needsLayout = true; needsDisplay = true } }
    var decorating = false { didSet { needsLayout = true; needsDisplay = true } }
    weak var scene: NSView?
    weak var panel: NSView?

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    /// The tank, frame and all (the decorating panel is beside it).
    private var tankWidth: CGFloat { glass.width + HabitatRootView.rim * 2 }

    private var sceneFrame: CGRect {
        CGRect(x: HabitatRootView.rim, y: HabitatRootView.base, width: glass.width, height: glass.height)
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

/// The name in the middle of the lid, and a line of what is happening under
/// it. Clicking the name renames the tank; dragging it still moves the window.
final class HabitatTitleView: NSView, NSTextFieldDelegate {
    private let title = HabitatNameField(string: "")
    private let sub = NSTextField(labelWithString: "")
    private var titleWidth: NSLayoutConstraint!
    private(set) var status: String?
    /// The name as it was when editing began, for Escape to put back.
    private var before = ""
    private var hovering = false { didSet { needsDisplay = true } }

    /// A name was typed (empty if it was cleared).
    var onRename: ((String) -> Void)?
    /// Return or Escape: the keys go back to the tank.
    var onEndEditing: (() -> Void)?

    static let maxLength = 40

    init() {
        super.init(frame: .zero)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = NSColor(white: 1, alpha: 0.92)
        title.alignment = .center
        title.isBordered = false
        title.drawsBackground = false
        title.focusRingType = .none
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        title.isEditable = false
        title.isSelectable = false
        title.delegate = self
        title.toolTip = "Click to rename the habitat"
        title.onClick = { [weak self] in self?.beginEditing() }
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = NSColor(white: 1, alpha: 0.55)
        sub.alignment = .center
        let stack = NSStackView(views: [title, sub])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        titleWidth = title.widthAnchor.constraint(equalToConstant: 120)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            heightAnchor.constraint(equalToConstant: 34),
            titleWidth,
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    var editing: Bool { title.isEditable }
    var nameField: HabitatNameField { title }

    func set(title t: String, status s: String?) {
        if !editing { title.stringValue = t; fitTitle() }
        status = s
        sub.stringValue = s ?? ""
        sub.isHidden = s == nil
    }

    /// Wide enough for the name (and a little room to type), no wider.
    private func fitTitle() {
        let w = (title.stringValue as NSString).size(withAttributes: [.font: title.font!]).width
        titleWidth.constant = min(max(w + (editing ? 24 : 12), editing ? 140 : 60), 340).rounded()
        needsDisplay = true
    }

    private func beginEditing() {
        before = title.stringValue
        title.isEditable = true
        title.isSelectable = true
        fitTitle()
        window?.makeFirstResponder(title)
        title.currentEditor()?.selectAll(nil)
    }

    // A soft plate behind the name: faint when the pointer is on it, to
    // say it can be clicked, and plainer while typing.
    override func draw(_ dirtyRect: NSRect) {
        guard editing || hovering else { return }
        let r = title.convert(title.bounds, to: self).insetBy(dx: -6, dy: -2)
        NSColor(white: 1, alpha: editing ? 0.14 : 0.07).setFill()
        NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
        if editing {
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            let ring = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            ring.lineWidth = 1
            ring.stroke()
        }
    }

    override func layout() {
        super.layout()
        needsDisplay = true
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: title.convert(title.bounds, to: self).insetBy(dx: -6, dy: -2),
                                       options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    // MARK: Typing

    func controlTextDidChange(_ obj: Notification) {
        if title.stringValue.count > HabitatTitleView.maxLength {
            title.stringValue = String(title.stringValue.prefix(HabitatTitleView.maxLength))
        }
        fitTitle()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            onEndEditing?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            title.stringValue = before
            onEndEditing?()
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        title.isEditable = false
        title.isSelectable = false
        let typed = title.stringValue
        onRename?(typed)
        fitTitle()
    }
}

/// The tank's name: a click starts typing into it, a drag moves the window.
final class HabitatNameField: NSTextField {
    var onClick: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard !isEditable else { super.mouseDown(with: event); return }
        let start = event.locationInWindow
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { onClick?(); return }
            let p = e.locationInWindow
            if hypot(p.x - start.x, p.y - start.y) > 3 { window?.performDrag(with: event); return }
        }
    }
}

// MARK: - The decorating panel

/// Down the side while decorating: the scenery, things to add, ready-made
/// layouts, and — when something in the tank is picked — what can be done
/// to it.
final class DecorPanel: NSView {
    weak var controller: HabitatController?
    private let tabs = NSSegmentedControl(labels: ["Scenery", "Add", "Layouts", "Weather"], trackingMode: .selectOne, target: nil, action: nil)
    // The Weather tab.
    private let weatherMode = NSSegmentedControl(labels: ["Comes & Goes", "Always", "Outside"], trackingMode: .selectOne, target: nil, action: nil)
    private let weatherNow = NSTextField(labelWithString: "")
    private let weatherNowIcon = NSImageView()
    private var weatherNowRow = NSView()
    private var weatherTiles: [(kind: WeatherKind, tile: TileButton)] = []
    private var weatherGrid = NSView()
    private var tilesBiome: Biome?
    private var weatherListLabel = NSTextField(labelWithString: "")
    private var weatherListNote = NSTextField(wrappingLabelWithString: "")
    private let weatherReset = HabitatButton(title: "Back to Its Own", symbol: "arrow.counterclockwise")
    private let paceSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let amountSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private var paceRow = NSView(), amountRow = NSView()
    private var outsideNote = NSTextField(wrappingLabelWithString: "")
    private let outsideButton = HabitatButton(title: "Look Up the Weather Outside", symbol: "location")
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

        pages = [scenePage(width: inner), addPage(width: inner), layoutPage(width: inner), weatherPage(width: inner)]
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
        // Each the whole tank, end to end, so a row each.
        let world = controller?.scene.habitat.size ?? HabitatLayout.defaultWorld
        let thumb = CGSize(width: width - 12, height: ((width - 12) * min(world.height / world.width, 0.45)).rounded())
        let tiles = Habitat.Preset.allCases.map { p -> NSView in
            let t = TileButton(image: HabitatArt.habitatThumbnail(Habitat.preset(p, world: world), size: thumb), title: p.label, subtitle: nil, imageSize: thumb)
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
        return page([note("Start from a ready-made tank, laid out end to end. You can undo it if you liked yours better.", width: width),
                     grid(tiles, columns: 1, width: width), row])
    }

    private func weatherPage(width: CGFloat) -> NSView {
        weatherMode.segmentDistribution = .fillEqually
        weatherMode.target = self
        weatherMode.action = #selector(weatherModeChanged)
        weatherMode.translatesAutoresizingMaskIntoConstraints = false
        weatherMode.widthAnchor.constraint(equalToConstant: width).isActive = true
        weatherMode.setToolTip("Weather rolls in now and then, and clears again", forSegment: 0)
        weatherMode.setToolTip("Keep one kind of weather for good", forSegment: 1)
        weatherMode.setToolTip("The weather where you are", forSegment: 2)

        weatherNow.font = .systemFont(ofSize: 12.5, weight: .semibold)
        weatherNow.textColor = NSColor(white: 1, alpha: 0.92)
        weatherNow.lineBreakMode = .byTruncatingTail
        weatherNowIcon.contentTintColor = NSColor(white: 1, alpha: 0.85)
        weatherNowIcon.translatesAutoresizingMaskIntoConstraints = false
        weatherNowIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let nowLine = NSStackView(views: [weatherNowIcon, weatherNow])
        nowLine.spacing = 6

        let change = HabitatButton(title: "Something Else", symbol: "shuffle")
        change.target = controller
        change.action = #selector(HabitatController.weatherChangeNow)
        change.toolTip = "What's in clears, and something else comes"
        let clear = HabitatButton(title: "Clear the Sky", symbol: "sun.min")
        clear.target = controller
        clear.action = #selector(HabitatController.weatherClear)
        let buttons = NSStackView(views: [change, clear])
        buttons.distribution = .fillEqually
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: width).isActive = true
        weatherNowRow = buttons

        weatherListLabel = sectionLabel("")
        weatherListNote = note("", width: width)
        // Clear skies go last: they only show while keeping one kind.
        let kinds = WeatherKind.allCases.filter { $0 != .clear } + [.clear]
        let tileW = (width - 16) / 3
        let thumb = CGSize(width: tileW - 12, height: ((tileW - 12) * HabitatLayout.aspect).rounded())
        weatherTiles = kinds.map { k in
            let t = TileButton(image: NSImage(size: thumb), title: k.label, subtitle: nil, imageSize: thumb, titleSize: 10)
            t.onClick = { [weak self] in self?.weatherTileClicked(k) }
            t.toolTip = k.blurb
            return (k, t)
        }
        weatherGrid = grid(weatherTiles.map { $0.tile }, columns: 3, width: width)

        weatherReset.target = self
        weatherReset.action = #selector(weatherResetTapped)
        weatherReset.toolTip = "Only the weather that comes to this scenery by itself"

        func sliderRow(_ title: String, low: String, high: String, _ s: NSSlider, action: Selector) -> NSView {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12)
            label.textColor = NSColor(white: 1, alpha: 0.78)
            s.controlSize = .small
            s.isContinuous = true
            s.target = self
            s.action = action
            s.translatesAutoresizingMaskIntoConstraints = false
            s.widthAnchor.constraint(equalToConstant: width).isActive = true
            func caption(_ t: String) -> NSTextField {
                let c = NSTextField(labelWithString: t)
                c.font = .systemFont(ofSize: 10)
                c.textColor = NSColor(white: 1, alpha: 0.45)
                return c
            }
            let gap = NSView()
            gap.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let ends = NSStackView(views: [caption(low), gap, caption(high)])
            ends.translatesAutoresizingMaskIntoConstraints = false
            ends.widthAnchor.constraint(equalToConstant: width).isActive = true
            let col = NSStackView(views: [label, s, ends])
            col.orientation = .vertical
            col.alignment = .leading
            col.spacing = 3
            return col
        }
        paceRow = sliderRow("How Often It Changes", low: "Slowly", high: "Often", paceSlider, action: #selector(paceChanged))
        amountRow = sliderRow("How Much Weather", low: "Now and then", high: "Most of the time", amountSlider, action: #selector(amountChanged))

        outsideNote = note("", width: width)
        outsideButton.target = self
        outsideButton.action = #selector(outsideTapped)

        return page([note("The tank has weather of its own, and your spider feels it: rain soaks it, snow settles on it, the wind blows it about — and it runs for cover when it pours.", width: width),
                     weatherMode, nowLine, weatherNowRow, weatherListLabel, weatherListNote, weatherGrid, weatherReset,
                     paceRow, amountRow, outsideNote, outsideButton])
    }

    /// The Weather tab, back in step with the tank's weather.
    func refreshWeather() {
        guard let c = controller, !weatherTiles.isEmpty else { return }
        let s = c.weather.settings
        let b = c.scene.habitat.biome
        weatherMode.selectedSegment = s.mode == .changing ? 0 : (s.mode == .always ? 1 : 2)
        weatherNow.stringValue = c.weather.summary()
        weatherNowIcon.image = NSImage(systemSymbolName: c.weather.current.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        // The tiles show this scenery, with each kind of weather on it.
        if tilesBiome != b, pages.count > 3, !pages[3].isHidden {
            tilesBiome = b
            for (k, t) in weatherTiles {
                t.setImage(WeatherArt.thumbnail(k, biome: b, size: t.imageSize))
            }
        }
        let list = s.rotation(b)
        for (k, t) in weatherTiles {
            switch s.mode {
            case .changing:
                t.isHidden = k == .clear
                t.selected = list.contains(k)
                t.alphaValue = list.contains(k) ? 1 : 0.45
                t.toolTip = list.contains(k) ? "\(k.blurb) — comes to the \(b.label). Click to take it out." : "\(k.blurb). Click to have it come to the \(b.label) too."
            case .always:
                t.isHidden = false
                t.selected = s.always == k
                t.alphaValue = 1
                t.toolTip = "\(k.blurb). Click to keep it that way."
            case .outside:
                t.isHidden = true
            }
        }
        let changing = s.mode == .changing
        weatherGrid.isHidden = s.mode == .outside
        weatherListLabel.isHidden = s.mode == .outside
        weatherListNote.isHidden = s.mode == .outside
        weatherListLabel.stringValue = (changing ? "Weather in the \(b.label)" : "Keep It…").uppercased()
        weatherListNote.stringValue = changing
            ? "Lit up: comes to the \(b.label) now and then. Click to add or take one out — snow in the desert, if you like. Clear skies come in between."
            : "Click one to keep it that way."
        weatherReset.isHidden = !changing
        weatherReset.isEnabled = s.isCustom(b)
        weatherReset.set(title: "Back to the \(b.label)’s Own", symbol: "arrow.counterclockwise")
        weatherNowRow.isHidden = !changing
        paceRow.isHidden = !changing
        amountRow.isHidden = !changing
        if abs(paceSlider.doubleValue - Double(s.pace)) > 0.001 { paceSlider.doubleValue = Double(s.pace) }
        if abs(amountSlider.doubleValue - Double(s.amount)) > 0.001 { amountSlider.doubleValue = Double(s.amount) }
        let available = c.outsideAvailable()
        outsideNote.isHidden = s.mode != .outside
        outsideButton.isHidden = s.mode != .outside || available
        outsideNote.stringValue = available
            ? "The tank has the weather where you are — rain when it rains, snow when it snows. It’s looked up every twenty minutes, from Open-Meteo, going by roughly where your internet connection is. " + (c.outsideSummary() ?? "Looking it up…")
            : "To follow the weather where you are, the app looks it up every twenty minutes (from Open-Meteo, going by roughly where your internet connection is). That’s off at the moment."
    }

    @objc private func weatherModeChanged() {
        let m: WeatherSettings.Mode = weatherMode.selectedSegment == 1 ? .always : (weatherMode.selectedSegment == 2 ? .outside : .changing)
        if m == .outside {
            // (Only once it is allowed to look.)
            if controller?.outsideAvailable() == true { controller?.setWeatherMode(.outside) }
            else { controller?.weather.settings.mode = .outside; refreshWeather() }
        } else {
            controller?.setWeatherMode(m)
        }
    }

    private func weatherTileClicked(_ k: WeatherKind) {
        guard let c = controller else { return }
        switch c.weather.settings.mode {
        case .changing:
            c.weather.settings.toggle(k, in: c.scene.habitat.biome)
        case .always, .outside:
            c.keepWeather(k)
        }
        refreshWeather()
    }

    @objc private func weatherResetTapped() {
        guard let c = controller else { return }
        c.weather.settings.reset(c.scene.habitat.biome)
        refreshWeather()
    }

    @objc private func paceChanged() { controller?.weather.settings.pace = CGFloat(paceSlider.doubleValue) }
    @objc private func amountChanged() { controller?.weather.settings.amount = CGFloat(amountSlider.doubleValue) }
    @objc private func outsideTapped() { controller?.setWeatherMode(.outside) }

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
        hint.stringValue = "Click anything in the tank to move it; drag a corner to resize it. Drag the bare glass to look round the tank, or use the Overview to move things a long way. ⌘Z undoes."
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
        if i == 3 { refreshWeather() }
        scroll.documentView?.scroll(.zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Back in step with the tank.
    func refresh() {
        guard let c = controller else { return }
        refreshWeather()
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
            // (Keeping its own shape: a long vine stays long.)
            let tall = it.h / max(it.w, 1)
            it.w = it.kind.defaultSize.width * k
            it.h = it.w * tall
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

/// Fills a menu afresh each time it is about to open.
final class MenuFiller: NSObject, NSMenuDelegate {
    private let fill: (NSMenu) -> Void
    init(_ fill: @escaping (NSMenu) -> Void) { self.fill = fill }
    func menuNeedsUpdate(_ menu: NSMenu) { fill(menu) }
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
    let imageSize: CGSize

    init(image: NSImage, title: String, subtitle: String?, imageSize: CGSize, titleSize: CGFloat = 11.5) {
        self.imageSize = imageSize
        super.init(frame: .zero)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = subtitle == nil && imageSize.width < 80 && titleSize >= 11.5 ? 0 : 6
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = title
        label.font = .systemFont(ofSize: titleSize, weight: .medium)
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

    func setImage(_ img: NSImage) { imageView.image = img }

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
