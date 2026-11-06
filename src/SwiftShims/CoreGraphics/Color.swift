// CoreGraphics stand-in for Windows: colors, color spaces, gradients, line styles.
import Foundation

public final class CGColorSpace: @unchecked Sendable {
    public let name: String
    public static let sRGB = "kCGColorSpaceSRGB"
    public static let displayP3 = "kCGColorSpaceDisplayP3"
    public static let extendedSRGB = "kCGColorSpaceExtendedSRGB"
    public init?(name: String) { self.name = name }
    init(internalName: String) { self.name = internalName }
    public var numberOfComponents: Int { 3 }
}

public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace(internalName: "kCGColorSpaceDeviceRGB") }
public func CGColorSpaceCreateDeviceGray() -> CGColorSpace { CGColorSpace(internalName: "kCGColorSpaceDeviceGray") }

/// On the Mac, CGColor(red:green:blue:alpha:) and calibrated NSColors are Generic RGB (gamma 1.8, Apple's primaries),
/// and CGColor(gray:) is Generic Gray, and Core Graphics converts them to the bitmap's sRGB. So the same numbers paint
/// a different color from plain sRGB: 0.5 lands as 0.572. To look the same the conversion has to happen here. The matrix
/// comes from Apple's "Generic RGB Profile.icc" (rXYZ, gXYZ, bXYZ into D50-adapted linear sRGB; rows normalized so white
/// stays white) and was checked against CGColor.converted(to:) on the Mac: within 0.0002.
enum GenericRGB {
    static let gamma = 1.80078125
    static let m: [[Double]] = [[1.0249708, -0.0262889, 0.0013181],
                                [0.0193845, 0.9480289, 0.0325866],
                                [-0.0017838, -0.0014666, 1.0032504]]
    static func encode(_ v: Double) -> CGFloat {
        let c = max(0, min(1, v))
        return CGFloat(c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055)
    }
    static func toSRGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let l = [pow(max(0, Double(r)), gamma), pow(max(0, Double(g)), gamma), pow(max(0, Double(b)), gamma)]
        func row(_ i: Int) -> Double { m[i][0] * l[0] + m[i][1] * l[1] + m[i][2] * l[2] }
        return (encode(row(0)), encode(row(1)), encode(row(2)))
    }
    static func grayToSRGB(_ g: CGFloat) -> CGFloat { encode(pow(max(0, Double(g)), gamma)) }
}

public final class CGColor: Equatable, @unchecked Sendable {
    /// The components as given, in the color's own space.
    public let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    public let isGray: Bool
    /// What paints: the color in sRGB.
    public let sr: CGFloat, sg: CGFloat, sb: CGFloat
    public let spaceName: String

    /// Generic RGB, as on the Mac.
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        r = red; g = green; b = blue; a = alpha; isGray = false
        (sr, sg, sb) = GenericRGB.toSRGB(red, green, blue)
        spaceName = "kCGColorSpaceGenericRGB"
    }
    public init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        r = red; g = green; b = blue; a = alpha; isGray = false
        sr = red; sg = green; sb = blue
        spaceName = CGColorSpace.sRGB
    }
    /// Generic Gray, as on the Mac.
    public init(gray: CGFloat, alpha: CGFloat) {
        r = gray; g = gray; b = gray; a = alpha; isGray = true
        let v = GenericRGB.grayToSRGB(gray)
        sr = v; sg = v; sb = v
        spaceName = "kCGColorSpaceGenericGray"
    }
    /// Device RGB and sRGB pass through unchanged.
    public init?(colorSpace: CGColorSpace, components c: UnsafePointer<CGFloat>) {
        r = c[0]; g = c[1]; b = c[2]; a = c[3]; isGray = false
        sr = r; sg = g; sb = b
        spaceName = colorSpace.name
    }
    private init(raw r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat, gray: Bool, _ sr: CGFloat, _ sg: CGFloat, _ sb: CGFloat, _ space: String) {
        self.r = r; self.g = g; self.b = b; self.a = a; isGray = gray; self.sr = sr; self.sg = sg; self.sb = sb; spaceName = space
    }
    public static let clear = CGColor(gray: 0, alpha: 0)
    public static let black = CGColor(gray: 0, alpha: 1)
    public static let white = CGColor(gray: 1, alpha: 1)

    public var alpha: CGFloat { a }
    public var numberOfComponents: Int { isGray ? 2 : 4 }
    public var components: [CGFloat]? { isGray ? [r, a] : [r, g, b, a] }
    public var colorSpace: CGColorSpace? { CGColorSpace(internalName: spaceName) }
    public func copy(alpha: CGFloat) -> CGColor? { CGColor(raw: r, g, b, alpha, gray: isGray, sr, sg, sb, spaceName) }
    /// To sRGB, the one conversion the sources ask for.
    public func converted(to: CGColorSpace, intent: CGColorRenderingIntent, options: [String: Any]?) -> CGColor? {
        CGColor(srgbRed: sr, green: sg, blue: sb, alpha: a)
    }
    public static func == (x: CGColor, y: CGColor) -> Bool {
        x.r == y.r && x.g == y.g && x.b == y.b && x.a == y.a && x.spaceName == y.spaceName
    }
}

