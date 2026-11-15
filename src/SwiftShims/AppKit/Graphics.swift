// Colors, images, Bezier paths, shadows, gradients, cursors.
import Foundation
import QuartzCore
import WinSDK

// MARK: Colors
// System colours as AppKit gives them on the Mac the oracle runs (macOS 27), measured: tools/windows/swift/probe-colors.

public final class NSColor: NSObject, @unchecked Sendable {
    private let fixed: CGColor?
    private let dynamic: ((Bool) -> CGColor)?
    /// Resolved for the appearance being drawn in.
    public var cgColor: CGColor {
        if let fixed { return fixed }
        return dynamic!(NSAppearance.currentDrawing.isDark)
    }
    public init(cgColor c: CGColor) { fixed = c; dynamic = nil }
    public convenience init?(cgColor c: CGColor, _ unused: Void = ()) { self.init(cgColor: c) }
    private init(light: CGColor, dark: CGColor) { fixed = nil; dynamic = { $0 ? dark : light } }
    public convenience init(calibratedRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) { self.init(cgColor: CGColor(red: r, green: g, blue: b, alpha: a)) }
    public convenience init(srgbRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) { self.init(cgColor: CGColor(srgbRed: r, green: g, blue: b, alpha: a)) }
    public convenience init(red r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) { self.init(cgColor: CGColor(srgbRed: r, green: g, blue: b, alpha: a)) }
    public convenience init(deviceRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) { self.init(cgColor: CGColor(srgbRed: r, green: g, blue: b, alpha: a)) }
    public convenience init(white w: CGFloat, alpha a: CGFloat) { self.init(cgColor: CGColor(srgbRed: w, green: w, blue: w, alpha: a)) }
    public convenience init(calibratedWhite w: CGFloat, alpha a: CGFloat) { self.init(cgColor: CGColor(gray: w, alpha: a)) }
    public convenience init(deviceWhite w: CGFloat, alpha a: CGFloat) { self.init(cgColor: CGColor(srgbRed: w, green: w, blue: w, alpha: a)) }
    public convenience init(name: String?, dynamicProvider p: @escaping (NSAppearance) -> NSColor) {
        self.init(light: p(NSAppearance(named: .aqua)!).cgColor, dark: p(NSAppearance(named: .darkAqua)!).cgColor)
    }
    public convenience init(hue h: CGFloat, saturation s: CGFloat, brightness b: CGFloat, alpha a: CGFloat) {
        let i = Int(h * 6) % 6, f = h * 6 - CGFloat(Int(h * 6)), p = b * (1 - s), q = b * (1 - f * s), t = b * (1 - (1 - f) * s)
        let (r, g, bl): (CGFloat, CGFloat, CGFloat)
        switch i { case 0: (r, g, bl) = (b, t, p); case 1: (r, g, bl) = (q, b, p); case 2: (r, g, bl) = (p, b, t); case 3: (r, g, bl) = (p, q, b); case 4: (r, g, bl) = (t, p, b); default: (r, g, bl) = (b, p, q) }
        self.init(cgColor: CGColor(srgbRed: r, green: g, blue: bl, alpha: a))
    }
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }
    public static let black = NSColor(cgColor: rgb(0, 0, 0))
    public static let white = NSColor(cgColor: rgb(255, 255, 255))
    public static let clear = NSColor(cgColor: rgb(0, 0, 0, 0))
    public static let red = NSColor(cgColor: rgb(255, 0, 0)), green = NSColor(cgColor: rgb(0, 255, 0)), blue = NSColor(cgColor: rgb(0, 0, 255)), gray = NSColor(cgColor: rgb(128, 128, 128)), orange = NSColor(cgColor: rgb(255, 128, 0)), yellow = NSColor(cgColor: rgb(255, 255, 0))
    public static let darkGray = NSColor(cgColor: rgb(85, 85, 85)), lightGray = NSColor(cgColor: rgb(170, 170, 170))
    // macOS's semantic colors, in both appearances.
    public static let labelColor = NSColor(light: rgb(0, 0, 0, 0.847), dark: rgb(255, 255, 255, 0.847))
    public static let secondaryLabelColor = NSColor(light: rgb(0, 0, 0, 0.498), dark: rgb(255, 255, 255, 0.549))
    public static let tertiaryLabelColor = NSColor(light: rgb(0, 0, 0, 0.259), dark: rgb(255, 255, 255, 0.247))
    public static let quaternaryLabelColor = NSColor(light: rgb(0, 0, 0, 0.098), dark: rgb(255, 255, 255, 0.098))
    public static let textColor = NSColor(light: rgb(0, 0, 0), dark: rgb(255, 255, 255))
    public static let placeholderTextColor = NSColor(light: rgb(0, 0, 0, 0.498), dark: rgb(255, 255, 255, 0.549))
    public static let disabledControlTextColor = NSColor(light: rgb(0, 0, 0, 0.247), dark: rgb(255, 255, 255, 0.247))
    public static let controlTextColor = NSColor(light: rgb(0, 0, 0, 0.847), dark: rgb(255, 255, 255, 0.847))
    public static let controlAccentColor = NSColor(light: rgb(0, 122, 255), dark: rgb(0, 122, 255))
    public static let selectedContentBackgroundColor = NSColor(light: rgb(0, 100, 225), dark: rgb(0, 89, 209))
    public static let separatorColor = NSColor(light: rgb(0, 0, 0, 0.098), dark: rgb(255, 255, 255, 0.098))
    public static let gridColor = NSColor(light: rgb(230, 230, 230), dark: rgb(26, 26, 26))
    public static let windowBackgroundColor = NSColor(light: rgb(255, 255, 255), dark: rgb(30, 30, 30))
    public static let controlBackgroundColor = NSColor(light: rgb(255, 255, 255), dark: rgb(30, 30, 30))
    public static let textBackgroundColor = NSColor(light: rgb(255, 255, 255), dark: rgb(30, 30, 30))
    public static let underPageBackgroundColor = NSColor(light: rgb(246, 246, 246), dark: rgb(40, 40, 40))
    public static let controlColor = NSColor(light: rgb(255, 255, 255), dark: rgb(255, 255, 255, 0.247))
    public static let shadowColor = NSColor(cgColor: rgb(0, 0, 0))
    public static let linkColor = NSColor(light: rgb(0, 104, 218), dark: rgb(65, 156, 255))
    public static let systemRed = NSColor(light: rgb(255, 56, 60), dark: rgb(255, 66, 69))
    public static let systemOrange = NSColor(light: rgb(255, 141, 40), dark: rgb(255, 146, 48))
    public static let systemYellow = NSColor(light: rgb(255, 204, 0), dark: rgb(255, 214, 0))
    public static let systemGreen = NSColor(light: rgb(52, 199, 89), dark: rgb(48, 209, 88))
    public static let systemBlue = NSColor(light: rgb(0, 136, 255), dark: rgb(0, 145, 255))
    public static let systemGray = NSColor(light: rgb(142, 142, 147), dark: rgb(152, 152, 157))
    public static let systemPink = NSColor(light: rgb(255, 45, 85), dark: rgb(255, 55, 95))
    public static let systemPurple = NSColor(light: rgb(203, 48, 224), dark: rgb(219, 52, 242))
    public static let systemTeal = NSColor(light: rgb(0, 195, 208), dark: rgb(0, 210, 224))
    /// This colour as a control draws it in `view`. (Kept as a hook: measurements showed AppKit's label colours come
    /// out the same inside a visual effect view as outside it at text sizes; the difference was text rendering, which
    /// TextLayout.draw makes up for.)
    public func vibrant(in view: NSView?) -> NSColor { self }
    public var redComponent: CGFloat { cgColor.r }
    public var greenComponent: CGFloat { cgColor.g }
    public var blueComponent: CGFloat { cgColor.b }
    public var alphaComponent: CGFloat { cgColor.a }
    public var whiteComponent: CGFloat { cgColor.r }
    public func usingColorSpace(_ s: NSColorSpace) -> NSColor? {
        let c = cgColor
        return NSColor(cgColor: CGColor(srgbRed: c.sr, green: c.sg, blue: c.sb, alpha: c.a))
    }
    public func withAlphaComponent(_ a: CGFloat) -> NSColor { NSColor(cgColor: cgColor.copy(alpha: a) ?? cgColor) }
    public func blended(withFraction f: CGFloat, of o: NSColor) -> NSColor? {
        let a = cgColor, b = o.cgColor
        return NSColor(cgColor: CGColor(srgbRed: a.sr + (b.sr - a.sr) * f, green: a.sg + (b.sg - a.sg) * f, blue: a.sb + (b.sb - a.sb) * f, alpha: a.a + (b.a - a.a) * f))
    }
    public func highlight(withLevel l: CGFloat) -> NSColor? { blended(withFraction: l, of: .white) }
    public func shadow(withLevel l: CGFloat) -> NSColor? { blended(withFraction: l, of: .black) }
    public func set() { setFill(); setStroke() }
    public func setFill() { NSGraphicsContext.current?.cgContext.setFillColor(cgColor) }
    public func setStroke() { NSGraphicsContext.current?.cgContext.setStrokeColor(cgColor) }
}
public final class NSColorSpace: NSObject, @unchecked Sendable {
    public static let sRGB = NSColorSpace(), deviceRGB = NSColorSpace(), genericRGB = NSColorSpace(), displayP3 = NSColorSpace()
}

