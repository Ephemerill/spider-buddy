// NSResponder, NSEvent, NSView. A view always has a backing layer here: its position in the layer tree comes from its frame,
// and its own drawing runs as that layer's content. Everything composites through QuartzCore.
import Foundation
import QuartzCore

// MARK: Events

public final class NSEvent: NSObject, @unchecked Sendable {
    public enum EventType: UInt, Sendable {
        case leftMouseDown = 1, leftMouseUp, rightMouseDown, rightMouseUp, mouseMoved, leftMouseDragged, rightMouseDragged,
             mouseEntered, mouseExited, keyDown, keyUp, flagsChanged, scrollWheel = 22, otherMouseDown = 25, otherMouseUp, otherMouseDragged, pressure = 34,
             appKitDefined = 13, systemDefined = 14, applicationDefined = 15, periodic = 16, cursorUpdate = 17
    }
    public struct EventTypeMask: OptionSet, Sendable {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }
        static func of(_ t: EventType) -> Self { Self(rawValue: 1 << UInt64(t.rawValue)) }
        public static let leftMouseDown = of(.leftMouseDown), leftMouseUp = of(.leftMouseUp), rightMouseDown = of(.rightMouseDown), rightMouseUp = of(.rightMouseUp),
            mouseMoved = of(.mouseMoved), leftMouseDragged = of(.leftMouseDragged), rightMouseDragged = of(.rightMouseDragged), mouseEntered = of(.mouseEntered),
            mouseExited = of(.mouseExited), keyDown = of(.keyDown), keyUp = of(.keyUp), flagsChanged = of(.flagsChanged), scrollWheel = of(.scrollWheel),
            otherMouseDown = of(.otherMouseDown), otherMouseUp = of(.otherMouseUp), otherMouseDragged = of(.otherMouseDragged)
        public static let any = Self(rawValue: .max)
    }
    public struct ModifierFlags: OptionSet, Sendable, Hashable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let capsLock = Self(rawValue: 1 << 16), shift = Self(rawValue: 1 << 17), control = Self(rawValue: 1 << 18), option = Self(rawValue: 1 << 19), command = Self(rawValue: 1 << 20), numericPad = Self(rawValue: 1 << 21), function = Self(rawValue: 1 << 23)
        public static let deviceIndependentFlagsMask = Self(rawValue: 0xffff0000)
    }
    public enum Phase: Sendable { case none, began, stationary, changed, ended, cancelled, mayBegin }
    public var type: EventType = .mouseMoved
    public var locationInWindow = CGPoint.zero
    public var clickCount = 1
    public var pressure: Float = 0
    public var stage = 0
    public var modifierFlags = ModifierFlags()
    public var deltaX: CGFloat = 0, deltaY: CGFloat = 0
    public var scrollingDeltaX: CGFloat = 0
    public var scrollingDeltaY: CGFloat = 0
    public var hasPreciseScrollingDeltas = false
    public var isDirectionInvertedFromDevice = false
    public var phase = Phase.none
    public var momentumPhase = Phase.none
    public var timestamp: TimeInterval = 0
    public var keyCode: UInt16 = 0
    public var characters: String? = nil
    public var charactersIgnoringModifiers: String? = nil
    public var isARepeat = false
    public weak var window: NSWindow? = nil
    public var trackingArea: NSTrackingArea? = nil
    public var cgEvent: CGEventShim? { nil }

    /// Starts a trackpad gesture? Windows has no gesture phases: the core's own 0.35 s gap rule covers it.
    public var startsScrollGesture: Bool { phase == .began }

    /// Kept current by the app's event pump.
    nonisolated(unsafe) public static var mouseLocation = CGPoint.zero
    nonisolated(unsafe) public static var pressedMouseButtons = 0
    nonisolated(unsafe) public static var modifierFlagsNow = ModifierFlags()
    public static var modifierFlags: ModifierFlags { modifierFlagsNow }

    public override init() { super.init() }

    public static func mouseEvent(with type: EventType, location: CGPoint, modifierFlags: ModifierFlags, timestamp: TimeInterval, windowNumber: Int, context: Any?, eventNumber: Int, clickCount: Int, pressure: Float) -> NSEvent? {
        let e = NSEvent()
        e.type = type; e.locationInWindow = location; e.modifierFlags = modifierFlags; e.timestamp = timestamp
        e.clickCount = clickCount; e.pressure = pressure
        e.window = NSApplication.shared.windows.first { $0.windowNumber == windowNumber }
        return e
    }
    public static func keyEvent(with type: EventType, location: CGPoint, modifierFlags: ModifierFlags, timestamp: TimeInterval, windowNumber: Int, context: Any?, characters: String, charactersIgnoringModifiers: String, isARepeat: Bool, keyCode: UInt16) -> NSEvent? {
        let e = NSEvent()
        e.type = type; e.locationInWindow = location; e.modifierFlags = modifierFlags; e.timestamp = timestamp
        e.characters = characters; e.charactersIgnoringModifiers = charactersIgnoringModifiers; e.isARepeat = isARepeat; e.keyCode = keyCode
        return e
    }

    // Monitors. Local ones see events going to this app's windows; global ones are fed by the pump's polling of input.
    final class Monitor { let mask: EventTypeMask; let local: ((NSEvent) -> NSEvent?)?; let global: ((NSEvent) -> Void)?
        init(_ m: EventTypeMask, local: ((NSEvent) -> NSEvent?)?, global: ((NSEvent) -> Void)?) { mask = m; self.local = local; self.global = global } }
    nonisolated(unsafe) static var monitors: [Monitor] = []
    public static func addLocalMonitorForEvents(matching mask: EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        let m = Monitor(mask, local: handler, global: nil); monitors.append(m); return m
    }
    public static func addGlobalMonitorForEvents(matching mask: EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
        let m = Monitor(mask, local: nil, global: handler); monitors.append(m); return m
    }
    public static func removeMonitor(_ m: Any) { monitors.removeAll { $0 === (m as AnyObject) } }
    /// Runs local monitors. nil means an event has been swallowed.
    static func filterLocal(_ e: NSEvent) -> NSEvent? {
        var ev: NSEvent? = e
        for m in monitors where m.local != nil && m.mask.contains(.of(e.type)) {
            guard let cur = ev else { return nil }
            ev = m.local!(cur)
        }
        return ev
    }
    static func sendGlobal(_ e: NSEvent) {
        for m in monitors where m.global != nil && m.mask.contains(.of(e.type)) { m.global!(e) }
    }
}
public typealias CGEventShim = AnyObject

