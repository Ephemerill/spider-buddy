// Proof of concept: the Mac's spider on the real Windows desktop.
//
// Everything about the spider, the surface map and the window tracker is the Mac's code, compiled unchanged. This file
// only does what the Mac's AppDelegate and OverlayWindow do for the spider's own window: reports screens and windows,
// shows the picture in a layered window, flips click-through on each tick, and hands over mouse events. No silk,
// creatures, menus or UI yet: those come with the real app shell.
import AppKit
import WinSDK

setvbuf(stdout, nil, _IONBF, 0)

// MARK: Screens and units

_ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4))

let dpi = CGFloat(GetDpiForSystem())
/// Physical pixels per point. Points here are what the Mac means by points: 1 at 100% scaling.
let k = dpi / 96
let screenWpx = CGFloat(GetSystemMetrics(SM_CXSCREEN)), screenHpx = CGFloat(GetSystemMetrics(SM_CYSCREEN))
let screenW = screenWpx / k, screenH = screenHpx / k

var work = RECT()
_ = withUnsafeMutablePointer(to: &work) { SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, UnsafeMutableRawPointer($0), 0) }
let visible = CGRect(x: CGFloat(work.left) / k, y: (screenHpx - CGFloat(work.bottom)) / k,
                     width: CGFloat(work.right - work.left) / k, height: CGFloat(work.bottom - work.top) / k)
NSScreen.screens = [NSScreen(frame: CGRect(x: 0, y: 0, width: screenW, height: screenH), visibleFrame: visible, backingScaleFactor: k)]

func world(_ p: POINT) -> V2 { V2(CGFloat(p.x) / k, (screenHpx - CGFloat(p.y)) / k) }

// MARK: Windows, reported the way CGWindowListCopyWindowInfo does

let dwm = "dwmapi.dll".withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
typealias DwmAttr = @convention(c) (HWND?, DWORD, UnsafeMutableRawPointer, DWORD) -> Int32
typealias DwmFlushFn = @convention(c) () -> Int32
let dwmGetAttr = unsafeBitCast(GetProcAddress(dwm, "DwmGetWindowAttribute"), to: DwmAttr.self)
let dwmFlush = unsafeBitCast(GetProcAddress(dwm, "DwmFlush"), to: DwmFlushFn.self)

func className(_ h: HWND?) -> String {
    var buf = [WCHAR](repeating: 0, count: 256)
    let n = GetClassNameW(h, &buf, 256)
    return String(decoding: buf[0..<Int(max(n, 0))], as: UTF16.self)
}

nonisolated(unsafe) var enumerated: [[String: Any]] = []
let shellClasses: Set<String> = ["Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow",
                                 "Windows.UI.Core.CoreWindow", "XamlExplorerHostIslandWindow", "TopLevelWindowForOverflowXamlIsland"]