// MARK: Graphics context

public final class NSGraphicsContext: NSObject, @unchecked Sendable {
    public let cgContext: CGContext
    public let isFlipped: Bool
    public var imageInterpolation = NSImageInterpolation.default
    public var shouldAntialias = true { didSet { cgContext.setAllowsAntialiasing(shouldAntialias) } }
    public init(cgContext c: CGContext, flipped: Bool) { cgContext = c; isFlipped = flipped }
    /// Drawing into `rep`: what is drawn is in it once the context is done with (the next read of its image).
    public convenience init?(bitmapImageRep rep: NSBitmapImageRep) {
        guard let c = rep.contextForDrawing() else { return nil }
        self.init(cgContext: c, flipped: false)
    }
    nonisolated(unsafe) public static var current: NSGraphicsContext? = nil
    nonisolated(unsafe) private static var stack: [NSGraphicsContext?] = []
    public static func saveGraphicsState() { stack.append(current); current?.cgContext.saveGState() }
    public static func restoreGraphicsState() {
        current?.cgContext.restoreGState()
        if let top = stack.popLast() { current = top }
    }
    public func saveGraphicsState() { cgContext.saveGState() }
    public func restoreGraphicsState() { cgContext.restoreGState() }
    public func flushGraphics() {}
}
public enum NSImageInterpolation: UInt, Sendable { case `default`, none, low, medium, high }
public enum NSCompositingOperation: UInt, Sendable { case clear, copy, sourceOver, sourceIn, sourceOut, sourceAtop, destinationOver, destinationIn, destinationOut, destinationAtop, xor, plusLighter, multiply, screen, overlay, darken, lighten
    var blend: CGBlendMode {
        switch self {
        case .clear: return .clear; case .copy: return .copy; case .sourceIn: return .sourceIn; case .sourceOut: return .sourceOut; case .sourceAtop: return .sourceAtop
        case .destinationOver: return .destinationOver; case .destinationIn: return .destinationIn; case .destinationOut: return .destinationOut; case .destinationAtop: return .destinationAtop
        case .xor: return .xor; case .plusLighter: return .plusLighter; case .multiply: return .multiply; case .screen: return .screen; case .overlay: return .overlay; case .darken: return .darken; case .lighten: return .lighten
        default: return .normal
        }
    }
}
public enum NSImageScaling: UInt, Sendable { case scaleProportionallyDown, scaleAxesIndependently, scaleNone, scaleProportionallyUpOrDown }

