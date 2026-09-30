import AppKit
import CoreGraphics
import QuartzCore

// MARK: - Climbing web pages
//
// When a browser fills its screen — zoomed to fill it, or gone full screen
// — there is no desktop left and no other window to climb, and whoever
// works that way would never see it go anywhere but round the rim. So it
// climbs the page instead. The watcher here picks out those windows, looks
// at them now and then (a picture, taken and read off the main thread: see
// PageLedges.swift for what it makes of one), and hands the map the ledges
// it found, each with a name that lasts as long as the ledge does, so a
// spider standing on one stays put when the page is looked at again.
//
// When to look: every second and a half or so, to see whether anything has
// changed (a fingerprint of the picture, which is cheap — the reading is
// what costs, and is only done when something has); straight away when a
// page comes up or its title changes (a new page); a moment after a click
// in it (a link followed, a panel opened); and once a scroll comes to rest.
//
// While a page scrolls its ledges are on the move, so all of them but the
// one the spider is standing on are put aside until the page is still and
// has been looked at afresh. That one is followed: a small patch round its
// feet, looked at thirty times a second and matched against the last, so
// it rides the page up or down as it would a window being dragged. If it
// goes out of sight — up under the browser's bars, off the bottom — the
// spider falls, as from a window closed under it.
//
// Nothing on a page is ever read: the pictures are looked at for straight
// lines and open space, nothing else, and not kept.

final class PageWatcher {
    /// Climbing pages at all (the setting).
    var enabled = false {
        didSet {
            if !enabled, oldValue { forget() }
            if enabled { bridge.start() } else { bridge.stop() }
        }
    }
    /// The browser extension's line, where it has been added (see
    /// PageBridge.swift): exact scrolling, and word of changes.
    let bridge = PageBridge()

    init() {
        // A page scrolled: its ledges are where the extension says now.
        bridge.onScroll = { [weak self] _ in self?.onChange?(false) }
        // A page changed: look at it (the picture says whether anything
        // that matters did).
        bridge.onChange = { [weak self] tab in
            guard let self, let e = self.bridge.pages[tab] else { return }
            self.say("extension: tab \(tab) changed — \(e.scrollers.count) scrolling parts, \(e.fixed.count) fixed, zoom \(e.dpr)")
            let now = CACurrentMediaTime()
            for (id, p) in self.pages where self.bridge.page(in: p.window.frame)?.tab == e.tab {
                self.pages[id]?.dueAt = min(p.dueAt, now + 0.15)
                self.pages[id]?.restless = 0
                // Just come on the line, over a page read and not moved
                // since: where it is scrolled to now is where it was then.
                if p.baseline.isEmpty, p.still, !p.chains.isEmpty, now - p.lastScroll > PageWatcher.scrollQuiet {
                    self.pages[id]?.baseline = e.offsets
                    self.pages[id]?.carriers = self.carriers(for: p.chains, e, self.viewFrame(e, p))
                }
            }
        }
    }

