// NSApplication: the run loop, the frame source and the input pump.
import Foundation
import QuartzCore
import WinSDK

nonisolated(unsafe) public var NSApp: NSApplication! = NSApplication.shared

public protocol NSApplicationDelegate: AnyObject {
    func applicationDidFinishLaunching(_ notification: Notification)
    func applicationWillTerminate(_ notification: Notification)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
}
extension NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {}
    public func applicationWillTerminate(_ notification: Notification) {}
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
}

public final class NSApplication: NSResponder, @unchecked Sendable {
    public enum ActivationPolicy: Int, Sendable { case regular, accessory, prohibited }
    public struct ModalResponse: RawRepresentable, Hashable, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let OK = Self(rawValue: 1), cancel = Self(rawValue: 0), stop = Self(rawValue: -1000), abort = Self(rawValue: -1001), `continue` = Self(rawValue: -1002), alertFirstButtonReturn = Self(rawValue: 1000), alertSecondButtonReturn = Self(rawValue: 1001), alertThirdButtonReturn = Self(rawValue: 1002) }
    public struct PresentationOptions: OptionSet, Sendable { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue } }
    public static let didChangeScreenParametersNotification = Notification.Name("NSApplicationDidChangeScreenParametersNotification")
    public static let didBecomeActiveNotification = Notification.Name("NSApplicationDidBecomeActiveNotification")
    public static let didResignActiveNotification = Notification.Name("NSApplicationDidResignActiveNotification")
    public static let willTerminateNotification = Notification.Name("NSApplicationWillTerminateNotification")

    public static let shared: NSApplication = { let a = NSApplication(); return a }()
    public weak var delegate: NSApplicationDelegate?
    public private(set) var windows: [NSWindow] = []
    var keyWindowStore: NSWindow?
    public var keyWindow: NSWindow? { keyWindowStore }
    public var mainWindow: NSWindow? { keyWindowStore }
    public var isActive: Bool { windows.contains { $0.isKeyWindow } }
    public var isRunning: Bool { running }
    public var currentEvent: NSEvent? = nil
    public var mainMenu: NSMenu?
    public var servicesMenu: NSMenu?
    public var windowsMenu: NSMenu?
    public var helpMenu: NSMenu?
    public var applicationIconImage: NSImage?
    public var appearance: NSAppearance?
    public var presentationOptions: PresentationOptions = []
    public var modalWindow: NSWindow? { nil }
    public var isHidden: Bool { false }
    public var occlusionState: NSWindow.OcclusionState { .visible }
    public var dockTile: AnyObject? { nil }
    public var effectiveAppearance: NSAppearance { appearance ?? NSAppearance.system }
    private var running = false
    var pointerInjected: Bool { false }

    override init() {
        super.init()
        _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4))
        ScreenList.refresh()
        WindowListBridge.install()
        CATransaction.onCommit = nil
    }
    public required init?(coder: NSCoder) { fatalError() }
    func register(_ w: NSWindow) { if !windows.contains(where: { $0 === w }) { windows.append(w) } }
    public func setActivationPolicy(_ p: ActivationPolicy) -> Bool { true }
    public func activate(ignoringOtherApps: Bool) {}
    public func activate() {}
    public func deactivate() {}
    public func hide(_ s: Any?) {}
    public func unhide(_ s: Any?) {}
    public func arrangeInFront(_ s: Any?) {}
    public func requestUserAttention(_ t: Int) -> Int { 0 }
    public func orderFrontStandardAboutPanel(_ s: Any?) {}
    public func runModal(for w: NSWindow) -> ModalResponse {
        modal = nil
        w.makeKeyAndOrderFront(nil)
        while modal == nil { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
        return modal!
    }
    private var modal: ModalResponse?
    public func stopModal() { modal = .stop }
    public func stopModal(withCode c: ModalResponse) { modal = c }
    public func abortModal() { modal = .abort }
    public func stop(_ s: Any?) { running = false }
    public func terminate(_ s: Any?) {
        delegate?.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        NSStatusBar.removeAll()
        ExitProcess(0)
    }
    @discardableResult public func sendAction(_ a: Selector, to t: Any?, from s: Any?) -> Bool {
        if a.send(to: t as AnyObject?, from: s) { return true }
        return false
    }
    public func target(forAction a: Selector) -> Any? { nil }
    public func nextEvent(matching: NSEvent.EventTypeMask, until: Date?, inMode: RunLoop.Mode, dequeue: Bool) -> NSEvent? { nil }
    public func sendEvent(_ e: NSEvent) { e.window?.dispatch(e) }
    public func postEvent(_ e: NSEvent, atStart: Bool) { e.window?.dispatch(e) }
    public func beginModalSession(for w: NSWindow) -> Int { 0 }
    public func endModalSession(_ s: Int) {}

    // MARK: The clock

    private var dirtyWindows: [ObjectIdentifier: NSWindow] = [:]
    func windowChanged(_ w: NSWindow) { dirtyWindows[ObjectIdentifier(w)] = w }
    private var beatQueued = false
    private let beatLock = NSLock()
    private var inFrame = false
    /// Non-zero inside a Win32 modal loop (menu tracking, dragging a title bar), where only a timer gets through.
    var modalDepth = 0
    private var messageWindow: HWND?

    public func run() {
        running = true
        delegate?.applicationDidFinishLaunching(Notification(name: Notification.Name("NSApplicationDidFinishLaunchingNotification")))
        startBeat()
        while running { _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.25)) }
    }

    /// The display's beat, on its own thread: DwmFlush waits for the next composition, and a frame is queued on the main
    /// thread unless the last has not finished. Waiting inside the frame instead costs 10 ms a frame in the run loop.
    private func startBeat() {
        let dwm = "dwmapi.dll".withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
        typealias Flush = @convention(c) () -> Int32
        let flush = unsafeBitCast(GetProcAddress(dwm, "DwmFlush"), to: Flush.self)
        let t = Thread { [weak self] in
            while let self, self.running {
                if flush() != 0 { Thread.sleep(forTimeInterval: 1.0 / 60.0) }
                self.beatLock.lock()
                let busy = self.beatQueued
                if !busy { self.beatQueued = true }
                self.beatLock.unlock()
                if busy { continue }
                DispatchQueue.main.async {
                    self.beatLock.lock(); self.beatQueued = false; self.beatLock.unlock()
                    self.frame()
                }
            }
        }
        t.qualityOfService = .userInteractive
        t.start()
    }

    /// Everything a display beat does.
    func frame() {
        guard !inFrame else { return }
        inFrame = true
        defer { inFrame = false }
        pumpMessages()
        refreshPointer()
        let now = CACurrentMediaTime()
        for l in CADisplayLink.active { l.beat(now: now) }
        compositeChanged()
        if modalDepth > 0 { _ = RunLoop.main.run(mode: .default, before: Date()) }
    }
    func compositeChanged() {
        for w in windows where w.animating { dirtyWindows[ObjectIdentifier(w)] = w }
        guard !dirtyWindows.isEmpty else { return }
        let list = dirtyWindows.values
        dirtyWindows.removeAll(keepingCapacity: true)
        for w in list { w.composite() }
    }
    private func pumpMessages() {
        guard modalDepth == 0 else { return }
        var msg = MSG()
        var n = 0
        while n < 64, PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
            n += 1
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
        }
    }

    // MARK: The pointer, polled each frame, and global monitors

    private var lastButtons = 0
    private var lastLocation = CGPoint(x: -99999, y: -99999)
    func refreshPointer() {
        var p = POINT()
        if GetCursorPos(&p) { NSEvent.mouseLocation = pixelToWorld(x: p.x, y: p.y) }
        var b = 0
        func down(_ vk: Int32) -> Bool { (UInt16(bitPattern: GetAsyncKeyState(vk)) & 0x8000) != 0 }
        if down(VK_LBUTTON) { b |= 1 }
        if down(VK_RBUTTON) { b |= 2 }
        if down(VK_MBUTTON) { b |= 4 }
        NSEvent.pressedMouseButtons = b
        var f = NSEvent.ModifierFlags()
        if down(VK_SHIFT) { f.insert(.shift) }
        if down(VK_CONTROL) { f.insert(.control) }
        if down(VK_MENU) { f.insert(.option) }
        if down(VK_LWIN) || down(VK_RWIN) { f.insert(.command) }
        NSEvent.modifierFlagsNow = f
        guard !NSEvent.monitors.isEmpty else { lastButtons = b; return }
        func send(_ t: NSEvent.EventType) {
            let e = NSEvent()
            e.type = t
            e.locationInWindow = NSEvent.mouseLocation
            e.modifierFlags = f
            e.timestamp = CACurrentMediaTime()
            NSEvent.sendGlobal(e)
        }
        if b & 1 != lastButtons & 1 { send(b & 1 != 0 ? .leftMouseDown : .leftMouseUp) }
        if b & 2 != lastButtons & 2 { send(b & 2 != 0 ? .rightMouseDown : .rightMouseUp) }
        if NSEvent.mouseLocation != lastLocation { send(b & 1 != 0 ? .leftMouseDragged : .mouseMoved); lastLocation = NSEvent.mouseLocation }
        lastButtons = b
    }
}

