// CoreGraphics stand-in for Windows: paths.
//
// Elements use CoreGraphics' meaning exactly, including arcs (angles measured in the path's own
// coordinates, with `clockwise` as Core Graphics defines it in a y-up space) because the habitat's
// collision shapes are traced from the same paths the art draws.
import Foundation

public enum CGPathElementType: Int32, Sendable { case moveToPoint, addLineToPoint, addQuadCurveToPoint, addCurveToPoint, closeSubpath }

public struct CGPathElement {
    public var type: CGPathElementType
    public var points: UnsafeMutablePointer<CGPoint>
}

public enum PathElement: Equatable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(CGPoint, CGPoint)                  // control, end
    case cubic(CGPoint, CGPoint, CGPoint)        // control1, control2, end
    case close
}

public class CGPath: @unchecked Sendable {
    public fileprivate(set) var elements: [PathElement] = []
    fileprivate var subpathStart: CGPoint? = nil
    fileprivate var last: CGPoint? = nil

    public init() {}

    public convenience init(rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        self.init()
        appendRect(rect, transform?.pointee ?? .identity)
    }
    public convenience init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        self.init()
        appendEllipse(rect, transform?.pointee ?? .identity)
    }
    public convenience init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: UnsafePointer<CGAffineTransform>?) {
        self.init()
        appendRounded(rect, cornerWidth, cornerHeight, transform?.pointee ?? .identity)
    }

    public var isEmpty: Bool { elements.isEmpty }
    public var currentPoint: CGPoint { last ?? .zero }

    public func copy() -> CGPath? { let p = CGPath(); p.adopt(self); return p }
    public func mutableCopy() -> CGMutablePath? { let p = CGMutablePath(); p.adopt(self); return p }
    public func copy(using transform: UnsafePointer<CGAffineTransform>?) -> CGPath? {
        let p = CGPath(); p.adopt(self, transform?.pointee ?? .identity); return p
    }
    public func mutableCopy(using transform: UnsafePointer<CGAffineTransform>?) -> CGMutablePath? {
        let p = CGMutablePath(); p.adopt(self, transform?.pointee ?? .identity); return p
    }

    public func applyWithBlock(_ block: (UnsafePointer<CGPathElement>) -> Void) {
        let buf = UnsafeMutablePointer<CGPoint>.allocate(capacity: 3)
        defer { buf.deallocate() }
        for e in elements {
            var t = CGPathElementType.closeSubpath
            switch e {
            case let .move(p): buf[0] = p; t = .moveToPoint
            case let .line(p): buf[0] = p; t = .addLineToPoint
            case let .quad(c, p): buf[0] = c; buf[1] = p; t = .addQuadCurveToPoint
            case let .cubic(a, b, p): buf[0] = a; buf[1] = b; buf[2] = p; t = .addCurveToPoint
            case .close: break
            }
            var el = CGPathElement(type: t, points: buf)
            withUnsafePointer(to: &el) { block($0) }
        }
    }

    /// The smallest box containing every point, control points included (as Core Graphics does).
    public var boundingBox: CGRect {
        var pts: [CGPoint] = []
        for e in elements {
            switch e {
            case let .move(p), let .line(p): pts.append(p)
            case let .quad(c, p): pts += [c, p]
            case let .cubic(a, b, p): pts += [a, b, p]
            case .close: break
            }
        }
        return CGPath.box(pts)
    }

    /// The smallest box containing the curve itself.
    public var boundingBoxOfPath: CGRect {
        var pts: [CGPoint] = []
        for sub in flattened(tolerance: 0.05) { pts += sub.points }
        return CGPath.box(pts)
    }

    static func box(_ pts: [CGPoint]) -> CGRect {
        guard let f = pts.first else { return .null }
        var x0 = f.x, x1 = f.x, y0 = f.y, y1 = f.y
        for p in pts { x0 = min(x0, p.x); x1 = max(x1, p.x); y0 = min(y0, p.y); y1 = max(y1, p.y) }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public struct Flat { public var points: [CGPoint]; public var closed: Bool }

    /// Polylines close to the curves, for hit tests and bounds.
    public func flattened(tolerance: CGFloat = 0.25) -> [Flat] {
        var out: [Flat] = []
        var cur: [CGPoint] = []
        var at = CGPoint.zero
        func flush(_ closed: Bool) {
            if !cur.isEmpty { out.append(Flat(points: cur, closed: closed)) }
            cur = []
        }
        for e in elements {
            switch e {
            case let .move(p): flush(false); cur = [p]; at = p
            case let .line(p):
                if cur.isEmpty { cur = [at] }
                cur.append(p); at = p
            case let .quad(c, p):
                if cur.isEmpty { cur = [at] }
                let d = hypot(at.x - 2 * c.x + p.x, at.y - 2 * c.y + p.y)
                let n = max(2, Int((d / tolerance).squareRoot().rounded(.up)))
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n), u = 1 - t
                    cur.append(CGPoint(x: u * u * at.x + 2 * u * t * c.x + t * t * p.x,
                                       y: u * u * at.y + 2 * u * t * c.y + t * t * p.y))
                }
                at = p
            case let .cubic(a, b, p):
                if cur.isEmpty { cur = [at] }
                let d = max(hypot(at.x - 2 * a.x + b.x, at.y - 2 * a.y + b.y),
                            hypot(a.x - 2 * b.x + p.x, a.y - 2 * b.y + p.y))
                let n = max(2, Int(((3 * d) / (2 * tolerance)).squareRoot().rounded(.up)))
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n), u = 1 - t
                    let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
                    cur.append(CGPoint(x: w0 * at.x + w1 * a.x + w2 * b.x + w3 * p.x,
                                       y: w0 * at.y + w1 * a.y + w2 * b.y + w3 * p.y))
                }
                at = p
            case .close:
                if let f = cur.first { at = f }
                flush(true)
            }
        }
        flush(false)
        return out
    }

    public func contains(_ point: CGPoint, using rule: CGPathFillRule = .winding, transform: CGAffineTransform = .identity) -> Bool {
        let q = transform.isIdentity ? point : point.applying(transform.inverted())
        var winding = 0, crossings = 0
        for sub in flattened() {
            let ps = sub.points
            guard ps.count > 1 else { continue }
            for i in 0..<ps.count {
                let a = ps[i], b = ps[(i + 1) % ps.count]
                if a.y <= q.y {
                    if b.y > q.y, cross(a, b, q) > 0 { winding += 1; crossings += 1 }
                } else if b.y <= q.y, cross(a, b, q) < 0 { winding -= 1; crossings += 1 }
            }
        }
        return rule == .winding ? winding != 0 : crossings % 2 == 1
    }
    private func cross(_ a: CGPoint, _ b: CGPoint, _ q: CGPoint) -> CGFloat { (b.x - a.x) * (q.y - a.y) - (q.x - a.x) * (b.y - a.y) }

    // Outlining: a polygon around the stroke, close enough for the art's few uses (bounds and hit tests).
    public func copy(strokingWithWidth width: CGFloat, lineCap: CGLineCap, lineJoin: CGLineJoin, miterLimit: CGFloat, transform: CGAffineTransform = .identity) -> CGPath {
        let out = CGMutablePath()
        let h = width / 2
        for sub in flattened() {
            let ps = sub.points
            guard ps.count > 1 else { continue }
            var left: [CGPoint] = [], right: [CGPoint] = []
            for i in 0..<ps.count {
                let a = ps[max(0, i - 1)], b = ps[min(ps.count - 1, i + 1)]
                let dx = b.x - a.x, dy = b.y - a.y
                let l = max(hypot(dx, dy), 1e-6)
                let nx = -dy / l * h, ny = dx / l * h
                left.append(CGPoint(x: ps[i].x + nx, y: ps[i].y + ny))
                right.append(CGPoint(x: ps[i].x - nx, y: ps[i].y - ny))
            }
            let poly = left + right.reversed()
            out.addLines(between: poly, transform: transform)
            out.closeSubpath()
        }
        return out
    }

    // MARK: Building (shared with CGMutablePath and the context's current path)

    func adopt(_ other: CGPath, _ t: CGAffineTransform = .identity) {
        if t.isIdentity {
            elements += other.elements
            subpathStart = other.subpathStart ?? subpathStart
            last = other.last ?? last
            return
        }
        for e in other.elements {
            switch e {
            case let .move(p): rawMove(p.applying(t))
            case let .line(p): rawLine(p.applying(t))
            case let .quad(c, p): rawQuad(c.applying(t), p.applying(t))
            case let .cubic(a, b, p): rawCubic(a.applying(t), b.applying(t), p.applying(t))
            case .close: rawClose()
            }
        }
    }
    func rawMove(_ p: CGPoint) { elements.append(.move(p)); subpathStart = p; last = p }
    func rawLine(_ p: CGPoint) { ensureStart(p); elements.append(.line(p)); last = p }
    func rawQuad(_ c: CGPoint, _ p: CGPoint) { ensureStart(c); elements.append(.quad(c, p)); last = p }
    func rawCubic(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) { ensureStart(a); elements.append(.cubic(a, b, p)); last = p }
    func rawClose() { if !elements.isEmpty { elements.append(.close); last = subpathStart } }
    private func ensureStart(_ p: CGPoint) { if last == nil { rawMove(p) } }

    func appendRect(_ r: CGRect, _ t: CGAffineTransform) {
        rawMove(CGPoint(x: r.minX, y: r.minY).applying(t))
        rawLine(CGPoint(x: r.maxX, y: r.minY).applying(t))
        rawLine(CGPoint(x: r.maxX, y: r.maxY).applying(t))
        rawLine(CGPoint(x: r.minX, y: r.maxY).applying(t))
        rawClose()
    }

    private static let kappa: CGFloat = 0.5522847498307933

    func appendEllipse(_ r: CGRect, _ t: CGAffineTransform) {
        // The same order Core Graphics uses: start at the right, go counter-clockwise in y-up.
        let cx = r.midX, cy = r.midY, rx = r.width / 2, ry = r.height / 2
        let kx = rx * CGPath.kappa, ky = ry * CGPath.kappa
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(t) }
        rawMove(P(cx + rx, cy))
        rawCubic(P(cx + rx, cy + ky), P(cx + kx, cy + ry), P(cx, cy + ry))
        rawCubic(P(cx - kx, cy + ry), P(cx - rx, cy + ky), P(cx - rx, cy))
        rawCubic(P(cx - rx, cy - ky), P(cx - kx, cy - ry), P(cx, cy - ry))
        rawCubic(P(cx + kx, cy - ry), P(cx + rx, cy - ky), P(cx + rx, cy))
        rawClose()
    }

    func appendRounded(_ r: CGRect, _ w: CGFloat, _ h: CGFloat, _ t: CGAffineTransform) {
        let w = min(w, r.width / 2), h = min(h, r.height / 2)
        if w <= 0 || h <= 0 { appendRect(r, t); return }
        let kx = w * CGPath.kappa, ky = h * CGPath.kappa
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(t) }
        rawMove(P(r.minX + w, r.minY))
        rawLine(P(r.maxX - w, r.minY))
        rawCubic(P(r.maxX - w + kx, r.minY), P(r.maxX, r.minY + h - ky), P(r.maxX, r.minY + h))
        rawLine(P(r.maxX, r.maxY - h))
        rawCubic(P(r.maxX, r.maxY - h + ky), P(r.maxX - w + kx, r.maxY), P(r.maxX - w, r.maxY))
        rawLine(P(r.minX + w, r.maxY))
        rawCubic(P(r.minX + w - kx, r.maxY), P(r.minX, r.maxY - h + ky), P(r.minX, r.maxY - h))
        rawLine(P(r.minX, r.minY + h))
        rawCubic(P(r.minX, r.minY + h - ky), P(r.minX + w - kx, r.minY), P(r.minX + w, r.minY))
        rawClose()
    }

    /// `clockwise` follows Core Graphics: in y-up coordinates, clockwise == false runs counter-clockwise
    /// on the page, i.e. increasing angle.
    func appendArc(center c: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat, clockwise: Bool, _ t: CGAffineTransform) {
        let tau = CGFloat.pi * 2
        var sweep = end - start
        if clockwise {
            if sweep > 0 { sweep -= tau * (sweep / tau).rounded(.up) }
            if sweep < -tau { sweep = -tau }
        } else {
            if sweep < 0 { sweep += tau * (-sweep / tau).rounded(.up) }
            if sweep > tau { sweep = tau }
        }
        func P(_ a: CGFloat, _ r: CGFloat = 1) -> CGPoint {
            CGPoint(x: c.x + radius * r * CGFloat(cos(Double(a))), y: c.y + radius * r * CGFloat(sin(Double(a))))
        }
        let first = P(start).applying(t)
        if last == nil { rawMove(first) } else { rawLine(first) }
        if radius == 0 || sweep == 0 { return }
        let n = max(1, Int((abs(sweep) / (CGFloat.pi / 2)).rounded(.up)))
        let step = sweep / CGFloat(n)
        let k = 4.0 / 3.0 * CGFloat(tan(Double(step) / 4))
        var a = start
        for _ in 0..<n {
            let b = a + step
            let ca = CGFloat(cos(Double(a))), sa = CGFloat(sin(Double(a)))
            let cb = CGFloat(cos(Double(b))), sb = CGFloat(sin(Double(b)))
            let p1 = CGPoint(x: c.x + radius * (ca - k * sa), y: c.y + radius * (sa + k * ca)).applying(t)
            let p2 = CGPoint(x: c.x + radius * (cb + k * sb), y: c.y + radius * (sb - k * cb)).applying(t)
            let p3 = CGPoint(x: c.x + radius * cb, y: c.y + radius * sb).applying(t)
            rawCubic(p1, p2, p3)
            a = b
        }
    }

    /// `addArc(tangent1End:tangent2End:radius:)`.
    func appendTangentArc(_ p1: CGPoint, _ p2: CGPoint, _ radius: CGFloat, _ t: CGAffineTransform) {
        let t1 = p1.applying(t), t2 = p2.applying(t)
        guard let p0 = last else { rawMove(t1); return }
        let v1 = CGPoint(x: p0.x - t1.x, y: p0.y - t1.y), v2 = CGPoint(x: t2.x - t1.x, y: t2.y - t1.y)
        let l1 = hypot(v1.x, v1.y), l2 = hypot(v2.x, v2.y)
        let cosA = l1 > 0 && l2 > 0 ? (v1.x * v2.x + v1.y * v2.y) / (l1 * l2) : 1
        let angle = CGFloat(acos(Double(max(-1, min(1, cosA)))))
        if radius == 0 || l1 == 0 || l2 == 0 || angle == 0 || abs(angle - .pi) < 1e-9 { rawLine(t1); return }
        let d = radius / CGFloat(tan(Double(angle) / 2))
        let a = CGPoint(x: t1.x + v1.x / l1 * d, y: t1.y + v1.y / l1 * d)
        let b = CGPoint(x: t1.x + v2.x / l2 * d, y: t1.y + v2.y / l2 * d)
        rawLine(a)
        let turn = v1.x * v2.y - v1.y * v2.x
        let h = radius / CGFloat(sin(Double(angle) / 2))
        let bis = CGPoint(x: v1.x / l1 + v2.x / l2, y: v1.y / l1 + v2.y / l2)
        let bl = max(hypot(bis.x, bis.y), 1e-9)
        let c = CGPoint(x: t1.x + bis.x / bl * h, y: t1.y + bis.y / bl * h)
        let sa = CGFloat(atan2(Double(a.y - c.y), Double(a.x - c.x)))
        let ea = CGFloat(atan2(Double(b.y - c.y), Double(b.x - c.x)))
        appendArc(center: c, radius: radius, start: sa, end: ea, clockwise: turn > 0, .identity)
    }
}