CGWindowListProvider = {
    var list: [[String: Any]] = []
    // The Mac sees a window for the desktop picture: the tracker reads it as "this screen shows its desktop".
    list.append([kCGWindowLayer: Int(CGWindowLevelForKey(.desktopWindow)), kCGWindowNumber: 1, kCGWindowOwnerPID: Int32(0),
                 kCGWindowOwnerName: "Wallpaper",
                 kCGWindowBounds: ["X": 0 as CGFloat, "Y": 0 as CGFloat, "Width": screenW, "Height": screenH]])
    enumerated = []
    _ = EnumWindows({ hwnd, _ in
        guard let hwnd, IsWindowVisible(hwnd), !IsIconic(hwnd) else { return true }
        let style = GetWindowLongPtrW(hwnd, GWL_STYLE), ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
        if style & Int64(WS_CHILD) != 0 || ex & Int64(WS_EX_TOOLWINDOW) != 0 || ex & Int64(WS_EX_NOACTIVATE) != 0 { return true }
        var cloaked: DWORD = 0
        if dwmGetAttr(hwnd, 14, &cloaked, 4) == 0, cloaked != 0 { return true }
        let cls = className(hwnd)
        if shellClasses.contains(cls) { return true }
        var r = RECT()
        if dwmGetAttr(hwnd, 9, &r, DWORD(MemoryLayout<RECT>.size)) != 0 { _ = GetWindowRect(hwnd, &r) }
        var pid: DWORD = 0
        _ = GetWindowThreadProcessId(hwnd, &pid)
        var alpha: CGFloat = 1
        if ex & Int64(WS_EX_LAYERED) != 0 {
            var a: BYTE = 255, flags: DWORD = 0
            if GetLayeredWindowAttributes(hwnd, nil, &a, &flags), flags & DWORD(LWA_ALPHA) != 0 { alpha = CGFloat(a) / 255 }
        }
        let n = Int(bitPattern: UnsafeRawPointer(hwnd)) & 0x7FFF_FFFF
        enumerated.append([kCGWindowLayer: 0, kCGWindowNumber: n, kCGWindowOwnerPID: Int32(pid), kCGWindowOwnerName: cls,
                           kCGWindowAlpha: alpha,
                           kCGWindowBounds: ["X": CGFloat(r.left) / k, "Y": CGFloat(r.top) / k,
                                             "Width": CGFloat(r.right - r.left) / k, "Height": CGFloat(r.bottom - r.top) / k]])
        return true
    }, 0)
    list += enumerated
    return list
}
NSRunningApplication.lookup = { pid in
    let a = NSRunningApplication()
    a.processIdentifier = pid
    a.activationPolicy = .regular
    a.bundleIdentifier = "pid.\(pid)"
    return a
}

// MARK: The spider, as AppDelegate sets it up

let map = SurfaceMap()
let spider = Spider(map: map)
spider.apply(design: SpiderDesign.load())
let scale = spider.config.scale
map.standoff = -SpiderRenderer.ground * scale
map.rebuild(windows: [])

let tracker = WindowTracker()
// Windows 11's corners: 8 px at 100%. A maximized window has none.
CGCornersAvailable = true
tracker.measureCorner = { w, _ in
    w.frame.width >= visible.width - 4 && w.frame.height >= visible.height - 4 ? 0 : 8
}
tracker.onUpdate = { windows, fullScreens, docks, _ in
    map.rebuild(windows: windows, cinema: fullScreens, zoomed: [], docks: docks)
}
tracker.start()

// MARK: The layered window

/// The Mac's window has 68 points of slack around the sprite; a bubble needs room above and beside it as well.
let side = SpiderRenderer.spriteSide(for: scale) + 68 + (240 * scale).rounded()
let sidePx = Int((side * k).rounded(.up))
nonisolated(unsafe) var pressed = false, dragging = false
nonisolated(unsafe) var pressedAt = V2.zero, pressTime = 0.0
nonisolated(unsafe) var samples: [(p: V2, t: Double)] = []
nonisolated(unsafe) var running = true

func cursorWorld() -> V2 { var p = POINT(); _ = GetCursorPos(&p); return world(p) }
let now = { CACurrentMediaTime() }

