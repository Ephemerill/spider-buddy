// Fonts and text: NSFont, paragraph styles, and string drawing with wrapping and truncation, measured and drawn by Skia.
import Foundation
import QuartzCore

public final class NSFont: NSObject, @unchecked Sendable {
    public struct Weight: RawRepresentable, Hashable, Sendable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public init(_ v: CGFloat) { rawValue = v }
        public static let ultraLight = Weight(-0.8), thin = Weight(-0.6), light = Weight(-0.4), regular = Weight(0), medium = Weight(0.23), semibold = Weight(0.3), bold = Weight(0.4), heavy = Weight(0.56), black = Weight(0.62)
        var css: Int {
            switch rawValue {
            case ..<(-0.7): return 200
            case ..<(-0.5): return 250
            case ..<(-0.2): return 300
            case ..<(0.1): return 400
            case ..<(0.27): return 500
            case ..<(0.35): return 600
            case ..<(0.5): return 700
            case ..<(0.6): return 800
            default: return 900
            }
        }
    }
    public struct Key { public let rawValue: String }
    public enum TextStyle: Sendable { case body, callout, caption1, caption2, footnote, headline, subheadline, title1, title2, title3, largeTitle }
    /// The family standing in for SF Pro. See "Accepted differences" in the workflow.
    nonisolated(unsafe) public static var systemFamily = "Segoe UI"
    nonisolated(unsafe) public static var monoFamily = "Consolas"

    public let family: String
    public let weightCSS: Int
    public let italic: Bool
    public let pointSize: CGFloat
    public var fontName: String { family }
    public var familyName: String? { family }
    public var displayName: String? { family }
    var fontKey: String { "\(family)|\(weightCSS)|\(italic ? 1 : 0)" }
    init(family: String, weight: Int, italic: Bool = false, size: CGFloat) {
        _ = NSFont.installWidths
        self.family = family; weightCSS = weight; self.italic = italic; pointSize = size
    }
    public convenience init?(name: String, size: CGFloat) {
        let bold = name.contains("Bold"), medium = name.contains("Medium")
        let mono = name.hasPrefix("Menlo") || name.hasPrefix("Monaco") || name.hasPrefix("SFMono")
        self.init(family: mono ? NSFont.monoFamily : NSFont.systemFamily, weight: bold ? 700 : medium ? 500 : 400, size: size > 0 ? size : 13)
    }
    public static func systemFont(ofSize s: CGFloat) -> NSFont { NSFont(family: systemFamily, weight: 400, size: s > 0 ? s : 13) }
    public static func systemFont(ofSize s: CGFloat, weight w: Weight) -> NSFont { NSFont(family: systemFamily, weight: w.css, size: s > 0 ? s : 13) }
    public static func menuBarFont(ofSize s: CGFloat) -> NSFont { systemFont(ofSize: s > 0 ? s : 14) }
    /// The box any glyph of the font fits in.
    public var boundingRectForFont: CGRect { CGRect(x: 0, y: descender, width: pointSize, height: ascender - descender) }
    public static func boldSystemFont(ofSize s: CGFloat) -> NSFont { NSFont(family: systemFamily, weight: 700, size: s > 0 ? s : 13) }
    public static func monospacedSystemFont(ofSize s: CGFloat, weight w: Weight) -> NSFont { NSFont(family: monoFamily, weight: w.css, size: s) }
    public static func monospacedDigitSystemFont(ofSize s: CGFloat, weight w: Weight) -> NSFont { NSFont(family: systemFamily, weight: w.css, size: s) }
    public static func menuFont(ofSize s: CGFloat) -> NSFont { systemFont(ofSize: s) }
    public static func labelFont(ofSize s: CGFloat) -> NSFont { systemFont(ofSize: s) }
    public static func controlContentFont(ofSize s: CGFloat) -> NSFont { systemFont(ofSize: s) }
    public static func titleBarFont(ofSize s: CGFloat) -> NSFont { boldSystemFont(ofSize: s) }
    public static func preferredFont(forTextStyle t: TextStyle, options: [String: Any] = [:]) -> NSFont {
        switch t {
        case .largeTitle: return systemFont(ofSize: 26)
        case .title1: return systemFont(ofSize: 22)
        case .title2: return systemFont(ofSize: 17)
        case .title3: return systemFont(ofSize: 15)
        case .headline: return boldSystemFont(ofSize: 13)
        case .subheadline: return systemFont(ofSize: 11)
        case .callout: return systemFont(ofSize: 12)
        case .caption1: return systemFont(ofSize: 10)
        case .caption2: return systemFont(ofSize: 10)
        case .footnote: return systemFont(ofSize: 10)
        default: return systemFont(ofSize: 13)
        }
    }
    public static var systemFontSize: CGFloat { 13 }
    public static var smallSystemFontSize: CGFloat { 11 }
    public static var labelFontSize: CGFloat { 10 }
    public static func systemFontSize(for c: NSControl.ControlSize) -> CGFloat {
        switch c { case .mini: return 9; case .small: return 11; case .large: return 15; default: return 13 }
    }
    // The system font draws in Segoe UI, but lays out with SF Pro's metrics, so text takes the same room as on the Mac
    // and everything around it lands in the same place. Measured on the Mac (tools: see the work log, 2026-11-15):
    // ascender 0.96680 and descender 0.21094 of the size at every weight, no leading.
    var isSystem: Bool { family == NSFont.systemFamily }

    // Text widths. Segoe UI is narrower than SF Pro at text sizes and wider at title sizes, which moves every wrap
    // point. Measured over 400 of the app's own strings (tools/fontwidth), the ratio SF Pro / Segoe UI for each weight
    // at these sizes; the system font is drawn and measured stretched by it. SPIDER_FONT_RAW=1 turns it off.
    private static let widthSizes: [CGFloat] = [8, 9, 10, 11, 12, 13, 14, 15, 17, 20, 24, 30, 34, 40]
    private static let widthRatios: [Int32: [CGFloat]] = [
        400: [1.1149, 1.1010, 1.0866, 1.0744, 1.0624, 1.0496, 1.0396, 1.0295, 1.0085, 0.9848, 0.9656, 0.9651, 0.9610, 0.9569],
        500: [1.1052, 1.0918, 1.0783, 1.0664, 1.0545, 1.0425, 1.0321, 1.0222, 1.0021, 0.9804, 0.9644, 0.9646, 0.9608, 0.9569],
        600: [1.1233, 1.1099, 1.0964, 1.0846, 1.0727, 1.0606, 1.0503, 1.0404, 1.0203, 0.9994, 0.9853, 0.9862, 0.9823, 0.9784],
        700: [1.1071, 1.0937, 1.0805, 1.0689, 1.0578, 1.0460, 1.0364, 1.0268, 1.0073, 0.9882, 0.9773, 0.9788, 0.9750, 0.9713],
    ]
    static func widthRatio(weight: Int32, size: CGFloat) -> CGFloat {
        let key: Int32 = weight <= 450 ? 400 : weight <= 550 ? 500 : weight <= 650 ? 600 : 700
        guard let r = widthRatios[key] else { return 1 }
        let s = widthSizes
        if size <= s[0] { return r[0] }
        if size >= s[s.count - 1] { return r[r.count - 1] }
        var i = 0
        while s[i + 1] < size { i += 1 }
        let t = (size - s[i]) / (s[i + 1] - s[i])
        return r[i] + (r[i + 1] - r[i]) * t
    }
    private static let installWidths: Void = {
        guard ProcessInfo.processInfo.environment["SPIDER_FONT_RAW"] != "1" else { return }
        SkiaText.widthScale = { family, weight, size in family == NSFont.systemFamily ? NSFont.widthRatio(weight: weight, size: size) : 1 }
        SkiaText.inkOutset = NSFont.smoothingOutset
    }()
    /// macOS's text smoothing, as an outset in device pixels: light text on dark gains about 0.31 px a side, dark
    /// text about 0.1 (measured from glyph ink on the Mac against the outline's own area: "Spider" at 15 pt
    /// semibold, 206 square points of outline drawn as 253-266). L is the colour's brightness; its alpha doesn't
    /// matter (measured: white at 0.25 to 1 all dilate alike).
    static func smoothingOutset(_ c: CGColor) -> CGFloat {
        let l = 0.2126 * c.sr + 0.7152 * c.sg + 0.0722 * c.sb
        let t = max(0, min(1, (l - 0.30) / (0.85 - 0.30)))
        return 0.10 + 0.21 * t * t * (3 - 2 * t)
    }
    private var metricsCache: (CGFloat, CGFloat)?
    var metrics: (ascent: CGFloat, descent: CGFloat) {
        if let m = metricsCache { return m }
        if isSystem {
            metricsCache = (pointSize * 0.966797, pointSize * 0.210938)
            return metricsCache!
        }
        let m = CTTextMeasure("x", fontKey, pointSize)
        metricsCache = (m.ascent, m.descent)
        return (m.ascent, m.descent)
    }
    public var ascender: CGFloat { metrics.ascent }
    public var descender: CGFloat { -metrics.descent }
    public var leading: CGFloat { 0 }
    public var capHeight: CGFloat { pointSize * (isSystem ? 0.70459 : 0.7) }
    public var xHeight: CGFloat { pointSize * (isSystem ? 0.52637 : 0.5) }
    /// NSLayoutManager's default line height: the ascender and descender each rounded.
    public var lineHeight: CGFloat { isSystem ? metrics.ascent.rounded() + metrics.descent.rounded() : metrics.ascent + metrics.descent }
    /// The height of one line in a text field or label, as AppKit's typesetter rounds it (measured from NSTextField
    /// on the Mac, sizes 6 to 60 by halves).
    var labelLineHeight: CGFloat {
        guard isSystem else { return (metrics.ascent + metrics.descent).rounded(.up) }
        let i = Int((pointSize * 2).rounded()) - 12
        if i >= 0, i < NSFont.labelLines.count { return NSFont.labelLines[i] }
        return (pointSize * 1.18).rounded()
    }
    private static let labelLines: [CGFloat] = [8, 8, 9, 9, 10, 10, 11, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 18, 19, 19, 19, 20, 20, 21, 21, 22, 23, 24, 24, 25, 25, 26, 26, 27, 27, 28, 28, 29, 29, 30, 30, 32, 32, 33, 33, 34, 34, 35, 35, 35, 37, 37, 38, 38, 39, 39, 40, 40, 41, 41, 43, 43, 44, 44, 45, 45, 46, 46, 47, 48, 49, 49, 50, 50, 51, 51, 52, 52, 53, 54, 54, 55, 55, 56, 56, 57, 57, 58, 59, 60, 60, 61, 61, 62, 62, 63, 63, 64, 65, 66, 66, 67, 67, 68, 68, 69, 69, 71, 71]
    func width(_ s: String) -> CGFloat { CTTextMeasure(s, fontKey, pointSize).width }
}