public final class NSTrackingArea: NSObject {
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mouseEnteredAndExited = Self(rawValue: 1), mouseMoved = Self(rawValue: 2), cursorUpdate = Self(rawValue: 4), activeWhenFirstResponder = Self(rawValue: 0x10), activeInKeyWindow = Self(rawValue: 0x20), activeInActiveApp = Self(rawValue: 0x40), activeAlways = Self(rawValue: 0x80), assumeInside = Self(rawValue: 0x100), inVisibleRect = Self(rawValue: 0x200), enabledDuringMouseDrag = Self(rawValue: 0x400)
    }
    public var rect: CGRect
    public let options: Options
    public weak var owner: AnyObject?
    public let userInfo: [AnyHashable: Any]?
    var inside = false
    public init(rect: CGRect, options: Options, owner: Any?, userInfo: [AnyHashable: Any]?) {
        self.rect = rect; self.options = options; self.owner = owner as AnyObject?; self.userInfo = userInfo
    }
}

// MARK: Responder

open class NSResponder: NSObject {
    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    open var nextResponder: NSResponder? = nil
    open var acceptsFirstResponder: Bool { false }
    open func becomeFirstResponder() -> Bool { true }
    open func resignFirstResponder() -> Bool { true }
    open func mouseDown(with event: NSEvent) { nextResponder?.mouseDown(with: event) }
    open func mouseDragged(with event: NSEvent) { nextResponder?.mouseDragged(with: event) }
    open func mouseUp(with event: NSEvent) { nextResponder?.mouseUp(with: event) }
    open func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }
    open func rightMouseDragged(with event: NSEvent) { nextResponder?.rightMouseDragged(with: event) }
    open func rightMouseUp(with event: NSEvent) { nextResponder?.rightMouseUp(with: event) }
    open func otherMouseDown(with event: NSEvent) { nextResponder?.otherMouseDown(with: event) }
    open func mouseMoved(with event: NSEvent) { nextResponder?.mouseMoved(with: event) }
    open func mouseEntered(with event: NSEvent) {}
    open func mouseExited(with event: NSEvent) {}
    open func cursorUpdate(with event: NSEvent) {}
    open func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    open func pressureChange(with event: NSEvent) {}
    open func keyDown(with event: NSEvent) { nextResponder?.keyDown(with: event) }
    open func keyUp(with event: NSEvent) { nextResponder?.keyUp(with: event) }
    open func flagsChanged(with event: NSEvent) { nextResponder?.flagsChanged(with: event) }
    open func cancelOperation(_ sender: Any?) { nextResponder?.cancelOperation(sender) }
    open func performKeyEquivalent(with event: NSEvent) -> Bool { false }
    open func magnify(with event: NSEvent) { nextResponder?.magnify(with: event) }
    open func noResponder(for s: Selector) {}
    open func interpretKeyEvents(_ events: [NSEvent]) {}
    open func doCommand(by s: Selector) {}
    open func moveLeft(_ sender: Any?) {}
    open func moveRight(_ sender: Any?) {}
}