// MARK: Appearance

public final class NSAppearance: NSObject, @unchecked Sendable {
    public struct Name: Hashable, Sendable { public let rawValue: String; public init(_ s: String) { rawValue = s }; public init(rawValue: String) { self.rawValue = rawValue }
        public static let aqua = Name("NSAppearanceNameAqua"), darkAqua = Name("NSAppearanceNameDarkAqua"), vibrantLight = Name("NSAppearanceNameVibrantLight"), vibrantDark = Name("NSAppearanceNameVibrantDark") }
    public let name: Name
    public init?(named n: Name) { name = n }
    private init(_ n: Name) { name = n }
    public var isDark: Bool { name == .darkAqua || name == .vibrantDark }
    public func bestMatch(from names: [Name]) -> Name? { names.first { $0 == name } ?? names.first }
    nonisolated(unsafe) public static var current: NSAppearance? = nil
    public static var currentDrawing: NSAppearance { current ?? system }
    /// Follows Windows' app theme, as the Mac app follows the system's.
    public static var system: NSAppearance {
        var value: DWORD = 1
        var size = DWORD(4)
        let ok = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize".withCString(encodedAs: UTF16.self) { k in
            "AppsUseLightTheme".withCString(encodedAs: UTF16.self) { v in RegGetValueW(HKEY_CURRENT_USER, k, v, DWORD(RRF_RT_REG_DWORD), nil, &value, &size) }
        }
        return ok == 0 && value == 0 ? dark : light
    }
    private static let dark = NSAppearance(.darkAqua), light = NSAppearance(.aqua)
    public func performAsCurrentDrawingAppearance(_ f: () -> Void) {
        let p = NSAppearance.current
        NSAppearance.current = self
        f()
        NSAppearance.current = p
    }
}