public final class CGMutablePath: CGPath, @unchecked Sendable {
    public override init() { super.init() }

    public func move(to p: CGPoint, transform: CGAffineTransform = .identity) { rawMove(p.applying(transform)) }
    public func addLine(to p: CGPoint, transform: CGAffineTransform = .identity) { rawLine(p.applying(transform)) }
    public func addLines(between points: [CGPoint], transform: CGAffineTransform = .identity) {
        guard let f = points.first else { return }
        rawMove(f.applying(transform))
        for p in points.dropFirst() { rawLine(p.applying(transform)) }
    }
    public func addQuadCurve(to p: CGPoint, control: CGPoint, transform: CGAffineTransform = .identity) {
        rawQuad(control.applying(transform), p.applying(transform))
    }
    public func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint, transform: CGAffineTransform = .identity) {
        rawCubic(control1.applying(transform), control2.applying(transform), p.applying(transform))
    }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CGAffineTransform = .identity) {
        appendArc(center: center, radius: radius, start: startAngle, end: endAngle, clockwise: clockwise, transform)
    }
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {
        appendTangentArc(tangent1End, tangent2End, radius, transform)
    }
    public func addEllipse(in r: CGRect, transform: CGAffineTransform = .identity) { appendEllipse(r, transform) }
    public func addRect(_ r: CGRect, transform: CGAffineTransform = .identity) { appendRect(r, transform) }
    public func addRects(_ rs: [CGRect], transform: CGAffineTransform = .identity) { for r in rs { appendRect(r, transform) } }
    public func addRoundedRect(in r: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform = .identity) {
        appendRounded(r, cornerWidth, cornerHeight, transform)
    }
    public func addPath(_ p: CGPath, transform: CGAffineTransform = .identity) { adopt(p, transform) }
    public func closeSubpath() { rawClose() }
    public func removeAll() { elements.removeAll(); subpathStart = nil; last = nil }
}