// MARK: Images

public final class NSImage: NSObject, @unchecked Sendable {
    public struct SymbolConfiguration: Sendable {
        public var size: CGFloat = 13
        public var weight: NSFont.Weight = .regular
        public var scale: SymbolScale = .medium
        public init(pointSize: CGFloat, weight: NSFont.Weight) { size = pointSize; self.weight = weight }
        public init(pointSize: CGFloat, weight: NSFont.Weight, scale: SymbolScale) { size = pointSize; self.weight = weight; self.scale = scale }
        public init(scale: SymbolScale) { self.scale = scale; hasSize = false }
        public var paletteColors: [NSColor]?
        public var hierarchicalColor: NSColor?
        public init(paletteColors: [NSColor]) { self.paletteColors = paletteColors; hasSize = false; hasScale = false }
        public init(hierarchicalColor: NSColor) { self.hierarchicalColor = hierarchicalColor; hasSize = false; hasScale = false }
        /// This configuration with `other`'s settings over it.
        public func applying(_ other: SymbolConfiguration) -> SymbolConfiguration {
            var c = self
            if other.paletteColors != nil { c.paletteColors = other.paletteColors }
            if other.hierarchicalColor != nil { c.hierarchicalColor = other.hierarchicalColor }
            if other.hasSize { c.size = other.size; c.weight = other.weight }
            if other.hasScale { c.scale = other.scale }
            return c
        }
        var hasSize = true, hasScale = true
    }
    public enum SymbolScale: Int, Sendable { case small, medium, large }
    public struct Name: Hashable, Sendable { public let rawValue: String; public init(_ s: String) { rawValue = s } }
    public var size: CGSize
    public var isTemplate = false
    public var accessibilityDescription: String?
    public var alignmentRect = CGRect.zero
    public private(set) var bitmap: CGImage?
    let symbol: String?
    var symbolConfig: SymbolConfiguration?
    private let handler: ((CGRect) -> Bool)?
    public init(size: CGSize, flipped: Bool, drawingHandler: @escaping (CGRect) -> Bool) { self.size = size; handler = drawingHandler; symbol = nil }
    public init(size: CGSize) { self.size = size; handler = nil; symbol = nil }
    public convenience override init() { self.init(size: .zero) }
    public init(cgImage: CGImage, size: CGSize) {
        bitmap = cgImage
        self.size = size == .zero ? CGSize(width: cgImage.width, height: cgImage.height) : size
        handler = nil; symbol = nil
    }
    public init?(systemSymbolName n: String, accessibilityDescription d: String?) {
        if !Symbols.known(n) { Symbols.warnOnce(n) }
        size = Symbols.look(n, nil).size; handler = nil; symbol = n; accessibilityDescription = d
        isTemplate = true
    }
    private init(symbol n: String, config: SymbolConfiguration, description d: String?) {
        symbol = n; symbolConfig = config; handler = nil; size = Symbols.look(n, config).size; accessibilityDescription = d
        isTemplate = true
    }
    public func withSymbolConfiguration(_ c: SymbolConfiguration) -> NSImage? {
        guard let symbol else { return self }
        return NSImage(symbol: symbol, config: symbolConfig.map { $0.applying(c) } ?? c, description: accessibilityDescription)
    }
    public init?(contentsOf url: URL) {
        guard let im = ImageFile.load(url.path) else { return nil }
        bitmap = im; size = CGSize(width: im.width, height: im.height); handler = nil; symbol = nil
    }
    public convenience init?(contentsOfFile path: String) { self.init(contentsOf: URL(fileURLWithPath: path)) }
    public convenience init?(data: Data) {
        guard let im = ImageFile.decode(data) else { return nil }
        self.init(cgImage: im, size: .zero)
    }
    public convenience init?(named n: String) { return nil }
    public func addRepresentation(_ r: NSBitmapImageRep) { bitmap = r.cgImage }
    public var representations: [NSBitmapImageRep] { bitmap.map { [NSBitmapImageRep(cgImage: $0)] } ?? [] }
    public var isValid: Bool { true }
    public func cgImage(forProposedRect r: UnsafeMutablePointer<CGRect>?, context: NSGraphicsContext?, hints: [NSImageRep.HintKey: Any]?) -> CGImage? {
        if let bitmap { return bitmap }
        let k = NSScreen.primaryScale
        let w = max(Int((size.width * k).rounded(.up)), 1), h = max(Int((size.height * k).rounded(.up)), 1)
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.scaleBy(x: k, y: k)
        render(in: c, tint: nil)
        return c.makeImage()
    }
    public func tiffRepresentation() -> Data? { nil }
    public func lockFocus() {}
    public func unlockFocus() {}
    public func lockFocusFlipped(_ f: Bool) {}

