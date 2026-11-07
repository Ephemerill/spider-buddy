// QuartzCore stand-in for Windows. The layer tree is real: layers keep Core Animation's geometry, draw through Core
// Graphics, and tell their root when something changed. AppKit's windows composite the tree. Animations are evaluated
// at draw time, as a presentation of the model values.
@_exported import CoreGraphics
import Foundation
#if os(Windows)
import WinSDK
#endif

public func CACurrentMediaTime() -> CFTimeInterval {
    #if os(Windows)
    var f = LARGE_INTEGER(), c = LARGE_INTEGER()
    QueryPerformanceFrequency(&f)
    QueryPerformanceCounter(&c)
    return Double(c.QuadPart) / Double(f.QuadPart)
    #else
    return ProcessInfo.processInfo.systemUptime
    #endif
}

public protocol CAAction {}
extension NSNull: CAAction {}

public struct CATransform3D: Equatable, Sendable {
    public var m11: CGFloat = 1, m12: CGFloat = 0, m13: CGFloat = 0, m14: CGFloat = 0
    public var m21: CGFloat = 0, m22: CGFloat = 1, m23: CGFloat = 0, m24: CGFloat = 0
    public var m31: CGFloat = 0, m32: CGFloat = 0, m33: CGFloat = 1, m34: CGFloat = 0
    public var m41: CGFloat = 0, m42: CGFloat = 0, m43: CGFloat = 0, m44: CGFloat = 1
    public init() {}
    /// The 2D part: everything this app's layers use.
    public var affine: CGAffineTransform { CGAffineTransform(a: m11, b: m12, c: m21, d: m22, tx: m41, ty: m42) }
    public init(_ t: CGAffineTransform) { m11 = t.a; m12 = t.b; m21 = t.c; m22 = t.d; m41 = t.tx; m42 = t.ty }
}
public let CATransform3DIdentity = CATransform3D()
public func CATransform3DMakeTranslation(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    var t = CATransform3D(); t.m41 = x; t.m42 = y; t.m43 = z; return t
}
public func CATransform3DMakeScale(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    var t = CATransform3D(); t.m11 = x; t.m22 = y; t.m33 = z; return t
}
public func CATransform3DMakeRotation(_ a: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    CATransform3D(CGAffineTransform(rotationAngle: z < 0 ? -a : a))
}
public func CATransform3DMakeAffineTransform(_ t: CGAffineTransform) -> CATransform3D { CATransform3D(t) }
public func CATransform3DGetAffineTransform(_ t: CATransform3D) -> CGAffineTransform { t.affine }
public func CATransform3DConcat(_ a: CATransform3D, _ b: CATransform3D) -> CATransform3D { CATransform3D(a.affine.concatenating(b.affine)) }
public func CATransform3DTranslate(_ t: CATransform3D, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D { CATransform3D(t.affine.translatedBy(x: x, y: y)) }
public func CATransform3DScale(_ t: CATransform3D, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D { CATransform3D(t.affine.scaledBy(x: x, y: y)) }
public func CATransform3DRotate(_ t: CATransform3D, _ a: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D { CATransform3D(t.affine.rotated(by: z < 0 ? -a : a)) }
public func CATransform3DIsIdentity(_ t: CATransform3D) -> Bool { t == CATransform3DIdentity }

public struct CALayerContentsGravity: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let center = Self(rawValue: "center"), resize = Self(rawValue: "resize"), resizeAspect = Self(rawValue: "resizeAspect"), resizeAspectFill = Self(rawValue: "resizeAspectFill"), bottomLeft = Self(rawValue: "bottomLeft"), bottom = Self(rawValue: "bottom"), top = Self(rawValue: "top"), left = Self(rawValue: "left"), right = Self(rawValue: "right")
}
public struct CAShapeLayerLineCap: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let butt = Self(rawValue: "butt"), round = Self(rawValue: "round"), square = Self(rawValue: "square")
}
public struct CAShapeLayerLineJoin: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let miter = Self(rawValue: "miter"), round = Self(rawValue: "round"), bevel = Self(rawValue: "bevel")
}
public struct CAShapeLayerFillRule: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let nonZero = Self(rawValue: "non-zero"), evenOdd = Self(rawValue: "even-odd")
}
public struct CAGradientLayerType: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let axial = Self(rawValue: "axial"), radial = Self(rawValue: "radial"), conic = Self(rawValue: "conic")
}
public struct CAMediaTimingFunctionName: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let linear = Self(rawValue: "linear"), easeIn = Self(rawValue: "easeIn"), easeOut = Self(rawValue: "easeOut"), easeInEaseOut = Self(rawValue: "easeInEaseOut"), `default` = Self(rawValue: "default")
}
public struct CAMediaTimingFillMode: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let removed = Self(rawValue: "removed"), forwards = Self(rawValue: "forwards"), backwards = Self(rawValue: "backwards"), both = Self(rawValue: "both")
}
public struct CAAnimationCalculationMode: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let linear = Self(rawValue: "linear"), discrete = Self(rawValue: "discrete"), paced = Self(rawValue: "paced"), cubic = Self(rawValue: "cubic")
}
public struct CATransitionType: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let fade = Self(rawValue: "fade"), push = Self(rawValue: "push"), moveIn = Self(rawValue: "moveIn"), reveal = Self(rawValue: "reveal")
}
public struct CATransitionSubtype: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let fromLeft = Self(rawValue: "fromLeft"), fromRight = Self(rawValue: "fromRight"), fromTop = Self(rawValue: "fromTop"), fromBottom = Self(rawValue: "fromBottom")
}
public struct CAFrameRateRange: Equatable, Sendable {
    public var minimum: Float, maximum: Float, preferred: Float?
    public init(minimum: Float, maximum: Float, preferred: Float? = nil) { self.minimum = minimum; self.maximum = maximum; self.preferred = preferred }
    public static let `default` = CAFrameRateRange(minimum: 0, maximum: 0, preferred: 0)
}

