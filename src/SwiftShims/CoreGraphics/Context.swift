// CoreGraphics stand-in for Windows: the drawing context.
//
// The context keeps Core Graphics' state rules (state stack, current transform, path built in device
// space as it is added) and hands finished drawing to a CGBackend. The headless tools use the null
// backend, the app and image tools use the Skia one.
import Foundation

public enum CGImageAlphaInfo: UInt32, Sendable {
    case none, premultipliedLast, premultipliedFirst, last, first, noneSkipLast, noneSkipFirst, alphaOnly
}

public struct CGBitmapInfo: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let byteOrder32Little = CGBitmapInfo(rawValue: 2 << 12)
    public static let byteOrder32Big = CGBitmapInfo(rawValue: 4 << 12)
    public static let byteOrderDefault = CGBitmapInfo(rawValue: 0)
}

/// One graphics state. Everything that `saveGState` saves.
public struct CGState {
    public var ctm: CGAffineTransform = .identity
    public var fill = CGColor.black
    public var stroke = CGColor.black
    public var lineWidth: CGFloat = 1
    public var cap = CGLineCap.butt
    public var join = CGLineJoin.miter
    public var miter: CGFloat = 10
    public var dash: [CGFloat] = []
    public var dashPhase: CGFloat = 0
    public var alpha: CGFloat = 1
    public var blend = CGBlendMode.normal
    public var shadowOffset = CGSize.zero
    public var shadowBlur: CGFloat = 0
    public var shadowColor: CGColor? = nil
    public var antialias = true
    public var interpolation = CGInterpolationQuality.default
}

/// What actually puts pixels down. Paths reach it in device space, already transformed.
public protocol CGBackend: AnyObject {
    func save()
    func restore()
    func clip(_ path: CGPath, rule: CGPathFillRule, antialias: Bool)
    func fill(_ path: CGPath, rule: CGPathFillRule, state: CGState)
    func stroke(_ path: CGPath, state: CGState)
    func linearGradient(_ g: CGGradient, start: CGPoint, end: CGPoint, options: CGGradientDrawingOptions, state: CGState)
    func radialGradient(_ g: CGGradient, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat, options: CGGradientDrawingOptions, state: CGState)
    func drawImage(_ image: CGImage, in rect: CGRect, state: CGState)
    func beginLayer(state: CGState)
    func endLayer()
    func clear(_ rect: CGRect, state: CGState)
    func drawText(_ text: String, font: String, size: CGFloat, color: CGColor, at position: CGPoint, state: CGState)
    func flush()
}

/// A backend that draws nothing (headless behavior runs).
public final class CGNullBackend: CGBackend {
    public init() {}
    public func save() {}
    public func restore() {}
    public func clip(_ path: CGPath, rule: CGPathFillRule, antialias: Bool) {}
    public func fill(_ path: CGPath, rule: CGPathFillRule, state: CGState) {}
    public func stroke(_ path: CGPath, state: CGState) {}
    public func linearGradient(_ g: CGGradient, start: CGPoint, end: CGPoint, options: CGGradientDrawingOptions, state: CGState) {}
    public func radialGradient(_ g: CGGradient, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat, options: CGGradientDrawingOptions, state: CGState) {}
    public func drawImage(_ image: CGImage, in rect: CGRect, state: CGState) {}
    public func beginLayer(state: CGState) {}
    public func endLayer() {}
    public func clear(_ rect: CGRect, state: CGState) {}
    public func drawText(_ text: String, font: String, size: CGFloat, color: CGColor, at position: CGPoint, state: CGState) {}
    public func flush() {}
}

/// How bitmap contexts get a backend. Set once at startup by whichever module provides real drawing.
public enum CGBackendFactory {
    nonisolated(unsafe) public static var makeBitmapBackend: (_ data: UnsafeMutableRawPointer, _ width: Int, _ height: Int, _ bytesPerRow: Int, _ bitmapInfo: UInt32) -> CGBackend = { _, _, _, _, _ in CGNullBackend() }
}

