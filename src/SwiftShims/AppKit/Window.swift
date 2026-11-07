// NSWindow on Win32, and the app's frame source and event pump.
//
// Borderless windows are layered and per-pixel transparent, as the Mac's overlays are. Titled windows are ordinary Win32
// windows whose client area is drawn from the same bitmap. Either way, the layer tree is composited with Skia straight into a
// DIB when something changed, and only the part that was drawn is cleared and presented.
import Foundation
import QuartzCore
import WinSDK

// MARK: Units

extension NSScreen {
    /// Physical pixels per point on the primary display. (Mixed DPI uses the primary's for now.)
    nonisolated(unsafe) public static var primaryScale: CGFloat = 1
    nonisolated(unsafe) static var primaryPixelHeight: CGFloat = 0
}
func worldToPixel(_ p: CGPoint) -> POINT {
    POINT(x: LONG((p.x * NSScreen.primaryScale).rounded()), y: LONG(NSScreen.primaryPixelHeight - (p.y * NSScreen.primaryScale).rounded()))
}
func pixelToWorld(x: Int32, y: Int32) -> CGPoint {
    CGPoint(x: CGFloat(x) / NSScreen.primaryScale, y: (NSScreen.primaryPixelHeight - CGFloat(y)) / NSScreen.primaryScale)
}

// MARK: Levels and masks

extension NSWindow {
    public struct Level: RawRepresentable, Hashable, Comparable, Sendable {
        public var rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public init(_ v: Int) { rawValue = v }
        public static let normal = Level(0), floating = Level(3), submenu = Level(3), tornOffMenu = Level(3), modalPanel = Level(8), mainMenu = Level(24), statusBar = Level(25), popUpMenu = Level(101), screenSaver = Level(1000)
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    public struct StyleMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let borderless = Self([]), titled = Self(rawValue: 1), closable = Self(rawValue: 2), miniaturizable = Self(rawValue: 4), resizable = Self(rawValue: 8), utilityWindow = Self(rawValue: 16), docModalWindow = Self(rawValue: 64), nonactivatingPanel = Self(rawValue: 128), unifiedTitleAndToolbar = Self(rawValue: 1 << 12), fullScreen = Self(rawValue: 1 << 14), fullSizeContentView = Self(rawValue: 1 << 15), hudWindow = Self(rawValue: 1 << 13)
    }
    public struct CollectionBehavior: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let canJoinAllSpaces = Self(rawValue: 1), moveToActiveSpace = Self(rawValue: 2), managed = Self(rawValue: 4), transient = Self(rawValue: 8), stationary = Self(rawValue: 16), participatesInCycle = Self(rawValue: 32), ignoresCycle = Self(rawValue: 64), fullScreenPrimary = Self(rawValue: 128), fullScreenAuxiliary = Self(rawValue: 256), fullScreenNone = Self(rawValue: 512)
    }
    public enum OrderingMode: Int, Sendable { case below = -1, out = 0, above = 1 }
    public enum BackingStoreType: UInt, Sendable { case retained, nonretained, buffered }
    public enum TitleVisibility: Int, Sendable { case visible, hidden }
    public enum ButtonType: Int, Sendable { case closeButton, miniaturizeButton, zoomButton, toolbarButton, documentIconButton, documentVersionsButton }
    public enum ToolbarStyle: Int, Sendable { case automatic, expanded, preference, unified, unifiedCompact }
    public enum AnimationBehavior: Int, Sendable { case `default`, none, documentWindow, utilityWindow, alertPanel }
    public static let didResizeNotification = Notification.Name("NSWindowDidResizeNotification")
    public static let didMoveNotification = Notification.Name("NSWindowDidMoveNotification")
    public static let willCloseNotification = Notification.Name("NSWindowWillCloseNotification")
    public static let didBecomeKeyNotification = Notification.Name("NSWindowDidBecomeKeyNotification")
    public static let didResignKeyNotification = Notification.Name("NSWindowDidResignKeyNotification")
    public static let didBecomeMainNotification = Notification.Name("NSWindowDidBecomeMainNotification")
    public static let didResignMainNotification = Notification.Name("NSWindowDidResignMainNotification")
    public static let didMiniaturizeNotification = Notification.Name("NSWindowDidMiniaturizeNotification")
    public static let didDeminiaturizeNotification = Notification.Name("NSWindowDidDeminiaturizeNotification")
    public static let didEnterFullScreenNotification = Notification.Name("NSWindowDidEnterFullScreenNotification")
    public static let didExitFullScreenNotification = Notification.Name("NSWindowDidExitFullScreenNotification")
    public static let didEndLiveResizeNotification = Notification.Name("NSWindowDidEndLiveResizeNotification")
    public static let didChangeOcclusionStateNotification = Notification.Name("NSWindowDidChangeOcclusionStateNotification")
    public struct OcclusionState: OptionSet, Sendable { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }; public static let visible = Self(rawValue: 2) }
}
public typealias NSBackingStoreType = NSWindow.BackingStoreType
public protocol NSWindowDelegate: AnyObject {
    func windowWillClose(_ notification: Notification)
    func windowDidResize(_ notification: Notification)
    func windowDidBecomeKey(_ notification: Notification)
    func windowDidResignKey(_ notification: Notification)
    func windowDidMove(_ notification: Notification)
    func windowShouldClose(_ sender: NSWindow) -> Bool
    func windowDidEndLiveResize(_ notification: Notification)
    func windowDidMiniaturize(_ notification: Notification)
    func windowDidDeminiaturize(_ notification: Notification)
}
extension NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {}
    public func windowDidResize(_ notification: Notification) {}
    public func windowDidBecomeKey(_ notification: Notification) {}
    public func windowDidResignKey(_ notification: Notification) {}
    public func windowDidMove(_ notification: Notification) {}
    public func windowShouldClose(_ sender: NSWindow) -> Bool { true }
    public func windowDidEndLiveResize(_ notification: Notification) {}
    public func windowDidMiniaturize(_ notification: Notification) {}
    public func windowDidDeminiaturize(_ notification: Notification) {}
}

