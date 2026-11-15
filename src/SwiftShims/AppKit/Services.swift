// System services the Mac app reaches through AppKit and friends, done the Windows way:
//   - lock, unlock, sleep, wake and display sleep, as the notifications the Mac posts for them
//   - pictures of windows (CGWindowListCreateImage), through GDI
//   - the desktop picture and how it is placed
//   - CPU time (getrusage)
import Foundation
import CoreGraphics
import WinSDK

// MARK: Thread messages

/// Messages posted to the main thread rather than a window (WM_HOTKEY from RegisterHotKey with no window) go here.
nonisolated(unsafe) public var NSThreadMessageHook: ((UINT, WPARAM, LPARAM) -> Void)?

// MARK: Distributed notifications

/// The Mac's system-wide notification centre. On Windows only the session's own events arrive through it
/// (`com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`), posted by `SessionWatch`.
open class DistributedNotificationCenter: NotificationCenter, @unchecked Sendable {
    nonisolated(unsafe) private static let shared = DistributedNotificationCenter()
    open class func `default`() -> DistributedNotificationCenter { shared }
}

// MARK: Session: lock, sleep, displays

enum SessionWatch {
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var displayOn: Bool?
    static let WM_WTSSESSION_CHANGE: UINT = 0x02B1
    static let WM_POWERBROADCAST_: UINT = 0x0218
    // GUID_CONSOLE_DISPLAY_STATE {6FE69556-704A-47A0-8F24-C28D936FDA47}
    nonisolated(unsafe) static var displayGuid = GUID(Data1: 0x6FE69556, Data2: 0x704A, Data3: 0x47A0, Data4: (0x8F, 0x24, 0xC2, 0x8D, 0x93, 0x6F, 0xDA, 0x47))

    static func install() {
        guard !installed else { return }
        installed = true
        guard let hwnd = MessageWindow.shared.hwnd else { return }
        let wts = "wtsapi32.dll".withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
        typealias Register = @convention(c) (HWND?, DWORD) -> WindowsBool
        if let wts, let p = GetProcAddress(wts, "WTSRegisterSessionNotification") {
            _ = unsafeBitCast(p, to: Register.self)(hwnd, 0)   // NOTIFY_FOR_THIS_SESSION
        }
        _ = RegisterPowerSettingNotification(hwnd, &displayGuid, 0)   // DEVICE_NOTIFY_WINDOW_HANDLE
    }

    private static func post(_ name: Notification.Name) {
        NSWorkspace.shared.notificationCenter.post(name: name, object: NSWorkspace.shared)
    }

    static func handle(_ m: UINT, _ w: WPARAM, _ l: LPARAM) -> LRESULT? {
        switch m {
        case WM_WTSSESSION_CHANGE:
            switch Int32(w) {
            case 7:   // WTS_SESSION_LOCK
                CGSessionScreenIsLocked = true
                DistributedNotificationCenter.default().post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
            case 8:   // WTS_SESSION_UNLOCK
                CGSessionScreenIsLocked = false
                DistributedNotificationCenter.default().post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
            case 2, 4:   // console or remote disconnect: switched away from
                post(NSWorkspace.sessionDidResignActiveNotification)
            case 1, 3:   // console or remote connect
                post(NSWorkspace.sessionDidBecomeActiveNotification)
            default: break
            }
            return 0
        case WM_POWERBROADCAST_:
            switch Int32(w) {
            case 4:   // PBT_APMSUSPEND
                post(NSWorkspace.willSleepNotification)
            case 0x12:   // PBT_APMRESUMEAUTOMATIC
                post(NSWorkspace.didWakeNotification)
            case 0x8013:   // PBT_POWERSETTINGCHANGE
                guard let p = UnsafeRawPointer(bitPattern: Int(l)) else { break }
                // POWERBROADCAST_SETTING: GUID, DWORD length, then the data. 0 off, 1 on, 2 dimmed.
                let state = p.load(fromByteOffset: MemoryLayout<GUID>.size + 4, as: DWORD.self)
                let on = state != 0
                if let was = displayOn, was != on {
                    post(on ? NSWorkspace.screensDidWakeNotification : NSWorkspace.screensDidSleepNotification)
                }
                displayOn = on   // (the first notice, on registering, is only the current state)
            default: break
            }
            return LRESULT(1)
        default:
            return nil
        }
    }
}

