import AppKit

// MARK: - The tank's window

/// The habitat as a window: a terrarium with a lid along the top (where
/// its buttons are), a dark frame round the glass and a base under it,
/// and — while decorating — a panel of scenery and furniture to the side.
final class HabitatController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    let window: NSWindow
    let scene = HabitatSceneView(frame: CGRect(x: 0, y: 0, width: 860, height: 516))
    private let root = HabitatRootView()
    let titleView = HabitatTitleView()
    // The lid's buttons, in the order anyone uses them: getting about the
    // tank (and out of it) on the left of the name; what to do with it on
    // the right — look after it, then make it your own — and help.
    let letOutButton = HabitatButton(title: "Let Out", symbol: "door.left.hand.open")
    let mapButton = HabitatButton(title: "Map", symbol: "map")
    let feedButton = HabitatButton(title: "Feed", symbol: "fork.knife", menu: true)
    let weatherButton = HabitatButton(title: "Weather", symbol: "cloud.sun", menu: true)
    let decorateButton = HabitatButton(title: "Decorate", symbol: "paintbrush.pointed")
    let helpButton = HabitatButton(title: "Help", symbol: "questionmark")
    /// The weather's own panel, dropping down from its button (made the
    /// first time it is wanted).
    private var weatherPopover: NSPopover?
    private var weatherPanel: WeatherPanel?
    /// The tour, while it is on.
    var tour: HabitatTour?
    /// Which of My Habitats the tank was last put in from, or saved as.
    static let currentSaveKey = "habitatCurrentSave"
    var currentSaveID: String? {
        get { UserDefaults.standard.string(forKey: HabitatController.currentSaveKey) }
        set { UserDefaults.standard.set(newValue, forKey: HabitatController.currentSaveKey) }
    }

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
    /// Whether creatures find their own way into the tank, and turning that
    /// on or off (the Feed menu).
    var tankWildlife: () -> Bool = { true }
    var onToggleTankWildlife: (() -> Void)?

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

    /// The window and everything round the glass, laid out — but not the
    /// tank itself, which is set up the first time it is opened (see
    /// `load`): the app makes this ahead, as it starts, so that opening the
    /// tank has only the tank to do.
    /// `standoff`: the spider's height off what it stands on, for laying the
    /// surfaces out (the first time, before anything else is laid out, so it
    /// is done once).
    init(spiderName: String, standoff: CGFloat? = nil, syncMaps: Bool = false) {
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
        let saved = Habitat.load()
        weather = WeatherClock(biome: saved.biome)
        super.init()
        pending = saved
        if let standoff { scene.presetStandoff(standoff) }
        scene.syncMaps = syncMaps
        window.title = HabitatController.title(for: spiderName)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.1, alpha: 1)
        // The tank's pictures are painted in sRGB: in a window of the same
        // space Core Animation takes them as they are, rather than painting
        // each afresh into the display's colours on the main thread as it
        // is put up (a big picture took a tenth of a second or more), and
        // the window server matches the colours to the display as it shows
        // them.
        window.colorSpace = .sRGB
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone]
        window.tabbingMode = .disallowed
        window.delegate = self
        root.glass = glass
        window.contentView = root
        root.addSubview(scene)
        root.scene = scene
        // (The decorating panel is made the first time it is wanted.)

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
        decorateButton.toolTip = "Change the scenery, add things, and save your habitats"
        feedButton.target = self
        feedButton.action = #selector(showFeedMenu)
        feedButton.toolTip = "Let something loose in the tank for it to hunt"
        letOutButton.target = self
        letOutButton.action = #selector(letOut)
        letOutButton.toolTip = "Close the habitat — your spider goes back onto your desktop"
        mapButton.target = self
        mapButton.action = #selector(toggleOverview)
        mapButton.toolTip = "See the whole tank at once — click anywhere on it to go there"
        weatherButton.target = self
        weatherButton.action = #selector(showWeatherPanel)
        weatherButton.toolTip = "Rain, snow, wind, sun and more — change the weather in the tank"
        helpButton.target = self
        helpButton.action = #selector(showTour)
        helpButton.toolTip = "Show me round"
        helpButton.iconOnly = true
        weather.onChange = { [weak self] in self?.refreshWeatherPanel() }

        scene.onEdit = { [weak self] before, after in self?.edited(from: before, to: after) }
        scene.onSelect = { [weak self] _ in self?.decorPanel?.refresh() }
        scene.onCommand = { [weak self] c in
            switch c {
            case .undo: self?.undo()
            case .redo: self?.redo()
            case .done: if self?.decorating == true { self?.toggleDecorate() }
            }
        }
        scene.onOverviewChange = { [weak self] on in self?.mapButton.isOn = on }
        scene.spiderName = spiderName
        glass = fitted(glass)
        window.setContentSize(size(forGlass: glass))
        window.minSize = size(forGlass: HabitatController.minGlass)
        fitButtons()
        root.needsLayout = true
    }

    /// The habitat the tank shows, once it has been set up (see `load`);
    /// nil before.
    var loadedHabitat: Habitat? { pending == nil ? scene.habitat : nil }
    /// The saved habitat, until the tank is set up with it.
    private var pending: Habitat?

    /// Sets the tank up with its habitat, the first time it is opened: its
    /// pictures painted and its surfaces laid out off the main thread (see
    /// `HabitatPainter`, `HabitatSceneView.rebuildMap`). `mapNow`: its
    /// surfaces laid out at once (the spider is put straight into it).
    func load(mapNow: Bool = false) {
        guard let saved = pending else { return }
        pending = nil
        Perf.measure("habitat: scene set") { scene.setHabitat(saved, mapNow: mapNow) }
        if let o = HabitatCamera.saved() { scene.camera.jump(to: o) }
        glass = fitted(glass)
        window.setContentSize(size(forGlass: glass))
        root.needsLayout = true
    }

    /// The decorating panel, if it has been made.
    private var decorPanel: DecorPanel?
    var decorPanelIfBuilt: DecorPanel? { decorPanel?.built == true ? decorPanel : nil }
    func decorPanelRefresh() { decorPanel?.refresh() }

    /// The decorating panel: made, and built, the first time it is wanted.
    private var panel: DecorPanel {
        if let p = decorPanel { return p }
        let p = DecorPanel()
        p.controller = self
        p.isHidden = true
        root.addSubview(p)
        root.panel = p
        decorPanel = p
        Perf.measure("habitat: decorating panel built") { p.build() }
        root.needsLayout = true
        return p
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
        // (Before the tank is set up, the world it will be.)
        let world = (pending ?? scene.habitat).size
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
        fitButtons()
        tour?.windowResized()
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
        [.habitatGetAbout, .flexibleSpace, .habitatTitle, .flexibleSpace, .habitatCare, .habitatDecorate, .habitatHelp]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        func group(_ views: [NSView]) -> NSView {
            let g = NSStackView(views: views)
            g.spacing = 6
            return g
        }
        switch id {
        case .habitatTitle: item.view = titleView
        case .habitatGetAbout: item.view = group([letOutButton, mapButton]); item.label = "Let Out and Map"
        case .habitatCare: item.view = group([feedButton, weatherButton]); item.label = "Feed and Weather"
        case .habitatDecorate: item.view = decorateButton; item.label = "Decorate"
        case .habitatHelp: item.view = helpButton; item.label = "Help"
        default: return nil
        }
        return item
    }

    /// Words on the buttons while there is room for them, just their
    /// pictures when the window is narrow (their tips still say).
    private func fitButtons() {
        let compact = window.frame.width < 960
        for b in [letOutButton, mapButton, feedButton, weatherButton, decorateButton] where b.compact != compact { b.compact = compact }
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
            if self.decorating {
                self.window.makeFirstResponder(self.scene)
                // The first time: how decorating works.
                if !HabitatTour.seen(.decorating), !HabitatTour.suppressed { self.startTour(.decorating) }
            }
        })
    }

    // MARK: The tour

    /// The tour for what is showing: the tank's, or decorating's.
    @objc func showTour() {
        startTour(decorating ? .decorating : .tank)
    }

    /// The tank's tour, if it hasn't been seen: once the tank is open and
    /// the spider has had a moment to come in.
    func maybeStartTour() {
        guard !HabitatTour.seen(.tank), !HabitatTour.suppressed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.window.isVisible, !self.window.isMiniaturized, self.tour == nil,
                  !HabitatTour.seen(.tank) else { return }
            self.startTour(.tank)
        }
    }

    /// Something in view picked, for the tour to show what can be done
    /// to it: the thing nearest the middle of the glass.
    func pickSomethingToShow() {
        let vis = scene.visibleWorld
        let mid = CGPoint(x: vis.midX, y: vis.midY)
        let pick = scene.habitat.items
            .filter { vis.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) && !$0.kind.isBacking }
            .min { hypot($0.rect.midX - mid.x, $0.rect.midY - mid.y) < hypot($1.rect.midX - mid.x, $1.rect.midY - mid.y) }
        if let pick, scene.selected != pick.id { scene.select(pick.id) }
    }

    func startTour(_ k: HabitatTour.Kind) {
        guard tour == nil, window.isVisible else { return }
        weatherPopover?.performClose(nil)
        if scene.overviewOpen { scene.showOverview(false) }
        scene.select(nil)
        let t = HabitatTour(kind: k, controller: self)
        t.onFinish = { [weak self] in
            self?.tour = nil
            if let self { self.window.makeFirstResponder(self.scene) }
        }
        tour = t
        t.start()
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
        menu.addItem(.separator())
        let wild = NSMenuItem(title: "Creatures Find Their Own Way In", action: #selector(toggleTankWildlife), keyEquivalent: "")
        wild.target = self
        wild.state = tankWildlife() ? .on : .off
        wild.toolTip = "Now and then something comes into the tank on its own — what, and where, depends on what’s in there: flies to flowers, beetles under bark, worms in damp litter, moths to a light after dark"
        menu.addItem(wild)
        menu.autoenablesItems = false
        let below = feedButton.isFlipped ? feedButton.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: below), in: feedButton)
    }

    @objc private func feed(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? Int, let kind = PreyKind(rawValue: raw) else { return }
        onFeed?(kind)
    }

    @objc private func toggleTankWildlife() { onToggleTankWildlife?() }

    @objc func letOut() { onLetOut?() }

    /// The whole habitat at once, small — or back to the tank.
    @objc func toggleOverview() {
        scene.showOverview(!scene.overviewOpen)
    }

    /// Tools only: the decorating panel at a tab.
    func debugShowTab(_ i: Int) { panel.debugShowTab(i) }
    /// Tools only: the Add tab showing one part of it.
    func debugShowShelf(_ s: HabitatObjectDefinition.Shelf?) { debugShowTab(0); panel.showShelf(s) }
    func debugSearch(_ q: String) { debugShowTab(0); panel.debugSearch(q) }
    func debugSuits(_ on: Bool) { debugShowTab(0); panel.debugSuits(on) }

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
        decorPanel?.refresh()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append(scene.habitat)
        scene.setHabitat(prev, fade: prev.biome != scene.habitat.biome)
        prev.save()
        decorPanel?.refresh()
    }

    func redo() {
        guard let next = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append(scene.habitat)
        scene.setHabitat(next, fade: next.biome != scene.habitat.biome)
        next.save()
        decorPanel?.refresh()
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
        currentSaveID = nil
        scene.replace(with: Habitat.preset(p, world: scene.habitat.size), fade: true)
    }

    func shuffle() {
        // Half the time in the scenery it has, half the time somewhere new.
        currentSaveID = nil
        scene.replace(with: Habitat.surprise(world: scene.habitat.size, biome: Bool.random() ? scene.habitat.biome : nil), fade: true)
    }

    func clearAll() {
        var h = scene.habitat
        h.items = []
        currentSaveID = nil
        scene.replace(with: h, fade: true)
    }
}

