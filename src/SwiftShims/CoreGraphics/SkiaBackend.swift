// CoreGraphics stand-in for Windows: real drawing, through Skia's C API.
//
// libSkiaSharp.dll is loaded at run time and bound by name, so tools that never draw do not need it. Core Graphics is
// y-up with row 0 of the bitmap at the top, Skia is y-down, so device points are flipped here and nowhere else.
#if os(Windows)
import Foundation
import WinSDK

private typealias P = OpaquePointer?

private struct SkiaImageInfo { var colorspace: UnsafeRawPointer? = nil; var width: Int32; var height: Int32; var colorType: Int32; var alphaType: Int32 }
private struct SkiaMatrix { var m: (Float, Float, Float, Float, Float, Float, Float, Float, Float) }   // scaleX skewX transX skewY scaleY transY p0 p1 p2
private struct SkiaColor4f { var r: Float, g: Float, b: Float, a: Float }
private struct SkiaPoint { var x: Float, y: Float }
private struct SkiaRect { var left: Float, top: Float, right: Float, bottom: Float }
private struct SkiaM44 { var v: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) }
private struct SkiaSampling { var maxAniso: Int32 = 0; var useCubic: UInt8 = 0; var b: Float = 0; var c: Float = 0; var filter: Int32 = 1; var mipmap: Int32 = 0 }

private enum Sk {
    static let lib: HMODULE? = "libSkiaSharp.dll".withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
    static var available: Bool { lib != nil }

    static func f<T>(_ name: String, _ t: T.Type = T.self) -> T {
        guard let lib, let p = GetProcAddress(lib, name) else { fatalError("libSkiaSharp is missing \(name)") }
        return unsafeBitCast(p, to: T.self)
    }

    static let canvasNew: @convention(c) (UnsafeRawPointer, UnsafeMutableRawPointer, Int, P) -> P = f("sk_canvas_new_from_raster")
    static let canvasDestroy: @convention(c) (P) -> Void = f("sk_canvas_destroy")
    static let canvasSave: @convention(c) (P) -> Int32 = f("sk_canvas_save")
    static let canvasRestore: @convention(c) (P) -> Void = f("sk_canvas_restore")
    static let canvasSaveLayer: @convention(c) (P, UnsafeRawPointer?, P) -> Int32 = f("sk_canvas_save_layer")
    static let canvasClip: @convention(c) (P, P, Int32, Bool) -> Void = f("sk_canvas_clip_path_with_operation")
    static let canvasDrawPath: @convention(c) (P, P, P) -> Void = f("sk_canvas_draw_path")
    static let canvasDrawPaint: @convention(c) (P, P) -> Void = f("sk_canvas_draw_paint")
    static let canvasDrawRect: @convention(c) (P, UnsafeRawPointer, P) -> Void = f("sk_canvas_draw_rect")
    static let canvasConcat: @convention(c) (P, UnsafeRawPointer) -> Void = f("sk_canvas_concat")
    static let canvasDrawImageRect: @convention(c) (P, P, UnsafeRawPointer?, UnsafeRawPointer, UnsafeRawPointer, P) -> Void = f("sk_canvas_draw_image_rect")
    static let canvasDrawText: @convention(c) (P, UnsafeRawPointer, Int, Int32, Float, Float, P, P) -> Void = f("sk_canvas_draw_simple_text")

    static let paintNew: @convention(c) () -> P = f("sk_paint_new")
    static let paintDelete: @convention(c) (P) -> Void = f("sk_paint_delete")
    static let paintAA: @convention(c) (P, Bool) -> Void = f("sk_paint_set_antialias")
    static let paintColor4f: @convention(c) (P, UnsafeRawPointer, P) -> Void = f("sk_paint_set_color4f")
    static let paintStyle: @convention(c) (P, Int32) -> Void = f("sk_paint_set_style")
    static let paintStrokeWidth: @convention(c) (P, Float) -> Void = f("sk_paint_set_stroke_width")
    static let paintCap: @convention(c) (P, Int32) -> Void = f("sk_paint_set_stroke_cap")
    static let paintJoin: @convention(c) (P, Int32) -> Void = f("sk_paint_set_stroke_join")
    static let paintMiter: @convention(c) (P, Float) -> Void = f("sk_paint_set_stroke_miter")
    static let paintBlend: @convention(c) (P, Int32) -> Void = f("sk_paint_set_blendmode")
    static let paintShader: @convention(c) (P, P) -> Void = f("sk_paint_set_shader")
    static let paintImageFilter: @convention(c) (P, P) -> Void = f("sk_paint_set_imagefilter")
    static let paintPathEffect: @convention(c) (P, P) -> Void = f("sk_paint_set_path_effect")