func wndProc(_ h: HWND?, _ m: UINT, _ w: WPARAM, _ l: LPARAM) -> LRESULT {
    switch Int32(m) {
    case WM_MOUSEACTIVATE:
        return LRESULT(MA_NOACTIVATE)
    case WM_LBUTTONDOWN:
        let p = cursorWorld()
        pressedAt = p; pressTime = now(); samples = [(p, pressTime)]
        SetCapture(h)
        spider.beginGrab(at: p)
        dragging = true
        return 0
    case WM_LBUTTONDBLCLK:
        spider.celebrate()
        dragging = false
        return 0
    case WM_MOUSEMOVE:
        if dragging {
            let p = cursorWorld()
            spider.moveGrab(to: p)
            samples.append((p, now()))
            if samples.count > 8 { samples.removeFirst(samples.count - 8) }
        }
        return 0
    case WM_LBUTTONUP, WM_CAPTURECHANGED:
        ReleaseCapture()
        guard dragging else { return 0 }
        dragging = false
        let p = cursorWorld(), t = now()
        // Velocity from the recent samples, as in the Mac's mouseUp.
        var v = V2.zero
        if let first = samples.first, samples.count > 1 {
            if t - first.t < 0.22 {
                v = (p - first.p) / CGFloat(max(t - first.t, 0.008))
            } else if let recent = samples.last(where: { t - $0.t > 0.04 }) {
                v = (p - recent.p) / CGFloat(max(t - recent.t, 0.008))
            }
        }
        if p.distance(to: pressedAt) < 4 && t - pressTime < 0.35 {
            spider.endGrab(throwVelocity: .zero)
            spider.poke()
        } else {
            spider.endGrab(throwVelocity: v)
        }
        samples = []
        return 0
    case WM_MOUSEWHEEL:
        let delta = CGFloat(Int16(truncatingIfNeeded: (Int(w) >> 16) & 0xFFFF)) / CGFloat(WHEEL_DELTA)
        spider.scroll(delta, precise: false)
        return 0
    case WM_RBUTTONDOWN:
        let menu = CreatePopupMenu()
        "Quit Spider".withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menu, UINT(MF_STRING), 1, $0) }
        var pt = POINT(); _ = GetCursorPos(&pt)
        _ = SetForegroundWindow(h)
        let c = TrackPopupMenu(menu, UINT(TPM_RETURNCMD | TPM_NONOTIFY), pt.x, pt.y, 0, h, nil)
        DestroyMenu(menu)
        if c { running = false }   // (Only one item. Swift sees TrackPopupMenu's result as a BOOL.)
        return 0
    case WM_DESTROY:
        running = false
        return 0
    default:
        return DefWindowProcW(h, m, w, l)
    }
}

let clsName = Array("SpiderBuddyOverlay".utf16) + [0]
var wc = WNDCLASSW()
wc.style = UINT(CS_DBLCLKS)
wc.lpfnWndProc = { h, m, w, l in wndProc(h, m, w, l) }
wc.hInstance = GetModuleHandleW(nil)
wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
clsName.withUnsafeBufferPointer { b in
    wc.lpszClassName = b.baseAddress
    _ = RegisterClassW(&wc)
}
let hwnd = clsName.withUnsafeBufferPointer { b in
    CreateWindowExW(DWORD(WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT), b.baseAddress, nil,
                    DWORD(WS_POPUP), 0, 0, Int32(sidePx), Int32(sidePx), nil, nil, GetModuleHandleW(nil), nil)
}
_ = ShowWindow(hwnd, SW_SHOWNA)

