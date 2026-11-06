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

public final class CGColor: Equatable, @unchecked Sendable {
    public let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    public let isGray: Bool

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        r = red; g = green; b = blue; a = alpha; isGray = false
    }
    public init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        r = red; g = green; b = blue; a = alpha; isGray = false
    }
    public init(gray: CGFloat, alpha: CGFloat) {
        r = gray; g = gray; b = gray; a = alpha; isGray = true
    }
    public init?(colorSpace: CGColorSpace, components: UnsafePointer<CGFloat>) {
        r = components[0]; g = components[1]; b = components[2]; a = components[3]; isGray = false
    }
    public static let clear = CGColor(gray: 0, alpha: 0)
    public static let black = CGColor(gray: 0, alpha: 1)
    public static let white = CGColor(gray: 1, alpha: 1)

    public var alpha: CGFloat { a }
    public var numberOfComponents: Int { isGray ? 2 : 4 }
    public var components: [CGFloat]? { isGray ? [r, a] : [r, g, b, a] }
    public var colorSpace: CGColorSpace? { isGray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB() }
    public func copy(alpha: CGFloat) -> CGColor? {
        isGray ? CGColor(gray: r, alpha: alpha) : CGColor(red: r, green: g, blue: b, alpha: alpha)
    }
    public func converted(to: CGColorSpace, intent: CGColorRenderingIntent, options: [String: Any]?) -> CGColor? { self }
    public static func == (x: CGColor, y: CGColor) -> Bool {
        x.r == y.r && x.g == y.g && x.b == y.b && x.a == y.a
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
            CGColor(red: colorComponents[i * 4], green: colorComponents[i * 4 + 1], blue: colorComponents[i * 4 + 2], alpha: colorComponents[i * 4 + 3])
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