    static let builderNew: @convention(c) () -> P = f("sk_pathbuilder_new")
    static let builderDelete: @convention(c) (P) -> Void = f("sk_pathbuilder_delete")
    static let builderMove: @convention(c) (P, Float, Float) -> Void = f("sk_pathbuilder_move_to")
    static let builderLine: @convention(c) (P, Float, Float) -> Void = f("sk_pathbuilder_line_to")
    static let builderQuad: @convention(c) (P, Float, Float, Float, Float) -> Void = f("sk_pathbuilder_quad_to")
    static let builderCubic: @convention(c) (P, Float, Float, Float, Float, Float, Float) -> Void = f("sk_pathbuilder_cubic_to")
    static let builderClose: @convention(c) (P) -> Void = f("sk_pathbuilder_close")
    static let builderFill: @convention(c) (P, Int32) -> Void = f("sk_pathbuilder_set_filltype")
    static let builderDetach: @convention(c) (P) -> P = f("sk_pathbuilder_detach_path")
    static let pathDelete: @convention(c) (P) -> Void = f("sk_path_delete")

    static let linear: @convention(c) (UnsafeRawPointer, UnsafeRawPointer, P, UnsafeRawPointer?, Int32, Int32, UnsafeRawPointer?) -> P = f("sk_shader_new_linear_gradient_color4f")
    static let conical: @convention(c) (UnsafeRawPointer, Float, UnsafeRawPointer, Float, UnsafeRawPointer, P, UnsafeRawPointer?, Int32, Int32, UnsafeRawPointer?) -> P = f("sk_shader_new_two_point_conical_gradient_color4f")
    static let shaderUnref: @convention(c) (P) -> Void = f("sk_shader_unref")
    static let dropShadow: @convention(c) (Float, Float, Float, Float, UInt32, P, UnsafeRawPointer?) -> P = f("sk_imagefilter_new_drop_shadow")
    static let filterUnref: @convention(c) (P) -> Void = f("sk_imagefilter_unref")
    static let dash: @convention(c) (UnsafePointer<Float>, Int32, Float) -> P = f("sk_path_effect_create_dash")
    static let effectUnref: @convention(c) (P) -> Void = f("sk_path_effect_unref")
    static let imageCopy: @convention(c) (UnsafeRawPointer, UnsafeRawPointer, Int) -> P = f("sk_image_new_raster_copy")
    static let imageUnref: @convention(c) (P) -> Void = f("sk_image_unref")

    static let fontMgrNew: @convention(c) () -> P = f("sk_fontmgr_create_default")
    static let fontMatch: @convention(c) (P, UnsafePointer<CChar>, P) -> P = f("sk_fontmgr_match_family_style")
    static let fontStyleNew: @convention(c) (Int32, Int32, Int32) -> P = f("sk_fontstyle_new")
    static let fontNew: @convention(c) (P, Float, Float, Float) -> P = f("sk_font_new_with_values")
    static let fontDelete: @convention(c) (P) -> Void = f("sk_font_delete")
    static let fontEdging: @convention(c) (P, Int32) -> Void = f("sk_font_set_edging")
    static let fontSubpixel: @convention(c) (P, Bool) -> Void = f("sk_font_set_subpixel")
    static let fontMeasure: @convention(c) (P, UnsafeRawPointer, Int, Int32, UnsafeMutableRawPointer?, P) -> Float = f("sk_font_measure_text")
    static let fontMetrics: @convention(c) (P, UnsafeMutableRawPointer) -> Float = f("sk_font_get_metrics")
}

private func flt(_ v: CGFloat) -> Float { Float(v) }

/// Font lookup: Mac face names become the closest Windows face. Skia's faces are cached.
public enum SkiaText {
    nonisolated(unsafe) private static var faces: [String: P] = [:]
    private static let lock = NSLock()
    nonisolated(unsafe) private static let mgr: P = Sk.fontMgrNew()