extension NSToolbarItem.Identifier {
    static let habitatTitle = NSToolbarItem.Identifier("habitat.title")
    static let habitatGetAbout = NSToolbarItem.Identifier("habitat.getAbout")
    static let habitatCare = NSToolbarItem.Identifier("habitat.care")
    static let habitatDecorate = NSToolbarItem.Identifier("habitat.decorate")
    static let habitatHelp = NSToolbarItem.Identifier("habitat.help")
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
        refreshWeatherPanel()
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

    /// The weather's panel, dropping down from its button (or put away,
    /// if it is out).
    @objc func showWeatherPanel() {
        if let p = weatherPopover, p.isShown { p.performClose(nil); return }
        let panel = weatherPanel ?? WeatherPanel(controller: self)
        weatherPanel = panel
        panel.refresh()
        let p = weatherPopover ?? {
            let p = NSPopover()
            let vc = NSViewController()
            vc.view = panel
            p.contentViewController = vc
            p.behavior = .transient
            p.animates = true
            p.appearance = NSAppearance(named: .darkAqua)
            weatherPopover = p
            return p
        }()
        p.contentSize = panel.fittingSize
        let anchor: NSView = weatherButton.window != nil ? weatherButton : scene
        let rect = anchor === scene ? CGRect(x: scene.bounds.maxX - 40, y: scene.bounds.maxY - 4, width: 1, height: 1) : anchor.bounds
        p.show(relativeTo: rect, of: anchor, preferredEdge: .maxY)
    }

