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
        queue.async { [weak self] in
            guard let self else { return }
            let (result, fullScreens) = self.snapshot(primaryTop: primaryTop, screens: screens, selfPID: pid)
            DispatchQueue.main.async {
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

    private func snapshot(primaryTop: CGFloat, screens: [CGRect], selfPID: Int32) -> ([TrackedWindow], [CGRect]) {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return ([], [])
        }
        var out: [TrackedWindow] = []
        var fullScreens: [CGRect] = []
        var depth = 0
        for dict in info {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = dict[kCGWindowNumber as String] as? Int,
                  let ownerPID = dict[kCGWindowOwnerPID as String] as? Int32, ownerPID != selfPID,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  let cg = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            let owner = (dict[kCGWindowOwnerName as String] as? String) ?? ""
            if WindowTracker.ignoredOwners.contains(owner) { continue }
            if let alpha = dict[kCGWindowAlpha as String] as? CGFloat, alpha < 0.35 { continue }
            guard cg.width > 130, cg.height > 90 else { continue }
            guard isRegularApp(ownerPID) else { continue }

            // Flip into AppKit coordinates.
            let frame = CGRect(x: cg.minX, y: primaryTop - cg.maxY, width: cg.width, height: cg.height)

            // A window covering a display — or near enough: a full-screen
            // video on a notched display stops short of the camera housing —
            // is a full-screen app: not furniture, and a sign to sit still.
            if let taken = screens.first(where: { sc in
                frame.contains(sc.insetBy(dx: 2, dy: 2))
                    || (sc.insetBy(dx: -2, dy: -2).contains(frame)
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
        return (out, fullScreens)
    }
}