// MARK: Screens

enum ScreenList {
    static func refresh() {
        let dpi = CGFloat(GetDpiForSystem())
        NSScreen.primaryScale = dpi / 96
        let k = NSScreen.primaryScale
        NSScreen.primaryPixelHeight = CGFloat(GetSystemMetrics(SM_CYSCREEN))
        var found: [NSScreen] = []
        withUnsafeMutablePointer(to: &found) { ptr in
            _ = EnumDisplayMonitors(nil, nil, { mon, _, _, data in
                var info = MONITORINFO()
                info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
                guard GetMonitorInfoW(mon, &info) else { return true }
                let k = NSScreen.primaryScale, H = NSScreen.primaryPixelHeight
                let w = info.rcWork
                // The work area is the screen (spec 2.8): a taskbar is full width and not a Dock.
                let f = CGRect(x: CGFloat(w.left) / k, y: (H - CGFloat(w.bottom)) / k, width: CGFloat(w.right - w.left) / k, height: CGFloat(w.bottom - w.top) / k)
                let s = NSScreen(frame: f, visibleFrame: f, backingScaleFactor: k)
                let list = UnsafeMutablePointer<[NSScreen]>(bitPattern: Int(data))!
                if info.dwFlags & DWORD(MONITORINFOF_PRIMARY) != 0 { list.pointee.insert(s, at: 0) } else { list.pointee.append(s) }
                s.screenNumber = list.pointee.count
                return true
            }, LPARAM(Int(bitPattern: ptr)))
        }
        _ = k
        if ProcessInfo.processInfo.environment["SPIDER_SHIM_SCREEN"] == nil { NSScreen.screens = found }
    }
}

// MARK: The window list, as CGWindowListCopyWindowInfo reports it