// MARK: Pictures of windows

enum WindowPictures {
    static func install() {
        CGWindowImageProvider = { rect, option, id, opts in picture(rect, option, id, opts) }
        CGWindowArrayImageProvider = { rect, ids, opts in pictureOf(ids, rect, opts) }
    }

    /// Window-list space (points from the primary screen's top left) to desktop pixels.
    private static func toPixels(_ r: CGRect) -> RECT {
        let k = NSScreen.primaryScale
        let t = NSScreen.primaryPixelHeight / k
        let dy = t - (NSScreen.screens.first?.frame.maxY ?? t)
        return RECT(left: LONG((r.minX * k).rounded(.down)), top: LONG(((r.minY + dy) * k).rounded(.down)),
                    right: LONG((r.maxX * k).rounded(.up)), bottom: LONG(((r.maxY + dy) * k).rounded(.up)))
    }
    private static func toPoints(_ r: RECT) -> CGRect {
        let k = NSScreen.primaryScale
        let t = NSScreen.primaryPixelHeight / k
        let dy = t - (NSScreen.screens.first?.frame.maxY ?? t)
        return CGRect(x: CGFloat(r.left) / k, y: CGFloat(r.top) / k - dy, width: CGFloat(r.right - r.left) / k, height: CGFloat(r.bottom - r.top) / k)
    }

