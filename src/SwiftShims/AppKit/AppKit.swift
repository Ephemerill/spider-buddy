// AppKit stand-in for Windows: as much of AppKit, Core Text and the Accessibility API as the behavior and
// drawing sources use. Same names and meanings as on the Mac, so those sources compile unchanged. Grows as more
// of the Mac app is brought across. Screens, the window list and the pointer come from the host.
@_exported import CoreGraphics
@_exported import QuartzCore
@_exported import Foundation

public typealias pid_t = Int32

// MARK: Selectors. There is no Objective-C runtime here: the build rewrites #selector(x) to _sel("x", Self.x), a typed
// reference to the method, so targets and actions work the same way without one.

public struct Selector: Hashable, ExpressibleByStringLiteral, @unchecked Sendable {
    public let name: String
    let invoke: ((AnyObject, Any?) -> Void)?
    public init(_ n: String) { name = n; invoke = nil }
    public init(stringLiteral n: String) { name = n; invoke = nil }
    init(name: String, invoke: @escaping (AnyObject, Any?) -> Void) { self.name = name; self.invoke = invoke }
    public static func == (a: Selector, b: Selector) -> Bool { a.name == b.name }
    public func hash(into h: inout Hasher) { h.combine(name) }
    /// Sends it. False if it has no method to go to (a responder-chain action such as `cut:`).
    @discardableResult public func send(to target: AnyObject?, from sender: Any?) -> Bool {
        guard let invoke, let target else { return false }
        invoke(target, sender)
        return true
    }
}
public func _sel<T: AnyObject>(_ n: String, _ f: @escaping (T) -> () -> Void) -> Selector {
    Selector(name: n) { t, _ in if let t = t as? T { f(t)() } }
}
public func _sel<T: AnyObject, A>(_ n: String, _ f: @escaping (T) -> (A) -> Void) -> Selector {
    Selector(name: n) { t, s in
        guard let t = t as? T else { return }
        if let a = s as? A { f(t)(a) } else if let a = Optional<Any>.none as? A { f(t)(a) }
    }
}
public func _sel<T: AnyObject, R>(_ n: String, _ f: @escaping (T) -> () -> R) -> Selector {
    Selector(name: n) { t, _ in if let t = t as? T { _ = f(t)() } }
}

extension NotificationCenter {
    /// The selector form of addObserver, which Foundation has only with Objective-C.
    public func addObserver(_ observer: AnyObject, selector: Selector, name: Notification.Name?, object: Any?) {
        weak var o = observer
        _ = addObserver(forName: name, object: object as AnyObject?, queue: nil) { n in
            if let o { selector.send(to: o, from: n) }
        }
    }
}
public typealias NSPoint = CGPoint
public typealias NSSize = CGSize
public typealias NSRect = CGRect

// MARK: Colors

// MARK: Screens

public struct NSDeviceDescriptionKey: Hashable, Sendable { public let rawValue: String; public init(_ s: String) { rawValue = s }; public init(rawValue: String) { self.rawValue = rawValue } }
public typealias CGDirectDisplayID = UInt32

public final class NSScreen: NSObject, @unchecked Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let backingScaleFactor: CGFloat
    public var safeAreaInsets = NSEdgeInsets()   // No notch on Windows.
    public var localizedName = "Display"
    public var screenNumber = 1
    public struct DeviceKey: Hashable { public let rawValue: String; public init(_ s: String) { rawValue = s }; public init(rawValue: String) { self.rawValue = rawValue } }
    public var deviceDescription: [NSDeviceDescriptionKey: Any] { [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: screenNumber)] }
    public var maximumFramesPerSecond: Int { 60 }
    public var colorSpace: NSColorSpace? { .sRGB }
    /// A display link for this screen. The frame source drives it (see Window.swift).
    public func displayLink(target: AnyObject, selector: Selector) -> CADisplayLink {
        weak var t = target
        return CADisplayLink { if let t { selector.send(to: t, from: nil) } }
    }
    public init(frame: CGRect, visibleFrame: CGRect, backingScaleFactor: CGFloat) {
        self.frame = frame; self.visibleFrame = visibleFrame; self.backingScaleFactor = backingScaleFactor
    }
    /// Set by the host. For headless comparison runs, SPIDER_SHIM_SCREEN="x,y,w,h,vx,vy,vw,vh,scale,topInset"
    /// states the display the Mac oracle ran on, because the Mac tools read the real main screen.
    nonisolated(unsafe) public static var screens: [NSScreen] = {
        guard let e = ProcessInfo.processInfo.environment["SPIDER_SHIM_SCREEN"] else { return [] }
        let v = e.split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
        guard v.count >= 9 else { return [] }
        let s = NSScreen(frame: CGRect(x: v[0], y: v[1], width: v[2], height: v[3]),
                         visibleFrame: CGRect(x: v[4], y: v[5], width: v[6], height: v[7]), backingScaleFactor: v[8])
        if v.count > 9 { s.safeAreaInsets.top = v[9] }
        return [s]
    }()
    public static var main: NSScreen? { screens.first }
}