    private static func windowsFace(_ name: String) -> (String, Int32) {
        // The name tag and bubble use Helvetica Neue Medium. Arial has Helvetica's proportions.
        if name.hasPrefix("HelveticaNeue") || name.hasPrefix("Helvetica") { return ("Arial", name.contains("Bold") ? 700 : name.contains("Medium") ? 500 : 400) }
        if name.isEmpty { return ("Segoe UI", 400) }
        return (name, 400)
    }
    fileprivate static func font(_ name: String, _ size: CGFloat) -> P {
        lock.lock(); defer { lock.unlock() }
        let face: P
        if let known = faces[name] {
            face = known
        } else {
            let (family, weight) = windowsFace(name)
            let style = Sk.fontStyleNew(weight, 5, 0)
            face = family.withCString { Sk.fontMatch(mgr, $0, style) }
            faces[name] = face
        }
        let f = Sk.fontNew(face, flt(size), 1, 0)
        Sk.fontEdging(f, 1)
        Sk.fontSubpixel(f, true)
        return f
    }
    public static func measure(_ text: String, font name: String, size: CGFloat) -> (width: CGFloat, ascent: CGFloat, descent: CGFloat) {
        let f = font(name, size)
        defer { Sk.fontDelete(f) }
        var width: Float = 0
        text.withCString { width = Sk.fontMeasure(f, $0, strlen($0), 0, nil, nil) }
        var m = [Float](repeating: 0, count: 16)
        _ = m.withUnsafeMutableBytes { Sk.fontMetrics(f, $0.baseAddress!) }
        // Fields: flags, top, ascent, descent, ...
        return (CGFloat(width), CGFloat(-m[2]), CGFloat(m[3]))
    }
    public static var available: Bool { Sk.available }
}

public final class SkiaBackend: CGBackend {
    private let canvas: P
    private let h: CGFloat
    /// Depth of saves, so a backend can be retired tidily.
    public init?(pixels: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int, bitmapInfo: UInt32) {
        guard Sk.available else { return nil }
        // byteOrder32Little with premultipliedFirst is BGRA in memory; the plain premultipliedLast is RGBA.
        let bgra = bitmapInfo & (2 << 12) != 0
        var info = SkiaImageInfo(width: Int32(width), height: Int32(height), colorType: bgra ? 6 : 4, alphaType: 2)
        canvas = withUnsafeBytes(of: &info) { Sk.canvasNew($0.baseAddress!, pixels, bytesPerRow, nil) }
        h = CGFloat(height)
        if canvas == nil { return nil }
    }
    deinit { Sk.canvasDestroy(canvas) }

    public func save() { _ = Sk.canvasSave(canvas) }
    public func restore() { Sk.canvasRestore(canvas) }

    private func skPath(_ path: CGPath, rule: CGPathFillRule, flipOnly: Bool = true) -> P {
        let b = Sk.builderNew()
        defer { Sk.builderDelete(b) }
        Sk.builderFill(b, rule == .winding ? 0 : 1)
        let H = h
        for e in path.elements {
            switch e {
            case let .move(p): Sk.builderMove(b, flt(p.x), flt(H - p.y))
            case let .line(p): Sk.builderLine(b, flt(p.x), flt(H - p.y))
            case let .quad(c, p): Sk.builderQuad(b, flt(c.x), flt(H - c.y), flt(p.x), flt(H - p.y))
            case let .cubic(c1, c2, p): Sk.builderCubic(b, flt(c1.x), flt(H - c1.y), flt(c2.x), flt(H - c2.y), flt(p.x), flt(H - p.y))
            case .close: Sk.builderClose(b)
            }
        }
        return Sk.builderDetach(b)
    }

    /// The same path with the flip and transform taken back out: for strokes under a non-uniform transform,
    /// which have to be stroked in user space to get their shape right.
    private func skUserPath(_ path: CGPath, inverse t: CGAffineTransform) -> P {
        let b = Sk.builderNew()
        defer { Sk.builderDelete(b) }
        for e in path.elements {
            switch e {
            case let .move(p): let q = p.applying(t); Sk.builderMove(b, flt(q.x), flt(q.y))
            case let .line(p): let q = p.applying(t); Sk.builderLine(b, flt(q.x), flt(q.y))
            case let .quad(c, p): let d = c.applying(t), q = p.applying(t); Sk.builderQuad(b, flt(d.x), flt(d.y), flt(q.x), flt(q.y))
            case let .cubic(c1, c2, p):
                let a = c1.applying(t), d = c2.applying(t), q = p.applying(t)
                Sk.builderCubic(b, flt(a.x), flt(a.y), flt(d.x), flt(d.y), flt(q.x), flt(q.y))
            case .close: Sk.builderClose(b)
            }
        }
        return Sk.builderDetach(b)
    }

