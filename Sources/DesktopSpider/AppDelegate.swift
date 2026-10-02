import AppKit
import Carbon.HIToolbox
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
    /// Of those, the ones a maximized window has taken (the menu bar still
    /// over it): see `WindowTracker.zoomedScreens`.
    private var zoomedScreens: [CGRect] = []
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
    /// What it leaves about the desktop: silk, little webs, leftovers.
    private lazy var traces: TraceKeeper = {
        let k = TraceKeeper(map: map)
        k.toyBox = toyBox
        k.onTremble = { [weak self] p, strength in self?.spider.feelTremble(at: p, strength: strength) }
        return k
    }()
    private var traceWindow: OverlayWindow!
    private var traceView: TraceView!
    private var tracesShown = false
    /// Whether it leaves traces at all (the setting).
    private var leavesTraces = false
    /// The slider, 0...1: how many traces may be out at once, from a few
    /// up to no limit at all at the very top.
    private var traceLimitSetting: CGFloat = 0.45
    /// The slider's number: 3 at the bottom, rising steeply to 60, and
    /// then — the last notch — nil, for no limit.
    static func traceLimit(for v: CGFloat) -> Int? {
        v >= 0.95 ? nil : Int((3 * pow(20, v / 0.95)).rounded())
    }
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
    /// Creatures finding their own way into the tank, as its things draw
    /// them (see HabitatEcology.swift): on unless turned off.
    private var tankWildOn = true
    private var nextTankWildAt: CFTimeInterval = 0
    private var allSpiders: [Spider] { [spider] + visitors.map(\.spider) }
    private let tracker = WindowTracker()
    /// Browsers filling their screens, and the ledges on their pages (see
    /// WebPages.swift).
    private let pageWatch = PageWatcher()
    /// Climbs web pages that fill the screen (the setting).
    private var climbsPages = false
    /// Climbing web pages isn't finished: until it is, it stays off and out
    /// of the menu (SPIDER_PAGE_TEST still turns it on, in memory).
    static let pagesReady = false
    /// Scrolls and clicks anywhere, heard while it climbs pages: a page
    /// scrolling under it, or a click that may be off to another page.
    private var pageMonitors: [Any] = []
    /// Screens taken by a full-screen app showing something to watch — not
    /// a browser page it can climb.
    private var filmScreens: [CGRect] {
        let pages = pageWatch.pageScreens
        return cinemaScreens.filter { !pages.contains($0) }
    }
    private var statusItem: NSStatusItem!
    private let updater = Updater()
    private var studio: StudioController?
    private var bugReport: BugReportController?
    private var studioVisible = false
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
    /// The pointer where the spider sees it: the same, on the desktop; in
    /// the tank, where it is over the tank's world.
    private var lastSpiderCursor = V2(-9999, -9999)
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
    /// Its own Low Power Mode, set by hand: true puts it in whatever the Mac
    /// is doing, false keeps it at full speed through the Mac's Low Power
    /// Mode (until that ends), nil goes along with the Mac.
    private var powerOverride: Bool?
    /// Rain on its mind while it rains outside.
    private var feelsWeather = true
    /// A faint rain across the desktop while it rains, too.
    private var showsRain = true
    /// What the weather is doing outside, as the habitat has it (when the
    /// app may look it up), and a word on it for the controls.
    private var outsideWeather: WeatherKind?
    private var outsideSummary: String?
    /// Tools only (SPIDER_WEATHER=kind): the tank's weather kept to that,
    /// in memory only.
    private let forcedWeather = ProcessInfo.processInfo.environment["SPIDER_WEATHER"].flatMap(WeatherKind.init)
    /// Jumps at a notification; looks up at the volume or brightness changing.
    private var feelsCommotion = true
    /// Hears music playing on the Mac and dances to its beat.
    private let ears = Ears()
    private var dancesToMusic = true
    /// It remembers what happens to it and grows a little with it.
    private var learns = true
    /// What it has been through (nil with learning off).
    private var memory: SpiderMemory?
    /// What it knows of the things in its tank (see HabitatKnowledge.swift):
    /// kept whether or not it is learning — it is what it has seen, not
    /// what it has come to feel.
    private let knowledge = HabitatKnowledge.load()
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
        spider.knowledge = knowledge
        map.standoff = AppDelegate.standoff(for: spider.config.scale)
        map.rebuild(windows: [])
        toyBox.scale = spider.config.scale
        spider.toys = toyBox
        traces.enabled = leavesTraces
        traces.limit = AppDelegate.traceLimit(for: traceLimitSetting)
        spider.traces = traces

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

        // (Each window's corners measured on the tracker's own queue.)
        tracker.measureCorner = { w, top in AppDelegate.measureCornerRadius(of: w, primaryTop: top) }
        pageWatch.scale = spider.config.scale
        pageWatch.standoff = map.standoff
        pageWatch.spiderAt = { [weak self] in
            guard let self, let on = self.spider.standingOn else { return (nil, self?.spider.worldPos ?? .zero) }
            return (on.loopID, self.spider.worldPos - self.spider.standingNormal * self.map.standoff)
        }
        pageWatch.onChange = { [weak self] settled in self?.pagesChanged(settled: settled) }
        setClimbsPages(climbsPages, save: false)
        tracker.onUpdate = { [weak self] windows, fullScreens, docks, taken in
            guard let self else { return }
            let t0 = Perf.timing ? CACurrentMediaTime() : 0
            defer {
                if Perf.timing, CACurrentMediaTime() - t0 > 0.004 { Perf.note("windows: update (\(windows.count) windows)", ms: (CACurrentMediaTime() - t0) * 1000) }
            }
            // Entering full screen counts at once; leaving it only after a
            // few quiet polls, so a player's controls flickering over the
            // video cannot keep unsettling the spider.
            // (A window maximized, or tiled to fill the screen, is as good
            // as full screen: see `WindowTracker.onUpdate`.)
            let cinemaWas = self.cinemaScreens, zoomedWas = self.zoomedScreens
            if !fullScreens.isEmpty {
                self.cinemaScreens = fullScreens
                self.zoomedScreens = self.tracker.zoomedScreens
                self.cinemaClearPolls = 0
            } else if self.cinemaScreens.isEmpty == false {
                self.cinemaClearPolls += 1
                if self.cinemaClearPolls >= 4 { self.cinemaScreens = []; self.zoomedScreens = [] }
            }
            // Browsers filling their screens: pages to climb.
            self.pageWatch.update(windows: windows, taken: taken,
                                  screens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) }, bare: self.tracker.bareScreens)
            self.map.rebuild(windows: windows, cinema: self.cinemaScreens, zoomed: self.zoomedScreens, docks: docks,
                             pages: self.pageWatch.loops(), pageScreens: self.pageWatch.pageScreens)
            // The rim of a taken screen is a different set of edges: the
            // spider re-reads its footing from where it stands rather than
            // carrying its place over by index and jumping.
            if self.cinemaScreens != cinemaWas || self.zoomedScreens != zoomedWas {
                for s in self.allSpiders { s.surfacesRestructured() }
                if self.cinemaLog {
                    fputs("cinema: \(self.cinemaScreens.isEmpty ? "over" : "\(self.cinemaScreens)")\(self.zoomedScreens.isEmpty ? "" : " zoomed \(self.zoomedScreens)") — \(self.spider.debugState)\n", stderr)
                }
            }
            for s in self.allSpiders { s.fullScreenApp = !self.filmScreens.isEmpty }
        }
        tracker.start()
        startSensing()
        // The first time it is opened: the welcome tour, before it comes out.
        // (SPIDER_WELCOME=1 shows it again.)
        if !UserDefaults.standard.bool(forKey: "welcomed") || ProcessInfo.processInfo.environment["SPIDER_WELCOME"] == "1" {
            DispatchQueue.main.async { [weak self] in self?.startWelcome() }
        }
        // SPIDER_ENTRANCE_TEST=secs: straight to the first entrance (the tour
        // skipped), where it is every quarter second, then quits.
        if let secs = ProcessInfo.processInfo.environment["SPIDER_ENTRANCE_TEST"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                if self.welcome == nil { self.startWelcome() }
                self.welcome?.window.close()
                let n = Int(secs * 4)
                for i in 1...n {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.25) {
                        print("entrance: +\(Double(i) * 0.25)s \(self.spider.debugState) at \(Int(self.spider.worldPos.x)),\(Int(self.spider.worldPos.y)) entering \(self.spider.makingEntrance) level \(self.window.level.rawValue)")
                        if i == n { NSApp.terminate(nil) }
                    }
                }
            }
        }
        // SPIDER_WELCOME_SHOT=dir writes the welcome's pages there, then quits.
        if let dir = ProcessInfo.processInfo.environment["SPIDER_WELCOME_SHOT"] {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.welcome == nil { self.startWelcome() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.welcome?.debugSnapshot(to: "\(dir)/welcome1.png")
                    self.welcome?.debugNextPage()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self.welcome?.debugSnapshot(to: "\(dir)/welcome2.png")
                        self.welcome?.debugNextPage()
                        self.welcome?.window.displayIfNeeded()
                        self.welcome?.debugSnapshot(to: "\(dir)/welcome3.png")
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

        // (Before the spider is off: see `makeHabitatAhead`, `makePanel`,
        // `warmUpPanel` — which starts it off.)
        makeHabitatAhead()
        makePanel()
        warmUpPanel { [weak self] in self?.startClock() }
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
        // SPIDER_WEATHER_SHOT=dir opens the habitat with the spider in it and
        // writes a picture of the tank in every kind of weather, fully in
        // (SPIDER_WEATHER_KINDS and SPIDER_WEATHER_BIOMES, comma lists, to
        // pick), then puts everything back and quits.
        if let dir = ProcessInfo.processInfo.environment["SPIDER_WEATHER_SHOT"] {
            runWeatherShots(dir: dir)
        }
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_INPUT"] == "1" { runHabitatInputTest() }
        // SPIDER_HABITAT_TOUR=dir: both tours, a picture of each step, the
        // weather panel and My Habitats — saving and putting them back
        // checked on the way ([ok]/[FAIL]), in a library of its own — then quits.
        if let dir = ProcessInfo.processInfo.environment["SPIDER_HABITAT_TOUR"] { runHabitatTourTest(dir: dir) }
        // SPIDER_HABITAT_BUILD=1 (+SPIDER_HABITAT_DIR for pictures): structures
        // built in the tank by synthesized drags — snapping, carrying,
        // resizing, placing freely, supports, saving — then the spider on them.
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_BUILD"] == "1" { runHabitatBuildTest(dir: ProcessInfo.processInfo.environment["SPIDER_HABITAT_DIR"]) }
        // SPIDER_HABITAT_CAMERA=1: the big tank and its camera, through every
        // way of looking round it, coming and going, and decorating it
        // (prints [ok]/[FAIL] for each, then puts the habitat keys back).
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_CAMERA"] == "1" { runHabitatCameraTest() }
        // SPIDER_HABITAT_CURIOUS=1 (+SPIDER_HABITAT_DIR for pictures): a
        // toadstool added while decorating, and the spider getting to know it
        // (notices, watches, comes closer, feels it, climbs it, knows it,
        // leaves it be); then carried off on a stump it stands on.
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_CURIOUS"] == "1" { runHabitatCuriousTest(dir: ProcessInfo.processInfo.environment["SPIDER_HABITAT_DIR"]) }
        // SPIDER_HABITAT_PLACES=1 (+SPIDER_HABITAT_DIR for pictures): the tank
        // put to use, in real time — a dish found and later gone back to for a
        // drink, a lookout climbed to look out from, a downpour sat out under
        // the table rather than in the nearer bark cave.
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_PLACES"] == "1" { runHabitatPlacesTest(dir: ProcessInfo.processInfo.environment["SPIDER_HABITAT_DIR"]) }
        // SPIDER_HABITAT_ECOLOGY=1 (+SPIDER_HABITAT_DIR for pictures): the tank
        // alive — rain rolling in and the spider going in under the table, drops
        // on the leaves and rings on the dish, out after it and a drop drunk;
        // snow only where open; creatures coming in to what draws them.
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_ECOLOGY"] == "1" { runHabitatEcologyTest(dir: ProcessInfo.processInfo.environment["SPIDER_HABITAT_DIR"]) }
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
            // (SPIDER_HABITAT_PRESET=name: in that ready-made layout instead.)
            if let name = ProcessInfo.processInfo.environment["SPIDER_HABITAT_PRESET"], let p = Habitat.Preset(rawValue: name) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                    guard let hc = habitat else { return }
                    let world = hc.scene.habitat.size
                    hc.scene.setHabitat(Habitat.preset(p, world: world))
                    spider.placeInHabitat(map: hc.scene.map, at: V2(world.width / 2, HabitatLayout.ground + 30))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + abs(secs)) { self.finishHabitatTest(restore) }
        }
        // SPIDER_OPEN_TIMING=secs opens the habitat two seconds in, the way
        // clicking Open Habitat does (the spider climbing in from the
        // desktop), leaves it open that long, then puts things back and
        // quits — for timing it with SPIDER_TIMING / SPIDER_FRAMES.
        if let secs = ProcessInfo.processInfo.environment["SPIDER_OPEN_TIMING"].flatMap(Double.init) {
            testMapsNow = false
            let restore = habitatTestSnapshot()
            spider.knowledge = knowledge
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                openHabitat()
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) { self.finishHabitatTest(restore) }
            }
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
        // SPIDER_TRACE_TEST=secs takes every chance to leave a trace (memory
        // off, and hammocks off for the run — no setting is saved), lays out
        // a few to look at straight away — lines down from the menu bar, a
        // web in the bottom-left corner, leftovers on the floor — lets a fly
        // loose now and then, reports what is out every two seconds, and
        // quits.
        if let secs = ProcessInfo.processInfo.environment["SPIDER_TRACE_TEST"].flatMap(Double.init) {
            memory = nil
            spider.memory = nil
            spider.config.hammocks = false
            traces.enabled = true
            Spider.debugTraceOdds = 1
            traceTiming = true
            let start = CACurrentMediaTime()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.layOutTestTraces() }
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard let self else { return }
                let now = CACurrentMediaTime()
                if Int(now - start) % 16 < 2, self.spider.prey.filter({ $0.state == .loose }).count < 2 { self.release(.fruitFly) }
                // The second half with traces off, to compare what they cost.
                if now - start > secs / 2, self.traces.enabled {
                    self.traces.enabled = false
                    print("trace test: traces off from here")
                }
                let ms = self.traceTime.frames > 0 ? self.traceTime.total / Double(self.traceTime.frames) * 1000 : 0
                print(String(format: "trace test %3.0fs: %@ | %@ | calm %@ | traces %.3f ms/frame over %d", now - start, self.spider.debugState,
                             self.spider.debugTraces, self.calm ? "yes" : "no", ms, self.traceTime.frames))
                self.traceTime = (0, 0, 0)
                fflush(stdout)
                if now - start > secs { timer.invalidate(); NSApp.terminate(nil) }
            }
        }
        // SPIDER_PAGE_TEST=secs climbs pages whatever the setting (in memory
        // only; memory off), says what it sees, puts the spider on a page's
        // longest ledge as soon as there is one (SPIDER_PAGE_PUT=0 not to),
        // reports where it is every half second, and quits — saying how
        // much CPU time it took. SPIDER_PAGE_OFF=1 runs it with pages off,
        // to compare.
        if let secs = ProcessInfo.processInfo.environment["SPIDER_PAGE_TEST"].flatMap(Double.init) {
            memory = nil
            spider.memory = nil
            pageWatch.log = true
            let off = ProcessInfo.processInfo.environment["SPIDER_PAGE_OFF"] == "1"
            if climbsPages == off { setClimbsPages(!off, save: false) }
            let start = CACurrentMediaTime()
            var placed = ProcessInfo.processInfo.environment["SPIDER_PAGE_PUT"] == "0"
            // SPIDER_PAGE_REPUT=secs: put it on a ledge again then (for a scroll test).
            var reput = ProcessInfo.processInfo.environment["SPIDER_PAGE_REPUT"].flatMap(Double.init)
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                guard let self else { return }
                let now = CACurrentMediaTime()
                if let r = reput, now - start >= r { placed = false; reput = nil }
                let ledges = self.map.loops.filter { $0.kind == .webLedge }
                if !placed {
                    var best: (id: String, index: Int, len: CGFloat)?
                    for l in ledges {
                        for (i, seg) in l.segs.enumerated() where seg.facing == .up && seg.isOpen(at: seg.len / 2) {
                            if best == nil || seg.len > best!.len { best = (l.id, i, seg.len) }
                        }
                    }
                    if let best {
                        placed = true
                        self.spider.debugAttach(loopID: best.id, segIdx: best.index, t: best.len / 2, dir: 1)
                        print("page test: put on \(best.id) stretch \(best.index) (\(Int(best.len)) long)")
                    }
                }
                let on = self.spider.standingOn.map { "\($0.loopID)#\($0.segIdx)" } ?? "-"
                print(String(format: "page test %4.1fs: %d page ledges | on %@ at %d,%d | %@ | film %@ | extension %@", now - start, ledges.count, on,
                             Int(self.spider.worldPos.x), Int(self.spider.worldPos.y), self.spider.debugState,
                             self.filmScreens.isEmpty ? "no" : "yes", self.pageWatch.extensionConnected ? "on" : "off"))
                fflush(stdout)
                if now - start > secs {
                    var u = rusage()
                    getrusage(RUSAGE_SELF, &u)
                    let cpu = Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
                    print(String(format: "page test: %.2f s of CPU in %.0f s (%.1f%%)%@", cpu, now - start, cpu / (now - start) * 100,
                                 off ? " — pages off" : ""))
                    let w = self.pageWatch.spent
                    print(String(format: "page test: pages took %.3f s looking (%d looks, %d read) and %.3f s laying out ledges — %.2f%% of a core",
                                 w.looking, w.looks, w.readings, w.laying, (w.looking + w.laying) / (now - start) * 100))
                    timer.invalidate()
                    NSApp.terminate(nil)
                }
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
                    for i in 0..<(self?.panel?.pageCount ?? 0) { self?.panel?.snapshot(to: "\(dir)/panel\(i).png", page: i, dark: true) }
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
        // SPIDER_BUG_SHOT=dir opens Report a Bug and writes bug_form.png (and
        // bug_peek.png, with what's sent showing) there, then quits.
        // SPIDER_BUG_FILES=a:b attaches those first; SPIDER_BUG_SEND=1 sends
        // it too (to SPIDER_BUG_ENDPOINT, say) and writes bug_after.png.
        if let dir = ProcessInfo.processInfo.environment["SPIDER_BUG_SHOT"] {
            let env = ProcessInfo.processInfo.environment
            reportBug()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let c = self?.bugReport else { return }
                if let files = env["SPIDER_BUG_FILES"] {
                    c.debugFill(name: "Tester", text: "A test report from the SPIDER_BUG_SHOT hook: nothing's wrong, please ignore.",
                                files: files.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
                }
                c.debugSnapshot(to: "\(dir)/bug_form.png")
                c.debugPeek()
                c.debugSnapshot(to: "\(dir)/bug_peek.png")
                c.debugPeek()
                guard env["SPIDER_BUG_SEND"] == "1" else { NSApp.terminate(nil); return }
                c.debugSend()
                func wait(_ n: Int) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard n > 0, !c.debugDone, c.debugProblem == nil else {
                            print("bug report: \(c.debugDone ? "sent" : c.debugProblem ?? "timed out")")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                c.debugSnapshot(to: "\(dir)/bug_after.png")
                                NSApp.terminate(nil)
                            }
                            return
                        }
                        wait(n - 1)
                    }
                }
                wait(60)
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
        rememberTankPlace()
        memory?.save()
        if !testingHabitat { knowledge.save(keeping: habitat?.loadedHabitat) }
        ears.stop()
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
        view.onShow = { [weak self] pose in
            // (A picture that turns up after it has gone into the tank is
            // for nothing: it is drawn in there now.)
            guard let self, !self.drawnInTank else { return }
            if self.place(pose) { self.placeMoved = true }
            if self.frontWithPicture {
                self.frontWithPicture = false
                self.window.orderFrontRegardless()
            }
        }
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
        preyView.onToyRightClick = { [weak self] in self?.putAway() }
        preyWindow.contentView = preyView
        preyWindow.ignoresMouseEvents = true
        silkWindow = OverlayWindow(frame: frame)
        silkView = SilkView(frame: CGRect(origin: .zero, size: frame.size))
        silkView.worldOrigin = frame.origin
        silkWindow.contentView = silkView
        silkWindow.ignoresMouseEvents = true
        // What it leaves about, under all of that: never takes a click.
        traceWindow = OverlayWindow(frame: frame)
        traceView = TraceView(frame: CGRect(origin: .zero, size: frame.size))
        traceView.worldOrigin = frame.origin
        traceWindow.contentView = traceView
        traceWindow.ignoresMouseEvents = true

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
        traceWindow.setFrame(frame, display: false)
        traceView.frame = CGRect(origin: .zero, size: frame.size)
        traceView.worldOrigin = frame.origin
        rainWindow.setFrame(frame, display: false)
        rainView.frame = CGRect(origin: .zero, size: frame.size)
        // (Where the Dock is now comes with the next look at the windows,
        // asked for straight away: see `SurfaceMap.dockStrips`.)
        map.rebuild(windows: [], cinema: cinemaScreens, zoomed: zoomedScreens, docks: map.dockRects)
        tracker.pollNow()
        for s in allSpiders { s.surfacesRestructured() }
        spider.refitHammock()
        restartClockIfItsScreenWentAway()
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
            // (At 30 straight away if Low Power Mode was already on: see
            // `applyPowerMood`, which only changes it when that changes.)
            let hz: Float = lowPowerClock ? 30 : 60
            link.preferredFrameRateRange = CAFrameRateRange(minimum: hz, maximum: hz, preferred: hz)
            link.add(to: .main, forMode: .common)
            displayLink = link
            clockScreen = AppDelegate.displayID(of: screen)
        } else {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            fallbackTimer = t
        }
    }

    /// The display the clock's link is on. Unplugged, its link stops for
    /// good, and the clock is started again on one still there.
    private var clockScreen: CGDirectDisplayID?

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func restartClockIfItsScreenWentAway() {
        guard #available(macOS 14.0, *), let link = displayLink as? CADisplayLink, let id = clockScreen,
              !NSScreen.screens.contains(where: { AppDelegate.displayID(of: $0) == id }) else { return }
        link.invalidate()
        displayLink = nil
        clockScreen = nil
        startClock()
    }

    private var tickCount = 0
    @objc private func tick() {
        tickCount += 1
        if tickCount % 3600 == 0, let m = memory, m.dirty { Perf.measure("saved: memory") { m.save() } }
        if tickCount % 3600 == 1800, knowledge.dirty, !testingHabitat { Perf.measure("saved: habitat knowledge") { knowledge.save(keeping: habitat?.loadedHabitat) } }
        if tickCount % 30 == 0 {
            askToSeePages()
            updateRain(now: CACurrentMediaTime())
            updateEars()
            // Never left asleep for good by an unlock that went unheard.
            if spider.dormant, !away, !wakingUp, !AppDelegate.screenIsLocked { spider.wakeAndGreet() }
        }
        pageWatch.paused = hidden || inHabitat || awaitingEntrance
        pageWatch.lowPower = lowPower
        guard !hidden else { return }
        let now = CACurrentMediaTime()
        pageWatch.tick(now: now)

        // Whether clicks reach us is decided every tick, throttled or not: a
        // stale decision here is a spider you cannot pick up.
        let cursorNow = V2(NSEvent.mouseLocation)
        // (In the tank, it is the tank's window that takes the clicks.)
        let wantsMouseNow = interactive && (spider.isHeld || (!inHabitat && spider.hitTest(cursorNow)))
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
        if let meter = Perf.meter {
            meter.tickBegan()
            meter.context = "\(inHabitat ? "tank" : "desktop")\(calm ? " calm" : "") \(spider.debugState.prefix(28))"
        }
        defer { Perf.meter?.tickEnded(redrew: view.didRedraw || (habitat?.scene.didRedraw ?? false)) }
        // Everything the frame changes goes to the screen together, once, at
        // the end of it — rather than a part-way commit wherever something
        // sets its layers in a transaction of its own (the tank's creatures
        // did: a second commit a frame, walking the tank's whole layer tree).
        CATransaction.begin()
        defer { CATransaction.commit() }
        lastFrame = now
        let dt = CGFloat(min(max(now - lastTime, 1.0 / 240.0), 1.0 / 20.0))
        lastTime = now
        if !toyBox.isEmpty { toyBox.update(dt: dt) }

        let cursor = V2(NSEvent.mouseLocation)
        if cursor.distance(to: lastCursor) > 0.4 {
            lastCursor = cursor
            for v in visitors { v.spider.setCursor(cursor) }
        }
        // In the tank it sees the pointer over the tank's world (which moves
        // under a still pointer as the camera does); out past the glass the
        // pointer is outside the tank, to be looked at, not gone after.
        let seen = inHabitat ? (habitat.map { $0.scene.worldPoint(fromScreen: cursor) } ?? cursor) : cursor
        // (In your hand it goes where the drag takes it; a drag not made by
        // a real button — the tools' — is left to do so.)
        let handDrag = spider.isHeld && NSEvent.pressedMouseButtons == 0
        if !handDrag, seen.distance(to: lastSpiderCursor) > 0.4 {
            lastSpiderCursor = seen
            spider.setCursor(seen)
        }
        spider.cursorArea = inHabitat ? habitat?.scene.visibleWorld : nil
        updateWeather(now: now, dt: dt)
        // The beat of whatever is playing, as it is on the screen this frame.
        // (Not in a habitat test: what the Mac happens to be playing would
        // have it dancing instead of doing what is being tested.)
        let heard = dancesToMusic && !testingHabitat ? ears.music(at: now) : nil
        for s in allSpiders { s.music = heard }
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
            let looked = tickTank(dt: dt)
            let pose = spider.pose()
            let moved = show(pose)
            settle(moved: updateVisitors(dt: dt, now: a) || moved || looked || toyBox.astir, critters: spider.preyAstir || traces.astir)
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
            let looked = tickTank(dt: dt)
            let moved = show(pose)
            settle(moved: updateVisitors(dt: dt, now: now) || moved || looked || toyBox.astir, critters: spider.preyAstir || traces.astir)
        }
        if !inHabitat { updateHammock(dt: dt) }
        updateCarrying()
        updateTankEntry(now: now)
        updateWildlife(now: now)
        updateTankWildlife(now: now)
        updatePrey()
        updateTraces(dt: dt)
        updateHand()
        updateSurroundings(now: now)

        // Only swallow clicks when the pointer is actually on the spider.
        let wantsMouse = interactive && (spider.isHeld || (!inHabitat && spider.hitTest(cursor)))
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
                frontWithPicture = false
                window.orderOut(nil)
                silkView.clear(slot: 0)
            }
            hc.scene.showCreatures(pose, sprite: spriteSide, prey: spider.prey)
            return hc.scene.didRedraw
        }
        if drawnInTank {
            // Back out over the desktop: its window comes up with its first
            // picture there, not the last one it had before it went in.
            drawnInTank = false
            view.redrawNext()
            frontWithPicture = true
        }
        // In your hand, it is drawn over everything — out on the screen,
        // from where it is in the tank's world; what is loose in the tank
        // stays there.
        var pose = pose
        if inHabitat, let hc = habitat {
            hc.scene.showCreatures(nil, sprite: spriteSide, prey: spider.prey)
            pose = pose.shifted(by: hc.scene.worldToScreen)
        }
        // (The window follows it, and its silk is laid, as each pose goes
        // up with its picture: see `placeMoved`.)
        view.apply(pose)
        let moved = placeMoved
        placeMoved = false
        return moved
    }

    /// The window moved, or the silk is out, since the last frame: set as
    /// each pose goes up on the screen (see `SpriteShower`), which may be a
    /// moment after the frame that made it.
    private var placeMoved = false
    /// The spider's window is to come up with the next picture drawn.
    private var frontWithPicture = false

    /// The tank's camera, each frame while the tank is open: it follows the
    /// spider while it is in there (not while it is in your hand). And a
    /// tank closing with the spider out of sight in it waits for the glass
    /// to get to it first. True if the view moved.
    private func tickTank(dt: CGFloat) -> Bool {
        guard let hc = habitat, tankOpen else { return false }
        let moved = hc.scene.tick(dt: dt, spider: inHabitat && !spider.isHeld ? spider.worldPos : nil)
        if let deadline = closeWhenSeen, CACurrentMediaTime() >= deadline || hc.scene.isInView(spider.worldPos, margin: 40) || !inHabitat {
            closeWhenSeen = nil
            closeHabitat(animated: closeAnimated)
        }
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
        // (Nor making its entrance: it comes out from behind the bar.)
        guard !spider.inHammock, !spider.makingEntrance else {
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
            if visitors.count < Visitor.most, !inHabitat, !tankOpen, !awaitingEntrance, !spider.makingEntrance,
               !spider.config.paused, filmScreens.isEmpty {
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
        v.spider.fullScreenApp = !filmScreens.isEmpty
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
            s.config.approachCursor = spider.config.approachCursor
            s.config.pounceOnCursor = spider.config.pounceOnCursor
            s.config.webs = spider.config.webs
            s.config.hammocks = false
            s.config.paused = spider.config.paused
            s.drowsy = spider.drowsy
            s.raining = spider.raining
            if rescale { v.resize() }
        }
    }

    @objc private func toggleVisitors() { setVisitors(!visitorsOn, ask: true) }

    /// Turning them on from the panel asks first, over what they cost in
    /// power; the welcome tour says so in small print instead (`ask` false).
    private func setVisitors(_ on: Bool, ask: Bool) {
        guard on != visitorsOn else { return }
        if on {
            if ask {
                let alert = NSAlert()
                alert.messageText = "Let other spiders visit?"
                alert.informativeText = "Now and then a spider will drop by to play with \(spider.name.isEmpty ? "yours" : spider.name) for a few minutes — up to \(Visitor.most) at once.\n\nEvery spider is animated sixty times a second, so each visitor uses a lot more CPU and battery. With several about, your Mac may run warm and its fans may come on."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Let Them Visit")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
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

    /// Sends everyone about on their way, and gives it a proper wait
    /// before the next one drops by.
    private func dismissVisitors() {
        let now = CACurrentMediaTime()
        for v in visitors where !v.leaving { startLeaving(v, now: now) }
        nextVisitAt = now + visitGap
        refreshMenu()
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

    /// Looks at a window's top-left corner on its own: how far along its
    /// top row from the corner the window is still see-through is the
    /// radius of its rounding. (Called on the window tracker's queue: see
    /// `WindowTracker.withCornerRadii`.)
    static func measureCornerRadius(of w: TrackedWindow, primaryTop: CGFloat) -> CGFloat? {
        let side: CGFloat = 48
        let rect = CGRect(x: w.frame.minX, y: primaryTop - w.frame.maxY, width: side, height: side)
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

    // MARK: Traces

    /// What it has left about: their physics, and the window they are
    /// drawn in, up only while there is anything to show.
    private func updateTraces(dt: CGFloat) {
        if traces.isEmpty {
            if tracesShown {
                tracesShown = false
                traceView.apply(traces)
                traceWindow.orderOut(nil)
            }
            return
        }
        traces.scale = spider.config.scale
        let began = traceTiming ? CACurrentMediaTime() : 0
        defer {
            if traceTiming {
                traceTime.frames += 1
                traceTime.total += CACurrentMediaTime() - began
            }
        }
        let out = !inHabitat && !spider.isHeld
        traces.update(dt: dt, cursor: V2(NSEvent.mouseLocation), prey: inHabitat ? [] : spider.prey,
                      spider: out ? spider.worldPos : nil, spiderGrounded: out && spider.isStanding)
        traceView.apply(traces)
        if !tracesShown {
            tracesShown = true
            // Under the creatures, the lines and the spider.
            if preyShown { traceWindow.order(.below, relativeTo: preyWindow.windowNumber) }
            else if window.isVisible { traceWindow.order(.below, relativeTo: window.windowNumber) }
            else { traceWindow.orderFrontRegardless() }
        }
    }

    /// Tools only (SPIDER_TRACE_TEST): a few of each, to look at.
    private func layOutTestTraces() {
        guard let f = NSScreen.main?.frame else { return }
        let top = map.menuBarBottom(for: f) ?? f.maxY
        let a0 = V2(f.minX + 230, top), b0 = V2(f.minX + 290, f.minY)
        if let a = SilkPin.at(a0, map: map), let b = SilkPin.at(b0, map: map) {
            traces.leaveLine([a0, V2(f.minX + 250, f.midY), b0], from: a, to: b)
        }
        let c0 = V2(f.maxX - 320, top)
        if let c = SilkPin.at(c0, map: map) { traces.leaveLine([c0, c0 - V2(-30, 220)], from: c, to: nil) }
        if let id = traces.startWeb(corner: V2(f.minX, f.minY), a: V2(f.minX, f.minY + 58), b: V2(f.minX + 58, f.minY)) {
            traces.spin(id, by: 1)
        }
        for (i, kind) in [PreyKind.moth, .beetle, .fruitFly, .cricket].enumerated() {
            traces.leaveLeftover(of: kind, at: V2(f.minX + 120 + CGFloat(i) * 45, f.minY + 80), facing: 1)
        }
    }

    /// Tools only: how long the traces take a frame (SPIDER_TRACE_TEST).
    private var traceTiming = false
    private var traceTime: (update: Double, total: Double, frames: Int) = (0, 0, 0)

    private func setTraceLimit(_ v: CGFloat) {
        traceLimitSetting = v
        traces.limit = AppDelegate.traceLimit(for: v)
        UserDefaults.standard.set(Double(v), forKey: "traceLimit")
    }

    private func setLeavesTraces(_ on: Bool) {
        leavesTraces = on
        traces.enabled = on
        saveSettings()
        refreshMenu()
    }

    // MARK: Web pages

    /// Climbing pages on or off: the watcher, the browsers' titles (a new
    /// page's sign), and an ear for scrolls and clicks — all only while on.
    private func setClimbsPages(_ on: Bool, save: Bool = true) {
        climbsPages = on
        pageWatch.enabled = on
        tracker.readsBrowserTitles = on
        for m in pageMonitors { NSEvent.removeMonitor(m) }
        pageMonitors = []
        if on {
            // (Only the pointer's whereabouts and how far a scroll goes:
            // what is clicked or scrolled is not ours to know.)
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
                self?.pageWatch.scrolled(at: V2(NSEvent.mouseLocation), by: e.scrollingDeltaY, precise: e.hasPreciseScrollingDeltas)
            }) { pageMonitors.append(m) }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
                self?.pageWatch.clicked(at: V2(NSEvent.mouseLocation))
            }) { pageMonitors.append(m) }
        }
        if save {
            saveSettings()
            tracker.pollNow()
            refreshMenu()
        }
    }

    /// The first time a browser fills the screen with pages to climb and it
    /// cannot see them, it asks (once: after that, the menu says how).
    /// Where the extension goes on disk for a browser to load it from: a
    /// place of its own, which moving or updating the app leaves alone.
    private static var extensionFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(AppInfo.name).appendingPathComponent("Browser Extension")
    }

    /// The browser a page is being climbed in that the extension could be
    /// added to (while it is not on the line already).
    private var extensionWanted: (name: String, address: String)? {
        guard climbsPages, !pageWatch.extensionConnected else { return nil }
        return pageWatch.browsers.lazy.compactMap(PageWatcher.extensionsPage(for:)).first
    }

    /// Adding the extension: out of the store if it is there (see
    /// `extensionStore`); until then, loaded by hand — the extension put
    /// where the browser can find it, shown in the Finder, the way there
    /// on the clipboard, and three steps to follow.
    private func addExtension() {
        panel?.close()
        if let store = AppDelegate.extensionStore { NSWorkspace.shared.open(store); return }
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("Extension"),
              FileManager.default.fileExists(atPath: bundled.path) else { return }
        let dest = AppDelegate.extensionFolder
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: bundled, to: dest)
        let browser = extensionWanted ?? ("your browser", "chrome://extensions")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(browser.address, forType: .string)
        NSWorkspace.shared.activateFileViewerSelecting([dest])
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Add the \(AppInfo.name) extension to \(browser.name)"
        alert.informativeText = """
            With it, \(spider.name.isEmpty ? "your spider" : spider.name) rides the page exactly as you scroll, and notices at once when the page changes.

            1. In \(browser.name), go to \(browser.address) — it's on your clipboard, so paste it into the address bar.
            2. Turn on Developer mode (top right).
            3. Click Load unpacked, and choose the "Browser Extension" folder just shown in the Finder.

            It only ever tells the app where things are on the page you're looking at and how far you've scrolled — nothing on the page is read, and nothing goes anywhere but this Mac.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// The extension's page in the Chrome Web Store, once it is published
    /// there: then adding it is one click.
    static let extensionStore: URL? = nil

    private func askToSeePages() {
        guard climbsPages, pageWatch.wantsLeave, !UserDefaults.standard.bool(forKey: "askedToSeePages") else { return }
        UserDefaults.standard.set(true, forKey: "askedToSeePages")
        CGRequestScreenCaptureAccess()
    }

    /// The ledges on the pages have changed: into the map with them. Found
    /// afresh (`settled`), anything standing on one re-reads its footing.
    private func pagesChanged(settled: Bool) {
        map.setPages(pageWatch.loops(), screens: pageWatch.pageScreens)
        for s in allSpiders { s.fullScreenApp = !filmScreens.isEmpty }
        if settled { for s in allSpiders where !s.inHabitat { s.pageLedgesChanged(moved: pageWatch.moved) } }
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
              filmScreens.isEmpty, idle < 300, loose < 2 else {
            nextWildAt = now + Double(randRange(120, 300))
            return
        }
        nextWildAt = now + wildGap
        let hour = Calendar.current.component(.hour, from: Date())
        if spider.releaseWild(night: hour >= 20 || hour < 6, raining: feelsWeather && sense.raining).isEmpty {
            nextWildAt = now + Double(randRange(120, 300))
        }
    }

    /// The tank alive: now and then something finds its own way into the
    /// tank — what comes, and where, up to what is in there: flies to the
    /// flowers, a beetle out from under the bark, moths to a light after dark,
    /// worms in the wet (see HabitatEcology.swift) — while the spider is in
    /// there to meet it and somebody is about. A few at most.
    private func updateTankWildlife(now: CFTimeInterval) {
        guard tankWildOn, !testingHabitat, inHabitat, tankOpen, let hc = habitat else { return }
        let eco = hc.scene.ecology
        if nextTankWildAt == 0 { nextTankWildAt = now + Double(eco.arrivalGap()) * 0.5 }
        guard now >= nextTankWildAt else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let loose = spider.prey.filter { $0.state == .loose }
        guard !spider.config.paused, !spider.dormant, !spider.isHeld, idle < 600, loose.count < 4, loose.filter(\.wild).count < 3 else {
            nextTankWildAt = now + Double(randRange(30, 90))
            return
        }
        nextTankWildAt = now + Double(eco.arrivalGap())
        let seen = hc.scene.visibleWorld
        if let a = eco.arrival(near: V2(seen.midX, seen.midY)) { spider.releaseInTank(a) }
    }

    @objc private func toggleTankWildlife() {
        tankWildOn.toggle()
        nextTankWildAt = 0
        saveSettings()
        refreshMenu()
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
        // In the tank, somewhere the glass shows: you see it let go.
        spider.release(kind, in: inHabitat ? habitat?.scene.visibleWorld.insetBy(dx: 40, dy: 0) : nil)
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
        makePanel()
        Perf.measure("panel: shown") { panel?.toggle(from: button) }
    }

    /// The panel's popover shown once, unseen, as the app starts (see
    /// `PanelController.warmUp`) — as soon as the icon is in the menu bar,
    /// a moment after launch — and then `go`: the spider set off. (Within a
    /// second, or it goes anyway.)
    private func warmUpPanel(tries: Int = 0, then go: @escaping () -> Void) {
        if let button = statusItem.button, let panel, Perf.measure("panel: warmed up", { panel.warmUp(from: button) }) {
            go()
            return
        }
        guard tries < 20 else { go(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.warmUpPanel(tries: tries + 1, then: go) }
    }

    /// The panel, made once. The app makes it as it starts, laid out and
    /// ready, before the spider is out and about (see
    /// `applicationDidFinishLaunching`): made the first time the icon was
    /// clicked, it held the spider up for a good part of a second.
    private func makePanel() {
        guard panel == nil else { return }
        panel = Perf.measure("panel: built") {
            PanelController(pages: panelPages(), footer: panelFooter(),
                            design: { [weak self] in self?.spider.design ?? SpiderDesign() })
        }
        Perf.measure("panel: laid out") { panel?.refresh() }
    }

    private func panelFooter() -> [PanelButton] {
        [
            PanelButton("Spider Studio", symbol: "paintbrush.pointed") { [unowned self] in panel?.close(); openStudio() },
            PanelButton("Quit", symbol: "power") { [unowned self] in quit() },
        ]
    }

    /// The panel opened at a given page (0 is the first).
    @objc private func openSettings() {
        if panel?.isShown != true { togglePanel() }
        panel?.show(pageTitled: "Behavior")
    }

    /// `generic`: for the welcome tour's picture of it, which is the same
    /// for everyone — no name of anyone's spider in it.
    private func panelPages(generic: Bool = false) -> [PanelPage] {
        var name: String { generic ? "Spider" : spider.name.isEmpty ? "Your spider" : spider.name }
        let home = PanelPage(title: "Spider", symbol: "house", sections: [
            PanelSection(title: nil, rows: [
                // Only there while an update found on the daily check waits.
                .buttons([
                    PanelButton(title: { [unowned self] in "Update to \(updater.waiting ?? "")" }, symbol: { "arrow.down.circle" },
                                shown: { [unowned self] in updater.waiting != nil },
                                selected: { true }) { [unowned self] in checkForUpdates() },
                ]),
                .buttons([
                    PanelButton(title: { [unowned self] in hidden ? "Show \(name)" : "Hide \(name)" },
                                symbol: { [unowned self] in hidden ? "eye" : "eye.slash" }) { [unowned self] in toggleHidden() },
                    PanelButton("To the Middle", symbol: "scope") { [unowned self] in teleportToMiddle() },
                ]),
                .toggle("Pause", help: "It stays just where it is until you unpause it.",
                        get: { [unowned self] in spider.config.paused }, set: { [unowned self] _ in togglePause() }),
            ]),
            PanelSection(title: "Size", rows: [
                .choice(options: AppDelegate.sizes.map(\.0),
                        get: { [unowned self] in
                            AppDelegate.sizes.indices.min { abs(AppDelegate.sizes[$0].1 - spider.config.scale) < abs(AppDelegate.sizes[$1].1 - spider.config.scale) } ?? 2
                        },
                        set: { [unowned self] i in setScale(AppDelegate.sizes[i].1) }),
            ]),
            PanelSection(title: "Energy", rows: [
                .choice(options: AppDelegate.energyLevels.map(\.0),
                        get: { [unowned self] in
                            let l = spider.basePersonality.liveliness
                            return AppDelegate.energyLevels.indices.min { abs(AppDelegate.energyLevels[$0].1 - l) < abs(AppDelegate.energyLevels[$1].1 - l) } ?? 2
                        },
                        set: { [unowned self] i in setEnergy(level: AppDelegate.energyLevels[i].1) }),
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
                    // (Pictured in the welcome, it tells nothing of anyone's spider.)
                    if generic { return "Its personality drifts a little with how things go, always close to what you set in the Studio." }
                    guard learns, let m = memory else { return "\(name) is just as the Studio made it." }
                    return m.summary(name: name, base: spider.basePersonality)
                },
                .buttons([
                    PanelButton("Forget It All", symbol: "arrow.uturn.backward", shown: { [unowned self] in learns }) { [unowned self] in forgetExperiences() },
                ]),
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
                .toggle("Creatures Live in the Habitat",
                        help: "In the habitat, now and then something comes in on its own — what, and where, depends on what's in there: flies to flowers, mosquitoes to water, beetles and ants under bark and in leaf litter, crickets in the dark, worms in the damp after rain, moths to a light after dark.",
                        get: { [unowned self] in tankWildOn }, set: { [unowned self] on in if on != tankWildOn { toggleTankWildlife() } }),
            ]),
            PanelSection(title: "Appetite", rows: [
                .status { [unowned self] in
                    spider.fed > 0.66 ? "\(name) is stuffed." : spider.fed > 0.2 ? "\(name) is content." : "\(name) could eat."
                },
            ]),
        ])
        let behavior = PanelPage(title: "Behavior", symbol: "slider.horizontal.3", sections: [
            PanelSection(title: "The Pointer", rows: [
                .toggle("Watch the Cursor", help: "It notices the pointer and keeps its eyes on it: its head and body turn to follow it about, and it stops to look.",
                        get: { [unowned self] in spider.config.followCursor }, set: { [unowned self] _ in toggleFollow() }),
                .toggle("Come to the Cursor", help: "It goes over to see a pointer resting nearby — along its ledge, or down a line from the top of a window to one below. If it can't get any nearer, it soon loses interest.",
                        get: { [unowned self] in spider.config.approachCursor }, set: { [unowned self] _ in toggleApproach() }),
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
                .status { [unowned self] in
                    spider.hasHammock ? "\(name) has a hammock in the corner of the screen."
                        : spider.hasAnyHammock ? "\(name) is still spinning its hammock."
                        : spider.config.hammocks ? "No hammock yet." : "Turn on Build Hammocks for one."
                },
                .buttons([
                    PanelButton("Build One", symbol: "hammer", enabled: { [unowned self] in spider.config.hammocks },
                                shown: { [unowned self] in !spider.hasAnyHammock }) { [unowned self] in buildHammock() },
                    PanelButton("Nap in It", symbol: "moon.zzz", shown: { [unowned self] in spider.hasHammock }) { [unowned self] in nap() },
                    PanelButton("Clear It Away", symbol: "trash", shown: { [unowned self] in spider.hasAnyHammock }) { [unowned self] in clearHammock() },
                ]),
            ]),
            PanelSection(title: "Traces", rows: [
                .toggle("Leave Traces", help: "It leaves its mark about the desktop: silk strands between the ledges it leaps and drops between, little webs in corners, what's left of its meals, a toy hauled off on a line. Only ever drawn over the desktop — nothing of yours is touched — and it all fades away on its own.",
                        get: { [unowned self] in leavesTraces }, set: { [unowned self] on in setLeavesTraces(on) }),
                .slider("Most at Once", low: "A Few", high: "Unlimited",
                        get: { [unowned self] in traceLimitSetting }, set: { [unowned self] v in setTraceLimit(v) },
                        enabled: { [unowned self] in leavesTraces }),
                .status { [unowned self] in
                    guard leavesTraces else { return "\(name) leaves nothing behind." }
                    let most = AppDelegate.traceLimit(for: traceLimitSetting).map { "Up to \($0) at once; the oldest fade first." }
                        ?? "No limit: everything stays until it fades on its own."
                    let strands = traces.strands.filter { $0.kind != .free }.count, webs = traces.webs.count, bits = traces.leftovers.count
                    var parts: [String] = []
                    if strands > 0 { parts.append(strands == 1 ? "a strand of silk" : "\(strands) strands of silk") }
                    if webs > 0 { parts.append(webs == 1 ? "a little web" : "\(webs) little webs") }
                    if bits > 0 { parts.append(bits == 1 ? "some leftovers" : "leftovers from \(bits) meals") }
                    guard !parts.isEmpty else { return "\(most) Nothing about just now." }
                    let list = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
                    return "\(most) Out there: \(list)."
                },
                .buttons([
                    PanelButton("Tidy Up", symbol: "wind", enabled: { [unowned self] in !traces.isEmpty },
                                shown: { [unowned self] in leavesTraces }) { [unowned self] in traces.clear(); refreshMenu() },
                ]),
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
            PanelSection(title: "Toys", rows: [
                .buttons([PanelButton("Laser Pointer", symbol: "smallcircle.filled.circle",
                                      selected: { [unowned self] in handToy == .laser }) { [unowned self] in choose(.laser) }]
                         + ToyKind.allCases.map { kind in
                    PanelButton(kind.label, symbol: kind.symbol,
                                selected: { [unowned self] in handToy == .toy(kind) }) { [unowned self] in choose(.toy(kind)) }
                }),
                .status { [unowned self] in
                    switch handToy {
                    case nil: return "Pick one to play with it."
                    case .laser?: return "The red dot is on your pointer: it chases it wherever you take it. Right-click or press Esc to put it away."
                    case .toy(.feather)?: return "The feather dangles on its string from your pointer: wave it about for it to leap at. Right-click or press Esc to put it away."
                    case .toy(let kind)? where holdingToy:
                        return "The \(kind.label.lowercased()) is in your hand: take it where you want it and click to put it down, or drag and flick to throw it. Right-click or press Esc to put it away."
                    case .toy(let kind)?:
                        return "Drag the \(kind.label.lowercased()) to throw it again or click it to poke it, or press its button to pick it back up. Right-click it to put it away."
                    }
                },
                .buttons([
                    PanelButton("Put Away", symbol: "tray.and.arrow.down", shown: { [unowned self] in handToy != nil }) { [unowned self] in putAway() },
                ]),
                .toggle("Bell Sound", help: "The bell tinkles out loud — quietly — when it's knocked or shaken. Off, you only see it jingle.",
                        get: { [unowned self] in toySounds }, set: { [unowned self] on in toySounds = on; saveSettings() }),
            ]),
            PanelSection(title: "Places", rows: [
                .buttons([
                    PanelButton(title: { [unowned self] in spider.confine != nil ? "Redraw the Box" : "Draw a Box" }, symbol: { "square.dashed" }) { [unowned self] in panel?.close(); drawBox() },
                    PanelButton("Let It Out", symbol: "square.slash", shown: { [unowned self] in spider.confine != nil }) { [unowned self] in freeSpider() },
                    PanelButton(title: { [unowned self] in tankOpen ? "Close Habitat" : "Open Habitat" }, symbol: { "leaf" }) { [unowned self] in panel?.close(); toggleHabitat() },
                ]),
            ]),
        ])
        let mac = PanelPage(title: "Your Mac", symbol: "laptopcomputer", sections: [
            PanelSection(title: nil, rows: [
                .toggle("Low Power Mode", help: "Sleepy and slow, drawing half as many frames, so it uses less power itself. It follows your Mac's Low Power Mode, but you can put it in or take it out yourself.",
                        get: { [unowned self] in lowPower }, set: { [unowned self] on in setLowPower(on) }),
                .toggle("Feel the Battery", help: "When your Mac goes into Low Power Mode, so does it. Plugging in the charger perks it right up.",
                        get: { [unowned self] in feelsPower }, set: { [unowned self] _ in toggleFeelPower() }),
                .toggle("Notice the Weather", help: "When it rains where you are, rain is on its mind. It checks every twenty minutes, from Open-Meteo, going by roughly where your internet connection is (GeoJS).",
                        get: { [unowned self] in feelsWeather }, set: { [unowned self] _ in toggleFeelWeather() }),
                .toggle("Notice Pop-ups", help: "A notification sliding in makes it jump — right up in the air, if it is on top of something — and stare at it. Turn the volume or brightness up or down and it looks up to see. Nothing in a notification is read.",
                        get: { [unowned self] in feelsCommotion }, set: { [unowned self] _ in toggleFeelCommotion() }),
                .toggle("Dance to Music", help: Ears.supported
                        ? "When an app plays music with a beat, it hears it and dances along, in time. It only listens while something is playing, and only for the beat: nothing is recorded or kept. The first time, macOS asks whether it may listen to your Mac's sound."
                        : "Dancing along to music needs macOS 14.2 or later.",
                        get: { [unowned self] in dancesToMusic && Ears.supported }, set: { [unowned self] _ in toggleDanceToMusic() },
                        enabled: { Ears.supported }),
                .toggle("Rain on the Screen", help: "Faint streaks of rain across the desktop while it rains. Never over a full-screen app or in Low Power Mode.",
                        get: { [unowned self] in showsRain }, set: { [unowned self] _ in toggleShowRain() },
                        enabled: { [unowned self] in feelsWeather }),
                .status { [unowned self] in
                    let power: String?
                    switch (powerOverride, macLowPower) {
                    case (true?, false): power = "Low Power Mode, by your say-so: \(name) is feeling sleepy."
                    case (false?, _): power = "Your Mac is in Low Power Mode, but \(name) is at full speed."
                    case (_, true): power = "Low Power Mode: \(name) is feeling sleepy."
                    default: power = nil
                    }
                    let rain = feelsWeather && sense.raining ? "It's raining where you are." : nil
                    let apps = ears.playingApps.isEmpty ? "the music" : ears.playingApps.joined(separator: " and ")
                    let music: String?
                    switch dancesToMusic ? ears.status : .off {
                    case .hearing(let bpm): music = "Dancing to \(apps), at \(Int(bpm)) beats a minute."
                    case .listening: music = "Listening to \(apps) for a beat."
                    case .deaf: music = "Something is playing, but \(name) can't hear it. Allow \(AppInfo.name) under System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording."
                    default: music = nil
                    }
                    let said = [power, rain, music].compactMap { $0 }.joined(separator: " ")
                    return said.isEmpty ? "Nothing to report." : said
                },
            ]),
        ] + (!AppDelegate.pagesReady ? [] : [
            PanelSection(title: "Web Pages", rows: [
                .toggle("Climb Web Pages",
                        help: "When your browser fills the screen — zoomed to fill it, or full screen — it climbs about on the page itself: along the tops of cards, bars and boxes, under them and up their sides, wherever there's room for it. It rides along when you scroll, and finds its feet again when you click through to another page. It goes by how the page looks; nothing on it is read, kept or sent.",
                        get: { [unowned self] in climbsPages }, set: { [unowned self] on in if on != climbsPages { setClimbsPages(on) } }),
                .status { [unowned self] in
                    guard climbsPages else { return "With a browser filling the screen, \(name) keeps to the edges of the screen." }
                    guard CGPreflightScreenCaptureAccess() else {
                        return "To see the page, \(AppInfo.name) needs to be allowed under System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording — then quit and reopen it."
                    }
                    return pageWatch.summary ?? "Fill the screen with a browser window and \(name) will climb about the page."
                },
                .status { [unowned self] in
                    guard climbsPages, CGPreflightScreenCaptureAccess() else { return "" }
                    if pageWatch.extensionConnected { return "The \(AppInfo.name) extension is helping: it follows your scrolling exactly." }
                    guard let b = extensionWanted else { return "" }
                    return "Add the \(AppInfo.name) extension to \(b.name) and it rides along exactly as you scroll."
                },
                .buttons([
                    PanelButton(title: { [unowned self] in "Add to \(extensionWanted?.name ?? "the Browser")…" }, symbol: { "puzzlepiece.extension" },
                                shown: { [unowned self] in CGPreflightScreenCaptureAccess() && extensionWanted != nil }) { [unowned self] in
                        addExtension()
                    },
                ]),
                .buttons([
                    PanelButton("Let It See the Screen…", symbol: "eye",
                                shown: { [unowned self] in climbsPages && !CGPreflightScreenCaptureAccess() }) { [unowned self] in
                        CGRequestScreenCaptureAccess()
                        refreshMenu()
                    },
                ]),
            ]),
        ]))
        let app = PanelPage(title: "App", symbol: "gearshape", sections: [
            PanelSection(title: nil, rows: [
                .toggle("Launch at Login", help: "Opens by itself when you log in.",
                        get: { [unowned self] in loginEnabled }, set: { [unowned self] _ in toggleLogin() }),
            ]),
            PanelSection(title: "Updates", rows: [
                .toggle("Check Automatically", help: "Looks for a new version once a day.",
                        get: { [unowned self] in updater.checksAutomatically },
                        set: { [unowned self] on in updater.checksAutomatically = on }),
                .toggle("Install Automatically", help: "Downloads new versions quietly and puts them in the next time the app quits.",
                        info: nil,
                        get: { [unowned self] in updater.installsAutomatically },
                        set: { [unowned self] on in updater.installsAutomatically = on },
                        enabled: { [unowned self] in updater.checksAutomatically }),
                .buttons([
                    PanelButton(title: { [unowned self] in updater.waiting.map { "Update to \($0)" } ?? (updater.canCheck ? "Check for Updates" : "Checking…") },
                                symbol: { "arrow.down.circle" },
                                enabled: { [unowned self] in updater.canCheck },
                                selected: { [unowned self] in updater.waiting != nil }) { [unowned self] in checkForUpdates() },
                ]),
                .status { [unowned self] in
                    if let error = updater.startError {
                        return "Version \(Updater.currentVersion). Updates are off: \(error.localizedDescription)"
                    }
                    return updater.waiting.map { "Version \(Updater.currentVersion) — \($0) is ready to install." }
                        ?? "Version \(Updater.currentVersion)"
                },
            ]),
            PanelSection(title: "Start Over", rows: [
                .note("Lost it, or something looks stuck? This starts the app afresh. Its looks and settings are kept."),
                .buttons([PanelButton("Reset Everything", symbol: "arrow.counterclockwise") { [unowned self] in resetEverything() }]),
            ]),
            // Hardly ever wanted, so small: two buttons side by side.
            PanelSection(title: "Help", rows: [
                .buttons([
                    PanelButton("Welcome Tour", symbol: "play.circle") { [unowned self] in
                        panel?.close()
                        startWelcome()
                    },
                    PanelButton("Report a Bug", symbol: "ladybug") { [unowned self] in reportBug() },
                ]),
            ]),
            PanelSection(title: "Support", rows: [
                .note("Spider Buddy is completely free and I want to keep it that way. If you enjoy having it around, consider supporting the continued development :)"),
                .buttons([
                    PanelButton("Buy Me a Coffee", symbol: "cup.and.saucer") {
                        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/ephemeril")!)
                    },
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
                    PanelButton("Dismiss Visitors", symbol: "hand.wave",
                                enabled: { [unowned self] in visitors.contains { !$0.leaving } }) { [unowned self] in dismissVisitors() },
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
        return [home, play, feed, visitorsPage, behavior, mac, app]
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
        // With something on the pointer, a right-click (on the spider, say,
        // sat right on the dot) puts it away.
        if onPointer {
            putAway()
            return
        }
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
            traceWindow.orderOut(nil)
            tracesShown = false
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
    /// Closing with it somewhere in the tank the glass isn't showing: the
    /// glass goes to it first, and the tank closes once it can be seen (or
    /// at this time, whatever).
    private var closeWhenSeen: CFTimeInterval?
    private var closeAnimated = true
    /// Where in the tank's world it was, and where the glass was looking,
    /// for when the tank opens again with it inside.
    private static let tankSpiderKey = "habitatSpider"

    private func rememberTankPlace() {
        guard let hc = habitat, tankOpen || tankClosing else { return }
        hc.scene.camera.save()
        if inHabitat {
            UserDefaults.standard.set([Double(spider.worldPos.x), Double(spider.worldPos.y)], forKey: AppDelegate.tankSpiderKey)
        }
    }

    @objc private func toggleHabitat() {
        if tankOpen { closeHabitat() } else { openHabitat() }
    }

    private var spiderName: String { spider.name.isEmpty ? "Your spider" : spider.name }

    /// The tank's window, made once (ahead of time, as the app starts: see
    /// `makeHabitatAhead`). The tank itself is set up the first time it is
    /// opened (`HabitatController.load`).
    private func makeHabitat() -> HabitatController {
        if let hc = habitat { return hc }
        let hc = HabitatController(spiderName: spider.name, standoff: map.standoff, syncMaps: testingHabitat && testMapsNow)
        // (The tank alive: what it and whatever is loose in it read.)
        spider.ecology = hc.scene.ecology
        hc.tankWildlife = { [weak self] in self?.tankWildOn ?? false }
        hc.onToggleTankWildlife = { [weak self] in self?.toggleTankWildlife() }
        // (Its surfaces are laid out for its size: once now, then only as
        // the furniture changes.)
        hc.scene.setStandoff(map.standoff)
        view.toSpider = { [weak self] p in
            guard let self, self.inHabitat, let hc = self.habitat else { return p }
            return hc.scene.worldPoint(fromScreen: p)
        }
        hc.onLetOut = { [weak self] in self?.closeHabitat() }
        hc.onFeed = { [weak self] kind in self?.release(kind) }
        hc.canFeed = { [weak self] in self?.canFeed ?? false }
        hc.outsideAvailable = { [weak self] in self?.feelsWeather ?? false }
        hc.enableOutside = { [weak self] in
            guard let self, !self.feelsWeather else { return }
            self.toggleFeelWeather()
        }
        hc.outsideSummary = { [weak self] in self?.outsideSummary }
        hc.weather.outside = feelsWeather ? outsideWeather : nil
        if let k = forcedWeather {
            hc.weather.persists = false
            hc.weather.debugForce(k)
        }
        hc.scene.onThunder = { [weak self] p, loud in
            guard let self, self.inHabitat, !self.spider.isHeld else { return }
            self.spider.thunder(at: p, loud: loud)
        }
        habitat = hc
        return hc
    }

    /// The tank's window made and laid out now, while the app is starting
    /// and the spider isn't out and about yet: making a window with a
    /// toolbar, and laying it out and drawing it the first time, holds up
    /// the main thread — where the spider lives — for a good part of a
    /// second. Only the window: the tank itself is set up when it is first
    /// opened (off the main thread, mostly).
    private func makeHabitatAhead() {
        let hc = Perf.measure("habitat: window made ahead") { makeHabitat() }
        Perf.measure("habitat: window laid out ahead") {
            hc.window.contentView?.layoutSubtreeIfNeeded()
            hc.window.displayIfNeeded()
        }
    }

    /// The tank set up for opening: given its habitat, and the spider.
    /// `mapNow`: its surfaces laid out at once (the spider is being put
    /// straight into it), rather than off the main thread.
    private func loadHabitat(_ hc: HabitatController, mapNow: Bool) {
        hc.load(mapNow: mapNow)
        if hc.scene.spider !== spider { hc.scene.spider = spider }
    }

    // MARK: The habitat's weather

    /// The tank's weather, this frame: it is drawn there, and the spider —
    /// in it, and not in your hand — feels it. Anywhere else the air is
    /// still and dry.
    private func updateWeather(now: CFTimeInterval, dt: CGFloat) {
        guard let hc = habitat, tankOpen else {
            if !spider.weather.isCalm { spider.weather = .calm }
            return
        }
        let c = hc.tickWeather(dt: dt, clock: CGFloat(now))
        let feel = inHabitat && !spider.isHeld ? WeatherFeel(c) : .calm
        if spider.weather != feel { spider.weather = feel }
    }

    /// What it is doing outside, from the weather look-up: the habitat can
    /// follow it.
    private func heardOutside(code: Int, wind: Double, day: Bool, temperature: Double?) {
        let k = WeatherKind.outside(code: code, wind: wind, day: day, temperature: temperature)
        outsideWeather = k
        var bits = ["Outside it’s \(k == .clear ? "clear" : k.label.lowercased())"]
        if let t = temperature { bits.append(String(format: "%.0f°C", t)) }
        if wind >= 1 { bits.append(String(format: "wind %.0f km/h", wind)) }
        outsideSummary = bits.joined(separator: ", ") + "."
        habitat?.weather.outside = k
    }

    /// Where the tank opens: dead centre of its screen, every time — so it
    /// is always where it is expected, and the decorate sidebar (which
    /// grows the window to the right) always has room to open.
    private func tankFrame(_ hc: HabitatController) -> CGRect {
        let size = hc.tankSize
        let p = spider.worldPos
        let screen = NSScreen.screens.first { $0.frame.contains(p.point) } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? worldFrame()
        return CGRect(x: vis.midX - size.width / 2, y: vis.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Opens the tank. `restoring`: it was in there when the app last
    /// quit, and is put straight back — where it was in the tank, the glass
    /// on it.
    private func openHabitat(restoring: Bool = false) {
        if let hc = habitat, hc.window.isVisible || hc.window.isMiniaturized, !tankClosing {
            NSApp.activate(ignoringOtherApps: true)
            if hc.window.isMiniaturized { hc.window.deminiaturize(nil) }
            hc.window.makeKeyAndOrderFront(nil)
            return
        }
        if hidden { toggleHidden() }
        let opening = CACurrentMediaTime()
        defer { if Perf.timing { Perf.note("habitat: opened, all told", ms: (CACurrentMediaTime() - opening) * 1000) } }
        let hc = Perf.measure("habitat: controller made") { makeHabitat() }
        Perf.measure("habitat: loaded") { loadHabitat(hc, mapNow: restoring) }
        // (Put straight into it, it needs its surfaces there now.)
        if restoring, !hc.scene.mapCurrent { hc.scene.rebuildMap(now: true) }
        tankClosing = false
        closeWhenSeen = nil
        boxWhileInTank = spider.confine
        if spider.confine != nil {
            spider.confine = nil
            boxWindow.orderOut(nil)
        }
        Perf.measure("habitat: in the Dock") { updateDockPresence() }
        let target = tankFrame(hc)
        // It fades in where it goes. (Not rising into place as well: every
        // step of a window moving has AppKit asking the window server about
        // the displays, on the main thread — a good part of a tenth of a
        // second, all told, which the spider would feel.)
        hc.window.setFrame(target, display: false)
        hc.window.alphaValue = 0
        Perf.measure("habitat: window up") {
            NSApp.activate(ignoringOtherApps: true)
            hc.window.makeKeyAndOrderFront(nil)
            hc.scene.syncToScreen()
        }
        headInAfter = CACurrentMediaTime() + 0.45
        hc.setStatus(restoring ? nil : "\(spiderName) is on the way in…")
        if restoring {
            hc.window.setFrame(target, display: true)
            hc.scene.syncToScreen()
            let saved = (UserDefaults.standard.array(forKey: AppDelegate.tankSpiderKey) as? [Double]).flatMap { $0.count == 2 ? V2(CGFloat($0[0]), CGFloat($0[1])) : nil }
            let world = hc.scene.habitat.bounds.insetBy(dx: 30, dy: 30)
            let at: V2
            if let s = saved, world.contains(s.point) {
                at = s
            } else {
                let middle = V2(hc.scene.visibleWorld.midX, HabitatLayout.ground)
                at = hc.scene.groundSpots().min { $0.distance(to: middle) < $1.distance(to: middle) } ?? middle
            }
            spider.placeInHabitat(map: hc.scene.map, at: at)
            hc.scene.lookAt(spider.worldPos)
            settleIn()
        } else {
            // It will come in over the ground: the glass looks along it,
            // where it last looked (the middle, the first time).
            let x = HabitatCamera.saved() != nil ? hc.scene.visibleWorld.midX : hc.scene.habitat.size.width / 2
            hc.scene.lookAt(V2(x, hc.scene.visibleWorld.height / 2))
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hc.window.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            hc.scene.syncToScreen()
            self?.refreshMenu()
            // The first time: a look round.
            hc.maybeStartTour()
        })
        calmFrames = 0
        calm = false
        refreshMenu()
    }

    /// Each frame while the tank is open and it is not in it: it makes its
    /// way in. On the ground (or a window) under the tank, a line up to the
    /// lip of its ground and a climb; off to one side, it walks over; up
    /// above it, it drops down; flying, it is in the moment it is over it.
    /// (All on the screen: it is out on the desktop.)
    private func updateTankEntry(now: CFTimeInterval) {
        guard let hc = habitat, tankOpen, !inHabitat, !spider.isHeld, now >= headInAfter, closeWhenSeen == nil else { return }
        if spider.config.paused {
            hc.setStatus("\(spiderName) is paused — unpause it to let it climb in")
            return
        }
        let glass = hc.scene.glassOnScreen
        let p = spider.worldPos
        if spider.isAirborne {
            if glass.insetBy(dx: 10, dy: 10).contains(p.point) { enterThroughGlass(hc) }
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
        // The lip of the ground where the glass shows it. Looking up into
        // the air of the tank, the glass goes down to the ground for it
        // (once you have stopped looking round).
        guard let lip = hc.scene.groundLipOnScreen else {
            if hc.scene.camera.resting, !hc.scene.overviewOpen, now - lastEntryNudge > 1.5 {
                lastEntryNudge = now
                let vis = hc.scene.visibleWorld
                hc.scene.camera.glide(toCentre: V2(vis.midX, vis.height / 2), thenFollow: false)
            }
            return
        }
        let lips = hc.scene.visibleGroundSpotsOnScreen()
        // The lip of the open ground nearest to straight above it.
        guard let target = lips.min(by: { abs($0.x - p.x) < abs($1.x - p.x) }) else { return }
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

    /// Over the glass, in the air: in it is, just where it is — now in the
    /// tank's world.
    private func enterThroughGlass(_ hc: HabitatController) {
        spider.shiftSpace(by: -hc.scene.worldToScreen)
        spider.moveInMidAir(map: hc.scene.map, habitat: true)
        settleIn()
    }

    /// At the top of its line: over the lip and onto the ground — the
    /// screen spot it reached, and the one it is landing on, now in the
    /// tank's world.
    private func climbedIn(landing target: V2) {
        guard let hc = habitat, tankOpen, !inHabitat else { return }
        let d = hc.scene.worldToScreen
        spider.shiftSpace(by: -d)
        spider.hopIntoHabitat(map: hc.scene.map, landing: target - d)
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
    /// drawn over it as ever — from where it is in the tank's world to the
    /// same spot on the screen; after a while it heads back in.
    private func carriedOut() {
        guard let hc = habitat else { return }
        inHabitat = false
        spider.shiftSpace(by: hc.scene.worldToScreen)
        spider.moveInMidAir(map: map, habitat: false)
        headInAfter = CACurrentMediaTime() + 12
        habitat?.setStatus("\(spiderName) is out on your desktop — it’ll climb back in")
        refreshMenu()
    }

    /// Carried to the tank and let go of over it, or carried out of it —
    /// whichever side of the glass it is on is where it is.
    private func updateCarrying() {
        guard spider.isHeld, let hc = habitat, tankOpen else { return }
        let glass = hc.scene.glassOnScreen
        if inHabitat {
            if !glass.insetBy(dx: -6, dy: -6).contains(hc.scene.screenPoint(fromWorld: spider.worldPos).point) { carriedOut() }
        } else if glass.insetBy(dx: 16, dy: 16).contains(spider.worldPos.point) {
            enterThroughGlass(hc)
        }
    }

    /// Closes the tank. If it is in there, it drops from the very spot it
    /// was, onto whatever is below on the desktop, as the tank fades away —
    /// and if that spot is somewhere in the tank the glass isn't showing,
    /// the glass goes to it first, so it drops from where it can be seen.
    private func closeHabitat(animated: Bool = true) {
        guard let hc = habitat, hc.window.isVisible || hc.window.isMiniaturized, !tankClosing else { return }
        if animated, closeWhenSeen == nil, inHabitat, !spider.isHeld, !hc.window.isMiniaturized,
           !hc.scene.isInView(spider.worldPos, margin: 40) {
            hc.scene.showOverview(false)
            if hc.decorating { hc.toggleDecorate() }
            hc.scene.camera.recall(to: spider.worldPos)
            closeWhenSeen = CACurrentMediaTime() + 2.5
            closeAnimated = animated
            hc.setStatus("Off to find \(spiderName)…")
            return
        }
        closeWhenSeen = nil
        hc.tour?.finish()
        rememberTankPlace()
        tankClosing = true
        if inHabitat {
            inHabitat = false
            spider.shiftSpace(by: hc.scene.worldToScreen)
            spider.dropOutOfHabitat(onto: map)
        } else if spider.isClimbingAway {
            // Halfway up its line into it: the line goes with the tank.
            spider.dropOutOfHabitat(onto: map)
        }
        spider.cursorArea = nil
        lastSpiderCursor = V2(-9999, -9999)
        hc.scene.showCreatures(nil, sprite: spriteSide, prey: [])
        hc.scene.showOverview(false)
        if drawnInTank {
            // Straight back over the desktop, where it was — the window up
            // with its first picture (see `frontWithPicture`).
            drawnInTank = false
            view.redrawNext()
            frontWithPicture = true
            view.apply(spider.pose())
        }
        if hc.decorating { hc.toggleDecorate() }
        if let box = boxWhileInTank {
            spider.confine = box
            boxWindow.orderFrontRegardless()
            boxWhileInTank = nil
        }
        let f = hc.window.frame
        calmFrames = 0
        calm = false
        refreshMenu()
        let finish = { [weak self] in
            hc.window.orderOut(nil)
            hc.window.alphaValue = 1
            hc.window.setFrame(f, display: false)
            self?.tankClosing = false
            self?.updateDockPresence()
            self?.refreshMenu()
        }
        guard animated else { finish(); return }
        // (Fading where it is: see the opening, in `openHabitat`.)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hc.window.animator().alphaValue = 0
        }, completionHandler: finish)
    }

    /// While the tank or the Studio is open it is a window like any other
    /// app's, so the app is in the Dock (with its bundle icon, the menu bar spider) with a
    /// menu bar of its own; with both closed, it is a menu bar icon again.
    private func updateDockPresence() {
        showInDock(tankOpen || studioVisible)
    }

    private func showInDock(_ on: Bool) {
        guard on != (NSApp.activationPolicy() == .regular) else { return }
        if on {
            if NSApp.mainMenu == nil { NSApp.mainMenu = mainMenu() }
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// The menus it has while it is in the Dock.
    private func mainMenu() -> NSMenu {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Spider Buddy"
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        // The habitat's weather, filled in afresh each time it opens; and
        // saving it, and My Habitats.
        let weatherMenu = NSMenu(title: "Weather")
        weatherMenu.delegate = weatherMenuFiller
        let habitatMenu = NSMenu(title: "Habitat")
        habitatMenu.delegate = habitatMenuFiller
        // (Filled now too, so ⌘S works before the menu is first opened.)
        habitatMenuFiller.menuNeedsUpdate(habitatMenu)
        // (For typing names: paste and the rest.)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        for sub in [appMenu, editMenu, habitatMenu, weatherMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = sub
            menu.addItem(item)
        }
        NSApp.windowsMenu = windowMenu
        return menu
    }

    private lazy var habitatMenuFiller = MenuFiller { [weak self] menu in
        guard let self, let hc = self.habitat, self.tankOpen else {
            menu.removeAllItems()
            let none = NSMenuItem(title: "Open the habitat to save it", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return
        }
        hc.fillHabitatsMenu(menu)
    }

    private lazy var weatherMenuFiller = MenuFiller { [weak self] menu in
        guard let self, let hc = self.habitat, self.tankOpen else {
            menu.removeAllItems()
            let none = NSMenuItem(title: "Open the habitat to change its weather", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return
        }
        hc.fillWeatherMenu(menu)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking it in the Dock brings the tank forward.
        if tankOpen { openHabitat() }
        return false
    }

    // MARK: Habitat testing

    /// The saved state a habitat test may touch, to put back afterwards.
    /// A habitat test is running: what the spider comes to know of things
    /// in it is not kept.
    private var testingHabitat = false
    /// The self-tests look at the surfaces straight after changing them, so
    /// they have them laid out at once (see `HabitatSceneView.rebuildMap`).
    private var testMapsNow = true

    private func habitatTestSnapshot() -> () -> Void {
        testingHabitat = true
        habitat?.scene.syncMaps = testMapsNow
        // (What it makes of new things would change the timing of tests of
        // other things: they run without it. The curiosity test gives it a
        // knowledge of its own.)
        spider.knowledge = nil
        let keys = [Habitat.key, HabitatController.tankWidthKey, HabitatController.glassKey, HabitatController.nameKey, "inHabitat",
                    WeatherSettings.key, WeatherClock.saveKey, HabitatCamera.saveKey, AppDelegate.tankSpiderKey, HabitatKnowledge.key,
                    SpiderMemory.key, HabitatTour.seenKey, HabitatTour.decoratingSeenKey, HabitatController.currentSaveKey]
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
    private func debugShot(_ path: String, rect: CGRect, window: NSWindow? = nil, crop: CGRect? = nil) {
        let img: CGImage?
        if let window {
            img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution])
        } else {
            guard let primary = NSScreen.screens.first else { return }
            let r = CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            img = CGWindowListCreateImage(r, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
        }
        guard var img else { return }
        if let crop, let window {
            // (In points from the window's top left; the picture is in pixels.)
            let k = CGFloat(img.width) / max(window.frame.width, 1)
            guard let part = img.cropping(to: CGRect(x: crop.minX * k, y: crop.minY * k, width: crop.width * k, height: crop.height * k)) else { return }
            img = part
        }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func runHabitatTest(dir: String?) {
        print("habitat test: launched with inHabitat pref \(UserDefaults.standard.bool(forKey: "inHabitat")), open \(tankOpen)")
        let restore = habitatTestSnapshot()
        func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
        func report(_ label: String) {
            let p = spider.worldPos
            let scene = habitat?.scene.glassOnScreen ?? .zero
            let cam = habitat?.scene.camera.origin ?? .zero
            print(String(format: "habitat test: %@ in=%@ open=%@ at %.0f,%.0f %@ climbing=%@ glass %.0f,%.0f %.0fx%.0f lip %.0f camera %.0f,%.0f",
                         label, "\(inHabitat)", "\(tankOpen)", p.x, p.y, spider.debugState, "\(spider.isClimbingAway)",
                         scene.minX, scene.minY, scene.width, scene.height, habitat?.scene.groundLipOnScreen ?? -1, cam.x, cam.y))
            fflush(stdout)
        }
        func shot(_ name: String) {
            guard let dir, let hc = habitat else { return }
            let s = inHabitat ? hc.scene.screenPoint(fromWorld: spider.worldPos) : spider.worldPos
            let r = hc.window.frame.union(CGRect(x: s.x - 150, y: s.y - 150, width: 300, height: 300)).insetBy(dx: -40, dy: -40)
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
            let from = inHabitat ? hc.scene.screenPoint(fromWorld: spider.worldPos) : spider.worldPos
            let out = V2(hc.window.frame.minX - 180, hc.window.frame.midY)
            spider.beginGrab(at: view.toSpider?(from) ?? from)
            var step = 0
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
                step += 1
                let p = V2.lerp(from, out, CGFloat(min(step, 50)) / 50)
                self.spider.moveGrab(to: self.view.toSpider?(p) ?? p)
                if step >= 60 { t.invalidate(); self.spider.endGrab(throwVelocity: .zero); report("let go outside") }
            }
            for i in 1...20 { after(1.2 + Double(i) * 1.0) { report("outside+\(i)") } }
            after(3) { shot("outside") }
        }
        // The tank moved about with it inside.
        after(36) { [self] in
            guard let hc = habitat else { return }
            report("before move")
            // (Its world position is the same; on the screen it goes with the tank.)
            let rel = hc.scene.viewPoint(fromWorld: spider.worldPos)
            hc.window.setFrameOrigin(CGPoint(x: hc.window.frame.minX + 120, y: hc.window.frame.minY - 60))
            after(0.3) {
                let now = hc.scene.viewPoint(fromWorld: self.spider.worldPos)
                print(String(format: "habitat test: moved tank; spider on the glass %.1f,%.1f -> %.1f,%.1f", rel.x, rel.y, now.x, now.y))
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
            let local = scene.viewPoint(fromWorld: spider.worldPos)
            drag(local, CGPoint(x: -260, y: local.y), steps: 40) {
                check("carried out: out of the tank", !self.inHabitat && !self.spider.inHabitat, self.spider.debugState)
                check("carried out: drawn over the desktop", self.window.isVisible)
                after(0.5) {
                    // Straight back in, by hand, for the rest.
                    self.spider.beginGrab(at: self.spider.worldPos)
                    self.spider.moveGrab(to: V2(scene.glassOnScreen.midX, scene.glassOnScreen.midY))
                    after(0.3) {
                        self.updateCarrying()
                        self.spider.endGrab(throwVelocity: .zero)
                        check("carried back in", self.inHabitat, self.spider.debugState)
                    }
                }
            }
        }
        after(6) {
            hc.scene.setHabitat(Habitat.preset(.forestFloor, world: hc.scene.habitat.size))
            if !hc.decorating { hc.toggleDecorate() }
            // A log in the middle of the glass, the glass well along the tank.
            if let log = scene.habitat.items.last(where: { $0.kind == .log }) { scene.lookAt(V2(log.x, log.rect.midY)) }
        }
        after(7) {
            guard let log = scene.habitat.items.last(where: { $0.kind == .log }) else { check("a log to test with", false); return }
            let c = scene.viewPoint(fromWorld: V2(log.rect.midX, log.rect.midY))
            let start = CGPoint(x: c.x, y: c.y)
            check("the glass is well along the tank", scene.camera.origin.x > 200, String(format: "camera %.0f", scene.camera.origin.x))
            drag(start, CGPoint(x: start.x + 120, y: start.y + 40), steps: 20) {
                let moved = scene.habitat.items.first { $0.id == log.id }!
                check("clicked piece is selected", scene.selected == log.id)
                check("dragged along, one to one", abs(moved.x - log.x - 120) < 3, String(format: "x %.0f -> %.0f", log.x, moved.x))
                check("let go in the air, it comes to rest on what is under it", moved.y < 40 && (moved.y == 0 || scene.habitat.items.contains { o in
                    o.id != log.id && (Habitat.restingTop(o, from: moved.x - moved.w * 0.25, to: moved.x + moved.w * 0.25)
                        .map { abs($0 - HabitatLayout.ground - moved.y) < 0.5 } ?? false) }), String(format: "y %.1f", moved.y))
                // Its top-right handle, pulled out.
                let r2 = moved.rect.insetBy(dx: -5, dy: -5).offsetBy(dx: -scene.visibleWorld.minX, dy: -scene.visibleWorld.minY)
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
        after(9.2) { [self] in
            // The name in the lid: a click, typing, and Return renames it;
            // Escape leaves it be; cleared, it is the spider's again.
            let field = hc.titleView.nameField
            func click() {
                let p = field.convert(CGPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
                // The release is queued first: the press waits for it.
                for type in [NSEvent.EventType.leftMouseUp, .leftMouseDown] {
                    guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: hc.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
                    if type == .leftMouseUp { NSApp.postEvent(e, atStart: false) } else { field.mouseDown(with: e) }
                }
            }
            func type(_ text: String, then command: Selector) {
                guard let editor = field.currentEditor() as? NSTextView else { check("typing into the name", false); return }
                editor.insertText(text, replacementRange: editor.selectedRange())
                editor.doCommand(by: command)
            }
            let spiderName = self.spider.name
            click()
            check("clicking the name starts typing", hc.titleView.editing && field.currentEditor() != nil)
            type("Web Palace", then: #selector(NSResponder.insertNewline(_:)))
            check("Return renames it", hc.window.title == "Web Palace" && !hc.titleView.editing, hc.window.title)
            check("the keys go back to the tank", hc.window.firstResponder === scene)
            check("the name is kept", UserDefaults.standard.string(forKey: HabitatController.nameKey) == "Web Palace")
            hc.rename("Someone Else")
            check("renaming the spider leaves it", hc.window.title == "Web Palace", hc.window.title)
            click()
            type("Nope", then: #selector(NSResponder.cancelOperation(_:)))
            check("Escape leaves it be", hc.window.title == "Web Palace" && !hc.titleView.editing, hc.window.title)
            click()
            type("", then: #selector(NSResponder.insertNewline(_:)))
            check("cleared, it is named after the spider again", hc.window.title == "Someone Else’s Habitat"
                  && UserDefaults.standard.object(forKey: HabitatController.nameKey) == nil, hc.window.title)
            click()
            type(String(repeating: "x", count: 60), then: #selector(NSResponder.insertNewline(_:)))
            check("a long name is cut short", hc.window.title.count == HabitatTitleView.maxLength, "\(hc.window.title.count)")
            UserDefaults.standard.removeObject(forKey: HabitatController.nameKey)
            hc.rename(spiderName)
        }
        after(10) { [self] in
            // The window pulled wider (from its right edge): the glass shows
            // more of the world, which stays where it is.
            let was = scene.bounds.size, cam = scene.camera.origin, at = spider.worldPos
            let proposed = CGSize(width: hc.window.frame.width + 200, height: hc.window.frame.height - 40)
            let size = hc.windowWillResize(hc.window, to: proposed)
            hc.window.setFrame(CGRect(origin: hc.window.frame.origin, size: size), display: true)
            after(0.5) {
                let s = scene.bounds
                check("the glass grows, any shape", s.width > was.width + 150 && abs(s.height - was.height + 40) < 12,
                      String(format: "%.0fx%.0f -> %.0fx%.0f", was.width, was.height, s.width, s.height))
                check("the world stays put", (scene.camera.origin - cam).length < 1 || scene.camera.mode != .free,
                      String(format: "camera %.0f,%.0f -> %.0f,%.0f", cam.x, cam.y, scene.camera.origin.x, scene.camera.origin.y))
                check("the spider the same size, in the same place", self.inHabitat && self.spider.worldPos.distance(to: at) < 60, self.spider.debugState)
                self.closeHabitat(animated: false)
                check("closed", !self.inHabitat && !self.tankOpen)
                after(0.5) { self.finishHabitatTest(restore) }
            }
        }
    }

    /// SPIDER_HABITAT_BUILD=1: building up off the ground in the tank, by
    /// synthesized drags, well along the tank and up in the air (so the
    /// camera is far from the world's corner).
    private func runHabitatBuildTest(dir: String?) {
        let restore = habitatTestSnapshot()
        var fails = 0
        func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            if !ok { fails += 1 }
            print("habitat build: [\(ok ? "ok  " : "FAIL")] \(label) \(detail)")
            fflush(stdout)
        }
        openHabitat(restoring: true)
        guard let hc = habitat else { return }
        let scene = hc.scene
        // (A beat later, so what has just changed is on the glass.)
        func shot(_ name: String) { if let dir { after(0.12) { self.debugShot("\(dir)/\(name).png", rect: .zero, window: hc.window) } } }
        func mouse(_ type: NSEvent.EventType, _ w: V2, clicks: Int = 1) {
            let p = scene.convert(scene.viewPoint(fromWorld: w), to: nil)
            guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: hc.window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) else { return }
            switch type {
            case .leftMouseDown: scene.mouseDown(with: e)
            case .leftMouseDragged: scene.mouseDragged(with: e)
            default: scene.mouseUp(with: e)
            }
        }
        /// A drag in the world, `from` to `to`; `midway` runs part way.
        func drag(_ from: V2, _ to: V2, steps: Int = 24, midway: (() -> Void)? = nil, then: @escaping () -> Void) {
            mouse(.leftMouseDown, from)
            var i = 0
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
                i += 1
                // (Eased in at the end, as a hand does.)
                let u = CGFloat(i) / CGFloat(steps)
                mouse(.leftMouseDragged, V2.lerp(from, to, 1 - (1 - u) * (1 - u)))
                if i == steps - 2 { midway?() }
                if i >= steps { t.invalidate(); mouse(.leftMouseUp, to); then() }
            }
        }
        func item(_ id: Int) -> HabitatItem { scene.habitat.item(id: id)! }
        func added(_ kind: HabitatItemKind) -> Int {
            scene.add(kind)
            return scene.habitat.items.last!.id
        }
        func place(_ id: Int, x: CGFloat, y: CGFloat) { scene.update(id) { $0.x = x; $0.y = y } }
        func linked(_ child: Int, _ parent: Int) -> Bool {
            let c = item(child).uid, p = item(parent).uid
            return scene.habitat.links.contains { $0.child == c && $0.parent == p }
        }
        let G = HabitatLayout.ground
        let world = scene.habitat.size
        let X = (world.width * 0.62).rounded()
        var h = Habitat(biome: .jungle, world: world)
        h.items = []
        scene.setHabitat(h)
        // (Once the window has finished opening.)
        after(0.7) { if !hc.decorating { hc.toggleDecorate() } }
        var brace = 0, branch = 0, vine = 0, post1 = 0, post2 = 0, plank = 0, fern = 0, high = 0
        after(1.2) {
            scene.lookAt(V2(X, G + 330))
            check("the glass is well along and up the tank", scene.camera.origin.x > 1000 && scene.camera.origin.y > 20,
                  String(format: "camera %.0f,%.0f", scene.camera.origin.x, scene.camera.origin.y))
            brace = added(.brace)
            place(brace, x: X - 120, y: 300)
            branch = added(.mediumBranch)
            place(branch, x: X + 60, y: 280)
        }
        after(2.2) {
            // The branch dragged over to lie 10 points above the brace's cup.
            let cup = item(brace).port("cup")!.pts[0]
            let along = item(branch).port("along0")!
            let grab = along.point(at: 0.5)
            let target = cup + V2(0, 10 + along.halfWidth(at: 0.5))
            drag(grab, grab + (target - grab), midway: { shot("build_1_snapping") }) {
                check("the branch clicks into the brace's cup", linked(branch, brace))
                check("…and is held up", scene.habitat.support(of: branch) == .held(by: brace), "\(scene.habitat.support(of: branch))")
                check("…and stays chosen", scene.selected == branch)
            }
        }
        after(3.4) {
            vine = added(.thinVine)
            let hangAt = item(branch).port("along0")!.point(at: 0.85)
            let top = item(vine).port("b0").map { _ in V2(item(vine).x, item(vine).rect.maxY) }!
            let grab = V2(item(vine).x, item(vine).rect.maxY - 20)
            drag(grab, grab + (hangAt + V2(8, -5) - top), steps: 30) {
                check("a vine hung from the branch", linked(vine, branch), String(format: "top at %.0f,%.0f", item(vine).x, item(vine).rect.maxY))
                check("…shorter, clear of the ground", item(vine).rect.minY > G, String(format: "bottom %.0f", item(vine).rect.minY))
            }
        }
        after(4.8) {
            // The brace moved: the branch and the vine come with it.
            let b0 = item(branch), v0 = item(vine)
            let grab = V2(item(brace).x, item(brace).rect.minY + 30)
            drag(grab, grab + V2(150, 60)) {
                let d = V2(item(branch).x - b0.x, item(branch).y - b0.y), dv = V2(item(vine).x - v0.x, item(vine).y - v0.y)
                check("moving the brace takes what it holds", d.distance(to: V2(150, 60)) < 2 && dv.distance(to: V2(150, 60)) < 2,
                      String(format: "branch %.0f,%.0f vine %.0f,%.0f", d.x, d.y, dv.x, dv.y))
                check("…still fastened", linked(branch, brace) && linked(vine, branch))
            }
        }
        after(6.2) {
            // The branch's top right corner pulled out: bigger, still on its cup, the vine still on it.
            scene.select(branch)
            let r = item(branch).rect.insetBy(dx: -5, dy: -5)
            drag(V2(r.maxX, r.maxY), V2(r.maxX + 70, r.maxY + 25), steps: 16) {
                let js = scene.habitat.links.compactMap { scene.habitat.joint($0) }.map { $0.child.distance(to: $0.seat) }
                check("resized by its corner", item(branch).w > r.width, String(format: "w %.0f", item(branch).w))
                check("…what is fastened stays fastened", (js.max() ?? 0) < 1 && linked(vine, branch) && linked(branch, brace),
                      String(format: "worst joint %.2f", js.max() ?? 0))
                shot("build_2_resized")
            }
        }
        after(7.4) {
            // ⌥: dragged right past the branch, it doesn't catch — and with
            // nothing to hang from, it goes back up to the lid.
            scene.debugPlaceFreely = true
            let top = V2(item(vine).x, item(vine).rect.maxY)
            drag(top + V2(0, -15), top + V2(30, -15)) {
                scene.debugPlaceFreely = false
                check("⌥-dragged, it is placed freely (not fastened)", !linked(vine, branch))
                check("…and, hanging from nothing, back to the lid", item(vine).rect.maxY >= world.height - 0.5, String(format: "top %.0f", item(vine).rect.maxY))
                hc.undo()
                check("⌘Z: hung from the branch again", linked(vine, branch))
            }
        }
        after(8.8) {
            // Two uprights, a plank across them, a fern on it.
            post1 = added(.verticalSupport)
            place(post1, x: X + 380, y: 0)
            post2 = added(.verticalSupport)
            place(post2, x: X + 560, y: 0)
            plank = added(.plank)
            place(plank, x: X + 470, y: 420)
        }
        after(9.6) {
            let topY = item(post1).rect.maxY
            let grab = V2(item(plank).x, item(plank).rect.midY)
            drag(grab, V2(X + 472, topY + item(plank).h / 2 + 9)) {
                check("the plank clicks onto the uprights", linked(plank, post1) && linked(plank, post2),
                      "\(scene.habitat.links.filter { $0.child == item(plank).uid }.count) links")
                fern = added(.fern)
                place(fern, x: X + 300, y: 0)
            }
        }
        after(10.8) {
            let grab = V2(item(fern).x, item(fern).rect.midY)
            drag(grab, V2(X + 460, item(plank).rect.maxY + 70)) {
                check("a fern let go of over it comes to rest on it", scene.habitat.support(of: fern) == .resting(on: plank),
                      "\(scene.habitat.support(of: fern))")
            }
        }
        after(12) {
            // An upright moved: the plank stays on the other; the fern with it.
            let p0 = item(plank)
            let grab = V2(item(post1).x, item(post1).rect.midY)
            drag(grab, grab + V2(-70, 0)) {
                check("one upright moved away: the plank stays put", item(plank) == p0 && linked(plank, post2) && !linked(plank, post1))
                hc.undo()
                check("⌘Z: back under it", linked(plank, post1))
            }
        }
        after(13.2) {
            // A branch left floating, and a support made for it.
            high = added(.longBranch)
            place(high, x: X - 100, y: 620)
            scene.select(high)
            check("up in the air on its own, it floats", scene.habitat.support(of: high) == .floating)
            shot("build_3_floating")
            scene.supportSelected()
            check("Add a Support holds it up", scene.habitat.support(of: high).holds, "\(scene.habitat.support(of: high))")
            check("…propped from the ground by a stake at the back", scene.habitat.items.contains { $0.kind == .stake && $0.y < 2 })
        }
        after(14.2) {
            // Saved, and loaded again.
            let back = Habitat.load()
            check("saved with its links", back.links == scene.habitat.links && back.items == scene.habitat.items,
                  "\(back.links.count) of \(scene.habitat.links.count)")
            check("nothing floating", scene.habitat.supports().values.allSatisfy(\.holds))
            scene.select(branch)
            scene.lookAt(V2(X + 150, G + 330))
            after(0.4) { shot("build_4_decorating") }
            after(0.8) { hc.debugShowShelf(.supports); after(0.4) { shot("build_5_supports_tab") } }
            after(1.6) { hc.debugShowShelf(.built); after(0.4) { shot("build_6_built_tab") } }
        }
        // A house: a wood wall at the back, a wall and a door, floorboards
        // across them, a twig on the wall, and the door shut and opened.
        let X2 = X + 760
        var backing = 0, wall = 0, door = 0, floor = 0, twig = 0
        after(17) {
            hc.debugShowShelf(.building)
            backing = added(.woodBacking)
            place(backing, x: X2 + 150, y: 0)
            scene.update(backing) { $0.w = 300; $0.h = 150 }
            wall = added(.wall)
            place(wall, x: X2, y: 0)
            door = added(.door)
            place(door, x: X2 + 300, y: 0)
            floor = added(.floorboards)
            scene.update(floor) { $0.w = 330 }
            place(floor, x: X2 + 150, y: 300)
            twig = added(.twig)
            place(twig, x: X2 + 150, y: 100)
            scene.lookAt(V2(X2 + 150, G + 220))
        }
        after(17.8) {
            let f = item(floor)
            let grab = V2(f.x, f.rect.midY)
            drag(grab, V2(f.x + 4, item(wall).rect.maxY + f.h / 2 + 8)) {
                check("floorboards dragged over two walls sit on both", linked(floor, wall) && linked(floor, door))
            }
        }
        after(19) {
            scene.select(twig)
            scene.supportSelected()
            let made = scene.habitat.items.last!
            check("a twig in front of the wood wall: a bracket screwed into it", made.kind == .branchBracket && scene.habitat.isBacked(made)
                  && scene.habitat.support(of: twig).holds, made.kind.rawValue)
            check("…drawn screwed in", (scene.debugItemLayers[made.id] as? ItemLayer)?.backed == true)
            // Double-clicked: the door shuts.
            let d = V2(item(door).x, item(door).rect.maxY - 20)
            mouse(.leftMouseDown, d); mouse(.leftMouseUp, d)
            mouse(.leftMouseDown, d, clicks: 2); mouse(.leftMouseUp, d, clicks: 2)
            check("double-clicking the door shuts it", item(door).kind == .doorClosed, item(door).kind.rawValue)
            shot("build_8_house")
            // Close-ups of it swinging shut, then (double-clicked again) open.
            func closeUp(_ name: String) {
                guard let dir else { return }
                let r = item(door).rect.insetBy(dx: -40, dy: -20)
                let lo = scene.convert(scene.viewPoint(fromWorld: V2(r.minX, r.minY)), to: nil)
                let hi = scene.convert(scene.viewPoint(fromWorld: V2(r.maxX, r.maxY)), to: nil)
                let crop = CGRect(x: lo.x, y: hc.window.frame.height - hi.y, width: hi.x - lo.x, height: hi.y - lo.y)
                self.debugShot("\(dir)/\(name).png", rect: .zero, window: hc.window, crop: crop)
            }
            for (k, t) in [0.02, 0.12, 0.22, 0.32, 0.45, 0.8].enumerated() { after(t) { closeUp("door_shut_\(k)") } }
            after(1.0) {
                mouse(.leftMouseDown, d); mouse(.leftMouseUp, d)
                mouse(.leftMouseDown, d, clicks: 2); mouse(.leftMouseUp, d, clicks: 2)
                for (k, t) in [0.02, 0.12, 0.22, 0.32, 0.45, 0.8].enumerated() { after(t) { closeUp("door_open_\(k)") } }
                after(0.9) {
                    mouse(.leftMouseDown, d); mouse(.leftMouseUp, d)
                    mouse(.leftMouseDown, d, clicks: 2); mouse(.leftMouseUp, d, clicks: 2)
                }
            }
        }
        after(21) {
            hc.debugShowShelf(nil)
            hc.toggleDecorate()
            after(0.5) {
                // Out of decorating, too: opened again.
                let d = V2(item(door).x, item(door).rect.maxY - 20)
                mouse(.leftMouseDown, d); mouse(.leftMouseUp, d)
                mouse(.leftMouseDown, d, clicks: 2); mouse(.leftMouseUp, d, clicks: 2)
                check("…and opens it again, not decorating", item(door).kind == .door, item(door).kind.rawValue)
                hc.toggleDecorate()
            }
        }
        after(22.2) {
            hc.debugShowShelf(nil)
            hc.toggleDecorate()
            // Shut in: the door shut, the spider put in the room. It lets
            // itself out.
            let d = V2(item(door).x, item(door).rect.maxY - 20)
            mouse(.leftMouseDown, d); mouse(.leftMouseUp, d)
            mouse(.leftMouseDown, d, clicks: 2); mouse(.leftMouseUp, d, clicks: 2)
            check("shut again", item(door).kind == .doorClosed)
            self.spider.placeInHabitat(map: scene.map, at: V2(X2 + 120, G + 30))
            scene.lookAt(V2(X2 + 150, G + 220))
            // Called over to the door, across the floor of the room: it
            // pushes the door open on its way, and goes out.
            for t in [3.0, 12.0, 24.0] {
                after(t) { if item(door).kind == .doorClosed, self.spider.standingOn != nil { self.spider.summon(to: V2(item(door).x - 12, G + 20)) } }
            }
        }
        var pushedOpen = false, gotOut = false, shutBehind = false
        var visited: [Int: Int] = [:]
        for k in 0..<1200 {
            after(23 + Double(k) * 0.05) {
                if let a = self.spider.standingOn, let o = scene.map.owner(of: a) { visited[o, default: 0] += 1 }
                if item(door).kind == .door { pushedOpen = true }
                let p = self.spider.worldPos
                if pushedOpen, p.x > item(door).rect.maxX + 10 || p.x < item(wall).rect.minX - 10 { gotOut = true }
                if pushedOpen, gotOut, item(door).kind == .doorClosed { shutBehind = true }
                if k == 80 || (pushedOpen && k % 100 == 0) { shot("build_7_spider_\(k)") }
            }
        }
        after(84) {
            check("shut in, walking to the door, the spider pushes it open", pushedOpen)
            check("…goes out", gotOut, String(format: "at %.0f,%.0f", self.spider.worldPos.x, self.spider.worldPos.y))
            check("…and it swings shut behind it", shutBehind, item(door).kind.rawValue)
            print("habitat build: things it stood on: \(visited.keys.compactMap { scene.habitat.item(id: $0)?.kind.rawValue }.sorted().joined(separator: ", "))")
            print("habitat build: \(fails == 0 ? "all ok" : "\(fails) FAILED")")
            self.finishHabitatTest(restore)
        }
    }

    /// SPIDER_HABITAT_CURIOUS=1: a toadstool put in while decorating, and the
    /// spider getting to know it in real time — it notices it, watches it,
    /// feels it, climbs it, comes to know it and then leaves it be — then a
    /// stump it is standing on dragged off by the mouse, with it on it.
    private func runHabitatCuriousTest(dir: String?) {
        let restore = habitatTestSnapshot()
        var fails = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            if !ok { fails += 1 }
            print("habitat curious: [\(ok ? "ok  " : "FAIL")] \(label) \(detail)")
            fflush(stdout)
        }
        func note(_ s: String) { print("habitat curious: \(s)"); fflush(stdout) }
        func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
        openHabitat(restoring: true)
        guard let hc = habitat else { return }
        hc.scene.debugKeepAnimating = true
        let scene = hc.scene
        func shot(_ name: String) { if let dir { debugShot("\(dir)/curious_\(name).png", rect: .null, window: hc.window) } }
        // A tank it knows (with a knowledge of its own for the test: the
        // real one is left be).
        let W = scene.habitat.size.width, G = HabitatLayout.ground
        var h = Habitat(biome: .forest, world: scene.habitat.size)
        _ = h.add(.rock, at: CGPoint(x: W / 2 - 700, y: 0))
        let stump = h.add(.stump, at: CGPoint(x: W / 2 - 420, y: 0))
        _ = h.add(.fern, at: CGPoint(x: W / 2 + 700, y: 0))
        spider.knowledge = HabitatKnowledge()
        scene.setHabitat(h)
        let floorY = G + scene.map.standoff
        spider.placeInHabitat(map: scene.map, at: V2(W / 2, floorY))
        scene.lookAt(V2(W / 2, G + 220))
        guard let know = spider.knowledge else { return }
        check("what was there it knows already", h.items.allSatisfy { know.isFamiliar($0.uid) })

        // Decorating: a toadstool put in, where the editor puts it.
        var mush: HabitatItem?
        after(4) {
            hc.toggleDecorate()
            scene.add(.mushroom)
            // (Some way off from it: where the editor puts it could be right
            // by it, and that it would see at once.)
            if let id = scene.selected {
                let x = self.spider.worldPos.x
                scene.moveItem(id, to: V2(x + (x < W / 2 ? 330 : -330), G))
            }
            mush = scene.selected.flatMap { scene.habitat.item(id: $0) }
            after(0.8) { hc.toggleDecorate() }
            if let m = mush {
                note(String(format: "toadstool put in at %.0f (spider at %.0f)", m.x, self.spider.worldPos.x))
                check("…new to it", know.stage(of: m.uid) == .unknown)
            }
        }
        /// Then the stump (below).
        var carry: () -> Void = {}
        var t0 = 0.0, noticed: Double?, watched: Double?, touched: Double?, climbed: Double?, familiar: Double?
        var afterInquiries = 0, floating = 0
        var probes: Set<String> = []
        var last = ""
        let clock = CACurrentMediaTime()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [self] timer in
            guard let m = mush else { return }
            if t0 == 0 { t0 = CACurrentMediaTime() }
            let t = CACurrentMediaTime() - t0
            let stage = know.stage(of: m.uid)
            let inq = spider.debugInquiryUID == m.uid ? spider.debugInquiry : "-"
            if noticed == nil, stage != .unknown { noticed = t; after(0.6) { shot("1_noticed") } }
            if watched == nil, inq.hasPrefix("watch") { watched = t }
            if touched == nil, let f = spider.debugFeelAt, m.rect.insetBy(dx: -8, dy: -8).contains(f.point) { touched = t; after(0.5) { shot("2_touching") } }
            if climbed == nil, spider.debugUnderfoot == m.id, spider.isStanding { climbed = t; after(1.0) { shot("3_on_it") } }
            if familiar == nil, stage == .familiar { familiar = t; after(1.0) { shot("4_familiar") } }
            if let f = familiar, t > f + 8, spider.debugInquiryUID == m.uid { afterInquiries += 1 }
            if spider.isStanding, let a = spider.standingOn, let p = scene.map.worldPoint(a), p.distance(to: spider.worldPos) > 16 { floating += 1 }
            if let d = inq.range(of: "done [") { for p in inq[d.upperBound...].prefix(while: { $0 != "]" }).split(separator: ",") { probes.insert(String(p)) } }
            let line = "\(stage) | \(inq) | \(spider.debugState)"
            if line != last { note(String(format: "%6.1fs %@", t, line)); last = line }
            let done = familiar.map { t > $0 + 45 } ?? false
            if done || CACurrentMediaTime() - clock > 300 {
                timer.invalidate()
                func f(_ x: Double?) -> String { x.map { String(format: "%.1fs", $0) } ?? "never" }
                note("noticed \(f(noticed)), watched \(f(watched)), touched \(f(touched)), climbed \(f(climbed)), familiar \(f(familiar)); probes \(probes.sorted())")
                check("it notices the toadstool — not the moment it lands", noticed.map { $0 > 0.2 } ?? false, f(noticed))
                check("it watches it", watched != nil, f(watched))
                check("it feels it with its front legs", touched != nil, f(touched))
                check("it climbs it", climbed != nil, f(climbed))
                check("it comes to know it", familiar != nil, f(familiar))
                check("then leaves it be", afterInquiries == 0, "\(afterInquiries) looks into it after")
                check("never standing on nothing", floating == 0, "\(floating)")
                carry()
            }
        }

        // Carried off on the stump it is standing on.
        carry = { [self] in
            guard let s = scene.habitat.item(id: stump.id),
                  let top = s.interactionPoints(on: scene.map).first(where: { $0.kind == .top }), let a = top.stand else {
                check("stump top found", false)
                finishHabitatTest(restore)
                return
            }
            scene.lookAt(V2(s.x, G + 200))
            spider.debugAttach(loopID: a.loopID, segIdx: a.segIdx, t: a.t, dir: 1)
            after(1.0) { [self] in
                hc.toggleDecorate()
                check("standing on the stump", spider.debugUnderfoot == s.id, "\(spider.debugUnderfoot ?? -1)")
                let from = scene.viewPoint(fromWorld: V2(s.x, s.rect.midY - 10))
                // (Away from the toadstool, so it isn't set down beside it.)
                let by = CGPoint(x: (mush?.x ?? s.x) > s.x ? -220 : 220, y: 70)
                func mouse(_ type: NSEvent.EventType, _ p: CGPoint) {
                    let w = scene.convert(p, to: nil)
                    guard let e = NSEvent.mouseEvent(with: type, location: w, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: hc.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
                    switch type {
                    case .leftMouseDown: scene.mouseDown(with: e)
                    case .leftMouseDragged: scene.mouseDragged(with: e)
                    default: scene.mouseUp(with: e)
                    }
                }
                let p0 = spider.worldPos
                var worst: CGFloat = 0
                mouse(.leftMouseDown, from)
                var i = 0
                Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [self] timer in
                    i += 1
                    let u = CGFloat(i) / 90
                    mouse(.leftMouseDragged, CGPoint(x: from.x + by.x * u, y: from.y + by.y * u))
                    if let now = scene.habitat.item(id: s.id), i > 10 {
                        let moved = V2(now.x - s.x, now.y - s.y)
                        worst = max(worst, (spider.worldPos - p0 - moved).length)
                    }
                    if i == 45 { shot("5_carried") }
                    guard i >= 90 else { return }
                    timer.invalidate()
                    mouse(.leftMouseUp, CGPoint(x: from.x + by.x, y: from.y + by.y))
                    after(1.2) { [self] in
                        let now = scene.habitat.item(id: s.id)
                        let footed = spider.standingOn.flatMap { scene.map.worldPoint($0) }.map { $0.distance(to: spider.worldPos) < 16 } ?? false
                        check("carried on the stump, it goes with it", worst < 30, String(format: "strayed %.0f pt", worst))
                        check("…and stands on it where it is put down", spider.debugUnderfoot == s.id && footed,
                              "on \(spider.debugUnderfoot ?? -1) footed \(footed), stump moved \(Int((now?.x ?? s.x) - s.x))")
                        shot("6_put_down")
                        hc.toggleDecorate()
                        print("habitat curious: \(fails == 0 ? "all ok" : "\(fails) FAILED")")
                        finishHabitatTest(restore)
                    }
                }
            }
        }
    }

    /// SPIDER_HABITAT_PLACES=1: the tank put to use (see HabitatPlaces.swift
    /// and "Places in the tank" in Spider.swift), in real time. A tank it
    /// knows — a rock, a table, a bark cave, a lookout — and a water dish put
    /// in while decorating. It finds the dish; later, thirsty, goes back and
    /// drinks. Up the lookout to look out over it all. Then a downpour: in
    /// under the table (built) rather than the bark cave (nearer).
    private func runHabitatPlacesTest(dir: String?) {
        let restore = habitatTestSnapshot()
        var fails = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            if !ok { fails += 1 }
            print("habitat places: [\(ok ? "ok  " : "FAIL")] \(label) \(detail)")
            fflush(stdout)
        }
        func note(_ s: String) { print("habitat places: \(s)"); fflush(stdout) }
        func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
        /// Checks `test` every tenth of a second until it holds or `secs` pass, then `done(held, secs taken)`.
        func wait(_ secs: Double, _ test: @escaping () -> Bool, _ done: @escaping (Bool, Double) -> Void) {
            let t0 = CACurrentMediaTime()
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                let t = CACurrentMediaTime() - t0
                if test() { timer.invalidate(); done(true, t) } else if t > secs { timer.invalidate(); done(false, t) }
            }
        }
        openHabitat(restoring: true)
        guard let hc = habitat else { return }
        hc.scene.debugKeepAnimating = true
        let scene = hc.scene
        hc.weather.persists = false
        hc.weather.debugForce(.clear)
        func shot(_ name: String) { if let dir { debugShot("\(dir)/places_\(name).png", rect: .null, window: hc.window) } }
        let W = scene.habitat.size.width, G = HabitatLayout.ground
        var h = Habitat(biome: .forest, world: scene.habitat.size)
        _ = h.add(.rock, at: CGPoint(x: W / 2 - 900, y: 0))
        let table = h.add(.table, at: CGPoint(x: W / 2 - 420, y: 0))
        let cave = h.add(.barkCave, at: CGPoint(x: W / 2 + 260, y: 0))
        let look = h.add(.lookout, at: CGPoint(x: W / 2 + 760, y: 0))
        spider.knowledge = HabitatKnowledge()
        scene.setHabitat(h)
        let floorY = G + scene.map.standoff
        spider.placeInHabitat(map: scene.map, at: V2(W / 2, floorY))
        scene.lookAt(V2(W / 2, G + 220))
        guard let know = spider.knowledge else { return }
        spider.debugSetUrges(thirst: 0, view: 0, rest: 0, roam: 0)
        func gap(_ it: HabitatItem) -> CGFloat {
            let r = it.rect, p = spider.worldPos
            return V2(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY)).length
        }
        func footed() -> Bool { spider.standingOn.flatMap { scene.map.worldPoint($0) }.map { $0.distance(to: spider.worldPos) < 16 } ?? false }
        // (Off its surface for a moment — a hop, a landing, put down — is
        // nothing; for half a second, it is standing on nothing.)
        var floating = 0, offFor = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] timer in
            if !inHabitat { timer.invalidate(); return }
            offFor = spider.isStanding && !footed() ? offFor + 1 : 0
            if offFor == 5 { floating += 1 }
        }
        var last = ""
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [self] timer in
            guard inHabitat else { timer.invalidate(); return }
            let line = "\(spider.debugState) | \(spider.debugErrand)"
            if line != last { note(line); last = line }
        }

        // Decorating: a water dish put in, some way off.
        var dish: HabitatItem?
        after(4) {
            hc.toggleDecorate()
            scene.add(.waterDish)
            if let id = scene.selected {
                let x = self.spider.worldPos.x
                scene.moveItem(id, to: V2(x - 330, G))
            }
            dish = scene.selected.flatMap { scene.habitat.item(id: $0) }
            after(0.8) { hc.toggleDecorate() }
        }
        // It finds it; goes off; later, thirsty, comes back to it.
        after(6) { [self] in
            guard let d = dish else { check("dish put in", false); finishHabitatTest(restore); return }
            note(String(format: "water dish at %.0f (spider at %.0f)", d.x, spider.worldPos.x))
            wait(120, { know.stage(of: d.uid) != .unknown }) { [self] found, t in
                check("it finds the dish", found, String(format: "%.1fs", t))
                if !found { know.notice(d, unease: 0) }
                // Off about its business, a way from it.
                wait(90, { gap(d) > 220 }) { [self] away, _ in
                    if !away { spider.summon(to: V2(d.x + 500, floorY)) }
                    after(away ? 0.5 : 6) { [self] in
                        note(String(format: "away from it (%.0f pt); now it feels like a drink", gap(d)))
                        spider.debugSetUrges(thirst: 1.3)
                        wait(150, { [self] in spider.debugDrinking && spider.debugSipAt.map { d.water!.insetBy(dx: -6, dy: -6).contains($0.point) } == true }) { [self] drank, t in
                            check("…later it goes back to it and drinks", drank, String(format: "%.1fs", t))
                            if drank { after(1.5) { shot("1_drinking") } }
                            wait(40, { [self] in spider.debugErrandKind == nil }) { _, _ in lookout() }
                        }
                    }
                }
            }
        }
        // Up the lookout, to look out.
        func lookout() {
            // (From beside it: the best view about, by a long way.)
            spider.placeInHabitat(map: scene.map, at: V2(look.rect.minX - 90, floorY))
            scene.lookAt(V2(look.rect.midX, G + 260))
            spider.debugSetUrges(view: 1.3)
            var dirs: [V2] = []
            wait(120, { [self] in
                guard spider.debugErrandKind == "lookout", spider.debugUnderfoot == look.id, spider.debugErrand.contains(" act ") else { return false }
                if let e = spider.debugEyeOn {
                    let v = (e - spider.worldPos).normalized
                    if !dirs.contains(where: { $0.dot(v) > 0.9 }) { dirs.append(v) }
                }
                return dirs.count >= 3
            }) { [self] ok, t in
                check("it climbs the lookout and looks out from it, scanning", ok,
                      String(format: "%.1fs, %d directions (%@)", t, dirs.count, spider.debugErrandPlace?.key ?? spider.debugErrand))
                if ok { scene.lookAt(spider.worldPos); after(0.8) { shot("2_lookout") } }
                after(2) { downpour() }
            }
        }
        // A downpour: in under the table, not the cave.
        func downpour() {
            spider.debugSetUrges(thirst: 0, view: 0)
            spider.placeInHabitat(map: scene.map, at: V2(W / 2 + 120, floorY))
            after(1.5) { [self] in
                hc.weather.debugForce(.rain)
                wait(80, { [self] in spider.isStanding && spider.debugErrandKind == "shelter" && spider.debugErrand.contains(" act ") }) { [self] ok, t in
                    let pl = spider.debugErrandPlace
                    let underTable = pl.map { $0.roofOwner == table.id || $0.thing == table.id || $0.q[.made] >= 0.5 } ?? false
                    let inCave = gap(cave) < 20
                    check("in the rain it shelters under the table (built), not in the nearer cave", ok && underTable && !inCave,
                          String(format: "%.1fs at %@ %@", t, pl?.key ?? "-", "\(pl?.q ?? PlaceQualities())"))
                    scene.lookAt(spider.worldPos)
                    after(3) { shot("3_sheltering") }
                    after(5) { [self] in
                        hc.weather.debugForce(.clear)
                        check("never standing on nothing", floating == 0, "\(floating)")
                        print("habitat places: \(fails == 0 ? "all ok" : "\(fails) FAILED")")
                        finishHabitatTest(restore)
                    }
                }
            }
        }
    }

    /// SPIDER_HABITAT_ECOLOGY=1: the tank alive (HabitatEcology.swift, and
    /// "The tank alive" in Spider.swift), in real time. A tank it knows: a
    /// table with plants either side, flowers, a dish, a log, cork bark, leaf
    /// litter, a basking stone, a lantern. Rain rolls in and it goes in under
    /// the table; drops bead on the leaves out in it (none under the table),
    /// rings spread on the dish, the floor under the table stays dry. It
    /// clears: out it comes, finds a drop on a leaf, drinks it, gets on. Snow
    /// lies only where it is open. Then creatures, let in to what draws them:
    /// a fly to the flowers, a beetle from the bark, a moth to the lantern
    /// after dark, an ant to what is left of a meal.
    private func runHabitatEcologyTest(dir: String?) {
        let restore = habitatTestSnapshot()
        var fails = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            if !ok { fails += 1 }
            print("habitat ecology: [\(ok ? "ok  " : "FAIL")] \(label) \(detail)")
            fflush(stdout)
        }
        func note(_ s: String) { print("habitat ecology: \(s)"); fflush(stdout) }
        func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
        func wait(_ secs: Double, _ test: @escaping () -> Bool, _ done: @escaping (Bool, Double) -> Void) {
            let t0 = CACurrentMediaTime()
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                let t = CACurrentMediaTime() - t0
                if test() { timer.invalidate(); done(true, t) } else if t > secs { timer.invalidate(); done(false, t) }
            }
        }
        openHabitat(restoring: true)
        guard let hc = habitat else { return }
        hc.scene.debugKeepAnimating = true
        let scene = hc.scene
        hc.weather.persists = false
        hc.weather.debugForce(.clear)
        func shot(_ name: String) { if let dir { debugShot("\(dir)/ecology_\(name).png", rect: .null, window: hc.window) } }
        let W = scene.habitat.size.width, H = scene.habitat.size.height, G = HabitatLayout.ground, cx = W / 2
        var h = Habitat(biome: .forest, world: scene.habitat.size)
        let table = h.add(.table, at: CGPoint(x: cx, y: 0))
        let leafL = h.add(.broadLeaf, at: CGPoint(x: cx - 260, y: 0))
        let leafR = h.add(.largeFern, at: CGPoint(x: cx + 300, y: 0))
        let flowers = h.add(.floweringPlant, at: CGPoint(x: cx + 640, y: 0))
        let dish = h.add(.waterDish, at: CGPoint(x: cx - 560, y: 0))
        _ = h.add(.log, at: CGPoint(x: cx - 900, y: 0))
        let bark = h.add(.corkBark, at: CGPoint(x: cx + 980, y: 0))
        _ = h.add(.leafPile, at: CGPoint(x: cx - 1180, y: 0))
        _ = h.add(.baskingStone, at: CGPoint(x: cx + 1280, y: 0))
        let lantern = h.add(.lantern, at: CGPoint(x: cx + 640, y: H))
        spider.knowledge = HabitatKnowledge()
        scene.setHabitat(h)
        let eco = scene.ecology
        let floorY = G + scene.map.standoff
        spider.placeInHabitat(map: scene.map, at: V2(cx + 150, floorY))
        scene.lookAt(V2(cx, G + 200))
        spider.debugSetUrges(thirst: 0.4, view: 0, rest: 0, roam: 0)
        // (Full up, so what it lets in stays about to be seen.)
        spider.debugFed = 0.95
        func gap(_ r: CGRect, _ p: V2) -> CGFloat { V2(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY)).length }
        func footed() -> Bool { spider.standingOn.flatMap { scene.map.worldPoint($0) }.map { $0.distance(to: spider.worldPos) < 16 } ?? false }
        var floating = 0, offFor = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] timer in
            if !inHabitat { timer.invalidate(); return }
            offFor = spider.isStanding && !footed() ? offFor + 1 : 0
            if offFor == 5 { floating += 1 }
        }
        var last = ""
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [self] timer in
            guard inHabitat else { timer.invalidate(); return }
            let line = "\(spider.debugState) | \(spider.debugErrand)"
            if line != last { note(line); last = line }
        }
        note("\(eco.debugSummary)")

        // 1. Rain rolls in.
        // (In under the table for it — or there already, and staying put.)
        func underTable() -> Bool { spider.sheltered && gap(table.rect, spider.worldPos) < 12 }
        after(3) { [self] in
            hc.weather.bring(.rain)
            wait(90, { [self] in
                spider.sheltered && spider.weather.rain > 0.3 && ((spider.debugErrandKind == "shelter" && spider.debugErrand.contains(" act ")) || underTable())
            }) { [self] ok, t in
                let pl = spider.debugErrandKind == "shelter" ? spider.debugErrandPlace : nil
                let under = underTable() || (pl.map { $0.roofOwner == table.id || $0.thing == table.id || gap(table.rect, $0.point) < 12 } ?? false)
                check("rain rolls in: in it goes, under the table", ok && under, String(format: "%.1fs, %@ (%@)", t, pl?.key ?? "-", spider.debugPlaceNote))
                wait(40, { eco.droplets.count >= 8 }) { beaded, _ in
                    let underTable = eco.droplets.filter { gap(table.rect, $0.p) < 1 }
                    check("rain beads on the leaves out in it", beaded, "\(eco.droplets.count) drops")
                    check("…none under the table", underTable.isEmpty, "\(underTable.count)")
                    check("…drawn on the leaves", scene.debugDropsDrawn(on: leafL.id) || scene.debugDropsDrawn(on: leafR.id))
                    check("rings spread on the dish in the rain", scene.debugRain(on: dish.id) > 0.3, String(format: "%.2f", scene.debugRain(on: dish.id)))
                    check("the floor under the table stays dry", scene.weatherFX.debugOpenMasked)
                    scene.lookAt(V2(table.rect.midX, G + 180))
                    after(2) { shot("1_rain") }
                    after(12) { clearing() }
                }
            }
        }
        // 2. It clears: out, a drop, on.
        func clearing() {
            hc.weather.bring(.clear)
            wait(150, { [self] in spider.debugErrandKind == "emerge" }) { [self] out, t in
                check("the rain over, out it comes", out, String(format: "%.1fs", t))
                wait(180, { [self] in spider.debugErrandKind == "dew" && spider.debugDrinking }) { [self] drank, t2 in
                    check("…finds a drop on a leaf and drinks it", drank, String(format: "%.1fs", t2))
                    if drank {
                        scene.lookAt(spider.worldPos)
                        after(0.8) { shot("2_drop") }
                    }
                    wait(60, { [self] in spider.debugErrandKind == nil }) { on, _ in
                        check("…and gets on with its life", on)
                        after(2) { snow() }
                    }
                }
            }
        }
        // 3. Snow lies only where it is open.
        func snow() {
            hc.weather.debugForce(.snow)
            scene.weatherFX.debugGround(snow: 1, wet: 0)
            scene.lookAt(V2(table.rect.midX, G + 180))
            after(5) {
                shot("3_snow")
                check("snow on the floor kept off where the table is over it", scene.weatherFX.debugOpenMasked)
                hc.weather.debugForce(.clear)
                scene.weatherFX.debugGround(snow: 0, wet: 0)
                after(2) { creatures() }
            }
        }
        // 4. Creatures, to what draws them.
        func creatures() {
            // (Full up still, so it lets them be — minutes have gone by.)
            spider.debugFed = 0.95
            let flowerBox = flowers.rect.insetBy(dx: -16, dy: -16)
            // (One the flowers drew: what else could, and sometimes does.)
            let drawn = (0..<30).compactMap { _ in eco.arrival(near: V2(flowers.rect.midX, G + 200), kind: .fruitFly) }
            guard let a = drawn.first(where: { $0.feature == .bloom }) ?? drawn.first else { check("a fly comes in", false); finish(); return }
            note("of 30 flies, the flowers drew \(drawn.filter { $0.feature == .bloom }.count)")
            let fly = spider.releaseInTank(a)
            scene.lookAt(V2(flowers.rect.midX, G + 180))
            wait(40, { fly.first.map { $0.onSurface && flowerBox.contains($0.pos.point) } ?? false }) { [self] landed, t in
                check("a fly comes in and lands on the flowers", landed, String(format: "%.1fs, from %@", t, a.feature?.rawValue ?? "nowhere"))
                if landed { after(0.5) { shot("4_fly") } }
                guard let b = eco.arrival(near: V2(bark.rect.midX, G + 100), kind: .beetle) else { check("a beetle comes in", false); finish(); return }
                let beetle = spider.releaseInTank(b).first
                check("a beetle comes out by the bark", b.anchor != nil && gap(bark.rect, b.at) < 70, "\(b.feature?.rawValue ?? "-") at \(Int(b.at.x)),\(Int(b.at.y))")
                _ = beetle
                // After dark, a moth to the lantern.
                scene.debugNight = true
                after(1) { [self] in
                    let light = V2(lantern.rect.midX, lantern.rect.minY + lantern.rect.height * 0.25)
                    let drawnIn = (0..<30).compactMap { _ in eco.arrival(near: light, kind: .moth) }
                    note("of 30 moths after dark, the lantern drew \(drawnIn.filter { $0.feature == .glow }.count)")
                    guard let m = drawnIn.first(where: { $0.feature == .glow }) ?? drawnIn.first else { check("a moth comes in", false); finish(); return }
                    let moth = spider.releaseInTank(m).first
                    scene.lookAt(light + V2(0, -120))
                    var near: Double = 0
                    wait(40, {
                        if let p = moth, p.pos.distance(to: light) < 110 { near += 0.1 }
                        return near > 6
                    }) { [self] round, t in
                        check("after dark, a moth comes to the lantern and goes round it", round, String(format: "%.1fs", t))
                        if round { shot("5_moth") }
                        scene.debugNight = nil
                        // What is left of a meal, and an ant to it.
                        let at = V2(cx - 760, G)
                        eco.leaveRemains(of: .cricket, at: at, angle: 0.2)
                        // (Of those it would draw, one the leftovers drew — as
                        // the flowers' fly and the lantern's moth above.)
                        let drawnAnts = (0..<30).compactMap { _ in eco.arrival(near: at, kind: .ant) }
                        note("of 30 ants, what was left drew \(drawnAnts.filter { $0.feature == .remains }.count)")
                        guard let rid = eco.remains.last?.id,
                              let ra = drawnAnts.first(where: { $0.feature == .remains }) ?? drawnAnts.min(by: { $0.at.distance(to: at) < $1.at.distance(to: at) }) else {
                            check("an ant comes in", false); finish(); return
                        }
                        let ants = spider.releaseInTank(ra)
                        scene.lookAt(at + V2(0, 120))
                        after(1) { check("what is left of a meal is drawn", scene.debugRemainsDrawn >= 1) }
                        wait(90, { ants.contains { $0.carrying == rid } }) { took, t in
                            check("an ant finds it, and carries it off", took, String(format: "%.1fs, %d ants, from %@", t, ants.count, ra.feature?.rawValue ?? "nowhere"))
                            if took { shot("6_ant") }
                            finish()
                        }
                    }
                }
            }
        }
        func finish() {
            check("never standing on nothing", floating == 0, "\(floating)")
            print("habitat ecology: \(fails == 0 ? "all ok" : "\(fails) FAILED")")
            finishHabitatTest(restore)
        }
    }

    /// SPIDER_HABITAT_CAMERA=1: the habitat bigger than its window, and the
    /// glass looking round it — following the spider end to end and up the
    /// glass, panned away and back, resized, decorated far from the start,
    /// fed, the spider thrown, carried out and back, the tank closed with
    /// the spider out of sight and opened again, weather while it moves, and
    /// the overview.
    private func runHabitatCameraTest() {
        let restore = habitatTestSnapshot()
        var fails = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            if !ok { fails += 1 }
            print("habitat camera: [\(ok ? "ok  " : "FAIL")] \(label) \(detail)")
            fflush(stdout)
        }
        func note(_ s: String) { print("habitat camera: \(s)"); fflush(stdout) }
        func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
        /// Runs `each` every frame for `secs`, then `done`.
        func watch(_ secs: Double, each: @escaping () -> Void, done: @escaping () -> Void) {
            let end = CACurrentMediaTime() + secs
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
                each()
                if CACurrentMediaTime() >= end { t.invalidate(); done() }
            }
        }
        for s in [CGSize(width: 1280, height: 800), CGSize(width: 1470, height: 920), CGSize(width: 1728, height: 1080), CGSize(width: 2560, height: 1415), CGSize(width: 3840, height: 2135)] {
            let w = HabitatLayout.world(for: s)
            note(String(format: "a %.0fx%.0f screen makes a %.0fx%.0f world (%.2f screens across, %.2f high)", s.width, s.height, w.width, w.height, w.width / s.width, w.height / s.height))
        }
        openHabitat(restoring: true)
        guard let hc = habitat else { return }
        hc.scene.debugKeepAnimating = true
        let scene = hc.scene
        scene.setHabitat(Habitat.preset(.forestFloor, world: scene.habitat.size))
        let W = scene.habitat.size.width, H = scene.habitat.size.height, G = HabitatLayout.ground
        let floorY = G + scene.map.standoff
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint) {
            let w = scene.convert(p, to: nil)
            guard let e = NSEvent.mouseEvent(with: type, location: w, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: hc.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            switch type {
            case .leftMouseDown: scene.mouseDown(with: e)
            case .leftMouseDragged: scene.mouseDragged(with: e)
            default: scene.mouseUp(with: e)
            }
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
        /// Stood on the open floor at `x`.
        func standAt(_ x: CGFloat) {
            spider.placeInHabitat(map: scene.map, at: V2(x, floorY))
        }
        var steps: [(Double, () -> Void)] = []
        var t: Double = 1.5
        func step(_ wait: Double, _ f: @escaping () -> Void) { steps.append((t, f)); t += wait }

        step(3) { [self] in
            note(String(format: "world %.0fx%.0f, glass %.0fx%.0f, %d things", W, H, scene.bounds.width, scene.bounds.height, scene.habitat.items.count))
            check("the world is much bigger than the glass", W > scene.bounds.width * 2.5 && H > scene.bounds.height * 1.5)
            check("in the tank", inHabitat, spider.debugState)
            standAt(W / 2)
            scene.lookAt(spider.worldPos)
            check("true scale: a point on the glass is a point in the world",
                  abs(scene.worldPoint(fromView: CGPoint(x: 100, y: 0)).x - scene.worldPoint(fromView: .zero).x - 100) < 0.01)
            check("the ground shows at the bottom of the glass", scene.groundLipOnScreen != nil)
        }
        // 1–3: the camera, following something along the tank end to end,
        // up the glass, and flung across it (the same camera, on its own,
        // with a spider that goes exactly where it is told).
        step(0.5) {
            let cam = HabitatCamera()
            cam.setWorld(CGSize(width: W, height: H))
            cam.setView(scene.bounds.size)
            var s = V2(W / 2, floorY)
            cam.jump(to: cam.centring(s))
            let dt: CGFloat = 1.0 / 60
            var frames = 0, seen = 0, moving = 0, goes = 0, wasMoving = false
            func run(until done: () -> Bool, move: () -> Void) {
                var n = 0
                while !done() && n < 60 * 120 {
                    move()
                    let before = cam.origin
                    cam.update(dt: dt, spider: s, follows: true)
                    let m = (cam.origin - before).length > 0.05
                    frames += 1; n += 1
                    if cam.visible.insetBy(dx: -10, dy: -10).contains(s.point) { seen += 1 }
                    if m { moving += 1 }
                    if m && !wasMoving { goes += 1 }
                    wasMoving = m
                }
            }
            // Along the floor at a walk, stopping now and then.
            var pause = 0
            run(until: { s.x <= 60 }, move: {
                pause = (pause + 1) % 400
                if pause < 300 { s.x -= 95 * dt }
            })
            let along = (frames, seen, moving, goes, cam.origin)
            note(String(format: "along the tank: in sight %d/%d frames, camera moving %d frames in %d goes, ends at %.0f,%.0f", along.0, along.1, along.2, along.3, along.4.x, along.4.y))
            check("followed end to end, it is always in sight", along.1 == along.0)
            check("the camera ends at the end of the tank, not past it", along.4.x == 0)
            check("the camera goes in easy stretches, and is still in between", along.2 < along.0 * 3 / 4 && along.3 >= 3, "\(along.2)/\(along.0) in \(along.3)")
            // Up the glass to near the lid.
            frames = 0; seen = 0; moving = 0; goes = 0
            run(until: { s.y >= H - 60 }, move: { s = V2(22, s.y + 70 * dt) })
            note(String(format: "up the glass: in sight %d/%d, camera at %.0f,%.0f", seen, frames, cam.origin.x, cam.origin.y))
            check("up the glass, the camera goes up with it, to the top", seen == frames && abs(cam.origin.y - (H - scene.bounds.height)) < 6,
                  String(format: "%.0f of %.0f", cam.origin.y, H - scene.bounds.height))
            // Flung across the tank: it catches up and settles.
            s = V2(W * 0.6, H * 0.5)
            var n = 0
            frames = 0; seen = 0
            run(until: { n += 1; return n > 150 }, move: {})
            let caught = cam.visible.contains(s.point)
            check("flung across, the camera catches up within a few seconds", caught, String(format: "at %.0f,%.0f", cam.origin.x, cam.origin.y))
            // Resting in the middle, jiggling about a little: no stirring.
            n = 0
            run(until: { n += 1; return n > 300 }, move: {})
            let still = cam.origin
            s = V2(cam.visible.midX, cam.visible.midY)
            n = 0
            run(until: { n += 1; return n > 300 }, move: { s = V2(cam.visible.midX + sin(CGFloat(n) * 0.2) * 60, cam.visible.midY + cos(CGFloat(n) * 0.13) * 40) })
            check("pottering about in the middle, the camera doesn't stir", (cam.origin - still).length < 1)
        }
        // And the real spider, walking about for a while (smoke test).
        step(22) { [self] in
            standAt(W / 2)
            scene.lookAt(spider.worldPos)
            var frames = 0, seen = 0
            var summoned: CFTimeInterval = 0
            watch(21, each: {
                frames += 1
                let now = CACurrentMediaTime()
                if now - summoned > 2 { summoned = now; self.spider.summon(to: V2(self.spider.worldPos.x - 300, floorY)) }
                if scene.isInView(self.spider.worldPos, margin: -10) { seen += 1 }
            }, done: {
                note(String(format: "the spider wandered to %.0f,%.0f (%@), in sight %d/%d, camera at %.0f,%.0f",
                            self.spider.worldPos.x, self.spider.worldPos.y, self.spider.debugState, seen, frames, scene.camera.origin.x, scene.camera.origin.y))
                check("the real spider, followed, stays in sight", CGFloat(seen) >= CGFloat(frames) * 0.97)
            })
        }
        // 4–5: panned away; it carries on out of sight; the find button.
        step(6) { [self] in
            standAt(W * 0.3)
            scene.lookAt(spider.worldPos)
            after(0.5) {
                let from = scene.camera.origin
                scene.camera.pan(by: V2(1600, 300))
                let panned = scene.camera.origin
                let at = self.spider.worldPos
                var moved: CGFloat = 0
                watch(5, each: { moved = max(moved, self.spider.worldPos.distance(to: at)) }, done: {
                    check("panned away, the camera stays where it was put", (scene.camera.origin - panned).length < 1 && (panned - from).length > 500,
                          String(format: "%.0f,%.0f", scene.camera.origin.x, scene.camera.origin.y))
                    check("out of sight, it carries on as it was", self.inHabitat, String(format: "moved %.0f, %@", moved, self.spider.debugState))
                    check("the find button shows the way", scene.debugFindShown)
                })
            }
        }
        // 6: found.
        step(4) {
            scene.findSpider()
            after(3.5) { [self] in
                check("found: back on it, gliding, and following again", scene.isInView(spider.worldPos, margin: 10)
                      && (scene.camera.mode == .follow || scene.camera.mode == .glide(thenFollow: true)),
                      String(format: "camera %.0f,%.0f spider %.0f,%.0f", scene.camera.origin.x, scene.camera.origin.y, spider.worldPos.x, spider.worldPos.y))
                check("the find button goes", !scene.debugFindShown)
            }
        }
        // 7: resized.
        step(1.5) {
            let was = scene.bounds.size
            let size = hc.windowWillResize(hc.window, to: CGSize(width: hc.window.frame.width + 260, height: hc.window.frame.height + 90))
            hc.window.setFrame(CGRect(origin: hc.window.frame.origin, size: size), display: true)
            after(0.8) {
                check("resized: the glass shows more of the world, same scale", scene.visibleWorld.size == scene.bounds.size && scene.bounds.width > was.width + 100,
                      String(format: "%.0fx%.0f -> %.0fx%.0f", was.width, was.height, scene.bounds.width, scene.bounds.height))
            }
        }
        // 8: something added with the glass far along the tank.
        step(1.5) { [self] in
            scene.lookAt(V2(W - 300, 300))
            let count = scene.habitat.items.count
            scene.add(.rock)
            let it = scene.habitat.items.last!
            check("added where the glass is looking", scene.habitat.items.count == count + 1 && scene.visibleWorld.insetBy(dx: -30, dy: -60).contains(CGPoint(x: it.x, y: it.rect.midY)),
                  String(format: "rock at %.0f, glass %.0f…%.0f", it.x, scene.visibleWorld.minX, scene.visibleWorld.maxX))
            hc.undo()
            _ = spider
        }
        // 9: dragged by hand with the glass far along (in decorating).
        step(2.5) {
            if !hc.decorating { hc.toggleDecorate() }
            after(0.6) {
                guard let it = scene.habitat.items.filter({ $0.kind == .log || $0.kind == .rock || $0.kind == .boulder })
                        .min(by: { abs($0.x - scene.visibleWorld.midX) < abs($1.x - scene.visibleWorld.midX) }) else { check("something to drag", false); return }
                scene.lookAt(V2(it.x, it.rect.midY + 100))
                let c = scene.viewPoint(fromWorld: V2(it.x, it.rect.midY))
                drag(c, CGPoint(x: c.x - 90, y: c.y), steps: 12) {
                    let moved = scene.habitat.items.first { $0.id == it.id }!
                    check("dragged with the glass along the tank, one to one", abs(moved.x - (it.x - 90)) < 3 || abs(moved.x - it.x) > 60,
                          String(format: "%.0f -> %.0f (glass at %.0f)", it.x, moved.x, scene.camera.origin.x))
                    hc.undo()
                    hc.toggleDecorate()
                }
            }
        }
        // 10–11: a layout, and a surprise.
        step(2) { [self] in
            hc.loadPreset(.jungleCanopy)
            let h = scene.habitat
            check("a layout fills the tank end to end", (h.items.map(\.x).min() ?? W) < W * 0.2 && (h.items.map(\.x).max() ?? 0) > W * 0.8, "\(h.items.count) things")
            check("things up in the air to climb to", h.items.contains { $0.kind == .branch && $0.y > H * 0.4 })
            check("it is still in the tank, on something", inHabitat, spider.debugState)
            hc.shuffle()
            let s = scene.habitat
            check("surprise: spread across the tank", (s.items.map(\.x).min() ?? W) < W * 0.25 && (s.items.map(\.x).max() ?? 0) > W * 0.75, "\(s.items.count) things, \(s.biome)")
            note("regions: " + s.regions.map { "\($0.kind.rawValue)@\(Int($0.rect.minX))" }.joined(separator: " "))
            hc.loadPreset(.forestFloor)
        }
        // 12–13: fed with the glass along from it; hunting across the glass's edge.
        step(26) { [self] in
            standAt(W * 0.35)
            scene.lookAt(spider.worldPos + V2(scene.bounds.width * 0.3, 0))
            after(0.3) {
                self.release(.fruitFly)
                self.release(.cricket)
                let loose = self.spider.prey
                check("let loose where the glass is looking", loose.count >= 2 && loose.allSatisfy { scene.visibleWorld.insetBy(dx: -120, dy: -200).contains($0.pos.point) },
                      loose.map { String(format: "%.0f,%.0f", $0.pos.x, $0.pos.y) }.joined(separator: " "))
                var outOfSight = 0
                watch(24, each: { if !scene.isInView(self.spider.worldPos) { outOfSight += 1 } }, done: {
                    note("after 24 s: \(self.spider.prey.count) of 2 still loose, spider \(self.spider.debugState), out of sight \(outOfSight) frames, camera \(scene.camera.mode)")
                    check("hunting, the camera keeps it in sight", outOfSight < 60)
                })
            }
        }
        // 14: picked up and thrown with the glass along the tank.
        step(4) { [self] in
            scene.findSpider()
            after(1.8) {
                let at = scene.viewPoint(fromWorld: self.spider.worldPos)
                check("the glass along the tank", scene.camera.origin.x > 50, String(format: "%.0f", scene.camera.origin.x))
                drag(at, CGPoint(x: min(at.x + 160, scene.bounds.width - 60), y: min(at.y + 150, scene.bounds.height - 60)), steps: 6) {
                    check("thrown, it flies in the tank", self.inHabitat && (self.spider.isAirborne || self.spider.isStanding), self.spider.debugState)
                    after(1.8) {
                        check("thrown, it lands in the tank", self.inHabitat && scene.habitat.bounds.insetBy(dx: -10, dy: -10).contains(self.spider.worldPos.point), self.spider.debugState)
                    }
                }
            }
        }
        // 15–16: carried out through the glass, and back in.
        step(2) { [self] in
            // (Down on the floor again after being thrown, the glass on it.)
            standAt(scene.visibleWorld.midX)
            scene.findSpider()
        }
        step(3) { [self] in
            let at = scene.viewPoint(fromWorld: spider.worldPos)
            let out = CGPoint(x: -220, y: at.y)
            drag(at, out, steps: 30) {
                let pointer = V2(scene.glassOnScreen.minX + out.x, scene.glassOnScreen.minY + out.y)
                check("carried out: on the desktop", !self.inHabitat && !self.spider.inHabitat, self.spider.debugState)
                check("carried out: where the pointer is, on the screen", self.spider.worldPos.distance(to: pointer) < 60,
                      String(format: "%.0f,%.0f vs %.0f,%.0f", self.spider.worldPos.x, self.spider.worldPos.y, pointer.x, pointer.y))
                after(0.4) {
                    let mid = V2(scene.glassOnScreen.midX, scene.glassOnScreen.midY)
                    self.spider.beginGrab(at: self.spider.worldPos)
                    self.spider.moveGrab(to: mid)
                    after(2.0) {
                        self.updateCarrying()
                        let want = scene.worldPoint(fromScreen: mid)
                        check("dropped back in: in the tank's world where it was let go", self.inHabitat && self.spider.worldPos.distance(to: want) < 60,
                              String(format: "%.0f,%.0f vs %.0f,%.0f", self.spider.worldPos.x, self.spider.worldPos.y, want.x, want.y))
                        self.spider.endGrab(throwVelocity: .zero)
                    }
                }
            }
        }
        // 17: closed with it out of sight: the glass goes to it, then it drops.
        step(6) { [self] in
            standAt(W * 0.2)
            after(1.2) {
                scene.camera.pan(by: V2(W * 0.5, 0))
                after(0.2) {
                    check("out of sight before closing", !scene.isInView(self.spider.worldPos))
                    self.closeHabitat()
                    check("closing waits for the glass to get to it", self.tankOpen && self.inHabitat)
                    var dropped: V2?
                    var glass = CGRect.zero
                    watch(3.5, each: {
                        if dropped == nil, !self.inHabitat { dropped = self.spider.worldPos; glass = scene.glassOnScreen }
                    }, done: {
                        check("closed, it dropped from where it could be seen", dropped.map { glass.insetBy(dx: -30, dy: -30).contains($0.point) } ?? false,
                              dropped.map { String(format: "%.0f,%.0f in %@", $0.x, $0.y, NSStringFromRect(glass)) } ?? "never")
                        check("closed", !self.tankOpen)
                    })
                }
            }
        }
        // 19: open again with it put back where it was.
        step(4) { [self] in
            let saved = (UserDefaults.standard.array(forKey: AppDelegate.tankSpiderKey) as? [Double]) ?? []
            openHabitat(restoring: true)
            after(1) {
                let want = saved.count == 2 ? V2(CGFloat(saved[0]), CGFloat(saved[1])) : .zero
                check("opened again: back where it was, and the glass on it", self.inHabitat && self.spider.worldPos.distance(to: want) < 120 && scene.isInView(self.spider.worldPos),
                      String(format: "%.0f,%.0f (was %.0f,%.0f)", self.spider.worldPos.x, self.spider.worldPos.y, want.x, want.y))
            }
        }
        // 18: weather while the glass moves.
        step(7) {
            hc.weather.persists = false
            hc.weather.debugForce(.snow)
            after(2) {
                scene.camera.glide(toCentre: V2(W * 0.8, H * 0.6), thenFollow: false)
                after(2.5) {
                    hc.weather.debugForce(.storm)
                    scene.weatherFX.strike(near: true)
                    after(1.5) {
                        check("weather while the glass moves along and up", scene.camera.origin.x > W * 0.5, String(format: "%.0f,%.0f", scene.camera.origin.x, scene.camera.origin.y))
                        hc.weather.debugForce(.clear)
                    }
                }
            }
        }
        // 20: the overview.
        step(4) { [self] in
            scene.showOverview(true)
            after(0.5) {
                check("the overview opens", scene.overviewOpen)
                guard let o = scene.overview else { return }
                let goal = V2(W * 0.15, 200)
                let p = o.debugViewPoint(for: goal)
                o.debugClick(at: p)
                after(2.8) {
                    check("a click in it takes the glass there, life size", !scene.overviewOpen && scene.visibleWorld.insetBy(dx: -40, dy: -40).contains(goal.point),
                          String(format: "glass %.0f…%.0f", scene.visibleWorld.minX, scene.visibleWorld.maxX))
                    let hidden = scene.debugItemLayers.values.filter(\.isHidden).count
                    check("what is well out of sight is left out", hidden > 0, "\(hidden) of \(scene.debugItemLayers.count) hidden")
                    _ = self.spider
                }
            }
        }
        step(1) { [self] in
            closeHabitat(animated: false)
            print("habitat camera: \(fails == 0 ? "all passed" : "\(fails) FAILED")")
            after(0.5) { self.finishHabitatTest(restore) }
        }
        for (at, f) in steps { after(at, f) }
    }

    private func runWeatherShots(dir: String) {
        let restore = habitatTestSnapshot()
        let env = ProcessInfo.processInfo.environment
        openHabitat(restoring: true)
        guard let hc = habitat else { return }
        hc.weather.persists = false
        hc.scene.debugKeepAnimating = true
        hc.scene.setAnimating(true)
        let kinds = env["SPIDER_WEATHER_KINDS"].map { $0.split(separator: ",").compactMap { WeatherKind(rawValue: String($0)) } } ?? WeatherKind.allCases
        let biomes = env["SPIDER_WEATHER_BIOMES"].map { $0.split(separator: ",").compactMap { Biome(rawValue: String($0)) } } ?? [hc.scene.habitat.biome]
        var queue = biomes.flatMap { b in kinds.map { (b, $0) } }
        let settle = Double(env["SPIDER_WEATHER_SETTLE"] ?? "") ?? 5
        func after(_ secs: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: f) }
        func next() {
            guard !queue.isEmpty else { self.finishHabitatTest(restore); return }
            let (b, k) = queue.removeFirst()
            if hc.scene.habitat.biome != b {
                var h = hc.scene.habitat
                h.biome = b
                hc.scene.setHabitat(h)
            }
            hc.weather.debugForce(k)
            let m = k.recipe
            hc.scene.weatherFX.debugGround(snow: m.snow > 0 ? 1 : 0, wet: m.rain > 0 ? 1 : 0)
            self.spider.debugWeatherOn(wet: m.rain > 0 ? 0.85 : 0, snow: m.snow > 0 ? 0.8 : 0, dust: m.sand > 0 ? 0.7 : 0)
            after(settle) {
                if m.lightning > 0.5 { hc.scene.weatherFX.strike(near: true) }
                after(m.lightning > 0.5 ? 0.08 : 0) {
                    print("weather shot: \(b.rawValue) \(k.rawValue) — \(self.spider.debugState) — \(self.spider.debugWeather)")
                    self.debugShot("\(dir)/weather_\(b.rawValue)_\(k.rawValue).png", rect: .zero, window: hc.window)
                    // And a close look at the spider.
                    let f = hc.window.frame, p = hc.scene.screenPoint(fromWorld: self.spider.worldPos)
                    self.debugShot("\(dir)/weather_\(b.rawValue)_\(k.rawValue)_spider.png", rect: .zero, window: hc.window,
                                   crop: CGRect(x: p.x - f.minX - 70, y: f.maxY - p.y - 70, width: 140, height: 140))
                    next()
                }
            }
        }
        after(2) { next() }
    }

    /// SPIDER_HABITAT_SHOT=dir: pictures of the tank in every layout —
    /// looking at the middle, along at one end, and up at the top —
    /// the overview, and the decorating panel's tabs. (SPIDER_HABITAT_SHOT_ONLY
    /// = a layout's name, to take just that one.)
    private func runHabitatTourTest(dir: String) {
        let restore = habitatTestSnapshot()
        // (Never the user's own saved habitats.)
        if ProcessInfo.processInfo.environment["SPIDER_HABITAT_LIBRARY"] == nil {
            HabitatLibrary.folder = URL(fileURLWithPath: dir).appendingPathComponent("library", isDirectory: true)
        }
        try? FileManager.default.removeItem(at: HabitatLibrary.folder)
        for k in [HabitatTour.seenKey, HabitatTour.decoratingSeenKey, HabitatController.currentSaveKey] { UserDefaults.standard.removeObject(forKey: k) }
        var fails = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            if !ok { fails += 1 }
            print("habitat tour: [\(ok ? "ok" : "FAIL")] \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            fflush(stdout)
        }
        func after(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }
        /// A picture of the tank with whatever is over it (the tour, a popover).
        func shot(_ name: String, _ windows: [NSWindow]) {
            // (Front to back: whatever is over the tank first.)
            var ptrs = windows.reversed().filter { $0.isVisible }.map { UnsafeRawPointer(bitPattern: UInt($0.windowNumber)) }
            guard let arr = CFArrayCreate(nil, &ptrs, ptrs.count, nil),
                  let img = CGImage(windowListFromArrayScreenBounds: .null, windowArray: arr, imageOption: [.boundsIgnoreFraming, .bestResolution]) else { return }
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
        openHabitat(restoring: true)
        after(2.2) { [self] in
            guard let hc = habitat else { return }
            hc.scene.debugKeepAnimating = true
            hc.scene.setAnimating(true)
            hc.scene.setHabitat(Habitat.preset(.forestFloor, world: hc.scene.habitat.size))
            hc.startTour(.tank)
            guard let tour = hc.tour else { check("the tank's tour starts", false); finishHabitatTest(restore); return }
            func tankStep(_ i: Int) {
                guard i < tour.stepCount else {
                    tour.finish()
                    after(0.5) {
                        check("the tank's tour ends, and is remembered", hc.tour == nil && HabitatTour.seen(.tank))
                        weatherShots()
                    }
                    return
                }
                tour.debugShow(i)
                after(0.5) { shot("tour_tank_\(i)", [hc.window, tour.overlayWindow]); tankStep(i + 1) }
            }
            func weatherShots() {
                hc.showWeatherPanel()
                after(0.8) {
                    shot("weather_panel", [hc.window] + (hc.weatherPopoverWindow.map { [$0] } ?? []))
                    hc.showWeatherPanel()
                    after(0.4) { decorate() }
                }
            }
            func decorate() {
                hc.toggleDecorate()
                after(1.2) {
                    guard let dt = hc.tour, dt.kind == .decorating else { check("decorating's tour starts the first time", false); saving(); return }
                    check("decorating's tour starts the first time", true)
                    func step(_ i: Int) {
                        guard i < dt.stepCount else {
                            dt.finish()
                            after(0.5) {
                                check("decorating's tour ends, and is remembered", hc.tour == nil && HabitatTour.seen(.decorating))
                                saving()
                            }
                            return
                        }
                        dt.debugShow(i)
                        after(0.5) { shot("tour_decorate_\(i)", [hc.window, dt.overlayWindow]); step(i + 1) }
                    }
                    step(0)
                }
            }
            func saving() {
                let world = hc.scene.habitat.size
                let forest = hc.scene.habitat
                check("nothing saved to begin with", HabitatLibrary.all().isEmpty)
                let a = SavedHabitat(name: "Test Forest", habitat: forest)
                check("saved", HabitatLibrary.store(a) && HabitatLibrary.all().count == 1)
                hc.currentSaveID = a.id
                check("in the tank, unchanged", hc.currentSaved?.changed == false)
                hc.loadPreset(.desertScrub)
                check("a ready-made layout isn't the saved one", hc.currentSaved == nil)
                var b = SavedHabitat(name: "Test Desert", habitat: hc.scene.habitat)
                b.saved = Date(timeIntervalSinceNow: -86400 * 3)
                HabitatLibrary.store(b)
                hc.loadSaved(id: a.id)
                check("put back in the tank, just as it was", hc.scene.habitat == forest && hc.currentSaved?.changed == false)
                hc.scene.select(hc.scene.habitat.items.first?.id)
                hc.scene.updateSelected { $0.x += 50 }
                check("moving something changes it", hc.currentSaved?.changed == true)
                hc.undo()
                check("undone, it is the saved one again", hc.currentSaved?.changed == false)
                hc.scene.updateSelected { $0.x += 50 }
                hc.saveHabitatAction()
                check("Save keeps the changes in it", hc.currentSaved?.changed == false && HabitatLibrary.saved(id: a.id)?.habitat == hc.scene.habitat)
                hc.undo()
                // One saved in a smaller world stands in the middle of this one.
                var small = forest
                small.world = CGSize(width: world.width - 400, height: world.height)
                small.items = small.items.map { var it = $0; it.x = max(it.x - 200, it.w); return it }
                let c = SavedHabitat(name: "Smaller", habitat: small)
                HabitatLibrary.store(c)
                let fitted = c.habitat(for: world)
                check("a habitat from a smaller world fits this one", fitted.size == world
                      && fitted.items.allSatisfy { $0.x >= 0 && $0.x <= world.width && $0.y >= 0 && $0.y <= world.height }
                      && abs((fitted.items.first?.x ?? 0) - ((small.items.first?.x ?? 0) + 200)) < 1)
                // Shared as a file and brought back in.
                let file = URL(fileURLWithPath: dir).appendingPathComponent("shared.\(HabitatLibrary.fileExtension)")
                do {
                    try HabitatLibrary.export(b, to: file)
                    let back = try HabitatLibrary.importFile(file)
                    check("shared and brought back in", back.id != b.id && back.habitat == b.habitat && back.name == "Test Desert 2", back.name)
                    HabitatLibrary.delete(id: back.id)
                } catch {
                    check("shared and brought back in", false, "\(error)")
                }
                HabitatLibrary.delete(id: c.id)
                check("deleted", HabitatLibrary.all().count == 2)
                hc.loadSaved(id: a.id)
                hc.decorPanelIfBuilt?.showTab(.habitats)
                after(1.2) {
                    shot("habitats_tab", [hc.window])
                    hc.scene.select(hc.scene.habitat.items.first { $0.kind == .log }?.id)
                    hc.decorPanelIfBuilt?.showTab(.add)
                    after(0.8) {
                        shot("add_tab_selected", [hc.window])
                        hc.toggleDecorate()
                        after(0.6) {
                            let w = hc.window.frame
                            let sz = hc.windowWillResize(hc.window, to: CGSize(width: 700, height: w.height))
                            hc.window.setFrame(CGRect(origin: w.origin, size: sz), display: true)
                            after(0.6) {
                                shot("narrow", [hc.window])
                                hc.window.setFrame(CGRect(origin: w.origin, size: hc.windowWillResize(hc.window, to: w.size)), display: true)
                                print("habitat tour: \(fails == 0 ? "all ok" : "\(fails) failed")")
                                try? FileManager.default.removeItem(at: HabitatLibrary.folder)
                                self.finishHabitatTest(restore)
                            }
                        }
                    }
                }
            }
            tankStep(0)
        }
    }

    private func runHabitatShots(dir: String) {
        let restore = habitatTestSnapshot()
        openHabitat(restoring: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            guard let hc = habitat else { return }
            hc.scene.debugKeepAnimating = true
            hc.scene.setAnimating(true)
            let world = hc.scene.habitat.size
            var presets = Habitat.Preset.allCases
            if let only = ProcessInfo.processInfo.environment["SPIDER_HABITAT_SHOT_ONLY"] { presets = presets.filter { $0.rawValue == only } }
            func shot(_ name: String) { self.debugShot("\(dir)/\(name).png", rect: .zero, window: hc.window) }
            func after(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }
            // The Add page: a shelf, a search, what suits the scenery; then
            // close to some of the natural world's parts.
            func addPageShots() {
                let steps: [(String, () -> Void)] = [
                    ("add_shelter", { hc.debugShowShelf(.shelter) }), ("add_plants", { hc.debugShowShelf(.plants) }),
                    ("add_details", { hc.debugShowShelf(.details) }), ("add_search", { hc.debugSearch("mushroom") }),
                    ("add_suits", { hc.debugSearch(""); hc.debugShowShelf(nil); hc.debugSuits(true) }),
                ]
                func step(_ i: Int) {
                    guard i < steps.count else { hc.debugSuits(false); closeUps(); return }
                    steps[i].1()
                    after(0.6) { shot("habitat_\(steps[i].0)"); step(i + 1) }
                }
                step(0)
            }
            func closeUps() {
                hc.scene.select(nil)
                let kinds: [HabitatItemKind] = [.lookout, .largeFern, .logDen, .barkCave, .waterDish, .rootHollow, .threeFork]
                let spots = kinds.compactMap { k in hc.scene.habitat.items.first { $0.kind == k }.map { (k, $0) } }
                func look(_ i: Int) {
                    guard i < spots.count else { self.finishHabitatTest(restore); return }
                    let it = spots[i].1
                    hc.scene.lookAt(V2(it.x, it.rect.minY + hc.scene.visibleWorld.height * 0.3))
                    after(0.9) { shot("habitat_near_\(spots[i].0.rawValue)"); look(i + 1) }
                }
                after(1) { look(0) }
            }
            func next() {
                guard let p = presets.first else {
                    hc.scene.setHabitat(Habitat.preset(.forestFloor, world: world))
                    hc.toggleDecorate()
                    after(1.2) {
                        let log = hc.scene.habitat.items.last { $0.kind == .log }
                        if let log { hc.scene.lookAt(V2(log.x, log.rect.midY + 150)) }
                        hc.scene.select(log?.id)
                        after(0.4) { shot("habitat_decorating") }
                        after(0.8) {
                            hc.scene.showOverview(true)
                            after(0.6) {
                                shot("habitat_overview_decorating")
                                hc.scene.showOverview(false)
                            }
                        }
                        for tab in 1...2 {
                            after(1.8 + Double(tab) * 0.8) {
                                hc.debugShowTab(tab)
                                after(0.5) {
                                    shot("habitat_decorating_tab\(tab)")
                                    if tab == 2 { addPageShots() }
                                }
                            }
                        }
                    }
                    return
                }
                presets.removeFirst()
                hc.scene.setHabitat(Habitat.preset(p, world: world))
                self.spider.placeInHabitat(map: hc.scene.map, at: V2(world.width / 2, HabitatLayout.ground + 30))
                hc.scene.lookAt(V2(world.width / 2, 0))
                after(2.5) {
                    shot("habitat_\(p.rawValue)")
                    hc.scene.lookAt(V2(0, 0))
                    after(0.8) {
                        shot("habitat_\(p.rawValue)_end")
                        hc.scene.lookAt(V2(world.width * 0.7, world.height))
                        after(0.8) {
                            shot("habitat_\(p.rawValue)_high")
                            hc.scene.showOverview(true)
                            after(0.6) {
                                shot("habitat_\(p.rawValue)_overview")
                                hc.scene.showOverview(false)
                                after(0.3) { next() }
                            }
                        }
                    }
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
    // gets played with now and then. Put Away puts it away; so does a
    // right-click or Esc while it is on the pointer, or a right-click on it
    // once it is down.

    private enum HandToy: Equatable { case laser, toy(ToyKind) }
    private var handToy: HandToy?
    private var laserOn: Bool { handToy == .laser }
    /// A ball, bell or bug is in your hand, waiting to be put down.
    private var holdingToy = false
    private var toyDrag: [(p: V2, t: TimeInterval)] = []
    /// Something is on the pointer — the dot, the feather on its string, a
    /// toy in hand — and the pointer is for playing with it.
    private var onPointer: Bool {
        switch handToy {
        case .laser?: return !inHabitat
        case .toy(let kind)?: return kind.tether > 0 ? !toyBox.isEmpty : holdingToy
        case nil: return false
        }
    }
    /// Rides under the pointer while something is on it, to take the clicks:
    /// a click puts a toy in hand down, a right-click puts it all away.
    private lazy var handWindow: OverlayWindow = {
        let w = OverlayWindow(frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        w.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        let v = HandCatchView(frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        v.onDown = { [weak self] e in self?.handDown(e) }
        v.onDrag = { [weak self] e in self?.handDrag(e) }
        v.onUp = { [weak self] e in self?.handUp(e) }
        v.onRight = { [weak self] in self?.putAway() }
        w.contentView = v
        w.ignoresMouseEvents = false
        return w
    }()
    /// Esc, taken from whatever app is in front only while something is on
    /// the pointer. (A hot key needs no permission to watch the keyboard.)
    private var escapeKey: EventHotKeyRef?
    private var escapeHandler: EventHandlerRef?

    private func catchEscape(_ on: Bool) {
        guard on != (escapeKey != nil) else { return }
        if let k = escapeKey {
            UnregisterEventHotKey(k)
            escapeKey = nil
            return
        }
        if escapeHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, me in
                guard let me else { return noErr }
                let app = Unmanaged<AppDelegate>.fromOpaque(me).takeUnretainedValue()
                DispatchQueue.main.async { if app.onPointer { app.putAway() } }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &escapeHandler)
        }
        RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: OSType(0x53504452), id: 1),
                            GetApplicationEventTarget(), 0, &escapeKey)
    }

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
        catchEscape(false)
        refreshMenu()
    }

    private func takeInHand(_ toy: Toy) {
        toy.grab(at: V2(NSEvent.mouseLocation))
        holdingToy = true
        toyDrag = []
        refreshMenu()
    }

    /// Every frame: the dot and the toy with the pointer, and the catcher
    /// under it while something is on it.
    private func updateHand() {
        let p = V2(NSEvent.mouseLocation)
        switch handToy {
        case .laser?:
            // Not in the tank: the dot is a desktop game.
            if inHabitat {
                if spider.laser != nil { spider.laser = nil; laserWindow.orderOut(nil) }
                break
            }
            laserWindow.setFrameOrigin(CGPoint(x: p.x - 18, y: p.y - 18))
            if !laserWindow.isVisible { laserWindow.orderFrontRegardless() }
            laserView.phase += 0.016
            // Visitors go for the dot too — except one on its way out.
            spider.laser = p
            for v in visitors where !v.leaving { v.spider.laser = p }
        case .toy?:
            guard let toy = toyBox.toys.first else { break }
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
        let playing = onPointer
        catchEscape(playing)
        // The spider (or a visitor) under the dot or the feather can still
        // be picked up; a toy in hand is put down on it.
        let overSpider = !holdingToy && interactive && allSpiders.contains { $0.isHeld || $0.hitTest(p) }
        if playing, !overSpider {
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
        guard holdingToy else { return }
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
        let f = inHabitat ? (habitat?.scene.visibleWorld ?? worldFrame()) : spider.confine ?? NSScreen.main?.frame ?? worldFrame()
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
        spider.knowledge = knowledge
        map.standoff = AppDelegate.standoff(for: spider.config.scale)
        map.rebuild(windows: [], docks: map.dockRects)
        view.spider = spider
        spider.toys = toyBox
        spider.traces = traces
        traces.clear()
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
        pageWatch.scale = spider.config.scale
        pageWatch.standoff = map.standoff
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
                self.studioVisible = shown
                self.updateDockPresence()
                // The last page of the welcome: done designing, out it comes.
                if !shown, self.awaitingEntrance { self.finishWelcome() }
            }
            studio = st
        }
        studio?.scale = spider.config.scale
        studio?.show()
    }

    // MARK: - Bug reports

    @objc private func reportBug() {
        panel?.close()
        if bugReport == nil {
            let c = BugReportController(look: spider.design.look,
                                        spiderName: spider.name.isEmpty ? "Your spider" : spider.name,
                                        systemInfo: { [weak self] in SystemReport.lines(extra: self?.reportDetails() ?? []) })
            c.onClose = { [weak self] in self?.bugReport = nil }
            bugReport = c
        }
        bugReport?.show()
    }

    /// What the spider and the app were up to, for a bug report.
    private func reportDetails() -> [(String, String)] {
        let on = { (b: Bool) in b ? "On" : "Off" }
        var doing = spider.debugState
        if hidden { doing += ", hidden" }
        if spider.config.paused { doing += ", paused" }
        if tankOpen { doing += ", in its habitat" }
        return [
            ("Spider", doing),
            ("Size", String(format: "%.2f×", Double(spider.config.scale))),
            ("Its Low Power Mode", on(lowPower)),
            ("Visitors", visitorsOn ? "\(visitors.count) about" : "Off"),
            ("Notice the Weather", on(feelsWeather)),
        ]
    }

    // MARK: - Welcome

    /// The welcome tour: a hello, where its panel lives, a few house rules,
    /// and the Studio — and then the spider makes its grand entrance from
    /// its menu bar icon (`Spider.makeEntrance`). Shown once, the first time
    /// the app is opened; the App page can replay it.
    @objc private func startWelcome() {
        guard welcome == nil, !awaitingEntrance else { welcome?.show(); return }
        if tankOpen { closeHabitat(animated: false) }
        panel?.close()
        // The panel as it will be once the spider is out — shown, not
        // paused — for the picture of it, light and dark; drawn before the
        // tour puts the spider away. (Each picture takes a panel of its own:
        // picturing one uses it up.)
        let wasHidden = hidden
        hidden = false
        var pictures: [Bool: NSImage] = [:]
        for dark in [false, true] {
            let p = PanelController(pages: panelPages(generic: true), footer: panelFooter(), design: { [weak self] in
                var d = self?.spider.design ?? SpiderDesign()
                d.name = ""
                return d
            })
            if let rep = p.picture(page: 0, dark: dark) {
                let img = NSImage(size: rep.size)
                img.addRepresentation(rep)
                pictures[dark] = img
            }
        }
        hidden = wasHidden
        awaitingEntrance = true
        pausedBeforeWelcome = spider.config.paused
        spider.config.paused = true
        window.orderOut(nil)
        for v in visitors { removeVisitor(v) }
        silkWindow.orderOut(nil)
        silkVisible = false
        hammockWindow.orderOut(nil)
        let w = OnboardingController(design: spider.design, panelPicture: { pictures[$0] }, choices: welcomeChoices())
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

    /// The house rules the welcome asks about: the settings that most
    /// change what having it about is like.
    private func welcomeChoices() -> [WelcomeChoice] {
        [
            WelcomeChoice(title: "Wandering Bugs", detail: "Now and then a moth, a beetle or a trail of ants wanders in for it to hunt.",
                          symbol: "ladybug", get: { [unowned self] in wildOn },
                          set: { [unowned self] on in if on != wildOn { toggleWildlife() } }),
            WelcomeChoice(title: "Visiting Spiders", detail: "Other spiders drop by to play for a while, then head off again.",
                          symbol: "person.2", note: "More spiders on screen use more battery.",
                          get: { [unowned self] in visitorsOn }, set: { [unowned self] on in setVisitors(on, ask: false) }),
            WelcomeChoice(title: "Traces", detail: "It leaves silk strands, little webs and leftovers about. They fade on their own.",
                          symbol: "scribble.variable", get: { [unowned self] in leavesTraces },
                          set: { [unowned self] on in setLeavesTraces(on) }),
            WelcomeChoice(title: "Learns as It Goes", detail: "Its personality drifts a little with how you treat it and how its days go.",
                          symbol: "sparkles", get: { [unowned self] in learns },
                          set: { [unowned self] on in if on != learns { toggleLearning() } }),
            WelcomeChoice(title: "Notices the Weather", detail: "When it rains where you are, it knows. Checks online, by your rough location.",
                          symbol: "cloud.rain", get: { [unowned self] in feelsWeather },
                          set: { [unowned self] on in if on != feelsWeather { toggleFeelWeather() } }),
            WelcomeChoice(title: "Open at Login", detail: "It's there waiting for you every time you log in.",
                          symbol: "power", get: { [unowned self] in loginEnabled },
                          set: { [unowned self] on in if on != loginEnabled { toggleLogin() } }),
        ]
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
        // Its grand entrance: out from behind the menu bar, under its icon.
        let icon = statusItem.button?.window?.frame
        let screen = icon.flatMap { f in NSScreen.screens.first { $0.frame.contains(CGPoint(x: f.midX, y: f.midY)) } }
            ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            let x = icon?.midX ?? screen.frame.midX
            spider.makeEntrance(x: x, barY: screen.visibleFrame.maxY, top: screen.frame.maxY, floorY: screen.visibleFrame.minY)
        }
        wiggleIcon()
        refreshMenu()
    }

    /// Something stirring in the menu bar icon: two little shakes, the
    /// spider getting ready to come out.
    private var iconWiggle: Timer?
    private func wiggleIcon() {
        guard let button = statusItem.button else { return }
        iconWiggle?.invalidate()
        let plain = SpiderRenderer.statusItemImage(size: 17)
        let start = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            let e = CGFloat(CACurrentMediaTime() - start)
            // Two bursts, each dying away, with a pause between.
            func burst(_ from: CGFloat, _ len: CGFloat, _ swings: CGFloat, _ size: CGFloat) -> CGFloat {
                let u = (e - from) / len
                guard u > 0, u < 1 else { return 0 }
                return sin(u * swings * .pi) * size * (1 - u * 0.7)
            }
            let angle = burst(0.05, 0.6, 4, 0.38) + burst(0.9, 0.4, 3, 0.26)
            if e > 1.35 {
                button.image = plain
                timer.invalidate()
                self?.iconWiggle = nil
                return
            }
            button.image = AppDelegate.rotated(plain, by: angle)
        }
        RunLoop.main.add(t, forMode: .common)
        iconWiggle = t
    }

    private static func rotated(_ img: NSImage, by angle: CGFloat) -> NSImage {
        let out = NSImage(size: img.size, flipped: false) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // About a point low in the icon, as if it rocked on its feet.
            ctx.translateBy(x: r.midX, y: r.midY * 0.6)
            ctx.rotate(by: angle)
            ctx.translateBy(x: -r.midX, y: -r.midY * 0.6)
            img.draw(in: r)
            return true
        }
        out.isTemplate = img.isTemplate
        return out
    }

    @objc private func toggleFollow() {
        spider.config.followCursor.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func togglePounce() {
        spider.config.pounceOnCursor.toggle(); saveSettings(); refreshMenu()
    }

    @objc private func toggleApproach() {
        spider.config.approachCursor.toggle(); saveSettings(); refreshMenu()
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
        sense.onOutside = { [weak self] code, wind, day, temp in
            self?.heardOutside(code: code, wind: wind, day: day, temperature: temp)
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
        ears.onChange = { [weak self] in self?.refreshMenu() }
        updateEars()
        applyPowerMood()
    }

    /// Listening for music only while there is a spider out to dance to it
    /// (not put away, paused, or asleep while you are away).
    private func updateEars() {
        let want = dancesToMusic && !hidden && !awaitingEntrance && !spider.config.paused && !spider.dormant
        if want, ears.status == .off {
            ears.start()
        } else if !want, ears.status != .off, ears.status != .unsupported {
            ears.stop()
        }
    }

    @objc private func toggleDanceToMusic() {
        dancesToMusic.toggle()
        updateEars(); saveSettings(); refreshMenu()
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

    /// The Mac's Low Power Mode, as far as it goes along with it.
    private var macLowPower: Bool { feelsPower && sense.lowPower }
    /// In Low Power Mode itself: the Mac's, or its own.
    private var lowPower: Bool { powerOverride ?? macLowPower }

    private func applyPowerMood() {
        // Kept awake through one spell of the Mac's Low Power Mode, not the
        // next as well.
        if powerOverride == false, !ProcessInfo.processInfo.isLowPowerModeEnabled {
            powerOverride = nil
            saveSettings()
        }
        let low = lowPower
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
            && cinemaScreens.isEmpty && !lowPower
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

    /// Its own Low Power Mode switched by hand. Taking it out while the Mac
    /// is in Low Power Mode asks first: it is the one thing the Mac is
    /// trying to save.
    private func setLowPower(_ on: Bool) {
        guard on != lowPower else { return }
        if !on, ProcessInfo.processInfo.isLowPowerModeEnabled {
            let alert = NSAlert()
            alert.messageText = "Keep \(spider.name.isEmpty ? "your spider" : spider.name) at full speed?"
            alert.informativeText = "Your Mac is in Low Power Mode to save battery. Out of Low Power Mode, the spider is animated sixty times a second instead of thirty and is up and about far more, so it uses a lot more CPU and battery — and your battery will run down sooner.\n\nIt goes back to following your Mac once Low Power Mode is turned off."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Use Full Speed")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        powerOverride = on == macLowPower ? nil : on
        applyPowerMood(); saveSettings()
    }

    @objc private func toggleFeelWeather() {
        feelsWeather.toggle()
        if feelsWeather { sense.startWeather() } else { sense.stopWeather() }
        if !feelsWeather {
            outsideWeather = nil
            outsideSummary = nil
            habitat?.weather.outside = nil
        }
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
        updater.check()
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
        d.set(spider.config.approachCursor, forKey: "approachCursor")
        d.set(spider.config.pounceOnCursor, forKey: "pounceOnCursor")
        d.set(spider.config.webs, forKey: "webs")
        d.set(spider.config.hammocks, forKey: "hammocks")
        d.set(spider.config.paused, forKey: "paused")
        d.set(interactive, forKey: "interactive")
        d.set(hidden, forKey: "hidden")
        d.set(feelsPower, forKey: "feelPower")
        if let o = powerOverride { d.set(o, forKey: "lowPowerOverride") } else { d.removeObject(forKey: "lowPowerOverride") }
        d.set(feelsWeather, forKey: "feelWeather")
        d.set(showsRain, forKey: "showRain")
        d.set(feelsCommotion, forKey: "feelCommotion")
        d.set(dancesToMusic, forKey: "danceToMusic")
        d.set(learns, forKey: "learns")
        d.set(wildOn, forKey: "wildlife")
        d.set(tankWildOn, forKey: "tankWildlife")
        d.set(toySounds, forKey: "toySounds")
        d.set(leavesTraces, forKey: "traces")
        if AppDelegate.pagesReady { d.set(climbsPages, forKey: "climbPages") }
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "scale": 0.95, "liveliness": 1.0, "followCursor": true, "approachCursor": true, "pounceOnCursor": true,
            "webs": true, "hammocks": true, "paused": false, "interactive": true, "hidden": false,
            "visitors": false, "visitFrequency": 0.5, "visitStay": 0.5,
            "feelPower": true, "feelWeather": true, "showRain": true, "feelCommotion": true, "danceToMusic": true,
            "learns": true, "wildlife": false, "wildFrequency": 0.35, "toySounds": true, "traces": false, "traceLimit": 0.45,
            "tankWildlife": true, "climbPages": false,
        ])
        // (Not ready yet: off, and forget any old "on" so it starts off.)
        if !AppDelegate.pagesReady { d.removeObject(forKey: "climbPages") }
        climbsPages = AppDelegate.pagesReady && d.bool(forKey: "climbPages")
        tankWildOn = d.bool(forKey: "tankWildlife")
        toySounds = d.bool(forKey: "toySounds")
        leavesTraces = d.bool(forKey: "traces")
        traceLimitSetting = CGFloat(d.double(forKey: "traceLimit"))
        feelsPower = d.bool(forKey: "feelPower")
        powerOverride = d.object(forKey: "lowPowerOverride") as? Bool
        feelsWeather = d.bool(forKey: "feelWeather")
        showsRain = d.bool(forKey: "showRain")
        feelsCommotion = d.bool(forKey: "feelCommotion")
        dancesToMusic = d.bool(forKey: "danceToMusic")
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
        spider.config.approachCursor = d.bool(forKey: "approachCursor")
        spider.config.pounceOnCursor = d.bool(forKey: "pounceOnCursor")
        spider.config.webs = d.bool(forKey: "webs")
        spider.config.hammocks = d.bool(forKey: "hammocks")
        spider.config.paused = d.bool(forKey: "paused")
        interactive = d.bool(forKey: "interactive")
        hidden = d.bool(forKey: "hidden")
    }
}