    /// Draws into a fresh top-down 32-bit DIB of `w` x `h` and returns it as an RGBA image.
    /// `opaque`: GDI leaves alpha undefined when copying the screen, so it is set to 255.
    static func capture(_ w: Int, _ h: Int, opaque: Bool, _ draw: (HDC) -> Void) -> CGImage? {
        guard w > 0, h > 0, w < 16384, h < 16384 else { return nil }
        let screen = GetDC(nil)
        defer { ReleaseDC(nil, screen) }
        guard let dc = CreateCompatibleDC(screen) else { return nil }
        defer { DeleteDC(dc) }
        var bi = BITMAPINFO()
        bi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bi.bmiHeader.biWidth = LONG(w)
        bi.bmiHeader.biHeight = -LONG(h)
        bi.bmiHeader.biPlanes = 1
        bi.bmiHeader.biBitCount = 32
        bi.bmiHeader.biCompression = DWORD(BI_RGB)
        var raw: UnsafeMutableRawPointer?
        guard let bmp = CreateDIBSection(dc, &bi, UINT(DIB_RGB_COLORS), &raw, nil, 0), let raw else { return nil }
        defer { DeleteObject(bmp) }
        let old = SelectObject(dc, bmp)
        draw(dc)
        GdiFlush()
        _ = SelectObject(dc, old)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let src = raw.assumingMemoryBound(to: UInt8.self)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            px[i] = src[i + 2]; px[i + 1] = src[i + 1]; px[i + 2] = src[i]
            px[i + 3] = opaque ? 255 : src[i + 3]
        }
        return CGImage(pixels: px, width: w, height: h, bytesPerRow: w * 4)
    }

    /// Scaled to points when the caller asks for nominal resolution.
    private static func sized(_ img: CGImage?, _ points: CGRect, _ opts: CGWindowImageOption) -> CGImage? {
        guard let img, opts.contains(.nominalResolution), NSScreen.primaryScale != 1 else { return img }
        let w = max(1, Int(points.width.rounded())), h = max(1, Int(points.height.rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private static func own(_ id: CGWindowID) -> NSWindow? {
        guard id != 0 else { return nil }
        return NSApplication.shared.windows.first { CGWindowID(truncatingIfNeeded: $0.windowNumber) == id }
    }

    /// One of our own windows, from the bitmap it last put on the screen.
    private static func ownPicture(_ win: NSWindow) -> (CGImage, RECT)? {
        guard let hwnd = win.hwnd, let bits = win.bits, win.pxW > 0, win.pxH > 0 else { return nil }
        var r = RECT()
        _ = GetWindowRect(hwnd, &r)
        let w = win.pxW, h = win.pxH
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let src = bits.assumingMemoryBound(to: UInt8.self)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            px[i] = src[i + 2]; px[i + 1] = src[i + 1]; px[i + 2] = src[i]; px[i + 3] = src[i + 3]
        }
        return (CGImage(pixels: px, width: w, height: h, bytesPerRow: w * 4), RECT(left: r.left, top: r.top, right: r.left + LONG(w), bottom: r.top + LONG(h)))
    }

    /// Another program's window, as it draws itself (PW_RENDERFULLCONTENT also gets DirectX and browser content).
    private static func foreignPicture(_ id: CGWindowID) -> (CGImage, RECT)? {
        guard let hwnd = HWND(bitPattern: UInt(id)), IsWindow(hwnd) else { return nil }
        var r = RECT()
        guard GetWindowRect(hwnd, &r) else { return nil }
        let img = capture(Int(r.right - r.left), Int(r.bottom - r.top), opaque: true) { dc in
            _ = PrintWindow(hwnd, dc, UINT(2))
        }
        return img.map { ($0, r) }
    }

    private static func crop(_ img: CGImage, at origin: RECT, to want: RECT) -> CGImage? {
        img.cropping(to: CGRect(x: Int(want.left - origin.left), y: Int(want.top - origin.top),
                                width: Int(want.right - want.left), height: Int(want.bottom - want.top)))
    }

    static func picture(_ rect: CGRect, _ option: CGWindowListOption, _ id: CGWindowID, _ opts: CGWindowImageOption) -> CGImage? {
        if option.contains(.optionIncludingWindow), !option.contains(.optionOnScreenBelowWindow), !option.contains(.optionOnScreenAboveWindow) {
            // Just the one window.
            guard let (img, at) = own(id).flatMap(ownPicture) ?? foreignPicture(id) else { return nil }
            if rect.isNull { return sized(img, toPoints(at), opts) }
            return sized(crop(img, at: at, to: toPixels(rect)), rect, opts)
        }
        guard !rect.isNull, !rect.isEmpty else { return nil }
        let r = toPixels(rect)
        // The screen as it shows. Leaving out CAPTUREBLT leaves out layered windows, which are all of ours: what is
        // below the overlay, as `.optionOnScreenBelowWindow` asks for. Otherwise everything, ours included.
        let below = option.contains(.optionOnScreenBelowWindow)
        let img = capture(Int(r.right - r.left), Int(r.bottom - r.top), opaque: true) { dc in
            let screen = GetDC(nil)
            _ = BitBlt(dc, 0, 0, r.right - r.left, r.bottom - r.top, screen, r.left, r.top, DWORD(SRCCOPY) | (below ? 0 : DWORD(CAPTUREBLT)))
            ReleaseDC(nil, screen)
        }
        return sized(img, rect, opts)
    }

    /// Several windows, front to back, over each other in one picture (the Mac's own screenshots of the tank).
    static func pictureOf(_ ids: [CGWindowID], _ rect: CGRect, _ opts: CGWindowImageOption) -> CGImage? {
        let parts = ids.compactMap { own($0).flatMap(ownPicture) ?? foreignPicture($0) }
        guard !parts.isEmpty else { return nil }
        var u = parts[0].1
        for (_, r) in parts.dropFirst() { u = RECT(left: min(u.left, r.left), top: min(u.top, r.top), right: max(u.right, r.right), bottom: max(u.bottom, r.bottom)) }
        if !rect.isNull { u = toPixels(rect) }
        let w = Int(u.right - u.left), h = Int(u.bottom - u.top)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for (img, r) in parts.reversed() {
            ctx.draw(img, in: CGRect(x: Int(r.left - u.left), y: h - Int(r.bottom - u.top), width: img.width, height: img.height))
        }
        return sized(ctx.makeImage(), toPoints(u), opts)
    }
}

// MARK: The desktop picture

enum Wallpaper {
    /// The picture's file, as Windows reports it. Windows keeps a copy of whatever is showing in TranscodedWallpaper,
    /// which is there even when the original has moved, so that is the fallback.
    static func url() -> URL? {
        var buf = [WCHAR](repeating: 0, count: Int(MAX_PATH) + 1)
        if SystemParametersInfoW(UINT(SPI_GETDESKWALLPAPER), UINT(buf.count), &buf, 0) {
            let path = String(decoding: buf.prefix { $0 != 0 }, as: UTF16.self)
            if !path.isEmpty, FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        if let app = ProcessInfo.processInfo.environment["APPDATA"] {
            let t = app + "\\Microsoft\\Windows\\Themes\\TranscodedWallpaper"
            if FileManager.default.fileExists(atPath: t) { return URL(fileURLWithPath: t) }
        }
        return nil
    }

    private static func registryString(_ key: String, _ value: String) -> String? {
        var size: DWORD = 0
        let sub = key, name = value
        guard sub.withCString(encodedAs: UTF16.self, { k in name.withCString(encodedAs: UTF16.self) { v in
            RegGetValueW(HKEY_CURRENT_USER, k, v, DWORD(RRF_RT_REG_SZ), nil, nil, &size) } }) == ERROR_SUCCESS, size > 0 else { return nil }
        var buf = [WCHAR](repeating: 0, count: Int(size) / 2 + 1)
        guard sub.withCString(encodedAs: UTF16.self, { k in name.withCString(encodedAs: UTF16.self) { v in
            RegGetValueW(HKEY_CURRENT_USER, k, v, DWORD(RRF_RT_REG_SZ), nil, &buf, &size) } }) == ERROR_SUCCESS else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }, as: UTF16.self)
    }

    /// How the picture is placed, in the Mac's terms. Windows' Stretch is the Mac's "stretch to fill"
    /// (axes independently); Fill, Fit, Span, Center and Tile are read as filling proportionally, which is the
    /// Mac's default and what the Mac's code does for anything that is not stretched.
    static func options() -> [NSWorkspace.DesktopImageOptionKey: Any] {
        var o: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        let style = Int(registryString("Control Panel\\Desktop", "WallpaperStyle") ?? "") ?? 10
        let tile = registryString("Control Panel\\Desktop", "TileWallpaper") == "1"
        let scaling: NSImageScaling = (style == 2 && !tile) ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        o[.imageScaling] = NSNumber(value: Int(scaling.rawValue))
        o[.allowClipping] = NSNumber(value: style != 6)
        let c = GetSysColor(COLOR_DESKTOP)
        o[.fillColor] = NSColor(deviceRed: CGFloat(c & 0xFF) / 255, green: CGFloat((c >> 8) & 0xFF) / 255, blue: CGFloat((c >> 16) & 0xFF) / 255, alpha: 1)
        return o
    }
}