public struct NSEdgeInsets: Equatable, Sendable {
    public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat
    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
}
public func NSEdgeInsetsMake(_ t: CGFloat, _ l: CGFloat, _ b: CGFloat, _ r: CGFloat) -> NSEdgeInsets { NSEdgeInsets(top: t, left: l, bottom: b, right: r) }
public let NSEdgeInsetsZero = NSEdgeInsets()
public let NSViewNoIntrinsicMetric: CGFloat = -1
public func NSRectFill(_ r: CGRect) { NSGraphicsContext.current?.cgContext.fill(r) }
public func NSZeroRectValue() -> CGRect { .zero }
public let NSZeroRect = CGRect.zero
public let NSZeroSize = CGSize.zero
public let NSZeroPoint = CGPoint.zero
public func NSMakeRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
public func NSMakeSize(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
public func NSMakePoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
public func NSStringFromRect(_ r: CGRect) -> String { "{{\(r.minX), \(r.minY)}, {\(r.width), \(r.height)}}" }

// MARK: Views

open class NSView: NSResponder {
    public struct AutoresizingMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let none = Self([]), minXMargin = Self(rawValue: 1), width = Self(rawValue: 2), maxXMargin = Self(rawValue: 4), minYMargin = Self(rawValue: 8), height = Self(rawValue: 16), maxYMargin = Self(rawValue: 32)
    }
    public struct NSViewLayerContentsPlacement { }
    public enum LayerContentsRedrawPolicy: Int, Sendable { case never, onSetNeedsDisplay, duringViewResize, beforeViewResize, crossfade }

    /// The backing layer. `layer` stays nil until asked for, as the Mac's does, but the view draws through this either way.
    public let backing = CALayer()
    private var customLayer: CALayer?
    open var layer: CALayer? {
        get { customLayer ?? (wantsLayer ? backing : nil) }
        set {
            customLayer?.removeFromSuperlayer()
            customLayer = newValue
            if let newValue { backing.addSublayer(newValue); newValue.frame = bounds; newValue.host = nil }
            syncLayer()
        }
    }
    open var wantsLayer = false { didSet { syncLayer() } }
    open var layerContentsRedrawPolicy = LayerContentsRedrawPolicy.onSetNeedsDisplay
    open var wantsUpdateLayer: Bool { false }
    open func updateLayer() {}

    public var frame: CGRect {
        didSet {
            if frame.size != oldValue.size {
                resizeSubviews(withOldSize: oldValue.size)
                customLayer?.frame = CGRect(origin: .zero, size: frame.size)
                needsDisplay = true
                needsLayout = true
            }
            syncLayer()
            superview?.syncChildren()
        }
    }
    open var bounds: CGRect {
        get { boundsStore ?? CGRect(origin: .zero, size: frame.size) }
        set { boundsStore = newValue; if newValue.size != frame.size { frame.size = newValue.size }; syncLayer(); syncChildren() }
    }
    private var boundsStore: CGRect?
    public func setBoundsOrigin(_ p: CGPoint) { bounds = CGRect(origin: p, size: frame.size) }
    public func setFrameOrigin(_ p: CGPoint) { frame.origin = p }
    public func setFrameSize(_ s: CGSize) { frame.size = s }
    public func setBoundsSize(_ s: CGSize) { bounds.size = s }

    public private(set) var subviews: [NSView] = []
    public private(set) weak var superview: NSView?
    public weak var windowStore: NSWindow?
    open var window: NSWindow? { windowStore ?? superview?.window }
    open var isFlipped: Bool { false }
    open var isHidden = false {
        didSet {
            guard isHidden != oldValue else { return }
            backing.isHidden = isHidden
            superview?.needsLayout = true
        }
    }
    public var isHiddenOrHasHiddenAncestor: Bool { isHidden || (superview?.isHiddenOrHasHiddenAncestor ?? false) }
    open var alphaValue: CGFloat { get { CGFloat(backing.opacity) } set { backing.opacity = Float(newValue) } }
    open var frameRotation: CGFloat = 0
    open var toolTip: String?
    open var tag: Int { -1 }
    open var isOpaque: Bool { false }
    public var autoresizingMask = AutoresizingMask.none
    public var autoresizesSubviews = true
    public var translatesAutoresizingMaskIntoConstraints = true { didSet { needsLayout = true } }
    open var needsDisplay = false {
        didSet { if needsDisplay { backing.setNeedsDisplay(); needsDisplay = false } }
    }
    private var layoutFlag = true
    open var needsLayout: Bool {
        get { layoutFlag }
        set { layoutFlag = newValue; if newValue { window?.markLayout() } }
    }
    open var needsUpdateConstraints = false
    open var identifier: NSUserInterfaceItemIdentifier?
    open var userInterfaceLayoutDirection = NSUserInterfaceLayoutDirection.leftToRight
    open var effectiveAppearance: NSAppearance { appearance ?? superview?.effectiveAppearance ?? NSApp.effectiveAppearance }
    open var appearance: NSAppearance? { didSet { needsDisplay = true } }
    open var enclosingScrollView: NSScrollView? { (superview as? NSScrollView) ?? superview?.enclosingScrollView }
    open var visibleRect: CGRect { bounds }
    open var inLiveResize: Bool { false }
    open var mouseDownCanMoveWindow: Bool { false }
    open var canBecomeKeyView: Bool { false }
    open var acceptsTouchEvents = false
    open var allowedTouchTypes: Int = 0
    open var focusRingType = NSFocusRingType.default
    public var shadow: NSShadow? { didSet { needsDisplay = true } }
    public var compositingFilter: Any? = nil
    public var backgroundFilters: [Any] = []
    public var postsFrameChangedNotifications = false
    public var pressureConfiguration: Any? = nil

    public init(frame frameRect: CGRect) {
        frame = frameRect
        super.init()
        setupBacking()
    }
    public required init?(coder: NSCoder) { frame = .zero; super.init(); setupBacking() }
    public convenience override init() { self.init(frame: .zero) }

    private func setupBacking() {
        backing.anchorPoint = .zero
        backing.drawContent = { [unowned self] ctx in self.drawBacking(ctx) }
        syncLayer()
    }
    func drawBacking(_ ctx: CGContext) {
        let prior = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: isFlippedInContext(ctx))
        let flip = isFlipped
        if flip {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        if bounds.origin != .zero { ctx.saveGState(); ctx.translateBy(x: -bounds.minX, y: -bounds.minY) }
        if let s = shadow { s.set() }
        draw(bounds)
        if bounds.origin != .zero { ctx.restoreGState() }
        if flip { ctx.restoreGState() }
        NSGraphicsContext.current = prior
    }
    private func isFlippedInContext(_ c: CGContext) -> Bool { isFlipped }

    /// Places the backing layer from the frame, and puts the backing's sublayers in view order.
    func syncLayer() {
        backing.anchorPoint = .zero
        backing.bounds = CGRect(origin: .zero, size: frame.size)
        guard let sup = superview else { backing.position = frame.origin; return }
        let b = sup.bounds
        let x = frame.minX - b.minX
        let y = sup.isFlipped ? b.height - (frame.minY - b.minY) - frame.height : frame.minY - b.minY
        backing.position = CGPoint(x: x, y: y)
        if sup.clipsSubviewsToBounds { sup.backing.masksToBounds = true }
    }
    func syncChildren() { for v in subviews { v.syncLayer() } }
    open var clipsSubviewsToBounds: Bool { false }
    open var clipsToBounds: Bool { get { backing.masksToBounds } set { backing.masksToBounds = newValue } }

    // MARK: Hierarchy

    open func addSubview(_ v: NSView) { insert(v, at: subviews.count) }
    open func addSubview(_ v: NSView, positioned p: NSWindow.OrderingMode, relativeTo other: NSView?) {
        if let other, let i = subviews.firstIndex(where: { $0 === other }) {
            insert(v, at: p == .above ? i + 1 : i)
        } else {
            insert(v, at: p == .above ? subviews.count : 0)
        }
    }
    private func insert(_ v: NSView, at i: Int) {
        let before = v.window
        if v.superview === self, let old = subviews.firstIndex(where: { $0 === v }) { subviews.remove(at: old) } else { v.removeFromSuperview() }
        let at = min(i, subviews.count)
        subviews.insert(v, at: at)
        v.superview = self
        v.nextResponder = self
        // Order among the backing's sublayers follows the subviews, after any layers of the view's own.
        let siblings = subviews
        if let above = siblings[..<at].last {
            backing.insertSublayer(v.backing, above: above.backing)
        } else {
            backing.addSublayer(v.backing)
        }
        v.syncLayer()
        needsLayout = true
        if before !== v.window { v.notifyWindowChange() }
    }
    func notifyWindowChange() {
        viewDidMoveToWindow()
        for s in subviews { s.notifyWindowChange() }
    }
    open func removeFromSuperview() {
        guard let sup = superview else { return }
        sup.subviews.removeAll { $0 === self }
        backing.removeFromSuperlayer()
        superview = nil
        nextResponder = nil
        sup.needsLayout = true
    }
    open func viewDidMoveToWindow() {}
    open func viewDidMoveToSuperview() {}
    open func viewWillMove(toWindow w: NSWindow?) {}
    open func viewDidChangeEffectiveAppearance() {}
    open func viewDidEndLiveResize() {}
    open func viewWillDraw() {}
    public func isDescendant(of v: NSView) -> Bool { self === v || (superview?.isDescendant(of: v) ?? false) }
    public func ancestorShared(with v: NSView) -> NSView? {
        var a: NSView? = self
        while let c = a { if v.isDescendant(of: c) { return c }; a = c.superview }
        return nil
    }
    public func replaceSubview(_ old: NSView, with new: NSView) {
        guard let i = subviews.firstIndex(where: { $0 === old }) else { return }
        old.removeFromSuperview()
        insert(new, at: i)
    }
    open func sortSubviews() {}

    // MARK: Drawing

    open func draw(_ dirtyRect: CGRect) {}
    open func setNeedsDisplay(_ r: CGRect) { backing.setNeedsDisplay() }
    open func display() { backing.setNeedsDisplay() }
    open func displayIfNeeded() { window?.composite() }
    public func lockFocus() {}
    public func unlockFocus() {}
    open func cacheDisplay(in r: CGRect, to rep: NSBitmapImageRep) {
        guard let ctx = rep.makeContext() else { return }
        ctx.saveGState()
        ctx.scaleBy(x: rep.scale, y: rep.scale)
        ctx.translateBy(x: -r.minX, y: -r.minY)
        let keep = backing.position
        backing.position = .zero
        backing.render(in: ctx, now: CACurrentMediaTime())
        backing.position = keep
        ctx.restoreGState()
        rep.capture()
    }
    open func bitmapImageRepForCachingDisplay(in r: CGRect) -> NSBitmapImageRep? { NSBitmapImageRep(pointSize: r.size) }

    // MARK: Geometry

    /// This view's point in the window's content coordinates (y-up), and back.
    open func convert(_ p: CGPoint, to v: NSView?) -> CGPoint {
        let win = toWindow(p)
        return v?.fromWindow(win) ?? win
    }
    open func convert(_ p: CGPoint, from v: NSView?) -> CGPoint {
        fromWindow(v?.toWindow(p) ?? p)
    }
    open func convert(_ r: CGRect, to v: NSView?) -> CGRect {
        let a = convert(r.origin, to: v), b = convert(CGPoint(x: r.maxX, y: r.maxY), to: v)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
    open func convert(_ r: CGRect, from v: NSView?) -> CGRect {
        let a = convert(r.origin, from: v), b = convert(CGPoint(x: r.maxX, y: r.maxY), from: v)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
    public func convertToLayer(_ p: CGPoint) -> CGPoint { p }
    public func convertToBacking(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * NSScreen.primaryScale, y: p.y * NSScreen.primaryScale) }
    public func convertToBacking(_ s: CGSize) -> CGSize { CGSize(width: s.width * NSScreen.primaryScale, height: s.height * NSScreen.primaryScale) }
    public func convertToBacking(_ r: CGRect) -> CGRect { r.applying(CGAffineTransform(scaleX: NSScreen.primaryScale, y: NSScreen.primaryScale)) }
    public func centerScanRect(_ r: CGRect) -> CGRect { r }
    private func toWindow(_ p: CGPoint) -> CGPoint {
        guard let sup = superview else { return CGPoint(x: p.x - bounds.minX + frame.minX, y: p.y - bounds.minY + frame.minY) }
        let inSup: CGPoint
        let local = CGPoint(x: p.x - bounds.minX, y: p.y - bounds.minY)
        let y = isFlipped ? frame.height - local.y : local.y   // in y-up within the frame
        if sup.isFlipped {
            inSup = CGPoint(x: frame.minX + local.x, y: frame.maxY - y)
        } else {
            inSup = CGPoint(x: frame.minX + local.x, y: frame.minY + y)
        }
        return sup.toWindow(inSup)
    }
    private func fromWindow(_ p: CGPoint) -> CGPoint {
        guard let sup = superview else { return CGPoint(x: p.x - frame.minX + bounds.minX, y: p.y - frame.minY + bounds.minY) }
        let s = sup.fromWindow(p)
        let up = sup.isFlipped ? frame.maxY - s.y : s.y - frame.minY
        return CGPoint(x: s.x - frame.minX + bounds.minX, y: (isFlipped ? frame.height - up : up) + bounds.minY)
    }

    /// `p` is in the superview's coordinates, as AppKit has it.
    open func hitTest(_ p: CGPoint) -> NSView? {
        guard !isHidden, frame.contains(p) else { return nil }
        let local = fromSuperview(p)
        for v in subviews.reversed() {
            if let h = v.hitTest(local) { return h }
        }
        return self
    }
    private func fromSuperview(_ p: CGPoint) -> CGPoint {
        let up = (superview?.isFlipped ?? false) ? frame.maxY - p.y : p.y - frame.minY
        return CGPoint(x: p.x - frame.minX + bounds.minX, y: (isFlipped ? frame.height - up : up) + bounds.minY)
    }
    public func mouse(_ p: CGPoint, in r: CGRect) -> Bool { r.contains(p) }
    public func scroll(_ p: CGPoint) { enclosingScrollView?.scroll(to: p) }
    public func scrollToVisible(_ r: CGRect) -> Bool { enclosingScrollView?.reveal(r, in: self); return true }

    // MARK: Tracking and cursors

    public private(set) var trackingAreas: [NSTrackingArea] = []
    public func addTrackingArea(_ t: NSTrackingArea) { trackingAreas.append(t) }
    public func removeTrackingArea(_ t: NSTrackingArea) { trackingAreas.removeAll { $0 === t } }
    open func updateTrackingAreas() {}
    open func resetCursorRects() {}
    public func addCursorRect(_ r: CGRect, cursor: NSCursor) { cursorRects.append((r, cursor)) }
    public func discardCursorRects() { cursorRects.removeAll() }
    var cursorRects: [(CGRect, NSCursor)] = []
    open func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    open func menu(for e: NSEvent) -> NSMenu? { menu }
    open var menu: NSMenu?
    open func registerForDraggedTypes(_ t: [NSPasteboard.PasteboardType]) {}
    open func unregisterDraggedTypes() {}

    // MARK: Layout

    let layoutVars = LayoutVars()
    var activeConstraints: [NSLayoutConstraint] = []
    public private(set) var layoutGuides: [NSLayoutGuide] = []
    public func addLayoutGuide(_ g: NSLayoutGuide) { g.owningView = self; layoutGuides.append(g) }
    public func removeLayoutGuide(_ g: NSLayoutGuide) { layoutGuides.removeAll { $0 === g } }
    public var constraints: [NSLayoutConstraint] { activeConstraints }
    public func addConstraint(_ c: NSLayoutConstraint) { c.isActive = true }
    public func addConstraints(_ cs: [NSLayoutConstraint]) { for c in cs { c.isActive = true } }
    public func removeConstraint(_ c: NSLayoutConstraint) { c.isActive = false }
    public func removeConstraints(_ cs: [NSLayoutConstraint]) { for c in cs { c.isActive = false } }
    var takesPartInConstraints: Bool { !translatesAutoresizingMaskIntoConstraints }
    /// Constraints a view makes itself (a stack view's).
    func generatedConstraints() -> [NSLayoutConstraint] { [] }
    /// A wrapping label's height depends on its width: true if a new width changed what it wants.
    func widthChangedIntrinsic() -> Bool { false }
    var firstBaselineFromTop: CGFloat { 0 }
    var lastBaselineFromBottom: CGFloat { 0 }

    open var intrinsicContentSize: CGSize { CGSize(width: NSViewNoIntrinsicMetric, height: NSViewNoIntrinsicMetric) }
    public func invalidateIntrinsicContentSize() { needsLayout = true }
    private var hugging: [CGFloat] = [250, 250], resist: [CGFloat] = [750, 750]
    public func contentHuggingPriority(for o: NSLayoutConstraint.Orientation) -> NSLayoutPriority { NSLayoutPriority(Float(hugging[o.rawValue])) }
    public func setContentHuggingPriority(_ p: NSLayoutPriority, for o: NSLayoutConstraint.Orientation) { hugging[o.rawValue] = CGFloat(p.rawValue); needsLayout = true }
    public func contentCompressionResistancePriority(for o: NSLayoutConstraint.Orientation) -> NSLayoutPriority { NSLayoutPriority(Float(resist[o.rawValue])) }
    public func setContentCompressionResistancePriority(_ p: NSLayoutPriority, for o: NSLayoutConstraint.Orientation) { resist[o.rawValue] = CGFloat(p.rawValue); needsLayout = true }
    public var fittingSize: CGSize { LayoutEngine.solve(root: self, size: nil) }
    open func layout() {}
    public func layoutSubtreeIfNeeded() {
        if let w = window { w.layoutIfNeeded(force: true); return }
        LayoutEngine.layout(root: self, size: frame.size)
    }
    public func updateConstraints() {}
    public func updateConstraintsForSubtreeIfNeeded() {}
    public var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    public var firstBaselineOffsetFromTop: CGFloat { firstBaselineFromTop }
    public var lastBaselineOffsetFromBottom: CGFloat { lastBaselineFromBottom }
    public var baselineOffsetFromBottom: CGFloat { lastBaselineFromBottom }

    /// The Mac's autoresizing of frame-based subviews.
    open func resizeSubviews(withOldSize old: CGSize) {
        guard autoresizesSubviews else { return }
        for v in subviews where v.translatesAutoresizingMaskIntoConstraints { v.resize(withOldSuperviewSize: old) }
    }
    open func resize(withOldSuperviewSize old: CGSize) {
        guard let sup = superview, autoresizingMask != .none else { return }
        let dw = sup.frame.width - old.width, dh = sup.frame.height - old.height
        var f = frame
        let m = autoresizingMask
        let xs = [m.contains(.minXMargin), m.contains(.width), m.contains(.maxXMargin)].filter { $0 }.count
        if xs > 0 {
            let part = dw / CGFloat(xs)
            if m.contains(.minXMargin) { f.origin.x += part }
            if m.contains(.width) { f.size.width += part }
        }
        let ys = [m.contains(.minYMargin), m.contains(.height), m.contains(.maxYMargin)].filter { $0 }.count
        if ys > 0 {
            let part = dh / CGFloat(ys)
            if sup.isFlipped {
                if m.contains(.maxYMargin) { f.origin.y += part }
            } else if m.contains(.minYMargin) { f.origin.y += part }
            if m.contains(.height) { f.size.height += part }
        }
        frame = f
    }

    public lazy var leadingAnchor = NSLayoutXAxisAnchor(item: self, attr: .leading)
    public lazy var trailingAnchor = NSLayoutXAxisAnchor(item: self, attr: .trailing)
    public lazy var leftAnchor = NSLayoutXAxisAnchor(item: self, attr: .left)
    public lazy var rightAnchor = NSLayoutXAxisAnchor(item: self, attr: .right)
    public lazy var topAnchor = NSLayoutYAxisAnchor(item: self, attr: .top)
    public lazy var bottomAnchor = NSLayoutYAxisAnchor(item: self, attr: .bottom)
    public lazy var widthAnchor = NSLayoutDimension(item: self, attr: .width)
    public lazy var heightAnchor = NSLayoutDimension(item: self, attr: .height)
    public lazy var centerXAnchor = NSLayoutXAxisAnchor(item: self, attr: .centerX)
    public lazy var centerYAnchor = NSLayoutYAxisAnchor(item: self, attr: .centerY)
    public lazy var firstBaselineAnchor = NSLayoutYAxisAnchor(item: self, attr: .firstBaseline)
    public lazy var lastBaselineAnchor = NSLayoutYAxisAnchor(item: self, attr: .lastBaseline)

    // MARK: Hit-testing convenience for tree walks

    func allTrackingViews(into out: inout [NSView]) {
        if !trackingAreas.isEmpty { out.append(self) }
        for s in subviews where !s.isHidden { s.allTrackingViews(into: &out) }
    }
}

public struct NSUserInterfaceItemIdentifier: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ s: String) { rawValue = s }
}
public enum NSUserInterfaceLayoutDirection: Int, Sendable { case leftToRight, rightToLeft }
public enum NSFocusRingType: UInt, Sendable { case `default`, none, exterior }

open class NSViewController: NSResponder {
    open var view: NSView = NSView(frame: .zero)
    open var preferredContentSize = CGSize.zero
    open var title: String?
    open var representedObject: Any?
    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    open func loadView() {}
    open func viewDidLoad() {}
    open func viewWillAppear() {}
    open func viewDidAppear() {}
}
