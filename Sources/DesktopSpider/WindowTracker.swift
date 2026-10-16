import AppKit
import CoreGraphics
import QuartzCore

struct TrackedWindow {
    let id: CGWindowID
    /// AppKit global coords (origin bottom-left of primary display).
    let frame: CGRect
    /// Front-to-back order, 0 == frontmost.
    let depth: Int
    let owner: String
    /// How round its corners are, in points. macOS windows are anything
    /// from about 16 to over 30; measured where the spider can see the
    /// screen, else a size that suits most (see `SurfaceMap.windowCornerRadius`).
    var cornerRadius: CGFloat = SurfaceMap.windowCornerRadius
    /// The app it belongs to.
    var pid: pid_t = 0
    var bundleID: String?
    /// For a browser's window only: its title (the page's, as a rule),
    /// boiled down to a number — which changes when the page does. The
    /// title itself is not kept. Nil when it cannot be read (without leave
    /// to see the screen) or for any other app.
    var titleHash: Int?
    /// It fills its screen below the menu bar — zoomed, or dragged to the
    /// top and tiled to fill it — rather than having a full-screen Space of
    /// its own (see `WindowTracker.fills`).
    var maximized = false
    /// One of the widgets on the desktop: furniture behind every window.
    var widget = false
}

/// Polls the window server for on-screen window rectangles so the spider knows
/// what it can climb on. Only geometry is read, which needs no special
/// permissions — window *titles* and images would, and we never ask for them.
final class WindowTracker {
    private var timer: Timer?
    private let queue = DispatchQueue(label: "spider.windows", qos: .utility)
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    /// Owners whose windows are decoration, not furniture.
    private static let ignoredOwners: Set<String> = [
        "Window Server", "Dock", "SystemUIServer", "Control Center",
        "Notification Center", "Spotlight", "DesktopSpider", "Wallpaper",
        "TextInputMenuAgent", "universalaccessd", "coreautha", "loginwindow",
    ]

    /// Windows to climb on, and the displays some app has taken whole (a
    /// full-screen window is left out of the list: its edges are the
    /// screen's edges, and it is not furniture to play on — though what a
    /// browser shows there may be: those windows are `taken`). A maximized
    /// window in front of everything else on its display has taken it just
    /// the same (see `zoomedScreens`).
    /// (And where the Dock is: see `SurfaceMap.dockStrips`.)
    var onUpdate: (([TrackedWindow], _ fullScreens: [CGRect], _ docks: [CGRect], _ taken: [TrackedWindow]) -> Void)?

    /// Reads browser windows' titles (as a sign of the page changing): on
    /// while pages are being climbed.
    var readsBrowserTitles = false
    /// The widgets on the desktop count as furniture (Settings ▸ Behavior).
    var standsOnWidgets = true
    /// Screens with no desktop showing at the last look: a full-screen
    /// Space (whatever is on it — a browser with its bars showing is two
    /// windows, neither covering the screen).
    private(set) var bareScreens: [CGRect] = []
    /// Of the displays taken whole at the last look, those taken by a
    /// maximized window rather than a full-screen one: the menu bar is
    /// still there over it (and the Dock, if it is not hidden).
    private(set) var zoomedScreens: [CGRect] = []

    /// A notification banner came up, on the display given. Each banner is
    /// a window of its own from Notification Center, over everything else
    /// and as big as the display it is on (on macOS 26: layer 21, about
    /// four seconds). What it says is not ours to read, and is not read.
    var onBanner: ((_ screen: CGRect) -> Void)?
    /// The banners up at the last look; nil until the first, so one already
    /// showing at launch is not news.
    private var banners: Set<CGWindowID>?

    /// Our own windows that count as furniture all the same — the studio.
    /// Everything else of ours is an overlay: the spider itself, its silk,
    /// the box, the laser dot — and is skipped without a second look.
    var ownFurniture: Set<CGWindowID> = []

    /// The window-server layers of the desktop picture (the Dock's, before
    /// Sonoma's Wallpaper process took it over) and of Finder's desktop icons.
    private static let desktopLayer = Int(CGWindowLevelForKey(.desktopWindow))
    private static let desktopIconLayer = Int(CGWindowLevelForKey(.desktopIconWindow))

    private var lastFrames: [CGWindowID: CGRect] = [:]
    private var busyUntil: TimeInterval = 0
    private var ticks = 0