// MARK: The window class

private let windowClassName: [WCHAR] = Array("SpiderBuddyWindow".utf16) + [0]
nonisolated(unsafe) private var classRegistered = false
nonisolated(unsafe) var windowsByHandle: [HWND: NSWindow] = [:]

private func windowProc(_ h: HWND?, _ m: UINT, _ w: WPARAM, _ l: LPARAM) -> LRESULT {
    if let h, let win = windowsByHandle[h], let r = win.handle(m, w, l) { return r }
    return DefWindowProcW(h, m, w, l)
}
func registerWindowClass() {
    guard !classRegistered else { return }
    classRegistered = true
    var wc = WNDCLASSW()
    wc.style = UINT(CS_DBLCLKS)
    wc.lpfnWndProc = { h, m, w, l in windowProc(h, m, w, l) }
    wc.hInstance = GetModuleHandleW(nil)
    wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
    wc.hIcon = LoadIconW(GetModuleHandleW(nil), UnsafePointer<WCHAR>(bitPattern: 1))
    windowClassName.withUnsafeBufferPointer { b in
        wc.lpszClassName = b.baseAddress
        _ = RegisterClassW(&wc)
    }
}

open class NSWindow: NSResponder, CALayerHost {
    public private(set) var hwnd: HWND?
    public let styleMask0: StyleMask
    open var styleMask: StyleMask { didSet { applyStyle() } }
    public var layered: Bool { !styleMask.contains(.titled) }

