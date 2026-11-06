// CoreGraphics stand-in for Windows: geometry.
//
// Foundation on Windows already has CGFloat, CGPoint, CGSize and CGRect. This adds what it lacks,
// keeping Apple's names and semantics so the Mac sources compile unchanged.
@_exported import Foundation

public struct CGAffineTransform: Equatable, Sendable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init() { self = .identity }
    public init(translationX x: CGFloat, y: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y) }
    public init(scaleX x: CGFloat, y: CGFloat) { self.init(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0) }
    public init(rotationAngle t: CGFloat) {
        let s = CGFloat(sin(Double(t))), k = CGFloat(cos(Double(t)))
        self.init(a: k, b: s, c: -s, d: k, tx: 0, ty: 0)
    }
    public static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    public var isIdentity: Bool { self == .identity }

    /// `self` first, then `t` (Apple's order).
    public func concatenating(_ t: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(a: a * t.a + b * t.c, b: a * t.b + b * t.d,
                          c: c * t.a + d * t.c, d: c * t.b + d * t.d,
                          tx: tx * t.a + ty * t.c + t.tx, ty: tx * t.b + ty * t.d + t.ty)
    }
    public func translatedBy(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: x, y: y).concatenating(self)
    }
    public func scaledBy(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: x, y: y).concatenating(self)
    }
    public func rotated(by angle: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: angle).concatenating(self)
    }
    public func inverted() -> CGAffineTransform {
        let det = a * d - b * c
        if det == 0 { return self }
        return CGAffineTransform(a: d / det, b: -b / det, c: -c / det, d: a / det,
                                 tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
    }
}

public func CGAffineTransformMakeTranslation(_ x: CGFloat, _ y: CGFloat) -> CGAffineTransform { .init(translationX: x, y: y) }
public func CGAffineTransformMakeScale(_ x: CGFloat, _ y: CGFloat) -> CGAffineTransform { .init(scaleX: x, y: y) }
public func CGAffineTransformMakeRotation(_ t: CGFloat) -> CGAffineTransform { .init(rotationAngle: t) }

extension CGPoint {
    public func applying(_ t: CGAffineTransform) -> CGPoint {
        CGPoint(x: x * t.a + y * t.c + t.tx, y: x * t.b + y * t.d + t.ty)
    }
}

extension CGSize {
    public func applying(_ t: CGAffineTransform) -> CGSize {
        CGSize(width: width * t.a + height * t.c, height: width * t.b + height * t.d)
    }
}

extension CGRect {
    /// The bounding box of the transformed corners.
    public func applying(_ t: CGAffineTransform) -> CGRect {
        let n = standardized
        let ps = [CGPoint(x: n.minX, y: n.minY), CGPoint(x: n.maxX, y: n.minY),
                  CGPoint(x: n.maxX, y: n.maxY), CGPoint(x: n.minX, y: n.maxY)].map { $0.applying(t) }
        let xs = ps.map(\.x), ys = ps.map(\.y)
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