    private func blend(_ m: CGBlendMode) -> Int32 {
        switch m {
        case .normal: return 3
        case .multiply: return 24
        case .screen: return 14
        case .overlay: return 15
        case .darken: return 16
        case .lighten: return 17
        case .colorDodge: return 18
        case .colorBurn: return 19
        case .softLight: return 21
        case .hardLight: return 20
        case .difference: return 22
        case .exclusion: return 23
        case .hue: return 25
        case .saturation: return 26
        case .color: return 27
        case .luminosity: return 28
        case .clear: return 0
        case .copy: return 1
        case .sourceIn: return 5
        case .sourceOut: return 7
        case .sourceAtop: return 9
        case .destinationOver: return 4
        case .destinationIn: return 6
        case .destinationOut: return 8
        case .destinationAtop: return 10
        case .xor: return 11
        case .plusLighter: return 12
        case .plusDarker: return 3
        }
    }

    private func paint(_ c: CGColor, _ s: CGState, style: Int32) -> P {
        let p = Sk.paintNew()
        Sk.paintAA(p, s.antialias)
        var col = SkiaColor4f(r: flt(c.sr), g: flt(c.sg), b: flt(c.sb), a: flt(c.a * s.alpha))
        withUnsafeBytes(of: &col) { Sk.paintColor4f(p, $0.baseAddress!, nil) }
        Sk.paintStyle(p, style)
        Sk.paintBlend(p, blend(s.blend))
        applyShadow(p, s)
        return p
    }

    private func applyShadow(_ p: P, _ s: CGState) {
        guard let sc = s.shadowColor, sc.a > 0 else { return }
        let a = UInt32(max(0, min(255, (sc.a * s.alpha * 255).rounded())))
        let r = UInt32(max(0, min(255, (sc.sr * 255).rounded()))), g = UInt32(max(0, min(255, (sc.sg * 255).rounded()))), b = UInt32(max(0, min(255, (sc.sb * 255).rounded())))
        let color = (a << 24) | (r << 16) | (g << 8) | b
        // Core Graphics' blur is twice the Gaussian's sigma. Its offset is in device space, y up.
        let f = Sk.dropShadow(flt(s.shadowOffset.width), flt(-s.shadowOffset.height), flt(s.shadowBlur / 2), flt(s.shadowBlur / 2), color, nil, nil)
        Sk.paintImageFilter(p, f)
        Sk.filterUnref(f)
    }

    public func clip(_ path: CGPath, rule: CGPathFillRule, antialias: Bool) {
        let p = skPath(path, rule: rule)
        Sk.canvasClip(canvas, p, 1, antialias)
        Sk.pathDelete(p)
    }

    public func fill(_ path: CGPath, rule: CGPathFillRule, state s: CGState) {
        let p = skPath(path, rule: rule)
        let pt = paint(s.fill, s, style: 0)
        Sk.canvasDrawPath(canvas, p, pt)
        Sk.paintDelete(pt)
        Sk.pathDelete(p)
    }

    public func stroke(_ path: CGPath, state s: CGState) {
        let t = s.ctm
        let e1 = t.a * t.a + t.b * t.b, e2 = t.c * t.c + t.d * t.d, dot = t.a * t.c + t.b * t.d
        let uniform = abs(e1 - e2) < 1e-6 * max(e1, 1e-9) && abs(dot) < 1e-6 * max(e1, 1e-9)
        let pt = paint(s.stroke, s, style: 1)
        defer { Sk.paintDelete(pt) }
        Sk.paintCap(pt, s.cap.rawValue)
        Sk.paintJoin(pt, s.join.rawValue)
        Sk.paintMiter(pt, flt(s.miter))
        if uniform {
            let k = CGFloat(e1).squareRoot()
            Sk.paintStrokeWidth(pt, flt(s.lineWidth * k))
            setDash(pt, s, k)
            let p = skPath(path, rule: .winding)
            Sk.canvasDrawPath(canvas, p, pt)
            Sk.pathDelete(p)
        } else {
            // Stroke in user space, then transform: y flip, then the current transform.
            let p = skUserPath(path, inverse: t.inverted())
            Sk.paintStrokeWidth(pt, flt(s.lineWidth))
            setDash(pt, s, 1)
            _ = Sk.canvasSave(canvas)
            concat(t)
            Sk.canvasDrawPath(canvas, p, pt)
            Sk.canvasRestore(canvas)
            Sk.pathDelete(p)
        }
    }