    public private(set) var frame: CGRect
    open var contentView: NSView? {
        didSet {
            oldValue?.windowStore = nil
            oldValue?.backing.host = nil
            if let v = contentView {
                v.removeFromSuperview()
                v.windowStore = self
                v.backing.host = self
                v.frame = contentRect(forFrameRect: frame).offsetBy(dx: -frame.minX, dy: -frame.minY)
                v.frame.origin = .zero
                v.autoresizingMask = [.width, .height]
                v.nextResponder = self
                v.notifyWindowChange()
            }
            markLayout()
            layerTreeChanged()
        }
    }
    open var contentViewController: NSViewController? { didSet { if let c = contentViewController { contentView = c.view } } }
    public weak var delegate: NSWindowDelegate?
    open var title: String = "" { didSet { title.withCString(encodedAs: UTF16.self) { _ = SetWindowTextW(hwnd, $0) } } }
    public var subtitle = ""
    open var level = Level.normal { didSet { applyLevel() } }
    open var isOpaque = true
    open var backgroundColor: NSColor = .windowBackgroundColor { didSet { layerTreeChanged() } }
    open var hasShadow = true
    open var alphaValue: CGFloat = 1 { didSet { layerTreeChanged() } }
    open var ignoresMouseEvents = false { didSet { if ignoresMouseEvents != oldValue { applyExStyle() } } }
    open var acceptsMouseMovedEvents = false
    open var isMovable = true
    open var isMovableByWindowBackground = false
    open var isReleasedWhenClosed = true
    open var hidesOnDeactivate = false
    open var collectionBehavior: CollectionBehavior = []
    open var titlebarAppearsTransparent = false
    open var titleVisibility = TitleVisibility.visible
    open var toolbarStyle = ToolbarStyle.automatic
    open var toolbar: NSToolbar? { didSet { toolbar?.window = self } }
    open var minSize = CGSize.zero
    open var maxSize = CGSize(width: 1e6, height: 1e6)
    open var contentMinSize = CGSize.zero
    open var contentMaxSize = CGSize(width: 1e6, height: 1e6)
    open var isExcludedFromWindowsMenu = false
    open var canHide = true
    open var animationBehavior = AnimationBehavior.default
    open var colorSpace: NSColorSpace? = nil
    open var appearance: NSAppearance? = nil
    open var representedURL: URL?
    open var sharingType = 1
    open var preventsApplicationTerminationWhenModal = true
    public var occlusionState: OcclusionState { .visible }
    open var effectiveAppearance: NSAppearance { appearance ?? NSApp.effectiveAppearance }
    open var firstResponder: NSResponder? { firstResponderStore }
    private var firstResponderStore: NSResponder?
    open var initialFirstResponder: NSView?
    public var attachedSheet: NSWindow? { nil }
    public var parent: NSWindow? { parentStore }
    private weak var parentStore: NSWindow?
    public private(set) var childWindows: [NSWindow]? = nil
    public var isVisible: Bool { visible }
    private var visible = false
    public var isMiniaturized: Bool { hwnd.map { IsIconic($0) } ?? false }
    public var isZoomed: Bool { hwnd.map { IsZoomed($0) } ?? false }
    public var isKeyWindow: Bool { GetForegroundWindow() == hwnd && hwnd != nil }
    public var isMainWindow: Bool { isKeyWindow }
    public var isOnActiveSpace: Bool { true }
    public var isSheet: Bool { false }
    public var windowNumber: Int { hwnd.map { Int(bitPattern: UnsafeRawPointer($0)) & 0x7FFF_FFFF } ?? 0 }
    public var screen: NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
    }
    public var deepestScreen: NSScreen? { screen }
    public var backingScaleFactor: CGFloat { NSScreen.primaryScale }
    open var canBecomeKey: Bool { styleMask.contains(.titled) }
    open var canBecomeMain: Bool { styleMask.contains(.titled) }
    public var worksWhenModal: Bool { false }
    public var becomesKeyOnlyIfNeeded = false
    public var isFloatingPanelStore = false

    // Bitmap
    private var memDC: HDC?
    private var dib: HBITMAP?
    private var bits: UnsafeMutableRawPointer?
    private var pxW = 0, pxH = 0
    private var ctx: CGContext?
    private var lastBox: SkiaBox? = nil
    private var dirty = true
    private var layoutDirty = true
    /// Whether `show` has gone up since the last frame change.
    private var pendingFrameMove = false

    public init(contentRect: CGRect, styleMask: StyleMask, backing: BackingStoreType, defer flag: Bool) {
        self.styleMask = styleMask
        styleMask0 = styleMask
        frame = contentRect
        super.init()
        registerWindowClass()
        create(contentRect)
        frame = frameRect(forContentRect: contentRect)
        placeNative()
        let c = NSView(frame: CGRect(origin: .zero, size: contentRect.size))
        contentView = c
        NSApplication.shared.register(self)
    }
    public convenience init(contentViewController c: NSViewController) {
        self.init(contentRect: CGRect(origin: .zero, size: c.view.frame.size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        contentViewController = c
    }
    public convenience override init() { self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false) }
    public required init?(coder: NSCoder) { fatalError() }

    private func nativeStyle() -> (DWORD, DWORD) {
        var ex: Int32 = WS_EX_NOACTIVATE
        var st: UInt32
        if layered {
            st = UInt32(WS_POPUP)
            ex |= WS_EX_LAYERED | WS_EX_TOOLWINDOW
        } else {
            ex = 0
            st = UInt32(WS_OVERLAPPED) | UInt32(WS_CAPTION) | UInt32(WS_SYSMENU)
            if styleMask.contains(.miniaturizable) { st |= UInt32(WS_MINIMIZEBOX) }
            if styleMask.contains(.resizable) { st |= UInt32(WS_THICKFRAME) | UInt32(WS_MAXIMIZEBOX) }
        }
        if ignoresMouseEvents { ex |= WS_EX_TRANSPARENT }
        return (st, DWORD(ex))
    }
    private func create(_ r: CGRect) {
        let (st, ex) = nativeStyle()
        hwnd = windowClassName.withUnsafeBufferPointer { b in
            CreateWindowExW(ex, b.baseAddress, nil, st, 0, 0, 10, 10, nil, nil, GetModuleHandleW(nil), nil)
        }
        if let hwnd { windowsByHandle[hwnd] = self }
    }
    private func applyStyle() {
        guard let hwnd else { return }
        let (st, ex) = nativeStyle()
        _ = SetWindowLongPtrW(hwnd, GWL_STYLE, LONG_PTR(st))
        _ = SetWindowLongPtrW(hwnd, GWL_EXSTYLE, LONG_PTR(ex))
    }
    private func applyExStyle() {
        guard let hwnd else { return }
        let (_, ex) = nativeStyle()
        _ = SetWindowLongPtrW(hwnd, GWL_EXSTYLE, LONG_PTR(ex))
    }
    private func applyLevel() {
        guard let hwnd, visible else { return }
        let top = level.rawValue > 0
        _ = SetWindowPos(hwnd, top ? HWND(bitPattern: -1) : HWND(bitPattern: -2), 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE))
    }

    // MARK: Frames

    private func chromeInsets() -> (l: CGFloat, t: CGFloat, r: CGFloat, b: CGFloat) {
        guard !layered else { return (0, 0, 0, 0) }
        let (st, ex) = nativeStyle()
        var rc = RECT(left: 0, top: 0, right: 100, bottom: 100)
        _ = AdjustWindowRectEx(&rc, st, false, ex)
        let k = NSScreen.primaryScale
        return (CGFloat(-rc.left) / k, CGFloat(-rc.top) / k, CGFloat(rc.right - 100) / k, CGFloat(rc.bottom - 100) / k)
    }
    open func contentRect(forFrameRect r: CGRect) -> CGRect {
        let c = chromeInsets()
        return CGRect(x: r.minX + c.l, y: r.minY + c.b, width: max(0, r.width - c.l - c.r), height: max(0, r.height - c.t - c.b))
    }
    open func frameRect(forContentRect r: CGRect) -> CGRect {
        let c = chromeInsets()
        return CGRect(x: r.minX - c.l, y: r.minY - c.b, width: r.width + c.l + c.r, height: r.height + c.t + c.b)
    }
    public func setFrame(_ r: CGRect, display: Bool) { setFrameNow(r) }
    public func setFrame(_ r: CGRect, display: Bool, animate: Bool) { setFrameNow(r) }
    public func setFrameOrigin(_ p: CGPoint) { setFrameNow(CGRect(origin: p, size: frame.size)) }
    public func setFrameTopLeftPoint(_ p: CGPoint) { setFrameNow(CGRect(x: p.x, y: p.y - frame.height, width: frame.width, height: frame.height)) }
    public func cascadeTopLeft(from p: CGPoint) -> CGPoint { p }
    public func setContentSize(_ s: CGSize) {
        var cr = contentRect(forFrameRect: frame)
        let top = cr.maxY
        cr.size = s
        cr.origin.y = top - s.height
        setFrameNow(frameRect(forContentRect: cr))
    }
    public func center() {
        let s = (NSScreen.main?.visibleFrame) ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        setFrameOrigin(CGPoint(x: s.midX - frame.width / 2, y: s.midY - frame.height / 2 + s.height * 0.08))
    }
    func setFrameNow(_ r: CGRect) {
        let sizeChanged = r.size != frame.size
        frame = r
        if sizeChanged {
            contentView?.frame.size = contentRect(forFrameRect: r).size
            markLayout()
            dirty = true
        }
        placeNative()
        if sizeChanged { post(NSWindow.didResizeNotification); delegate?.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: self)) }
    }
    private var ignoreNativeMove = false
    private func placeNative() {
        guard let hwnd else { return }
        let k = NSScreen.primaryScale
        let tl = worldToPixel(CGPoint(x: frame.minX, y: frame.maxY))
        ignoreNativeMove = true
        _ = SetWindowPos(hwnd, nil, tl.x, tl.y, Int32((frame.width * k).rounded()), Int32((frame.height * k).rounded()), UINT(SWP_NOZORDER | SWP_NOACTIVATE))
        ignoreNativeMove = false
    }
    public func convertPoint(toScreen p: CGPoint) -> CGPoint { let o = contentOrigin; return CGPoint(x: o.x + p.x, y: o.y + p.y) }
    public func convertPoint(fromScreen p: CGPoint) -> CGPoint { let o = contentOrigin; return CGPoint(x: p.x - o.x, y: p.y - o.y) }
    public func convertToScreen(_ r: CGRect) -> CGRect { r.offsetBy(dx: contentOrigin.x, dy: contentOrigin.y) }
    public func convertFromScreen(_ r: CGRect) -> CGRect { r.offsetBy(dx: -contentOrigin.x, dy: -contentOrigin.y) }
    public var contentLayoutRect: CGRect { CGRect(origin: .zero, size: contentView?.frame.size ?? .zero) }
    public var contentLayoutGuide: Any? { nil }
    public var mouseLocationOutsideOfEventStream: CGPoint { convertPoint(fromScreen: NSEvent.mouseLocation) }
    private var contentOrigin: CGPoint { contentRect(forFrameRect: frame).origin }

    // MARK: Ordering

    public func orderOut(_ sender: Any?) {
        guard visible, let hwnd else { return }
        visible = false
        _ = ShowWindow(hwnd, SW_HIDE)
        lastBox = nil
    }
    public func orderFrontRegardless() { show(activate: false) }
    public func orderFront(_ sender: Any?) { show(activate: false) }
    public func orderBack(_ sender: Any?) { show(activate: false); if let hwnd { _ = SetWindowPos(hwnd, HWND(bitPattern: 1), 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)) } }
    public func makeKeyAndOrderFront(_ sender: Any?) { show(activate: true) }
    public func makeKey() { show(activate: true) }
    public func makeMain() {}
    public func resignKey() {}
    public func resignMain() {}
    public func order(_ place: OrderingMode, relativeTo other: Int) {
        guard place != .out else { orderOut(nil); return }
        show(activate: false)
        guard let hwnd, other != 0, let o = NSApplication.shared.windows.first(where: { $0.windowNumber == other })?.hwnd else { return }
        if place == .below {
            _ = SetWindowPos(hwnd, o, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE))
        } else {
            _ = SetWindowPos(o, hwnd, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE))
        }
    }
    private func show(activate: Bool) {
        guard let hwnd else { return }
        layoutIfNeeded(force: false)
        if !visible {
            visible = true
            dirty = true
            if !layered || activate { composite() }
            _ = ShowWindow(hwnd, activate && canBecomeKey ? SW_SHOW : SW_SHOWNA)
            applyLevel()
            composite()
        } else {
            _ = SetWindowPos(hwnd, level.rawValue > 0 ? HWND(bitPattern: -1) : HWND(bitPattern: 0), 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE))
        }
        if activate, canBecomeKey {
            _ = SetForegroundWindow(hwnd)
            NSApp.keyWindowStore = self
            post(NSWindow.didBecomeKeyNotification)
        }
    }
    public func close() {
        guard let hwnd else { return }
        delegate?.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: self))
        post(NSWindow.willCloseNotification)
        visible = false
        _ = ShowWindow(hwnd, SW_HIDE)
    }
    public func performClose(_ sender: Any?) {
        if delegate?.windowShouldClose(self) ?? true { close() }
    }
    public func miniaturize(_ sender: Any?) { if let hwnd { _ = ShowWindow(hwnd, SW_MINIMIZE) } }
    public func deminiaturize(_ sender: Any?) { if let hwnd { _ = ShowWindow(hwnd, SW_RESTORE) } }
    public func zoom(_ sender: Any?) { if let hwnd { _ = ShowWindow(hwnd, isZoomed ? SW_RESTORE : SW_MAXIMIZE) } }
    public func toggleFullScreen(_ sender: Any?) { zoom(sender) }
    public func addChildWindow(_ w: NSWindow, ordered: OrderingMode) {
        if childWindows == nil { childWindows = [] }
        childWindows!.append(w)
        w.parentStore = self
    }
    public func removeChildWindow(_ w: NSWindow) { childWindows?.removeAll { $0 === w }; w.parentStore = nil }
    public func standardWindowButton(_ b: ButtonType) -> NSButton? { nil }
    public func invalidateCursorRects(for v: NSView) {}
    public func invalidateShadow() {}
    public func displayIfNeeded() { composite() }
    public func display() { dirty = true; composite() }
    public func update() {}
    public func disableCursorRects() {}
    public func enableCursorRects() {}
    public func setIsVisible(_ v: Bool) { if v { orderFrontRegardless() } else { orderOut(nil) } }
    public func beginSheet(_ w: NSWindow, completionHandler: ((NSApplication.ModalResponse) -> Void)? = nil) { w.makeKeyAndOrderFront(nil) }
    public func endSheet(_ w: NSWindow) { w.orderOut(nil) }
    public func selectNextKeyView(_ s: Any?) {}
    public func selectPreviousKeyView(_ s: Any?) {}
    public func recalculateKeyViewLoop() {}
    public func sendEvent(_ e: NSEvent) { dispatch(e) }
    public func postEvent(_ e: NSEvent, atStart: Bool) { dispatch(e) }
    public func makeFirstResponder(_ r: NSResponder?) -> Bool {
        if firstResponderStore === r { return true }
        if let cur = firstResponderStore, !cur.resignFirstResponder() { return false }
        firstResponderStore = r
        _ = r?.becomeFirstResponder()
        return true
    }
    public func fieldEditor(_ create: Bool, for o: Any?) -> NSText? { nil }
    public func nextEvent(matching: NSEvent.EventTypeMask, until: Date?, inMode: RunLoop.Mode, dequeue: Bool) -> NSEvent? { nil }
    public func nextEvent(matching: NSEvent.EventTypeMask) -> NSEvent? { nil }
    public func trackEvents(matching: NSEvent.EventTypeMask, timeout: TimeInterval, mode: RunLoop.Mode, handler: (NSEvent?, UnsafeMutablePointer<ObjCBool>) -> Void) {}

    private func post(_ n: Notification.Name) { NotificationCenter.default.post(name: n, object: self) }

    // MARK: Layout and compositing

    public func layerTreeChanged() { dirty = true; NSApp.windowChanged(self) }
    func markLayout() { layoutDirty = true; NSApp.windowChanged(self) }
    func layoutIfNeeded(force: Bool) {
        guard layoutDirty || force, let c = contentView else { return }
        layoutDirty = false
        LayoutEngine.layout(root: c, size: c.frame.size)
        layoutDirty = false
    }

    private func ensureBitmap() {
        let k = NSScreen.primaryScale
        let cr = contentRect(forFrameRect: frame)
        let w = max(Int((cr.width * k).rounded(.up)), 1), h = max(Int((cr.height * k).rounded(.up)), 1)
        guard w != pxW || h != pxH || ctx == nil else { return }
        if let d = dib { DeleteObject(d) }
        if memDC == nil { memDC = CreateCompatibleDC(nil) }
        var bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bmi.bmiHeader.biWidth = Int32(w)
        bmi.bmiHeader.biHeight = -Int32(h)
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bmi.bmiHeader.biCompression = DWORD(BI_RGB)
        var b: UnsafeMutableRawPointer? = nil
        dib = CreateDIBSection(memDC, &bmi, UINT(DIB_RGB_COLORS), &b, nil, 0)
        _ = SelectObject(memDC, dib)
        bits = b
        pxW = w; pxH = h
        ctx = CGContext(data: b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        lastBox = nil
    }

    /// True if anything animated, so the frame source keeps drawing.
    var animating: Bool { contentView?.backing.isAnimating ?? false }

    /// Draws what changed, and puts it on the screen.
    open func composite() {
        guard visible, let hwnd, let content = contentView else { return }
        layoutIfNeeded(force: false)
        guard dirty || animating else { return }
        dirty = false
        ensureBitmap()
        guard let ctx, let bits, let memDC else { return }
        let skia = ctx.backend as? SkiaBackend
        // Only what was drawn last time needs clearing.
        if let b = lastBox, layered {
            let x0 = max(0, b.x0), x1 = min(pxW, b.x1), y0 = max(0, b.y0), y1 = min(pxH, b.y1)
            if x1 > x0, y1 > y0 { for y in y0..<y1 { memset(bits + y * pxW * 4 + x0 * 4, 0, (x1 - x0) * 4) } }
        } else {
            memset(bits, 0, pxW * pxH * 4)
        }
        skia?.resetBox()
        let k = NSScreen.primaryScale
        ctx.saveGState()
        ctx.scaleBy(x: k, y: k)
        if !layered {
            // A titled window has an opaque background.
            ctx.setFillColor(backgroundColor.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(pxW) / k, height: CGFloat(pxH) / k))
        }
        let now = CACurrentMediaTime()
        if !isOpaque, !layered, backgroundColor.cgColor.a > 0 { }
        if layered, backgroundColor.cgColor.a > 0, !isOpaque {
            ctx.setFillColor(backgroundColor.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(pxW) / k, height: CGFloat(pxH) / k))
        }
        content.backing.position = .zero
        content.backing.render(in: ctx, now: now)
        ctx.restoreGState()
        let box = skia?.box
        if layered {
            let cr = contentRect(forFrameRect: frame)
            var dst = worldToPixel(CGPoint(x: cr.minX, y: cr.maxY))
            var size = SIZE(cx: LONG(pxW), cy: LONG(pxH))
            var src = POINT(x: 0, y: 0)
            var blend = BLENDFUNCTION(BlendOp: BYTE(AC_SRC_OVER), BlendFlags: 0, SourceConstantAlpha: BYTE(max(0, min(255, alphaValue * 255))), AlphaFormat: BYTE(AC_SRC_ALPHA))
            // Only the union of old and new needs to be recomposed by the system.
            var dirtyRect = RECT(left: 0, top: 0, right: LONG(pxW), bottom: LONG(pxH))
            if let b = box, let o = lastBox {
                dirtyRect = RECT(left: LONG(max(0, min(b.x0, o.x0))), top: LONG(max(0, min(b.y0, o.y0))), right: LONG(min(pxW, max(b.x1, o.x1))), bottom: LONG(min(pxH, max(b.y1, o.y1))))
            }
            withUnsafeMutablePointer(to: &dst) { pd in withUnsafeMutablePointer(to: &size) { ps in withUnsafeMutablePointer(to: &src) { pc in withUnsafeMutablePointer(to: &blend) { pb in withUnsafeMutablePointer(to: &dirtyRect) { pr in
                var info = UPDATELAYEREDWINDOWINFO()
                info.cbSize = DWORD(MemoryLayout<UPDATELAYEREDWINDOWINFO>.size)
                info.pptDst = UnsafePointer(pd)
                info.psize = UnsafePointer(ps)
                info.hdcSrc = memDC
                info.pptSrc = UnsafePointer(pc)
                info.pblend = UnsafePointer(pb)
                info.dwFlags = DWORD(ULW_ALPHA)
                info.prcDirty = UnsafePointer(pr)
                if !UpdateLayeredWindowIndirect(hwnd, &info) {
                    info.prcDirty = nil
                    _ = UpdateLayeredWindowIndirect(hwnd, &info)
                }
            } } } } }
        } else {
            let dc = GetDC(hwnd)
            _ = BitBlt(dc, 0, 0, Int32(pxW), Int32(pxH), memDC, 0, 0, DWORD(SRCCOPY))
            ReleaseDC(hwnd, dc)
        }
        lastBox = box
    }

    // MARK: Native events

    private var trackingView: NSView?
    private var pressCount = 0, lastPressAt = 0.0, lastPressSpot = CGPoint.zero
    private var hoverViews: [ObjectIdentifier: Bool] = [:]

    func event(_ type: NSEvent.EventType) -> NSEvent {
        let e = NSEvent()
        e.type = type
        e.window = self
        e.timestamp = CACurrentMediaTime()
        e.locationInWindow = convertPoint(fromScreen: NSEvent.mouseLocation)
        e.modifierFlags = NSEvent.modifierFlagsNow
        return e
    }

    func handle(_ m: UINT, _ w: WPARAM, _ l: LPARAM) -> LRESULT? {
        switch Int32(m) {
        case WM_MOUSEACTIVATE:
            if layered { return LRESULT(MA_NOACTIVATE) }
            return nil
        case WM_NCHITTEST:
            return nil
        case WM_LBUTTONDOWN, WM_LBUTTONDBLCLK, WM_RBUTTONDOWN, WM_RBUTTONUP, WM_LBUTTONUP, WM_MOUSEMOVE, WM_MOUSEWHEEL:
            NSApp.refreshPointer()
            mouse(Int32(m), w)
            return 0
        case WM_CAPTURECHANGED:
            if let t = trackingView, lParamWindow(l) != hwnd {
                let e = event(.leftMouseUp)
                trackingView = nil
                if !NSApp.pointerInjected { t.mouseUp(with: e) }
            }
            return 0
        case WM_KEYDOWN, WM_SYSKEYDOWN:
            if key(down: true, vk: Int32(w), l) { return 0 }
            return nil
        case WM_KEYUP:
            if key(down: false, vk: Int32(w), l) { return 0 }
            return nil
        case WM_CHAR:
            if character(UInt32(w)) { return 0 }
            return nil
        case WM_PAINT:
            var ps = PAINTSTRUCT()
            let dc = BeginPaint(hwnd, &ps)
            if let memDC, !layered { _ = BitBlt(dc, 0, 0, Int32(pxW), Int32(pxH), memDC, 0, 0, DWORD(SRCCOPY)) }
            EndPaint(hwnd, &ps)
            return 0
        case WM_ERASEBKGND:
            return layered ? nil : 1
        case WM_SIZE, WM_MOVE:
            if !ignoreNativeMove, !layered { syncFrameFromNative() }
            return nil
        case WM_ACTIVATE:
            let active = (w & 0xFFFF) != 0
            if active { NSApp.keyWindowStore = self }
            post(active ? NSWindow.didBecomeKeyNotification : NSWindow.didResignKeyNotification)
            return nil
        case WM_CLOSE:
            performClose(nil)
            return 0
        case WM_COMMAND:
            NSMenu.performNative(id: Int(w & 0xFFFF))
            return 0
        case WM_SETCURSOR:
            if NSCursor.applyCurrent() { return 1 }
            return nil
        case WM_APP_TRAY:
            NSStatusBar.handleTray(l)
            return 0
        case WM_TIMER:
            NSApp.frame()
            return 0
        default:
            return nil
        }
    }
    private func lParamWindow(_ l: LPARAM) -> HWND? { HWND(bitPattern: Int(l)) }

    private func syncFrameFromNative() {
        guard let hwnd else { return }
        var r = RECT()
        _ = GetWindowRect(hwnd, &r)
        let k = NSScreen.primaryScale
        let tl = pixelToWorld(x: r.left, y: r.top)
        let f = CGRect(x: tl.x, y: tl.y - CGFloat(r.bottom - r.top) / k, width: CGFloat(r.right - r.left) / k, height: CGFloat(r.bottom - r.top) / k)
        guard f != frame else { return }
        let resized = f.size != frame.size
        frame = f
        if resized {
            contentView?.frame.size = contentRect(forFrameRect: f).size
            markLayout()
            dirty = true
            post(NSWindow.didResizeNotification)
            delegate?.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: self))
        } else {
            post(NSWindow.didMoveNotification)
        }
    }

    private func mouse(_ msg: Int32, _ w: WPARAM) {
        guard let content = contentView else { return }
        let loc = convertPoint(fromScreen: NSEvent.mouseLocation)
        let type: NSEvent.EventType
        switch msg {
        case WM_LBUTTONDOWN, WM_LBUTTONDBLCLK: type = .leftMouseDown
        case WM_LBUTTONUP: type = .leftMouseUp
        case WM_RBUTTONDOWN: type = .rightMouseDown
        case WM_RBUTTONUP: type = .rightMouseUp
        case WM_MOUSEWHEEL: type = .scrollWheel
        default: type = trackingView != nil ? .leftMouseDragged : .mouseMoved
        }
        let e = event(type)
        e.locationInWindow = loc
        if type == .leftMouseDown || type == .rightMouseDown {
            let now = e.timestamp
            let near = hypot(loc.x - lastPressSpot.x, loc.y - lastPressSpot.y) < 4
            if now - lastPressAt < Double(GetDoubleClickTime()) / 1000, near, msg == WM_LBUTTONDBLCLK || pressCount > 0 { pressCount += 1 } else { pressCount = 1 }
            lastPressAt = now
            lastPressSpot = loc
            e.clickCount = pressCount
            if let hwnd { SetCapture(hwnd) }
        } else {
            e.clickCount = pressCount
        }
        if type == .scrollWheel {
            let d = CGFloat(Int16(truncatingIfNeeded: Int(w >> 16)))
            let lines = d / CGFloat(WHEEL_DELTA)
            e.scrollingDeltaY = lines
            e.deltaY = lines
            // A precision touchpad sends fractions of a notch; call those "precise", in points, as a Mac trackpad does.
            e.hasPreciseScrollingDeltas = abs(d) < CGFloat(WHEEL_DELTA) && abs(d) > 0
            if e.hasPreciseScrollingDeltas { e.scrollingDeltaY = d / 4 }
        }
        guard let ev = NSEvent.filterLocal(e) else { return }
        switch type {
        case .leftMouseDown, .rightMouseDown:
            let hit = content.hitTest(CGPoint(x: loc.x, y: loc.y)) ?? content
            if type == .leftMouseDown {
                trackingView = hit
                if hit.acceptsFirstResponder { _ = makeFirstResponder(hit) } else if !(firstResponder is NSWindow) { endEditingIfOutside(hit) }
                hit.mouseDown(with: ev)
            } else if let m = hit.menu(for: ev) {
                m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            } else {
                hit.rightMouseDown(with: ev)
            }
        case .leftMouseDragged:
            trackingView?.mouseDragged(with: ev)
        case .leftMouseUp:
            let t = trackingView
            trackingView = nil
            ReleaseCapture()
            t?.mouseUp(with: ev)
        case .rightMouseUp:
            ReleaseCapture()
            (content.hitTest(loc) ?? content).rightMouseUp(with: ev)
        case .scrollWheel:
            (content.hitTest(loc) ?? content).scrollWheel(with: ev)
        default:
            updateHover(loc, ev)
            if acceptsMouseMovedEvents { (content.hitTest(loc) ?? content).mouseMoved(with: ev) }
        }
    }
    private func endEditingIfOutside(_ hit: NSView) {
        if let fr = firstResponder as? NSView, !hit.isDescendant(of: fr) { _ = makeFirstResponder(nil) }
    }
    func dispatch(_ e: NSEvent) {
        guard let content = contentView else { return }
        let hit = content.hitTest(e.locationInWindow) ?? content
        switch e.type {
        case .leftMouseDown: trackingView = hit; hit.mouseDown(with: e)
        case .leftMouseDragged: trackingView?.mouseDragged(with: e)
        case .leftMouseUp: let t = trackingView; trackingView = nil; t?.mouseUp(with: e)
        case .rightMouseDown: hit.rightMouseDown(with: e)
        case .scrollWheel: hit.scrollWheel(with: e)
        case .keyDown: (firstResponder ?? self).keyDown(with: e)
        default: break
        }
    }
    func updateHover(_ loc: CGPoint, _ ev: NSEvent) {
        guard let content = contentView else { return }
        var views: [NSView] = []
        content.allTrackingViews(into: &views)
        for v in views {
            for t in v.trackingAreas {
                let p = v.convert(loc, from: nil)
                let r = t.options.contains(.inVisibleRect) ? v.bounds : t.rect
                let inside = r.contains(p) && !v.isHiddenOrHasHiddenAncestor
                guard let owner = t.owner as? NSResponder else { continue }
                if inside != t.inside {
                    t.inside = inside
                    if t.options.contains(.mouseEnteredAndExited) {
                        let e = event(inside ? .mouseEntered : .mouseExited)
                        e.trackingArea = t
                        if inside { owner.mouseEntered(with: e) } else { owner.mouseExited(with: e) }
                    }
                }
                if inside, t.options.contains(.mouseMoved) { owner.mouseMoved(with: ev) }
            }
        }
        // The pointer leaving altogether is seen by the pump, not by a message: ask to hear of it.
        var tme = TRACKMOUSEEVENT(cbSize: DWORD(MemoryLayout<TRACKMOUSEEVENT>.size), dwFlags: DWORD(TME_LEAVE), hwndTrack: hwnd, dwHoverTime: 0)
        _ = TrackMouseEvent(&tme)
    }
    func pointerLeft() {
        updateHover(CGPoint(x: -99999, y: -99999), event(.mouseExited))
    }

    private func key(down: Bool, vk: Int32, _ l: LPARAM) -> Bool {
        let e = event(down ? .keyDown : .keyUp)
        e.keyCode = KeyCodes.macCode(forVirtualKey: vk)
        e.isARepeat = down && (Int(l) & 0x4000_0000) != 0
        e.characters = KeyCodes.characters(forVirtualKey: vk)
        e.charactersIgnoringModifiers = e.characters
        guard let ev = NSEvent.filterLocal(e) else { return true }
        let target = firstResponder ?? contentView ?? self
        if down {
            if KeyCodes.isText(vk), (target is NSTextInputClient) { return false }   // WM_CHAR is coming.
            target.keyDown(with: ev)
        } else {
            target.keyUp(with: ev)
        }
        return target is NSTextInputClient || vk == VK_ESCAPE
    }
    private func character(_ c: UInt32) -> Bool {
        guard let t = firstResponder as? NSTextInputClient, let s = Unicode.Scalar(c), c >= 32, c != 127 else { return false }
        t.insertText(String(Character(s)))
        return true
    }
}