// MARK: CPU time

public struct SpiderTimeValue: Sendable { public var tv_sec: Int = 0; public var tv_usec: Int = 0; public init() {} }
public struct rusage: Sendable {
    public var ru_utime = SpiderTimeValue()
    public var ru_stime = SpiderTimeValue()
    public init() {}
}
public let RUSAGE_SELF: Int32 = 0

/// This process's user and kernel time, from GetProcessTimes.
@discardableResult public func getrusage(_ who: Int32, _ u: UnsafeMutablePointer<rusage>) -> Int32 {
    var created = FILETIME(), exited = FILETIME(), kernel = FILETIME(), user = FILETIME()
    guard GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user) else { return -1 }
    func tv(_ f: FILETIME) -> SpiderTimeValue {
        let hundredNs = (UInt64(f.dwHighDateTime) << 32) | UInt64(f.dwLowDateTime)
        var t = SpiderTimeValue()
        t.tv_sec = Int(hundredNs / 10_000_000)
        t.tv_usec = Int((hundredNs % 10_000_000) / 10)
        return t
    }
    u.pointee.ru_utime = tv(user)
    u.pointee.ru_stime = tv(kernel)
    return 0
}

// MARK: Odds and ends of the C library the Mac sources call

/// Hands freed memory back to the system. The Windows heap does this by itself.
@discardableResult public func malloc_zone_pressure_relief(_ zone: UnsafeMutableRawPointer?, _ goal: Int) -> Int { 0 }