public final class CGContext {
    public private(set) var state = CGState()
    private var stack: [CGState] = []
    private var path = CGMutablePath()
    public let backend: CGBackend

    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let bitsPerComponent: Int
    public let data: UnsafeMutableRawPointer?
    public let bitmapInfoRaw: UInt32
    private var ownsData = false

    public init(backend: CGBackend, width: Int = 0, height: Int = 0) {
        self.backend = backend; self.width = width; self.height = height
        bytesPerRow = width * 4; bitsPerComponent = 8; data = nil; bitmapInfoRaw = 0
    }

    /// `bitmapInfo` is the raw alpha-and-order value, as the Mac sources pass it.
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace, bitmapInfo: UInt32) {
        guard width > 0, height > 0 else { return nil }
        let row = bytesPerRow > 0 ? bytesPerRow : width * 4
        let bytes: UnsafeMutableRawPointer
        if let data {
            bytes = data
        } else {
            bytes = UnsafeMutableRawPointer.allocate(byteCount: row * height, alignment: 16)
            bytes.initializeMemory(as: UInt8.self, repeating: 0, count: row * height)
            ownsData = true
        }
        self.data = bytes
        self.width = width; self.height = height; self.bytesPerRow = row
        self.bitsPerComponent = bitsPerComponent; self.bitmapInfoRaw = bitmapInfo
        backend = CGBackendFactory.makeBitmapBackend(bytes, width, height, row, bitmapInfo)
    }
    deinit { if ownsData { data?.deallocate() } }

    public var ctm: CGAffineTransform { state.ctm }
    public var textPosition = CGPoint.zero
    public var textMatrix = CGAffineTransform.identity
    public var interpolationQuality: CGInterpolationQuality {
        get { state.interpolation } set { state.interpolation = newValue }
    }
    public var isPathEmpty: Bool { path.isEmpty }
    public var currentPointOfPath: CGPoint { path.currentPoint.applying(state.ctm.inverted()) }
    public var boundingBoxOfPath: CGRect { path.boundingBoxOfPath.applying(state.ctm.inverted()) }
    public var boundingBoxOfClipPath: CGRect { CGRect(x: 0, y: 0, width: width, height: height).applying(state.ctm.inverted()) }

    // MARK: State

    public func saveGState() { stack.append(state); backend.save() }
    public func restoreGState() {
        guard let s = stack.popLast() else { return }
        state = s
        backend.restore()
    }
    public func translateBy(x: CGFloat, y: CGFloat) { state.ctm = state.ctm.translatedBy(x: x, y: y) }
    public func scaleBy(x: CGFloat, y: CGFloat) { state.ctm = state.ctm.scaledBy(x: x, y: y) }
    public func rotate(by a: CGFloat) { state.ctm = state.ctm.rotated(by: a) }
    public func concatenate(_ t: CGAffineTransform) { state.ctm = t.concatenating(state.ctm) }

    public func setFillColor(_ c: CGColor) { state.fill = c }
    public func setStrokeColor(_ c: CGColor) { state.stroke = c }
    public func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { state.fill = CGColor(red: red, green: green, blue: blue, alpha: alpha) }
    public func setStrokeColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { state.stroke = CGColor(red: red, green: green, blue: blue, alpha: alpha) }
    public func setFillColor(gray: CGFloat, alpha: CGFloat) { state.fill = CGColor(gray: gray, alpha: alpha) }
    public func setStrokeColor(gray: CGFloat, alpha: CGFloat) { state.stroke = CGColor(gray: gray, alpha: alpha) }
    public func setLineWidth(_ w: CGFloat) { state.lineWidth = w }
    public func setLineCap(_ c: CGLineCap) { state.cap = c }
    public func setLineJoin(_ j: CGLineJoin) { state.join = j }
    public func setMiterLimit(_ m: CGFloat) { state.miter = m }
    public func setLineDash(phase: CGFloat, lengths: [CGFloat]) { state.dash = lengths; state.dashPhase = phase }
    public func setAlpha(_ a: CGFloat) { state.alpha = a }
    public func setBlendMode(_ m: CGBlendMode) { state.blend = m }
    public func setShadow(offset: CGSize, blur: CGFloat, color: CGColor?) {
        state.shadowOffset = offset; state.shadowBlur = blur; state.shadowColor = color
    }
    public func setShadow(offset: CGSize, blur: CGFloat) {
        setShadow(offset: offset, blur: blur, color: CGColor(gray: 0, alpha: 1.0 / 3.0))
    }
    public func setAllowsAntialiasing(_ on: Bool) { state.antialias = on }
    public func setShouldAntialias(_ on: Bool) { state.antialias = on }
    public func setShouldSmoothFonts(_ on: Bool) {}
    public func setAllowsFontSmoothing(_ on: Bool) {}
    public func setShouldSubpixelPositionFonts(_ on: Bool) {}

    // MARK: Current path. Points are transformed as they are added, which is Core Graphics' rule.

    public func beginPath() { path = CGMutablePath() }
    public func closePath() { path.rawClose() }
    public func move(to p: CGPoint) { path.rawMove(p.applying(state.ctm)) }
    public func addLine(to p: CGPoint) { path.rawLine(p.applying(state.ctm)) }
    public func addLines(between ps: [CGPoint]) { path.addLines(between: ps, transform: state.ctm) }
    public func addQuadCurve(to p: CGPoint, control c: CGPoint) { path.rawQuad(c.applying(state.ctm), p.applying(state.ctm)) }
    public func addCurve(to p: CGPoint, control1 a: CGPoint, control2 b: CGPoint) { path.rawCubic(a.applying(state.ctm), b.applying(state.ctm), p.applying(state.ctm)) }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise, transform: state.ctm)
    }
    public func addArc(tangent1End a: CGPoint, tangent2End b: CGPoint, radius: CGFloat) {
        path.addArc(tangent1End: a, tangent2End: b, radius: radius, transform: state.ctm)
    }
    public func addEllipse(in r: CGRect) { path.addEllipse(in: r, transform: state.ctm) }
    public func addRect(_ r: CGRect) { path.addRect(r, transform: state.ctm) }
    public func addRects(_ rs: [CGRect]) { path.addRects(rs, transform: state.ctm) }
    public func addPath(_ p: CGPath) { path.addPath(p, transform: state.ctm) }

    private func takePath() -> CGPath { let p = path; path = CGMutablePath(); return p }

    // MARK: Painting

    public func fillPath(using rule: CGPathFillRule = .winding) { backend.fill(takePath(), rule: rule, state: state) }
    public func strokePath() { backend.stroke(takePath(), state: state) }
    public func clip(using rule: CGPathFillRule = .winding) { backend.clip(takePath(), rule: rule, antialias: state.antialias) }
    public func clip(to r: CGRect) {
        let p = CGMutablePath(); p.addRect(r, transform: state.ctm)
        backend.clip(p, rule: .winding, antialias: state.antialias)
    }
    public func clip(to rs: [CGRect]) {
        let p = CGMutablePath(); p.addRects(rs, transform: state.ctm)
        backend.clip(p, rule: .winding, antialias: state.antialias)
    }
    public func drawPath(using mode: CGPathDrawingMode) {
        let p = takePath()
        switch mode {
        case .fill: backend.fill(p, rule: .winding, state: state)
        case .eoFill: backend.fill(p, rule: .evenOdd, state: state)
        case .stroke: backend.stroke(p, state: state)
        case .fillStroke: backend.fill(p, rule: .winding, state: state); backend.stroke(p, state: state)
        case .eoFillStroke: backend.fill(p, rule: .evenOdd, state: state); backend.stroke(p, state: state)
        }
    }
    public func fill(_ r: CGRect) {
        let p = CGMutablePath(); p.addRect(r, transform: state.ctm)
        backend.fill(p, rule: .winding, state: state)
    }
    public func fill(_ rs: [CGRect]) {
        let p = CGMutablePath(); p.addRects(rs, transform: state.ctm)
        backend.fill(p, rule: .winding, state: state)
    }
    public func stroke(_ r: CGRect) {
        let p = CGMutablePath(); p.addRect(r, transform: state.ctm)
        backend.stroke(p, state: state)
    }
    public func stroke(_ r: CGRect, width: CGFloat) { saveGState(); setLineWidth(width); stroke(r); restoreGState() }
    public func fillEllipse(in r: CGRect) {
        let p = CGMutablePath(); p.addEllipse(in: r, transform: state.ctm)
        backend.fill(p, rule: .winding, state: state)
    }
    public func strokeEllipse(in r: CGRect) {
        let p = CGMutablePath(); p.addEllipse(in: r, transform: state.ctm)
        backend.stroke(p, state: state)
    }
    public func strokeLineSegments(between ps: [CGPoint]) {
        let p = CGMutablePath()
        var i = 0
        while i + 1 < ps.count {
            p.move(to: ps[i], transform: state.ctm)
            p.addLine(to: ps[i + 1], transform: state.ctm)
            i += 2
        }
        backend.stroke(p, state: state)
    }
    public func clear(_ r: CGRect) { backend.clear(r.applying(state.ctm), state: state) }

    public func drawLinearGradient(_ g: CGGradient, start: CGPoint, end: CGPoint, options: CGGradientDrawingOptions) {
        backend.linearGradient(g, start: start, end: end, options: options, state: state)
    }
    public func drawRadialGradient(_ g: CGGradient, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat, options: CGGradientDrawingOptions) {
        backend.radialGradient(g, startCenter: startCenter, startRadius: startRadius, endCenter: endCenter, endRadius: endRadius, options: options, state: state)
    }
    public func draw(_ image: CGImage, in r: CGRect) { backend.drawImage(image, in: r, state: state) }
    public func beginTransparencyLayer(auxiliaryInfo: [String: Any]?) { stack.append(state); backend.beginLayer(state: state); state.alpha = 1; state.shadowColor = nil; state.blend = .normal }
    public func endTransparencyLayer() { backend.endLayer(); if let s = stack.popLast() { state = s } }
    public func flush() { backend.flush() }
    public func synchronize() { backend.flush() }

    public func makeImage() -> CGImage? {
        guard let data else { return nil }
        backend.flush()
        return CGImage(copying: data, width: width, height: height, bytesPerRow: bytesPerRow)
    }
}

/// A premultiplied RGBA bitmap, or a window onto one with a crop.
public final class CGImage: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let bitsPerPixel = 32
    public let bitsPerComponent = 8
    public let pixels: [UInt8]

    public init(copying data: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) {
        self.width = width; self.height = height; self.bytesPerRow = bytesPerRow
        pixels = Array(UnsafeRawBufferPointer(start: data, count: bytesPerRow * height))
    }
    public init(pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int) {
        self.pixels = pixels; self.width = width; self.height = height; self.bytesPerRow = bytesPerRow
    }
    public func cropping(to r: CGRect) -> CGImage? {
        let x = max(0, Int(r.minX)), y = max(0, Int(r.minY))
        let w = min(width - x, Int(r.width)), h = min(height - y, Int(r.height))
        guard w > 0, h > 0 else { return nil }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for row in 0..<h {
            let src = (y + row) * bytesPerRow + x * 4
            for i in 0..<(w * 4) { out[row * w * 4 + i] = pixels[src + i] }
        }
        return CGImage(pixels: out, width: w, height: h, bytesPerRow: w * 4)
    }
}

// The C-style names the sources use in a few places.
public func CGRectMake(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
public func CGPointMake(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
public func CGSizeMake(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