public final class CAMediaTimingFunction: NSObject, @unchecked Sendable {
    let c1: CGPoint, c2: CGPoint
    public init(name: CAMediaTimingFunctionName) {
        switch name {
        case .easeIn: c1 = CGPoint(x: 0.42, y: 0); c2 = CGPoint(x: 1, y: 1)
        case .easeOut: c1 = CGPoint(x: 0, y: 0); c2 = CGPoint(x: 0.58, y: 1)
        case .easeInEaseOut: c1 = CGPoint(x: 0.42, y: 0); c2 = CGPoint(x: 0.58, y: 1)
        case .default: c1 = CGPoint(x: 0.25, y: 0.1); c2 = CGPoint(x: 0.25, y: 1)
        default: c1 = .zero; c2 = CGPoint(x: 1, y: 1)
        }
    }
    public init(controlPoints a: Float, _ b: Float, _ c: Float, _ d: Float) {
        c1 = CGPoint(x: CGFloat(a), y: CGFloat(b)); c2 = CGPoint(x: CGFloat(c), y: CGFloat(d))
    }
    func value(at x: CGFloat) -> CGFloat {
        func bez(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t }
        var lo: CGFloat = 0, hi: CGFloat = 1
        for _ in 0..<24 {
            let m = (lo + hi) / 2
            if bez(m, c1.x, c2.x) < x { lo = m } else { hi = m }
        }
        return bez((lo + hi) / 2, c1.y, c2.y)
    }
}

// MARK: Dirty tracking

/// The root of a tree says it needs compositing. Set by whichever window owns the root.
public protocol CALayerHost: AnyObject { func layerTreeChanged() }

// MARK: CALayer

open class CALayer: NSObject {
    public override init() { super.init() }
    public init(layer: Any) { super.init() }

    /// The window (or view) that composites this tree, found from the root.
    public weak var host: CALayerHost?
    func touch() {
        var l: CALayer? = self
        while let c = l {
            if let h = c.host { h.layerTreeChanged(); return }
            l = c.superlayer
        }
    }