public enum CGColorRenderingIntent: Int32, Sendable {
    case defaultIntent, absoluteColorimetric, relativeColorimetric, perceptual, saturation
}

public enum CGLineCap: Int32, Sendable { case butt, round, square }
public enum CGLineJoin: Int32, Sendable { case miter, round, bevel }
public enum CGPathFillRule: Int, Sendable { case winding, evenOdd }
public enum CGPathDrawingMode: Int32, Sendable { case fill, eoFill, stroke, fillStroke, eoFillStroke }
public enum CGInterpolationQuality: Int32, Sendable { case `default`, none, low, medium, high }

public enum CGBlendMode: Int32, Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight,
         difference, exclusion, hue, saturation, color, luminosity, clear, copy, sourceIn, sourceOut,
         sourceAtop, destinationOver, destinationIn, destinationOut, destinationAtop, xor, plusDarker, plusLighter
}

public struct CGGradientDrawingOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let drawsBeforeStartLocation = CGGradientDrawingOptions(rawValue: 1)
    public static let drawsAfterEndLocation = CGGradientDrawingOptions(rawValue: 2)
}

public final class CGGradient: @unchecked Sendable {
    public let colors: [CGColor]
    public let locations: [CGFloat]

    public init?(colorsSpace: CGColorSpace?, colors: CFArray, locations: UnsafePointer<CGFloat>?) {
        let cs = colors.compactMap { $0 as? CGColor }
        guard !cs.isEmpty else { return nil }
        self.colors = cs
        if let locations {
            self.locations = (0..<cs.count).map { locations[$0] }
        } else {
            self.locations = cs.count < 2 ? [0] : (0..<cs.count).map { CGFloat($0) / CGFloat(cs.count - 1) }
        }
    }
    public init?(colorSpace: CGColorSpace, colorComponents: UnsafePointer<CGFloat>, locations: UnsafePointer<CGFloat>?, count: Int) {
        guard count > 0 else { return nil }
        colors = (0..<count).map { i in
            // Components in the gradient's own space: device RGB, unconverted.
            CGColor(srgbRed: colorComponents[i * 4], green: colorComponents[i * 4 + 1], blue: colorComponents[i * 4 + 2], alpha: colorComponents[i * 4 + 3])
        }
        if let locations {
            self.locations = (0..<count).map { locations[$0] }
        } else {
            self.locations = count < 2 ? [0] : (0..<count).map { CGFloat($0) / CGFloat(count - 1) }
        }
    }
}

// Core Foundation's bridged types, as far as the sources use them. With these aliases the Mac code's
// `x as CFArray`, `"key" as CFString` and `dict as CFDictionary` are ordinary upcasts and compile unchanged.
public typealias CFArray = [Any]
public typealias CFDictionary = [String: Any]
public typealias CFString = String
public typealias CFTypeRef = AnyObject
public typealias CFTimeInterval = Double