    var weatherPopoverWindow: NSWindow? { weatherPopover?.isShown == true ? weatherPanel?.window : nil }

    /// The weather's panel back in step (and the right size for what it
    /// shows now).
    func refreshWeatherPanel() {
        guard let panel = weatherPanel, let p = weatherPopover, p.isShown else { return }
        panel.refresh()
        let size = panel.fittingSize
        if p.contentSize != size { p.contentSize = size }
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
            let it = NSMenuItem(title: k.summon, action: #selector(weatherBroughtItem(_:)), keyEquivalent: "")
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
        _ = item("Weather Settings…", #selector(showWeatherPanel), tip: "Pick what weather comes to this scenery, and how often")
    }

    @objc private func weatherModeChosen(_ sender: NSMenuItem) {
        setWeatherMode(sender.tag == 2 ? .outside : .changing)
    }

    func setWeatherMode(_ m: WeatherSettings.Mode) {
        if m == .outside, !outsideAvailable() { enableOutside?() }
        weather.settings.mode = m
        refreshWeatherPanel()
    }

    @objc private func weatherKept(_ sender: NSMenuItem) {
        guard WeatherKind.allCases.indices.contains(sender.tag) else { return }
        keepWeather(WeatherKind.allCases[sender.tag])
    }

    func keepWeather(_ k: WeatherKind) {
        weather.settings.always = k
        weather.settings.mode = .always
        refreshWeatherPanel()
    }

    @objc func weatherBroughtItem(_ sender: NSMenuItem) {
        guard WeatherKind.allCases.indices.contains(sender.tag) else { return }
        weather.bring(WeatherKind.allCases[sender.tag])
        refreshWeatherPanel()
    }

    @objc func weatherChangeNow() {
        weather.changeNow()
        refreshWeatherPanel()
    }

    @objc func weatherClear() {
        weather.bring(.clear)
        refreshWeatherPanel()
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
        layOutFrame()
    }

    // The frame round the glass is made of Core Animation layers, which the
    // window server draws: painted here, its gradients the size of the
    // window were a good part of the main thread's time as the tank opened
    // (and at every step of a resize).
    private let lidFill = CAGradientLayer(), lidMesh = CAShapeLayer()
    private let bodyFill = CAGradientLayer()
    private let lipDark = CALayer(), lipLight = CALayer()
    private let baseFill = CAGradientLayer(), baseLight = CALayer()
    private let vents = CAShapeLayer(), ventLights = CAShapeLayer()
    private let groove = CAShapeLayer(), grooveRim = CAShapeLayer()
    private var framed = false

    private func makeFrame() {
        guard !framed, let root = layer else { return }
        framed = true
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { HabitatArt.c(r, g, b, a) }
        // The lid: brushed dark metal with a mesh.
        lidFill.colors = [c(0.13, 0.13, 0.15), c(0.2, 0.2, 0.22)]
        lidMesh.strokeColor = c(1, 1, 1, 0.035)
        lidMesh.fillColor = nil
        lidMesh.lineWidth = 1
        lidMesh.masksToBounds = true
        // The body of the tank.
        bodyFill.colors = [c(0.12, 0.12, 0.13), c(0.2, 0.2, 0.22)]
        // A lip of light between lid and body.
        lipDark.backgroundColor = c(0, 0, 0, 0.5)
        lipLight.backgroundColor = c(1, 1, 1, 0.07)
        // The base: a slightly lighter band with a row of vent slots.
        baseFill.colors = [c(0.1, 0.1, 0.11), c(0.17, 0.17, 0.19)]
        baseLight.backgroundColor = c(1, 1, 1, 0.06)
        vents.fillColor = c(0, 0, 0, 0.55)
        ventLights.fillColor = c(1, 1, 1, 0.05)
        // The glass sits in a groove.
        groove.fillColor = c(0.03, 0.03, 0.04)
        groove.fillRule = .evenOdd
        grooveRim.fillColor = nil
        grooveRim.strokeColor = c(1, 1, 1, 0.06)
        grooveRim.lineWidth = 1
        // (In order, back to front, all under the subviews' own layers.)
        for (i, l) in ([lidFill, lidMesh, bodyFill, lipDark, lipLight, baseFill, baseLight, vents, ventLights, groove, grooveRim] as [CALayer]).enumerated() {
            l.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "frame": NSNull()]
            l.zPosition = -100 + CGFloat(i)
            root.addSublayer(l)
        }
    }

    private func layOutFrame() {
        wantsLayer = true
        makeFrame()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let glass = sceneFrame
        let lidBottom = glass.maxY + HabitatRootView.topRim
        let lid = CGRect(x: 0, y: lidBottom, width: bounds.width, height: max(bounds.height - lidBottom, 0))
        lidFill.frame = lid
        lidMesh.frame = lid
        let mesh = CGMutablePath()
        var x: CGFloat = -lid.height
        while x < lid.width {
            mesh.move(to: CGPoint(x: x, y: 0)); mesh.addLine(to: CGPoint(x: x + lid.height, y: lid.height))
            mesh.move(to: CGPoint(x: x + lid.height, y: 0)); mesh.addLine(to: CGPoint(x: x, y: lid.height))
            x += 5
        }
        lidMesh.path = mesh
        bodyFill.frame = CGRect(x: 0, y: 0, width: tankWidth, height: lidBottom)
        lipDark.frame = CGRect(x: 0, y: lidBottom - 1, width: bounds.width, height: 1)
        lipLight.frame = CGRect(x: 0, y: lidBottom, width: bounds.width, height: 1)
        let base = CGRect(x: 0, y: 0, width: tankWidth, height: HabitatRootView.base - 4)
        baseFill.frame = base
        baseLight.frame = CGRect(x: 0, y: base.maxY - 1, width: tankWidth, height: 1)
        let slots = 9
        let slotW: CGFloat = 16, gap: CGFloat = 6
        let total = CGFloat(slots) * slotW + CGFloat(slots - 1) * gap
        let slotPath = CGMutablePath(), slotLights = CGMutablePath()
        for k in 0..<slots {
            let r = CGRect(x: tankWidth / 2 - total / 2 + CGFloat(k) * (slotW + gap), y: base.midY - 2, width: slotW, height: 4)
            slotPath.addRoundedRect(in: r, cornerWidth: 2, cornerHeight: 2)
            slotLights.addRect(CGRect(x: r.minX + 1, y: r.minY - 1, width: r.width - 2, height: 1))
        }
        vents.frame = bounds
        vents.path = slotPath
        ventLights.frame = bounds
        ventLights.path = slotLights
        let g = glass.insetBy(dx: -3, dy: -3)
        let groovePath = CGMutablePath()
        groovePath.addRoundedRect(in: g, cornerWidth: 5, cornerHeight: 5)
        groovePath.addRect(glass.insetBy(dx: 2, dy: 2))
        groove.frame = bounds
        groove.path = groovePath
        grooveRim.frame = bounds
        grooveRim.path = CGPath(roundedRect: g.insetBy(dx: -1, dy: -1), cornerWidth: 6, cornerHeight: 6, transform: nil)
    }
}

// MARK: - Buttons

/// A clear, roomy toolbar button: an icon and a word, on a soft pill that
/// lights up under the pointer and fills with the accent while it is on.
final class HabitatButton: NSButton {
    var isOn = false { didSet { needsDisplay = true; updateTint() } }
    var destructive = false { didSet { updateTint() } }
    /// Just its picture (when the window is narrow).
    var compact = false { didSet { updateTint() } }
    /// Only ever its picture: a round button.
    var iconOnly = false { didSet { updateTint() } }
    private var showsWords: Bool { !compact && !iconOnly }
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
        if !showsWords && !hasMenu { return NSSize(width: 32, height: 30) }
        let s = super.intrinsicContentSize
        return NSSize(width: s.width + (showsWords ? 24 : 18), height: 30)
    }