// MARK: Apps

public enum NSApplicationActivationPolicy: Int, Sendable { case regular, accessory, prohibited }
public typealias ActivationPolicy = NSApplicationActivationPolicy

public final class NSRunningApplication: NSObject, @unchecked Sendable {
    public var processIdentifier: Int32 = 0
    public var bundleIdentifier: String? = nil
    public var localizedName: String? = nil
    public var activationPolicy = NSApplicationActivationPolicy.regular
    public override init() { super.init() }
    /// Set by the host: what is known about a process.
    nonisolated(unsafe) public static var lookup: (Int32) -> NSRunningApplication? = { _ in nil }
    public convenience init?(processIdentifier pid: Int32) {
        guard let known = NSRunningApplication.lookup(pid) else { return nil }
        self.init()
        processIdentifier = known.processIdentifier
        bundleIdentifier = known.bundleIdentifier
        localizedName = known.localizedName
        activationPolicy = known.activationPolicy
    }
    public static func runningApplications(withBundleIdentifier id: String) -> [NSRunningApplication] { [] }
}
public final class NSWorkspace: NSObject, @unchecked Sendable {
    public static let shared = NSWorkspace()
    public var runningApplications: [NSRunningApplication] { [] }
    public let notificationCenter = NotificationCenter()
    public var frontmostApplication: NSRunningApplication? { nil }
    public var menuBarOwningApplication: NSRunningApplication? { nil }
    public static let willSleepNotification = Notification.Name("NSWorkspaceWillSleepNotification")
    public static let didWakeNotification = Notification.Name("NSWorkspaceDidWakeNotification")
    public static let screensDidSleepNotification = Notification.Name("NSWorkspaceScreensDidSleepNotification")
    public static let screensDidWakeNotification = Notification.Name("NSWorkspaceScreensDidWakeNotification")
    public static let sessionDidResignActiveNotification = Notification.Name("NSWorkspaceSessionDidResignActiveNotification")
    public static let sessionDidBecomeActiveNotification = Notification.Name("NSWorkspaceSessionDidBecomeActiveNotification")
    public static let activeSpaceDidChangeNotification = Notification.Name("NSWorkspaceActiveSpaceDidChangeNotification")
    public static let didActivateApplicationNotification = Notification.Name("NSWorkspaceDidActivateApplicationNotification")
    public struct DesktopImageOptionKey: Hashable { public let rawValue: String }
    public func desktopImageURL(for s: NSScreen) -> URL? { nil }
    public func desktopImageOptions(for s: NSScreen) -> [DesktopImageOptionKey: Any]? { nil }
    @discardableResult public func open(_ url: URL) -> Bool { ShellOpen.open(url.isFileURL ? url.path : url.absoluteString) }
    public func activateFileViewerSelecting(_ urls: [URL]) { if let u = urls.first { ShellOpen.reveal(u.path) } }
    public func selectFile(_ path: String?, inFileViewerRootedAtPath root: String) -> Bool { if let path { ShellOpen.reveal(path) }; return true }
    public func icon(forFile path: String) -> NSImage { NSImage(size: CGSize(width: 16, height: 16)) }
}

// MARK: Accessibility: the Mac reads the Dock through it. Windows has none: always "not trusted".