    /// Draws into `c` at this image's own size, origin at (0, 0).
    public func render(in c: CGContext, tint: NSColor? = nil) {
        if let symbol {
            Symbols.draw(symbol, config: symbolConfig, in: CGRect(origin: .zero, size: size), ctx: c, color: tint?.cgColor ?? NSColor.labelColor.cgColor)
            return
        }
        if let bitmap { c.draw(bitmap, in: CGRect(origin: .zero, size: size)); return }
        let prior = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
        _ = handler?(CGRect(origin: .zero, size: size))
        NSGraphicsContext.current = prior
    }
    public func draw(in r: CGRect) { draw(in: r, from: .zero, operation: .sourceOver, fraction: 1) }
    public func draw(at p: CGPoint, from: CGRect, operation: NSCompositingOperation, fraction: CGFloat) {
        draw(in: CGRect(origin: p, size: size), from: from, operation: operation, fraction: fraction)
    }
    public func draw(in r: CGRect, from: CGRect, operation: NSCompositingOperation, fraction: CGFloat) { draw(in: r, from: from, operation: operation, fraction: fraction, respectFlipped: true, hints: nil) }
    public func draw(in r: CGRect, from: CGRect, operation: NSCompositingOperation, fraction: CGFloat, respectFlipped: Bool, hints: [NSImageRep.HintKey: Any]?) {
        guard let g = NSGraphicsContext.current else { return }
        let c = g.cgContext
        c.saveGState()
        c.setAlpha(fraction * c.state.alpha)
        c.setBlendMode(operation.blend)
        // (In a flipped view it would come out upside down without this.)
        if g.isFlipped {
            c.translateBy(x: r.minX, y: r.maxY)
            c.scaleBy(x: 1, y: -1)
        } else {
            c.translateBy(x: r.minX, y: r.minY)
        }
        if size.width > 0, size.height > 0 { c.scaleBy(x: r.width / size.width, y: r.height / size.height) }
        render(in: c)
        c.restoreGState()
    }
}

extension CGImage {
    /// (On the Mac this is CGImage's own; kept for readers of pixels.)
    public var dataBytes: [UInt8] { pixels }
}

open class NSImageRep: NSObject {
    public struct HintKey: Hashable, RawRepresentable, @unchecked Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let interpolation = Self(rawValue: "NSImageHintInterpolation")
        public static let ctm = Self(rawValue: "NSImageHintCTM")
    }
}

