import AppKit
import QuartzCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow!
    private var view: SpiderView!
    private var silkWindow: OverlayWindow!
    private var silkView: SilkView!
    private var silkVisible = false
    private var hammockWindow: OverlayWindow!
    private var hammockView: HammockView!
    private var preyWindow: OverlayWindow!
    private var preyView: PreyView!
    private var preyShown = false
    private var hammockShown = false
    private var hammockTear: CGFloat = 0
    private var lastHammock: Hammock?
    private var lastWipeCursor = V2(-9999, -9999)
    private let map = SurfaceMap()
    private var spider: Spider!
    private let tracker = WindowTracker()
    private var statusItem: NSStatusItem!
    private var studio: StudioController?

    private var displayLink: Any?
    private var fallbackTimer: Timer?
    private var lastTime: CFTimeInterval = 0
    private var lastFrame: CFTimeInterval = 0
    /// When nothing has actually changed for a second — asleep, or just
    /// sitting there — the clock drops to a third of the display rate.
    private var calm = false
    private var calmSkip = 0
    private var calmFrames = 0
    private var lastCursor = V2(-9999, -9999)
    // SPIDER_STATS=1 prints a frame budget breakdown once a second.
    private let stats = ProcessInfo.processInfo.environment["SPIDER_STATS"] == "1"
    private var statFrames = 0
    private var statUpdate: CFTimeInterval = 0
    private var statApply: CFTimeInterval = 0
    private var statWindow: CFTimeInterval = 0
    private var statSince: CFTimeInterval = 0
    private var interactive = true
    private var hidden = false

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        spider = Spider(map: map)
        spider.apply(design: SpiderDesign.load())
        loadSettings()
        map.standoff = AppDelegate.standoff(for: spider.config.scale)
        map.rebuild(windows: [])

        buildWindow()
        buildStatusItem()
        applyWindowSize()
        let saved = UserDefaults.standard.integer(forKey: "hammock")   // 0 none, 1 left, 2 right
        if saved == 1 || saved == 2 { spider.restoreHammock(left: saved == 1) }
        if hidden {
            window.orderOut(nil)
            statusItem.button?.appearsDisabled = true
        }

        tracker.onUpdate = { [weak self] windows, fullScreen in
            guard let self else { return }
            self.map.rebuild(windows: windows)
            self.spider.fullScreenApp = fullScreen
        }
        tracker.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(showContextMenu(_:)),
            name: .spiderContextMenu, object: nil)

        startClock()
        // SPIDER_STUDIO=1 opens the studio straight away (handy for testing).
        if ProcessInfo.processInfo.environment["SPIDER_STUDIO"] == "1" { openStudio() }
        // SPIDER_STUDIO_SHOT=dir writes one PNG per studio tab there, then quits.
        if let dir = ProcessInfo.processInfo.environment["SPIDER_STUDIO_SHOT"] {
            openStudio()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                for i in 0..<8 { self?.studio?.snapshot(to: "\(dir)/studio_tab\(i).png", tab: i) }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.stop()
        fallbackTimer?.invalidate()
    }

    /// The sprite is just big enough for this size of spider with its legs
    /// splayed and an emote overhead. The window is bigger by `windowSlack`, so
    /// the spider can wander inside it and the window only needs moving every
    /// so often instead of sixty times a second.
    private var spriteSide: CGFloat = 160
    private var side: CGFloat = 228
    private static let windowSlack: CGFloat = 68
    private var recentreAt: CGFloat { AppDelegate.windowSlack / 2 - 4 }

    /// Height of the body origin above the ledge, so the feet land on the edge.
    static func standoff(for scale: CGFloat) -> CGFloat { -SpiderRenderer.ground * scale }

    private func buildWindow() {
        spriteSide = SpiderRenderer.spriteSide(for: spider.config.scale)
        side = spriteSide + AppDelegate.windowSlack
        window = OverlayWindow(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view = SpiderView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.spider = spider
        window.contentView = view
        window.orderFrontRegardless()

        // Silk needs to reach across the desktop, so it gets its own
        // screen-sized window that stays hidden unless a thread is out.
        let frame = worldFrame()
        preyWindow = OverlayWindow(frame: frame)
        preyView = PreyView(frame: CGRect(origin: .zero, size: frame.size))
        preyView.worldOrigin = frame.origin
        preyWindow.contentView = preyView
        preyWindow.ignoresMouseEvents = true
        silkWindow = OverlayWindow(frame: frame)
        silkView = SilkView(frame: CGRect(origin: .zero, size: frame.size))
        silkView.worldOrigin = frame.origin
        silkWindow.contentView = silkView
        silkWindow.ignoresMouseEvents = true

        // The hammock sits above the spider so it is seen through the silk.
        hammockWindow = OverlayWindow(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
        hammockWindow.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        hammockView = HammockView(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
        hammockWindow.contentView = hammockView
        hammockWindow.ignoresMouseEvents = true
    }

    private func worldFrame() -> CGRect {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        return union.isNull ? CGRect(x: 0, y: 0, width: 1440, height: 900) : union
    }

    @objc private func screensChanged() {
        let frame = worldFrame()
        silkWindow.setFrame(frame, display: false)
        preyWindow.setFrame(frame, display: false)
        preyView.frame = CGRect(origin: .zero, size: frame.size)
        preyView.worldOrigin = frame.origin
        silkView.frame = CGRect(origin: .zero, size: frame.size)
        silkView.worldOrigin = frame.origin
        map.rebuild(windows: [])
        spider.refitHammock()
    }

    // MARK: Frame clock

    private func startClock() {
        lastTime = CACurrentMediaTime()
        if #available(macOS 14.0, *) {
            let link = view.displayLink(target: self, selector: #selector(tick))
            // Ask for 60 Hz outright. Gating a 120 Hz link by elapsed time
            // instead gives alternating 16 ms and 25 ms steps, which reads as
            // stutter in anything that moves smoothly.
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            fallbackTimer = t
        }
    }

    @objc private func tick() {
        guard !hidden else { return }
        let now = CACurrentMediaTime()

        // Whether clicks reach us is decided every tick, throttled or not: a
        // stale decision here is a spider you cannot pick up.
        let cursorNow = V2(NSEvent.mouseLocation)
        let wantsMouseNow = interactive && (spider.isHeld || spider.hitTest(cursorNow))
        if window.ignoresMouseEvents == wantsMouseNow {
            window.ignoresMouseEvents = !wantsMouseNow
        }

        // The calm throttle skips whole frames; the active rate is the link's.
        if calm {
            calmSkip += 1
            guard calmSkip % 3 == 0 else { return }
        }
        lastFrame = now
        let dt = CGFloat(min(max(now - lastTime, 1.0 / 240.0), 1.0 / 20.0))
        lastTime = now

        let cursor = V2(NSEvent.mouseLocation)
        if cursor.distance(to: lastCursor) > 0.4 {
            lastCursor = cursor
            spider.setCursor(cursor)
        }
        // Wiping the pointer across the hammock tears it down.
        if spider.hammock != nil {
            let moved = lastWipeCursor.x > -9000 ? cursor.distance(to: lastWipeCursor) : 0
            if moved > 0.5, interactive { spider.wipeHammock(at: cursor, movement: min(moved, 80)) }
        }
        lastWipeCursor = cursor

        if stats {
            let a = CACurrentMediaTime()
            spider.update(dt: dt)
            let b = CACurrentMediaTime()
            let pose = spider.pose()
            let moved = place(pose)
            view.apply(pose)
            settle(moved: moved)
            let c = CACurrentMediaTime()
            let d = CACurrentMediaTime()
            statUpdate += b - a
            statApply += c - b
            statWindow += d - c
            statFrames += 1
            if statSince == 0 { statSince = a }
            if a - statSince > 1 {
                let elapsed = a - statSince
                let f = Double(statFrames)
                print(String(format: "%.0f fps | update %.2fms | apply %.2fms | winmove %.3fms",
                             f / elapsed, statUpdate / f * 1000, statApply / f * 1000,
                             statWindow / f * 1000))
                fflush(stdout)
                statFrames = 0; statUpdate = 0; statApply = 0; statWindow = 0; statSince = a
            }
        } else {
            spider.update(dt: dt)
            let pose = spider.pose()
            let moved = place(pose)
            view.apply(pose)
            settle(moved: moved)
        }
        updateHammock(dt: dt)
        updatePrey()

        // Only swallow clicks when the pointer is actually on the spider.
        let wantsMouse = interactive && (spider.isHeld || spider.hitTest(cursor))
        if window.ignoresMouseEvents == wantsMouse {
            window.ignoresMouseEvents = !wantsMouse
        }
    }

    /// Keeps the follower window centred on the spider. The window origin is
    /// rounded to whole points and the fraction is left to the layer, so motion
    /// stays smooth instead of stepping.
    /// Throttles the clock once the picture stops changing, and snaps straight
    /// back to full rate the moment it does.
    private func settle(moved: Bool) {
        if moved || view.didRedraw || spider.isHeld {
            calmFrames = 0
            calm = false
        } else {
            calmFrames += 1
            if calmFrames > 45 { calm = true }
        }
    }

    @discardableResult
    private func place(_ pose: SpiderPose) -> Bool {
        var moved = false
        let frame = window.frame
        let centre = V2(frame.midX, frame.midY)
        // Re-centre only once it has drifted. This runs before the sprite is
        // positioned, so the sprite can never end up outside the window.
        if abs(pose.pos.x - centre.x) > recentreAt || abs(pose.pos.y - centre.y) > recentreAt {
            let origin = CGPoint(x: (pose.pos.x - side / 2).rounded(),
                                 y: (pose.pos.y - side / 2).rounded())
            window.setFrameOrigin(origin)
            // Use where the window actually ended up, not where we asked: if
            // the system nudged it, drawing and hit-testing must follow.
            view.worldOrigin = window.frame.origin
            moved = true
        }

        let wantSilk = pose.web != nil || pose.dragline != nil
        if wantSilk {
            silkView.apply(pose)
            if !silkVisible {
                silkVisible = true
                silkWindow.order(.below, relativeTo: window.windowNumber)
            }
        } else if silkVisible {
            silkVisible = false
            _ = silkView.apply(pose)
            silkWindow.orderOut(nil)
        }
        return moved || wantSilk
    }

    /// Shows, redraws, tears down and remembers the hammock.
    private func updateHammock(dt: CGFloat) {
        let h = spider.hammock
        if h != lastHammock {
            if let h {
                if !hammockShown || h.rect != hammockWindow.frame {
                    hammockWindow.setFrame(h.rect, display: false)
                    hammockView.frame = CGRect(origin: .zero, size: h.rect.size)
                }
                hammockView.hammock = h
                if !hammockShown {
                    hammockShown = true
                    hammockWindow.orderFrontRegardless()
                }
                let code = h.progress >= 1 ? (h.left ? 1 : 2) : 0
                if UserDefaults.standard.integer(forKey: "hammock") != code {
                    UserDefaults.standard.set(code, forKey: "hammock")
                }
            } else if lastHammock != nil {
                // Torn away: let the loose threads fade.
                hammockTear = 1
                hammockView.hammock = nil
                hammockView.tear = 1
                UserDefaults.standard.set(0, forKey: "hammock")
                calmFrames = 0
                calm = false
            }
            let hadHammock = lastHammock.map { $0.progress >= 1 } ?? false
            lastHammock = h
            if hadHammock != spider.hasHammock { refreshMenu() }
        }
        if h == nil, hammockShown {
            hammockTear = max(0, hammockTear - dt * 1.4)
            hammockView.tear = hammockTear
            if hammockTear <= 0 {
                hammockShown = false
                hammockWindow.orderOut(nil)
            }
        }
    }

    private func updatePrey() {
        let prey = spider.prey
        if prey.isEmpty {
            if preyShown {
                preyShown = false
                preyView.prey = []
                preyView.refresh()
                preyWindow.orderOut(nil)
            }
            return
        }
        preyView.prey = prey
        preyView.refresh()
        if !preyShown {
            preyShown = true
            preyWindow.order(.below, relativeTo: window.windowNumber)
        }
    }

    @objc private func feed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int, let kind = PreyKind(rawValue: raw) else { return }
        // Not too many at once.
        guard spider.prey.filter({ $0.state == .loose }).count < 4 else { return }
        spider.release(kind)
        calmFrames = 0
        calm = false
    }

    // MARK: Status item + menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = SpiderRenderer.statusItemImage(size: 17)
        statusItem.button?.toolTip = spider.name
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let name = spider.name.isEmpty ? "Spider" : spider.name
        let toggle = NSMenuItem(title: hidden ? "Show \(name)" : "Hide \(name)",
                                action: #selector(toggleHidden), keyEquivalent: "h")
        toggle.target = self
        toggle.keyEquivalentModifierMask = []
        menu.addItem(toggle)
        add(menu, "Spider Studio…", #selector(openStudio), key: ",")
        menu.addItem(.separator())

        add(menu, "Come Here", #selector(comeHere))
        add(menu, "Say Hi", #selector(sayHi))
        add(menu, "Toss It", #selector(toss))
        add(menu, "Swing!", #selector(swing))
        let feedMenu = NSMenu()
        for kind in PreyKind.allCases {
            let item = NSMenuItem(title: "Release a \(kind.label)", action: #selector(feed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            feedMenu.addItem(item)
        }
        let feedItem = NSMenuItem(title: "Feed", action: nil, keyEquivalent: "")
        feedItem.submenu = feedMenu
        menu.addItem(feedItem)
        menu.addItem(.separator())
        if spider.hasHammock {
            add(menu, "Nap in the Hammock", #selector(nap))
            add(menu, "Clear the Hammock", #selector(clearHammock))
        } else {
            add(menu, "Build a Hammock", #selector(buildHammock))
        }
        menu.addItem(.separator())

        let size = NSMenu()
        let sizes: [(String, CGFloat)] = [("Tiny", 0.62), ("Small", 0.78), ("Medium", 0.95),
                                          ("Large", 1.2), ("Chonky", 1.55)]
        for (name, s) in sizes {
            let item = NSMenuItem(title: name, action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s
            item.state = abs(spider.config.scale - s) < 0.01 ? .on : .off
            size.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = size
        menu.addItem(sizeItem)

        let energy = NSMenu()
        let levels: [(String, CGFloat)] = [("Sleepy", 0.5), ("Calm", 0.8), ("Normal", 1.0),
                                           ("Playful", 1.5), ("Caffeinated", 2.4)]
        for (name, s) in levels {
            let item = NSMenuItem(title: name, action: #selector(setEnergy(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s
            item.state = abs(spider.personality.liveliness - s) < 0.02 ? .on : .off
            energy.addItem(item)
        }
        let energyItem = NSMenuItem(title: "Energy", action: nil, keyEquivalent: "")
        energyItem.submenu = energy
        menu.addItem(energyItem)
        menu.addItem(.separator())

        add(menu, "Follow the Cursor", #selector(toggleFollow), state: spider.config.followCursor)
        add(menu, "Spin Webs", #selector(toggleWebs), state: spider.config.webs)
        add(menu, "Click to Pick Up", #selector(toggleInteractive), state: interactive)
        add(menu, "Pause", #selector(togglePause), state: spider.config.paused)
        menu.addItem(.separator())
        add(menu, "Launch at Login", #selector(toggleLogin), state: loginEnabled)
        menu.addItem(.separator())
        add(menu, "Quit Spider", #selector(quit), key: "q")
        return menu
    }

    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector,
                     key: String = "", state: Bool? = nil) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = self
        if let s = state { item.state = s ? .on : .off }
        menu.addItem(item)
    }

    private func refreshMenu() {
        statusItem.menu = buildMenu()
    }

    @objc private func showContextMenu(_ note: Notification) {
        let menu = buildMenu()
        if let event = note.object as? NSEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }
    }

    // MARK: Actions

    @objc private func toggleHidden() {
        hidden.toggle()
        if hidden {
            window.orderOut(nil)
            silkWindow.orderOut(nil)
            silkVisible = false
            hammockWindow.orderOut(nil)
        } else {
            window.orderFrontRegardless()
            if hammockShown { hammockWindow.orderFrontRegardless() }
            lastTime = CACurrentMediaTime()
            spider.reappear()
        }
        statusItem.button?.appearsDisabled = hidden
        statusItem.button?.toolTip = hidden ? "\(spider.name) (hidden)" : spider.name
        saveSettings()
        refreshMenu()
    }

    @objc private func comeHere() { spider.summon(to: V2(NSEvent.mouseLocation)) }
    @objc private func swing() { spider.debugActivity("swing", for: 0) }
    @objc private func nap() { spider.napInHammock() }
    @objc private func buildHammock() { spider.buildHammock() }
    @objc private func clearHammock() { spider.clearHammock() }
    @objc private func sayHi() { spider.celebrate() }

    @objc private func toss() {
        spider.beginGrab(at: spider.worldPos)
        spider.endGrab(throwVelocity: V2(randRange(-700, 700), randRange(700, 1300)))
    }

    @objc private func setSize(_ item: NSMenuItem) {
        guard let s = item.representedObject as? CGFloat else { return }
        spider.config.scale = s
        applyWindowSize()
        saveSettings()
        refreshMenu()
    }

    private func applyWindowSize() {
        map.standoff = AppDelegate.standoff(for: spider.config.scale)
        spriteSide = SpiderRenderer.spriteSide(for: spider.config.scale)
        side = spriteSide + AppDelegate.windowSlack
        view.resize(sprite: spriteSide, window: side)
        window.setContentSize(CGSize(width: side, height: side))
        view.worldOrigin = window.frame.origin
    }

    @objc private func setEnergy(_ item: NSMenuItem) {
        guard let s = item.representedObject as? CGFloat else { return }
        // The quick menu just moves the energy slider.
        var d = spider.design
        d.personality.energy = clamp(remap(s, 0.45, 2.4, 0, 1), 0, 1)
        spider.apply(design: d)
        d.save()
        saveSettings()
        refreshMenu()
    }

    @objc private func openStudio() {
        if studio == nil {
            let st = StudioController(design: spider.design)
            st.onChange = { [weak self] d in
                guard let self else { return }
                self.spider.apply(design: d)
                d.save()
                self.refreshMenu()
                self.statusItem.button?.toolTip = d.name
            }
            st.onScale = { [weak self] s in
                guard let self else { return }
                self.spider.config.scale = s
                self.applyWindowSize()
                self.saveSettings()
                self.refreshMenu()
            }
            studio = st
        }
        studio?.scale = spider.config.scale
        studio?.show()
    }

    @objc private func toggleFollow() {
        spider.config.followCursor.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func toggleWebs() {
        spider.config.webs.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func toggleInteractive() {
        interactive.toggle()
        if !interactive { window.ignoresMouseEvents = true }
        saveSettings(); refreshMenu()
    }

    @objc private func togglePause() {
        spider.config.paused.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Launch at login

    private var loginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                NSSound.beep()
            }
            refreshMenu()
        }
    }

    // MARK: Settings

    private func saveSettings() {
        let d = UserDefaults.standard
        d.set(Double(spider.config.scale), forKey: "scale")
        d.set(spider.config.followCursor, forKey: "followCursor")
        d.set(spider.config.webs, forKey: "webs")
        d.set(spider.config.paused, forKey: "paused")
        d.set(interactive, forKey: "interactive")
        d.set(hidden, forKey: "hidden")
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "scale": 0.95, "liveliness": 1.0, "followCursor": true,
            "webs": true, "paused": false, "interactive": true, "hidden": false,
        ])
        spider.config.scale = CGFloat(d.double(forKey: "scale"))
        spider.config.followCursor = d.bool(forKey: "followCursor")
        spider.config.webs = d.bool(forKey: "webs")
        spider.config.paused = d.bool(forKey: "paused")
        interactive = d.bool(forKey: "interactive")
        hidden = d.bool(forKey: "hidden")
    }
}