    private func updateTint() {
        let col: NSColor = isOn ? .white : (destructive ? .systemRed : NSColor(white: 1, alpha: 0.9))
        contentTintColor = col
        // A menu button carries a small chevron after its word.
        let words = showsWords ? " " + label + (hasMenu ? "  ▾" : "") : (hasMenu ? " ▾" : "")
        imagePosition = words.isEmpty ? .imageOnly : .imageLeading
        attributedTitle = NSAttributedString(string: words, attributes: [
            .font: font ?? .systemFont(ofSize: 12.5),
            .foregroundColor: col,
        ])
        invalidateIntrinsicContentSize()
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

/// Down the side while decorating, in the order it is used: things to add,
/// the scenery behind the glass, and whole habitats — your own saved ones
/// and ready-made ones. Under them, when something in the tank is picked,
/// what can be done to it.
final class DecorPanel: NSView {
    weak var controller: HabitatController?
    static let tabNames = ["Add", "Scenery", "Habitats"]
    enum Tab: Int { case add, scenery, habitats }
    private let tabs = NSSegmentedControl(labels: DecorPanel.tabNames, trackingMode: .selectOne, target: nil, action: nil)
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
    /// What holds the chosen thing up, and a way to hold it up if nothing does.
    private let supportIcon = NSImageView()
    private let supportLabel = NSTextField(labelWithString: "")
    private var supportLine = NSView()
    private let supportButton = HabitatButton(title: "Add a Support", symbol: "wrench.and.screwdriver")
    /// A door or a window: open it, or shut it.
    private let openButton = HabitatButton(title: "Open", symbol: "door.left.hand.open")
    // The Add tab: a chip for each part of it, and each part's heading and tiles.
    private let shelfMenu = NSPopUpButton()
    private var shownShelf: HabitatObjectDefinition.Shelf?
    private struct AddGroup { let label: NSTextField?; let host: NSStackView; let kinds: [HabitatItemKind] }
    private struct AddSection { let shelf: HabitatObjectDefinition.Shelf; let header: NSView; let groups: [AddGroup] }
    private var addSections: [AddSection] = []
    private var addTiles: [HabitatItemKind: TileButton] = [:]
    private var addWidth: CGFloat = 0
    private let searchField = NSSearchField()
    private let suitsBox = NSButton(checkboxWithTitle: "Only what suits this scenery", target: nil, action: nil)
    private let nothingNote = NSTextField(labelWithString: "")
    /// The scenery the Add tab was last filtered for.
    private var filteredBiome: Biome?
    // The Habitats tab: My Habitats, then the ready-made ones.
    private let saveButton = HabitatButton(title: "Save This Habitat", symbol: "square.and.arrow.down")
    private let saveNewButton = HabitatButton(title: "Save as New", symbol: "plus.square.on.square")
    private let importButton = HabitatButton(title: "Import", symbol: "tray.and.arrow.down")
    private let savedHost = NSStackView()
    private var savedEmpty = NSTextField(wrappingLabelWithString: "")
    private var savedCards: [SavedHabitatCard] = []
    private var savedWidth: CGFloat = 0
    private var libraryWatch: NSObjectProtocol?

    override var isFlipped: Bool { true }

    deinit { if let w = libraryWatch { NotificationCenter.default.removeObserver(w) } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.13, alpha: 1).setFill()
        bounds.fill()
        NSColor(white: 0, alpha: 0.6).setFill()
        CGRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        NSColor(white: 1, alpha: 0.05).setFill()
        CGRect(x: 1, y: 0, width: 1, height: bounds.height).fill()
    }

    /// Built the first time it is wanted (decorating), not with the tank:
    /// its hundreds of little pictures would hold up the tank opening, and
    /// the spider with it.
    private(set) var built = false

    private func paintLater(_ tile: TileButton, _ paint: @escaping () -> NSImage) {
        PanelKit.paintLater({ [weak tile] in tile?.setImage($0) }, paint)
    }

    func build() {
        guard !built else { return }
        built = true
        let pad: CGFloat = 16
        let inner = HabitatController.sidebarWidth - pad * 2

        tabs.segmentDistribution = .fillEqually
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.setToolTip("Plants, rocks, logs, shelters and more to put in the tank", forSegment: 0)
        tabs.setToolTip("The backdrop behind the glass", forSegment: 1)
        tabs.setToolTip("Save this habitat, go back to one you saved, or start from a ready-made one", forSegment: 2)

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

        pages = [addPage(width: inner), scenePage(width: inner), habitatsPage(width: inner)]
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
        libraryWatch = NotificationCenter.default.addObserver(forName: HabitatLibrary.changed, object: nil, queue: .main) { [weak self] _ in
            self?.reloadSaved()
        }
        showPage(0)
        refresh()
    }

    private func sectionLabel(_ s: String) -> NSTextField { PanelKit.sectionLabel(s) }
    private func note(_ s: String, width: CGFloat) -> NSTextField { PanelKit.note(s, width: width) }
    private func grid(_ tiles: [NSView], columns: Int, width: CGFloat, spacing: CGFloat = 8) -> NSView {
        PanelKit.grid(tiles, columns: columns, width: width, spacing: spacing)
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
            let t = TileButton(image: NSImage(size: thumb), title: b.label, subtitle: b.blurb, imageSize: thumb)
            t.onClick = { [weak self] in self?.controller?.setBiome(b) }
            paintLater(t) { HabitatArt.biomeThumbnail(b, size: thumb) }
            return t
        }
        return page([note("The backdrop behind the glass. Everything in it moves — clouds, leaves, snow, fireflies. What’s in the tank stays where it is.", width: width),
                     grid(biomeTiles, columns: 2, width: width)])
    }