public enum NSTextAlignment: Int, Sendable { case left, right, center, justified, natural }
public enum NSLineBreakMode: Int, Sendable { case byWordWrapping, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle }
public typealias NSWritingDirection = Int

public class NSParagraphStyle: NSObject, @unchecked Sendable {
    public var alignment = NSTextAlignment.natural
    public var lineBreakMode = NSLineBreakMode.byWordWrapping
    public var lineSpacing: CGFloat = 0
    public var paragraphSpacing: CGFloat = 0
    public var lineHeightMultiple: CGFloat = 0
    public var minimumLineHeight: CGFloat = 0
    public var maximumLineHeight: CGFloat = 0
    public var firstLineHeadIndent: CGFloat = 0
    public var headIndent: CGFloat = 0
    public var tailIndent: CGFloat = 0
    public static let `default` = NSParagraphStyle()
    public override init() { super.init() }
}
public final class NSMutableParagraphStyle: NSParagraphStyle, @unchecked Sendable {}

public struct NSUnderlineStyle: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }; public static let single = Self(rawValue: 1), thick = Self(rawValue: 2), double = Self(rawValue: 9) }

/// A run of text with one look.
struct TextRun { var text: String; var font: NSFont; var color: CGColor; var underline: Bool }
struct TextLine {
    var runs: [TextRun]; var width: CGFloat; var ascent: CGFloat; var descent: CGFloat
    /// The line's height as AppKit lays it out; the glyphs sit in the middle of any room beyond ascent and descent.
    var height: CGFloat = 0
    var lineHeight: CGFloat { max(height, ascent + descent) }
    var baseline: CGFloat { ascent + (lineHeight - ascent - descent) / 2 }
}