public final class NSBitmapImageRep: NSObject, @unchecked Sendable {
    public enum FileType { case png, jpeg, tiff, bmp, gif }
    public struct PropertyKey: Hashable { public let rawValue: String; public static let compressionFactor = PropertyKey(rawValue: "compression") }
    public private(set) var cgImage: CGImage?
    public var size: CGSize
    let scale: CGFloat
    private var ctx: CGContext?
    public init(cgImage: CGImage) { self.cgImage = cgImage; size = CGSize(width: cgImage.width, height: cgImage.height); scale = 1 }
    init(pointSize s: CGSize) { size = s; scale = NSScreen.primaryScale }
    public convenience init?(data: Data) {
        guard let im = ImageFile.decode(data) else { return nil }
        self.init(cgImage: im)
    }
    public var pixelsWide: Int { cgImage?.width ?? Int(size.width * scale) }
    public var pixelsHigh: Int { cgImage?.height ?? Int(size.height * scale) }
    func makeContext() -> CGContext? {
        ctx = CGContext(data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return ctx
    }
    func capture() { cgImage = ctx?.makeImage() }
    /// A context in points onto this rep's pixels, kept so later reads see what was drawn.
    func contextForDrawing() -> CGContext? {
        if ctx == nil {
            guard let c = makeContext() else { return nil }
            if let im = cgImage { c.draw(im, in: CGRect(x: 0, y: 0, width: im.width, height: im.height)) }
            c.scaleBy(x: scale, y: scale)
        }
        drawnInto = true
        return ctx
    }
    var drawnInto = false
    public func representation(using t: FileType, properties: [PropertyKey: Any]) -> Data? {
        if drawnInto { capture() }
        guard let cgImage else { return nil }
        return PNGWriter.encode(cgImage)
    }
}

/// A plain PNG: unpremultiplies RGBA and stores the rows uncompressed.
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

/// Reading image files goes through Skia's codecs when the app shell needs it (photo drops, bug report).
enum ImageFile {
    static func load(_ path: String) -> CGImage? { FileManager.default.contents(atPath: path).flatMap(decode) }
    static func decode(_ d: Data) -> CGImage? { SkiaDecode.decode(d) }
}

/// SF Symbols cannot ship on Windows. Each maps to a glyph in Segoe Fluent Icons; see Accepted differences.
/// SF Symbols can't ship on Windows, so Fluent System Icons stand in (MIT, see THIRD_PARTY_NOTICES.md).
/// Each is drawn into the box the Mac's SF Symbol takes, its ink where the SF Symbol's ink is,
/// thickened per weight to carry as much ink. All of that is measured on a Mac: tools/symbols.
enum Symbols {
    struct Look { let size: CGSize; let ink: CGRect }
    /// SF name to Fluent key.
    static let fluent: [String: String] = {
        var d: [String: String] = [:]
        for l in SymbolData.names.split(separator: "\n") {
            let t = l.split(separator: " ")
            if t.count == 2 { d[String(t[0])] = String(t[1]) }
        }
        return d
    }()
    /// Fluent key to its designs: box size to outline, in box units, y down.
    static let outlines: [String: [Int: CGPath]] = {
        var d: [String: [Int: CGPath]] = [:]
        for l in SymbolData.outlines.split(separator: "\n") {
            let t = l.split(separator: " ", maxSplits: 2)
            guard t.count == 3, let box = Int(t[1]) else { continue }
            d[String(t[0]), default: [:]][box] = path(t[2])
        }
        return d
    }()
    /// SF name to config key to its size and ink.
    static let looks: [String: [String: Look]] = {
        var d: [String: [String: Look]] = [:]
        for l in SymbolData.sizes.split(separator: "\n") {
            let t = l.split(separator: " ")
            guard t.count == 8 else { continue }
            let v = t[2...].map { CGFloat(Double($0) ?? 0) }
            d[String(t[0]), default: [:]][String(t[1])] = Look(size: CGSize(width: v[0], height: v[1]), ink: CGRect(x: v[2], y: v[3], width: v[4], height: v[5]))
        }
        return d
    }()
    /// SF name to weight letter to outset, in thousandths of the point size.
    static let outsets: [String: [String: CGFloat]] = {
        var d: [String: [String: CGFloat]] = [:]
        for l in SymbolData.weights.split(separator: "\n") {
            let t = l.split(separator: " ")
            guard t.count == 3 else { continue }
            d[String(t[0]), default: [:]][String(t[1])] = CGFloat(Double(t[2]) ?? 0)
        }
        return d
    }()
    static func known(_ name: String) -> Bool { fluent[name] != nil }
    nonisolated(unsafe) private static var warned = Set<String>()
    /// A name tools/symbols/fluent-map.txt doesn't have: drawn as a circle, said once.
    static func warnOnce(_ name: String) {
        if warned.insert(name).inserted { print("symbols: no Fluent icon for SF Symbol \"\(name)\" (add it to tools/symbols/fluent-map.txt)") }
    }

    /// "M x y L x y Q .. C .. Z", absolute.
    static func path(_ s: Substring) -> CGPath {
        let p = CGMutablePath()
        var nums: [CGFloat] = []
        var op: Character = " "
        func flush() {
            switch op {
            case "M" where nums.count >= 2: p.move(to: CGPoint(x: nums[0], y: nums[1]))
            case "L" where nums.count >= 2: p.addLine(to: CGPoint(x: nums[0], y: nums[1]))
            case "Q" where nums.count >= 4: p.addQuadCurve(to: CGPoint(x: nums[2], y: nums[3]), control: CGPoint(x: nums[0], y: nums[1]))
            case "C" where nums.count >= 6: p.addCurve(to: CGPoint(x: nums[4], y: nums[5]), control1: CGPoint(x: nums[0], y: nums[1]), control2: CGPoint(x: nums[2], y: nums[3]))
            case "Z": p.closeSubpath()
            default: break
            }
            nums.removeAll(keepingCapacity: true)
        }
        var token = ""
        func endToken() { if !token.isEmpty { nums.append(CGFloat(Double(token) ?? 0)); token = "" } }
        for ch in s {
            if ch == "M" || ch == "L" || ch == "Q" || ch == "C" || ch == "Z" { endToken(); flush(); op = ch }
            else if ch == " " { endToken() }
            else { token.append(ch) }
        }
        endToken(); flush()
        return p
    }