    private func setDash(_ p: P, _ s: CGState, _ k: CGFloat) {
        guard !s.dash.isEmpty else { return }
        var v = s.dash.map { flt($0 * k) }
        if v.count % 2 == 1 { v += v }
        let e = v.withUnsafeBufferPointer { Sk.dash($0.baseAddress!, Int32($0.count), flt(s.dashPhase * k)) }
        Sk.paintPathEffect(p, e)
        Sk.effectUnref(e)
    }

    /// Applies `t` (y-up user to y-up device) to the canvas, with the flip around it.
    private func concat(_ t: CGAffineTransform) {
        // y-down device = flip(y-up device).
        // Laid out as SkiaSharp's sk_matrix44: columns of the matrix first.
        var m = SkiaM44(v: (flt(t.a), flt(-t.b), 0, 0,
                            flt(t.c), flt(-t.d), 0, 0,
                            0, 0, 1, 0,
                            flt(t.tx), flt(h - t.ty), 0, 1))
        withUnsafeBytes(of: &m) { Sk.canvasConcat(canvas, $0.baseAddress!) }
    }

    private func localMatrix(_ t: CGAffineTransform) -> SkiaMatrix {
        SkiaMatrix(m: (flt(t.a), flt(t.c), flt(t.tx), flt(-t.b), flt(-t.d), flt(h - t.ty), 0, 0, 1))
    }

    private func drawGradientShader(_ shader: P, state s: CGState) {
        let p = Sk.paintNew()
        Sk.paintAA(p, s.antialias)
        var white = SkiaColor4f(r: 1, g: 1, b: 1, a: flt(s.alpha))
        withUnsafeBytes(of: &white) { Sk.paintColor4f(p, $0.baseAddress!, nil) }
        Sk.paintShader(p, shader)
        Sk.paintBlend(p, blend(s.blend))
        Sk.canvasDrawPaint(canvas, p)
        Sk.paintDelete(p)
        Sk.shaderUnref(shader)
    }

    private func tile(_ o: CGGradientDrawingOptions) -> Int32 { o.isEmpty ? 3 : 0 }   // Decal past the ends unless asked.

    public func linearGradient(_ g: CGGradient, start: CGPoint, end: CGPoint, options: CGGradientDrawingOptions, state s: CGState) {
        var cols = g.colors.map { SkiaColor4f(r: flt($0.sr), g: flt($0.sg), b: flt($0.sb), a: flt($0.a)) }
        var pos = g.locations.map { flt($0) }
        var pts = [SkiaPoint(x: flt(start.x), y: flt(start.y)), SkiaPoint(x: flt(end.x), y: flt(end.y))]
        var lm = localMatrix(s.ctm)
        let shader = pts.withUnsafeMutableBytes { pp in cols.withUnsafeMutableBytes { cc in pos.withUnsafeMutableBytes { oo in
            withUnsafeBytes(of: &lm) { mm in
                Sk.linear(pp.baseAddress!, cc.baseAddress!, nil, oo.baseAddress!, Int32(g.colors.count), tile(options), mm.baseAddress!)
            }
        } } }
        drawGradientShader(shader, state: s)
    }

