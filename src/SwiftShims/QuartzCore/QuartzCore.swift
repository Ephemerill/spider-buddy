// QuartzCore stand-in for Windows. Timing is real. The layer tree is, for now, state with no compositor behind it:
// enough for behavior to compile and run. The Windows compositor attaches to it later.
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
}
public let CATransform3DIdentity = CATransform3D()
public func CATransform3DMakeTranslation(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    var t = CATransform3D(); t.m41 = x; t.m42 = y; t.m43 = z; return t
}
public func CATransform3DMakeScale(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    var t = CATransform3D(); t.m11 = x; t.m22 = y; t.m33 = z; return t
}
public func CATransform3DMakeRotation(_ a: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    var t = CATransform3D()
    let c = CGFloat(cos(Double(a))), s = CGFloat(sin(Double(a)))
    if z != 0 { t.m11 = c; t.m12 = s * z; t.m21 = -s * z; t.m22 = c }
    return t
}

public struct CALayerContentsGravity: Equatable, Sendable { public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let center = Self(rawValue: "center"), resize = Self(rawValue: "resize"), resizeAspect = Self(rawValue: "resizeAspect"), resizeAspectFill = Self(rawValue: "resizeAspectFill"), bottomLeft = Self(rawValue: "bottomLeft")
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

open class CALayer: NSObject {
    public override init() { super.init() }
    public init(layer: Any) { super.init() }
    open var bounds = CGRect.zero
    open var position = CGPoint.zero
    open var anchorPoint = CGPoint(x: 0.5, y: 0.5)
    open var zPosition: CGFloat = 0
    open var transform = CATransform3DIdentity
    open var opacity: Float = 1
    open var isHidden = false
    open var masksToBounds = false
    open var isOpaque = false
    public private(set) var affineTransform_ = CGAffineTransform.identity
    open func setAffineTransform(_ t: CGAffineTransform) { affineTransform_ = t }
    open func affineTransform() -> CGAffineTransform { affineTransform_ }
    open var contents: Any? = nil
    open var contentsScale: CGFloat = 1
    open var contentsGravity = CALayerContentsGravity.resize
    open var contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    open var backgroundColor: CGColor? = nil
    open var cornerRadius: CGFloat = 0
    open var borderWidth: CGFloat = 0
    open var borderColor: CGColor? = nil
    open var shadowColor: CGColor? = nil
    open var shadowOpacity: Float = 0
    open var shadowRadius: CGFloat = 3
    open var shadowOffset = CGSize(width: 0, height: -3)
    open var shadowPath: CGPath? = nil
    open var mask: CALayer? = nil
    open var name: String? = nil
    open var actions: [String: CAAction]? = nil
    open private(set) var sublayers: [CALayer]? = nil
    open private(set) weak var superlayer: CALayer? = nil
    open var frame: CGRect {
        get { CGRect(x: position.x - bounds.width * anchorPoint.x, y: position.y - bounds.height * anchorPoint.y, width: bounds.width, height: bounds.height) }
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
    }
    open func insertSublayer(_ l: CALayer, at i: UInt32) {
        l.removeFromSuperlayer()
        if sublayers == nil { sublayers = [] }
        sublayers!.insert(l, at: min(Int(i), sublayers!.count))
        l.superlayer = self
    }
    open func removeFromSuperlayer() {
        superlayer?.sublayers?.removeAll { $0 === self }
        superlayer = nil
    }
    open func setNeedsDisplay() {}
    open func display() {}
    open func removeAllAnimations() {}
    open func removeAnimation(forKey key: String) {}
    open func add(_ anim: CAAnimation, forKey key: String?) {}
    open func animation(forKey key: String) -> CAAnimation? { nil }
    open func presentation() -> Self? { self }
}

open class CAShapeLayer: CALayer {
    open var path: CGPath? = nil
    open var fillColor: CGColor? = nil
    open var strokeColor: CGColor? = nil
    open var lineWidth: CGFloat = 1
    open var lineCap = CAShapeLayerLineCap.butt
    open var lineJoin = CAShapeLayerLineJoin.miter
    open var fillRule = CAShapeLayerFillRule.nonZero
    open var lineDashPattern: [NSNumber]? = nil
    open var lineDashPhase: CGFloat = 0
    open var strokeStart: CGFloat = 0
    open var strokeEnd: CGFloat = 1
    open var miterLimit: CGFloat = 10
}

open class CAAnimation: NSObject {
    public override init() { super.init() }
    open var duration: CFTimeInterval = 0
    open var beginTime: CFTimeInterval = 0
    open var repeatCount: Float = 0
    open var autoreverses = false
    open var isRemovedOnCompletion = true
}

public enum CATransaction {
    public static func begin() {}
    public static func commit() {}
    public static func flush() {}
    public static func setDisableActions(_ on: Bool) {}
    public static func setAnimationDuration(_ d: CFTimeInterval) {}
}