// A top-down premultiplied BGRA DIB that Skia draws straight into. No copies.
var bmi = BITMAPINFO()
bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
bmi.bmiHeader.biWidth = Int32(sidePx)
bmi.bmiHeader.biHeight = -Int32(sidePx)
bmi.bmiHeader.biPlanes = 1
bmi.bmiHeader.biBitCount = 32
bmi.bmiHeader.biCompression = DWORD(BI_RGB)
var bits: UnsafeMutableRawPointer? = nil
let screenDC = GetDC(nil)
let memDC = CreateCompatibleDC(screenDC)
let dib = CreateDIBSection(memDC, &bmi, UINT(DIB_RGB_COLORS), &bits, nil, 0)
_ = SelectObject(memDC, dib)
let ctx = CGContext(data: bits, width: sidePx, height: sidePx, bitsPerComponent: 8, bytesPerRow: sidePx * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
ctx.scaleBy(x: k, y: k)

nonisolated(unsafe) var clickThrough = true
func flipClicks(wants: Bool) {
    guard wants == clickThrough else { return }
    clickThrough = !wants
    let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
    _ = SetWindowLongPtrW(hwnd, GWL_EXSTYLE, wants ? ex & ~Int64(WS_EX_TRANSPARENT) : ex | Int64(WS_EX_TRANSPARENT))
}

/// Puts up one pose: the picture is drawn at its exact fractional spot, the window moved to whole pixels.
func present(_ pose: SpiderPose, hitDisc: Bool) {
    let cx = pose.pos.x * k - CGFloat(sidePx) / 2
    let by = pose.pos.y * k - CGFloat(sidePx) / 2
    let left = cx.rounded(.down), bottom = by.rounded(.down)
    memset(bits, 0, sidePx * sidePx * 4)
    ctx.saveGState()
    ctx.translateBy(x: (cx - left) / k, y: (by - bottom) / k)
    if hitDisc {
        // A layered window lets clicks through wherever alpha is 0. The Mac takes the whole disc around the body,
        // and so does this: alpha 1 of 255 is invisible but solid.
        let r = 30 * scale
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1.0 / 255.0))
        ctx.fillEllipse(in: CGRect(x: side / 2 - r, y: side / 2 - r, width: r * 2, height: r * 2))
    }
    SpiderRenderer.draw(pose, in: ctx, bounds: CGRect(x: 0, y: 0, width: side, height: side))
    ctx.restoreGState()
    var dst = POINT(x: LONG(left), y: LONG(screenHpx - bottom - CGFloat(sidePx)))
    var size = SIZE(cx: LONG(sidePx), cy: LONG(sidePx))
    var src = POINT(x: 0, y: 0)
    var blend = BLENDFUNCTION(BlendOp: BYTE(AC_SRC_OVER), BlendFlags: 0, SourceConstantAlpha: 255, AlphaFormat: BYTE(AC_SRC_ALPHA))
    _ = UpdateLayeredWindow(hwnd, screenDC, &dst, &size, memDC, &src, 0, &blend, DWORD(ULW_ALPHA))
}

// MARK: The clock

let seconds = CommandLine.arguments.dropFirst().first.flatMap { Double($0) } ?? 0
let began = now()
var last = now()
var frames = 0, statT = now(), workSum = 0.0, drawSum = 0.0
var lastCursor = V2(-99999, -99999)
let log = ProcessInfo.processInfo.environment["SPIDER_HOST_LOG"] != nil
var msg = MSG()
print("spider host: \(Int(screenW))x\(Int(screenH)) pt, \(k)x, visible \(visible), sprite window \(sidePx) px")

while running {
    while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
        TranslateMessage(&msg)
        DispatchMessageW(&msg)
    }
    // The tracker's timer and everything the Mac sends to the main queue.
    _ = RunLoop.main.run(mode: .default, before: Date())
    let t0 = now()
    let cursor = cursorWorld()
    // Whether clicks reach us is decided every tick (a stale answer is a spider you cannot pick up).
    let wants = spider.isHeld || spider.hitTest(cursor)
    flipClicks(wants: wants)
    let dt = CGFloat(min(max(t0 - last, 1.0 / 240.0), 1.0 / 20.0))
    last = t0
    if cursor.distance(to: lastCursor) > 0.4 { lastCursor = cursor; spider.setCursor(cursor) }
    spider.update(dt: dt)
    let pose = spider.pose()
    let t1 = now()
    present(pose, hitDisc: wants)
    let t2 = now()
    flipClicks(wants: spider.isHeld || spider.hitTest(cursor))
    frames += 1; workSum += t1 - t0; drawSum += t2 - t1
    if log, t2 - statT > 2 {
        let f = Double(frames)
        print(String(format: "%.1f fps | update %.2f ms | draw+present %.2f ms | %@ at (%.0f, %.0f)", f / (t2 - statT), workSum / f * 1000, drawSum / f * 1000, spider.debugState, pose.pos.x, pose.pos.y))
        frames = 0; workSum = 0; drawSum = 0; statT = t2
    }
    if seconds > 0, t2 - began > seconds { running = false }
    _ = dwmFlush()
}