enum TextLayout {
    static func runs(_ s: NSAttributedString, defaultFont: NSFont = .systemFont(ofSize: 12), defaultColor: CGColor = .black) -> ([TextRun], NSParagraphStyle?) {
        var out: [TextRun] = []
        var para: NSParagraphStyle? = nil
        let full = NSRange(location: 0, length: s.length)
        var at = 0
        let ns = s.string as NSString
        while at < full.length {
            var r = NSRange(location: 0, length: 0)
            let a = s.attributes(at: at, effectiveRange: &r)
            let font = (a[.font] as? NSFont) ?? defaultFont
            let color = (a[.foregroundColor] as? NSColor)?.cgColor ?? defaultColor
            if para == nil { para = a[.paragraphStyle] as? NSParagraphStyle }
            let end = max(r.location + r.length, at + 1)
            out.append(TextRun(text: ns.substring(with: NSRange(location: at, length: end - at)), font: font, color: color, underline: a[.underlineStyle] != nil))
            at = end
        }
        return (out, para)
    }
    /// Breaks runs into lines. `width` nil means no wrapping (still splits at newlines).
    static func lines(_ runs: [TextRun], width: CGFloat?, mode: NSLineBreakMode) -> [TextLine] {
        var lines: [TextLine] = []
        var cur: [TextRun] = []
        var curW: CGFloat = 0
        func flush() {
            var a: CGFloat = 0, d: CGFloat = 0, h: CGFloat = 0
            for r in cur { a = max(a, r.font.metrics.ascent); d = max(d, r.font.metrics.descent); h = max(h, r.font.labelLineHeight) }
            if cur.isEmpty, let f = runs.first?.font { a = f.metrics.ascent; d = f.metrics.descent; h = f.labelLineHeight }
            lines.append(TextLine(runs: cur, width: curW, ascent: a, descent: d, height: h))
            cur = []; curW = 0
        }
        func add(_ t: String, _ r: TextRun) {
            guard !t.isEmpty else { return }
            let w = r.font.width(t)
            if var last = cur.last, last.font === r.font, last.color == r.color {
                last.text += t
                cur[cur.count - 1] = last
            } else {
                var n = r; n.text = t; cur.append(n)
            }
            curW += w
        }
        for r in runs {
            let paras = r.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (pi, p) in paras.enumerated() {
                if pi > 0 { flush() }
                if let width, mode == .byWordWrapping || mode == .byCharWrapping {
                    var word = ""
                    func place() {
                        guard !word.isEmpty else { return }
                        let w = r.font.width(word.trimmingCharacters(in: .whitespaces))
                        if curW + w > width + 0.5, curW > 0 { flush() }
                        if r.font.width(word.trimmingCharacters(in: .whitespaces)) > width {
                            // A word wider than the line breaks by characters.
                            var piece = ""
                            for ch in word {
                                if r.font.width(piece + String(ch)) + curW > width, !piece.isEmpty || curW > 0 { add(piece, r); flush(); piece = "" }
                                piece.append(ch)
                            }
                            add(piece, r)
                        } else {
                            add(curW == 0 ? String(word.drop(while: { $0 == " " })) : word, r)
                        }
                        word = ""
                    }
                    for ch in p {
                        if ch == " ", !word.isEmpty, word.last != " " { word.append(ch); place(); continue }
                        word.append(ch)
                    }
                    place()
                } else {
                    add(p, r)
                }
            }
        }
        if !cur.isEmpty || lines.isEmpty { flush() }
        return lines
    }
    /// AppKit's standard line-break strategy for text fields: no word left alone on a paragraph's last line. The line
    /// before gives up its last word to it (measured: a wrapping label breaks "...or let a / cricket loose." where
    /// the text would fit "cricket" on the first line; NSString drawing doesn't do this). For one-paragraph text, and only
    /// two lines of it: from three lines on AppKit leaves the orphan (measured, 2 to 6 lines).
    static func pushOut(_ lines: [TextLine]) -> [TextLine] {
        guard lines.count == 2 else { return lines }
        var prev = lines[lines.count - 2], last = lines[lines.count - 1]
        let lastText = last.runs.map(\.text).joined().trimmingCharacters(in: .whitespaces)
        guard !lastText.isEmpty, !lastText.contains(" "), var r = prev.runs.last else { return lines }
        // The previous line's last word: after its last space, ignoring the space that ends the line.
        let body = r.text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        guard let space = body.lastIndex(of: " ") else { return lines }
        let moved = String(r.text[r.text.index(after: space)...])
        r.text = String(r.text[...space])
        let w = r.font.width(moved)
        prev.runs[prev.runs.count - 1] = r
        prev.width -= w
        var m = r; m.text = moved
        if let first = last.runs.first, first.font === m.font, first.color == m.color { last.runs[0].text = moved + first.text } else { last.runs.insert(m, at: 0) }
        last.width += w
        var out = lines
        out[out.count - 2] = prev; out[out.count - 1] = last
        return out
    }
    static func truncate(_ line: TextLine, width: CGFloat, mode: NSLineBreakMode) -> TextLine {
        guard line.width > width, mode != .byClipping, mode != .byWordWrapping, mode != .byCharWrapping, let r = line.runs.first else { return line }
        let text = line.runs.map(\.text).joined()
        let f = r.font
        var chars = Array(text)
        var out = ""
        switch mode {
        case .byTruncatingHead:
            while !chars.isEmpty, f.width("…" + String(chars)) > width { chars.removeFirst() }
            out = "…" + String(chars)
        case .byTruncatingMiddle:
            while chars.count > 1, f.width(String(chars.prefix(chars.count / 2)) + "…" + String(chars.suffix(chars.count / 2))) > width { chars.remove(at: chars.count / 2) }
            out = String(chars.prefix(chars.count / 2)) + "…" + String(chars.suffix(chars.count / 2))
        default:
            while !chars.isEmpty, f.width(String(chars) + "…") > width { chars.removeLast() }
            out = String(chars).trimmingCharacters(in: .whitespaces) + "…"
        }
        var n = line
        n.runs = [TextRun(text: out, font: f, color: r.color, underline: r.underline)]
        n.width = f.width(out)
        return n
    }
    static func size(_ lines: [TextLine], spacing: CGFloat) -> CGSize {
        var w: CGFloat = 0, h: CGFloat = 0
        for (i, l) in lines.enumerated() { w = max(w, l.width); h += l.lineHeight + (i > 0 ? spacing : 0) }
        return CGSize(width: w.rounded(.up), height: h.rounded(.up))
    }
    /// macOS draws text heavier than its colour's alpha says: a translucent label colour comes out as if drawn twice,
    /// 1 - (1 - a)^2 (measured on the Mac at 13 and 15 points: label 0.847 -> 0.977, secondary 0.549 -> 0.797 in dark,
    /// 0.498 -> 0.75 in light). Opaque colours are unchanged.
    static func macInk(_ c: CGColor) -> CGColor {
        let a = c.a
        guard a > 0, a < 1 else { return c }
        return c.copy(alpha: 1 - (1 - a) * (1 - a)) ?? c
    }
    /// Draws lines inside `rect` (in the current context's coordinates), top first, keeping text upright in flipped views.
    /// `boost`: draw translucent colours as macOS draws label text (`macInk`). AppKit does that for text fields and for
    /// stock buttons given a tint, not for segmented controls, pop-ups or button subclasses that draw themselves (measured).
    /// `dilate`: how much of macOS's text-smoothing dilation the glyphs get (measured as ink against the Mac): all for
    /// labels, drawn strings and stock buttons; half for segment labels; a third for text composited plus-lighter (a
    /// vibrant layer is drawn without an opaque backdrop); none for button subclasses that draw themselves.
    static func draw(_ lines: [TextLine], in rect: CGRect, alignment: NSTextAlignment, spacing: CGFloat, ctx: CGContext, flipped: Bool, boost: Bool = true, dilate: CGFloat = 1) {

        var y = flipped ? rect.minY : rect.maxY
        for l in lines {
            var x = rect.minX
            switch alignment {
            case .right: x = rect.maxX - l.width
            case .center: x = rect.minX + (rect.width - l.width) / 2
            default: break
            }
            let base = flipped ? y + l.baseline : y - l.baseline
            for r in l.runs {
                let w = r.font.width(r.text)
                ctx.saveGState()
                if dilate != 1 { ctx.setTextDilation(ctx.state.textDilation * dilate) }
                ctx.translateBy(x: x, y: base)
                if flipped { ctx.scaleBy(x: 1, y: -1) }
                ctx.textPosition = .zero
                ctx.backend.drawText(r.text, font: r.font.fontKey, size: r.font.pointSize, color: boost ? TextLayout.macInk(r.color) : r.color, at: CGPoint.zero.applying(ctx.ctm), state: ctx.state)
                if r.underline {
                    ctx.setFillColor(r.color)
                    ctx.fill(CGRect(x: 0, y: -2, width: w, height: 0.75))
                }
                ctx.restoreGState()
                x += w
            }
            let step = l.lineHeight + spacing
            y += flipped ? step : -step
        }
    }
}