public protocol NSTextInputClient: AnyObject { func insertText(_ s: String) }

open class NSPanel: NSWindow {
    open var isFloatingPanel = false { didSet { if isFloatingPanel, level < .floating { level = .floating } } }
    open var becomesKeyOnlyIfNeededPanel = false
    open override var canBecomeKey: Bool { true }
    open override var canBecomeMain: Bool { false }
}

let WM_APP_TRAY: Int32 = WM_APP + 7

enum KeyCodes {
    /// Windows virtual keys to the Mac key codes the sources compare with (kVK_*).
    static func macCode(forVirtualKey v: Int32) -> UInt16 {
        switch v {
        case VK_ESCAPE: return 53
        case VK_RETURN: return 36
        case VK_TAB: return 48
        case VK_SPACE: return 49
        case VK_BACK: return 51
        case VK_DELETE: return 117
        case VK_LEFT: return 123
        case VK_RIGHT: return 124
        case VK_DOWN: return 125
        case VK_UP: return 126
        case 0x5A: return 6   // Z
        default: return UInt16(truncatingIfNeeded: v + 1000)
        }
    }
    static func isText(_ v: Int32) -> Bool {
        (v >= 0x30 && v <= 0x5A) || (v >= 0x60 && v <= 0x6F) || (v >= 0xBA && v <= 0xE2) || v == VK_SPACE
    }
    static func characters(forVirtualKey v: Int32) -> String {
        switch v {
        case VK_ESCAPE: return "\u{1b}"
        case VK_RETURN: return "\r"
        case VK_TAB: return "\t"
        case VK_BACK: return "\u{7f}"
        case VK_LEFT: return "\u{f702}"
        case VK_RIGHT: return "\u{f703}"
        case VK_UP: return "\u{f700}"
        case VK_DOWN: return "\u{f701}"
        default:
            if v >= 0x30, v <= 0x5A, let s = Unicode.Scalar(UInt32(v)) { return String(Character(s)).lowercased() }
            return ""
        }
    }
}
