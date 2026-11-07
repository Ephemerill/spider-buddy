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
    init(family: String, weight: Int, italic: Bool = false, size: CGFloat) { self.family = family; weightCSS = weight; self.italic = italic; pointSize = size }
    public convenience init?(name: String, size: CGFloat) {
        let bold = name.contains("Bold"), medium = name.contains("Medium")
        let mono = name.hasPrefix("Menlo") || name.hasPrefix("Monaco") || name.hasPrefix("SFMono")
        self.init(family: mono ? NSFont.monoFamily : NSFont.systemFamily, weight: bold ? 700 : medium ? 500 : 400, size: size > 0 ? size : 13)
    }
    public static func systemFont(ofSize s: CGFloat) -> NSFont { NSFont(family: systemFamily, weight: 400, size: s > 0 ? s : 13) }
    public static func systemFont(ofSize s: CGFloat, weight w: Weight) -> NSFont { NSFont(family: systemFamily, weight: w.css, size: s > 0 ? s : 13) }
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
    private var metricsCache: (CGFloat, CGFloat)?
    var metrics: (ascent: CGFloat, descent: CGFloat) {
        if let m = metricsCache { return m }
        let m = CTTextMeasure("x", fontKey, pointSize)
        metricsCache = (m.ascent, m.descent)
        return (m.ascent, m.descent)
    }
    public var ascender: CGFloat { metrics.ascent }
    public var descender: CGFloat { -metrics.descent }
    public var leading: CGFloat { 0 }
    public var capHeight: CGFloat { pointSize * 0.7 }
    public var xHeight: CGFloat { pointSize * 0.5 }
    public var lineHeight: CGFloat { metrics.ascent + metrics.descent }
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
struct TextLine { var runs: [TextRun]; var width: CGFloat; var ascent: CGFloat; var descent: CGFloat }

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
            var a: CGFloat = 0, d: CGFloat = 0
            for r in cur { a = max(a, r.font.metrics.ascent); d = max(d, r.font.metrics.descent) }
            if cur.isEmpty, let f = runs.first?.font { a = f.metrics.ascent; d = f.metrics.descent }
            lines.append(TextLine(runs: cur, width: curW, ascent: a, descent: d))
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
        for (i, l) in lines.enumerated() { w = max(w, l.width); h += l.ascent + l.descent + (i > 0 ? spacing : 0) }
        return CGSize(width: w.rounded(.up), height: h.rounded(.up))
    }
    /// Draws lines inside `rect` (in the current context's coordinates), top first, keeping text upright in flipped views.
    static func draw(_ lines: [TextLine], in rect: CGRect, alignment: NSTextAlignment, spacing: CGFloat, ctx: CGContext, flipped: Bool) {
        var y = flipped ? rect.minY : rect.maxY
        for l in lines {
            var x = rect.minX
            switch alignment {
            case .right: x = rect.maxX - l.width
            case .center: x = rect.minX + (rect.width - l.width) / 2
            default: break
            }
            let base = flipped ? y + l.ascent : y - l.ascent
            for r in l.runs {
                let w = r.font.width(r.text)
                ctx.saveGState()
                ctx.translateBy(x: x, y: base)
                if flipped { ctx.scaleBy(x: 1, y: -1) }
                ctx.textPosition = .zero
                ctx.backend.drawText(r.text, font: r.font.fontKey, size: r.font.pointSize, color: r.color, at: CGPoint.zero.applying(ctx.ctm), state: ctx.state)
                if r.underline {
                    ctx.setFillColor(r.color)
                    ctx.fill(CGRect(x: 0, y: -2, width: w, height: 0.75))
                }
                ctx.restoreGState()
                x += w
            }
            let step = l.ascent + l.descent + spacing
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
    public func draw(at p: CGPoint) {
        guard let (c, f) = current else { return }
        let (r, st) = TextLayout.runs(self)
        let lines = TextLayout.lines(r, width: nil, mode: .byClipping)
        let z = TextLayout.size(lines, spacing: st?.lineSpacing ?? 0)
        TextLayout.draw(lines, in: CGRect(origin: p, size: z), alignment: .left, spacing: st?.lineSpacing ?? 0, ctx: c, flipped: f)
    }
    public func draw(in rect: CGRect) {
        guard let (c, f) = current else { return }
        let (r, st) = TextLayout.runs(self)
        let mode = st?.lineBreakMode ?? .byWordWrapping
        var lines = TextLayout.lines(r, width: rect.width, mode: mode)
        lines = lines.map { TextLayout.truncate($0, width: rect.width, mode: mode) }
        TextLayout.draw(lines, in: rect, alignment: st?.alignment ?? .left, spacing: st?.lineSpacing ?? 0, ctx: c, flipped: f)
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