    open var bounds = CGRect.zero { didSet { touch() } }
    open var position = CGPoint.zero { didSet { touch() } }
    open var anchorPoint = CGPoint(x: 0.5, y: 0.5) { didSet { touch() } }
    open var zPosition: CGFloat = 0 { didSet { touch() } }
    open var transform = CATransform3DIdentity { didSet { touch() } }
    open var sublayerTransform = CATransform3DIdentity { didSet { touch() } }
    open var opacity: Float = 1 { didSet { touch() } }
    open var isHidden = false { didSet { touch() } }
    open var masksToBounds = false { didSet { touch() } }
    open var isOpaque = false
    open var isGeometryFlipped = false { didSet { touch() } }
    open var contents: Any? = nil { didSet { touch() } }
    open var contentsScale: CGFloat = 1 { didSet { touch() } }
    open var contentsGravity = CALayerContentsGravity.resize { didSet { touch() } }
    open var contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1) { didSet { touch() } }
    open var magnificationFilter = "linear"
    open var minificationFilter = "linear"
    open var backgroundColor: CGColor? = nil { didSet { touch() } }
    open var cornerRadius: CGFloat = 0 { didSet { touch() } }
    open var borderWidth: CGFloat = 0 { didSet { touch() } }
    open var borderColor: CGColor? = nil { didSet { touch() } }
    open var shadowColor: CGColor? = nil { didSet { touch() } }
    open var shadowOpacity: Float = 0 { didSet { touch() } }
    open var shadowRadius: CGFloat = 3 { didSet { touch() } }
    open var shadowOffset = CGSize(width: 0, height: -3) { didSet { touch() } }
    open var shadowPath: CGPath? = nil { didSet { touch() } }
    open var mask: CALayer? = nil { didSet { touch() } }
    open var name: String? = nil
    open var actions: [String: CAAction]? = nil
    open var drawsAsynchronously = false
    open var shouldRasterize = false
    open var rasterizationScale: CGFloat = 1
    open var allowsEdgeAntialiasing = false
    open var compositingFilter: Any? = nil { didSet { touch() } }
    /// Set by AppKit for a view's backing layer: draws the view's own content.
    public var drawContent: ((CGContext) -> Void)?

    open private(set) var sublayers: [CALayer]? = nil
    open private(set) weak var superlayer: CALayer? = nil

    open var frame: CGRect {
        get {
            let t = transform.affine
            let base = CGRect(x: -bounds.width * anchorPoint.x, y: -bounds.height * anchorPoint.y, width: bounds.width, height: bounds.height)
            let r = t.isIdentity ? base : base.applying(t)
            return r.offsetBy(dx: position.x, dy: position.y)
        }
        set {
            bounds.size = newValue.size
            position = CGPoint(x: newValue.minX + newValue.width * anchorPoint.x, y: newValue.minY + newValue.height * anchorPoint.y)
        }
    }

    open func addSublayer(_ l: CALayer) {
        l.removeFromSuperlayer()
        if sublayers == nil { sublayers = [] }
        sublayers!.append(l)
        l.superlayer = self
        touch()
    }
    open func insertSublayer(_ l: CALayer, at i: UInt32) {
        l.removeFromSuperlayer()
        if sublayers == nil { sublayers = [] }
        sublayers!.insert(l, at: min(Int(i), sublayers!.count))
        l.superlayer = self
        touch()
    }
    open func insertSublayer(_ l: CALayer, above other: CALayer?) {
        l.removeFromSuperlayer()
        if sublayers == nil { sublayers = [] }
        if let other, let i = sublayers!.firstIndex(where: { $0 === other }) { sublayers!.insert(l, at: i + 1) } else { sublayers!.append(l) }
        l.superlayer = self
        touch()
    }
    open func insertSublayer(_ l: CALayer, below other: CALayer?) {
        l.removeFromSuperlayer()
        if sublayers == nil { sublayers = [] }
        if let other, let i = sublayers!.firstIndex(where: { $0 === other }) { sublayers!.insert(l, at: i) } else { sublayers!.insert(l, at: 0) }
        l.superlayer = self
        touch()
    }
    open func replaceSublayer(_ old: CALayer, with new: CALayer) {
        guard let i = sublayers?.firstIndex(where: { $0 === old }) else { return }
        old.removeFromSuperlayer()
        insertSublayer(new, at: UInt32(i))
    }
    open func removeFromSuperlayer() {
        guard let s = superlayer else { return }
        s.sublayers?.removeAll { $0 === self }
        superlayer = nil
        s.touch()
    }
    open func setNeedsDisplay() { touch() }
    open func setNeedsDisplay(_ r: CGRect) { touch() }
    open func display() { touch() }
    open func displayIfNeeded() {}
    open func setNeedsLayout() {}
    open func layoutIfNeeded() {}
    open func layoutSublayers() {}
    open func draw(in ctx: CGContext) {}
    open func action(forKey key: String) -> CAAction? { actions?[key] }
    open func setAffineTransform(_ t: CGAffineTransform) { transform = CATransform3D(t) }
    open func affineTransform() -> CGAffineTransform { transform.affine }
    open func convert(_ p: CGPoint, from l: CALayer?) -> CGPoint { p }
    open func convert(_ p: CGPoint, to l: CALayer?) -> CGPoint { p }
    open func hitTest(_ p: CGPoint) -> CALayer? { bounds.contains(p) ? self : nil }
    open func contains(_ p: CGPoint) -> Bool { bounds.contains(p) }

    // MARK: Animations

    private var animations: [(key: String, anim: CAAnimation, began: CFTimeInterval)] = []
    private var animSerial = 0
    open func add(_ anim: CAAnimation, forKey key: String?) {
        animSerial += 1
        let k = key ?? "anim\(animSerial)"
        animations.removeAll { $0.key == k }
        let now = CACurrentMediaTime()
        animations.append((k, anim, anim.beginTime > 0 ? anim.beginTime : now))
        touch()
    }
    open func removeAllAnimations() { animations.removeAll(); touch() }
    open func removeAnimation(forKey key: String) { animations.removeAll { $0.key == key }; touch() }
    open func animation(forKey key: String) -> CAAnimation? { animations.first { $0.key == key }?.anim }
    open func animationKeys() -> [String]? { animations.isEmpty ? nil : animations.map(\.key) }
    open func presentation() -> Self? { self }
    open func model() -> Self { self }

    public var isAnimating: Bool {
        if !animations.isEmpty { return true }
        return sublayers?.contains { $0.isAnimating } ?? false
    }

    /// What animations do to one numeric property right now.
    func animated(_ name: String, _ value: CGFloat, now: CFTimeInterval) -> CGFloat {
        var v = value
        for a in animations { if let x = a.anim.scalar(for: name, at: now - a.began, base: v) { v = x } }
        return v
    }
    func animatedPoint(_ name: String, _ value: CGPoint, now: CFTimeInterval) -> CGPoint {
        var v = value
        for a in animations { if let x = a.anim.point(for: name, at: now - a.began, base: v) { v = x } }
        return v
    }
    func animatedColor(_ name: String, _ value: CGColor?, now: CFTimeInterval) -> CGColor? {
        var v = value
        for a in animations { if let x = a.anim.color(for: name, at: now - a.began) { v = x } }
        return v
    }
    func animatedTransform(_ value: CGAffineTransform, now: CFTimeInterval) -> CGAffineTransform {
        var v = value
        for a in animations { v = a.anim.applyTransform(v, at: now - a.began) }
        return v
    }
    /// Finished animations leave; each one's completion, if it has one, runs.
    func expireAnimations(now: CFTimeInterval) {
        guard !animations.isEmpty else { return }
        var done: [CAAnimation] = []
        animations.removeAll { a in
            if a.anim.isFinished(at: now - a.began) {
                done.append(a.anim)
                return a.anim.isRemovedOnCompletion
            }
            return false
        }
        for d in done { d.delegateFinished() }
    }

    // MARK: Drawing

    /// Draws this layer and what is under it. `ctx`'s transform maps the superlayer's space.
    open func render(in ctx: CGContext, now: CFTimeInterval) {
        expireAnimations(now: now)
        guard !isHidden else { return }
        let alpha = animated("opacity", CGFloat(opacity), now: now)
        guard alpha > 0.001 else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let moved = animatedPoint("position", position, now: now)
        let pos = CGPoint(x: animated("position.x", moved.x, now: now), y: animated("position.y", moved.y, now: now))
        ctx.translateBy(x: pos.x, y: pos.y)
        let t = animatedTransform(transform.affine, now: now)
        if !t.isIdentity { ctx.concatenate(t) }
        ctx.translateBy(x: -bounds.width * anchorPoint.x - bounds.minX, y: -bounds.height * anchorPoint.y - bounds.minY)
        if isGeometryFlipped {
            ctx.translateBy(x: 0, y: bounds.height + 2 * bounds.minY)
            ctx.scaleBy(x: 1, y: -1)
        }
        let grouped = alpha < 0.999
        if grouped {
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        drawSelf(in: ctx, now: now)
        if grouped { ctx.endTransparencyLayer() }
    }

    func outline() -> CGPath { CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil) }

    open func drawSelf(in ctx: CGContext, now: CFTimeInterval) {
        let sh = shadowColor != nil && shadowOpacity > 0
        if sh, shadowPath != nil || backgroundColor != nil {
            ctx.saveGState()
            setShadow(ctx)
            ctx.addPath(shadowPath ?? outline())
            ctx.setFillColor(backgroundColor ?? CGColor(gray: 0, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
        }
        let clipped = masksToBounds
        if clipped {
            ctx.saveGState()
            ctx.addPath(outline())
            ctx.clip()
        }
        if let bg = animatedColor("backgroundColor", backgroundColor, now: now), bg.a > 0, !(sh && shadowPath == nil) {
            ctx.setFillColor(bg)
            ctx.addPath(outline())
            ctx.fillPath()
        }
        if let img = contents as? CGImage { drawContents(img, in: ctx) }
        drawBody(in: ctx, now: now)
        draw(in: ctx)
        drawContent?(ctx)
        if let subs = sublayers {
            if !sublayerTransform.affine.isIdentity { ctx.saveGState(); ctx.concatenate(sublayerTransform.affine) }
            let ordered = subs.contains { $0.zPosition != 0 } ? subs.enumerated().sorted { ($0.element.zPosition, $0.offset) < ($1.element.zPosition, $1.offset) }.map(\.element) : subs
            for s in ordered { s.render(in: ctx, now: now) }
            if !sublayerTransform.affine.isIdentity { ctx.restoreGState() }
        }
        if clipped { ctx.restoreGState() }
        if borderWidth > 0, let bc = borderColor {
            ctx.setStrokeColor(bc)
            ctx.setLineWidth(borderWidth)
            let inset = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            ctx.addPath(CGPath(roundedRect: inset, cornerWidth: max(0, cornerRadius - borderWidth / 2), cornerHeight: max(0, cornerRadius - borderWidth / 2), transform: nil))
            ctx.strokePath()
        }
    }

    func setShadow(_ ctx: CGContext) {
        guard let c = shadowColor else { return }
        let col = c.copy(alpha: c.a * CGFloat(shadowOpacity)) ?? c
        // Core Animation's radius is Core Graphics' blur. Shadow offsets are in device space.
        let k = abs(ctx.ctm.a) + abs(ctx.ctm.b)
        ctx.setShadow(offset: CGSize(width: shadowOffset.width * k, height: shadowOffset.height * k), blur: shadowRadius * k, color: col)
    }

    /// Subclasses' content: a shape, a gradient.
    open func drawBody(in ctx: CGContext, now: CFTimeInterval) {}

    private func drawContents(_ img: CGImage, in ctx: CGContext) {
        let scale = max(contentsScale, 0.01)
        let iw = CGFloat(img.width) / scale, ih = CGFloat(img.height) / scale
        var r = bounds
        switch contentsGravity {
        case .center: r = CGRect(x: bounds.midX - iw / 2, y: bounds.midY - ih / 2, width: iw, height: ih)
        case .bottomLeft: r = CGRect(x: bounds.minX, y: bounds.minY, width: iw, height: ih)
        case .bottom: r = CGRect(x: bounds.midX - iw / 2, y: bounds.minY, width: iw, height: ih)
        case .top: r = CGRect(x: bounds.midX - iw / 2, y: bounds.maxY - ih, width: iw, height: ih)
        case .left: r = CGRect(x: bounds.minX, y: bounds.midY - ih / 2, width: iw, height: ih)
        case .right: r = CGRect(x: bounds.maxX - iw, y: bounds.midY - ih / 2, width: iw, height: ih)
        case .resizeAspect, .resizeAspectFill:
            let f = contentsGravity == .resizeAspect ? min(bounds.width / max(iw, 1), bounds.height / max(ih, 1)) : max(bounds.width / max(iw, 1), bounds.height / max(ih, 1))
            r = CGRect(x: bounds.midX - iw * f / 2, y: bounds.midY - ih * f / 2, width: iw * f, height: ih * f)
        default: break
        }
        ctx.draw(img, in: r)
    }

    /// Key-value access is only used to reach emitter cells.
    open func setValue(_ v: Any?, forKeyPath key: String) {}
}

// MARK: Shape

open class CAShapeLayer: CALayer {
    open var path: CGPath? = nil { didSet { touch() } }
    open var fillColor: CGColor? = CGColor(gray: 0, alpha: 1) { didSet { touch() } }
    open var strokeColor: CGColor? = nil { didSet { touch() } }
    open var lineWidth: CGFloat = 1 { didSet { touch() } }
    open var lineCap = CAShapeLayerLineCap.butt { didSet { touch() } }
    open var lineJoin = CAShapeLayerLineJoin.miter { didSet { touch() } }
    open var fillRule = CAShapeLayerFillRule.nonZero { didSet { touch() } }
    open var lineDashPattern: [NSNumber]? = nil { didSet { touch() } }
    open var lineDashPhase: CGFloat = 0 { didSet { touch() } }
    open var strokeStart: CGFloat = 0 { didSet { touch() } }
    open var strokeEnd: CGFloat = 1 { didSet { touch() } }
    open var miterLimit: CGFloat = 10 { didSet { touch() } }

    open override func drawBody(in ctx: CGContext, now: CFTimeInterval) {
        guard let path, !path.isEmpty else { return }
        ctx.saveGState()
        if shadowColor != nil, shadowOpacity > 0 { setShadow(ctx) }
        if let f = animatedColor("fillColor", fillColor, now: now), f.a > 0 {
            ctx.setFillColor(f)
            ctx.addPath(path)
            ctx.fillPath(using: fillRule == .evenOdd ? .evenOdd : .winding)
        }
        let end = animated("strokeEnd", strokeEnd, now: now)
        if let s = animatedColor("strokeColor", strokeColor, now: now), s.a > 0, lineWidth > 0, end > strokeStart {
            ctx.setStrokeColor(s)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(lineCap == .round ? .round : lineCap == .square ? .square : .butt)
            ctx.setLineJoin(lineJoin == .round ? .round : lineJoin == .bevel ? .bevel : .miter)
            ctx.setMiterLimit(miterLimit)
            if let d = lineDashPattern, !d.isEmpty { ctx.setLineDash(phase: lineDashPhase, lengths: d.map { CGFloat($0.doubleValue) }) }
            if strokeStart > 0 || end < 1 {
                ctx.addPath(path.trimmed(from: strokeStart, to: end))
            } else {
                ctx.addPath(path)
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

extension CGPath {
    /// The stretch of the path between two fractions of its length, for stroke-drawing animations.
    func trimmed(from a: CGFloat, to b: CGFloat) -> CGPath {
        let out = CGMutablePath()
        var total: CGFloat = 0
        let subs = flattened()
        for s in subs where s.points.count > 1 { for i in 1..<s.points.count { total += hypot(s.points[i].x - s.points[i - 1].x, s.points[i].y - s.points[i - 1].y) } }
        let from = a * total, to = b * total
        var run: CGFloat = 0
        for s in subs where s.points.count > 1 {
            var started = false
            for i in 1..<s.points.count {
                let p = s.points[i - 1], q = s.points[i]
                let l = hypot(q.x - p.x, q.y - p.y)
                if l > 0, run + l >= from, run <= to {
                    let u0 = max(0, (from - run) / l), u1 = min(1, (to - run) / l)
                    let s0 = CGPoint(x: p.x + (q.x - p.x) * u0, y: p.y + (q.y - p.y) * u0)
                    let s1 = CGPoint(x: p.x + (q.x - p.x) * u1, y: p.y + (q.y - p.y) * u1)
                    if !started { out.move(to: s0); started = true }
                    out.addLine(to: s1)
                }
                run += l
            }
        }
        return out
    }
}

// MARK: Gradient

open class CAGradientLayer: CALayer {
    open var colors: [Any]? = nil { didSet { touch() } }
    open var locations: [NSNumber]? = nil { didSet { touch() } }
    open var startPoint = CGPoint(x: 0.5, y: 0) { didSet { touch() } }
    open var endPoint = CGPoint(x: 0.5, y: 1) { didSet { touch() } }
    open var type = CAGradientLayerType.axial { didSet { touch() } }

    open override func drawBody(in ctx: CGContext, now: CFTimeInterval) {
        guard let cols = colors?.compactMap({ $0 as? CGColor }), !cols.isEmpty else { return }
        var locs = locations?.map { CGFloat($0.doubleValue) }
        if locs?.count != cols.count { locs = nil }
        let g = locs.flatMap { l in l.withUnsafeBufferPointer { CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols as CFArray, locations: $0.baseAddress) } }
            ?? CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols as CFArray, locations: nil)
        guard let g else { return }
        func P(_ u: CGPoint) -> CGPoint { CGPoint(x: bounds.minX + u.x * bounds.width, y: bounds.minY + u.y * bounds.height) }
        ctx.saveGState()
        ctx.addPath(outline())
        ctx.clip()
        if type == .radial {
            let r = hypot((endPoint.x - startPoint.x) * bounds.width, (endPoint.y - startPoint.y) * bounds.height)
            ctx.drawRadialGradient(g, startCenter: P(startPoint), startRadius: 0, endCenter: P(startPoint), endRadius: r, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        } else {
            ctx.drawLinearGradient(g, start: P(startPoint), end: P(endPoint), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }
}

// MARK: Text. Drawing is supplied by AppKit, where the fonts are.

open class CATextLayer: CALayer {
    public struct AlignmentMode: Equatable, Sendable { public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let left = Self(rawValue: "left"), center = Self(rawValue: "center"), right = Self(rawValue: "right"), natural = Self(rawValue: "natural"), justified = Self(rawValue: "justified")
    }
    public struct TruncationMode: Equatable, Sendable { public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let none = Self(rawValue: "none"), start = Self(rawValue: "start"), end = Self(rawValue: "end"), middle = Self(rawValue: "middle")
    }
    open var string: Any? = nil { didSet { touch() } }
    open var font: Any? = nil { didSet { touch() } }
    open var fontSize: CGFloat = 36 { didSet { touch() } }
    open var foregroundColor: CGColor? = CGColor(gray: 1, alpha: 1) { didSet { touch() } }
    open var alignmentMode = AlignmentMode.natural { didSet { touch() } }
    open var truncationMode = TruncationMode.none
    open var isWrapped = false
    nonisolated(unsafe) public static var drawText: ((CATextLayer, CGContext) -> Void)?
    open override func drawBody(in ctx: CGContext, now: CFTimeInterval) { CATextLayer.drawText?(self, ctx) }
}

// MARK: Animations

open class CAAnimation: NSObject {
    public override init() { super.init() }
    open var duration: CFTimeInterval = 0
    open var beginTime: CFTimeInterval = 0
    open var timeOffset: CFTimeInterval = 0
    open var repeatCount: Float = 0
    open var repeatDuration: CFTimeInterval = 0
    open var autoreverses = false
    open var speed: Float = 1
    open var isRemovedOnCompletion = true
    open var fillMode = CAMediaTimingFillMode.removed
    open var timingFunction: CAMediaTimingFunction? = nil
    public var onFinish: (() -> Void)?

    var effectiveDuration: CFTimeInterval { duration > 0 ? duration : 0.25 }
    var totalTime: CFTimeInterval {
        if repeatCount.isInfinite || repeatDuration.isInfinite { return .infinity }
        if repeatDuration > 0 { return repeatDuration }
        var d = effectiveDuration * Double(max(repeatCount, 1))
        if autoreverses { d *= 2 }
        return d
    }
    func isFinished(at t: CFTimeInterval) -> Bool { t >= totalTime }
    func delegateFinished() { onFinish?(); onFinish = nil }
    /// Progress 0...1 through one run, or nil when not active.
    func progress(at t: CFTimeInterval) -> CGFloat? {
        if t < 0 {
            return fillMode == .backwards || fillMode == .both ? 0 : nil
        }
        let total = totalTime
        var local = t
        if t >= total {
            guard !isRemovedOnCompletion, fillMode == .forwards || fillMode == .both else { return nil }
            local = total - 1e-6
        }
        let d = effectiveDuration
        var u = local / d
        if autoreverses {
            let c = u.truncatingRemainder(dividingBy: 2)
            u = c > 1 ? 2 - c : c
        } else {
            u = u.truncatingRemainder(dividingBy: 1)
            if local >= total - 1e-5 { u = 1 }
        }
        return timingFunction?.value(at: CGFloat(u)) ?? CGFloat(u)
    }
    func scalar(for name: String, at t: CFTimeInterval, base: CGFloat) -> CGFloat? { nil }
    func point(for name: String, at t: CFTimeInterval, base: CGPoint) -> CGPoint? { nil }
    func color(for name: String, at t: CFTimeInterval) -> CGColor? { nil }
    func applyTransform(_ v: CGAffineTransform, at t: CFTimeInterval) -> CGAffineTransform { v }
}

/// NSValue(point:) is a Foundation class here; animations read it through this.
public protocol CGPointBox { var point: CGPoint { get } }

open class CAPropertyAnimation: CAAnimation {
    open var keyPath: String?
    open var isAdditive = false
    open var isCumulative = false
    public init(keyPath: String?) { self.keyPath = keyPath; super.init() }
    public override init() { super.init() }
    func sample(at t: CFTimeInterval) -> Any? { nil }

    private func num(_ v: Any?) -> CGFloat? {
        if let c = v as? CGFloat { return c }
        if let d = v as? Double { return CGFloat(d) }
        if let f = v as? Float { return CGFloat(f) }
        if let i = v as? Int { return CGFloat(i) }
        if let n = v as? NSNumber { return CGFloat(n.doubleValue) }
        return nil
    }
    override func scalar(for name: String, at t: CFTimeInterval, base: CGFloat) -> CGFloat? {
        guard keyPath == name, let v = num(sample(at: t)) else { return nil }
        return isAdditive ? base + v : v
    }
    override func point(for name: String, at t: CFTimeInterval, base: CGPoint) -> CGPoint? {
        guard keyPath == name else { return nil }
        let s = sample(at: t)
        if let p = s as? CGPoint { return isAdditive ? CGPoint(x: base.x + p.x, y: base.y + p.y) : p }
        if let p = (s as? CGPointBox)?.point { return p }
        return nil
    }
    override func color(for name: String, at t: CFTimeInterval) -> CGColor? {
        guard keyPath == name else { return nil }
        return sample(at: t) as? CGColor
    }
    override func applyTransform(_ v: CGAffineTransform, at t: CFTimeInterval) -> CGAffineTransform {
        guard let k = keyPath, k.hasPrefix("transform"), let s = sample(at: t) else { return v }
        if let m = s as? CATransform3D { return m.affine }
        guard let n = num(s) else { return v }
        switch k {
        case "transform.scale": return CGAffineTransform(scaleX: n, y: n).concatenating(v)
        case "transform.scale.x": return CGAffineTransform(scaleX: n, y: 1).concatenating(v)
        case "transform.scale.y": return CGAffineTransform(scaleX: 1, y: n).concatenating(v)
        case "transform.rotation", "transform.rotation.z": return CGAffineTransform(rotationAngle: n).concatenating(v)
        case "transform.translation.x": return CGAffineTransform(translationX: n, y: 0).concatenating(v)
        case "transform.translation.y": return CGAffineTransform(translationX: 0, y: n).concatenating(v)
        default: return v
        }
    }
    func interpolate(_ a: Any?, _ b: Any?, _ u: CGFloat) -> Any? {
        if let x = num(a), let y = num(b) { return x + (y - x) * u }
        if let x = a as? CGPoint, let y = b as? CGPoint { return CGPoint(x: x.x + (y.x - x.x) * u, y: x.y + (y.y - x.y) * u) }
        if let x = a as? CATransform3D, let y = b as? CATransform3D {
            var m = x
            m.m11 += (y.m11 - x.m11) * u; m.m12 += (y.m12 - x.m12) * u; m.m21 += (y.m21 - x.m21) * u; m.m22 += (y.m22 - x.m22) * u
            m.m41 += (y.m41 - x.m41) * u; m.m42 += (y.m42 - x.m42) * u
            return m
        }
        if let x = a as? CGColor, let y = b as? CGColor {
            return CGColor(srgbRed: x.sr + (y.sr - x.sr) * u, green: x.sg + (y.sg - x.sg) * u, blue: x.sb + (y.sb - x.sb) * u, alpha: x.a + (y.a - x.a) * u)
        }
        return u < 0.5 ? a : b
    }
}

open class CABasicAnimation: CAPropertyAnimation {
    open var fromValue: Any?
    open var toValue: Any?
    open var byValue: Any?
    override func sample(at t: CFTimeInterval) -> Any? {
        guard let u = progress(at: t) else { return nil }
        return interpolate(fromValue, toValue, u)
    }
}
open class CASpringAnimation: CABasicAnimation {
    open var mass: CGFloat = 1
    open var stiffness: CGFloat = 100
    open var damping: CGFloat = 10
    open var initialVelocity: CGFloat = 0
    open var settlingDuration: CFTimeInterval {
        let w = (stiffness / mass).squareRoot(), z = damping / (2 * (stiffness * mass).squareRoot())
        return Double(6.9 / max(z * w, 0.01))
    }
    override var effectiveDuration: CFTimeInterval { duration > 0 ? duration : settlingDuration }
    override func sample(at t: CFTimeInterval) -> Any? {
        if t >= totalTime, isRemovedOnCompletion { return nil }
        let w = (stiffness / mass).squareRoot(), z = damping / (2 * (stiffness * mass).squareRoot())
        let x = CGFloat(max(t, 0))
        let u: CGFloat
        if z < 1 {
            let wd = w * (1 - z * z).squareRoot()
            let e = CGFloat(exp(Double(-z * w * x)))
            u = 1 - e * (CGFloat(cos(Double(wd * x))) + (z * w - initialVelocity) / wd * CGFloat(sin(Double(wd * x))))
        } else {
            u = 1 - CGFloat(exp(Double(-w * x))) * (1 + (w - initialVelocity) * x)
        }
        return interpolate(fromValue, toValue, u)
    }
}
open class CAKeyframeAnimation: CAPropertyAnimation {
    open var values: [Any]?
    open var keyTimes: [NSNumber]?
    open var timingFunctions: [CAMediaTimingFunction]?
    open var calculationMode = CAAnimationCalculationMode.linear
    open var path: CGPath?
    override func sample(at t: CFTimeInterval) -> Any? {
        guard let u = progress(at: t), let v = values, !v.isEmpty else { return nil }
        if v.count == 1 { return v[0] }
        let times = keyTimes?.map { CGFloat($0.doubleValue) } ?? (0..<v.count).map { CGFloat($0) / CGFloat(v.count - 1) }
        var i = 0
        while i < times.count - 2, u >= times[min(i + 1, times.count - 1)] { i += 1 }
        let a = times[i], b = times[min(i + 1, times.count - 1)]
        if calculationMode == .discrete { return v[min(i, v.count - 1)] }
        var f = b > a ? (u - a) / (b - a) : 1
        if let tf = timingFunctions, !tf.isEmpty { f = tf[min(i, tf.count - 1)].value(at: f) }
        return interpolate(v[min(i, v.count - 1)], v[min(i + 1, v.count - 1)], max(0, min(1, f)))
    }
}
open class CAAnimationGroup: CAAnimation {
    open var animations: [CAAnimation]?
    private func over(_ t: CFTimeInterval) -> Bool { t >= totalTime && isRemovedOnCompletion }
    override func scalar(for name: String, at t: CFTimeInterval, base: CGFloat) -> CGFloat? {
        guard !over(t) else { return nil }
        var v: CGFloat? = nil
        for a in animations ?? [] { if let x = a.scalar(for: name, at: t - a.beginTime, base: v ?? base) { v = x } }
        return v
    }
    override func point(for name: String, at t: CFTimeInterval, base: CGPoint) -> CGPoint? {
        guard !over(t) else { return nil }
        var v: CGPoint? = nil
        for a in animations ?? [] { if let x = a.point(for: name, at: t - a.beginTime, base: v ?? base) { v = x } }
        return v
    }
    override func color(for name: String, at t: CFTimeInterval) -> CGColor? {
        guard !over(t) else { return nil }
        var v: CGColor? = nil
        for a in animations ?? [] { if let x = a.color(for: name, at: t - a.beginTime) { v = x } }
        return v
    }
    override func applyTransform(_ v: CGAffineTransform, at t: CFTimeInterval) -> CGAffineTransform {
        guard !over(t) else { return v }
        var m = v
        for a in animations ?? [] { m = a.applyTransform(m, at: t - a.beginTime) }
        return m
    }
}
open class CATransition: CAAnimation {
    open var type = CATransitionType.fade
    open var subtype: CATransitionSubtype?
}

public enum CATransaction {
    nonisolated(unsafe) private static var completions: [() -> Void] = []
    nonisolated(unsafe) private static var depth = 0
    nonisolated(unsafe) public static var onCommit: (() -> Void)?
    public static func begin() { depth += 1 }
    public static func commit() {
        depth = max(0, depth - 1)
        guard depth == 0 else { return }
        onCommit?()
        if !completions.isEmpty {
            let c = completions; completions = []
            for f in c { f() }
        }
    }
    public static func flush() { onCommit?() }
    public static func setDisableActions(_ on: Bool) {}
    public static func disableActions() -> Bool { true }
    public static func setAnimationDuration(_ d: CFTimeInterval) {}
    public static func animationDuration() -> CFTimeInterval { 0.25 }
    public static func setAnimationTimingFunction(_ f: CAMediaTimingFunction?) {}
    public static func setCompletionBlock(_ f: (() -> Void)?) { if let f { completions.append(f) } }
}

// MARK: Particle emitters. The simulation fills in with the habitat's weather; the shape is here so it compiles and keys resolve.

public struct CAEmitterLayerEmitterShape: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let point = Self(rawValue: "point"), line = Self(rawValue: "line"), rectangle = Self(rawValue: "rectangle"), circle = Self(rawValue: "circle"), cuboid = Self(rawValue: "cuboid"), sphere = Self(rawValue: "sphere")
}
public struct CAEmitterLayerEmitterMode: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let points = Self(rawValue: "points"), outline = Self(rawValue: "outline"), surface = Self(rawValue: "surface"), volume = Self(rawValue: "volume")
}
public struct CAEmitterLayerRenderMode: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let unordered = Self(rawValue: "unordered"), oldestFirst = Self(rawValue: "oldestFirst"), oldestLast = Self(rawValue: "oldestLast"), backToFront = Self(rawValue: "backToFront"), additive = Self(rawValue: "additive")
}
open class CAEmitterCell: NSObject {
    public override init() { super.init() }
    open var name: String?
    open var isEnabled = true
    open var birthRate: Float = 0
    open var lifetime: Float = 0
    open var lifetimeRange: Float = 0
    open var velocity: CGFloat = 0
    open var velocityRange: CGFloat = 0
    open var xAcceleration: CGFloat = 0
    open var yAcceleration: CGFloat = 0
    open var zAcceleration: CGFloat = 0
    open var emissionLongitude: CGFloat = 0
    open var emissionLatitude: CGFloat = 0
    open var emissionRange: CGFloat = 0
    open var scale: CGFloat = 1
    open var scaleRange: CGFloat = 0
    open var scaleSpeed: CGFloat = 0
    open var spin: CGFloat = 0
    open var spinRange: CGFloat = 0
    open var alphaRange: Float = 0
    open var alphaSpeed: Float = 0
    open var redRange: Float = 0, greenRange: Float = 0, blueRange: Float = 0
    open var redSpeed: Float = 0, greenSpeed: Float = 0, blueSpeed: Float = 0
    open var color: CGColor?
    open var contents: Any?
    open var contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    open var contentsScale: CGFloat = 1
    open var beginTime: CFTimeInterval = 0
    open var duration: CFTimeInterval = 0
    open var speed: Float = 1
    open var repeatCount: Float = 0
    open var emitterCells: [CAEmitterCell]?
}
open class CAEmitterLayer: CALayer {
    open var emitterCells: [CAEmitterCell]? { didSet { touch() } }
    open var emitterPosition = CGPoint.zero
    open var emitterZPosition: CGFloat = 0
    open var emitterSize = CGSize.zero
    open var emitterDepth: CGFloat = 0
    open var emitterShape = CAEmitterLayerEmitterShape.point
    open var emitterMode = CAEmitterLayerEmitterMode.volume
    open var renderMode = CAEmitterLayerRenderMode.unordered
    open var birthRate: Float = 1
    open var lifetime: Float = 1
    open var velocity: Float = 1
    open var scale: Float = 1
    open var spin: Float = 1
    open var seed: UInt32 = 0
    open var beginTime: CFTimeInterval = 0
    open var timeOffset: CFTimeInterval = 0
    open var preservesDepth = false
    open override func setValue(_ v: Any?, forKeyPath key: String) {
        // "emitterCells.<name>.<property>"
        let parts = key.split(separator: ".").map(String.init)
        guard parts.count == 3, parts[0] == "emitterCells", let c = emitterCells?.first(where: { $0.name == parts[1] }) else { return }
        let n: CGFloat
        if let x = v as? CGFloat { n = x } else if let x = v as? Double { n = CGFloat(x) } else if let x = v as? Float { n = CGFloat(x) } else if let x = v as? Int { n = CGFloat(x) } else { return }
        switch parts[2] {
        case "birthRate": c.birthRate = Float(n)
        case "velocity": c.velocity = n
        case "velocityRange": c.velocityRange = n
        case "emissionLongitude": c.emissionLongitude = n
        case "xAcceleration": c.xAcceleration = n
        case "yAcceleration": c.yAcceleration = n
        case "lifetime": c.lifetime = Float(n)
        case "scale": c.scale = n
        default: break
        }
    }
}

// MARK: The display link. AppKit's frame source drives it.

public final class CADisplayLink: NSObject, @unchecked Sendable {
    let fire: () -> Void
    public var isPaused = false
    public var preferredFrameRateRange = CAFrameRateRange.default
    public var preferredFramesPerSecond = 0
    public private(set) var timestamp: CFTimeInterval = 0
    public private(set) var targetTimestamp: CFTimeInterval = 0
    public var duration: CFTimeInterval { 1.0 / 60.0 }
    nonisolated(unsafe) public static var active: [CADisplayLink] = []
    private var last: CFTimeInterval = 0
    public init(fire: @escaping () -> Void) { self.fire = fire; super.init() }
    public func add(to loop: RunLoop, forMode mode: RunLoop.Mode) { CADisplayLink.active.append(self) }
    public func remove(from loop: RunLoop, forMode mode: RunLoop.Mode) { invalidate() }
    public func invalidate() { CADisplayLink.active.removeAll { $0 === self } }
    /// One beat of the display. Honors a lower preferred rate by skipping beats.
    public func beat(now: CFTimeInterval) {
        guard !isPaused else { return }
        let rate = preferredFrameRateRange.preferred ?? preferredFrameRateRange.maximum
        if rate > 0, rate < 59, now - last < 1.0 / Double(rate) - 0.004 { return }
        timestamp = now
        targetTimestamp = now + duration
        last = now
        fire()
    }
}