    static func weightKey(_ w: NSFont.Weight) -> String { w.rawValue < 0.12 ? "r" : w.rawValue < 0.27 ? "m" : "s" }
    static func number(_ v: CGFloat) -> String {
        v == v.rounded() ? String(Int(v)) : String(Double(v))
    }
    static let scaleFactor: [NSImage.SymbolScale: CGFloat] = [.small: 0.79, .medium: 1, .large: 1.29]

    /// The size and ink AppKit gives `name` under `config`: as measured, or the nearest measured one of the same weight, scaled.
    static func look(_ name: String, _ config: NSImage.SymbolConfiguration?) -> Look {
        let table = looks[name] ?? looks["circle"]!
        let k = scaleFactor[config?.scale ?? .medium] ?? 1
        func scaled(_ l: Look, _ f: CGFloat) -> Look {
            if f == 1 { return l }
            return Look(size: CGSize(width: (l.size.width * f).rounded(), height: (l.size.height * f).rounded()),
                        ink: CGRect(x: l.ink.minX * f, y: l.ink.minY * f, width: l.ink.width * f, height: l.ink.height * f))
        }
        guard let c = config, c.hasSize else { return scaled(table["d"]!, k) }
        let w = weightKey(c.weight)
        if let l = table[number(c.size) + w] { return scaled(l, k) }
        // The nearest measured size of this weight.
        var best: (CGFloat, Look)?
        for (key, l) in table where key.hasSuffix(w) {
            guard let p = Double(key.dropLast()) else { continue }
            let d = abs(CGFloat(p) - c.size)
            if best == nil || d < abs(best!.0 - c.size) { best = (CGFloat(p), l) }
        }
        guard let (p, l) = best else { return scaled(table["d"]!, k * c.size / 13) }
        return scaled(l, k * c.size / p)
    }