    /// Whether the extension is helping with the page in a window.
    var extensionConnected: Bool { bridge.connected }
    /// In the tank, hidden or put away: not looking at anything for now.
    var paused = false
    /// How big the spider is: it needs room to fit.
    var scale: CGFloat = 0.95 {
        didSet { if scale != oldValue { for k in pages.keys { pages[k]?.force = true; pages[k]?.dueAt = 0 } } }
    }
    /// The height of its body line off an edge (the map's `standoff`).
    var standoff: CGFloat = 22
    /// Taking it easy (Low Power Mode): it looks less often.
    var lowPower = false
    /// Where the spider is: the surface it is on (nil if none), and the
    /// point on that surface's edge its feet are on.
    var spiderAt: () -> (loopID: String?, ground: V2) = { (nil, .zero) }
    /// The pages' ledges have changed — found afresh (`settled`, when the
    /// spider re-reads its footing), or only carried along by a scroll.
    var onChange: ((_ settled: Bool) -> Void)?
    /// Ledges just found again somewhere else, the whole page having moved
    /// under them — how far each went (in the world, by name): whatever is
    /// on one goes along with it. Good until the next change.
    private(set) var moved: [String: V2] = [:]
    /// SPIDER_PAGE_LOG=1: what it sees, as it sees it (stderr).
    var log = ProcessInfo.processInfo.environment["SPIDER_PAGE_LOG"] == "1"
    /// SPIDER_PAGE_SHOT=dir: every reading drawn over its picture, there.
    private let shots = ProcessInfo.processInfo.environment["SPIDER_PAGE_SHOT"]
    private var shotCount = 0
    /// Tools only: CPU time spent looking (on the queue) and laying out
    /// ledges (on the main thread), in seconds, and how many looks and
    /// readings there have been.
    private(set) var spent: (looking: Double, laying: Double, looks: Int, readings: Int) = (0, 0, 0, 0)
    static func threadCPU() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
    }

    /// A browser window it is climbing, and what it has made of it.
    private struct Page {
        var window: TrackedWindow
        var screen: CGRect
        var fullScreen: Bool
        /// What the last reading found, in picture pixels, each path with
        /// its name, and the window's size and the picture's scale then.
        var chains: [(id: Int, chain: PageChain)] = []
        var readSize: CGSize = .zero
        var pxPerPt: CGFloat = 1
        var pageTop = 0
        var nextID = 1
        /// The last picture's fingerprint, and when it was taken.
        var fingerprint: [UInt32]?
        var lastLook: CFTimeInterval = -100
        /// When it is next to be looked at, and whether it is to be read
        /// then even if it looks the same.
        var dueAt: CFTimeInterval = 0
        var force = true
        var busy = false
        /// How many looks in a row found it changing, unasked (an animation,
        /// a film playing): it is looked at less often while it goes on.
        var restless = 0
        /// Full screen with a film playing: no page to climb, but a film to
        /// sit and watch.
        var playing = false
        var titleHash: Int?
        /// The last scroll over it, and the scrolls since the last patch
        /// was taken (points, as the events have them).
        var lastScroll: CFTimeInterval = -100
        var scrolled: CGFloat = 0
        /// The path being carried along by a scroll, how far it has been
        /// (picture pixels, down being more), and the patch round the
        /// spider's feet it is being followed by.
        var tracked: Int?
        var shift: CGFloat = 0
        var patch: Patch?
        var tracking = false
        var lastTrack: CFTimeInterval = -100
        /// How far the page moves for a point of scrolling, learnt as it
        /// goes (and kept for the next scroll: pages mostly scroll just as
        /// far as the fingers go). None at all over a part that stays put.
        var gain: CGFloat = 0
        var gainKnown = false
        /// This scroll has been measured once: the first measure of each
        /// replaces the gain outright (this ledge may be on a part that
        /// stays put), later ones only nudge it.
        var measured = false
        /// With the extension: how far each part of the page had scrolled
        /// when the ledges were read (and as a look set off), and which
        /// part each ledge is carried by (-1: one that stays put).
        var baseline: [Int: CGPoint] = [:]
        var pendingBaseline: [Int: CGPoint]?
        var carriers: [Int: Int] = [:]
        /// Nothing has moved or changed on it since it was last read.
        var still = false
    }

    /// The pixels round the spider's feet, to follow them by.
    struct Patch {
        var pixels: [UInt32]
        var width: Int, height: Int
        /// Its top left, in picture pixels, when it was taken.
        var x: Int, y: Int
    }

    private var pages: [CGWindowID: Page] = [:]
    private let queue = DispatchQueue(label: "spider.pages", qos: .utility)
    /// The last picture of each page (only ever touched on the queue), as
    /// it came: turned into pixels to read only when it has to be.
    private var pictures: [CGWindowID: CGImage] = [:]
    private var allowed = false
    private var allowedAsked: CFTimeInterval = -100
    /// The windows as last seen, front first: to tell whether a scroll or a
    /// click went to the page (and not to a window over it).
    private var windowsFront: [TrackedWindow] = []

    /// A scroll is over when nothing has come for this long (momentum
    /// comes as events too).
    private static let scrollQuiet: CFTimeInterval = 0.3

    // MARK: Which windows

    /// The windows as the tracker sees them (front first), the full-screen
    /// ones, and the screens (frame, visible frame): which are pages to climb.
    func update(windows: [TrackedWindow], taken: [TrackedWindow], screens: [(frame: CGRect, visible: CGRect)],
                bare: [CGRect] = [], now: CFTimeInterval = CACurrentMediaTime()) {
        windowsFront = windows
        guard enabled else { return }
        var found: [CGWindowID: (TrackedWindow, CGRect, Bool)] = [:]
        for w in taken where Browsers.isBrowser(w.bundleID) {
            let sc = screens.first { $0.frame.intersects(w.frame) }?.frame ?? w.frame
            found[w.id] = (w, sc, true)
        }
        for sc in screens {
            // The front window of those filling the screen, if it is a
            // browser's (smaller ones in front of it just cover a bit).
            // (Full screen, the browser's bars may be a window of their own
            // over the top of the page's: the page's window then reaches
            // right across and down to the bottom, but not up to the top.)
            let fullSpace = bare.contains(sc.frame)
            let filling = windows.filter { w in
                let i = w.frame.intersection(sc.visible)
                if !i.isNull && i.width >= sc.visible.width - 40 && i.height >= sc.visible.height - 40 { return true }
                let j = w.frame.intersection(sc.frame)
                return fullSpace && !j.isNull && j.width >= sc.frame.width - 4 && j.minY <= sc.frame.minY + 4
                    && j.height >= sc.frame.height * 0.6
            }
            guard let w = filling.min(by: { $0.depth < $1.depth }), Browsers.isBrowser(w.bundleID),
                  found[w.id] == nil else { continue }
            found[w.id] = (w, sc.frame, fullSpace)
        }
        var changed = false, moved = false
        for id in pages.keys where found[id] == nil {
            pages[id] = nil
            changed = true
            queue.async { [weak self] in self?.pictures[id] = nil }
            say("page \(id) gone")
        }
        for (id, (w, screen, full)) in found {
            guard var p = pages[id] else {
                pages[id] = Page(window: w, screen: screen, fullScreen: full, titleHash: w.titleHash)
                say("page \(id): \(w.bundleID ?? w.owner)\(full ? " (full screen)" : "") \(Int(w.frame.width))×\(Int(w.frame.height))")
                continue
            }
            if w.frame.size != p.window.frame.size || full != p.fullScreen && !w.maximized {
                // Resized (or in or out of full screen): what was read no
                // longer fits. Read it again once it is still. (A maximized
                // window taking its screen, or no longer — another window
                // brought in front of it — looks just the same as it did.)
                if !p.chains.isEmpty { p.chains = []; changed = true }
                p.force = true
                p.dueAt = now + 0.4
                p.patch = nil
                p.tracked = nil
            }
            if let h = w.titleHash, h != p.titleHash {
                // A new page (or a new title on it): look now, and again once
                // it has had a moment to come in.
                p.titleHash = h
                p.force = true
                p.dueAt = min(p.dueAt, now + 0.25)
                p.restless = 0
                say("page \(id): title changed")
            }
            // Moved as it is: its ledges go with it (as a window's edges do).
            if w.frame.origin != p.window.frame.origin || w.depth != p.window.depth { moved = true }
            p.window = w
            p.screen = screen
            p.fullScreen = full
            pages[id] = p
        }
        if changed { onChange?(true) } else if moved { onChange?(false) }
        bridge.want(pages.values.map { $0.window.frame })
    }

    /// Screens a browser has taken whole to show a page (not a film).
    var pageScreens: [CGRect] {
        pages.values.filter { $0.fullScreen && !$0.playing }.map(\.screen)
    }

    /// Whether a browser has taken this screen to play a film.
    var filmScreens: [CGRect] {
        pages.values.filter { $0.fullScreen && $0.playing }.map(\.screen)
    }

    /// The browsers whose pages it is climbing (bundle identifiers).
    var browsers: [String] { pages.values.compactMap { $0.window.bundleID } }

    /// Browsers the extension can be added to (the Chromium family), with
    /// the address of their extensions page.
    static func extensionsPage(for bundleID: String) -> (name: String, address: String)? {
        let known: [(String, String, String)] = [
            ("com.brave.Browser", "Brave", "brave://extensions"), ("com.google.Chrome", "Chrome", "chrome://extensions"),
            ("com.microsoft.edgemac", "Edge", "edge://extensions"), ("company.thebrowser.", "Arc", "arc://extensions"),
            ("com.vivaldi.Vivaldi", "Vivaldi", "vivaldi://extensions"), ("com.operasoftware.", "Opera", "opera://extensions"),
            ("org.chromium.", "Chromium", "chrome://extensions"), ("ai.perplexity.comet", "Comet", "chrome://extensions"),
        ]
        return known.first { bundleID.hasPrefix($0.0) }.map { ($0.1, $0.2) }
    }

    /// For the menu: what it is climbing, if anything.
    var summary: String? {
        guard enabled else { return nil }
        let live = pages.values.filter { !$0.playing && !$0.chains.isEmpty }
        guard let p = live.max(by: { $0.chains.count < $1.chains.count }) else { return nil }
        let name = NSRunningApplication(processIdentifier: p.window.pid)?.localizedName ?? p.window.owner
        let n = live.reduce(0) { $0 + $1.chains.count }
        return "Climbing about \(name): \(n == 1 ? "one ledge" : "\(n) ledges") on the page."
    }

    /// Whether it can see pages at all: it needs leave to see the screen.
    var canSee: Bool { allowed }
    /// A browser fills a screen and it would climb the page, but has been
    /// found not to have leave to see it.
    var wantsLeave: Bool { enabled && !pages.isEmpty && allowedAsked > 0 && !allowed }

    private func forget() {
        let had = !pages.isEmpty
        pages = [:]
        queue.async { [weak self] in self?.pictures = [:] }
        if had { onChange?(true) }
    }

    private func say(_ s: @autoclosure () -> String) {
        if log { fputs("pages: \(s())\n", stderr) }
    }

    // MARK: The ledges

    /// Every page's ledges, laid out on the screen as surfaces. (While a
    /// page scrolls, only the one being carried along with the spider.)
    func loops(now: CFTimeInterval = CACurrentMediaTime()) -> [SurfaceLoop] {
        guard enabled else { return [] }
        let c0 = PageWatcher.threadCPU()
        defer { spent.laying += PageWatcher.threadCPU() - c0 }
        var out: [SurfaceLoop] = []
        for (wid, p) in pages where !p.playing && !p.chains.isEmpty {
            let f = p.window.frame
            guard abs(f.width - p.readSize.width) < 1, abs(f.height - p.readSize.height) < 1 else { continue }
            let ext = p.baseline.isEmpty ? nil : bridge.page(in: f)
            let frame = ext.map { viewFrame($0, p) }
            let scrolling = ext == nil && (p.tracking || p.lastLook < p.lastScroll || now - p.lastScroll < PageWatcher.scrollQuiet)
            let k = 1 / max(p.pxPerPt, 0.1)
            let top = CGFloat(p.pageTop), bottom = f.height * p.pxPerPt
            for (id, ch) in p.chains {
                var dx: CGFloat = 0, dy: CGFloat = 0
                if let ext, let frame, let c = p.carriers[id] {
                    // Carried exactly as far as its part of the page has
                    // scrolled — and gone once out of that part's sight.
                    let d = PageWatcher.carried(c, ext, p.baseline)
                    dx = d.x * frame.scale
                    dy = d.y * frame.scale
                    if dx != 0 || dy != 0 {
                        let clip = visible(c, ext, p.baseline, frame).insetBy(dx: -2, dy: -2)
                        if ch.points.contains(where: { !clip.contains(CGPoint(x: $0.x + dx, y: $0.y + dy)) }) { continue }
                    }
                } else if id == p.tracked {
                    dy = p.shift + p.gain * p.scrolled * p.pxPerPt
                } else if scrolling {
                    continue
                }
                // Carried up under the browser's bars, or off the bottom:
                // out of sight, and gone.
                if dy != 0, ch.points.contains(where: { $0.y + dy < top - 1 || $0.y + dy > bottom - 2 }) { continue }
                let pts = ch.points.map { V2(f.minX + ($0.x + dx) * k, f.maxY - ($0.y + dy) * k) }
                if let loop = SurfaceMap.pathLoop(id: "page:\(wid):\(id)", kind: .webLedge, points: pts,
                                                  facings: ch.sides.map(PageWatcher.facing), closed: ch.closed,
                                                  depth: p.fullScreen ? 0 : p.window.depth, standoff: standoff) {
                    out.append(loop)
                }
            }
        }
        return out
    }

    /// Where the extension's page area is in the window's picture: its top
    /// (picture pixels) and how many picture pixels to one of the page's.
    struct ViewFrame { var top: CGFloat; var scale: CGFloat }

    private func viewFrame(_ e: PageBridge.Page, _ p: Page) -> ViewFrame {
        let backing = NSScreen.screens.first { $0.frame.intersects(p.window.frame) }?.backingScaleFactor ?? 2
        let zoom = e.dpr / max(backing, 1)
        let scale = zoom * p.pxPerPt
        return ViewFrame(top: p.window.frame.height * p.pxPerPt - e.viewport.height * scale, scale: scale)
    }

    /// How far a part of the page (and whatever carries it) has scrolled
    /// since `base`, in the page's pixels, as its contents move (up the
    /// screen for a scroll down).
    static func carried(_ id: Int, _ e: PageBridge.Page, _ base: [Int: CGPoint]) -> CGPoint {
        var d = CGPoint.zero
        var c = id, n = 0
        while c >= 0, n < 16 {
            let now = e.offsets[c] ?? .zero, then = base[c] ?? now
            d.x += then.x - now.x
            d.y += then.y - now.y
            c = e.scrollers[c]?.carrier ?? -1
            n += 1
        }
        return d
    }

    /// Where a part of the page shows now, in picture pixels.
    private func visible(_ id: Int, _ e: PageBridge.Page, _ base: [Int: CGPoint], _ v: ViewFrame) -> CGRect {
        guard id >= 0, let s = e.scrollers[id] else { return .infinite }
        let d = s.carrier >= 0 ? PageWatcher.carried(s.carrier, e, base) : .zero
        let r = s.rect.offsetBy(dx: d.x, dy: d.y)
        return CGRect(x: r.minX * v.scale, y: v.top + r.minY * v.scale, width: r.width * v.scale, height: r.height * v.scale)
    }

    /// Which part of the page each path is on, going by the extension's
    /// last layout: what stays put, the innermost scrolling part it is in,
    /// or the page.
    private func carriers(for chains: [(id: Int, chain: PageChain)], _ e: PageBridge.Page, _ v: ViewFrame) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for (id, ch) in chains {
            let b = ch.bounds
            let c = CGPoint(x: b.midX / v.scale, y: (b.midY - v.top) / v.scale)
            if e.fixed.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(c) }) { out[id] = -1; continue }
            let inner = e.scrollers.values.filter { $0.id != 0 && $0.rect.insetBy(dx: -2, dy: -2).contains(c) }
                .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
            out[id] = inner?.id ?? 0
        }
        return out
    }

    static func facing(_ side: PageSide) -> EdgeFacing {
        switch side {
        case .above: return .up
        case .below: return .down
        case .left: return .left
        case .right: return .right
        }
    }

    // MARK: What you do

    /// A scroll went to whatever is under the pointer: a page, perhaps.
    func scrolled(at p: V2, by dy: CGFloat, precise: Bool, now: CFTimeInterval = CACurrentMediaTime()) {
        guard enabled, !paused, let id = page(at: p), var pg = pages[id] else { return }
        let wasStill = pg.lastLook >= pg.lastScroll && now - pg.lastScroll > PageWatcher.scrollQuiet && !pg.tracking
        pg.lastScroll = now
        pg.scrolled += dy
        pg.still = false
        // The extension says exactly where everything has got to: nothing
        // to put aside or follow, only a fresh look once it is still.
        if !pg.baseline.isEmpty, bridge.page(in: pg.window.frame) != nil {
            pages[id] = pg
            return
        }
        if wasStill {
            // The spider on one of its ledges: follow that one along.
            let at = spiderAt()
            let prefix = "page:\(id):"
            if let loop = at.loopID, loop.hasPrefix(prefix), let n = Int(loop.dropFirst(prefix.count)),
               pg.chains.contains(where: { $0.id == n }) {
                pg.tracked = n
                pg.shift = 0
                pg.patch = nil
                pg.scrolled = 0
                pg.measured = false
                say("page \(id): scrolling, following ledge \(n)")
            } else {
                pg.tracked = nil
                say("page \(id): scrolling")
            }
            pages[id] = pg
            // Everything else on it is put aside until it is still.
            onChange?(false)
            return
        }
        pages[id] = pg
    }

    /// A click on a page: it may be off to another, or open something.
    func clicked(at p: V2, now: CFTimeInterval = CACurrentMediaTime()) {
        guard enabled, !paused, let id = page(at: p), var pg = pages[id] else { return }
        pg.dueAt = min(pg.dueAt, now + 0.3)
        pg.force = true
        pg.restless = 0
        pages[id] = pg
        // …and again when whatever it started has come in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, var q = self.pages[id] else { return }
            q.dueAt = min(q.dueAt, CACurrentMediaTime())
            self.pages[id] = q
        }
    }

    /// The page window under a point, if nothing is in front of it there.
    private func page(at p: V2) -> CGWindowID? {
        for (id, pg) in pages where pg.window.frame.contains(p.point) {
            if pg.fullScreen { return id }
            let front = windowsFront.first { $0.frame.contains(p.point) }
            if front == nil || front?.id == id { return id }
        }
        return nil
    }

    // MARK: Looking

    /// Once a frame: sets off whatever looks are due. (Cheap: the looking
    /// itself is on its own queue.)
    func tick(now: CFTimeInterval = CACurrentMediaTime()) {
        guard enabled, !paused, !pages.isEmpty else { return }
        if now - allowedAsked > 5 {
            allowedAsked = now
            allowed = CGPreflightScreenCaptureAccess()
        }
        guard allowed else { return }
        let spider = spiderAt()
        for id in Array(pages.keys) {
            guard var p = pages[id] else { continue }
            let scrolling = now - p.lastScroll < PageWatcher.scrollQuiet
            if p.tracked != nil || p.tracking {
                if scrolling || p.tracking {
                    if !p.tracking, now - p.lastTrack > 1.0 / 30 { follow(id, &p, now: now, ground: spider.ground) }
                    pages[id] = p
                    continue
                }
                // Come to rest: read it afresh (keeping the one it rode on).
                p.dueAt = now
                p.force = true
            } else if scrolling {
                pages[id] = p
                continue
            } else if now - p.lastScroll < PageWatcher.scrollQuiet + 0.1, p.lastLook < p.lastScroll {
                p.dueAt = min(p.dueAt, now)
                p.force = true
            }
            if !p.busy, now >= p.dueAt {
                look(id, &p, now: now, near: p.screen.insetBy(dx: -40, dy: -40).contains(spider.ground.point))
            }
            pages[id] = p
        }
    }

    /// Takes a picture of the page and, if it has changed (or must be read
    /// regardless), reads it — on the queue; the answer comes back here.
    private func look(_ id: CGWindowID, _ p: inout Page, now: CFTimeInterval, near: Bool) {
        p.busy = true
        p.pendingBaseline = bridge.page(in: p.window.frame)?.offsets
        let before = p.fingerprint
        let force = p.force || p.chains.isEmpty && p.lastLook < 0
        let scale = self.scale
        // (Maximized, its bars are showing as ever.)
        let full = p.fullScreen && !p.window.maximized
        let film = p.playing
        let size = p.window.frame.size
        p.force = false
        queue.async { [weak self] in
            let t0 = CACurrentMediaTime(), c0 = PageWatcher.threadCPU()
            defer {
                let c = PageWatcher.threadCPU() - c0
                DispatchQueue.main.async { self?.spent.looking += c }
            }
            guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .nominalResolution]),
                  let print = PageWatcher.fingerprint(img) ?? PagePicture(image: img).map(PageWatcher.fingerprint) else {
                DispatchQueue.main.async { self?.looked(id, nil, near: near) }
                return
            }
            let changed = before.map { PageWatcher.difference($0, print) } ?? 1
            // (Kept, to follow the spider's feet from if the page scrolls.)
            self?.pictures[id] = img
            var reading: Reading?
            if force || (changed > 0.004 && !film), let pic = PagePicture(image: img) {
                let pxPerPt = CGFloat(pic.width) / max(size.width, 1)
                let s = PageReader.Settings.forScale(scale * pxPerPt)
                // (Full screen, the browser's bars may be hidden: none, or
                // only as far down as they reach when shown.)
                let top = PageReader.pageTop(in: pic, within: min(full ? 160 : 240, pic.height / 3), s)
                let y0 = max(top - 3, 0)
                let edges = PageReader.edges(in: pic, s, area: CGRect(x: 0, y: y0, width: pic.width, height: pic.height - y0))
                let chains = PageReader.chains(edges, trim: CGFloat(s.trim))
                reading = Reading(chains: chains, pageTop: top, pxPerPt: pxPerPt,
                                  picture: CGSize(width: pic.width, height: pic.height))
                if let dir = self?.shots, let n = self?.nextShot() {
                    PageWatcher.draw(pic, chains: chains, top: top, to: "\(dir)/page-\(id)-\(n).png")
                }
            }
            let result = LookResult(fingerprint: print, changed: changed, reading: reading, size: size,
                                    ms: (CACurrentMediaTime() - t0) * 1000, forced: force)
            DispatchQueue.main.async { self?.looked(id, result, near: near) }
        }
    }

    private struct Reading {
        var chains: [PageChain]
        var pageTop: Int
        var pxPerPt: CGFloat
        var picture: CGSize
    }

    private struct LookResult {
        var fingerprint: [UInt32]
        var changed: Double
        var reading: Reading?
        var size: CGSize
        var ms: Double
        var forced: Bool
    }

    private func looked(_ id: CGWindowID, _ r: LookResult?, near: Bool) {
        guard var p = pages[id] else { return }
        let now = CACurrentMediaTime()
        moved = [:]
        p.busy = false
        p.lastLook = now
        spent.looks += 1
        if r?.reading != nil { spent.readings += 1 }
        guard let r else {
            // No picture (the window going, or not allowed): try again later.
            p.dueAt = now + 3
            pages[id] = p
            return
        }
        p.fingerprint = r.fingerprint
        // A page that keeps changing unasked is looked at less often; full
        // screen, it is a film playing (nothing to climb: a film to watch).
        let busy = r.changed > 0.004 && !r.forced
        p.restless = busy ? p.restless + 1 : 0
        let wasPlaying = p.playing
        if p.fullScreen {
            if r.changed > 0.25 && !r.forced { p.playing = p.playing || p.restless >= 2 } else if !busy { p.playing = false }
        } else {
            p.playing = false
        }
        var settled = p.playing != wasPlaying
        if let reading = r.reading, abs(r.size.width - p.window.frame.width) < 1, abs(r.size.height - p.window.frame.height) < 1 {
            // (Where the old ledges had got to: carried along by a scroll —
            // exactly, with the extension; the one followed, without.)
            let ext = p.baseline.isEmpty ? nil : bridge.page(in: p.window.frame)
            let frame = ext.map { viewFrame($0, p) }
            let old = p.chains.map { entry -> (id: Int, chain: PageChain) in
                var d = CGPoint.zero
                if let ext, let frame, let c = p.carriers[entry.id] {
                    var then = ext
                    then.offsets = p.pendingBaseline ?? ext.offsets
                    let m = PageWatcher.carried(c, then, p.baseline)
                    d = CGPoint(x: m.x * frame.scale, y: m.y * frame.scale)
                } else if entry.id == p.tracked {
                    d.y = p.shift
                }
                guard d != .zero else { return entry }
                var c = entry.chain
                c.points = c.points.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
                return (entry.id, c)
            }
            let named = PageWatcher.name(reading.chains, after: old, next: &p.nextID)
            if named.map(\.id) != p.chains.map(\.id) || named.map(\.chain) != old.map(\.chain) || p.shift != 0 { settled = true }
            // Ledges that moved with the page carry whatever is on them along.
            let k = 1 / max(reading.pxPerPt, 0.1)
            for n in named where n.moved != 0 { moved["page:\(id):\(n.id)"] = V2(0, -n.moved * k) }
            p.chains = named.map { ($0.id, $0.chain) }
            p.pageTop = reading.pageTop
            p.still = true
            p.baseline = [:]
            p.carriers = [:]
            if let base = p.pendingBaseline, let e = bridge.page(in: p.window.frame) {
                p.baseline = base
                p.pxPerPt = reading.pxPerPt
                p.carriers = carriers(for: p.chains, e, viewFrame(e, p))
            }
            p.pxPerPt = reading.pxPerPt
            p.readSize = r.size
            p.tracked = nil
            p.shift = 0
            p.patch = nil
            p.scrolled = 0
            say(String(format: "page %d: read in %.1f ms — %d ledges%@, top %d, %.1f%% changed", id, r.ms, named.count,
                       p.playing ? " (a film)" : "", reading.pageTop, r.changed * 100))
        } else if r.reading == nil {
            say(String(format: "page %d: looked in %.1f ms, the same (%.2f%% changed)", id, r.ms, r.changed * 100))
        }
        // Next look: every second and a half or so while it is being
        // climbed; less often in Low Power Mode, off on another screen, or
        // while it keeps changing by itself; a film, every second (to see
        // it stop).
        var every: CFTimeInterval = lowPower ? 4 : 1.5
        if !near { every *= 3 }
        if p.restless > 2 { every *= min(Double(p.restless - 1), 4) }
        if p.playing { every = 1 }
        p.dueAt = max(p.dueAt, now + every)
        if p.dueAt < now { p.dueAt = now + every }
        pages[id] = p
        if settled { onChange?(true) }
    }

    /// Names for what was just found: each path takes the name of the one
    /// it was, if it overlaps it well enough (found a pixel off, a little
    /// longer or shorter), else a new one. Where much of the page has moved
    /// by the same amount since (a bar above it closing, the keys scrolling
    /// it), a path that moved with it keeps its name too — and how far it
    /// moved, in picture pixels (down being more), comes back with it.
    private static func name(_ fresh: [PageChain], after old: [(id: Int, chain: PageChain)],
                             next: inout Int) -> [(id: Int, chain: PageChain, moved: CGFloat)] {
        typealias Stretch = (horizontal: Bool, pos: CGFloat, lo: CGFloat, hi: CGFloat, side: PageSide)
        func stretches(_ c: PageChain) -> [Stretch] {
            c.sides.indices.map { i in
                let a = c.points[i], b = c.points[c.closed ? (i + 1) % c.points.count : i + 1]
                let horizontal = abs(a.y - b.y) < 0.5
                return horizontal ? (true, a.y, min(a.x, b.x), max(a.x, b.x), c.sides[i])
                                  : (false, a.x, min(a.y, b.y), max(a.y, b.y), c.sides[i])
            }
        }
        let oldStretches = old.map { stretches($0.chain) }
        let freshStretches = fresh.map(stretches)
        // The page moved as a whole? Lines across that are the same but for
        // being higher or lower, all by the same amount.
        var votes: [Int: Int] = [:]
        for theirs in oldStretches {
            for b in theirs where b.horizontal {
                for mine in freshStretches {
                    for a in mine where a.horizontal && a.side == b.side && a.pos != b.pos && abs(a.pos - b.pos) < 600 {
                        let overlap = min(a.hi, b.hi) - max(a.lo, b.lo)
                        let shorter = min(a.hi - a.lo, b.hi - b.lo), longer = max(a.hi - a.lo, b.hi - b.lo)
                        if overlap >= 0.8 * shorter, shorter >= 0.85 * longer { votes[Int((a.pos - b.pos).rounded()), default: 0] += 1 }
                    }
                }
            }
        }
        // (A pixel either way is the same move.)
        let best = votes.keys.max { k1, k2 in
            (votes[k1 - 1] ?? 0) + votes[k1]! + (votes[k1 + 1] ?? 0) < (votes[k2 - 1] ?? 0) + votes[k2]! + (votes[k2 + 1] ?? 0)
        }
        let support = best.map { (votes[$0 - 1] ?? 0) + votes[$0]! + (votes[$0 + 1] ?? 0) } ?? 0
        let moves: [CGFloat] = best != nil && support >= 3 ? [0, CGFloat(best!)] : [0]

        var scores: [(fresh: Int, old: Int, score: CGFloat, moved: CGFloat)] = []
        for (i, mine) in freshStretches.enumerated() {
            let total = mine.reduce(CGFloat(0)) { $0 + $1.hi - $1.lo }
            for (j, theirs) in oldStretches.enumerated() {
                let theirTotal = theirs.reduce(CGFloat(0)) { $0 + $1.hi - $1.lo }
                for dy in moves {
                    var shared: CGFloat = 0
                    for a in mine {
                        for b in theirs where a.horizontal == b.horizontal && a.side == b.side {
                            let pos = b.horizontal ? b.pos + dy : b.pos
                            let lo = b.horizontal ? b.lo : b.lo + dy, hi = b.horizontal ? b.hi : b.hi + dy
                            guard abs(a.pos - pos) <= 3 else { continue }
                            shared += max(0, min(a.hi, hi) - max(a.lo, lo))
                        }
                    }
                    if shared >= 0.5 * min(total, theirTotal) { scores.append((i, j, shared, dy)) }
                }
            }
        }
        // (Staying put beats moving, other things being equal.)
        scores.sort { $0.score != $1.score ? $0.score > $1.score : abs($0.moved) < abs($1.moved) }
        var given = [(id: Int, moved: CGFloat)?](repeating: nil, count: fresh.count)
        var taken = Set<Int>()
        for s in scores where given[s.fresh] == nil && !taken.contains(s.old) {
            given[s.fresh] = (old[s.old].id, s.moved)
            taken.insert(s.old)
        }
        return fresh.enumerated().map { i, c in
            if let g = given[i] { return (g.id, c, g.moved) }
            next += 1
            return (next - 1, c, 0)
        }
    }

    private func nextShot() -> Int {
        shotCount += 1
        return shotCount
    }

    /// Tools only (SPIDER_PAGE_SHOT): a reading drawn over its picture —
    /// ledges to stand on green, to hang from blue, walls orange (room to
    /// the left) and magenta (to the right), corners red, and a line where
    /// the page starts under the browser's bars.
    static func draw(_ pic: PagePicture, chains: [PageChain], top: Int, to path: String) {
        let w = pic.width, h = pic.height
        var px = pic.pixels.map { $0 | 0xFF00_0000 }
        guard let ctx = px.withUnsafeMutableBytes({ buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        }), let base = ctx.makeImage() else { return }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.45))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setStrokeColor(CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1))
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 0, y: CGFloat(h - top))); ctx.addLine(to: CGPoint(x: CGFloat(w), y: CGFloat(h - top))); ctx.strokePath()
        for ch in chains {
            for i in ch.sides.indices {
                let a = ch.points[i], b = ch.points[ch.closed ? (i + 1) % ch.points.count : i + 1]
                switch ch.sides[i] {
                case .above: ctx.setStrokeColor(CGColor(red: 0.1, green: 0.75, blue: 0.2, alpha: 1))
                case .below: ctx.setStrokeColor(CGColor(red: 0.15, green: 0.35, blue: 1, alpha: 1))
                case .left: ctx.setStrokeColor(CGColor(red: 1, green: 0.55, blue: 0, alpha: 1))
                case .right: ctx.setStrokeColor(CGColor(red: 0.85, green: 0.1, blue: 0.8, alpha: 1))
                }
                ctx.setLineWidth(3)
                ctx.move(to: CGPoint(x: a.x, y: CGFloat(h) - a.y)); ctx.addLine(to: CGPoint(x: b.x, y: CGFloat(h) - b.y)); ctx.strokePath()
            }
            ctx.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
            for (k, pt) in ch.points.enumerated() where ch.closed || (k > 0 && k < ch.points.count - 1) {
                ctx.fillEllipse(in: CGRect(x: pt.x - 4, y: CGFloat(h) - pt.y - 4, width: 8, height: 8))
            }
        }
        guard let img = ctx.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    // MARK: Fingerprints

    /// The same, straight from a window's picture as it comes (32-bit,
    /// little-endian, alpha first), without making pixels of all of it.
    /// Nil for a picture in any other form.
    static func fingerprint(_ img: CGImage) -> [UInt32]? {
        let w = img.width, h = img.height
        guard w > 8, h > 8, img.bitsPerPixel == 32, img.bitsPerComponent == 8,
              img.bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little,
              [.premultipliedFirst, .first, .noneSkipFirst].contains(img.alphaInfo),
              let data = img.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
              CFDataGetLength(data) >= img.bytesPerRow * h else { return nil }
        let raw = UnsafeRawPointer(bytes)
        var out: [UInt32] = [UInt32(w), UInt32(h)]
        let step = 12
        out.reserveCapacity((w / step + 1) * (h / step + 1) + 2)
        var y = step / 2
        while y < h {
            var x = step / 2
            while x < w {
                out.append(raw.loadUnaligned(fromByteOffset: y * img.bytesPerRow + x * 4, as: UInt32.self) & 0x00FF_FFFF)
                x += step
            }
            y += step
        }
        return out
    }

    /// A sparse sample of the picture: enough to tell whether it has
    /// changed, not to see anything by.
    static func fingerprint(_ pic: PagePicture) -> [UInt32] {
        var out: [UInt32] = []
        let step = 12
        out.reserveCapacity((pic.width / step + 1) * (pic.height / step + 1) + 2)
        out.append(UInt32(pic.width))
        out.append(UInt32(pic.height))
        var y = step / 2
        while y < pic.height {
            var x = step / 2
            while x < pic.width {
                out.append(pic.at(x, y))
                x += step
            }
            y += step
        }
        return out
    }

    /// The share of two fingerprints that differs (1 if they are of
    /// different pictures altogether).
    static func difference(_ a: [UInt32], _ b: [UInt32]) -> Double {
        guard a.count == b.count, a.count > 2, a[0] == b[0], a[1] == b[1] else { return 1 }
        var n = 0
        for i in 2..<a.count where PageReader.dist(a[i], b[i]) > 10 { n += 1 }
        return Double(n) / Double(a.count - 2)
    }

    // MARK: Following a scroll

    /// Looks at the patch round the spider's feet again (on the queue) to
    /// see how far the page has carried them.
    private func follow(_ id: CGWindowID, _ p: inout Page, now: CFTimeInterval, ground: V2) {
        guard p.tracked != nil else { return }
        p.tracking = true
        p.lastTrack = now
        let f = p.window.frame
        let k = p.pxPerPt
        // Its feet in picture pixels, as things stand.
        let fx = Int(((ground.x - f.minX) * k).rounded()), fy = Int(((f.maxY - ground.y) * k).rounded())
        let predicted = p.gainKnown ? p.gain * p.scrolled * k : 0
        let patch = p.patch
        let scrolledThen = p.scrolled
        let cg = CGRect(x: f.minX, y: (NSScreen.screens.first?.frame.maxY ?? f.maxY) - f.maxY, width: f.width, height: f.height)
        let picW = Int(f.width * k), picH = Int(f.height * k)
        let top = p.pageTop
        queue.async { [weak self] in
            let c0 = PageWatcher.threadCPU()
            defer {
                let c = PageWatcher.threadCPU() - c0
                DispatchQueue.main.async { self?.spent.looking += c }
            }
            let result = PageWatcher.track(windowID: id, cgFrame: cg, pxPerPt: k, picSize: (picW, picH), pageTop: top,
                                           foot: (fx, fy), patch: patch,
                                           read: patch == nil ? self?.pictures[id].flatMap(PagePicture.init(image:)) : nil,
                                           predicted: predicted)
            DispatchQueue.main.async { self?.followed(id, result, scrolledThen: scrolledThen) }
        }
    }

    private func followed(_ id: CGWindowID, _ r: (moved: CGFloat, patch: Patch)?, scrolledThen: CGFloat) {
        guard var p = pages[id] else { return }
        p.tracking = false
        guard p.tracked != nil else { pages[id] = p; return }
        guard let r else {
            // Lost it: gone out of sight, or under something that stays put.
            say("page \(id): lost the ledge it was riding")
            p.chains.removeAll { $0.id == p.tracked }
            p.tracked = nil
            p.patch = nil
            pages[id] = p
            onChange?(true)
            return
        }
        // How far the page moves for a point of scrolling, learnt from how
        // far it did.
        if abs(scrolledThen) > 2 {
            let g = clamp(r.moved / (scrolledThen * p.pxPerPt), -2, 2)
            p.gain = p.gainKnown && p.measured ? p.gain * 0.6 + g * 0.4 : g
            p.gainKnown = true
            p.measured = true
        }
        p.shift += r.moved
        p.scrolled -= scrolledThen
        p.patch = r.patch
        pages[id] = p
        onChange?(false)
    }

    /// Where the patch round the spider's feet has got to: a strip of the
    /// window around where it was (or where the scroll so far should have
    /// taken it), searched up and down for the best match. The first patch
    /// is cut from the picture the ledges were read from (`read`), so it is
    /// where the ledge was, however far the page has gone since. Nil if
    /// nothing matches well: it has gone. Off the main thread.
    private static func track(windowID: CGWindowID, cgFrame: CGRect, pxPerPt k: CGFloat, picSize: (Int, Int), pageTop: Int,
                              foot: (x: Int, y: Int), patch: Patch?, read: PagePicture?,
                              predicted: CGFloat) -> (moved: CGFloat, patch: Patch)? {
        let halfW = 90, halfH = 26, reach = 170
        let (picW, picH) = picSize
        let x0 = max(foot.x - halfW, 0), x1 = min(foot.x + halfW, picW)
        guard x1 - x0 > 20 else { return nil }
        // The patch to find: the last one, or one cut from the reading.
        var old: Patch
        if let patch {
            old = patch
        } else {
            // (Cut short at the picture's edge, for a ledge right at the
            // bottom of the window, say.)
            guard let pic = read, pic.width >= x1 else { return nil }
            let r0 = max(foot.y - halfH, pageTop), r1 = min(foot.y + halfH, pic.height)
            guard r1 - r0 >= 16 else { return nil }
            var px: [UInt32] = []
            px.reserveCapacity((x1 - x0) * (r1 - r0))
            for r in r0..<r1 { for c in x0..<x1 { px.append(pic.at(c, r)) } }
            old = Patch(pixels: px, width: x1 - x0, height: r1 - r0, x: x0, y: r0)
        }
        let want = old.y + Int(predicted.rounded())
        let y0 = max(want - reach, pageTop), y1 = min(want + old.height + reach, picH)
        guard y1 - y0 > old.height + 4 else { return nil }
        let rect = CGRect(x: cgFrame.minX + CGFloat(old.x) / k, y: cgFrame.minY + CGFloat(y0) / k,
                          width: CGFloat(old.width) / k, height: CGFloat(y1 - y0) / k)
        guard let img = CGWindowListCreateImage(rect, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .nominalResolution]),
              let strip = PagePicture(image: img) else { return nil }
        // (The strip may come back a pixel off the size asked for.)
        let sw = min(strip.width, old.width), rows = strip.height - old.height
        guard sw > 20, rows >= 0 else { return nil }
        // Every place it could have moved to; ties go to where the scroll
        // said it should be.
        var best = Int.max, bestRow = -1
        let wantRow = want - y0
        for r0 in 0...rows {
            var sad = 0
            var r = 0
            while r < old.height, sad <= best {
                let row = (r0 + r) * strip.width, prow = r * old.width
                var c = 1
                while c < sw {
                    sad += Int(PageReader.dist(strip.pixels[row + c], old.pixels[prow + c]))
                    c += 3
                }
                r += 1
            }
            if sad < best || (sad == best && abs(r0 - wantRow) < abs(bestRow - wantRow)) {
                best = sad
                bestRow = r0
            }
        }
        let samples = max(old.height * (sw / 3), 1)
        guard bestRow >= 0, best / samples <= 14 else { return nil }
        var px: [UInt32] = []
        px.reserveCapacity(sw * old.height)
        for r in bestRow..<(bestRow + old.height) { for c in 0..<sw { px.append(strip.at(c, r)) } }
        let fresh = Patch(pixels: px, width: sw, height: old.height, x: old.x, y: y0 + bestRow)
        return (CGFloat(fresh.y - old.y), fresh)
    }
}