public let CLOCK_REALTIME: Int32 = 0
public let CLOCK_MONOTONIC: Int32 = 6
public let CLOCK_PROCESS_CPUTIME_ID: Int32 = 12
public let CLOCK_THREAD_CPUTIME_ID: Int32 = 16

/// The clocks the app reads: this thread's or process's CPU time, and the monotonic clock.
@discardableResult public func clock_gettime(_ id: Int32, _ ts: UnsafeMutablePointer<timespec>) -> Int32 {
    var hundredNs: UInt64 = 0
    switch id {
    case CLOCK_THREAD_CPUTIME_ID, CLOCK_PROCESS_CPUTIME_ID:
        var c = FILETIME(), e = FILETIME(), k = FILETIME(), u = FILETIME()
        let ok = id == CLOCK_THREAD_CPUTIME_ID ? GetThreadTimes(GetCurrentThread(), &c, &e, &k, &u) : GetProcessTimes(GetCurrentProcess(), &c, &e, &k, &u)
        guard ok else { return -1 }
        func n(_ f: FILETIME) -> UInt64 { (UInt64(f.dwHighDateTime) << 32) | UInt64(f.dwLowDateTime) }
        hundredNs = n(k) + n(u)
    default:
        let t = CACurrentMediaTime()
        ts.pointee.tv_sec = .init(t.rounded(.down))
        ts.pointee.tv_nsec = .init((t - t.rounded(.down)) * 1e9)
        return 0
    }
    ts.pointee.tv_sec = .init(hundredNs / 10_000_000)
    ts.pointee.tv_nsec = .init((hundredNs % 10_000_000) * 100)
    return 0
}