    public func radialGradient(_ g: CGGradient, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat, options: CGGradientDrawingOptions, state s: CGState) {
        var cols = g.colors.map { SkiaColor4f(r: flt($0.sr), g: flt($0.sg), b: flt($0.sb), a: flt($0.a)) }
        var pos = g.locations.map { flt($0) }
        var a = SkiaPoint(x: flt(startCenter.x), y: flt(startCenter.y)), b = SkiaPoint(x: flt(endCenter.x), y: flt(endCenter.y))
        var lm = localMatrix(s.ctm)
        let shader = withUnsafeBytes(of: &a) { aa in withUnsafeBytes(of: &b) { bb in cols.withUnsafeMutableBytes { cc in pos.withUnsafeMutableBytes { oo in
            withUnsafeBytes(of: &lm) { mm in
                Sk.conical(aa.baseAddress!, flt(startRadius), bb.baseAddress!, flt(endRadius), cc.baseAddress!, nil, oo.baseAddress!, Int32(g.colors.count), tile(options), mm.baseAddress!)
            }
        } } } }
        drawGradientShader(shader, state: s)
    }

    public func drawImage(_ image: CGImage, in r: CGRect, state s: CGState) {
        var info = SkiaImageInfo(width: Int32(image.width), height: Int32(image.height), colorType: 4, alphaType: 2)
        let im = image.pixels.withUnsafeBytes { px in withUnsafeBytes(of: &info) { Sk.imageCopy($0.baseAddress!, px.baseAddress!, image.bytesPerRow) } }
        guard im != nil else { return }
        let p = Sk.paintNew()
        Sk.paintAA(p, s.antialias)
        var col = SkiaColor4f(r: 0, g: 0, b: 0, a: flt(s.alpha))
        withUnsafeBytes(of: &col) { Sk.paintColor4f(p, $0.baseAddress!, nil) }
        Sk.paintBlend(p, blend(s.blend))
        applyShadow(p, s)
        _ = Sk.canvasSave(canvas)
        // The image's top row is its highest y: undo the flip for it.
        concat(s.ctm.translatedBy(x: r.minX, y: r.maxY).scaledBy(x: 1, y: -1))
        var dst = SkiaRect(left: 0, top: 0, right: flt(r.width), bottom: flt(r.height))
        var src = SkiaRect(left: 0, top: 0, right: Float(image.width), bottom: Float(image.height))
        // In this space y runs down the image, and our concat's flip already accounts for it.
        var sampling = SkiaSampling(filter: s.interpolation == .none ? 0 : 1)
        // (The concat above leaves y going the same way as the image's rows.)
        withUnsafeBytes(of: &dst) { d in withUnsafeBytes(of: &src) { c in withUnsafeBytes(of: &sampling) { o in
            Sk.canvasDrawImageRect(canvas, im, c.baseAddress!, d.baseAddress!, o.baseAddress!, p)
        } } }
        Sk.canvasRestore(canvas)
        Sk.paintDelete(p)
        Sk.imageUnref(im)
    }

    public func beginLayer(state s: CGState) {
        let p = Sk.paintNew()
        var col = SkiaColor4f(r: 0, g: 0, b: 0, a: flt(s.alpha))
        withUnsafeBytes(of: &col) { Sk.paintColor4f(p, $0.baseAddress!, nil) }
        Sk.paintBlend(p, blend(s.blend))
        applyShadow(p, s)
        _ = Sk.canvasSaveLayer(canvas, nil, p)
        Sk.paintDelete(p)
    }
    public func endLayer() { Sk.canvasRestore(canvas) }

    public func clear(_ r: CGRect, state s: CGState) {
        let p = Sk.paintNew()
        Sk.paintBlend(p, 0)
        var d = SkiaRect(left: flt(r.minX), top: flt(h - r.maxY), right: flt(r.maxX), bottom: flt(h - r.minY))
        withUnsafeBytes(of: &d) { Sk.canvasDrawRect(canvas, $0.baseAddress!, p) }
        Sk.paintDelete(p)
    }

    public func drawText(_ text: String, font: String, size: CGFloat, color: CGColor, at position: CGPoint, state s: CGState) {
        let f = SkiaText.font(font, size)
        defer { Sk.fontDelete(f) }
        let pt = paint(color, s, style: 0)
        defer { Sk.paintDelete(pt) }
        // Text is laid out in user space (the font size is in points), then taken through the transform.
        _ = Sk.canvasSave(canvas)
        let at = position.applying(s.ctm.inverted())
        concat(s.ctm.translatedBy(x: at.x, y: at.y).scaledBy(x: 1, y: -1))
        text.withCString { Sk.canvasDrawText(canvas, $0, strlen($0), 0, 0, 0, f, pt) }
        Sk.canvasRestore(canvas)
    }

    public func flush() {}
}
#endif