public final class AXUIElement {}
public final class AXValue {}
public enum AXError: Int32, Sendable { case success = 0, failure = -25200 }
public enum AXValueType: Int32, Sendable { case illegal, cgPoint, cgSize, cgRect, cfRange }
public func AXIsProcessTrusted() -> Bool { false }
public func AXUIElementCreateApplication(_ pid: Int32) -> AXUIElement { AXUIElement() }
public func AXUIElementSetMessagingTimeout(_ e: AXUIElement, _ t: Float) {}
public func AXUIElementCopyAttributeValue(_ e: AXUIElement, _ k: CFString, _ v: UnsafeMutablePointer<CFTypeRef?>) -> AXError { .failure }
public func AXValueGetValue<T>(_ v: AXValue, _ t: AXValueType, _ out: UnsafeMutablePointer<T>) -> Bool { false }
public let kAXChildrenAttribute: CFString = "AXChildren"
public let kAXRoleAttribute: CFString = "AXRole"
public let kAXListRole: CFString = "AXList"
public let kAXPositionAttribute: CFString = "AXPosition"
public let kAXSizeAttribute: CFString = "AXSize"

public func CFPreferencesAppSynchronize(_ app: CFString) -> Bool { true }

public func autoreleasepool<T>(_ body: () throws -> T) rethrows -> T { try body() }

// MARK: Core Text, as far as the name tag and the thought bubble use it

public final class CTFont: @unchecked Sendable {
    public let name: String, size: CGFloat
    init(name: String, size: CGFloat) { self.name = name; self.size = size }
}
public func CTFontCreateWithName(_ name: CFString, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?) -> CTFont {
    CTFont(name: name, size: size)
}

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
    public static let foregroundColor = NSAttributedString.Key("NSColor")
    public static let backgroundColor = NSAttributedString.Key("NSBackgroundColor")
    public static let kern = NSAttributedString.Key("NSKern")
    public static let paragraphStyle = NSAttributedString.Key("NSParagraphStyle")
    public static let underlineStyle = NSAttributedString.Key("NSUnderline")
    public static let strikethroughStyle = NSAttributedString.Key("NSStrikethrough")
    public static let link = NSAttributedString.Key("NSLink")
    public static let baselineOffset = NSAttributedString.Key("NSBaselineOffset")
    public static let shadow = NSAttributedString.Key("NSShadow")
}

public final class CTLine: @unchecked Sendable {
    public let text: String
    public let font: CTFont?
    public let color: CGColor
    init(text: String, font: CTFont?, color: CGColor) { self.text = text; self.font = font; self.color = color }
}

/// Measures text. The host sets it to real font metrics; this default is a close estimate for headless runs.
nonisolated(unsafe) public var CTTextMeasure: (_ text: String, _ font: String, _ size: CGFloat) -> (width: CGFloat, ascent: CGFloat, descent: CGFloat) = { text, font, size in
    #if os(Windows)
    if SkiaText.available { return SkiaText.measure(text, font: font, size: size) }
    #endif
    return (CGFloat(text.count) * size * 0.52, size * 0.95, size * 0.21)
}

public func CTLineCreateWithAttributedString(_ s: NSAttributedString) -> CTLine {
    let attrs: [NSAttributedString.Key: Any] = s.length > 0 ? s.attributes(at: 0, effectiveRange: nil) : [:]
    let font = (attrs[.font] as? CTFont) ?? (attrs[.font] as? NSFont).map { CTFont(name: $0.fontKey, size: $0.pointSize) }
    let color = (attrs[.foregroundColor] as? NSColor)?.cgColor ?? .black
    return CTLine(text: s.string, font: font, color: color)
}
public func CTLineGetTypographicBounds(_ line: CTLine, _ ascent: UnsafeMutablePointer<CGFloat>?, _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    let m = CTTextMeasure(line.text, line.font?.name ?? "", line.font?.size ?? 12)
    ascent?.pointee = m.ascent
    descent?.pointee = m.descent
    leading?.pointee = 0
    return Double(m.width)
}
public enum CTLineTruncationType: UInt32, Sendable { case start, end, middle }
public func CTLineCreateTruncatedLine(_ line: CTLine, _ width: Double, _ type: CTLineTruncationType, _ token: CTLine?) -> CTLine? {
    var chars = Array(line.text)
    let ell = token?.text ?? "…"
    func w(_ t: String) -> Double { Double(CTTextMeasure(t, line.font?.name ?? "", line.font?.size ?? 12).width) }
    if w(line.text) <= width { return line }
    while !chars.isEmpty, w(String(chars) + ell) > width { chars.removeLast() }
    return CTLine(text: String(chars) + ell, font: line.font, color: line.color)
}
public func CTLineDraw(_ line: CTLine, _ ctx: CGContext) {
    ctx.backend.drawText(line.text, font: line.font?.name ?? "", size: line.font?.size ?? 12, color: line.color, at: ctx.textPosition.applying(ctx.state.ctm), state: ctx.state)
}
