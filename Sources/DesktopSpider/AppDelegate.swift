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
    private var cinemaScreens: [CGRect] = []
    private var cinemaClearPolls = 0
    private var boxDrawWindow: BoxDrawWindow?
    private var laserOn = false
    private var laserWindow: OverlayWindow!
    private var laserView: LaserView!
    private var laserMonitors: [Any] = []
    private var laserOffAt: CFTimeInterval = 0
    private var laserHeld = false
    private var boxWindow: OverlayWindow!
    private var boxOutline: BoxOutlineView!
    private var hammockShown = false
    private var hammockTear: CGFloat = 0
    private var lastHammock: Hammock?
    private var lastWipeCursor = V2(-9999, -9999)
    private let map = SurfaceMap()
    private var spider: Spider!
    private let tracker = WindowTracker()
    private var statusItem: NSStatusItem!
    private let updater = Updater()
    private var studio: StudioController?
    private var habitat: HabitatController?
    /// Living in the habitat window; the desktop overlays are put away.
    private var inHabitat = false
    private var habitatLastTime: CFTimeInterval = 0

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
    /// SPIDER_CINEMA_LOG=1 prints when a display is taken by a full-screen app, and given back.
    private let cinemaLog = ProcessInfo.processInfo.environment["SPIDER_CINEMA_LOG"] == "1"
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
        if saved % 10 == 1 || saved % 10 == 2 {
            spider.restoreHammock(left: saved % 10 == 1, style: HammockStyle(rawValue: (saved / 10) % 10) ?? .sling,
                                  seed: saved / 100)
        }
        if let b = UserDefaults.standard.array(forKey: "confine") as? [Double], b.count == 4 {
            applyBox(CGRect(x: b[0], y: b[1], width: b[2], height: b[3]))
        }
        if hidden {
            window.orderOut(nil)
            statusItem.button?.appearsDisabled = true
        }

        tracker.onUpdate = { [weak self] windows, fullScreens in
            guard let self else { return }
            var windows = windows
            if self.tankGate, let hc = self.habitat {
                windows.insert(TrackedWindow(id: self.tankWindowID, frame: hc.window.frame, depth: -1, owner: "Habitat"), at: 0)
            }
            // Entering full screen counts at once; leaving it only after a
            // few quiet polls, so a player's controls flickering over the
            // video cannot keep unsettling the spider.
            let cinemaWas = self.cinemaScreens
            if !fullScreens.isEmpty {
                self.cinemaScreens = fullScreens
                self.cinemaClearPolls = 0
            } else if self.cinemaScreens.isEmpty == false {
                self.cinemaClearPolls += 1
                if self.cinemaClearPolls >= 4 { self.cinemaScreens = [] }
            }
            self.map.rebuild(windows: windows, cinema: self.cinemaScreens)
            // The rim of a taken screen is a different set of edges: the
            // spider re-reads its footing from where it stands rather than
            // carrying its place over by index and jumping.
            if self.cinemaScreens != cinemaWas {
                self.spider.surfacesRestructured()
                if self.cinemaLog { fputs("cinema: \(self.cinemaScreens.isEmpty ? "over" : "\(self.cinemaScreens)") — \(self.spider.debugState)\n", stderr) }
            }
            self.spider.fullScreenApp = !self.cinemaScreens.isEmpty
        }
        tracker.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(showContextMenu(_:)),
            name: .spiderContextMenu, object: nil)

        startClock()
        // Back into the tank if that is where it was.
        if UserDefaults.standard.bool(forKey: "inHabitat") { enterHabitat() }
        // SPIDER_HABITAT_TEST=1 runs the habitat through its paces on the real
        // clock (in, out, in again, the window closed and reopened, every kind
        // of furniture added, the window resized) and quits; a crash shows up
        // as a crash.
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_TEST"] == "1" {
            func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
            after(0.5) { [weak self] in
                guard let self else { return }
                self.enterHabitat()
                after(5) {
                    print("habitat test: in  -> inHabitat \(self.inHabitat), \(self.spider.debugState)")
                    self.leaveHabitat()
                    after(1.5) {
                        print("habitat test: out -> inHabitat \(self.inHabitat), \(self.spider.debugState)")
                        self.enterHabitat()
                        after(5) {
                            self.habitat?.window.performClose(nil)
                            after(1.5) {
                                print("habitat test: closed -> inHabitat \(self.inHabitat), \(self.spider.debugState)")
                                self.enterHabitat()
                                after(5) {
                                    guard let hc = self.habitat, self.inHabitat else { print("habitat test: not in"); NSApp.terminate(nil); return }
                                    let keep = hc.view.habitat
                                    hc.view.onChange = nil
                                    hc.view.building = true
                                    for k in HabitatItemKind.allCases { hc.view.add(k) }
                                    hc.view.updateSelected { $0.w *= 2; $0.h *= 2 }
                                    hc.view.duplicateSelected()
                                    hc.view.removeSelected()
                                    hc.window.setContentSize(CGSize(width: 760, height: 480)); hc.view.layout()
                                    after(1) {
                                        hc.window.setContentSize(CGSize(width: 1200, height: 700)); hc.view.layout()
                                        hc.view.building = false
                                        for kind in PreyKind.allCases { self.spider.release(kind) }
                                        after(8) {
                                            print("habitat test: furniture \(hc.view.habitat.items.count), prey \(self.spider.prey.count), state \(self.spider.debugState), in scene \(hc.view.screenScene.insetBy(dx: -40, dy: -40).contains(self.spider.worldPos.point))")
                                            hc.view.habitat = keep
                                            keep.save()
                                            // Dragged out of the tank by hand: it comes out, then wants back in.
                                            let out = V2(hc.window.frame.minX - 160, hc.window.frame.midY)
                                            self.spider.beginGrab(at: self.spider.worldPos)
                                            var step = 0
                                            let from = self.spider.worldPos
                                            Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
                                                step += 1
                                                let u = CGFloat(min(step, 60)) / 60
                                                self.spider.moveGrab(to: V2.lerp(from, out, u))
                                                if step >= 70 { t.invalidate(); self.spider.endGrab(throwVelocity: .zero) }
                                            }
                                            after(2.5) {
                                                print("habitat test: dragged out -> inHabitat \(self.inHabitat), gate \(self.tankGate), \(self.spider.debugState) at \(Int(self.spider.worldPos.x)),\(Int(self.spider.worldPos.y))")
                                                after(25) {
                                                    print("habitat test: back? -> inHabitat \(self.inHabitat), \(self.spider.debugState)")
                                                    self.leaveHabitat()
                                                    after(1.5) {
                                                        print("habitat test: done -> inHabitat \(self.inHabitat), \(self.spider.debugState)")
                                                        NSApp.terminate(nil)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // SPIDER_HABITAT_LIVE=1 enters the habitat and lets the real clock run
        // for a while, then reports whether anything moved, and quits.
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_LIVE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                if ProcessInfo.processInfo.environment["SPIDER_HABITAT_FAR"] == "1", let f = NSScreen.main?.frame {
                    // Start on the floor, far from where the tank will be.
                    self.spider.teleport(to: V2(f.maxX - 120, f.maxY - 60))
                }
                let before = self.spider.debugState
                self.enterHabitat()
                for i in 1...40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                        print("habitat live: t=\(Double(i) * 0.5) -> \(self.spider.debugState) at \(Int(self.spider.worldPos.x)),\(Int(self.spider.worldPos.y)) transitioning \(self.transitioning) in \(self.inHabitat) hidden \(self.hidden) paused \(self.spider.config.paused) ticks \(self.tickCount) (was \(before)) tank \(self.habitat?.window.frame ?? .zero)")
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 21.0) {
                    let start = self.spider.worldPos
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        let moved = self.spider.worldPos.distance(to: start)
                        print("habitat live: in \(self.inHabitat), clock \(self.habitat?.view.clockTime ?? -1)s, moved \(Int(moved)) px, \(self.spider.debugState)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        // SPIDER_HABITAT_SHOT=dir opens the habitat, writes one PNG per preset there, then quits.
        if let dir = ProcessInfo.processInfo.environment["SPIDER_HABITAT_SHOT"] {
            enterHabitat()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, let hc = self.habitat else { return }
                func shot(_ name: String) {
                    hc.view.displayIfNeeded()
                    if let rep = hc.view.bitmapImageRepForCachingDisplay(in: hc.view.bounds) {
                        hc.view.cacheDisplay(in: hc.view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                    }
                }
                let keep = hc.view.habitat
                hc.view.onChange = nil
                for p in Habitat.Preset.allCases {
                    hc.view.habitat = Habitat.preset(p)
                    hc.view.layout()
                    for _ in 0..<60 { hc.view.tick(dt: 1.0 / 60.0) }
                    shot("habitat_\(p.rawValue)")
                }
                hc.view.habitat = keep
                NSApp.terminate(nil)
            }
        }
        // SPIDER_STUDIO=1 opens the studio straight away (handy for testing).
        if ProcessInfo.processInfo.environment["SPIDER_STUDIO"] == "1" { openStudio() }
        // SPIDER_STUDIO_SHOT=dir writes one PNG per studio tab there, then quits.
        if let dir = ProcessInfo.processInfo.environment["SPIDER_STUDIO_SHOT"] {
            openStudio()
            // SPIDER_STUDIO_SHOT_CUSTOM=1 shows the hand-shaping sliders too.
            if ProcessInfo.processInfo.environment["SPIDER_STUDIO_SHOT_CUSTOM"] == "1" { studio?.debugSelectCustom() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                for i in 0..<11 { self?.studio?.snapshot(to: "\(dir)/studio_tab\(i).png", tab: i) }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(inHabitat, forKey: "inHabitat")
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
        preyView.spider = spider
        preyWindow.contentView = preyView
        preyWindow.ignoresMouseEvents = true
        silkWindow = OverlayWindow(frame: frame)
        silkView = SilkView(frame: CGRect(origin: .zero, size: frame.size))
        silkView.worldOrigin = frame.origin
        silkWindow.contentView = silkView
        silkWindow.ignoresMouseEvents = true

        // The laser dot.
        laserWindow = OverlayWindow(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        laserWindow.level = NSWindow.Level(rawValue: window.level.rawValue + 2)
        laserView = LaserView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        laserWindow.contentView = laserView
        laserWindow.ignoresMouseEvents = true

        // The box outline, shown only while there is a box.
        boxWindow = OverlayWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 150))
        boxWindow.level = NSWindow.Level(rawValue: window.level.rawValue - 1)
        boxOutline = BoxOutlineView(frame: CGRect(x: 0, y: 0, width: 200, height: 150))
        boxWindow.contentView = boxOutline
        boxWindow.ignoresMouseEvents = true

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
        map.rebuild(windows: [], cinema: cinemaScreens)
        spider.surfacesRestructured()
        spider.refitHammock()
    }

    // MARK: Frame clock

    private func startClock() {
        lastTime = CACurrentMediaTime()
        if #available(macOS 14.0, *), let screen = NSScreen.main {
            // A display link on the screen, not on the overlay view: one tied
            // to a view stops the moment that view's window is put away or
            // another window takes over, and the clock must never stop.
            let link = screen.displayLink(target: self, selector: #selector(tick))
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

    private var tickCount = 0
    @objc private func tick() {
        tickCount += 1
        guard !hidden else { return }
        let now = CACurrentMediaTime()

        // Whether clicks reach us is decided every tick, throttled or not: a
        // stale decision here is a spider you cannot pick up.
        let cursorNow = V2(NSEvent.mouseLocation)
        let wantsMouseNow = interactive && (spider.isHeld || spider.hitTest(cursorNow))
        if window.ignoresMouseEvents == wantsMouseNow {
            window.ignoresMouseEvents = !wantsMouseNow
        }
        // Likewise for the creatures: clicks reach their window only while
        // the pointer is over one (or one is on the pointer).
        let preyHeld = spider.prey.contains { $0.held }
        let wantsPreyMouse = interactive && preyShown && (preyHeld || (!wantsMouseNow && spider.preyHit(cursorNow) != nil))
        if preyWindow.ignoresMouseEvents == wantsPreyMouse {
            preyWindow.ignoresMouseEvents = !wantsPreyMouse
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
            let wantsRoom = pose.emote == .thought
            if wantsRoom != thoughtRoom {
                thoughtRoom = wantsRoom
                applyWindowSize()
            }
            let moved = place(pose)
            view.apply(pose)
            settle(moved: moved)
        }
        if !inHabitat { updateHammock(dt: dt) }
        if inHabitat, spider.isHeld, let hc = habitat, !hc.view.screenScene.insetBy(dx: -30, dy: -30).contains(spider.worldPos.point) {
            fellOutOfHabitat()
        }
        updatePrey()
        updateLaser()
        updateSurroundings(now: now)

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

        let wantSilk = pose.web != nil
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
                if !hammockShown || h.drawFrame != hammockWindow.frame {
                    hammockWindow.setFrame(h.drawFrame, display: false)
                    hammockView.frame = CGRect(origin: .zero, size: h.drawFrame.size)
                }
                hammockView.hammock = h
                if !hammockShown {
                    hammockShown = true
                    hammockWindow.orderFrontRegardless()
                }
                // side + 10 × style + 100 × seed
                let code = h.progress >= 1 ? (h.left ? 1 : 2) + 10 * h.style.rawValue + 100 * h.seed : 0
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
            let hadAny = lastHammock != nil
            lastHammock = h
            if hadHammock != spider.hasHammock || hadAny != spider.hasAnyHammock { refreshMenu() }
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

    // MARK: - Camouflage
    //
    // A camouflaged coat wants to know what is behind it — behind its
    // body, that is, not under its feet: standing on top of a window it
    // is against whatever is above that window, the wallpaper more often
    // than not. If it has been allowed to see the screen, it samples the
    // patch its body covers; if not, it works out what is there — a window
    // over that spot, or else the wallpaper at that spot — which is right
    // more often than not.

    private var lastSurroundingsSample: CFTimeInterval = 0
    /// The wallpaper of each screen, shrunk to a thumbnail to sample from.
    private var wallpaperCache: [String: CGImage] = [:]

    private func updateSurroundings(now: CFTimeInterval) {
        guard spider.look.isCamouflaged, now - lastSurroundingsSample > 0.4 else { return }
        lastSurroundingsSample = now
        spider.surroundings = sampleBehindSpider() ?? guessSurroundings()
    }

    /// The middle of its body, pushed a little off whatever it stands on so
    /// the patch behind it is not the ledge under its feet.
    private var bodyPoint: V2 {
        spider.worldPos + spider.standingNormal * (4 * spider.config.scale)
    }

    /// The average colour of what is on screen behind its body, if it is
    /// allowed to look.
    private func sampleBehindSpider() -> RGB? {
        guard !inHabitat, CGPreflightScreenCaptureAccess() else { return nil }
        let pos = bodyPoint
        let r = 18 * spider.config.scale
        // Window-list space has its origin at the top left of the primary
        // display.
        guard let primary = NSScreen.screens.first else { return nil }
        let rect = CGRect(x: pos.x - r, y: primary.frame.maxY - (pos.y + r), width: r * 2, height: r * 2)
        guard let img = CGWindowListCreateImage(rect, [.optionOnScreenBelowWindow], CGWindowID(window.windowNumber), [.nominalResolution]) else { return nil }
        return AppDelegate.average(of: img)
    }

    private func guessSurroundings() -> RGB {
        var chrome = RGB(0.93, 0.93, 0.93)
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            chrome = RGB(NSColor.windowBackgroundColor)
        }
        if inHabitat { return chrome }
        let p = bodyPoint
        // A window over that spot is what is behind it, whatever it is
        // standing on. (The one under its feet does not reach its body.)
        if map.occluders.contains(where: { $0.rect.contains(p.point) }) { return chrome }
        // Otherwise the desktop shows through: the wallpaper, at that spot.
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -40, dy: -40).contains(p.point) } ?? NSScreen.main
        guard let screen else { return RGB(0.5, 0.5, 0.55) }
        return wallpaperColour(at: p, on: screen) ?? RGB(0.5, 0.5, 0.55)
    }

    /// The colour of the wallpaper where `p` is on `screen`: the picture as
    /// the desktop shows it, filling the screen, or the plain colour behind
    /// it if there is no picture.
    private func wallpaperColour(at p: V2, on screen: NSScreen) -> RGB? {
        let ws = NSWorkspace.shared
        let options = ws.desktopImageOptions(for: screen) ?? [:]
        let fill = (options[.fillColor] as? NSColor).map { RGB($0.usingColorSpace(.deviceRGB) ?? $0) }
        guard let url = ws.desktopImageURL(for: screen) else { return fill }
        let img: CGImage
        if let cached = wallpaperCache[url.path] {
            img = cached
        } else {
            guard let full = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let small = AppDelegate.shrink(full, toWidth: 320) else { return fill }
            if wallpaperCache.count > 8 { wallpaperCache.removeAll() }
            wallpaperCache[url.path] = small
            img = small
        }
        // Where the point falls in the picture. Stretched to the screen's
        // shape if the desktop is set that way; otherwise the picture
        // fills the screen proportionally, centred, its overflow cropped.
        let f = screen.frame
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let scaling = (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: UInt($0.intValue)) }
        var sx: CGFloat, sy: CGFloat
        if scaling == .scaleAxesIndependently {
            sx = f.width / iw; sy = f.height / ih
        } else {
            let s = max(f.width / iw, f.height / ih)
            sx = s; sy = s
        }
        let ox = (f.width - iw * sx) / 2, oy = (f.height - ih * sy) / 2
        let px = (p.x - f.minX - ox) / sx
        let py = ih - (p.y - f.minY - oy) / sy     // rows run top down
        guard px.isFinite, py.isFinite else { return fill }
        // A patch about the size of its body.
        let r = max(2, 40 * spider.config.scale / sx)
        let patch = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
            .intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
        guard !patch.isNull, patch.width >= 1, patch.height >= 1, let crop = img.cropping(to: patch) else { return fill }
        return AppDelegate.average(of: crop)
    }

    /// A small copy of an image, to sample from cheaply.
    private static func shrink(_ img: CGImage, toWidth w: Int) -> CGImage? {
        let h = max(1, Int(CGFloat(img.height) * CGFloat(w) / CGFloat(max(img.width, 1))))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Averages an image by drawing it down to a few pixels.
    private static func average(of img: CGImage) -> RGB {
        let n = 4
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return RGB(0.5, 0.5, 0.5) }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let data = ctx.data else { return RGB(0.5, 0.5, 0.5) }
        let px = data.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var r = 0, g = 0, b = 0
        for i in 0..<(n * n) {
            r += Int(px[i * 4]); g += Int(px[i * 4 + 1]); b += Int(px[i * 4 + 2])
        }
        let k = CGFloat(n * n * 255)
        return RGB(CGFloat(r) / k, CGFloat(g) / k, CGFloat(b) / k)
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
        updater.onChange = { [weak self] in self?.refreshMenu() }
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
        add(menu, inHabitat ? "Leave Habitat" : "Enter Habitat…", #selector(toggleHabitat), key: "e")
        menu.addItem(.separator())

        add(menu, "Come Here", #selector(comeHere))

        // Everything it can be asked to do lives under Behavior.
        let behavior = NSMenu()
        add(behavior, "Say Hi", #selector(sayHi))
        add(behavior, "Toss It", #selector(toss))
        add(behavior, "Swing!", #selector(swing))
        add(behavior, "Peek-a-boo", #selector(peekaboo))
        add(behavior, "Laser Pointer", #selector(toggleLaser), state: laserOn)
        behavior.addItem(.separator())
        let feedMenu = NSMenu()
        for kind in PreyKind.allCases {
            let item = NSMenuItem(title: "Release a \(kind.label)", action: #selector(feed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            feedMenu.addItem(item)
        }
        let feedItem = NSMenuItem(title: "Feed", action: nil, keyEquivalent: "")
        feedItem.submenu = feedMenu
        behavior.addItem(feedItem)
        behavior.addItem(.separator())
        if spider.hasHammock {
            add(behavior, "Nap in the Hammock", #selector(nap))
            add(behavior, "Clear the Hammock", #selector(clearHammock))
        } else {
            let build = NSMenuItem(title: "Build a Hammock", action: #selector(buildHammock), keyEquivalent: "")
            build.target = self
            build.isEnabled = spider.config.hammocks
            behavior.addItem(build)
            if spider.hasAnyHammock { add(behavior, "Clear the Hammock", #selector(clearHammock)) }
        }
        behavior.addItem(.separator())
        if spider.confine != nil {
            add(behavior, "Redraw the Box…", #selector(drawBox))
            add(behavior, "Free \(name) from the Box", #selector(freeSpider))
        } else {
            add(behavior, "Keep \(name) in a Box…", #selector(drawBox))
        }
        let behaviorItem = NSMenuItem(title: "Behavior", action: nil, keyEquivalent: "")
        behaviorItem.submenu = behavior
        menu.addItem(behaviorItem)

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
        let pounce = NSMenuItem(title: "Pounce on the Cursor", action: #selector(togglePounce), keyEquivalent: "")
        pounce.target = self
        pounce.state = spider.config.pounceOnCursor ? .on : .off
        pounce.isEnabled = spider.config.followCursor
        menu.addItem(pounce)
        add(menu, "Shoot Webs", #selector(toggleWebs), state: spider.config.webs)
        add(menu, "Build Hammocks", #selector(toggleHammocks), state: spider.config.hammocks)
        add(menu, "Click to Pick Up", #selector(toggleInteractive), state: interactive)
        add(menu, "Pause", #selector(togglePause), state: spider.config.paused)
        menu.addItem(.separator())
        add(menu, "Launch at Login", #selector(toggleLogin), state: loginEnabled)
        let update = NSMenuItem(title: updater.busy ? "Checking for Updates…" : "Check for Updates…",
                                action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        update.isEnabled = !updater.busy
        menu.addItem(update)
        menu.addItem(.separator())
        add(menu, "Bring \(name) to the Middle", #selector(teleportToMiddle))
        add(menu, "Reset Everything", #selector(resetEverything))
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
    @objc private func peekaboo() { spider.playPeekaboo() }
    @objc private func nap() { spider.napInHammock() }
    @objc private func buildHammock() { spider.buildHammock() }
    @objc private func clearHammock() { spider.clearHammock() }
    @objc private func sayHi() { spider.debugActivity("greet", for: 2.4) }

    // MARK: The habitat

    /// Into the tank, or back out onto the desktop. It is the same spider —
    /// same looks, same appetite, same mood — moving house.
    @objc private func toggleHabitat() {
        if inHabitat { leaveHabitat() } else { enterHabitat() }
    }

    /// Where the menu bar icon is, on screen: the tank grows out of it and
    /// shrinks back into it.
    private var statusItemRect: CGRect {
        if let w = statusItem.button?.window {
            let r = w.frame
            return CGRect(x: r.midX - 12, y: r.minY, width: 24, height: r.height)
        }
        let f = NSScreen.main?.frame ?? worldFrame()
        return CGRect(x: f.maxX - 120, y: f.maxY - 24, width: 24, height: 22)
    }
    private var habitatFrame: CGRect?
    private var transitioning = false

    /// While the tank is open and it is still outside, the tank is a
    /// window it can climb on and the area it wants to be in.
    private var tankGate = false
    private var tankPoll: Timer?
    private var lineSince: CFTimeInterval = -1
    private var userConfine: CGRect?
    private var tankWindowID: CGWindowID { 4_000_000 }

    private func enterHabitat() {
        guard !inHabitat, !transitioning else { return }
        if hidden { toggleHidden() }
        if habitat == nil {
            let hc = HabitatController(spider: spider)
            hc.onLeave = { [weak self] in self?.leaveHabitat() }
            habitat = hc
        }
        guard let hc = habitat else { return }
        transitioning = true
        let target = habitatFrame ?? hc.window.frame
        habitatFrame = target
        // 1. The tank grows out of the menu bar.
        hc.window.setFrame(statusItemRect, display: false)
        hc.window.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        hc.window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hc.window.animator().setFrame(target, display: true)
            hc.window.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            guard let self else { return }
            hc.window.setFrame(target, display: true)
            hc.view.layout()
            self.openGate(hc)
        })
    }

    /// 2. The tank becomes part of the desktop — a window it can walk on, and
    /// the place it wants to be — and it makes its own way there, from
    /// wherever it is, by walking, leaping or climbing as it always does.
    /// When it reaches the tank it gets in the way a spider would: a leap
    /// from the rim in through the glass, or, hanging beneath, a line shot up
    /// into it and a climb. Mid-air over it (thrown, say), it drops in.
    private func openGate(_ hc: HabitatController) {
        tankGate = true
        userConfine = spider.confine
        tracker.pollNow()
        let f = hc.window.frame
        spider.confine = f.insetBy(dx: -(map.standoff + 14), dy: -(map.standoff + 14))
        spider.calmUnderCover = true
        spider.onMapSwitched = { [weak self] in self?.settleIntoHabitat() }
        spider.nudgeDecision()
        hc.view.map.standoff = map.standoff
        hc.view.rebuildMap()
        hc.noteOrigin()
        tankPoll?.invalidate()
        tankPoll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let hc = self.habitat, self.tankGate else { return }
            let inside = hc.view.screenScene
            // Swinging about on a line out here is no way to get anywhere:
            // let go and drop onto something.
            if self.spider.isOnLine, !self.spider.isHeld, self.lineSince < 0 { self.lineSince = CACurrentMediaTime() }
            if !self.spider.isOnLine { self.lineSince = -1 }
            if self.spider.isOnLine, !self.spider.isHeld, CACurrentMediaTime() - self.lineSince > 2.5 {
                self.spider.letGo()
                self.lineSince = -1
            }
            // Flying in: as soon as it is over the tank, it is in.
            if self.spider.isAirborne, inside.contains(self.spider.worldPos.point) {
                self.spider.moveInMidAir(map: hc.view.map, habitat: true)
                self.settleIntoHabitat()
                return
            }
            // On the tank, and not already on its way in: get in. The map
            // switches at the moment it leaves the rim, and that is when it
            // counts as in; if the leap is called off, it tries again.
            guard self.spider.currentLoopID == "win:\(self.tankWindowID)", !self.spider.isLeavingSurface else { return }
            let spots = hc.view.map.sampleSpots(spacing: 40).shuffled()
            if self.spider.standingNormal.y < -0.5 {
                // Hanging under the tank: a line up through the floor to
                // whatever is above, and a climb.
                let here = self.spider.worldPos
                let above = spots.filter { $0.point.y > here.y + 40 && abs($0.point.x - here.x) < 160 }
                if let target = above.min(by: { $0.point.distance(to: here) < $1.point.distance(to: here) }) {
                    self.spider.switchMapOnLeaving(hc.view.map, habitat: true)
                    if self.spider.climbAway(to: target.point, then: {}) { return }
                }
            }
            // A leap in: the nearest few spots inside it can reach.
            for spot in spots.prefix(40) {
                self.spider.switchMapOnLeaving(hc.view.map, habitat: true)
                if self.spider.leapIn(to: spot.point, throughGlass: true) { return }
            }
        }
    }

    /// Dragged out of the tank by the pointer: it comes out — and then wants
    /// back in, the same way it got in the first time.
    private func fellOutOfHabitat() {
        guard inHabitat, let hc = habitat else { return }
        inHabitat = false
        hc.view.stopClock()
        spider.moveInMidAir(map: map, habitat: false)
        if let h = spider.hammock { hammockView.hammock = h; hammockShown = false; lastHammock = nil }
        openGate(hc)
        hc.view.startClock()
        refreshMenu()
    }

    /// In: the same spider, the same size, at the same spot, now living in
    /// the tank's part of the screen. The desktop overlays keep drawing it.
    private func settleIntoHabitat() {
        guard let hc = habitat else { transitioning = false; return }
        tankPoll?.invalidate()
        tankPoll = nil
        tankGate = false
        spider.confine = userConfine
        spider.calmUnderCover = false
        spider.onMapSwitched = nil
        inHabitat = true
        transitioning = false
        hammockWindow.orderOut(nil)
        boxWindow.orderOut(nil)
        laserWindow.orderOut(nil)
        spider.laser = nil
        tracker.pollNow()
        hc.window.title = "\(spider.name.isEmpty ? "Spider" : spider.name)'s Habitat"
        hc.view.startClock()      // only the scenery: the desktop clock runs the spider
        refreshMenu()
    }

    private func leaveHabitat() {
        if tankGate, let hc = habitat {
            // Called off before it got in: the tank just goes away.
            tankPoll?.invalidate(); tankPoll = nil
            tankGate = false
            spider.confine = userConfine
            spider.calmUnderCover = false
            spider.onMapSwitched = nil
            transitioning = false
            tracker.pollNow()
            hc.window.delegate = nil
            hc.window.orderOut(nil)
            hc.window.delegate = hc
            refreshMenu()
            return
        }
        guard inHabitat, let hc = habitat, !transitioning else { return }
        inHabitat = false
        transitioning = true
        hc.view.stopClock()
        // 1. It drops out of the bottom of the tank onto the desktop.
        let f = hc.window.frame
        spider.enter(map: map, at: V2(f.midX, f.minY - 6), habitat: false)
        spider.dropIn(at: V2(f.midX, f.minY - 6))
        if let h = spider.hammock { hammockView.hammock = h; hammockShown = false; lastHammock = nil }
        if spider.confine != nil { boxWindow.orderFrontRegardless() }
        window.orderFrontRegardless()
        calmFrames = 0
        calm = false
        refreshMenu()
        // 2. The tank shrinks back into the menu bar.
        habitatFrame = f
        hc.window.delegate = nil
        NSAnimationContext.runAnimationGroup({ [weak self] ctx in
            guard let self else { return }
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hc.window.animator().setFrame(self.statusItemRect, display: true)
            hc.window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            hc.window.orderOut(nil)
            hc.window.setFrame(self.habitatFrame ?? f, display: false)
            hc.window.alphaValue = 1
            hc.window.delegate = hc
            self.transitioning = false
        })
    }

    // MARK: Laser pointer

    /// With the laser on, any click anywhere puts the dot down and the
    /// spider goes for it; dragging moves it; letting go leaves it a moment.
    @objc private func toggleLaser() {
        laserOn.toggle()
        if laserOn {
            let down: (NSEvent) -> Void = { [weak self] e in self?.laserDown(at: NSEvent.mouseLocation) }
            let drag: (NSEvent) -> Void = { [weak self] e in self?.laserMove(to: NSEvent.mouseLocation) }
            let up: (NSEvent) -> Void = { [weak self] _ in self?.laserUp() }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: down) { laserMonitors.append(m) }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: drag) { laserMonitors.append(m) }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: up) { laserMonitors.append(m) }
            // Clicks on our own windows come through the local monitor instead.
            if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] e in
                guard let self else { return e }
                // Not when picking the spider or a creature up.
                if e.window === self.window || e.window === self.preyWindow { return e }
                switch e.type {
                case .leftMouseDown: self.laserDown(at: NSEvent.mouseLocation)
                case .leftMouseDragged: self.laserMove(to: NSEvent.mouseLocation)
                default: self.laserUp()
                }
                return e
            }) { laserMonitors.append(m) }
        } else {
            for m in laserMonitors { NSEvent.removeMonitor(m) }
            laserMonitors = []
            laserHeld = false
            laserOffAt = 0
            spider.laser = nil
            laserWindow.orderOut(nil)
        }
        refreshMenu()
    }

    private func laserDown(at p: CGPoint) {
        laserHeld = true
        laserMove(to: p)
        laserWindow.orderFrontRegardless()
    }

    private func laserMove(to p: CGPoint) {
        guard laserOn else { return }
        laserWindow.setFrameOrigin(CGPoint(x: p.x - 18, y: p.y - 18))
        spider.laser = V2(p)
        calmFrames = 0
        calm = false
    }

    private func laserUp() {
        guard laserHeld else { return }
        laserHeld = false
        // The dot lingers a little after you let go.
        laserOffAt = CACurrentMediaTime() + 2.5
    }

    private func updateLaser() {
        guard laserOn else { return }
        if spider.laser != nil {
            laserView.phase += 0.016
            if !laserHeld, CACurrentMediaTime() > laserOffAt {
                spider.laser = nil
                laserWindow.orderOut(nil)
            }
        }
    }

    // MARK: The box

    @objc private func drawBox() {
        guard boxDrawWindow == nil else { return }
        let frame = worldFrame()
        let w = BoxDrawWindow(frame: frame)
        let v = BoxDrawView(frame: CGRect(origin: .zero, size: frame.size))
        v.worldOrigin = frame.origin
        v.onDone = { [weak self] rect in
            guard let self else { return }
            self.boxDrawWindow?.orderOut(nil)
            self.boxDrawWindow = nil
            if let rect { self.applyBox(rect) }
            self.refreshMenu()
        }
        w.contentView = v
        boxDrawWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(v)
    }

    private func applyBox(_ rect: CGRect?) {
        if let rect {
            boxWindow.setFrame(rect, display: true)
            boxOutline.frame = CGRect(origin: .zero, size: rect.size)
            boxOutline.needsDisplay = true
            boxWindow.orderFrontRegardless()
            UserDefaults.standard.set([rect.minX, rect.minY, rect.width, rect.height].map { Double($0) }, forKey: "confine")
        } else {
            boxWindow.orderOut(nil)
            UserDefaults.standard.removeObject(forKey: "confine")
        }
        spider.confine = rect
        calmFrames = 0
        calm = false
    }

    @objc private func freeSpider() {
        applyBox(nil)
        refreshMenu()
    }

    /// Lost it somewhere? This puts it in the middle of the main screen, in
    /// the air, and it falls from there onto whatever is below.
    @objc private func teleportToMiddle() {
        let f = spider.confine ?? NSScreen.main?.frame ?? worldFrame()
        if hidden { toggleHidden() }
        spider.config.paused = false
        spider.teleport(to: V2(f.midX, f.midY))
        calmFrames = 0
        calm = false
        refreshMenu()
    }

    /// Starts the whole thing over: the app relaunches itself, which rebuilds
    /// every window and re-reads the desktop. The design, settings and
    /// hammock are kept — they are saved. Running as a bare binary (not from
    /// the .app) it rebuilds in place instead.
    @objc private func resetEverything() {
        saveSettings()
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "sleep 0.5; open -n \"\(bundle.path)\""]
            do {
                try task.run()
                NSApp.terminate(nil)
                return
            } catch {
                // Fall through to an in-place reset.
            }
        }
        resetInPlace()
    }

    private func resetInPlace() {
        tracker.stop()
        let design = SpiderDesign.load()
        let config = spider.config
        let saved = UserDefaults.standard.integer(forKey: "hammock")
        spider = Spider(map: map)
        spider.config = config
        spider.config.paused = false
        spider.apply(design: design)
        map.standoff = AppDelegate.standoff(for: spider.config.scale)
        map.rebuild(windows: [])
        view.spider = spider
        preyView.spider = spider
        preyView.prey = []
        preyView.refresh()
        if saved % 10 == 1 || saved % 10 == 2 {
            spider.restoreHammock(left: saved % 10 == 1, style: HammockStyle(rawValue: (saved / 10) % 10) ?? .sling,
                                  seed: saved / 100)
        }
        lastHammock = nil
        hammockShown = false
        hammockWindow.orderOut(nil)
        silkWindow.orderOut(nil)
        silkVisible = false
        preyWindow.orderOut(nil)
        preyShown = false
        if hidden { toggleHidden() }
        let f = NSScreen.main?.frame ?? worldFrame()
        spider.teleport(to: V2(f.midX, f.midY))
        applyWindowSize()
        tracker.start()
        calmFrames = 0
        calm = false
        refreshMenu()
    }

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

    /// A thought bubble needs far more room over its head than anything
    /// else it draws, so the sprite and its window grow while one is up.
    private var thoughtRoom = false

    private func applyWindowSize() {
        map.standoff = AppDelegate.standoff(for: spider.config.scale)
        spriteSide = SpiderRenderer.spriteSide(for: spider.config.scale) + (thoughtRoom ? (240 * spider.config.scale).rounded() : 0)
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
            // The studio is a window like any other: something to climb on.
            st.onVisibility = { [weak self] number, shown in
                guard let self else { return }
                if shown { self.tracker.ownFurniture.insert(number) } else { self.tracker.ownFurniture.remove(number) }
                self.tracker.pollNow()
            }
            studio = st
        }
        studio?.scale = spider.config.scale
        studio?.show()
    }

    @objc private func toggleFollow() {
        spider.config.followCursor.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func togglePounce() {
        spider.config.pounceOnCursor.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func toggleWebs() {
        spider.config.webs.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func toggleHammocks() {
        spider.config.hammocks.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func toggleInteractive() {
        interactive.toggle()
        if !interactive { window.ignoresMouseEvents = true; preyWindow.ignoresMouseEvents = true }
        saveSettings(); refreshMenu()
    }

    @objc private func togglePause() {
        spider.config.paused.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func checkForUpdates() {
        saveSettings()
        updater.checkAndInstall()
    }

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
        d.set(spider.config.pounceOnCursor, forKey: "pounceOnCursor")
        d.set(spider.config.webs, forKey: "webs")
        d.set(spider.config.hammocks, forKey: "hammocks")
        d.set(spider.config.paused, forKey: "paused")
        d.set(interactive, forKey: "interactive")
        d.set(hidden, forKey: "hidden")
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "scale": 0.95, "liveliness": 1.0, "followCursor": true, "pounceOnCursor": true,
            "webs": true, "hammocks": true, "paused": false, "interactive": true, "hidden": false,
        ])
        spider.config.scale = CGFloat(d.double(forKey: "scale"))
        spider.config.followCursor = d.bool(forKey: "followCursor")
        spider.config.pounceOnCursor = d.bool(forKey: "pounceOnCursor")
        spider.config.webs = d.bool(forKey: "webs")
        spider.config.hammocks = d.bool(forKey: "hammocks")
        spider.config.paused = d.bool(forKey: "paused")
        interactive = d.bool(forKey: "interactive")
        hidden = d.bool(forKey: "hidden")
    }
}