    static func draw(_ name: String, config: NSImage.SymbolConfiguration?, in r: CGRect, ctx: CGContext, color: CGColor) {
        let key = fluent[name] ?? fluent["circle"]!
        guard let designs = outlines[key], !designs.isEmpty else { return }
        let l = look(name, config)
        guard l.size.width > 0, l.size.height > 0 else { return }
        let sx = r.width / l.size.width, sy = r.height / l.size.height
        let ink = CGRect(x: r.minX + l.ink.minX * sx, y: r.minY + l.ink.minY * sy, width: l.ink.width * sx, height: l.ink.height * sy)
        let points = (config?.hasSize ?? false) ? config!.size : 13
        let w = config.map { weightKey($0.weight) } ?? "r"
        let t = (outsets[name]?[w] ?? 0) / 1000 * points * min(sx, sy)
        let inner = ink.insetBy(dx: t, dy: t)
        guard inner.width > 0, inner.height > 0 else { return }
        // The design drawn closest to one device pixel per unit: Fluent hints each size to its own pixels.
        let device = max(hypot(ctx.ctm.a, ctx.ctm.b), 0.01)
        var pick: (score: CGFloat, path: CGPath, s: CGFloat)?
        for (_, p) in designs {
            let bb = p.boundingBoxOfPath
            guard bb.width > 0, bb.height > 0 else { continue }
            let s = min(inner.width / bb.width, inner.height / bb.height)
            let score = abs(log(s * device))
            if pick == nil || score < pick!.score { pick = (score, p, s) }
        }
        guard let pick else { return }
        let bb = pick.path.boundingBoxOfPath
        // Box units are y down; this context is y up.
        var m = CGAffineTransform(translationX: inner.midX, y: inner.midY).scaledBy(x: pick.s, y: -pick.s).translatedBy(x: -bb.midX, y: -bb.midY)
        guard let placed = pick.path.copy(using: &m) else { return }
        // Palette and hierarchical symbols are one colour here: Fluent's outlines have no layers.
        let ink0 = config?.paletteColors?.first?.cgColor ?? config?.hierarchicalColor?.cgColor ?? color
        ctx.saveGState()
        ctx.setFillColor(ink0)
        ctx.addPath(placed)
        ctx.fillPath()
        if t > 0.01 {
            ctx.setStrokeColor(ink0)
            ctx.setLineWidth(2 * t)
            ctx.setLineJoin(.round)
            ctx.addPath(placed)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

// MARK: Bezier paths

public final class NSBezierPath: NSObject, @unchecked Sendable {
    public struct RectCorner: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue } }
    public let path = CGMutablePath()
    public var lineWidth: CGFloat = 1
    public var lineCapStyle: NSLineCapStyle = .butt
    public var lineJoinStyle: NSLineJoinStyle = .miter
    public var miterLimit: CGFloat = 10
    public var windingRule: NSWindingRule = .nonZero
    private var dash: [CGFloat] = []
    private var dashPhase: CGFloat = 0
    public override init() { super.init() }
    public convenience init(rect r: CGRect) { self.init(); path.addRect(r) }
    /// The same outline traced the other way: each subpath backwards, so with the non-zero rule it cuts a hole.
    public var reversed: NSBezierPath {
        let out = NSBezierPath()
        out.lineWidth = lineWidth; out.windingRule = windingRule
        var subpaths: [[PathElement]] = []
        for e in path.elements {
            if case .move = e { subpaths.append([e]) } else if subpaths.isEmpty { subpaths.append([.move(.zero), e]) } else { subpaths[subpaths.count - 1].append(e) }
        }
        for sp in subpaths {
            guard case .move(let start) = sp[0] else { continue }
            let closed = sp.last == .close
            // Each segment from its start point to its end point.
            var segs: [(from: CGPoint, el: PathElement)] = []
            var cur = start
            for e in sp.dropFirst() {
                switch e {
                case .line(let p): segs.append((cur, e)); cur = p
                case .quad(_, let p): segs.append((cur, e)); cur = p
                case .cubic(_, _, let p): segs.append((cur, e)); cur = p
                case .close: if cur != start { segs.append((cur, .line(start))); cur = start }
                case .move: break
                }
            }
            out.path.move(to: cur)
            for (from, e) in segs.reversed() {
                switch e {
                case .line: out.path.addLine(to: from)
                case .quad(let c, _): out.path.addQuadCurve(to: from, control: c)
                case .cubic(let c1, let c2, _): out.path.addCurve(to: from, control1: c2, control2: c1)
                default: break
                }
            }
            if closed { out.path.closeSubpath() }
        }
        return out
    }
    public convenience init(ovalIn r: CGRect) { self.init(); path.addEllipse(in: r) }
    public convenience init(roundedRect r: CGRect, xRadius x: CGFloat, yRadius y: CGFloat) { self.init(); path.addRoundedRect(in: r, cornerWidth: x, cornerHeight: y) }
    public var cgPath: CGPath { path }
    public var isEmpty: Bool { path.isEmpty }
    public var bounds: CGRect { path.boundingBoxOfPath }
    public var currentPoint: CGPoint { path.currentPoint }
    public func move(to p: CGPoint) { path.move(to: p) }
    public func line(to p: CGPoint) { path.addLine(to: p) }
    public func curve(to p: CGPoint, controlPoint1 a: CGPoint, controlPoint2 b: CGPoint) { path.addCurve(to: p, control1: a, control2: b) }
    public func close() { path.closeSubpath() }
    public func removeAllPoints() { path.removeAll() }
    public func appendRect(_ r: CGRect) { path.addRect(r) }
    public func appendOval(in r: CGRect) { path.addEllipse(in: r) }
    public func appendRoundedRect(_ r: CGRect, xRadius x: CGFloat, yRadius y: CGFloat) { path.addRoundedRect(in: r, cornerWidth: x, cornerHeight: y) }
    public func append(_ o: NSBezierPath) { path.addPath(o.path) }
    public func appendArc(withCenter c: CGPoint, radius r: CGFloat, startAngle a: CGFloat, endAngle b: CGFloat, clockwise: Bool = false) {
        path.addArc(center: c, radius: r, startAngle: a * .pi / 180, endAngle: b * .pi / 180, clockwise: clockwise)
    }
    public func setLineDash(_ p: UnsafePointer<CGFloat>?, count: Int, phase: CGFloat) {
        dash = (0..<count).map { p![$0] }; dashPhase = phase
    }
    public func contains(_ p: CGPoint) -> Bool { path.contains(p, using: windingRule == .evenOdd ? .evenOdd : .winding) }
    public func transform(using t: AffineTransform) {
        var m = CGAffineTransform(a: t.m11, b: t.m12, c: t.m21, d: t.m22, tx: t.tX, ty: t.tY)
        if let c = path.mutableCopy(using: &m) { path.removeAll(); path.addPath(c) }
    }
    public func fill() {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.addPath(path)
        c.fillPath(using: windingRule == .evenOdd ? .evenOdd : .winding)
    }
    public func stroke() {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState()
        c.setLineWidth(lineWidth)
        c.setLineCap(lineCapStyle == .round ? .round : lineCapStyle == .square ? .square : .butt)
        c.setLineJoin(lineJoinStyle == .round ? .round : lineJoinStyle == .bevel ? .bevel : .miter)
        c.setMiterLimit(miterLimit)
        if !dash.isEmpty { c.setLineDash(phase: dashPhase, lengths: dash) }
        c.addPath(path)
        c.strokePath()
        c.restoreGState()
    }
    public func addClip() {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.addPath(path)
        c.clip(using: windingRule == .evenOdd ? .evenOdd : .winding)
    }
    public func setClip() { addClip() }
    public static func fill(_ r: CGRect) { NSGraphicsContext.current?.cgContext.fill(r) }
    public static func clip(_ r: CGRect) { NSGraphicsContext.current?.cgContext.clip(to: r) }
    public static func strokeLine(from a: CGPoint, to b: CGPoint) {
        let p = NSBezierPath(); p.move(to: a); p.line(to: b); p.stroke()
    }
}
public enum NSLineCapStyle: UInt, Sendable { case butt, round, square }
public enum NSLineJoinStyle: UInt, Sendable { case miter, round, bevel }
public enum NSWindingRule: UInt, Sendable { case nonZero, evenOdd }

public final class NSShadow: NSObject, @unchecked Sendable {
    public var shadowOffset = CGSize.zero
    public var shadowBlurRadius: CGFloat = 0
    public var shadowColor: NSColor?
    public override init() { super.init() }
    public func set() {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let k = NSScreen.primaryScale
        c.setShadow(offset: CGSize(width: shadowOffset.width * k, height: shadowOffset.height * k), blur: shadowBlurRadius * k, color: (shadowColor ?? NSColor(white: 0, alpha: 0.33)).cgColor)
    }
}

public final class NSGradient: NSObject, @unchecked Sendable {
    let colors: [NSColor]
    let locations: [CGFloat]?
    public init?(starting a: NSColor, ending b: NSColor) { colors = [a, b]; locations = nil }
    public init?(colors c: [NSColor]) { colors = c; locations = nil }
    public init?(colors c: [NSColor], atLocations l: UnsafePointer<CGFloat>?, colorSpace: NSColorSpace) {
        colors = c
        locations = l.map { p in (0..<c.count).map { p[$0] } }
    }
    private func grad() -> CGGradient? {
        let cs = colors.map(\.cgColor) as CFArray
        if let locations { return locations.withUnsafeBufferPointer { CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cs, locations: $0.baseAddress) } }
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cs, locations: nil)
    }
    public func draw(in r: CGRect, angle: CGFloat) {
        guard let c = NSGraphicsContext.current?.cgContext, let g = grad() else { return }
        let a = angle * .pi / 180
        let dx = CGFloat(cos(Double(a))), dy = CGFloat(sin(Double(a)))
        let half = (abs(dx) * r.width + abs(dy) * r.height) / 2
        c.saveGState()
        c.clip(to: r)
        c.drawLinearGradient(g, start: CGPoint(x: r.midX - dx * half, y: r.midY - dy * half), end: CGPoint(x: r.midX + dx * half, y: r.midY + dy * half), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }
    public func draw(in p: NSBezierPath, angle: CGFloat) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState()
        c.addPath(p.path)
        c.clip()
        draw(in: p.bounds, angle: angle)
        c.restoreGState()
    }
    public func draw(in r: CGRect, relativeCenterPosition p: CGPoint) {
        guard let c = NSGraphicsContext.current?.cgContext, let g = grad() else { return }
        let center = CGPoint(x: r.midX + p.x * r.width / 2, y: r.midY + p.y * r.height / 2)
        c.saveGState()
        c.clip(to: r)
        c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: hypot(r.width, r.height) / 2, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }
}

