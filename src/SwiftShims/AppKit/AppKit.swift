// AppKit stand-in for Windows: as much of AppKit, Core Text and the Accessibility API as the behavior and
// drawing sources use. Same names and meanings as on the Mac, so those sources compile unchanged. Grows as more
// of the Mac app is brought across. Screens, the window list and the pointer come from the host.
@_exported import CoreGraphics
@_exported import QuartzCore
@_exported import Foundation

public typealias pid_t = Int32
public typealias NSPoint = CGPoint
public typealias NSSize = CGSize
public typealias NSRect = CGRect

// MARK: Colors

public final class NSColor: NSObject, @unchecked Sendable {
    public let cgColor: CGColor
    public init(cgColor c: CGColor) { cgColor = c }
    public convenience init(calibratedRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) {
        self.init(cgColor: CGColor(red: r, green: g, blue: b, alpha: a))
    }
    public convenience init(srgbRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) {
        self.init(cgColor: CGColor(red: r, green: g, blue: b, alpha: a))
    }
    public convenience init(red r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) {
        self.init(cgColor: CGColor(srgbRed: r, green: g, blue: b, alpha: a))
    }
    public convenience init(white w: CGFloat, alpha a: CGFloat) { self.init(cgColor: CGColor(gray: w, alpha: a)) }
    public static let black = NSColor(white: 0, alpha: 1)
    public static let white = NSColor(white: 1, alpha: 1)
    public static let clear = NSColor(white: 0, alpha: 0)
    public var redComponent: CGFloat { cgColor.r }
    public var greenComponent: CGFloat { cgColor.g }
    public var blueComponent: CGFloat { cgColor.b }
    public var alphaComponent: CGFloat { cgColor.a }
    public func usingColorSpace(_ s: NSColorSpace) -> NSColor? {
        NSColor(cgColor: CGColor(srgbRed: cgColor.sr, green: cgColor.sg, blue: cgColor.sb, alpha: cgColor.a))
    }
    public func withAlphaComponent(_ a: CGFloat) -> NSColor { NSColor(cgColor: cgColor.copy(alpha: a) ?? cgColor) }
}
public final class NSColorSpace: NSObject, @unchecked Sendable {
    public static let sRGB = NSColorSpace()
    public static let deviceRGB = NSColorSpace()
    public static let genericRGB = NSColorSpace()
}

// MARK: Screens

public struct NSEdgeInsets: Equatable, Sendable {
    public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat
    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
}

public final class NSScreen: NSObject, @unchecked Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let backingScaleFactor: CGFloat
    public var safeAreaInsets = NSEdgeInsets()   // No notch on Windows.
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

// MARK: Events and views

public final class NSEvent: NSObject, @unchecked Sendable {
    public var locationInWindow = CGPoint.zero
    public var clickCount = 1
    public var pressure: Float = 0
    public var stage = 0
    public var modifierFlags = ModifierFlags()
    public var scrollingDeltaY: CGFloat = 0
    public var hasPreciseScrollingDeltas = false
    public var timestamp: TimeInterval = 0
    public struct ModifierFlags: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let shift = Self(rawValue: 1 << 17), control = Self(rawValue: 1 << 18), option = Self(rawValue: 1 << 19), command = Self(rawValue: 1 << 20)
    }
    /// Set by the host each tick.
    nonisolated(unsafe) public static var mouseLocation = CGPoint.zero
    nonisolated(unsafe) public static var pressedMouseButtons = 0
}

open class NSResponder: NSObject {
    public override init() { super.init() }
    open func mouseDown(with event: NSEvent) {}
    open func mouseDragged(with event: NSEvent) {}
    open func mouseUp(with event: NSEvent) {}
    open func rightMouseDown(with event: NSEvent) {}
    open func scrollWheel(with event: NSEvent) {}
    open func pressureChange(with event: NSEvent) {}
}

open class NSWindow: NSResponder {
    public var frame = CGRect.zero
    public var ignoresMouseEvents = false
    public func convertPoint(toScreen p: CGPoint) -> CGPoint { CGPoint(x: frame.minX + p.x, y: frame.minY + p.y) }
    public func convertPoint(fromScreen p: CGPoint) -> CGPoint { CGPoint(x: p.x - frame.minX, y: p.y - frame.minY) }
}

open class NSView: NSResponder {
    public var frame: CGRect
    public var bounds: CGRect { get { CGRect(origin: .zero, size: frame.size) } set { frame.size = newValue.size } }
    public var wantsLayer = false
    public var layer: CALayer? = nil
    public var needsDisplay = false
    public var isHidden = false
    public weak var window: NSWindow? = nil
    public init(frame frameRect: CGRect) { frame = frameRect; super.init() }
    public required init?(coder: NSCoder) { frame = .zero; super.init() }
    open func hitTest(_ point: CGPoint) -> NSView? { self }
    open func draw(_ dirtyRect: CGRect) {}
    open func setNeedsDisplay(_ r: CGRect) { needsDisplay = true }
    open func convert(_ p: CGPoint, from view: NSView?) -> CGPoint { p }
    open func convert(_ p: CGPoint, to view: NSView?) -> CGPoint { p }
    open var isFlipped: Bool { false }
}

