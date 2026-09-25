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
    /// screen's edges, and it is not furniture to play on).
    var onUpdate: (([TrackedWindow], _ fullScreens: [CGRect]) -> Void)?

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
    func pollNow() { poll() }

    private func poll()  {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map { $0.frame }
        let pid = selfPID
        let own = ownFurniture
        queue.async { [weak self] in
            guard let self else { return }
            let (result, fullScreens, banners) = self.snapshot(primaryTop: primaryTop, screens: screens, selfPID: pid, own: own)
            DispatchQueue.main.async {
                if let before = self.banners {
                    for (id, screen) in banners where !before.contains(id) { self.onBanner?(screen) }
                }
                self.banners = Set(banners.keys)
                var frames: [CGWindowID: CGRect] = [:]
                var changed = false
                for w in result {
                    frames[w.id] = w.frame
                    if self.lastFrames[w.id] != w.frame { changed = true }
                }
                if frames.count != self.lastFrames.count { changed = true }
                self.lastFrames = frames
                if changed { self.busyUntil = CACurrentMediaTime() + 0.8 }
                self.onUpdate?(result, fullScreens)
            }
        }
    }

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

    private func snapshot(primaryTop: CGFloat, screens: [CGRect], selfPID: Int32,
                          own: Set<CGWindowID>) -> ([TrackedWindow], [CGRect], [CGWindowID: CGRect]) {
        // Desktop elements are listed too: the wallpaper is how a display
        // shows it is on an ordinary Space.
        let opts: CGWindowListOption = [.optionOnScreenOnly]
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return ([], [], [:])
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

            // A window covering a display, menu-bar strip included, is an
            // exclusive full-screen app: not furniture, and a sign to sit
            // still. One that stops just short of the top could be a
            // full-screen video on a notched display, which halts at the
            // camera housing — or a merely zoomed or tiled window under the
            // menu bar. Only the first has taken the desktop away with it;
            // the second is ordinary furniture, and the spider climbs it
            // like any other.
            if let taken = screens.first(where: { sc in
                frame.contains(sc.insetBy(dx: 2, dy: 2))
                    || (!desktopScreens.contains(sc)
                        && sc.insetBy(dx: -2, dy: -2).contains(frame)
                        && frame.width >= sc.width * 0.98 && frame.height >= sc.height * 0.9)
            }) {
                if !fullScreens.contains(taken) { fullScreens.append(taken) }
                continue
            }
            out.append(TrackedWindow(id: CGWindowID(number), frame: frame, depth: depth, owner: owner))
            depth += 1
            if out.count >= 28 { break }
        }
        // Whatever else is listed on a taken display is on a different
        // Space, or under the video: nothing to walk on.
        out.removeAll { w in fullScreens.contains { $0.intersects(w.frame) } }
        return (out, fullScreens, banners)
    }
}