public final class NSCursor: NSObject, @unchecked Sendable {
    let id: Int
    init(id: Int) { self.id = id }
    public init(image: NSImage, hotSpot: CGPoint) { id = 32512 }
    public static let arrow = NSCursor(id: 32512), iBeam = NSCursor(id: 32513), crosshair = NSCursor(id: 32515), pointingHand = NSCursor(id: 32649), openHand = NSCursor(id: 32649), closedHand = NSCursor(id: 32646), resizeLeftRight = NSCursor(id: 32644), resizeUpDown = NSCursor(id: 32645), operationNotAllowed = NSCursor(id: 32648)
    nonisolated(unsafe) static var currentCursor: NSCursor? = nil
    public static var current: NSCursor { currentCursor ?? arrow }
    public func set() { NSCursor.currentCursor = self; _ = NSCursor.applyCurrent() }
    public func push() { set() }
    public func pop() { NSCursor.pop() }
    public static func pop() { currentCursor = nil; _ = applyCurrent() }
    public static func hide() { _ = ShowCursor(false) }
    public static func unhide() { _ = ShowCursor(true) }
    public static func setHiddenUntilMouseMoves(_ b: Bool) {}
    @discardableResult static func applyCurrent() -> Bool {
        guard let c = currentCursor else { return false }
        _ = SetCursor(LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: c.id)))
        return true
    }
}

// NSRectFill and friends: a plain fill with the current colour, replacing what is there (AppKit fills with copy).
extension CGRect {
    public func fill() { fill(using: .copy) }
    public func fill(using op: NSCompositingOperation) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setBlendMode(op.blend)
        ctx.fill(self)
        ctx.restoreGState()
    }
    public func frame(withWidth w: CGFloat = 1, using op: NSCompositingOperation = .sourceOver) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setBlendMode(op.blend)
        ctx.fill(CGRect(x: minX, y: minY, width: width, height: w)); ctx.fill(CGRect(x: minX, y: maxY - w, width: width, height: w))
        ctx.fill(CGRect(x: minX, y: minY, width: w, height: height)); ctx.fill(CGRect(x: maxX - w, y: minY, width: w, height: height))
        ctx.restoreGState()
    }
}
