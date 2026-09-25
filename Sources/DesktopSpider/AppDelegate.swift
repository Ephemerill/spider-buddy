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
    private var laserWindow: OverlayWindow!
    private var laserView: LaserView!
    private var boxWindow: OverlayWindow!
    private var boxOutline: BoxOutlineView!
    private var hammockShown = false
    private var hammockTear: CGFloat = 0
    private var lastHammock: Hammock?
    private var lastWipeCursor = V2(-9999, -9999)
    private let map = SurfaceMap()
    private var spider: Spider!
    /// Toys out on the desktop, for it (and any visitors) to play with.
    private lazy var toyBox: ToyBox = {
        let box = ToyBox(map: map)
        box.onJingle = { [weak self] _, loud in self?.jingle(loud) }
        return box
    }()
    /// The bell jingles out loud (quietly), not just to look at.
    private var toySounds = true
    private var lastJingleAt: CFTimeInterval = 0
    /// Other spiders dropping by, if they are let (see `visitorsOn`).
    private var visitors: [Visitor] = []
    private var visitorsOn = false
    private var nextVisitAt: CFTimeInterval = 0
    /// The two visitor sliders in the menu, 0...1: how often they come
    /// (rarely to often) and how long they stay (briefly to a good while).
    private var visitFrequency: CGFloat = 0.5
    private var visitStay: CGFloat = 0.5
    /// Seconds to the next visit: from ten minutes apart at the rare end
    /// to under a minute at the often end, give or take.
    private var visitGap: CFTimeInterval { Double(600 * pow(45.0 / 600, visitFrequency) * randRange(0.6, 1.4)) }
    /// Seconds a visitor stays: a minute up to a quarter of an hour.
    private var visitLength: CFTimeInterval { Double(60 * pow(900.0 / 60, visitStay) * randRange(0.7, 1.3)) }
    private let playground = Playground()
    /// Small creatures finding their own way in now and then, if they are
    /// let — rarely, and never on the dot.
    private var wildOn = false
    private var nextWildAt: CFTimeInterval = 0
    /// The slider, 0...1: from rarely to now and then.
    private var wildFrequency: CGFloat = 0.35
    /// Seconds to the next: about an hour and a half apart at the rare end,
    /// ten minutes or so at the other, and anywhere from half to half as
    /// much again of that.
    private var wildGap: CFTimeInterval { Double(5400 * pow(600.0 / 5400, wildFrequency) * randRange(0.5, 1.5)) }
    private var allSpiders: [Spider] { [spider] + visitors.map(\.spider) }
    private let tracker = WindowTracker()
    private var statusItem: NSStatusItem!
    private let updater = Updater()
    private var studio: StudioController?
    private var welcome: OnboardingController?
    /// The welcome tour is on: the spider is put away until the end of it,
    /// and then comes out of its menu bar icon.
    private var awaitingEntrance = false
    private var pausedBeforeWelcome = false
    private var habitat: HabitatController?
    /// Living in the habitat: on its surfaces, drawn inside it.
    private var inHabitat = false

    private var displayLink: Any?
    private var fallbackTimer: Timer?
    private var lastTime: CFTimeInterval = 0
    private var lastFrame: CFTimeInterval = 0
    /// When nothing has actually changed for a second — asleep, or just
    /// sitting there — the clock drops to a third of the display rate.
    private var calm = false
    private var calmSkip = 0
    private var calmFrames = 0
    /// Creatures are moving about, so the calm clock only halves the rate.
    private var critterPace = false
    private var lastCursor = V2(-9999, -9999)
    // SPIDER_STATS=1 prints a frame budget breakdown once a second.
    private let stats = ProcessInfo.processInfo.environment["SPIDER_STATS"] == "1"
    /// SPIDER_CINEMA_LOG=1 prints when a display is taken by a full-screen app, and given back.
    private let cinemaLog = ProcessInfo.processInfo.environment["SPIDER_CINEMA_LOG"] == "1"
    /// SPIDER_COMMOTION_LOG=1 prints each notification, volume or brightness change it notices.
    private let commotionLog = ProcessInfo.processInfo.environment["SPIDER_COMMOTION_LOG"] == "1"
    private var statFrames = 0
    private var statUpdate: CFTimeInterval = 0
    private var statApply: CFTimeInterval = 0
    private var statWindow: CFTimeInterval = 0
    private var statSince: CFTimeInterval = 0
    private var interactive = true
    private var hidden = false

    /// The Mac it lives on: Low Power Mode, the charger, the weather, the
    /// volume and the brightness.
    private let sense = SystemSense()
    /// Sleepy in Low Power Mode, excited when the charger goes in.
    private var feelsPower = true
    /// Rain on its mind while it rains outside.
    private var feelsWeather = true
    /// A faint rain across the desktop while it rains, too.
    private var showsRain = true
    /// Jumps at a notification; looks up at the volume or brightness changing.
    private var feelsCommotion = true
    /// It remembers what happens to it and grows a little with it.
    private var learns = true
    /// What it has been through (nil with learning off).
    private var memory: SpiderMemory?
    private var rainWindow: OverlayWindow!
    private var rainView: RainView!
    private var rainOffAt: CFTimeInterval = 0

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppInfo.takeOwnNameIfNeeded()
        spider = Spider(map: map)
        spider.apply(design: SpiderDesign.load())
        loadSettings()
        if learns { memory = SpiderMemory.load(); spider.memory = memory }
        map.standoff = AppDelegate.standoff(for: spider.config.scale)
        map.rebuild(windows: [])
        toyBox.scale = spider.config.scale
        spider.toys = toyBox

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
            let windows = self.withCornerRadii(windows)
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
                for s in self.allSpiders { s.surfacesRestructured() }
                if self.cinemaLog { fputs("cinema: \(self.cinemaScreens.isEmpty ? "over" : "\(self.cinemaScreens)") — \(self.spider.debugState)\n", stderr) }
            }
            for s in self.allSpiders { s.fullScreenApp = !self.cinemaScreens.isEmpty }
        }
        tracker.start()
        startSensing()
        // The first time it is opened: the welcome tour, before it comes out.
        // (SPIDER_WELCOME=1 shows it again.)
        if !UserDefaults.standard.bool(forKey: "welcomed") || ProcessInfo.processInfo.environment["SPIDER_WELCOME"] == "1" {
            DispatchQueue.main.async { [weak self] in self?.startWelcome() }
        }
        // SPIDER_WELCOME_SHOT=dir writes the welcome's first two pages there, then quits.
        if let dir = ProcessInfo.processInfo.environment["SPIDER_WELCOME_SHOT"] {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.welcome == nil { self.startWelcome() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.welcome?.debugSnapshot(to: "\(dir)/welcome1.png")
                    self.welcome?.debugNextPage()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self.welcome?.debugSnapshot(to: "\(dir)/welcome2.png")
                        guard ProcessInfo.processInfo.environment["SPIDER_WELCOME_FLOW"] == "1" else { NSApp.terminate(nil); return }
                        // On through the Studio and out: where each window
                        // is, and what the spider does as it arrives.
                        let tourFrame = self.welcome?.window.frame ?? .zero
                        self.welcome?.debugAdvance()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            print("welcome flow: tour \(tourFrame) studio \(self.studio?.debugFrame ?? .zero) same \(tourFrame == self.studio?.debugFrame) awaiting \(self.awaitingEntrance) spider window \(self.window.isVisible)")
                            self.studio?.debugDone()
                            for i in 1...12 {
                                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                                    print("welcome flow: +\(Double(i) * 0.5)s \(self.spider.debugState) at \(Int(self.spider.worldPos.x)),\(Int(self.spider.worldPos.y)) visible \(self.window.isVisible) welcomed \(UserDefaults.standard.bool(forKey: "welcomed"))")
                                    if i == 12 { NSApp.terminate(nil) }
                                }
                            }
                        }
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(showContextMenu(_:)),
            name: .spiderContextMenu, object: nil)
        watchForYouComingBack()

        startClock()
        // Back into the tank if that is where it was.
        if UserDefaults.standard.bool(forKey: "inHabitat") { openHabitat(restoring: true) }
        // SPIDER_HABITAT_TEST=1 runs the habitat through its paces on the real
        // clock — open it and watch it climb in, carry it out and watch it go
        // back, move the tank, decorate, feed it, close it and watch it drop
        // — printing what happens (and, with SPIDER_HABITAT_DIR set, taking
        // pictures), then puts the saved habitat back as it was and quits.
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_TEST"] == "1" {
            runHabitatTest(dir: ProcessInfo.processInfo.environment["SPIDER_HABITAT_DIR"])
        }
        // SPIDER_HABITAT_SHOT=dir opens the habitat with the spider in it and
        // writes a picture of the tank for every layout there (and one while
        // decorating), then puts everything back and quits.
        if let dir = ProcessInfo.processInfo.environment["SPIDER_HABITAT_SHOT"] {
            runHabitatShots(dir: dir)
        }
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_INPUT"] == "1" { runHabitatInputTest() }
        // SPIDER_HABITAT_RETURN=left|right|above: carried out of the tank to
        // that side and let go; reports how long it takes to get back in.
        if let side = ProcessInfo.processInfo.environment["SPIDER_HABITAT_RETURN"] {
            let restore = habitatTestSnapshot()
            openHabitat(restoring: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                guard let hc = habitat else { return }
                let f = hc.window.frame
                let to: V2 = side == "right" ? V2(f.maxX + 160, f.midY) : side == "above" ? V2(f.midX + 100, min(f.maxY + 120, (NSScreen.main?.visibleFrame.maxY ?? 900) - 40)) : V2(f.minX - 160, f.midY)
                spider.beginGrab(at: spider.worldPos)
                spider.moveGrab(to: to)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                    spider.endGrab(throwVelocity: .zero)
                    let start = CACurrentMediaTime()
                    var last = ""
                    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { t in
                        let el = CACurrentMediaTime() - start
                        let st = self.spider.debugState
                        let short = String(st.prefix(40))
                        if short != last { print(String(format: "habitat return: %5.1fs %@ at %.0f,%.0f", el, st, self.spider.worldPos.x, self.spider.worldPos.y)); last = short }
                        if self.inHabitat || el > 50 {
                            t.invalidate()
                            print(String(format: "habitat return: %@ after %.1fs", self.inHabitat ? "BACK IN" : "NOT BACK", el))
                            self.finishHabitatTest(restore)
                        }
                    }
                }
            }
        }
        // SPIDER_HABITAT_OPEN=secs opens the habitat with it inside for that
        // long (for measuring what it costs), then puts things back and quits.
        if let secs = ProcessInfo.processInfo.environment["SPIDER_HABITAT_OPEN"].flatMap(Double.init) {
            let restore = habitatTestSnapshot()
            if secs > 0 { openHabitat(restoring: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + abs(secs)) { self.finishHabitatTest(restore) }
        }
        // SPIDER_WILD_TEST=secs lets something wander in every few seconds
        // for that long (the setting itself is left alone), reports on
        // what is about every two seconds, and quits.
        if let secs = ProcessInfo.processInfo.environment["SPIDER_WILD_TEST"].flatMap(Double.init) {
            // Nothing that happens in the test goes into what it remembers.
            memory = nil
            spider.memory = nil
            let start = CACurrentMediaTime()
            var next = start + 2
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard let self else { return }
                let now = CACurrentMediaTime()
                if now >= next, now - start < secs - 20, self.spider.prey.filter({ $0.state == .loose }).count < 3 {
                    next = now + 12
                    let hour = Calendar.current.component(.hour, from: Date())
                    _ = self.spider.releaseWild(night: hour >= 20 || hour < 6, raining: false)
                }
                let about = self.spider.prey.map { p in
                    "\(p.kind.label)\(p.noticed ? "" : "(unseen)")\(p.leaving ? "(leaving)" : "") \(p.state) \(Int(p.pos.x)),\(Int(p.pos.y))"
                }
                print(String(format: "wild test %3.0fs: %@ | %@ | calm %@", now - start, self.spider.debugState,
                             about.joined(separator: "; "), self.calm ? "yes" : "no"))
                fflush(stdout)
                if now - start > secs { timer.invalidate(); NSApp.terminate(nil) }
            }
        }
        // SPIDER_TOY_TEST=secs picks each toy in turn (memory off, the Bell
        // Sound setting untouched), throws it now and then as if by you,
        // reports what it and the toy are up to every two seconds, and quits.
        if let secs = ProcessInfo.processInfo.environment["SPIDER_TOY_TEST"].flatMap(Double.init) {
            memory = nil
            spider.memory = nil
            let start = CACurrentMediaTime()
            let kinds = ToyKind.allCases
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.choose(.toy(kinds[0])) }
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard let self else { return }
                let now = CACurrentMediaTime()
                let about = self.toyBox.toys.map { t in
                    "\(t.kind.label) \(Int(t.pos.x)),\(Int(t.pos.y)) \(t.onSurface ? "on" : "air")\(t.walking ? " walking" : "")"
                }
                print(String(format: "toy test %3.0fs: %@ | %@ | %@ | calm %@", now - start, self.spider.debugState, self.spider.debugToy,
                             about.joined(separator: "; "), self.calm ? "yes" : "no"))
                fflush(stdout)
                // A fresh toy every so often, thrown in from above it as if by you.
                let step = Int(now - start) / 2
                if step % 12 == 11 { self.choose(.toy(kinds[(step / 12 + 1) % kinds.count])) }
                if step % 12 == 5, let toy = self.toyBox.toys.first, !toy.dangling {
                    // Put down (or, once down, picked up and thrown) near it.
                    if !self.holdingToy { self.takeInHand(toy) }
                    self.putDown(toy, at: self.spider.worldPos + V2(randRange(-200, 200), 160), fling: V2(randRange(-300, 300), 100))
                }
                if now - start > secs { timer.invalidate(); NSApp.terminate(nil) }
            }
        }
        // SPIDER_VISITORS_TEST=1 lets visitors in (no alert), brings three,
        // starts a game of tag, reports what they get up to, sends them
        // home, and quits.
        if ProcessInfo.processInfo.environment["SPIDER_VISITORS_TEST"] == "1" {
            func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
            after(0.5) { [weak self] in
                guard let self else { return }
                self.visitorsOn = true
                for i in 0..<3 { after(Double(i) * 0.5) { self.nextVisitAt = 0 } }
                func report(_ label: String) {
                    let vs = self.visitors.map { v in "\(Int(v.spider.worldPos.x)),\(Int(v.spider.worldPos.y)) \(v.spider.debugState)\(v.leaving ? " leaving" : "") skin \(v.spider.look.skin)" }
                    print("visitors test: \(label) host \(Int(self.spider.worldPos.x)),\(Int(self.spider.worldPos.y)) \(self.spider.debugState) | \(vs.count) visitors: \(vs.joined(separator: " ; ")) | hidden \(self.hidden) paused \(self.spider.config.paused) ticks \(self.tickCount) calm \(self.calm) awaiting \(self.awaitingEntrance) | game \(self.playground.busy) tags \(self.playground.debugTags) met \(self.playground.debugMeetings) silk \(self.silkVisible)")
                    fflush(stdout)
                }
                after(8) {
                    report("arrived")
                    if let g = self.visitors.first { self.playground.debugStartTag(it: g.spider, runner: self.spider) }
                    for i in 1...20 { after(Double(i)) { report("t+\(i)") } }
                    after(22) {
                        self.visitorsOn = false
                        let now = CACurrentMediaTime()
                        for v in self.visitors { self.startLeaving(v, now: now) }
                        for i in 1...15 { after(Double(i) * 2) { report("leaving +\(i * 2)") } }
                        after(32) { NSApp.terminate(nil) }
                    }
                }
            }
        }
        // SPIDER_PANEL_SHOT=dir opens the menu bar panel and writes one PNG per page there, then quits.
        if let dir = ProcessInfo.processInfo.environment["SPIDER_PANEL_SHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.togglePanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    for i in 0..<5 { self?.panel?.snapshot(to: "\(dir)/panel\(i).png", page: i, dark: true) }
                    NSApp.terminate(nil)
                }
            }
        }
        // SPIDER_LOCK_TEST=1 goes through a lock and an unlock, with a
        // picture of each moment in SPIDER_LOCK_TEST_DIR if it is set.
        if ProcessInfo.processInfo.environment["SPIDER_LOCK_TEST"] == "1" {
            let dir = ProcessInfo.processInfo.environment["SPIDER_LOCK_TEST_DIR"]
            func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
            func report(_ label: String) {
                print("lock test: \(label) \(Int(self.spider.worldPos.x)),\(Int(self.spider.worldPos.y)) \(self.spider.debugState) dormant \(self.spider.dormant) hammock \(self.spider.inHammock) \(self.spider.debugHammockBed)")
                fflush(stdout)
                if let dir {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    p.arguments = ["-x", "\(dir)/lock_\(label).png"]
                    try? p.run()
                }
            }
            // SPIDER_LOCK_TEST_HAMMOCK=1 gives it a hammock to go to bed in.
            // (Only in memory: nothing here is saved.)
            // (SPIDER_LOCK_TEST_HAMMOCK=left puts it in the top-left corner.)
            // The saved hammock is put back as it was when the test ends.
            let savedHammock = UserDefaults.standard.object(forKey: "hammock")
            if let side = ProcessInfo.processInfo.environment["SPIDER_LOCK_TEST_HAMMOCK"] {
                spider.config.hammocks = true
                spider.restoreHammock(left: side == "left")
            }
            after(4) { report("before"); self.youLeft(); report("tucked") }
            after(8) { report("asleep"); self.youCameBack() }
            for i in 1...8 { after(8 + Double(i) * 0.75) { report(String(format: "back+%.2f", Double(i) * 0.75)) } }
            after(15) {
                self.spider.clearHammock()
                UserDefaults.standard.set(savedHammock, forKey: "hammock")
                UserDefaults.standard.synchronize()
                exit(0)
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
        memory?.save()
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
        preyView.toyBox = toyBox
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

        // Rain, under the spider and everything of its own.
        rainWindow = OverlayWindow(frame: frame)
        rainWindow.level = NSWindow.Level(rawValue: window.level.rawValue - 1)
        rainView = RainView(frame: CGRect(origin: .zero, size: frame.size))
        rainWindow.contentView = rainView
        rainWindow.ignoresMouseEvents = true
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
        rainWindow.setFrame(frame, display: false)
        rainView.frame = CGRect(origin: .zero, size: frame.size)
        map.rebuild(windows: [], cinema: cinemaScreens)
        for s in allSpiders { s.surfacesRestructured() }
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
        if tickCount % 3600 == 0, let m = memory, m.dirty { m.save() }
        if tickCount % 30 == 0 {
            updateRain(now: CACurrentMediaTime())
            // Never left asleep for good by an unlock that went unheard.
            if spider.dormant, !away, !wakingUp, !AppDelegate.screenIsLocked { spider.wakeAndGreet() }
        }
        guard !hidden else { return }
        let now = CACurrentMediaTime()

        // Whether clicks reach us is decided every tick, throttled or not: a
        // stale decision here is a spider you cannot pick up.
        let cursorNow = V2(NSEvent.mouseLocation)
        let wantsMouseNow = interactive && (spider.isHeld || spider.hitTest(cursorNow))
        if window.ignoresMouseEvents == wantsMouseNow {
            window.ignoresMouseEvents = !wantsMouseNow
        }
        for v in visitors {
            let wants = interactive && (v.spider.isHeld || v.spider.hitTest(cursorNow))
            if v.window.ignoresMouseEvents == wants { v.window.ignoresMouseEvents = !wants }
        }
        // Likewise for the creatures: clicks reach their window only while
        // the pointer is over one (or one is on the pointer).
        // (Not the toy on your pointer: that goes where the pointer goes,
        // clicks and all, and a drag on a toy is the view's until it ends.)
        let preyHeld = spider.prey.contains { $0.held } || preyView.busy
        let wantsPreyMouse = interactive && preyShown
            && (preyHeld || (!wantsMouseNow && (spider.preyHit(cursorNow) != nil || toyBox.hit(cursorNow) != nil)))
        if preyWindow.ignoresMouseEvents == wantsPreyMouse {
            preyWindow.ignoresMouseEvents = !wantsPreyMouse
        }

        // Something on the pointer goes where it goes, at the full rate.
        if handToy != nil, cursorNow.distance(to: lastCursor) > 0.4 {
            calm = false
            calmFrames = 0
        }
        // The calm throttle skips whole frames; the active rate is the link's.
        if calm {
            calmSkip += 1
            guard calmSkip % (lowPowerClock || critterPace ? 2 : 3) == 0 else { return }
        }
        lastFrame = now
        let dt = CGFloat(min(max(now - lastTime, 1.0 / 240.0), 1.0 / 20.0))
        lastTime = now
        if !toyBox.isEmpty { toyBox.update(dt: dt) }

        let cursor = V2(NSEvent.mouseLocation)
        if cursor.distance(to: lastCursor) > 0.4 {
            lastCursor = cursor
            for s in allSpiders { s.setCursor(cursor) }
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
            let moved = show(pose)
            settle(moved: updateVisitors(dt: dt, now: a) || moved || toyBox.astir, critters: spider.preyAstir)
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
            let moved = show(pose)
            settle(moved: updateVisitors(dt: dt, now: now) || moved || toyBox.astir, critters: spider.preyAstir)
        }
        if !inHabitat { updateHammock(dt: dt) }
        updateCarrying()
        updateTankEntry(now: now)
        updateWildlife(now: now)
        updatePrey()
        updateHand()
        updateSurroundings(now: now)

        // Only swallow clicks when the pointer is actually on the spider.
        let wantsMouse = interactive && (spider.isHeld || spider.hitTest(cursor))
        if window.ignoresMouseEvents == wantsMouse {
            window.ignoresMouseEvents = !wantsMouse
        }
    }

    /// Draws it where it is: in the tank when it is in there (and not in
    /// your hand), over the desktop otherwise. True if anything moved.
    private func show(_ pose: SpiderPose) -> Bool {
        if inHabitat, !spider.isHeld, let hc = habitat {
            if !drawnInTank {
                drawnInTank = true
                window.orderOut(nil)
                silkView.clear(slot: 0)
            }
            hc.scene.showCreatures(pose, sprite: spriteSide, prey: spider.prey)
            return hc.scene.didRedraw
        }
        if drawnInTank {
            drawnInTank = false
            window.orderFrontRegardless()
        }
        // In your hand, it is drawn over everything; what is loose in the
        // tank stays there.
        if inHabitat { habitat?.scene.showCreatures(nil, sprite: spriteSide, prey: spider.prey) }
        let moved = place(pose)
        view.apply(pose)
        return moved
    }

    /// Keeps the follower window centred on the spider. The window origin is
    /// rounded to whole points and the fraction is left to the layer, so motion
    /// stays smooth instead of stepping.
    /// Throttles the clock once the picture stops changing, and snaps straight
    /// back to full rate the moment it does.
    /// Only creatures on the move (the spider itself sitting still): half
    /// rate is plenty for them.
    private func settle(moved: Bool, critters: Bool = false) {
        if moved || view.didRedraw || spider.isHeld {
            calmFrames = 0
            calm = false
        } else {
            calmFrames += 1
            if calmFrames > 45 { calm = true }
        }
        critterPace = critters
    }

    /// The spider lives below the menu bar and the Dock — but the menu bar
    /// is drawn over everything under it, clear as it looks, so any of the
    /// spider up in its strip (legs reaching up as it hangs there, a leap or
    /// a throw going up through it) would vanish behind it. While any of it
    /// is up there it is lifted over the bar; the rest of the time it goes
    /// back under. A menu opened over it still covers it. (Not in its
    /// hammock, which hangs below the bar and is drawn over it on purpose,
    /// so it is seen through the silk.)
    private func raiseOverMenuBarIfNeeded(_ pose: SpiderPose) {
        guard !spider.inHammock else {
            if window.level != .floating { window.level = .floating }
            return
        }
        let r = spriteSide / 2
        let sprite = CGRect(x: pose.pos.x - r, y: pose.pos.y - r, width: r * 2, height: r * 2)
        let inStrip = !inHabitat && (NSScreen.screens.contains { s in
            let bar = s.frame.maxY - s.visibleFrame.maxY
            guard bar > 12 else { return false }
            return sprite.intersects(CGRect(x: s.frame.minX, y: s.frame.maxY - bar, width: s.frame.width, height: bar))
        } || map.dockRects.contains { sprite.intersects($0) })   // the Dock too: it climbs on it
        let want: NSWindow.Level = inStrip ? .statusBar : .floating
        if window.level != want { window.level = want }
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
        raiseOverMenuBarIfNeeded(pose)

        let wantSilk = silkView.apply(pose, slot: 0)
        return moved || wantSilk
    }

    /// The silk window is up while any spider has a line out.
    private func updateSilkWindow() {
        let want = silkView.anyShown
        if want, !silkVisible {
            silkVisible = true
            silkWindow.order(.below, relativeTo: window.windowNumber)
        } else if !want, silkVisible {
            silkVisible = false
            silkWindow.orderOut(nil)
        }
    }

    // MARK: - Visitors

    /// Runs the visitors for a frame — their comings and goings, and their
    /// games with your spider. True if anything moved or was redrawn.
    private func updateVisitors(dt: CGFloat, now: CFTimeInterval) -> Bool {
        if visitorsOn, now >= nextVisitAt {
            nextVisitAt = now + visitGap
            if visitors.count < Visitor.most, !inHabitat, !tankOpen, !awaitingEntrance,
               !spider.config.paused, cinemaScreens.isEmpty {
                arriveVisitor()
            }
        }
        var moved = false
        for v in visitors {
            v.spider.update(dt: dt)
            let pose = v.spider.pose()
            if v.show(pose, map: map) { moved = true }
            if silkView.apply(pose, slot: v.slot) { moved = true }
            if !v.leaving, now >= v.leaveAt || inHabitat { startLeaving(v, now: now) }
            if v.leaving { keepLeaving(v, now: now) }
        }
        updateSilkWindow()
        if !visitors.isEmpty {
            playground.update(host: spider, guests: visitors.filter { !$0.leaving }.map(\.spider), now: now)
            if playground.busy || visitors.contains(where: { $0.spider.isHeld }) { moved = true }
        }
        return moved
    }

    /// Someone drops by: down on a line from the top of the screen,
    /// somewhere along it, to stay a few minutes.
    private func arriveVisitor() {
        let used = Set(visitors.map(\.slot))
        let slot = (1...Visitor.most).first { !used.contains($0) } ?? visitors.count + 1
        let v = Visitor(map: map, slot: slot, scale: spider.config.scale, stay: visitLength)
        v.spider.toys = toyBox
        visitors.append(v)
        syncVisitors()
        v.spider.fullScreenApp = !cinemaScreens.isEmpty
        let f = NSScreen.main?.visibleFrame ?? worldFrame()
        v.spider.enterOnThread(from: V2(randRange(f.minX + 100, max(f.minX + 101, f.maxX - 100)), f.maxY))
        if !hidden { v.window.orderFrontRegardless() }
        calmFrames = 0
        calm = false
        refreshMenu()
    }

    /// Time to go: it stops playing, walks to the nearer side of the
    /// screen and leaps out past it.
    private func startLeaving(_ v: Visitor, now: CFTimeInterval) {
        v.leaving = true
        v.leavingSince = now
        v.spider.laser = nil
        v.spider.depart()
    }

    /// Gone once no part of it is on any screen. One that somehow cannot
    /// find its way off (held there, say) slips away after a good while.
    private func keepLeaving(_ v: Visitor, now: CFTimeInterval) {
        guard v.window.alphaValue == 1 else { return }
        let r = SpiderRenderer.spriteSide(for: v.spider.config.scale) / 2
        let p = v.spider.worldPos.point
        if !NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -r, dy: -r).contains(p) }) {
            removeVisitor(v)
        } else if now - v.leavingSince > 60, !v.spider.isHeld {
            fadeOut(v)
        }
    }

    private func fadeOut(_ v: Visitor) {
        guard v.window.alphaValue == 1, visitors.contains(where: { $0 === v }) else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.6
            v.window.animator().alphaValue = 0.01
        }, completionHandler: { [weak self] in self?.removeVisitor(v) })
    }

    private func removeVisitor(_ v: Visitor) {
        guard visitors.contains(where: { $0 === v }) else { return }
        playground.stop(allSpiders)
        v.window.orderOut(nil)
        silkView.clear(slot: v.slot)
        updateSilkWindow()
        visitors.removeAll { $0 === v }
        refreshMenu()
    }

    /// Visitors go by your spider's settings — its size, whether it
    /// follows the pointer, shoots silk, is paused — but never build.
    private func syncVisitors() {
        for v in visitors {
            let s = v.spider
            let rescale = s.config.scale != spider.config.scale
            s.config.scale = spider.config.scale
            s.config.followCursor = spider.config.followCursor
            s.config.pounceOnCursor = spider.config.pounceOnCursor
            s.config.webs = spider.config.webs
            s.config.hammocks = false
            s.config.paused = spider.config.paused
            s.drowsy = spider.drowsy
            s.raining = spider.raining
            if rescale { v.resize() }
        }
    }

    @objc private func toggleVisitors() {
        if !visitorsOn {
            let alert = NSAlert()
            alert.messageText = "Let other spiders visit?"
            alert.informativeText = "Now and then a spider will drop by to play with \(spider.name.isEmpty ? "yours" : spider.name) for a few minutes — up to \(Visitor.most) at once.\n\nEvery spider is animated sixty times a second, so each visitor uses a lot more CPU and battery. With several about, your Mac may run warm and its fans may come on."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Let Them Visit")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            visitorsOn = true
            // The first one soon, so it is plain that it worked.
            nextVisitAt = CACurrentMediaTime() + Double(randRange(4, 10))
        } else {
            visitorsOn = false
            let now = CACurrentMediaTime()
            for v in visitors where !v.leaving { startLeaving(v, now: now) }
        }
        saveSettings()
        refreshMenu()
    }

    @objc private func inviteVisitor() {
        nextVisitAt = 0
    }

    private func setVisitFrequency(_ v: CGFloat) {
        visitFrequency = v
        UserDefaults.standard.set(Double(v), forKey: "visitFrequency")
        // Made more often: the next one comes sooner, not after the old wait.
        nextVisitAt = min(nextVisitAt, CACurrentMediaTime() + visitGap)
    }

    private func setVisitStay(_ v: CGFloat) {
        visitStay = v
        UserDefaults.standard.set(Double(v), forKey: "visitStay")
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

    // MARK: - Window corners

    /// How round each window's corners are, measured once per window.
    private var cornerRadii: [CGWindowID: CGFloat] = [:]

    /// Fills in each window's corner radius — the spider's feet go on the
    /// curve of a window's corner, not out on the square corner where
    /// there is no window. Allowed to see the screen, it measures each
    /// window once (a couple of new ones a poll, so a crowded desktop is
    /// not all done at once); otherwise every window gets the default.
    private func withCornerRadii(_ windows: [TrackedWindow]) -> [TrackedWindow] {
        let canSee = CGPreflightScreenCaptureAccess()
        var budget = 2
        let live = Set(windows.map(\.id))
        cornerRadii = cornerRadii.filter { live.contains($0.key) }
        return windows.map { w in
            var w = w
            if let r = cornerRadii[w.id] {
                w.cornerRadius = r
            } else if canSee, budget > 0 {
                budget -= 1
                let r = AppDelegate.measureCornerRadius(of: w) ?? SurfaceMap.windowCornerRadius
                cornerRadii[w.id] = r
                w.cornerRadius = r
            }
            return w
        }
    }

    /// Looks at a window's top-left corner on its own: how far along its
    /// top row from the corner the window is still see-through is the
    /// radius of its rounding.
    private static func measureCornerRadius(of w: TrackedWindow) -> CGFloat? {
        guard let primary = NSScreen.screens.first else { return nil }
        let side: CGFloat = 48
        let rect = CGRect(x: w.frame.minX, y: primary.frame.maxY - w.frame.maxY, width: side, height: side)
        guard let img = CGWindowListCreateImage(rect, .optionIncludingWindow, w.id, [.boundsIgnoreFraming, .nominalResolution]),
              img.width > 4, img.height > 4 else { return nil }
        let n = img.width
        guard let ctx = CGContext(data: nil, width: n, height: img.height, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: img.height))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: n * img.height * 4)
        // Row 0 in memory is the top of the image.
        var run = 0
        while run < n, px[run * 4 + 3] < 128 { run += 1 }
        guard run > 0, run < n - 2 else { return nil }
        let r = CGFloat(run) * side / CGFloat(n)
        return clamp(r + 1, 4, 40)
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

    /// A colour seen once that is well away from the one it is wearing:
    /// taken on only if the next look sees it too, so walking past a
    /// busy patch of the picture does not have it flicking between colours.
    private var surroundingsCandidate: RGB?

    private func updateSurroundings(now: CFTimeInterval) {
        guard spider.look.isCamouflaged, now - lastSurroundingsSample > 0.4 else { return }
        lastSurroundingsSample = now
        let seen = sampleBehindSpider() ?? guessSurroundings()
        let current = spider.surroundings
        if seen.distance(to: current) < 0.09 {
            // Much the same: settle onto it.
            spider.surroundings = seen
            surroundingsCandidate = nil
        } else if let c = surroundingsCandidate, seen.distance(to: c) < 0.12 {
            // Seen twice running: it has really moved onto something else.
            spider.surroundings = c.mix(seen, 0.5)
            surroundingsCandidate = nil
        } else {
            surroundingsCandidate = seen
        }
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
        // About the size of the spider: the colour it is seen against.
        let r = 34 * spider.config.scale
        // Window-list space has its origin at the top left of the primary
        // display.
        guard let primary = NSScreen.screens.first else { return nil }
        let rect = CGRect(x: pos.x - r, y: primary.frame.maxY - (pos.y + r), width: r * 2, height: r * 2)
        guard let img = CGWindowListCreateImage(rect, [.optionOnScreenBelowWindow], CGWindowID(window.windowNumber), [.nominalResolution]) else { return nil }
        return AppDelegate.dominant(of: img)
    }

    private func guessSurroundings() -> RGB {
        var chrome = RGB(0.93, 0.93, 0.93)
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            chrome = RGB(NSColor.windowBackgroundColor)
        }
        if inHabitat { return habitat?.scene.colourBehind(bodyPoint) ?? chrome }
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
        return AppDelegate.dominant(of: crop)
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

    /// The colour most of an image is: its pixels sorted into coarse
    /// colour bins, and the average of the fullest bin. Blue sky with a few
    /// dark branches across it is blue, not the muddy mix an average gives;
    /// and a boundary between two colours is whichever has more of the
    /// patch, not a blend of both that matches neither.
    static func dominant(of img: CGImage) -> RGB {
        let n = 16
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return average(of: img) }
        ctx.interpolationQuality = .medium
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let data = ctx.data else { return average(of: img) }
        let px = data.bindMemory(to: UInt8.self, capacity: n * n * 4)
        // 6 levels a channel: coarse enough that a gradient or a texture
        // falls into a few bins, fine enough to tell blue from teal.
        var bins: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for i in 0..<(n * n) {
            let r = Int(px[i * 4]), g = Int(px[i * 4 + 1]), b = Int(px[i * 4 + 2])
            let key = (r * 6 / 256) * 36 + (g * 6 / 256) * 6 + (b * 6 / 256)
            var e = bins[key] ?? (0, 0, 0, 0)
            e.count += 1; e.r += r; e.g += g; e.b += b
            bins[key] = e
        }
        guard let topKey = bins.max(by: { $0.value.count < $1.value.count })?.key else { return average(of: img) }
        // The fullest bin and its neighbours: on a gradient the fullest bin
        // hands over to the next as it moves along, and taking the pixels
        // either side of the boundary too keeps the colour moving smoothly
        // rather than stepping a bin at a time.
        let (tr, tg, tb) = (topKey / 36, (topKey / 6) % 6, topKey % 6)
        var sum = (count: 0, r: 0, g: 0, b: 0)
        for (key, e) in bins where abs(key / 36 - tr) <= 1 && abs((key / 6) % 6 - tg) <= 1 && abs(key % 6 - tb) <= 1 {
            sum.count += e.count; sum.r += e.r; sum.g += e.g; sum.b += e.b
        }
        let k = CGFloat(max(sum.count, 1) * 255)
        return RGB(CGFloat(sum.r) / k, CGFloat(sum.g) / k, CGFloat(sum.b) / k)
    }

    /// Averages an image by drawing it down to a few pixels.
    static func average(of img: CGImage) -> RGB {
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
        // In the tank, they are drawn in there with it. The toys stay out on
        // the desktop.
        let prey = inHabitat ? [] : spider.prey
        if prey.isEmpty, toyBox.isEmpty {
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

    // MARK: Wildlife

    /// Now and then, if it is let, something finds its own way in — though
    /// not while nobody is about to see it, it is busy in the tank, or a
    /// full-screen app has the desktop. Then it tries again a while later.
    private func updateWildlife(now: CFTimeInterval) {
        guard wildOn, now >= nextWildAt else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let loose = spider.prey.filter { $0.state == .loose }.count
        guard !inHabitat, !tankOpen, !awaitingEntrance, !spider.config.paused, !spider.dormant, !away,
              cinemaScreens.isEmpty, idle < 300, loose < 2 else {
            nextWildAt = now + Double(randRange(120, 300))
            return
        }
        nextWildAt = now + wildGap
        let hour = Calendar.current.component(.hour, from: Date())
        if spider.releaseWild(night: hour >= 20 || hour < 6, raining: feelsWeather && sense.raining).isEmpty {
            nextWildAt = now + Double(randRange(120, 300))
        }
    }

    @objc private func toggleWildlife() {
        wildOn.toggle()
        // The first comes a little sooner, so you see what it is like.
        if wildOn { nextWildAt = CACurrentMediaTime() + min(wildGap, Double(randRange(90, 300))) }
        saveSettings()
        refreshMenu()
    }

    private func setWildFrequency(_ v: CGFloat) {
        wildFrequency = v
        nextWildAt = min(nextWildAt, CACurrentMediaTime() + wildGap)
        UserDefaults.standard.set(Double(v), forKey: "wildFrequency")
    }

    @objc private func feed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int, let kind = PreyKind(rawValue: raw) else { return }
        release(kind)
    }

    /// Not too many at once.
    private var canFeed: Bool { spider.prey.filter { $0.state == .loose }.count < 4 }

    private func release(_ kind: PreyKind) {
        guard canFeed else { return }
        spider.release(kind)
        calmFrames = 0
        calm = false
        refreshMenu()
    }

    // MARK: Toys

    @objc private func chooseToyItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int else { return }
        choose(raw < 0 ? .laser : ToyKind(rawValue: raw).map { .toy($0) })
    }

    /// The bell, out loud: a quiet tink, never more than a few a second.
    private func jingle(_ loud: CGFloat) {
        guard toySounds, !hidden else { return }
        let now = CACurrentMediaTime()
        guard now - lastJingleAt > 0.22, let sound = NSSound(named: "Tink")?.copy() as? NSSound else { return }
        lastJingleAt = now
        sound.volume = Float(0.06 + 0.2 * min(loud, 1))
        sound.play()
    }

    // MARK: Status item + menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = SpiderRenderer.statusItemImage(size: 17)
        statusItem.button?.toolTip = spider.name
        // A click drops the panel down; the old menu is still what a
        // right-click on the spider brings up.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updater.onChange = { [weak self] in self?.refreshMenu() }
    }

    /// The menu bar menu: only the everyday things. Everything else is in
    /// Settings.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let name = spider.name.isEmpty ? "Spider" : spider.name
        let toggle = NSMenuItem(title: hidden ? "Show \(name)" : "Hide \(name)",
                                action: #selector(toggleHidden), keyEquivalent: "h")
        toggle.target = self
        toggle.keyEquivalentModifierMask = []
        menu.addItem(toggle)
        add(menu, "Spider Studio…", #selector(openStudio), key: "s")
        add(menu, "Settings…", #selector(openSettings), key: ",")
        menu.addItem(.separator())

        let feedMenu = NSMenu()
        for kind in PreyKind.allCases {
            let item = NSMenuItem(title: "Release a \(kind.label)", action: #selector(feed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            feedMenu.addItem(item)
        }
        feedMenu.addItem(.separator())
        let wild = NSMenuItem(title: "Let Creatures Wander In", action: #selector(toggleWildlife), keyEquivalent: "")
        wild.target = self
        wild.state = wildOn ? .on : .off
        feedMenu.addItem(wild)
        let feedItem = NSMenuItem(title: "Feed", action: nil, keyEquivalent: "")
        feedItem.submenu = feedMenu
        menu.addItem(feedItem)

        // What the pointer plays with: the laser and the toys, one at a time.
        let toyMenu = NSMenu()
        toyMenu.autoenablesItems = false
        for (title, raw, pick) in [("Laser Pointer", -1, HandToy.laser)] + ToyKind.allCases.map({ ($0.label, $0.rawValue, HandToy.toy($0)) }) {
            let item = NSMenuItem(title: title, action: #selector(chooseToyItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = raw
            item.state = handToy == pick ? .on : .off
            toyMenu.addItem(item)
        }
        toyMenu.addItem(.separator())
        let away = NSMenuItem(title: "Put Away", action: #selector(putAway), keyEquivalent: "")
        away.target = self
        away.isEnabled = handToy != nil
        toyMenu.addItem(away)
        let toyItem = NSMenuItem(title: "Toys", action: nil, keyEquivalent: "")
        toyItem.submenu = toyMenu
        menu.addItem(toyItem)

        let size = NSMenu()
        for (name, s) in AppDelegate.sizes {
            let item = NSMenuItem(title: name, action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s
            item.state = abs(spider.config.scale - s) < 0.01 ? .on : .off
            size.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = size
        menu.addItem(sizeItem)
        menu.addItem(.separator())

        add(menu, "Bring \(name) to the Middle", #selector(teleportToMiddle))
        add(menu, "Reset Everything", #selector(resetEverything))
        menu.addItem(.separator())
        add(menu, "Quit \(AppInfo.name)", #selector(quit), key: "q")
        return menu
    }

    private static let sizes: [(String, CGFloat)] = [("Tiny", 0.62), ("Small", 0.78), ("Medium", 0.95),
                                                     ("Large", 1.2), ("Chonky", 1.55)]
    private static let energyLevels: [(String, CGFloat)] = [("Sleepy", 0.5), ("Calm", 0.8), ("Normal", 1.0),
                                                            ("Playful", 1.5), ("Caffeinated", 2.4)]

    // MARK: The panel

    private var panel: PanelController?

    /// Clicking the menu bar icon drops the panel down from it.
    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if panel == nil {
            panel = PanelController(pages: panelPages(), footer: [
                PanelButton("Spider Studio", symbol: "paintbrush.pointed") { [unowned self] in panel?.close(); openStudio() },
                PanelButton("Quit", symbol: "power") { [unowned self] in quit() },
            ], design: { [weak self] in self?.spider.design ?? SpiderDesign() })
        }
        panel?.toggle(from: button)
    }

    /// The panel opened at a given page (0 is the first).
    @objc private func openSettings() {
        if panel?.isShown != true { togglePanel() }
        panel?.show(page: 2)
    }

    private func panelPages() -> [PanelPage] {
        var name: String { spider.name.isEmpty ? "Your spider" : spider.name }
        let home = PanelPage(title: "Spider", symbol: "house", sections: [
            PanelSection(title: nil, rows: [
                .buttons([
                    PanelButton(title: { [unowned self] in hidden ? "Show \(name)" : "Hide \(name)" },
                                symbol: { [unowned self] in hidden ? "eye" : "eye.slash" }) { [unowned self] in toggleHidden() },
                    PanelButton("To the Middle", symbol: "scope") { [unowned self] in teleportToMiddle() },
                ]),
            ]),
            PanelSection(title: "Size", rows: [
                .choice(options: AppDelegate.sizes.map(\.0),
                        get: { [unowned self] in
                            AppDelegate.sizes.indices.min { abs(AppDelegate.sizes[$0].1 - spider.config.scale) < abs(AppDelegate.sizes[$1].1 - spider.config.scale) } ?? 2
                        },
                        set: { [unowned self] i in setScale(AppDelegate.sizes[i].1) }),
            ]),
            PanelSection(title: "Start Over", rows: [
                .note("Lost it, or something looks stuck? This starts the app afresh. Its looks and settings are kept."),
                .buttons([PanelButton("Reset Everything", symbol: "arrow.counterclockwise") { [unowned self] in resetEverything() }]),
            ]),
        ])
        let feed = PanelPage(title: "Feed", symbol: "fork.knife", sections: [
            PanelSection(title: "Let Something Loose", rows: [
                .note("It hunts down whatever you let go on the desktop, each its own way — and you can pick them up and move them about yourself."),
                .buttons(PreyKind.allCases.map { kind in
                    PanelButton("A \(kind.label)", symbol: AppDelegate.preySymbol(kind),
                                enabled: { [unowned self] in canFeed }) { [unowned self] in release(kind) }
                }),
                .status { [unowned self] in
                    let loose = spider.prey.filter { $0.state == .loose }.count
                    return loose >= 4 ? "That's plenty loose for now." : loose == 0 ? "Nothing loose right now." : loose == 1 ? "One on the loose." : "\(loose) on the loose."
                },
            ]),
            PanelSection(title: "Wildlife", rows: [
                .toggle("Let Creatures Wander In",
                        help: "Once in a while, unasked, something finds its way onto the desktop: a moth, a beetle, a little line of ants. It has to spot them before it can hunt them, and they don't stay forever.",
                        get: { [unowned self] in wildOn }, set: { [unowned self] on in if on != wildOn { toggleWildlife() } }),
                .slider("How Often They Come", low: "Rarely", high: "Now and Then",
                        get: { [unowned self] in wildFrequency }, set: { [unowned self] v in setWildFrequency(v) },
                        enabled: { [unowned self] in wildOn }),
                .status { [unowned self] in
                    guard wildOn else { return "Only what you let loose." }
                    let n = spider.prey.filter { $0.wild && $0.state == .loose }.count
                    let mins = Int(5400 * pow(600.0 / 5400, wildFrequency) / 60)
                    return n > 0 ? "Something has wandered in." : "About one every \(mins) minutes or so. Moths come out at night, worms in the rain."
                },
            ]),
            PanelSection(title: "Appetite", rows: [
                .status { [unowned self] in
                    spider.fed > 0.66 ? "\(name) is stuffed." : spider.fed > 0.2 ? "\(name) is content." : "\(name) could eat."
                },
            ]),
        ])
        let behavior = PanelPage(title: "Behavior", symbol: "slider.horizontal.3", sections: [
            PanelSection(title: "Energy", rows: [
                .choice(options: AppDelegate.energyLevels.map(\.0),
                        get: { [unowned self] in
                            let l = spider.basePersonality.liveliness
                            return AppDelegate.energyLevels.indices.min { abs(AppDelegate.energyLevels[$0].1 - l) < abs(AppDelegate.energyLevels[$1].1 - l) } ?? 2
                        },
                        set: { [unowned self] i in setEnergy(level: AppDelegate.energyLevels[i].1) }),
            ]),
            PanelSection(title: "The Pointer", rows: [
                .toggle("Follow the Cursor", help: "It notices the pointer, comes over to see it, and watches it.",
                        get: { [unowned self] in spider.config.followCursor }, set: { [unowned self] _ in toggleFollow() }),
                .toggle("Pounce on the Cursor", help: "Wiggle the pointer near it for long enough and it stalks it, pounces and hangs on.",
                        get: { [unowned self] in spider.config.pounceOnCursor }, set: { [unowned self] _ in togglePounce() },
                        enabled: { [unowned self] in spider.config.followCursor }),
                .toggle("Click to Pick Up", help: "Click it to say hello, drag it about and throw it. Off, clicks go straight through it.",
                        get: { [unowned self] in interactive }, set: { [unowned self] _ in toggleInteractive() }),
            ]),
            PanelSection(title: "Silk", rows: [
                .toggle("Shoot Webs", help: "Lines to swing on, drop down and climb up.",
                        get: { [unowned self] in spider.config.webs }, set: { [unowned self] _ in toggleWebs() }),
                .toggle("Build Hammocks", help: "Now and then it spins a hammock in a top corner of the screen and naps in it.",
                        get: { [unowned self] in spider.config.hammocks }, set: { [unowned self] _ in toggleHammocks() }),
            ]),
            PanelSection(title: "Your Mac", rows: [
                .toggle("Feel the Battery", help: "In Low Power Mode it gets sleepy and slow — and draws fewer frames, so it uses less power itself. Plugging in the charger perks it right up.",
                        get: { [unowned self] in feelsPower }, set: { [unowned self] _ in toggleFeelPower() }),
                .toggle("Notice the Weather", help: "When it rains where you are, rain is on its mind. It checks every twenty minutes, from Open-Meteo, going by roughly where your internet connection is (GeoJS).",
                        get: { [unowned self] in feelsWeather }, set: { [unowned self] _ in toggleFeelWeather() }),
                .toggle("Notice Pop-ups", help: "A notification sliding in makes it jump — right up in the air, if it is on top of something — and stare at it. Turn the volume or brightness up or down and it looks up to see. Nothing in a notification is read.",
                        get: { [unowned self] in feelsCommotion }, set: { [unowned self] _ in toggleFeelCommotion() }),
                .toggle("Rain on the Screen", help: "Faint streaks of rain across the desktop while it rains. Never over a full-screen app or in Low Power Mode.",
                        get: { [unowned self] in showsRain }, set: { [unowned self] _ in toggleShowRain() },
                        enabled: { [unowned self] in feelsWeather }),
                .status { [unowned self] in
                    let power = feelsPower && sense.lowPower ? "Low Power Mode: \(name) is feeling sleepy." : nil
                    let rain = feelsWeather && sense.raining ? "It's raining where you are." : nil
                    let said = [power, rain].compactMap { $0 }.joined(separator: " ")
                    return said.isEmpty ? "Nothing to report." : said
                },
            ]),
            PanelSection(title: "Growing Up", rows: [
                .toggle("Learn From Experience", help: "It remembers how things go — petting, play, frights, good hunts, time on its own — and its personality drifts a little with them, always close to what you set in the Studio. Nothing is needed of you. Off, it's exactly as the Studio made it.",
                        info: """
                            It remembers how things go: being stroked and said hello to, your company and its time alone, being carried or flung, frights, games, meals and hunts, and the spots where it settles.

                            Each memory has a feeling that passes within the hour, and a lesson that builds slowly over days and fades unless it happens again.

                            Together they nudge its personality a little — never more than a fifth of the way from what you set in the Studio, which stays just as you left it. A shy spider stroked often grows easier with you but stays shy. A run of frights leaves it warier for a while. Good hunts make it surer of itself, time on its own makes it more of an explorer, and favourite spots draw it back.

                            Nothing is needed of you: left be, it never sulks or suffers — it just grows a bit more independent. Turn this off and it's exactly as the Studio made it; what it remembers is kept for if you turn it back on. Forget It All starts it afresh.
                            """,
                        get: { [unowned self] in learns }, set: { [unowned self] _ in toggleLearning() }),
                .status { [unowned self] in
                    guard learns, let m = memory else { return "\(name) is just as the Studio made it." }
                    return m.summary(name: name, base: spider.basePersonality)
                },
                .buttons([
                    PanelButton("Forget It All", symbol: "arrow.uturn.backward", shown: { [unowned self] in learns }) { [unowned self] in forgetExperiences() },
                ]),
            ]),
            PanelSection(title: nil, rows: [
                .toggle("Pause", help: "It stays just where it is until you unpause it.",
                        get: { [unowned self] in spider.config.paused }, set: { [unowned self] _ in togglePause() }),
                .toggle("Launch at Login", help: "Opens by itself when you log in.",
                        get: { [unowned self] in loginEnabled }, set: { [unowned self] _ in toggleLogin() }),
                .buttons([
                    PanelButton(title: { [unowned self] in updater.busy ? "Checking…" : "Check for Updates" }, symbol: { "arrow.down.circle" },
                                enabled: { [unowned self] in !updater.busy }) { [unowned self] in checkForUpdates() },
                ]),
                .status { "Version \(Updater.currentVersion)" },
            ]),
        ])
        let play = PanelPage(title: "Play", symbol: "sparkles", sections: [
            PanelSection(title: "Ask It To", rows: [
                .buttons([
                    PanelButton("Come Here", symbol: "hand.wave") { [unowned self] in comeHere() },
                    PanelButton("Say Hi", symbol: "heart") { [unowned self] in sayHi() },
                    PanelButton("Toss It", symbol: "arrow.up.forward") { [unowned self] in toss() },
                    PanelButton("Swing!", symbol: "wind") { [unowned self] in swing() },
                    PanelButton("Peek-a-boo", symbol: "eyes") { [unowned self] in peekaboo() },
                ]),
            ]),
            PanelSection(title: "Laser & Toys", rows: [
                .buttons([PanelButton("Laser Pointer", symbol: "smallcircle.filled.circle",
                                      selected: { [unowned self] in handToy == .laser }) { [unowned self] in choose(.laser) }]
                         + ToyKind.allCases.map { kind in
                    PanelButton(kind.label, symbol: kind.symbol,
                                selected: { [unowned self] in handToy == .toy(kind) }) { [unowned self] in choose(.toy(kind)) }
                }),
                .status { [unowned self] in
                    switch handToy {
                    case nil: return "Pick one to play with it."
                    case .laser?: return "The red dot is on your pointer: it chases it wherever you take it."
                    case .toy(.feather)?: return "The feather dangles on its string from your pointer: wave it about for it to leap at."
                    case .toy(let kind)? where holdingToy:
                        return "The \(kind.label.lowercased()) is in your hand: take it where you want it and click to put it down, or drag and flick to throw it."
                    case .toy(let kind)?:
                        return "Drag the \(kind.label.lowercased()) to throw it again or click it to poke it, or press its button to pick it back up."
                    }
                },
                .buttons([
                    PanelButton("Put Away", symbol: "tray.and.arrow.down", shown: { [unowned self] in handToy != nil }) { [unowned self] in putAway() },
                ]),
                .toggle("Bell Sound", help: "The bell tinkles out loud — quietly — when it's knocked or shaken. Off, you only see it jingle.",
                        get: { [unowned self] in toySounds }, set: { [unowned self] on in toySounds = on; saveSettings() }),
            ]),
            PanelSection(title: "Hammock", rows: [
                .status { [unowned self] in
                    spider.hasHammock ? "\(name) has a hammock in the corner of the screen."
                        : spider.hasAnyHammock ? "\(name) is still spinning its hammock."
                        : spider.config.hammocks ? "No hammock yet." : "Hammocks are turned off in Behavior."
                },
                .buttons([
                    PanelButton("Build One", symbol: "hammer", enabled: { [unowned self] in spider.config.hammocks },
                                shown: { [unowned self] in !spider.hasAnyHammock }) { [unowned self] in buildHammock() },
                    PanelButton("Nap in It", symbol: "moon.zzz", shown: { [unowned self] in spider.hasHammock }) { [unowned self] in nap() },
                    PanelButton("Clear It Away", symbol: "trash", shown: { [unowned self] in spider.hasAnyHammock }) { [unowned self] in clearHammock() },
                ]),
            ]),
            PanelSection(title: "Places", rows: [
                .buttons([
                    PanelButton(title: { [unowned self] in spider.confine != nil ? "Redraw the Box" : "Draw a Box" }, symbol: { "square.dashed" }) { [unowned self] in panel?.close(); drawBox() },
                    PanelButton("Let It Out", symbol: "square.slash", shown: { [unowned self] in spider.confine != nil }) { [unowned self] in freeSpider() },
                    PanelButton(title: { [unowned self] in tankOpen ? "Close Habitat" : "Open Habitat" }, symbol: { "leaf" }) { [unowned self] in panel?.close(); toggleHabitat() },
                ]),
            ]),
        ])
        let visitorsPage = PanelPage(title: "Visitors", symbol: "person.2", sections: [
            PanelSection(title: nil, rows: [
                .toggle("Let Other Spiders Visit",
                        help: "Now and then a spider drops by to play, then heads off again. Up to \(Visitor.most) at once.",
                        get: { [unowned self] in visitorsOn }, set: { [unowned self] on in if on != visitorsOn { toggleVisitors() } }),
                .note("Now and then a spider drops by to play — hellos, dances, games of tag — then heads off again. They come in all sorts of looks, but aren't yours to dress up."),
            ]),
            PanelSection(title: "Visits", rows: [
                .slider("How Often They Visit", low: "Rarely", high: "Often",
                        get: { [unowned self] in visitFrequency }, set: { [unowned self] v in setVisitFrequency(v) },
                        enabled: { [unowned self] in visitorsOn }),
                .slider("How Long They Stay", low: "Briefly", high: "Ages",
                        get: { [unowned self] in visitStay }, set: { [unowned self] v in setVisitStay(v) },
                        enabled: { [unowned self] in visitorsOn }),
                .buttons([
                    PanelButton("Invite One Now", symbol: "envelope",
                                enabled: { [unowned self] in visitorsOn && visitors.count < Visitor.most && !inHabitat }) { [unowned self] in inviteVisitor() },
                ]),
                .status { [unowned self] in
                    let n = visitors.filter { !$0.leaving }.count
                    return n == 0 ? "No one visiting right now." : n == 1 ? "One visitor about." : "\(n) visitors about (\(Visitor.most) at most)."
                },
            ]),
            PanelSection(title: "A Note on Power", rows: [
                .note("Each spider is animated sixty times a second, so every visitor uses a lot more CPU and battery. With several about, your Mac may run warm and its fans may come on."),
            ]),
        ])
        return [home, feed, behavior, play, visitorsPage]
    }

    private static func preySymbol(_ k: PreyKind) -> String {
        switch k {
        case .cricket: return "hare"
        case .worm: return "scribble"
        case .fruitFly: return "circle.dotted"
        case .moth: return "moon.stars"
        case .beetle: return "shield"
        case .ant: return "ant"
        case .mosquito: return "wind"
        case .ladybug: return "ladybug"
        }
    }

    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector,
                     key: String = "", state: Bool? = nil) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = self
        if let s = state { item.state = s ? .on : .off }
        menu.addItem(item)
    }

    private func refreshMenu() {
        panel?.refresh()
    }

    @objc private func showContextMenu(_ note: Notification) {
        let menu = buildMenu()
        if let event = note.object as? NSEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: event.window?.contentView ?? view)
        }
    }

    // MARK: Actions

    @objc private func toggleHidden() {
        hidden.toggle()
        if hidden {
            // Put away, it is put away from the tank too.
            if habitat?.window.isVisible == true { closeHabitat(animated: false) }
            window.orderOut(nil)
            silkWindow.orderOut(nil)
            silkVisible = false
            hammockWindow.orderOut(nil)
            // The creatures go with it (and come back with it); the toys are
            // put away.
            putAway()
            preyWindow.orderOut(nil)
            preyShown = false
            // Visitors don't hang about while it is away.
            for v in visitors { v.window.orderOut(nil); silkView.clear(slot: v.slot) }
            visitors = []
            playground.stop([spider])
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
    //
    // Open, the tank is a window over the desktop. The spider shoots a line
    // up to the lip of its ground and climbs in; inside, it lives on the
    // tank's own surfaces and is drawn in the tank, among its furniture.
    // It never leaves by itself — but it can be picked up and carried out
    // (and it goes back in after a while), or dropped in from outside.
    // Closed, the tank goes, and it drops from wherever it was in it.

    /// The tank is open: up, or on its way up.
    private var tankOpen: Bool { habitat.map { $0.window.isVisible || $0.window.isMiniaturized } == true && !tankClosing }
    private var tankClosing = false
    /// The desktop overlay was put away because it is drawn in the tank.
    private var drawnInTank = false
    /// The user's box, set aside while the tank is open: it goes to the
    /// tank whatever box it is kept in, and comes back to it after.
    private var boxWhileInTank: CGRect?
    /// Outside with the tank open, it heads back in once it is this time.
    private var headInAfter: CFTimeInterval = 0
    private var lastEntryNudge: CFTimeInterval = 0
    private var onLineSince: CFTimeInterval = -1
    private static let tankOriginKey = "habitatOrigin"

    @objc private func toggleHabitat() {
        if tankOpen { closeHabitat() } else { openHabitat() }
    }

    private var spiderName: String { spider.name.isEmpty ? "Your spider" : spider.name }

    private func makeHabitat() -> HabitatController {
        if let hc = habitat { return hc }
        let hc = HabitatController(spiderName: spider.name)
        hc.scene.spider = spider
        hc.scene.map.standoff = map.standoff
        hc.onLetOut = { [weak self] in self?.closeHabitat() }
        hc.onFeed = { [weak self] kind in self?.release(kind) }
        hc.canFeed = { [weak self] in self?.canFeed ?? false }
        habitat = hc
        return hc
    }

    /// Where the tank opens: over the spider, with room under it for a
    /// line, if there is room on its screen; otherwise where it last was.
    private func tankFrame(_ hc: HabitatController) -> CGRect {
        let size = hc.tankSize
        let p = spider.worldPos
        let screen = NSScreen.screens.first { $0.frame.contains(p.point) } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? worldFrame()
        let lift = max(150, 110 * spider.config.scale)
        var f = CGRect(x: p.x - size.width / 2, y: p.y + lift - HabitatRootView.base, width: size.width, height: size.height)
        f.origin.x = min(max(f.minX, vis.minX + 6), vis.maxX - size.width - 6)
        if f.maxY <= vis.maxY - 2, size.width < vis.width { return f }
        if let o = UserDefaults.standard.array(forKey: AppDelegate.tankOriginKey) as? [Double], o.count == 2 {
            let saved = CGRect(x: o[0], y: o[1], width: size.width, height: size.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved.insetBy(dx: 100, dy: 100)) }) { return saved }
        }
        return CGRect(x: vis.midX - size.width / 2, y: vis.maxY - size.height - 20, width: size.width, height: size.height)
    }

    /// Opens the tank. `restoring`: it was in there when the app last
    /// quit, and is put straight back.
    private func openHabitat(restoring: Bool = false) {
        if let hc = habitat, hc.window.isVisible || hc.window.isMiniaturized, !tankClosing {
            NSApp.activate(ignoringOtherApps: true)
            if hc.window.isMiniaturized { hc.window.deminiaturize(nil) }
            hc.window.makeKeyAndOrderFront(nil)
            return
        }
        if hidden { toggleHidden() }
        let hc = makeHabitat()
        tankClosing = false
        boxWhileInTank = spider.confine
        if spider.confine != nil {
            spider.confine = nil
            boxWindow.orderOut(nil)
        }
        let target = tankFrame(hc)
        // It rises into place and fades in.
        hc.window.setFrame(target.offsetBy(dx: 0, dy: -24), display: false)
        hc.window.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        hc.window.makeKeyAndOrderFront(nil)
        hc.scene.syncToScreen()
        headInAfter = CACurrentMediaTime() + 0.45
        hc.setStatus(restoring ? nil : "\(spiderName) is on the way in…")
        if restoring {
            hc.window.setFrame(target, display: true)
            hc.scene.syncToScreen()
            let spots = hc.scene.groundSpots()
            let middle = V2(hc.scene.screenScene.midX, hc.scene.screenGroundY)
            spider.placeInHabitat(map: hc.scene.map, at: spots.min { $0.distance(to: middle) < $1.distance(to: middle) } ?? middle)
            settleIn()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hc.window.animator().setFrame(target, display: true)
            hc.window.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            hc.window.setFrame(target, display: true)
            hc.scene.syncToScreen()
            self?.refreshMenu()
        })
        calmFrames = 0
        calm = false
        refreshMenu()
    }

    /// Each frame while the tank is open and it is not in it: it makes its
    /// way in. On the ground (or a window) under the tank, a line up to the
    /// lip of its ground and a climb; off to one side, it walks over; up
    /// above it, it drops down; flying, it is in the moment it is over it.
    private func updateTankEntry(now: CFTimeInterval) {
        guard let hc = habitat, tankOpen, !inHabitat, !spider.isHeld, now >= headInAfter else { return }
        if spider.config.paused {
            hc.setStatus("\(spiderName) is paused — unpause it to let it climb in")
            return
        }
        let scene = hc.scene.screenScene
        let p = spider.worldPos
        if spider.isAirborne {
            if scene.insetBy(dx: 10, dy: 10).contains(p.point) {
                spider.moveInMidAir(map: hc.scene.map, habitat: true)
                settleIn()
            }
            return
        }
        if spider.isOnLine {
            // Climbing its line in: nothing to do but wait. On any other
            // line, it lets go and drops, to get somewhere it can shoot from.
            guard !spider.isClimbingAway else { onLineSince = -1; return }
            if onLineSince < 0 { onLineSince = now }
            if now - onLineSince > 1.2 { spider.letGo(); onLineSince = -1 }
            return
        }
        onLineSince = -1
        if spider.inHammock {
            if now - lastEntryNudge > 2 { lastEntryNudge = now; spider.leaveHammock() }
            return
        }
        guard spider.currentLoopID != nil, !spider.isLeavingSurface else { return }
        // The lip of the open ground nearest to straight above it.
        let lip = hc.scene.screenGroundY
        guard let target = hc.scene.groundSpots().min(by: { abs($0.x - p.x) < abs($1.x - p.x) }) else { return }
        let rise = lip - p.y
        // Straight up is best; having tried a while for a spot like that,
        // it settles for a line at a slant, and swings in on it.
        let patient = now - headInAfter > 10
        if rise > (patient ? 45 : 70), abs(target.x - p.x) < rise * (patient ? 1.6 : 0.7) {
            if spider.climbIntoHabitat(at: V2(target.x, lip), arrived: { [weak self] in self?.climbedIn(landing: target) }) {
                hc.setStatus("\(spiderName) is climbing in…")
            }
            return
        }
        guard now - lastEntryNudge > 2.2 else { return }
        lastEntryNudge = now
        // Not somewhere it can shoot from: over to a ledge under the tank
        // that it can — a leap if it can make it, a walk along if it is
        // on the same edge — and failing that, down, or across.
        let lips = hc.scene.groundSpots()
        let perches = map.sampleSpots(spacing: 40).filter { s in
            guard s.seg.facing == .up, map.isOnScreen(s.point, slack: -20) else { return false }
            let up = lip - s.point.y
            return up > 110 && lips.contains { abs($0.x - s.point.x) < up * 0.5 }
        }
        let near = perches.sorted { $0.point.distance(to: p) < $1.point.distance(to: p) }
        if let spot = near.first, spot.loop.id == spider.currentLoopID {
            spider.summon(to: spot.point)
            return
        }
        for spot in near.prefix(10) where spider.leapIn(to: spot.point) { return }
        // On the rim of the screen: down the wall and along the floor.
        if spider.currentLoopID == "screen:0", let spot = near.first(where: { $0.loop.id == "screen:0" }) ?? near.first {
            spider.summon(to: spot.point)
            return
        }
        if rise <= 70 {
            // Level with the tank or above it: down first.
            spider.dropOff()
        } else {
            // Below it but off to the side: over to under it.
            spider.summon(to: V2(target.x, p.y))
        }
    }

    /// At the top of its line: over the lip and onto the ground.
    private func climbedIn(landing target: V2) {
        guard let hc = habitat, tankOpen, !inHabitat else { return }
        spider.hopIntoHabitat(map: hc.scene.map, landing: target)
        settleIn()
    }

    /// In: it lives on the tank's surfaces now, and is drawn in there.
    private func settleIn() {
        inHabitat = true
        hammockWindow.orderOut(nil)
        hammockShown = false
        lastHammock = nil
        boxWindow.orderOut(nil)
        laserWindow.orderOut(nil)
        spider.laser = nil
        silkView.clear(slot: 0)
        updateSilkWindow()
        habitat?.setStatus(nil)
        calmFrames = 0
        calm = false
        refreshMenu()
    }

    /// Out, with the tank still open (carried out by hand): on the desktop,
    /// drawn over it as ever; after a while it heads back in.
    private func carriedOut() {
        inHabitat = false
        spider.moveInMidAir(map: map, habitat: false)
        headInAfter = CACurrentMediaTime() + 12
        habitat?.setStatus("\(spiderName) is out on your desktop — it’ll climb back in")
        refreshMenu()
    }

    /// Carried to the tank and let go of over it, or carried out of it —
    /// whichever side of the glass it is on is where it is.
    private func updateCarrying() {
        guard spider.isHeld, let hc = habitat, tankOpen else { return }
        let scene = hc.scene.screenScene
        let p = spider.worldPos.point
        if inHabitat, !scene.insetBy(dx: -6, dy: -6).contains(p) {
            carriedOut()
        } else if !inHabitat, scene.insetBy(dx: 16, dy: 16).contains(p) {
            spider.moveInMidAir(map: hc.scene.map, habitat: true)
            settleIn()
        }
    }

    /// Closes the tank. If it is in there, it drops from the very spot it
    /// was, onto whatever is below on the desktop, as the tank fades away.
    private func closeHabitat(animated: Bool = true) {
        guard let hc = habitat, hc.window.isVisible || hc.window.isMiniaturized, !tankClosing else { return }
        tankClosing = true
        if inHabitat {
            inHabitat = false
            spider.dropOutOfHabitat(onto: map)
        } else if spider.isClimbingAway {
            // Halfway up its line into it: the line goes with the tank.
            spider.dropOutOfHabitat(onto: map)
        }
        hc.scene.showCreatures(nil, sprite: spriteSide, prey: [])
        if drawnInTank {
            // Straight back over the desktop, this frame, where it was.
            drawnInTank = false
            _ = place(spider.pose())
            window.orderFrontRegardless()
        }
        if hc.decorating { hc.toggleDecorate() }
        if let box = boxWhileInTank {
            spider.confine = box
            boxWindow.orderFrontRegardless()
            boxWhileInTank = nil
        }
        let f = hc.window.frame
        UserDefaults.standard.set([Double(f.minX), Double(f.minY)], forKey: AppDelegate.tankOriginKey)
        calmFrames = 0
        calm = false
        refreshMenu()
        let finish = { [weak self] in
            hc.window.orderOut(nil)
            hc.window.alphaValue = 1
            hc.window.setFrame(f, display: false)
            self?.tankClosing = false
            self?.refreshMenu()
        }
        guard animated else { finish(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hc.window.animator().alphaValue = 0
            hc.window.animator().setFrame(f.offsetBy(dx: 0, dy: -18), display: true)
        }, completionHandler: finish)
    }

    // MARK: Habitat testing

    /// The saved state a habitat test may touch, to put back afterwards.
    private func habitatTestSnapshot() -> () -> Void {
        let keys = [Habitat.key, HabitatController.tankWidthKey, AppDelegate.tankOriginKey, "inHabitat"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        return {
            for (k, v) in zip(keys, saved) { UserDefaults.standard.set(v, forKey: k) }
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        }
    }

    /// Ends a test: the saved state put back, and a moment for it to reach
    /// the disk before the app goes.
    private func finishHabitatTest(_ restore: () -> Void) {
        restore()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exit(0) }
    }

    /// A picture of our own windows in `rect` (other apps' need permission).
    private func debugShot(_ path: String, rect: CGRect, window: NSWindow? = nil) {
        let img: CGImage?
        if let window {
            img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution])
        } else {
            guard let primary = NSScreen.screens.first else { return }
            let r = CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            img = CGWindowListCreateImage(r, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
        }
        guard let img else { return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func runHabitatTest(dir: String?) {
        print("habitat test: launched with inHabitat pref \(UserDefaults.standard.bool(forKey: "inHabitat")), open \(tankOpen)")
        let restore = habitatTestSnapshot()
        func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
        func report(_ label: String) {
            let p = spider.worldPos
            let scene = habitat?.scene.screenScene ?? .zero
            print(String(format: "habitat test: %@ in=%@ open=%@ at %.0f,%.0f %@ climbing=%@ scene %.0f,%.0f %.0fx%.0f ground %.0f",
                         label, "\(inHabitat)", "\(tankOpen)", p.x, p.y, spider.debugState, "\(spider.isClimbingAway)",
                         scene.minX, scene.minY, scene.width, scene.height, habitat?.scene.screenGroundY ?? 0))
            fflush(stdout)
        }
        func shot(_ name: String) {
            guard let dir, let hc = habitat else { return }
            let r = hc.window.frame.union(CGRect(x: spider.worldPos.x - 150, y: spider.worldPos.y - 150, width: 300, height: 300)).insetBy(dx: -40, dy: -40)
            debugShot("\(dir)/\(name).png", rect: r)
        }
        after(1) { [self] in
            report("before")
            openHabitat()
            for i in 1...24 { after(Double(i) * 0.5) { report(String(format: "open+%.1f", Double(i) * 0.5)) } }
            for t in [0.6, 1.2, 2.0, 3.0, 5.0, 8.0] { after(t) { shot(String(format: "enter_%.1f", t)) } }
        }
        // Carried out of the tank by hand, and let go of on the desktop.
        after(14) { [self] in
            guard let hc = habitat else { return }
            report("before carry")
            let from = spider.worldPos
            let out = V2(hc.window.frame.minX - 180, hc.window.frame.midY)
            spider.beginGrab(at: from)
            var step = 0
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
                step += 1
                self.spider.moveGrab(to: V2.lerp(from, out, CGFloat(min(step, 50)) / 50))
                if step >= 60 { t.invalidate(); self.spider.endGrab(throwVelocity: .zero); report("let go outside") }
            }
            for i in 1...20 { after(1.2 + Double(i) * 1.0) { report("outside+\(i)") } }
            after(3) { shot("outside") }
        }
        // The tank moved about with it inside.
        after(36) { [self] in
            guard let hc = habitat else { return }
            report("before move")
            let rel = spider.worldPos - V2(hc.scene.screenScene.origin)
            hc.window.setFrameOrigin(CGPoint(x: hc.window.frame.minX + 120, y: hc.window.frame.minY - 60))
            after(0.3) {
                let now = self.spider.worldPos - V2(hc.scene.screenScene.origin)
                print(String(format: "habitat test: moved tank; spider relative to scene %.1f,%.1f -> %.1f,%.1f", rel.x, rel.y, now.x, now.y))
                report("after move")
            }
        }
        // Decorating: every kind of thing in, moved about, sized, flipped, taken out.
        after(38) { [self] in
            guard let hc = habitat else { return }
            hc.toggleDecorate()
            after(0.6) {
                for k in HabitatItemKind.allCases { hc.scene.add(k) }
                hc.scene.updateSelected { $0.w *= 1.5; $0.h *= 1.5 }
                hc.scene.duplicateSelected()
                hc.scene.updateSelected { $0.flipped.toggle() }
                hc.scene.removeSelected()
                hc.setBiome(.night)
                after(1.5) { shot("decorating") }
                after(2.5) {
                    hc.undo(); hc.undo(); hc.undo()
                    report("decorated: \(hc.scene.habitat.items.count) things")
                    hc.loadPreset(.forestFloor)
                    hc.toggleDecorate()
                }
            }
        }
        // Fed in the tank.
        after(43) { [self] in
            for kind in PreyKind.allCases { release(kind) }
            after(0.5) { print("habitat test: prey in tank \(self.spider.prey.count)"); shot("fed") }
        }
        // Closed: it drops from right where it is.
        after(50) { [self] in
            report("before close")
            let at = spider.worldPos
            closeHabitat()
            let now = spider.worldPos
            print(String(format: "habitat test: closed; moved %.2f px at the moment of closing, now %@", at.distance(to: now), spider.debugState))
            after(0.15) { shot("close_0.15"); report("close+0.15") }
            after(0.6) { shot("close_0.6"); report("close+0.6") }
            after(2.0) { shot("close_2.0"); report("close+2.0") }
        }
        after(54) {
            self.finishHabitatTest(restore)
        }
    }

    /// SPIDER_HABITAT_INPUT=1: the tank's mouse and keys, by synthesized
    /// events: the spider picked up in there and carried out, a piece
    /// clicked, dragged, resized by its corner, deleted and undone, and the
    /// window resized.
    private func runHabitatInputTest() {
        let restore = habitatTestSnapshot()
        func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            print("habitat input: [\(ok ? "ok  " : "FAIL")] \(label) \(detail)")
            fflush(stdout)
        }
        openHabitat(restoring: true)
        guard let hc = habitat else { return }
        let scene = hc.scene
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1) {
            // `p` in the scene view's coordinates.
            let w = scene.convert(p, to: nil)
            guard let e = NSEvent.mouseEvent(with: type, location: w, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: hc.window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) else { return }
            switch type {
            case .leftMouseDown: scene.mouseDown(with: e)
            case .leftMouseDragged: scene.mouseDragged(with: e)
            default: scene.mouseUp(with: e)
            }
        }
        func key(_ code: UInt16, _ chars: String, _ mods: NSEvent.ModifierFlags = []) {
            guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: hc.window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                           isARepeat: false, keyCode: code) else { return }
            scene.keyDown(with: e)
        }
        func drag(_ from: CGPoint, _ to: CGPoint, steps: Int, then: @escaping () -> Void) {
            mouse(.leftMouseDown, from)
            var i = 0
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
                i += 1
                let u = CGFloat(i) / CGFloat(steps)
                mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * u, y: from.y + (to.y - from.y) * u))
                if i >= steps { t.invalidate(); mouse(.leftMouseUp, to); then() }
            }
        }
        after(3) { [self] in
            check("in the tank after opening", inHabitat, spider.debugState)
            // Picked up in the tank and carried out past its left side.
            let local = CGPoint(x: spider.worldPos.x - scene.screenOrigin.x, y: spider.worldPos.y - scene.screenOrigin.y)
            drag(local, CGPoint(x: -260, y: local.y), steps: 40) {
                check("carried out: out of the tank", !self.inHabitat && !self.spider.inHabitat, self.spider.debugState)
                check("carried out: drawn over the desktop", self.window.isVisible)
                after(0.5) {
                    // Straight back in, by hand, for the rest.
                    self.spider.beginGrab(at: self.spider.worldPos)
                    self.spider.moveGrab(to: V2(scene.screenScene.midX, scene.screenScene.midY))
                    after(0.3) {
                        self.updateCarrying()
                        self.spider.endGrab(throwVelocity: .zero)
                        check("carried back in", self.inHabitat, self.spider.debugState)
                    }
                }
            }
        }
        after(6) {
            hc.scene.setHabitat(Habitat.preset(.forestFloor))
            if !hc.decorating { hc.toggleDecorate() }
        }
        after(7) {
            guard let log = scene.habitat.items.first(where: { $0.kind == .log }) else { check("a log to test with", false); return }
            let r = scene.toView(log.rect)
            let start = CGPoint(x: r.midX, y: r.midY)
            drag(start, CGPoint(x: start.x + 120, y: start.y + 40), steps: 20) {
                let moved = scene.habitat.items.first { $0.id == log.id }!
                check("clicked piece is selected", scene.selected == log.id)
                check("dragged along", abs(moved.x - log.x - 120 / (scene.bounds.width / HabitatLayout.width)) < 3, String(format: "x %.0f -> %.0f", log.x, moved.x))
                check("let go in the air, it comes to rest on what is under it", moved.y < 40 && (moved.y == 0 || scene.habitat.items.contains { o in
                    o.id != log.id && (Habitat.solidRect(o).map { abs($0.maxY - HabitatLayout.ground - moved.y) < 0.5 } ?? false) }), String(format: "y %.1f", moved.y))
                // Its top-right handle, pulled out.
                let r2 = scene.toView(moved.rect).insetBy(dx: -5, dy: -5)
                drag(CGPoint(x: r2.maxX, y: r2.maxY), CGPoint(x: r2.maxX + 80, y: r2.maxY + 30), steps: 15) {
                    let grown = scene.habitat.items.first { $0.id == log.id }!
                    check("corner handle resizes it", grown.w > moved.w * 1.1, String(format: "w %.0f -> %.0f", moved.w, grown.w))
                    check("resized in proportion", abs(grown.w / grown.h - moved.w / moved.h) < 0.02)
                    let count = scene.habitat.items.count
                    key(51, "\u{7f}")
                    check("⌫ removes it", scene.habitat.items.count == count - 1 && scene.selected == nil)
                    key(6, "z", .command)
                    check("⌘Z brings it back", scene.habitat.items.count == count && scene.habitat.items.contains { $0.id == log.id })
                    key(6, "z", [.command, .shift])
                    check("⇧⌘Z takes it out again", scene.habitat.items.count == count - 1)
                    hc.undo()
                    key(53, "\u{1b}")
                    hc.toggleDecorate()
                }
            }
        }
        after(10) { [self] in
            // The window pulled wider: the tank keeps its shape.
            let proposed = CGSize(width: hc.window.frame.width + 200, height: hc.window.frame.height)
            let size = hc.windowWillResize(hc.window, to: proposed)
            hc.window.setFrame(CGRect(origin: hc.window.frame.origin, size: size), display: true)
            after(0.5) {
                let s = scene.bounds
                check("tank keeps its shape", abs(s.height / s.width - HabitatLayout.aspect) < 0.01, String(format: "%.0fx%.0f", s.width, s.height))
                check("spider still in the tank", scene.screenScene.insetBy(dx: -10, dy: -10).contains(self.spider.worldPos.point) && self.inHabitat, self.spider.debugState)
                self.closeHabitat(animated: false)
                check("closed", !self.inHabitat && !self.tankOpen)
                after(0.5) { self.finishHabitatTest(restore) }
            }
        }
    }

    private func runHabitatShots(dir: String) {
        let restore = habitatTestSnapshot()
        openHabitat(restoring: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            guard let hc = habitat else { return }
            var presets = Habitat.Preset.allCases
            func next() {
                guard let p = presets.first else {
                    hc.scene.setHabitat(Habitat.preset(.forestFloor))
                    hc.toggleDecorate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        hc.scene.select(hc.scene.habitat.items.first { $0.kind == .log }?.id)
                        self.debugShot("\(dir)/habitat_decorating.png", rect: .zero, window: hc.window)
                        for tab in 1...2 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(tab) * 0.8) {
                                hc.debugShowTab(tab)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    self.debugShot("\(dir)/habitat_decorating_tab\(tab).png", rect: .zero, window: hc.window)
                                    if tab == 2 { self.finishHabitatTest(restore) }
                                }
                            }
                        }
                    }
                    return
                }
                presets.removeFirst()
                hc.scene.setHabitat(Habitat.preset(p))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.debugShot("\(dir)/habitat_\(p.rawValue).png", rect: .zero, window: hc.window)
                    next()
                }
            }
            next()
        }
    }

    // MARK: Toys and the laser
    //
    // What the pointer plays with, one at a time: the laser, or a toy. The
    // laser's dot sits right on the pointer, and the feather dangles from it
    // on its string, for as long as they are picked. The ball, the bell and
    // the bug come in your hand, riding along with the pointer: take it
    // where you want it and click to put it down there (or drag and flick
    // to throw it). Put down, a toy stays where it ends up — to be dragged
    // and thrown again, poked, or picked back up with its button — and still
    // gets played with now and then. Put Away puts it away.

    private enum HandToy: Equatable { case laser, toy(ToyKind) }
    private var handToy: HandToy?
    private var laserOn: Bool { handToy == .laser }
    /// A ball, bell or bug is in your hand, waiting to be put down.
    private var holdingToy = false
    private var toyDrag: [(p: V2, t: TimeInterval)] = []
    /// Rides under the pointer while a toy is in hand, to take the click.
    private lazy var handWindow: OverlayWindow = {
        let w = OverlayWindow(frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        w.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        let v = HandCatchView(frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        v.onDown = { [weak self] e in self?.handDown(e) }
        v.onDrag = { [weak self] e in self?.handDrag(e) }
        v.onUp = { [weak self] e in self?.handUp(e) }
        w.contentView = v
        w.ignoresMouseEvents = false
        return w
    }()

    @objc private func toggleLaser() { choose(laserOn ? nil : .laser) }

    /// Picks what the pointer plays with. Picking what is already picked
    /// takes a toy that has been put down back in hand; otherwise it puts
    /// it away.
    private func choose(_ h: HandToy?) {
        if let h, h == handToy {
            if case .toy(let kind) = h, kind.tether == 0, let toy = toyBox.toys.first, !toy.held {
                takeInHand(toy)
            } else {
                putAway()
            }
            return
        }
        putAway()
        guard let h, !hidden else { return }
        handToy = h
        switch h {
        case .laser:
            break
        case .toy(let kind):
            let p = V2(NSEvent.mouseLocation)
            let toy = toyBox.place(kind, at: p)
            for s in allSpiders { s.seeToy(toy) }
            if kind.tether > 0 { toy.grab(at: p) } else { takeInHand(toy) }
        }
        updateHand()
        calmFrames = 0
        calm = false
        refreshMenu()
    }

    @objc private func putAway() {
        if laserOn {
            for s in allSpiders { s.laser = nil }
            laserWindow.orderOut(nil)
        }
        toyBox.removeAll()
        holdingToy = false
        toyDrag = []
        handWindow.orderOut(nil)
        handToy = nil
        refreshMenu()
    }

    private func takeInHand(_ toy: Toy) {
        toy.grab(at: V2(NSEvent.mouseLocation))
        holdingToy = true
        toyDrag = []
        refreshMenu()
    }

    /// Every frame: the dot and the toy with the pointer, and the catcher
    /// under it while a toy is in hand.
    private func updateHand() {
        let p = V2(NSEvent.mouseLocation)
        switch handToy {
        case .laser?:
            // Not in the tank: the dot is a desktop game.
            guard !inHabitat else {
                if spider.laser != nil { spider.laser = nil; laserWindow.orderOut(nil) }
                return
            }
            laserWindow.setFrameOrigin(CGPoint(x: p.x - 18, y: p.y - 18))
            if !laserWindow.isVisible { laserWindow.orderFrontRegardless() }
            laserView.phase += 0.016
            // Visitors go for the dot too — except one on its way out.
            spider.laser = p
            for v in visitors where !v.leaving { v.spider.laser = p }
        case .toy?:
            guard let toy = toyBox.toys.first else { return }
            if toy.dangling {
                toy.drag(to: p)
            } else if toy.kind.tether > 0 {
                // The feather is always on its string.
                toy.grab(at: p)
            } else if holdingToy {
                toy.drag(to: p)
            }
        case nil:
            break
        }
        if holdingToy {
            handWindow.setFrameOrigin(CGPoint(x: p.x - 80, y: p.y - 80))
            if !handWindow.isVisible { handWindow.orderFrontRegardless() }
        } else if handWindow.isVisible {
            handWindow.orderOut(nil)
        }
    }

    private func handDown(_ e: NSEvent) {
        toyDrag = [(V2(NSEvent.mouseLocation), e.timestamp)]
    }

    private func handDrag(_ e: NSEvent) {
        let p = V2(NSEvent.mouseLocation)
        toyBox.toys.first?.drag(to: p)
        handWindow.setFrameOrigin(CGPoint(x: p.x - 80, y: p.y - 80))
        toyDrag.append((p, e.timestamp))
        if toyDrag.count > 8 { toyDrag.removeFirst(toyDrag.count - 8) }
    }

    /// Put down: dropped just where it is with a click, thrown with a flick;
    /// the bug wound up.
    private func handUp(_ e: NSEvent) {
        guard holdingToy, let toy = toyBox.toys.first else { return }
        let p = V2(NSEvent.mouseLocation)
        var v = V2.zero
        if let recent = toyDrag.last(where: { e.timestamp - $0.t > 0.04 }) {
            v = (p - recent.p) / CGFloat(max(e.timestamp - recent.t, 0.008))
        }
        putDown(toy, at: p, fling: v.length < 120 ? .zero : v)
    }

    private func putDown(_ toy: Toy, at p: V2, fling: V2) {
        toy.drag(to: p)
        toy.release(fling: fling)
        toy.wind()
        holdingToy = false
        toyDrag = []
        handWindow.orderOut(nil)
        calmFrames = 0
        calm = false
        refreshMenu()
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
        // With the tank open, the box waits until it is closed.
        if tankOpen { boxWhileInTank = rect } else { spider.confine = rect }
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
        let f = inHabitat ? (habitat?.scene.screenScene ?? worldFrame()) : spider.confine ?? NSScreen.main?.frame ?? worldFrame()
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
        spider.memory = memory
        map.standoff = AppDelegate.standoff(for: spider.config.scale)
        map.rebuild(windows: [])
        view.spider = spider
        spider.toys = toyBox
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
        for v in visitors { removeVisitor(v) }
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
        setScale(s)
    }

    private func setScale(_ s: CGFloat) {
        spider.config.scale = s
        toyBox.scale = s
        applyWindowSize()
        saveSettings()
        refreshMenu()
    }

    /// A thought bubble needs far more room over its head than anything
    /// else it draws, so the sprite and its window grow while one is up.
    private var thoughtRoom = false

    private func applyWindowSize() {
        map.standoff = AppDelegate.standoff(for: spider.config.scale)
        habitat?.scene.setStandoff(map.standoff)
        spriteSide = SpiderRenderer.spriteSide(for: spider.config.scale) + (thoughtRoom ? (240 * spider.config.scale).rounded() : 0)
        side = spriteSide + AppDelegate.windowSlack
        view.resize(sprite: spriteSide, window: side)
        window.setContentSize(CGSize(width: side, height: side))
        view.worldOrigin = window.frame.origin
    }

    private func setEnergy(level s: CGFloat) {
        // Just moves the Studio's energy slider.
        var d = spider.design
        d.personality.energy = clamp(remap(s, 0.45, 2.4, 0, 1), 0, 1)
        spider.apply(design: d)
        d.save()
        saveSettings()
        refreshMenu()
    }

    /// Learning off: it goes back to just who the Studio says it is, and
    /// what it remembers is kept, untouched, for if you turn it on again.
    @objc private func toggleLearning() {
        learns.toggle()
        if learns {
            memory = SpiderMemory.load()
        } else {
            memory?.save()
            memory = nil
        }
        spider.memory = memory
        saveSettings()
        refreshMenu()
    }

    private func forgetExperiences() {
        memory?.forget()
        memory?.save()
        spider.memory = memory
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
                self.habitat?.rename(d.name)
                self.statusItem.button?.toolTip = d.name
            }
            st.onDemoOnDesktop = { [weak self] habit in self?.spider.demo(habit) }
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
                // The last page of the welcome: done designing, out it comes.
                if !shown, self.awaitingEntrance { self.finishWelcome() }
            }
            studio = st
        }
        studio?.scale = spider.config.scale
        studio?.show()
    }

    // MARK: - Welcome

    /// The welcome tour: a hello, where its menu lives, and the Studio —
    /// and then the spider lets itself down into the desktop from its menu
    /// bar icon. Shown once, the first time the app is opened.
    @objc private func startWelcome() {
        guard welcome == nil, !awaitingEntrance else { welcome?.show(); return }
        if tankOpen { closeHabitat(animated: false) }
        // The menu as it will be once the spider is out — shown, not
        // paused — for the picture of it; built before the tour puts the
        // spider away.
        let wasHidden = hidden
        hidden = false
        let pictured = buildMenu()
        hidden = wasHidden
        awaitingEntrance = true
        pausedBeforeWelcome = spider.config.paused
        spider.config.paused = true
        window.orderOut(nil)
        for v in visitors { removeVisitor(v) }
        silkWindow.orderOut(nil)
        silkVisible = false
        hammockWindow.orderOut(nil)
        let w = OnboardingController(design: spider.design, menu: pictured)
        w.onOpenMenu = { [weak self] in self?.statusItem.button?.performClick(nil) }
        w.onStudio = { [weak self] frame in
            guard let self else { return }
            self.openStudio()
            self.studio?.show(in: frame)
        }
        w.onSkip = { [weak self] in self?.finishWelcome() }
        welcome = w
        w.show()
    }

    private func finishWelcome() {
        guard awaitingEntrance else { return }
        awaitingEntrance = false
        welcome = nil
        UserDefaults.standard.set(true, forKey: "welcomed")
        spider.config.paused = pausedBeforeWelcome
        if hidden {
            hidden = false
            statusItem.button?.appearsDisabled = false
            saveSettings()
        }
        window.orderFrontRegardless()
        if hammockShown { hammockWindow.orderFrontRegardless() }
        lastTime = CACurrentMediaTime()
        // Down on a line from just under its icon in the menu bar.
        var from = V2(NSScreen.main.map { $0.frame.midX } ?? 600, NSScreen.main.map { $0.visibleFrame.maxY } ?? 800)
        if let icon = statusItem.button?.window?.frame {
            from = V2(icon.midX, icon.minY)
        }
        spider.enterOnThread(from: from)
        refreshMenu()
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
        if !interactive {
            window.ignoresMouseEvents = true
            preyWindow.ignoresMouseEvents = true
            for v in visitors { v.window.ignoresMouseEvents = true }
        }
        saveSettings(); refreshMenu()
    }

    @objc private func togglePause() {
        spider.config.paused.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Locked and unlocked

    /// Locked, asleep or switched away from: it is put to bed, and wakes to
    /// greet you when you are back.
    private var away = false

    private func watchForYouComingBack() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.youLeft() }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.youCameBack() }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.youLeft() }
        }
        // Waking with no password to type: back as soon as the screen is.
        // (With one, the unlock is what brings you back.)
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard let self, !AppDelegate.screenIsLocked else { return }
                    self.youCameBack()
                }
            }
        }
    }

    private static var screenIsLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func youLeft() {
        guard !away else { return }
        away = true
        guard !hidden, !awaitingEntrance, !inHabitat, !spider.config.paused else { return }
        if handToy != nil { putAway() }
        // The visitors have gone home by the time you are back.
        for v in visitors { removeVisitor(v) }
        tracker.pollNow()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let near = screen.map { V2($0.frame.midX, $0.frame.midY) } ?? spider.worldPos
        spider.tuckIn(near: near)
        calmFrames = 0
        calm = false
    }

    /// Back, and it is about to wake: seen asleep for a moment first.
    private var wakingUp = false

    private func youCameBack() {
        guard away else { return }
        away = false
        guard spider.dormant else { return }
        wakingUp = true
        // Wherever it went to bed may be under a window now: to a bed in
        // sight, before the desktop is.
        tracker.pollNow()
        if !spider.bedInSight {
            spider.tuckIn(near: spider.worldPos)
        }
        // Seen asleep for a moment first, then up to say hello.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self else { return }
            self.wakingUp = false
            guard !self.away else { return }
            self.spider.wakeAndGreet()
            self.calmFrames = 0
            self.calm = false
        }
    }

    // MARK: - The Mac it lives on

    private func startSensing() {
        sense.onLowPower = { [weak self] _ in self?.applyPowerMood() }
        sense.onPluggedIn = { [weak self] in
            guard let self, self.feelsPower, !self.hidden, !self.awaitingEntrance else { return }
            for s in self.allSpiders { s.perkUp() }
            self.calmFrames = 0
            self.calm = false
        }
        sense.onRain = { [weak self] r in
            guard let self else { return }
            for s in self.allSpiders { s.raining = r }
            self.updateRain(now: CACurrentMediaTime())
            self.refreshMenu()
        }
        sense.onCommotion = { [weak self] c in
            guard let self else { return }
            // Its little window of lights comes up at the top right of the
            // screen in use.
            if self.commotionLog { fputs("commotion: \(c) — \(self.spider.debugState)\n", stderr) }
            self.commotion(on: NSScreen.main?.frame, fright: false)
        }
        tracker.onBanner = { [weak self] screen in
            if let self, self.commotionLog { fputs("commotion: banner on \(screen) — \(self.spider.debugState)\n", stderr) }
            self?.commotion(on: screen, fright: true)
        }
        if feelsPower { sense.startPower() }
        if feelsWeather { sense.startWeather() }
        if feelsCommotion { sense.startCommotion() }
        applyPowerMood()
    }

    /// Something going off up at the top right of a screen — where the
    /// banners and the volume and brightness lights come up.
    private func commotion(on screen: CGRect?, fright: Bool) {
        guard feelsCommotion, !hidden, !inHabitat, !awaitingEntrance,
              let frame = screen ?? NSScreen.main?.frame else { return }
        let visible = NSScreen.screens.first { $0.frame == frame }?.visibleFrame ?? frame
        let spot = V2(visible.maxX - 180, visible.maxY - 50)
        for s in allSpiders { s.noticeCommotion(at: spot, fright: fright) }
        calmFrames = 0
        calm = false
    }

    /// Low Power Mode, if it is minded: a drowsy spider on a half-rate clock.
    private var lowPowerClock = false

    private func applyPowerMood() {
        let low = feelsPower && sense.lowPower
        for s in allSpiders { s.drowsy = low ? 1 : 0 }
        if low != lowPowerClock {
            lowPowerClock = low
            if #available(macOS 14.0, *), let link = displayLink as? CADisplayLink {
                let hz: Float = low ? 30 : 60
                link.preferredFrameRateRange = CAFrameRateRange(minimum: hz, maximum: hz, preferred: hz)
            }
        }
        updateRain(now: CACurrentMediaTime())
        refreshMenu()
    }

    /// The rain is out while it rains and there is a desktop to see it on.
    private func updateRain(now: CFTimeInterval) {
        let want = feelsWeather && showsRain && sense.raining && !hidden && !inHabitat && !awaitingEntrance
            && cinemaScreens.isEmpty && !(feelsPower && sense.lowPower)
        if want, !rainView.falling {
            rainWindow.order(.below, relativeTo: window.windowNumber)
            rainView.start()
        } else if !want, rainView.falling {
            rainView.stop()
            rainOffAt = now
        } else if !want, rainWindow.isVisible, now - rainOffAt > 3 {
            // The last drops have landed.
            rainWindow.orderOut(nil)
        }
    }

    @objc private func toggleFeelPower() {
        feelsPower.toggle()
        if feelsPower { sense.startPower() } else { sense.stopPower() }
        applyPowerMood(); saveSettings()
    }

    @objc private func toggleFeelWeather() {
        feelsWeather.toggle()
        if feelsWeather { sense.startWeather() } else { sense.stopWeather() }
        updateRain(now: CACurrentMediaTime()); saveSettings(); refreshMenu()
    }

    @objc private func toggleFeelCommotion() {
        feelsCommotion.toggle()
        if feelsCommotion { sense.startCommotion() } else { sense.stopCommotion() }
        saveSettings(); refreshMenu()
    }

    @objc private func toggleShowRain() {
        showsRain.toggle()
        updateRain(now: CACurrentMediaTime()); saveSettings(); refreshMenu()
    }

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

    /// Every change of setting comes through here, so the visitors pick it
    /// up here too.
    private func saveSettings() {
        syncVisitors()
        let d = UserDefaults.standard
        d.set(visitorsOn, forKey: "visitors")
        d.set(Double(spider.config.scale), forKey: "scale")
        d.set(spider.config.followCursor, forKey: "followCursor")
        d.set(spider.config.pounceOnCursor, forKey: "pounceOnCursor")
        d.set(spider.config.webs, forKey: "webs")
        d.set(spider.config.hammocks, forKey: "hammocks")
        d.set(spider.config.paused, forKey: "paused")
        d.set(interactive, forKey: "interactive")
        d.set(hidden, forKey: "hidden")
        d.set(feelsPower, forKey: "feelPower")
        d.set(feelsWeather, forKey: "feelWeather")
        d.set(showsRain, forKey: "showRain")
        d.set(feelsCommotion, forKey: "feelCommotion")
        d.set(learns, forKey: "learns")
        d.set(wildOn, forKey: "wildlife")
        d.set(toySounds, forKey: "toySounds")
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "scale": 0.95, "liveliness": 1.0, "followCursor": true, "pounceOnCursor": true,
            "webs": true, "hammocks": true, "paused": false, "interactive": true, "hidden": false,
            "visitors": false, "visitFrequency": 0.5, "visitStay": 0.5,
            "feelPower": true, "feelWeather": true, "showRain": true, "feelCommotion": true,
            "learns": true, "wildlife": false, "wildFrequency": 0.35, "toySounds": true,
        ])
        toySounds = d.bool(forKey: "toySounds")
        feelsPower = d.bool(forKey: "feelPower")
        feelsWeather = d.bool(forKey: "feelWeather")
        showsRain = d.bool(forKey: "showRain")
        feelsCommotion = d.bool(forKey: "feelCommotion")
        learns = d.bool(forKey: "learns")
        visitorsOn = d.bool(forKey: "visitors")
        visitFrequency = CGFloat(d.double(forKey: "visitFrequency"))
        visitStay = CGFloat(d.double(forKey: "visitStay"))
        nextVisitAt = CACurrentMediaTime() + visitGap / 2
        wildOn = d.bool(forKey: "wildlife")
        wildFrequency = CGFloat(d.double(forKey: "wildFrequency"))
        nextWildAt = CACurrentMediaTime() + wildGap / 2
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