    /// Polls at 30 Hz while any window is moving or resizing — so a spider
    /// riding a dragged window keeps up with it — and drops to 10 Hz once the
    /// desktop is still, which is still quick enough that a window opened
    /// over it is noticed at once.
    func start() {
        stop()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ticks += 1
            let busy = CACurrentMediaTime() < self.busyUntil
            if busy || self.ticks % 3 == 0 { self.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// A fresh look at the desktop right now.
    func pollNow() { poll(asked: true) }

    /// A look is under way on the queue. The clock's next tick skips while it
    /// is, rather than queueing up behind it (on a slow Mac a look can outlast
    /// the tick, and a backlog makes every answer late); a fresh look asked
    /// for meanwhile is taken as soon as it is back.
    private var looking = false
    private var lookAgain = false

    private func poll(asked: Bool = false)  {
        if looking { if asked { lookAgain = true }; return }
        looking = true
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let visible = NSScreen.screens.map { ($0.frame, $0.visibleFrame) }
        let pid = selfPID
        let own = ownFurniture
        let titles = readsBrowserTitles
        let widgets = standsOnWidgets
        queue.async { [weak self] in
            guard let self else { return }
            let (found, fullScreens, banners, taken, bare, zoomed) = self.snapshot(primaryTop: primaryTop, screens: visible, selfPID: pid,
                                                                                  own: own, titles: titles, widgets: widgets)
            let result = self.withCornerRadii(found, primaryTop: primaryTop)
            let docks = SurfaceMap.dockStrips(screens: visible)
            DispatchQueue.main.async {
                self.looking = false
                defer { if self.lookAgain { self.lookAgain = false; self.poll(asked: true) } }
                if let before = self.banners {
                    for (id, screen) in banners where !before.contains(id) { self.onBanner?(screen) }
                }
                self.banners = Set(banners.keys)
                self.bareScreens = bare
                self.zoomedScreens = zoomed
                var frames: [CGWindowID: CGRect] = [:]
                var changed = false
                let now = CACurrentMediaTime()
                for w in result {
                    frames[w.id] = w.frame
                    if let was = self.lastFrames[w.id], was != w.frame {
                        changed = true
                        if self.leaving[w.id] != nil || WindowTracker.minimizing(from: was, to: w.frame, dock: self.dockEdge()) {
                            self.leaving[w.id] = now
                        }
                    } else if self.lastFrames[w.id] == nil { changed = true }
                }
                if frames.count != self.lastFrames.count { changed = true }
                self.lastFrames = frames
                // A window on its way into the Dock is gone the moment it
                // sets off: until it is out of the list — or, if it was not
                // going after all (tiled to the bottom of the screen, say),
                // has been still a moment.
                // (A window already on its way stays so while it moves.)
                self.leaving = self.leaving.filter { id, since in frames[id] != nil && now - since < 0.6 }
                if changed { self.busyUntil = now + 0.8 }
                self.onUpdate?(self.leaving.isEmpty ? result : result.filter { self.leaving[$0.id] == nil }, fullScreens, docks, taken)
            }
        }
    }

    // MARK: Minimizing
    //
    // Minimized, a window goes down into the Dock over a quarter to half a
    // second, and all the while the window server lists it where it is
    // drawn: shrinking (Scale), or warped and stretched toward its tile
    // (Genie, whose box widens and slides down whole). Anything standing
    // on it would ride that box about in mid-air, so it is let go of at
    // once (see `leaving`).

    /// Windows seen setting off into the Dock, and when they last moved
    /// like it: left out of what is reported.
    private var leaving: [CGWindowID: CFTimeInterval] = [:]

    /// Which side of the screen the Dock is on (shown or hidden), from its
    /// own settings, read now and then.
    private var dockSide: (read: CFTimeInterval, edge: SurfaceMap.DockEdge)?
    private func dockEdge() -> SurfaceMap.DockEdge {
        let now = CACurrentMediaTime()
        if let d = dockSide, now - d.read < 5 { return d.edge }
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let edge: SurfaceMap.DockEdge
        switch UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") {
        case "left": edge = .left
        case "right": edge = .right
        default: edge = .bottom
        }
        dockSide = (now, edge)
        return edge
    }

    /// Whether a window's frame changing from `was` to `now` between two
    /// looks is the start of it going into the Dock. Dragged, a window keeps
    /// its size; resized by an edge or a corner, it keeps a corner where it
    /// was (and resized with ⌥ held, its middle). Going into the Dock, its
    /// size changes with no corner kept, its middle heads for the Dock and
    /// the side away from the Dock comes along with it.
    static func minimizing(from was: CGRect, to now: CGRect, dock: SurfaceMap.DockEdge) -> Bool {
        let slack: CGFloat = 1.5
        let resized = abs(now.width - was.width) > slack || abs(now.height - was.height) > slack
        guard resized else { return false }
        let left = abs(now.minX - was.minX) <= slack, right = abs(now.maxX - was.maxX) <= slack
        let bottom = abs(now.minY - was.minY) <= slack, top = abs(now.maxY - was.maxY) <= slack
        if (left || right) && (bottom || top) { return false }
        let lead: CGFloat = 2
        switch dock {
        case .bottom: return was.maxY - now.maxY >= lead && was.midY - now.midY >= lead
        case .left: return was.maxX - now.maxX >= lead && was.midX - now.midX >= lead
        case .right: return now.minX - was.minX >= lead && now.midX - was.midX >= lead
        }
    }

    // MARK: Window corners
    //
    // (On the tracker's own queue, as the rest of the looking is: a look at
    // a window's corner is a picture of it, which takes a good few
    // milliseconds — too long for the main thread, where the spider lives.)

    /// How round each window's corners are, measured once per window.
    private var cornerRadii: [CGWindowID: CGFloat] = [:]
    /// Whether it may look at the screen, and when that was last asked
    /// (asking is itself a trip to another process).
    private var canSee = false
    private var canSeeAsked: CFTimeInterval = -100

    /// Fills in each window's corner radius — the spider's feet go on the
    /// curve of a window's corner, not out on the square corner where
    /// there is no window. Allowed to see the screen, it measures each
    /// window once (a couple of new ones a poll, so a crowded desktop is
    /// not all done at once); otherwise every window gets the default.
    private func withCornerRadii(_ windows: [TrackedWindow], primaryTop: CGFloat) -> [TrackedWindow] {
        let now = CACurrentMediaTime()
        if now - canSeeAsked > 5 {
            canSeeAsked = now
            canSee = CGPreflightScreenCaptureAccess()
        }
        var budget = 2
        let live = Set(windows.map(\.id))
        cornerRadii = cornerRadii.filter { live.contains($0.key) }
        return windows.map { w in
            var w = w
            // (A widget's corners are always the same.)
            if w.widget { return w }
            if let r = cornerRadii[w.id] {
                w.cornerRadius = r
            } else if canSee, budget > 0, let measure = measureCorner {
                budget -= 1
                let r = measure(w, primaryTop) ?? SurfaceMap.windowCornerRadius
                cornerRadii[w.id] = r
                w.cornerRadius = r
            }
            return w
        }
    }

    /// How the app looks at a window's corner (see
    /// `AppDelegate.measureCornerRadius`): called on the tracker's queue.
    var measureCorner: ((TrackedWindow, _ primaryTop: CGFloat) -> CGFloat?)?

    /// Whether a process is an ordinary app with a Dock icon. Background
    /// agents — window managers, screenshot tools, menu-bar utilities — often
    /// keep invisible layer-0 windows; walking on those looks like walking on
    /// thin air.
    private var regularApp: [Int32: Bool] = [:]

    private func isRegularApp(_ pid: Int32) -> Bool {
        if let known = regularApp[pid] { return known }
        let policy = NSRunningApplication(processIdentifier: pid)?.activationPolicy
        let regular = policy == .regular
        regularApp[pid] = regular
        if regularApp.count > 200 { regularApp.removeAll() }
        return regular
    }

    /// Whether a process is Notification Center, by bundle rather than by
    /// its (translated) name.
    private var notificationCenter: [Int32: Bool] = [:]

    private func isNotificationCenter(_ pid: Int32) -> Bool {
        if let known = notificationCenter[pid] { return known }
        let nc = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.notificationcenterui"
        notificationCenter[pid] = nc
        if notificationCenter.count > 200 { notificationCenter.removeAll() }
        return nc
    }

    /// Each process's bundle identifier, looked up once.
    private var bundleIDs: [Int32: String] = [:]

    private func bundleID(_ pid: Int32) -> String? {
        if let known = bundleIDs[pid] { return known.isEmpty ? nil : known }
        let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        bundleIDs[pid] = id
        if bundleIDs.count > 200 { bundleIDs.removeAll() }
        return id.isEmpty ? nil : id
    }

    /// Whether a window fills a screen whose visible part (below the menu
    /// bar, clear of a Dock that is not hidden) is `visible`: maximized, or
    /// tiled to fill it — with or without the margins tiling can leave.
    static func fills(_ frame: CGRect, visible: CGRect) -> Bool {
        frame.contains(visible.insetBy(dx: maximizedSlack, dy: maximizedSlack))
    }
    /// How far short of each side of the screen a maximized window may stop.
    static let maximizedSlack: CGFloat = 24
    /// A desktop widget's card, inside its window (measured on macOS 26:
    /// the same for every size of widget), and how round its corners are.
    static let widgetMargin: CGFloat = 8
    static let widgetCornerRadius: CGFloat = 26

    private func snapshot(primaryTop: CGFloat, screens visibleFrames: [(CGRect, CGRect)], selfPID: Int32,
                          own: Set<CGWindowID>, titles: Bool, widgets: Bool)
        -> ([TrackedWindow], [CGRect], [CGWindowID: CGRect], [TrackedWindow], [CGRect], [CGRect]) {
        let screens = visibleFrames.map(\.0)
        // Desktop elements are listed too: the wallpaper is how a display
        // shows it is on an ordinary Space.
        let opts: CGWindowListOption = [.optionOnScreenOnly]
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return ([], [], [:], [], [], [])
        }
        // Notification banners: Notification Center's windows above the
        // ordinary ones (its desktop widgets sit down at the desktop).
        var banners: [CGWindowID: CGRect] = [:]
        for dict in info {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer > 0, layer < 1000,
                  let number = dict[kCGWindowNumber as String] as? Int,
                  let ownerPID = dict[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID != selfPID, isNotificationCenter(ownerPID),
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  let cg = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let frame = CGRect(x: cg.minX, y: primaryTop - cg.maxY, width: cg.width, height: cg.height)
            let screen = screens.first { $0.intersects(frame) } ?? screens.first ?? frame
            banners[CGWindowID(number)] = screen
        }
        // Displays with a desktop showing. An exclusive full-screen Space
        // has none — no wallpaper, no desktop icons — while a zoomed or
        // tiled window merely sits on top of one. (The menu bar is no
        // guide: on a notched display it stays listed, at full alpha, in
        // the black strip over a full-screen film.)
        var desktopScreens: [CGRect] = []
        for dict in info {
            guard let layer = dict[kCGWindowLayer as String] as? Int,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  let cg = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let owner = (dict[kCGWindowOwnerName as String] as? String) ?? ""
            let isDesktop = owner == "Wallpaper" || owner == "WallpaperAgent"
                || layer == WindowTracker.desktopIconLayer
                || (layer == WindowTracker.desktopLayer && owner != "Window Server")
            guard isDesktop else { continue }
            let frame = CGRect(x: cg.minX, y: primaryTop - cg.maxY, width: cg.width, height: cg.height)
            for sc in screens where frame.contains(sc.insetBy(dx: 2, dy: 2)) || sc.insetBy(dx: -2, dy: -2).contains(frame) && frame.width >= sc.width * 0.9 {
                if !desktopScreens.contains(sc) { desktopScreens.append(sc) }
            }
        }

        var out: [TrackedWindow] = []
        var fullScreens: [CGRect] = []
        var zoomed: [CGRect] = []
        var taken: [TrackedWindow] = []
        var depth = 0
        for dict in info {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = dict[kCGWindowNumber as String] as? Int,
                  let ownerPID = dict[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  let cg = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            let ours = ownerPID == selfPID
            if ours && !own.contains(CGWindowID(number)) { continue }
            let owner = (dict[kCGWindowOwnerName as String] as? String) ?? ""
            if !ours && WindowTracker.ignoredOwners.contains(owner) { continue }
            if let alpha = dict[kCGWindowAlpha as String] as? CGFloat, alpha < 0.35 { continue }
            guard cg.width > 130, cg.height > 90 else { continue }
            guard ours || isRegularApp(ownerPID) else { continue }

            // Flip into AppKit coordinates.
            let frame = CGRect(x: cg.minX, y: primaryTop - cg.maxY, width: cg.width, height: cg.height)
            let bundle = ours ? nil : bundleID(ownerPID)
            var titleHash: Int?
            if titles, Browsers.isBrowser(bundle), let title = dict[kCGWindowName as String] as? String {
                titleHash = title.hashValue
            }
            var tracked = TrackedWindow(id: CGWindowID(number), frame: frame, depth: depth, owner: owner,
                                        pid: ownerPID, bundleID: bundle, titleHash: titleHash)

            // A window covering a display, menu-bar strip included, is an
            // exclusive full-screen app: not furniture, and a sign to sit
            // still. One that stops just short of the top could be a
            // full-screen video on a notched display, which halts at the
            // camera housing — or a zoomed or tiled window under the menu
            // bar. Only the first has taken the desktop away with it; the
            // second is below.
            if let screen = screens.first(where: { sc in
                frame.contains(sc.insetBy(dx: 2, dy: 2))
                    || (!desktopScreens.contains(sc)
                        && sc.insetBy(dx: -2, dy: -2).contains(frame)
                        && frame.width >= sc.width * 0.98 && frame.height >= sc.height * 0.9)
            }) {
                if !fullScreens.contains(screen) { fullScreens.append(screen) }
                if !taken.contains(where: { $0.frame.intersects(screen) }) { taken.append(tracked) }
                continue
            }
            // A window filling the screen under the menu bar — maximized,
            // or dragged to the top and tiled — is as good as full screen:
            // its edges are the screen's, and there is nothing else on that
            // screen to see. So long as it is the front window there: one
            // with others in front of it is only the back of the room, with
            // no edges of its own to walk (see `SurfaceMap.rebuild`).
            // (Behind a full-screen one, it is on another Space.)
            if let (screen, _) = visibleFrames.first(where: { WindowTracker.fills(frame, visible: $0.1) }) {
                tracked.maximized = true
                if !fullScreens.contains(screen),
                   !out.contains(where: { $0.frame.intersects(screen) }) {
                    fullScreens.append(screen)
                    zoomed.append(screen)
                    taken.append(tracked)
                    continue
                }
            }
            out.append(tracked)
            depth += 1
            if out.count >= 28 { break }
        }
        // The widgets on the desktop: Notification Center's windows down
        // there, one each, just above the desktop icons — so behind every
        // window, which hides what it covers of them. Each window has a
        // clear margin round the card it shows; the card is what is stood on.
        if widgets {
            var count = 0
            for dict in info {
                guard let layer = dict[kCGWindowLayer as String] as? Int,
                      layer > WindowTracker.desktopIconLayer, layer < 0,
                      let number = dict[kCGWindowNumber as String] as? Int,
                      let ownerPID = dict[kCGWindowOwnerPID as String] as? Int32,
                      ownerPID != selfPID, isNotificationCenter(ownerPID),
                      let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                      let cg = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
                else { continue }
                if let alpha = dict[kCGWindowAlpha as String] as? CGFloat, alpha < 0.35 { continue }
                let card = CGRect(x: cg.minX, y: primaryTop - cg.maxY, width: cg.width, height: cg.height)
                    .insetBy(dx: WindowTracker.widgetMargin, dy: WindowTracker.widgetMargin)
                // (Nothing the size of a screen: that is no widget.)
                guard card.width > 130, card.height > 90,
                      !screens.contains(where: { card.width >= $0.width * 0.9 && card.height >= $0.height * 0.9 })
                else { continue }
                var tracked = TrackedWindow(id: CGWindowID(number), frame: card, depth: depth,
                                            owner: (dict[kCGWindowOwnerName as String] as? String) ?? "",
                                            pid: ownerPID, bundleID: "com.apple.notificationcenterui")
                tracked.widget = true
                tracked.cornerRadius = WindowTracker.widgetCornerRadius
                out.append(tracked)
                depth += 1
                count += 1
                if count >= 16 { break }
            }
        }
        // Whatever else is listed on a taken display is on a different
        // Space, or under the video: nothing to walk on.
        out.removeAll { w in fullScreens.contains { $0.intersects(w.frame) } }
        return (out, fullScreens, banners, taken, screens.filter { !desktopScreens.contains($0) }, zoomed)
    }
}

/// Web browsers, by bundle identifier: what they show in a window is a web
/// page, which the spider can climb about on when it fills the screen
/// (see WebPages.swift).
enum Browsers {
    /// Whole families share a prefix (Chrome's channels, Firefox's,
    /// Opera's…); a few stand alone.
    private static let prefixes = [
        "com.google.Chrome", "org.chromium.", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
        "com.operasoftware.", "company.thebrowser.", "org.mozilla.", "app.zen-browser.", "com.apple.Safari",
        "com.apple.SafariTechnologyPreview", "com.kagi.kagimacOS", "com.duckduckgo.macos.browser", "ai.perplexity.comet",
        "net.imput.helium", "com.sigmaos.sigmaos", "org.torproject.torbrowser", "com.naver.Whale",
        "ru.yandex.desktop.yandex-browser", "com.openai.atlas",
    ]

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return prefixes.contains { id.hasPrefix($0) }
    }
}