/// The few machine facts the bug report asks the Mac for, from where Windows keeps them.
@discardableResult public func sysctlbyname(_ name: UnsafePointer<CChar>, _ old: UnsafeMutableRawPointer?, _ oldSize: UnsafeMutablePointer<Int>?,
                                            _ new: UnsafeMutableRawPointer?, _ newSize: Int) -> Int32 {
    let key = String(cString: name)
    let value: String?
    switch key {
    case "hw.model":
        let maker = MachineInfo.registry("HARDWARE\\DESCRIPTION\\System\\BIOS", "SystemManufacturer")
        let product = MachineInfo.registry("HARDWARE\\DESCRIPTION\\System\\BIOS", "SystemProductName")
        value = [maker, product].compactMap { $0 }.joined(separator: " ").nilIfEmpty
    case "machdep.cpu.brand_string":
        value = MachineInfo.registry("HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", "ProcessorNameString")?.trimmingCharacters(in: .whitespaces)
    case "kern.osversion":
        // The build, as Windows reports it: 26300.1234.
        let build = MachineInfo.registry("SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", "CurrentBuildNumber")
        let ubr = MachineInfo.registryDWORD("SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", "UBR")
        value = build.map { b in ubr.map { "\(b).\($0)" } ?? b }
    default: value = nil
    }
    guard let value else { return -1 }
    let bytes = Array(value.utf8CString)
    guard let oldSize else { return -1 }
    if let old {
        guard oldSize.pointee >= bytes.count else { return -1 }
        bytes.withUnsafeBytes { old.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
    }
    oldSize.pointee = bytes.count
    return 0
}

enum MachineInfo {
    static func registry(_ key: String, _ value: String, root: HKEY = HKEY_LOCAL_MACHINE) -> String? {
        var size: DWORD = 0
        guard key.withCString(encodedAs: UTF16.self, { k in value.withCString(encodedAs: UTF16.self) { v in
            RegGetValueW(root, k, v, DWORD(RRF_RT_REG_SZ), nil, nil, &size) } }) == ERROR_SUCCESS, size > 0 else { return nil }
        var buf = [WCHAR](repeating: 0, count: Int(size) / 2 + 1)
        guard key.withCString(encodedAs: UTF16.self, { k in value.withCString(encodedAs: UTF16.self) { v in
            RegGetValueW(root, k, v, DWORD(RRF_RT_REG_SZ), nil, &buf, &size) } }) == ERROR_SUCCESS else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }, as: UTF16.self)
    }
    static func registryDWORD(_ key: String, _ value: String, root: HKEY = HKEY_LOCAL_MACHINE) -> DWORD? {
        var out: DWORD = 0, size = DWORD(MemoryLayout<DWORD>.size)
        guard key.withCString(encodedAs: UTF16.self, { k in value.withCString(encodedAs: UTF16.self) { v in
            RegGetValueW(root, k, v, DWORD(RRF_RT_REG_DWORD), nil, &out, &size) } }) == ERROR_SUCCESS else { return nil }
        return out
    }
}
private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

// MARK: Crash reports (developer aid)

/// SPIDER_CRASH_STACK=1: on a fatal exception, prints the stack as offsets into each module
/// ("SpiderBuddy.exe+0x1234"), for llvm-symbolizer and the .pdb. Swift's own backtracer cannot read our PDBs.
public enum CrashStack {
    nonisolated(unsafe) static var installed = false
    public static func install() {
        guard !installed else { return }
        if ProcessInfo.processInfo.environment["SPIDER_VIEW_DUMP"] == "1" { write("", fresh: true) }
        guard ProcessInfo.processInfo.environment["SPIDER_CRASH_STACK"] == "1" else { return }
        installed = true
        CrashStack.write("crash stacks on\n", fresh: true)
        _ = AddVectoredExceptionHandler(1) { info in
            guard let rec = info?.pointee.ExceptionRecord?.pointee else { return EXCEPTION_CONTINUE_SEARCH }
            let code = UInt32(bitPattern: Int32(truncatingIfNeeded: rec.ExceptionCode))
            // Only the fatal ones: access violation, illegal instruction (Swift's traps), stack overflow, breakpoint.
            guard [0xC0000005, 0xC000001D, 0xC00000FD, 0x80000003].contains(code) else { return EXCEPTION_CONTINUE_SEARCH }
            var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 62)
            let n = Int(RtlCaptureStackBackTrace(0, 62, &frames, nil))
            var out = "*** crash 0x\(String(code, radix: 16)) at \(CrashStack.describe(rec.ExceptionAddress))\n"
            for i in 0..<n { out += "  #\(i) \(CrashStack.describe(frames[i]))\n" }
            CrashStack.write(out, fresh: false)
            return EXCEPTION_CONTINUE_SEARCH
        }
    }
    /// To %TEMP%\\spider-crash.txt, straight through the file system: nothing buffered is lost when the process dies.
    public static func mark(_ s: String) { if installed { write("at \(s)\n", fresh: false) } }
    public static func write(_ s: String, fresh: Bool) {
        let path = (ProcessInfo.processInfo.environment["TEMP"] ?? ".") + "\\spider-crash.txt"
        let h = path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(FILE_APPEND_DATA), DWORD(FILE_SHARE_READ), nil, DWORD(fresh ? CREATE_ALWAYS : OPEN_ALWAYS), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let h, h != INVALID_HANDLE_VALUE else { return }
        var bytes = Array(s.utf8)
        var n: DWORD = 0
        _ = WriteFile(h, &bytes, DWORD(bytes.count), &n, nil)
        CloseHandle(h)
    }
    static func describe(_ p: UnsafeMutableRawPointer?) -> String {
        guard let p else { return "?" }
        var module: HMODULE?
        guard GetModuleHandleExW(DWORD(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT),
                                 p.assumingMemoryBound(to: WCHAR.self), &module), let module else { return "\(p)" }
        var buf = [WCHAR](repeating: 0, count: 260)
        let len = GetModuleFileNameW(module, &buf, 260)
        let path = String(decoding: buf[0..<Int(len)], as: UTF16.self)
        let name = path.split(separator: "\\").last.map(String.init) ?? path
        let off = UInt(bitPattern: p) - UInt(bitPattern: UnsafeRawPointer(module))
        return "\(name)+0x\(String(off, radix: 16))"
    }
}