    private func addPage(width: CGFloat) -> NSView {
        typealias Shelf = HabitatObjectDefinition.Shelf
        addWidth = width
        let tileW = (width - 16) / 3
        for k in HabitatItemKind.allCases {
            let t = TileButton(image: NSImage(size: CGSize(width: 56, height: 56)), title: k.label, subtitle: nil, imageSize: CGSize(width: 56, height: 56), titleSize: 10.5)
            paintLater(t) { HabitatArt.thumbnail(k, side: 56) }
            t.onClick = { [weak self] in self?.controller?.scene.add(k) }
            t.toolTip = k.definition.note.map { "\(k.label): \($0)" } ?? "Add \(k.label.lowercased())"
            t.translatesAutoresizingMaskIntoConstraints = false
            t.widthAnchor.constraint(equalToConstant: tileW).isActive = true
            addTiles[k] = t
        }
        // Search, and only what belongs in this scenery.
        searchField.placeholderString = "Search — fern, shelter, water…"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: width).isActive = true
        suitsBox.target = self
        suitsBox.action = #selector(suitsChanged)
        suitsBox.font = .systemFont(ofSize: 11.5)
        suitsBox.toolTip = "Hide what wouldn't be found in the scenery you have chosen"
        // Which part to show: a menu, the natural world first, then what is made by hand.
        shelfMenu.removeAllItems()
        shelfMenu.addItem(withTitle: "Everything")
        shelfMenu.menu?.addItem(.separator())
        for shelf in Shelf.allCases where shelf.natural { shelfMenu.addItem(withTitle: shelf.label); shelfMenu.lastItem?.representedObject = shelf.rawValue }
        shelfMenu.menu?.addItem(.separator())
        for shelf in Shelf.allCases where !shelf.natural { shelfMenu.addItem(withTitle: shelf.label); shelfMenu.lastItem?.representedObject = shelf.rawValue }
        shelfMenu.target = self
        shelfMenu.action = #selector(shelfPicked)
        shelfMenu.controlSize = .small
        shelfMenu.font = .systemFont(ofSize: 11.5)
        let filters = NSStackView(views: [shelfMenu, suitsBox])
        filters.spacing = 10
        nothingNote.stringValue = "Nothing matches."
        nothingNote.font = .systemFont(ofSize: 12)
        nothingNote.textColor = NSColor(white: 1, alpha: 0.5)
        nothingNote.isHidden = true
        var views: [NSView] = [note("Click something to drop it into the tank, then drag it where you want it.", width: width),
                               searchField, filters, nothingNote]
        addSections = Shelf.allCases.map { shelf in
            let header = sectionLabel(shelf.heading)
            views.append(header)
            let kinds = HabitatItemKind.allCases.filter { $0.definition.shelf == shelf }
            // Its parts, in order; what is in none of them first.
            let groups: [HabitatObjectDefinition.Group?] = [nil] + HabitatObjectDefinition.Group.allCases.map { Optional($0) }
            var parts: [AddGroup] = []
            for g in groups {
                let ks = kinds.filter { $0.definition.group == g }
                guard !ks.isEmpty else { continue }
                let label = g.map { subLabel($0.label) }
                let host = NSStackView()
                host.orientation = .vertical
                host.alignment = .leading
                if let label { views.append(label) }
                views.append(host)
                parts.append(AddGroup(label: label, host: host, kinds: ks))
            }
            return AddSection(shelf: shelf, header: header, groups: parts)
        }
        let p = page(views)
        refilter()
        return p
    }

    private func subLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = NSColor(white: 1, alpha: 0.7)
        return l
    }

    /// Tiles in rows of three (their widths are their own).
    private func tileRows(_ tiles: [NSView]) -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        var i = 0
        while i < tiles.count {
            let row = NSStackView(views: Array(tiles[i..<min(i + 3, tiles.count)]))
            row.spacing = 8
            rows.addArrangedSubview(row)
            i += 3
        }
        return rows
    }

    @objc private func searchChanged() {
        if !searchField.stringValue.isEmpty, shownShelf != nil { shownShelf = nil; selectInMenu(nil) }
        refilter()
    }

    @objc private func suitsChanged() { refilter() }

    private func selectInMenu(_ shelf: HabitatObjectDefinition.Shelf?) {
        if let i = shelfMenu.itemArray.firstIndex(where: { ($0.representedObject as? String) == shelf?.rawValue && !$0.isSeparatorItem }) { shelfMenu.selectItem(at: i) }
    }

    func debugSearch(_ q: String) { searchField.stringValue = q; searchChanged() }
    func debugSuits(_ on: Bool) { suitsBox.state = on ? .on : .off; refilter() }

    @objc private func shelfPicked() {
        showShelf((shelfMenu.selectedItem?.representedObject as? String).flatMap(HabitatObjectDefinition.Shelf.init(rawValue:)))
    }

    /// The Add tab showing only one part of it (nil: all of them).
    func showShelf(_ shelf: HabitatObjectDefinition.Shelf?) {
        shownShelf = shelf
        selectInMenu(shelf)
        refilter()
        scroll.documentView?.scroll(.zero)
    }

    /// The Add tab's tiles laid out again for what is being looked for:
    /// the part chosen, the search, and (if asked) this scenery.
    private func refilter() {
        let biome = controller?.scene.habitat.biome ?? .forest
        filteredBiome = biome
        suitsBox.title = "Suits \(biome.label)"
        suitsBox.toolTip = "Only what would be found in the \(biome.label) scenery"
        let query = searchField.stringValue
        let suits = suitsBox.state == .on
        var shown = false
        for sec in addSections {
            var any = false
            for g in sec.groups {
                let ks = g.kinds.filter { (query.isEmpty || $0.matches(query)) && (!suits || $0.suits(biome)) }
                for v in g.host.arrangedSubviews { g.host.removeArrangedSubview(v); v.removeFromSuperview() }
                let show = !ks.isEmpty && (shownShelf == nil || shownShelf == sec.shelf)
                if show { g.host.addArrangedSubview(tileRows(ks.compactMap { addTiles[$0] })) }
                g.host.isHidden = !show
                g.label?.isHidden = !show
                any = any || show
            }
            sec.header.isHidden = !any
            shown = shown || any
        }
        nothingNote.isHidden = shown
    }

    // MARK: Habitats

    private func habitatsPage(width: CGFloat) -> NSView {
        savedWidth = width
        saveButton.target = controller
        saveButton.action = #selector(HabitatController.saveHabitatAction)
        saveButton.toolTip = "Keep a copy of the tank as it is now, to come back to (⌘S)"
        saveNewButton.target = controller
        saveNewButton.action = #selector(HabitatController.saveHabitatAsNewAction)
        saveNewButton.toolTip = "Keep it as another habitat, leaving the one it came from as it was"
        importButton.target = controller
        importButton.action = #selector(HabitatController.importHabitatAction)
        importButton.iconOnly = true
        importButton.toolTip = "Bring in a habitat someone shared with you (a .\(HabitatLibrary.fileExtension) file)"
        let saveRow = NSStackView(views: [saveButton, saveNewButton, importButton])
        saveRow.spacing = 8
        saveRow.distribution = .fill
        // (Save takes what room there is.)
        saveButton.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        saveNewButton.setContentHuggingPriority(.required, for: .horizontal)
        importButton.setContentHuggingPriority(.required, for: .horizontal)
        saveRow.translatesAutoresizingMaskIntoConstraints = false
        saveRow.widthAnchor.constraint(equalToConstant: width).isActive = true
        savedHost.orientation = .vertical
        savedHost.alignment = .leading
        savedHost.spacing = 8
        savedEmpty = note("Nothing saved yet. The tank always stays as you leave it — save it here too, and you can try something new and come back to this whenever you like.", width: width)

        // Ready-made: each the whole tank, end to end, so a row each.
        let world = controller?.scene.habitat.size ?? HabitatLayout.defaultWorld
        let thumb = CGSize(width: width - 12, height: ((width - 12) * min(world.height / world.width, 0.36)).rounded())
        let tiles = Habitat.Preset.allCases.map { p -> NSView in
            let t = TileButton(image: NSImage(size: thumb), title: p.label, subtitle: nil, imageSize: thumb)
            t.onClick = { [weak self] in self?.controller?.loadPreset(p) }
            t.toolTip = "Start again from \(p.label) (you can undo it)"
            paintLater(t) { HabitatArt.habitatThumbnail(Habitat.preset(p, world: world), size: thumb) }
            return t
        }
        let shuffle = HabitatButton(title: "Surprise Me", symbol: "dice")
        shuffle.target = self
        shuffle.action = #selector(shuffleTapped)
        shuffle.toolTip = "A new tank, laid out at random"
        let clear = HabitatButton(title: "Empty the Tank", symbol: "trash")
        clear.destructive = true
        clear.target = self
        clear.action = #selector(clearTapped)
        clear.toolTip = "Take everything out (you can undo it)"
        let p = page([sectionLabel("My Habitats"), saveRow, savedEmpty, savedHost,
                      sectionLabel("Start Afresh"), PanelKit.row([shuffle, clear], width: width),
                      note("Or start from a ready-made tank — save yours first if you want to keep it.", width: width),
                      grid(tiles, columns: 1, width: width)])
        p.setCustomSpacing(20, after: savedHost)
        p.setCustomSpacing(20, after: savedEmpty)
        reloadSaved()
        return p
    }

    /// My Habitats laid out afresh, from the library.
    private func reloadSaved() {
        for v in savedHost.arrangedSubviews { savedHost.removeArrangedSubview(v); v.removeFromSuperview() }
        savedCards = HabitatLibrary.all().map { s in
            let card = SavedHabitatCard(s, width: savedWidth)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.widthAnchor.constraint(equalToConstant: savedWidth).isActive = true
            card.onLoad = { [weak self] in self?.controller?.loadSaved(id: s.id) }
            card.onMenu = { [weak self] from in self?.controller?.showSavedMenu(id: s.id, from: from) }
            savedHost.addArrangedSubview(card)
            return card
        }
        savedEmpty.isHidden = !savedCards.isEmpty
        savedHost.isHidden = savedCards.isEmpty
        refreshSaved()
    }

    /// Which of My Habitats is in the tank, and whether it has been changed
    /// since: the Save button says what it will do.
    private func refreshSaved() {
        guard let c = controller else { return }
        let current = c.currentSaved
        for card in savedCards { card.current = card.saved.id == current?.saved.id }
        if let cur = current, cur.changed {
            saveButton.set(title: "Save Changes", symbol: "square.and.arrow.down")
            saveButton.toolTip = "Keep the changes in “\(cur.saved.name)” (⌘S)"
            saveNewButton.isHidden = false
        } else {
            saveButton.set(title: current == nil ? "Save This Habitat" : "Saved", symbol: current == nil ? "square.and.arrow.down" : "checkmark")
            saveButton.toolTip = current == nil ? "Keep a copy of the tank as it is now, to come back to (⌘S)" : "“\(current!.saved.name)” is saved just as it is"
            saveNewButton.isHidden = current == nil
        }
        saveButton.isEnabled = current?.changed ?? true
    }

    /// Tools only: the Habitats tab.
    func debugShowHabitats() { debugShowTab(Tab.habitats.rawValue) }

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
        supportIcon.translatesAutoresizingMaskIntoConstraints = false
        supportIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        supportLabel.font = .systemFont(ofSize: 11.5)
        supportLabel.textColor = NSColor(white: 1, alpha: 0.7)
        supportLabel.lineBreakMode = .byTruncatingTail
        let line = NSStackView(views: [supportIcon, supportLabel])
        line.spacing = 6
        supportLine = line
        supportButton.target = self
        supportButton.action = #selector(supportTapped)
        supportButton.toolTip = "Prop it up from below — or, with a backing wall behind it, fix it to that"
        openButton.target = self
        openButton.action = #selector(openTapped)
        openButton.toolTip = "Open or shut it (or double-click it in the tank)"
        let r1 = NSStackView(views: [flipButton, copyButton, layerButton, removeButton])
        r1.distribution = .fillEqually
        r1.spacing = 6
        r1.translatesAutoresizingMaskIntoConstraints = false
        r1.widthAnchor.constraint(equalToConstant: width - 24).isActive = true
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = NSColor(white: 1, alpha: 0.55)
        hint.stringValue = "Click something in the tank to move it, resize it or take it out."
        hint.toolTip = "Drag a corner to resize. Pieces click together where they meet (hold ⌥ to place freely). Double-click a door to open it. Drag the bare glass to look round the tank. ⌘Z undoes."
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.widthAnchor.constraint(equalToConstant: width - 24).isActive = true
        for v in [top, supportLine, supportButton, openButton, sizeRow, r1, hint] as [NSView] { inspector.addArrangedSubview(v) }
    }

    @objc private func tabChanged() { showPage(tabs.selectedSegment) }

    /// Shows a tab (tools, and the tour).
    func debugShowTab(_ i: Int) {
        tabs.selectedSegment = i
        showPage(i)
    }

    func showTab(_ t: Tab) { debugShowTab(t.rawValue) }

    /// Where a tab is, in the panel (for the tour to point at).
    func tabRect(_ t: Tab) -> CGRect {
        let w = tabs.bounds.width / CGFloat(DecorPanel.tabNames.count)
        return convert(CGRect(x: w * CGFloat(t.rawValue), y: 0, width: w, height: tabs.bounds.height), from: tabs)
    }
    var inspectorView: NSView { inspector }
    var undoView: NSView { undoButton }
    var savedArea: NSView { saveButton.superview ?? saveButton }

    private func showPage(_ i: Int) {
        for (k, p) in pages.enumerated() { p.isHidden = k != i }
        if i == Tab.habitats.rawValue { refreshSaved() }
        scroll.documentView?.scroll(.zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Back in step with the tank.
    func refresh() {
        guard built, let c = controller else { return }
        let h = c.scene.habitat
        for (b, t) in zip(Biome.allCases, biomeTiles) { t.selected = b == h.biome }
        if filteredBiome != h.biome, !addSections.isEmpty { refilter() }
        if pages.count > 2, !pages[Tab.habitats.rawValue].isHidden { refreshSaved() }
        undoButton.isEnabled = c.canUndo
        redoButton.isEnabled = c.canRedo
        let item = c.scene.selected.flatMap { id in h.items.first { $0.id == id } }
        for v in inspector.arrangedSubviews where v !== hint { v.isHidden = item == nil }
        hint.isHidden = item != nil
        guard let it = item else { return }
        selName.stringValue = it.kind.label
        let fn = it.kind.functions
        selKind.stringValue = it.kind.atBack ? (it.kind.climbable ? "Support — at the back; it can climb this" : "Support — at the back")
            : fn.contains(.retreat) ? "A shelter — it can get right inside"
            : fn.contains(.cover) && it.kind.climbable ? "Cover — a roof to get under"
            : !fn.isEmpty ? "For " + HabitatFunction.allCases.filter(fn.contains).map(\.label).joined(separator: " and ")
            : it.kind.loose != nil ? "Loose — light enough to blow about"
            : (it.kind.climbable ? "A perch — it can climb this" : "Scenery")
        let (text, symbol, floating) = supportText(h, it)
        supportLabel.stringValue = text
        supportLabel.toolTip = text
        supportLabel.textColor = floating ? NSColor.systemOrange.withAlphaComponent(0.95) : NSColor(white: 1, alpha: 0.7)
        supportIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        supportIcon.contentTintColor = floating ? .systemOrange : NSColor(white: 1, alpha: 0.6)
        // (Only where one can be made for it.)
        var trial = h
        supportButton.isHidden = !(floating && !trial.addSupport(for: it.id).isEmpty)
        if let other = it.kind.toggled {
            let opens = other == .door || other == .windowOpen
            openButton.isHidden = false
            openButton.set(title: opens ? "Open It" : "Shut It", symbol: opens ? "door.left.hand.open" : "door.left.hand.closed")
        } else {
            openButton.isHidden = true
        }
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

    /// What holds a thing up, in words: and its symbol, and whether it is floating.
    private func supportText(_ h: Habitat, _ it: HabitatItem) -> (String, String, Bool) {
        func name(_ id: Int) -> String { h.item(id: id).map { "the " + $0.kind.label.lowercased() } ?? "something" }
        switch h.support(of: it.id) {
        case .ground: return ("On the ground", "arrow.down.to.line", false)
        case .lid: return ("Hanging from the lid", "arrow.up.to.line", false)
        case .wall:
            if it.kind.isBacking { return ("Against the glass at the back", "square.grid.3x3.square", false) }
            if h.isBacked(it), let wall = h.items.first(where: { $0.kind.isBacking && $0.rect.contains(CGPoint(x: it.rect.midX, y: it.rect.midY)) }) {
                return ("Fixed to the \(wall.kind.label.lowercased()) behind it", "hammer", false)
            }
            return ("Stuck to the glass at the back (suction cups)", "circle.dotted", false)
        case .glass: return ("Wedged against the glass", "rectangle.portrait", false)
        case .held(let by): return ("Held by \(name(by))", "link", false)
        case .resting(let on): return ("Resting on \(name(on))", "square.stack.3d.down.forward", false)
        case .wedged(let into): return ("Propped against \(name(into))", "arrow.triangle.merge", false)
        case .floating: return ("Floating — nothing holds it up", "exclamationmark.triangle", true)
        }
    }

    @objc private func supportTapped() { controller?.scene.supportSelected() }
    @objc private func openTapped() { if let id = controller?.scene.selected { controller?.scene.toggleOpen(id) } }

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
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = subtitle == nil && imageSize.width < 80 && titleSize >= 11.5 ? 0 : 6
        imageView.layer?.masksToBounds = true
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
        // (Laid out by hand, not with a stack and constraints: the Add page
        // has a couple of hundred of these, and all that layout bookkeeping
        // came to tens of megabytes.)
        for v in [imageView, label, sub] { addSubview(v) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ img: NSImage) { imageView.image = img }

    private var hasSub: Bool { !sub.isHidden }
    private var labelHeight: CGFloat { ceil((label.font?.boundingRectForFont.height ?? 14) * 0.95) }
    private static let subHeight: CGFloat = 26

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 6 + imageSize.height + 4 + labelHeight + (hasSub ? 4 + TileButton.subHeight : 0) + 7)
    }

    override func layout() {
        super.layout()
        // (From the top down: it is not flipped.)
        var y = bounds.height - 6 - imageSize.height
        imageView.frame = CGRect(x: ((bounds.width - imageSize.width) / 2).rounded(), y: y, width: imageSize.width, height: imageSize.height)
        y -= 4 + labelHeight
        let w = bounds.width - 12
        label.frame = CGRect(x: 6, y: y, width: w, height: labelHeight)
        if hasSub {
            y -= 4 + TileButton.subHeight
            sub.frame = CGRect(x: 6, y: y, width: w, height: TileButton.subHeight)
        }
    }

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

    // (Its rounded background is the layer's own — not drawn into a bitmap
    // of its own, which with a couple of hundred tiles on the Add page came
    // to tens of megabytes.)
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let l = layer else { return }
        l.cornerRadius = 10
        l.backgroundColor = NSColor(white: 1, alpha: pressed ? 0.16 : (hovering ? 0.11 : 0.05)).cgColor
        l.borderWidth = selected ? 2 : 1
        l.borderColor = selected ? NSColor.controlAccentColor.cgColor : NSColor(white: 1, alpha: 0.07).cgColor
    }
}