public final class NSGraphicsContext: NSObject, @unchecked Sendable {
    public let cgContext: CGContext
    public init(cgContext c: CGContext, flipped: Bool) { cgContext = c }
    public convenience init?(cgContext c: CGContext, flipped: Bool, _ unused: Void = ()) { self.init(cgContext: c, flipped: flipped) }
    nonisolated(unsafe) public static var current: NSGraphicsContext? = nil
    nonisolated(unsafe) private static var stack: [NSGraphicsContext?] = []
    public static func saveGraphicsState() { stack.append(current); current?.cgContext.saveGState() }
    public static func restoreGraphicsState() {
        current?.cgContext.restoreGState()
        if let top = stack.popLast() { current = top }
    }
}

public final class NSImage: NSObject, @unchecked Sendable {
    public var size: CGSize
    public var isTemplate = false
    private let handler: ((CGRect) -> Bool)?
    public init(size: CGSize, flipped: Bool, drawingHandler: @escaping (CGRect) -> Bool) {
        self.size = size; handler = drawingHandler
    }
    public init(size: CGSize) { self.size = size; handler = nil }
    public func render(in c: CGContext) {
        let prior = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
        _ = handler?(CGRect(origin: .zero, size: size))
        NSGraphicsContext.current = prior
    }
    /// Draws straight into the current context. (AppKit caches a bitmap at the destination's resolution; drawing the
    /// vectors at that resolution comes to the same picture.)
    public func draw(in r: CGRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState()
        c.translateBy(x: r.minX, y: r.minY)
        if size.width > 0, size.height > 0 { c.scaleBy(x: r.width / size.width, y: r.height / size.height) }
        render(in: c)
        c.restoreGState()
    }
}

public final class NSBitmapImageRep: NSObject, @unchecked Sendable {
    public enum FileType { case png, jpeg, tiff, bmp, gif }
    public struct PropertyKey: Hashable { public let rawValue: String }
    public let cgImage: CGImage?
    public init(cgImage: CGImage) { self.cgImage = cgImage }
    public func representation(using t: FileType, properties: [PropertyKey: Any]) -> Data? {
        guard t == .png, let cgImage else { return nil }
        return PNGWriter.encode(cgImage)
    }
}

/// A plain PNG: unpremultiplies RGBA and stores the rows uncompressed (these files are tool output).
enum PNGWriter {
    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    private static func crc(_ b: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for x in b { c = crcTable[Int((c ^ UInt32(x)) & 255)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
    private static func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
    private static func chunk(_ t: String, _ d: [UInt8]) -> [UInt8] {
        let body = Array(t.utf8) + d
        return be(UInt32(d.count)) + body + be(crc(body))
    }
    static func encode(_ im: CGImage) -> Data {
        var raw = [UInt8](); raw.reserveCapacity((im.width * 4 + 1) * im.height)
        for y in 0..<im.height {
            raw.append(0)
            for x in 0..<im.width {
                let i = y * im.bytesPerRow + x * 4
                let a = im.pixels[i + 3]
                if a == 0 || a == 255 {
                    raw += [a == 0 ? 0 : im.pixels[i], a == 0 ? 0 : im.pixels[i + 1], a == 0 ? 0 : im.pixels[i + 2], a]
                } else {
                    func up(_ v: UInt8) -> UInt8 { UInt8(min(255, (Int(v) * 255 + Int(a) / 2) / Int(a))) }
                    raw += [up(im.pixels[i]), up(im.pixels[i + 1]), up(im.pixels[i + 2]), a]
                }
            }
        }
        var z: [UInt8] = [0x78, 0x01]
        var at = 0, s1: UInt32 = 1, s2: UInt32 = 0
        while at < raw.count {
            let n = min(65535, raw.count - at)
            z.append(at + n >= raw.count ? 1 : 0)
            z += [UInt8(n & 255), UInt8(n >> 8), UInt8(~n & 255), UInt8((~n >> 8) & 255)]
            z += raw[at..<(at + n)]
            at += n
        }
        for x in raw { s1 = (s1 + UInt32(x)) % 65521; s2 = (s2 + s1) % 65521 }
        z += be((s2 << 16) | s1)
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        out += chunk("IHDR", be(UInt32(im.width)) + be(UInt32(im.height)) + [8, 6, 0, 0, 0])
        out += chunk("IDAT", z)
        out += chunk("IEND", [])
        return Data(out)
    }
}

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
    public static let kern = NSAttributedString.Key("NSKern")
    public static let paragraphStyle = NSAttributedString.Key("NSParagraphStyle")
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
    let font = attrs[.font] as? CTFont
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