enum WindowListBridge {
    nonisolated(unsafe) static var collected: [[String: Any]] = []
    private static let dwm = "dwmapi.dll".withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
    typealias DwmAttr = @convention(c) (HWND?, DWORD, UnsafeMutableRawPointer, DWORD) -> Int32
    static let attr: DwmAttr = unsafeBitCast(GetProcAddress(dwm, "DwmGetWindowAttribute"), to: DwmAttr.self)
    static let shell: Set<String> = ["Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow",
                                     "Windows.UI.Core.CoreWindow", "XamlExplorerHostIslandWindow", "TopLevelWindowForOverflowXamlIsland"]
    static func className(_ h: HWND?) -> String {
        var buf = [WCHAR](repeating: 0, count: 256)
        let n = GetClassNameW(h, &buf, 256)
        return String(decoding: buf[0..<Int(max(n, 0))], as: UTF16.self)
    }
    static func install() {
        CGWindowListProvider = {
            var list: [[String: Any]] = []
            let primary = NSScreen.screens.first?.frame ?? .zero
            // The Mac sees a window for the desktop picture: the tracker reads it as "this screen shows its desktop".
            for s in NSScreen.screens {
                list.append([kCGWindowLayer: Int(CGWindowLevelForKey(.desktopWindow)), kCGWindowNumber: 1, kCGWindowOwnerPID: Int32(0),
                             kCGWindowOwnerName: "Wallpaper",
                             kCGWindowBounds: ["X": s.frame.minX, "Y": primary.maxY - s.frame.maxY, "Width": s.frame.width, "Height": s.frame.height] as [String: CGFloat]])
            }
            let top = primary.maxY
            collected = []
            _ = EnumWindows({ hwnd, _ in
                guard let hwnd, IsWindowVisible(hwnd), !IsIconic(hwnd) else { return true }
                let style = GetWindowLongPtrW(hwnd, GWL_STYLE), ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
                if style & Int64(WS_CHILD) != 0 || ex & Int64(WS_EX_TOOLWINDOW) != 0 || ex & Int64(WS_EX_NOACTIVATE) != 0 { return true }
                var cloaked: DWORD = 0
                if attr(hwnd, 14, &cloaked, 4) == 0, cloaked != 0 { return true }
                let cls = className(hwnd)
                if shell.contains(cls) { return true }
                var r = RECT()
                if attr(hwnd, 9, &r, DWORD(MemoryLayout<RECT>.size)) != 0 { _ = GetWindowRect(hwnd, &r) }
                var pid: DWORD = 0
                _ = GetWindowThreadProcessId(hwnd, &pid)
                var alpha: CGFloat = 1
                if ex & Int64(WS_EX_LAYERED) != 0 {
                    var a: BYTE = 255, flags: DWORD = 0
                    if GetLayeredWindowAttributes(hwnd, nil, &a, &flags), flags & DWORD(LWA_ALPHA) != 0 { alpha = CGFloat(a) / 255 }
                }
                let n = Int(bitPattern: UnsafeRawPointer(hwnd)) & 0x7FFF_FFFF
                let k = NSScreen.primaryScale
                let t = NSScreen.primaryPixelHeight / k
                let dy = t - (NSScreen.screens.first?.frame.maxY ?? t)
                collected.append([kCGWindowLayer: 0, kCGWindowNumber: n, kCGWindowOwnerPID: Int32(pid), kCGWindowOwnerName: cls,
                                  kCGWindowAlpha: alpha,
                                  kCGWindowBounds: ["X": CGFloat(r.left) / k, "Y": CGFloat(r.top) / k - dy,
                                                    "Width": CGFloat(r.right - r.left) / k, "Height": CGFloat(r.bottom - r.top) / k] as [String: CGFloat]])
                return true
            }, 0)
            _ = top
            list += collected
            return list
        }
        NSRunningApplication.lookup = { pid in
            let a = NSRunningApplication()
            a.processIdentifier = pid
            a.activationPolicy = .regular
            a.bundleIdentifier = "pid.\(pid)"
            return a
        }
        CGCornersAvailable = true
    }
}

enum ShellOpen {
    @discardableResult static func open(_ target: String) -> Bool {
        target.withCString(encodedAs: UTF16.self) { t in
            "open".withCString(encodedAs: UTF16.self) { v in
                Int(bitPattern: ShellExecuteW(nil, v, t, nil, nil, SW_SHOWNORMAL)) > 32
            }
        }
    }
    static func reveal(_ path: String) {
        let arg = "/select,\"\(path.replacingOccurrences(of: "/", with: "\\"))\""
        arg.withCString(encodedAs: UTF16.self) { a in
            "explorer.exe".withCString(encodedAs: UTF16.self) { e in
                _ = ShellExecuteW(nil, nil, e, a, nil, SW_SHOWNORMAL)
            }
        }
    }
}

extension ProcessInfo {
    /// Battery Saver. The sensors phase fills this in.
    public var isLowPowerModeEnabled: Bool { false }
}