extension NSAttributedString {
    public struct DrawingOptions: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let usesLineFragmentOrigin = Self(rawValue: 1), usesFontLeading = Self(rawValue: 2), truncatesLastVisibleLine = Self(rawValue: 32) }
    private var current: (CGContext, Bool)? {
        guard let g = NSGraphicsContext.current else { return nil }
        return (g.cgContext, g.isFlipped)
    }
    public func size() -> CGSize {
        let (r, p) = TextLayout.runs(self)
        return TextLayout.size(TextLayout.lines(r, width: nil, mode: .byClipping), spacing: p?.lineSpacing ?? 0)
    }
    public func boundingRect(with s: CGSize, options: DrawingOptions = [], context: Any? = nil) -> CGRect {
        let (r, p) = TextLayout.runs(self)
        let z = TextLayout.size(TextLayout.lines(r, width: s.width > 0 && s.width < 1e6 ? s.width : nil, mode: p?.lineBreakMode ?? .byWordWrapping), spacing: p?.lineSpacing ?? 0)
        return CGRect(origin: .zero, size: z)
    }
    /// (Drawn plain: a string drawn by a view of its own gets no label boost on the Mac, measured.)
    public func draw(at p: CGPoint) {
        guard let (c, f) = current else { return }
        let (r, st) = TextLayout.runs(self)
        let lines = TextLayout.lines(r, width: nil, mode: .byClipping)
        let z = TextLayout.size(lines, spacing: st?.lineSpacing ?? 0)
        TextLayout.draw(lines, in: CGRect(origin: p, size: z), alignment: .left, spacing: st?.lineSpacing ?? 0, ctx: c, flipped: f, boost: false)
    }
    public func draw(in rect: CGRect) {
        guard let (c, f) = current else { return }
        let (r, st) = TextLayout.runs(self)
        let mode = st?.lineBreakMode ?? .byWordWrapping
        var lines = TextLayout.lines(r, width: rect.width, mode: mode)
        lines = lines.map { TextLayout.truncate($0, width: rect.width, mode: mode) }
        TextLayout.draw(lines, in: rect, alignment: st?.alignment ?? .left, spacing: st?.lineSpacing ?? 0, ctx: c, flipped: f, boost: false)
    }
    public func draw(with rect: CGRect, options: DrawingOptions = [], context: Any? = nil) { draw(in: rect) }
}
extension NSString {
    public func size(withAttributes a: [NSAttributedString.Key: Any]? = nil) -> CGSize { NSAttributedString(string: self as String, attributes: a).size() }
    public func draw(at p: CGPoint, withAttributes a: [NSAttributedString.Key: Any]? = nil) { NSAttributedString(string: self as String, attributes: a).draw(at: p) }
    public func draw(in r: CGRect, withAttributes a: [NSAttributedString.Key: Any]? = nil) { NSAttributedString(string: self as String, attributes: a).draw(in: r) }
    public func boundingRect(with s: CGSize, options: NSAttributedString.DrawingOptions = [], attributes a: [NSAttributedString.Key: Any]? = nil, context: Any? = nil) -> CGRect {
        NSAttributedString(string: self as String, attributes: a).boundingRect(with: s, options: options)
    }
}
extension String {
    public func size(withAttributes a: [NSAttributedString.Key: Any]? = nil) -> CGSize { NSAttributedString(string: self, attributes: a).size() }
    public func draw(at p: CGPoint, withAttributes a: [NSAttributedString.Key: Any]? = nil) { NSAttributedString(string: self, attributes: a).draw(at: p) }
    public func draw(in r: CGRect, withAttributes a: [NSAttributedString.Key: Any]? = nil) { NSAttributedString(string: self, attributes: a).draw(in: r) }
    public func boundingRect(with s: CGSize, options: NSAttributedString.DrawingOptions = [], attributes a: [NSAttributedString.Key: Any]? = nil, context: Any? = nil) -> CGRect {
        NSAttributedString(string: self, attributes: a).boundingRect(with: s, options: options)
    }
}