// MARK: Hang samples (developer aid)

/// SPIDER_HANG_STACK=1: when the main thread has not finished a frame for 3 s, its stack is written to
/// %TEMP%\spider-crash.txt as module offsets, every 3 s while it stays stuck. Unwinds with the x64 unwind tables,
/// which work where debuggers cannot unwind our frames.
public enum HangWatch {
    nonisolated(unsafe) static var beats = 0
    nonisolated(unsafe) static var mainThread: HANDLE?
    public static func beat() { beats &+= 1 }
    public static func install() {
        guard ProcessInfo.processInfo.environment["SPIDER_HANG_STACK"] == "1", mainThread == nil else { return }
        var h: HANDLE?
        _ = DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &h, 0, false, DWORD(DUPLICATE_SAME_ACCESS))
        mainThread = h
        CrashStack.write("hang watch on\n", fresh: true)
        let t = Thread {
            var last = -1, stuck = 0
            while true {
                Thread.sleep(forTimeInterval: 1)
                if beats == last { stuck += 1 } else { stuck = 0; last = beats }
                if stuck >= 3, stuck % 3 == 0 { sample() }
            }
        }
        t.start()
    }
    static func sample() {
        guard let th = mainThread else { return }
        guard SuspendThread(th) != DWORD.max else { return }
        defer { ResumeThread(th) }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<CONTEXT>.size, alignment: 16)
        defer { raw.deallocate() }
        let ctx = raw.bindMemory(to: CONTEXT.self, capacity: 1)
        memset(raw, 0, MemoryLayout<CONTEXT>.size)
        ctx.pointee.ContextFlags = 0x10000B   // CONTEXT_FULL (AMD64: control, integer, floating point)
        guard GetThreadContext(th, ctx) else { return }
        var out = "*** main thread stuck (\(beats) frames so far)\n"
        for i in 0..<48 {
            let pc = ctx.pointee.Rip
            guard pc != 0 else { break }
            out += "  #\(i) \(CrashStack.describe(UnsafeMutableRawPointer(bitPattern: UInt(pc))))\n"
            var base: DWORD64 = 0
            if let fn = RtlLookupFunctionEntry(pc, &base, nil) {
                var handler: PVOID?
                var frame: DWORD64 = 0
                _ = RtlVirtualUnwind(DWORD(UNW_FLAG_NHANDLER), base, pc, fn, ctx, &handler, &frame, nil)
            } else {
                // A leaf: the return address is on top of the stack.
                guard let sp = UnsafePointer<DWORD64>(bitPattern: UInt(ctx.pointee.Rsp)) else { break }
                ctx.pointee.Rip = sp.pointee
                ctx.pointee.Rsp += 8
            }
        }
        CrashStack.write(out, fresh: false)
    }
}
