// The controls, drawn in Skia to look like macOS's. Sizes and colors follow AppKit's metrics; compare with the Mac's screenshots.
import Foundation
import QuartzCore

extension NSControl {
    public enum ControlSize: UInt, Sendable { case regular, small, mini, large
        var height: CGFloat { switch self { case .regular: return 22; case .small: return 19; case .mini: return 16; case .large: return 28 } }
        var fontSize: CGFloat { switch self { case .regular: return 13; case .small: return 11; case .mini: return 9; case .large: return 13 } }
    }
    public enum StateValue: Int, Sendable { case off = 0, on = 1, mixed = -1 }
    public typealias TextAlignment = NSTextAlignment
}
public typealias NSButtonStateValue = NSControl.StateValue

open class NSCell: NSObject {
    public override init() { super.init() }
    public init(textCell s: String) { title = s; super.init() }
    public var title = ""
    open var isEnabled = true
    public var font: NSFont?
    public var alignment = NSTextAlignment.natural
    public var wraps = false
    public var isScrollable = false
    public var truncatesLastVisibleLine = false
    public var lineBreakMode = NSLineBreakMode.byClipping
    public var usesSingleLineMode = false
    public var controlSize = NSControl.ControlSize.regular
    public var backgroundStyle = 0
    public var focusRingType = NSFocusRingType.default
    public var sendsActionOnEndEditing = false
    public var isBordered = false
    public var isBezeled = false
    public var placeholderString: String?
}
open class NSActionCell: NSCell {}
open class NSTextFieldCell: NSActionCell {
    public var drawsBackground = false
    public var backgroundColor: NSColor?
    public var textColor: NSColor?
}
open class NSButtonCell: NSActionCell {
    public var imageDimsWhenDisabled = true
    public var highlightsBy = 0
    public var showsStateBy = 0
    public var imageScaling = NSImageScaling.scaleProportionallyDown
    public var hasDestructiveAction = false
}
open class NSSliderCell: NSActionCell {}

open class NSControl: NSView {
    open var target: AnyObject?
    open var action: Selector?
    open var isEnabled = true { didSet { needsDisplay = true } }
    open var tagStore = -1
    open override var tag: Int { get { tagStore } set { tagStore = newValue } }
    open var font: NSFont? { didSet { fontChanged() } }
    open var alignment = NSTextAlignment.natural { didSet { needsDisplay = true } }
    open var controlSize = ControlSize.regular { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    open var stringValue: String { get { valueString } set { valueString = newValue; valueChanged() } }
    private var valueString = ""
    open var attributedStringValue: NSAttributedString { get { attributedStore ?? NSAttributedString(string: valueString) } set { attributedStore = newValue; valueString = newValue.string; valueChanged() } }
    var attributedStore: NSAttributedString?
    open var doubleValue: Double { get { numberStore } set { numberStore = newValue; valueChanged() } }
    private var numberStore = 0.0
    open var integerValue: Int { get { Int(doubleValue) } set { doubleValue = Double(newValue) } }
    open var floatValue: Float { get { Float(doubleValue) } set { doubleValue = Double(newValue) } }
    open var cell: NSCell? = NSCell()
    open var isContinuous = false
    open var lineBreakMode = NSLineBreakMode.byClipping { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    open var usesSingleLineMode = false
    open var allowsExpansionToolTips = false
    open var refusesFirstResponder = false
    open var formatter: Formatter?
    open var isHighlighted = false { didSet { needsDisplay = true } }
    func fontChanged() { invalidateIntrinsicContentSize(); needsDisplay = true }
    func valueChanged() { invalidateIntrinsicContentSize(); needsDisplay = true }
    @discardableResult open func sendAction(_ a: Selector?, to t: Any?) -> Bool { a?.send(to: (t as AnyObject?), from: self) ?? false }
    func fire() { _ = sendAction(action, to: target) }
    open func sizeToFit() {
        let s = intrinsicContentSize
        if s.width >= 0 { frame.size.width = s.width }
        if s.height >= 0 { frame.size.height = s.height }
    }
    open func abortEditing() -> Bool { false }
    open func validateEditing() {}
    public func takeStringValueFrom(_ s: Any?) {}
    var effectiveFont: NSFont { font ?? .systemFont(ofSize: controlSize.fontSize) }
    var dark: Bool { effectiveAppearance.isDark }
    var ctx: CGContext? { NSGraphicsContext.current?.cgContext }
    func drawString(_ s: String, in r: CGRect, color: NSColor, alignment a: NSTextAlignment, font f: NSFont, mode: NSLineBreakMode = .byTruncatingTail) {
        guard let g = NSGraphicsContext.current else { return }
        let run = [TextRun(text: s, font: f, color: color.cgColor, underline: false)]
        var lines = TextLayout.lines(run, width: nil, mode: .byClipping)
        lines = lines.map { TextLayout.truncate($0, width: r.width, mode: mode) }
        let z = TextLayout.size(lines, spacing: 0)
        let box = CGRect(x: r.minX, y: r.midY - z.height / 2, width: r.width, height: z.height)
        TextLayout.draw(lines, in: box, alignment: a == .natural ? .left : a, spacing: 0, ctx: g.cgContext, flipped: g.isFlipped)
    }
    func withAppearance(_ f: () -> Void) { effectiveAppearance.performAsCurrentDrawingAppearance(f) }
}

// MARK: Text field

public protocol NSControlTextEditingDelegate: AnyObject {}
public protocol NSTextFieldDelegate: AnyObject {
    func controlTextDidChange(_ n: Notification)
    func controlTextDidBeginEditing(_ n: Notification)
    func controlTextDidEndEditing(_ n: Notification)
    func control(_ c: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool
}
extension NSTextFieldDelegate {
    public func controlTextDidChange(_ n: Notification) {}
    public func controlTextDidBeginEditing(_ n: Notification) {}
    public func controlTextDidEndEditing(_ n: Notification) {}
    public func control(_ c: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool { false }
}
public enum NSTextFieldBezelStyle: UInt, Sendable { case squareBezel, roundedBezel }

open class NSTextField: NSControl, NSTextInputClient {
    public static let textDidChangeNotification = Notification.Name("NSTextDidChangeNotification")
    open var isEditable = true { didSet { needsDisplay = true } }
    open var isSelectable = true
    open var isBordered = true { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    open var isBezeled = true { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    open var bezelStyle = NSTextFieldBezelStyle.squareBezel
    open var drawsBackground = true { didSet { needsDisplay = true } }
    open var backgroundColor: NSColor? { didSet { needsDisplay = true } }
    open var textColor: NSColor? { didSet { needsDisplay = true } }
    open var placeholderString: String? { didSet { needsDisplay = true } }
    open var placeholderAttributedString: NSAttributedString?
    open var maximumNumberOfLines = 0 { didSet { invalidateIntrinsicContentSize() } }
    open var preferredMaxLayoutWidth: CGFloat = 0 { didSet { invalidateIntrinsicContentSize() } }
    open var allowsEditingTextAttributes = false
    public weak var delegate: NSTextFieldDelegate?
    private var caret = 0
    private var selectionStart: Int? = nil
    private var editing = false
    private var lastMeasuredWidth: CGFloat = -1
    private var wrappedTextCell = false

    public override init(frame r: CGRect) { super.init(frame: r); setContentHuggingPriority(NSLayoutPriority(251), for: .horizontal); setContentHuggingPriority(NSLayoutPriority(251), for: .vertical) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public convenience init(labelWithString s: String) {
        self.init(frame: .zero)
        isEditable = false; isSelectable = false; isBordered = false; isBezeled = false; drawsBackground = false
        stringValue = s
        lineBreakMode = .byClipping
    }
    public convenience init(wrappingLabelWithString s: String) {
        self.init(labelWithString: s)
        lineBreakMode = .byWordWrapping
        isSelectable = true
        wrappedTextCell = true
    }
    public convenience init(string s: String) { self.init(frame: .zero); stringValue = s }
    public convenience init(labelWithAttributedString s: NSAttributedString) { self.init(labelWithString: s.string); attributedStringValue = s }
    public static func wrappingLabel(_ s: String) -> NSTextField { NSTextField(wrappingLabelWithString: s) }

    open override var acceptsFirstResponder: Bool { isEditable && isEnabled }
    var wraps: Bool { (lineBreakMode == .byWordWrapping || lineBreakMode == .byCharWrapping) && maximumNumberOfLines != 1 }
    var padX: CGFloat { isBezeled || isBordered ? 4 : 2 }
    private func textRuns() -> ([TextRun], NSParagraphStyle?) {
        let color = (textColor ?? NSColor.labelColor)
        var out: ([TextRun], NSParagraphStyle?) = ([], nil)
        withAppearance {
            if let a = attributedStore { out = TextLayout.runs(a, defaultFont: effectiveFont, defaultColor: color.cgColor) } else {
                out = ([TextRun(text: stringValue, font: effectiveFont, color: color.cgColor, underline: false)], nil)
            }
        }
        return out
    }
    private func layoutLines(width: CGFloat?) -> [TextLine] {
        let (r, _) = textRuns()
        guard !r.isEmpty else { return [TextLine(runs: [], width: 0, ascent: effectiveFont.metrics.ascent, descent: effectiveFont.metrics.descent)] }
        if wraps, let width {
            var l = TextLayout.lines(r, width: width, mode: lineBreakMode)
            if maximumNumberOfLines > 0, l.count > maximumNumberOfLines { l = Array(l.prefix(maximumNumberOfLines)) }
            return l
        }
        return TextLayout.lines(r, width: nil, mode: .byClipping)
    }
    open override var intrinsicContentSize: CGSize {
        let wrapW: CGFloat? = wraps ? (preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth - padX * 2 : (lastMeasuredWidth > 0 ? lastMeasuredWidth - padX * 2 : nil)) : nil
        let z = TextLayout.size(layoutLines(width: wrapW), spacing: 0)
        let vPad: CGFloat = isBezeled || isBordered ? 6 : 0
        // AppKit gives wrapping labels no intrinsic width of their own beyond the one they were measured at.
        return CGSize(width: wraps && lastMeasuredWidth > 0 && preferredMaxLayoutWidth == 0 ? NSViewNoIntrinsicMetric : z.width + padX * 2, height: z.height + vPad)
    }
    override func widthChangedIntrinsic() -> Bool {
        guard wraps, preferredMaxLayoutWidth == 0, abs(frame.width - lastMeasuredWidth) > 0.5, frame.width > 0 else { return false }
        lastMeasuredWidth = frame.width
        return true
    }
    override var firstBaselineFromTop: CGFloat { effectiveFont.metrics.ascent + ((isBezeled || isBordered) ? 3 : 0) }
    override var lastBaselineFromBottom: CGFloat { effectiveFont.metrics.descent + ((isBezeled || isBordered) ? 3 : 0) }

    open override func draw(_ d: CGRect) {
        guard let c = ctx, let g = NSGraphicsContext.current else { return }
        withAppearance {
            let b = bounds
            if isBezeled || isBordered {
                let r = b.insetBy(dx: 0.5, dy: 0.5)
                c.addPath(CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil))
                c.setFillColor(drawsBackground ? (backgroundColor ?? (dark ? NSColor(white: 1, alpha: 0.05) : .white)).cgColor : NSColor.clear.cgColor)
                c.setStrokeColor((editing ? NSColor.controlAccentColor : NSColor(white: dark ? 1 : 0, alpha: 0.18)).cgColor)
                c.setLineWidth(editing ? 2 : 1)
                c.drawPath(using: .fillStroke)
            } else if drawsBackground, let bg = backgroundColor {
                c.setFillColor(bg.cgColor)
                c.fill(b)
            }
            let box = b.insetBy(dx: padX, dy: isBezeled || isBordered ? 3 : 0)
            if stringValue.isEmpty, !editing || isEditable {
                if let p = placeholderString, !editing {
                    let lines = TextLayout.lines([TextRun(text: p, font: effectiveFont, color: NSColor.placeholderTextColor.cgColor, underline: false)], width: nil, mode: .byClipping)
                    TextLayout.draw(lines, in: box, alignment: alignment == .natural ? .left : alignment, spacing: 0, ctx: c, flipped: g.isFlipped)
                }
            } else {
                var lines = layoutLines(width: box.width)
                if !wraps { lines = lines.map { TextLayout.truncate($0, width: box.width, mode: lineBreakMode) } }
                else if let last = lines.last, maximumNumberOfLines > 0, TextLayout.lines(textRuns().0, width: box.width, mode: lineBreakMode).count > maximumNumberOfLines {
                    lines[lines.count - 1] = TextLayout.truncate(last, width: box.width - 1, mode: .byTruncatingTail)
                }
                let align = (textRuns().1?.alignment ?? alignment)
                TextLayout.draw(lines, in: box, alignment: align == .natural ? .left : align, spacing: 0, ctx: c, flipped: g.isFlipped)
            }
            if editing {
                let f = effectiveFont
                let before = String(stringValue.prefix(caret))
                let x = box.minX + f.width(before)
                c.setFillColor(NSColor.textColor.cgColor)
                c.fill(CGRect(x: x, y: b.midY - f.pointSize * 0.6, width: 1, height: f.pointSize * 1.2))
            }
        }
    }

    // Editing
    open override func becomeFirstResponder() -> Bool {
        guard isEditable else { return false }
        editing = true
        caret = stringValue.count
        needsDisplay = true
        delegate?.controlTextDidBeginEditing(Notification(name: Notification.Name("NSControlTextDidBeginEditingNotification"), object: self))
        return true
    }
    open override func resignFirstResponder() -> Bool {
        if editing {
            editing = false
            needsDisplay = true
            delegate?.controlTextDidEndEditing(Notification(name: Notification.Name("NSControlTextDidEndEditingNotification"), object: self))
        }
        return true
    }
    public func currentEditor() -> NSText? { editing ? NSText(frame: .zero) : nil }
    public func selectText(_ s: Any?) { _ = window?.makeFirstResponder(self) }
    open func insertText(_ s: String) {
        guard editing else { return }
        var ch = Array(stringValue)
        ch.insert(contentsOf: Array(s), at: min(caret, ch.count))
        caret += s.count
        setEdited(String(ch))
    }
    private func setEdited(_ s: String) {
        stringValue = s
        NotificationCenter.default.post(name: NSTextField.textDidChangeNotification, object: self)
        delegate?.controlTextDidChange(Notification(name: Notification.Name("NSControlTextDidChangeNotification"), object: self))
    }
    open override func mouseDown(with e: NSEvent) {
        guard isEditable, isEnabled else { super.mouseDown(with: e); return }
        _ = window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        let x = p.x - padX
        var i = 0
        while i < stringValue.count, effectiveFont.width(String(stringValue.prefix(i + 1))) < x { i += 1 }
        caret = i
        needsDisplay = true
    }
    open override func keyDown(with e: NSEvent) {
        guard editing else { super.keyDown(with: e); return }
        var ch = Array(stringValue)
        switch e.keyCode {
        case 51: if caret > 0 { ch.remove(at: caret - 1); caret -= 1; setEdited(String(ch)) }
        case 117: if caret < ch.count { ch.remove(at: caret); setEdited(String(ch)) }
        case 123: caret = max(0, caret - 1); needsDisplay = true
        case 124: caret = min(ch.count, caret + 1); needsDisplay = true
        case 36:
            let tv = NSTextView(frame: .zero)
            if delegate?.control(self, textView: tv, doCommandBy: Selector("insertNewline:")) != true { fire(); _ = window?.makeFirstResponder(nil) }
        case 53:
            let tv = NSTextView(frame: .zero)
            if delegate?.control(self, textView: tv, doCommandBy: Selector("cancelOperation:")) != true { _ = window?.makeFirstResponder(nil) }
        default: break
        }
    }
}
public final class NSSecureTextField: NSTextField {}

public final class NSSearchField: NSTextField {
    public var sendsSearchStringImmediately = true
    public var sendsWholeSearchString = false
    public var recentSearches: [String] = []
    public var maximumRecents = 0
    public override init(frame r: CGRect) { super.init(frame: r); placeholderString = "Search" }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    override var padX: CGFloat { 20 }
    public override func draw(_ d: CGRect) {
        super.draw(d)
        guard let c = ctx else { return }
        withAppearance { c.setStrokeColor(NSColor.secondaryLabelColor.cgColor); c.setLineWidth(1.2); c.strokeEllipse(in: CGRect(x: 6, y: bounds.midY - 3, width: 7, height: 7)) }
    }
}

// MARK: Text view

public protocol NSTextDelegate: AnyObject {}
public protocol NSTextViewDelegate: AnyObject {
    func textDidChange(_ n: Notification)
    func textDidEndEditing(_ n: Notification)
    func textDidBeginEditing(_ n: Notification)
    func textView(_ t: NSTextView, doCommandBy s: Selector) -> Bool
}
extension NSTextViewDelegate {
    public func textDidChange(_ n: Notification) {}
    public func textDidEndEditing(_ n: Notification) {}
    public func textDidBeginEditing(_ n: Notification) {}
    public func textView(_ t: NSTextView, doCommandBy s: Selector) -> Bool { false }
}
open class NSText: NSView, NSTextInputClient {
    public static let didChangeNotification = Notification.Name("NSTextDidChangeNotification")
    public static let didEndEditingNotification = Notification.Name("NSTextDidEndEditingNotification")
    open var string = "" { didSet { needsDisplay = true } }
    open var font: NSFont? { didSet { needsDisplay = true } }
    open var textColor: NSColor? { didSet { needsDisplay = true } }
    open var backgroundColor: NSColor = .textBackgroundColor
    open var drawsBackground = true
    open var isEditable = true
    open var isSelectable = true
    open var isRichText = false
    open var alignment = NSTextAlignment.natural
    open var isVerticallyResizable = true
    open var isHorizontallyResizable = false
    open var minSize = CGSize.zero
    open var maxSize = CGSize(width: 1e7, height: 1e7)
    open override var acceptsFirstResponder: Bool { isEditable }
    open func insertText(_ s: String) { string += s; changed() }
    open func changed() {}
    public func selectAll(_ s: Any?) {}
    public func copy(_ s: Any?) { NSPasteboard.general.setString(string, forType: .string) }
    public func paste(_ s: Any?) { if let t = NSPasteboard.general.string(forType: .string) { insertText(t) } }
    public func cut(_ s: Any?) {}
    public func undo(_ s: Any?) {}
    public func redo(_ s: Any?) {}
}
public final class NSTextContainer: NSObject { public var widthTracksTextView = true; public var containerSize = CGSize(width: 1e7, height: 1e7); public var lineFragmentPadding: CGFloat = 5 }
open class NSTextView: NSText {
    public weak var delegate: NSTextViewDelegate?
    public var textContainerInset = CGSize.zero
    public var textContainer: NSTextContainer? = NSTextContainer()
    public var isAutomaticQuoteSubstitutionEnabled = false
    public var isAutomaticDashSubstitutionEnabled = false
    public var isAutomaticTextReplacementEnabled = false
    public var isAutomaticSpellingCorrectionEnabled = false
    public var isContinuousSpellCheckingEnabled = false
    public var allowsUndo = false
    public var usesFontPanel = false
    public var insertionPointColor = NSColor.textColor
    public var selectedRange = NSRange(location: 0, length: 0)
    public func scrollRangeToVisible(_ r: NSRange) {}
    public func setSelectedRange(_ r: NSRange) { selectedRange = r }
    public static func scrollableTextView() -> NSScrollView { let s = NSScrollView(frame: .zero); s.documentView = NSTextView(frame: .zero); return s }
    open override func changed() {
        delegate?.textDidChange(Notification(name: NSText.didChangeNotification, object: self))
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: self)
    }
    open override func draw(_ d: CGRect) {
        guard let g = NSGraphicsContext.current else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if drawsBackground { g.cgContext.setFillColor(backgroundColor.cgColor); g.cgContext.fill(bounds) }
            let f = font ?? .systemFont(ofSize: 13)
            let box = bounds.insetBy(dx: textContainerInset.width + 5, dy: textContainerInset.height)
            let lines = TextLayout.lines([TextRun(text: string, font: f, color: (textColor ?? .textColor).cgColor, underline: false)], width: box.width, mode: .byWordWrapping)
            TextLayout.draw(lines, in: box, alignment: alignment == .natural ? .left : alignment, spacing: 0, ctx: g.cgContext, flipped: g.isFlipped)
        }
    }
    open override var isFlipped: Bool { true }
    open override func keyDown(with e: NSEvent) {
        if e.keyCode == 51, !string.isEmpty { string.removeLast(); changed(); return }
        if e.keyCode == 36 {
            if delegate?.textView(self, doCommandBy: Selector("insertNewline:")) == true { return }
            string += "\n"; changed(); return
        }
        if e.keyCode == 53 { _ = delegate?.textView(self, doCommandBy: Selector("cancelOperation:")); return }
    }
    open override func mouseDown(with e: NSEvent) { _ = window?.makeFirstResponder(self) }
    open override func becomeFirstResponder() -> Bool { delegate?.textDidBeginEditing(Notification(name: Notification.Name("NSTextDidBeginEditingNotification"), object: self)); return true }
    open override func resignFirstResponder() -> Bool { delegate?.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: self)); return true }
}

// MARK: Button

public enum NSBezelStyle: UInt, Sendable { case automatic = 0, rounded = 1, regularSquare = 2, disclosure = 5, shadowlessSquare = 6, circular = 7, texturedSquare = 8, helpButton = 9, smallSquare = 10, texturedRounded = 11, roundRect = 12, recessed = 13, roundedDisclosure = 14, inline = 15 }
public enum NSButtonType: UInt, Sendable { case momentaryLight, pushOnPushOff, toggle, `switch`, radio, momentaryChange, onOff, momentaryPushIn, accelerator, multiLevelAccelerator }
public enum NSCellImagePosition: UInt, Sendable { case noImage, imageOnly, imageLeft, imageRight, imageBelow, imageAbove, imageOverlaps, imageLeading, imageTrailing }

open class NSButton: NSControl {
    public typealias BezelStyle = NSBezelStyle
    public typealias ButtonType = NSButtonType
    open var title = "" { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    open var attributedTitle: NSAttributedString = NSAttributedString(string: "") { didSet { title = attributedTitle.string } }
    open var alternateTitle = ""
    open var image: NSImage? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    open var alternateImage: NSImage?
    open var imagePosition = NSCellImagePosition.imageLeft { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    open var imageScaling = NSImageScaling.scaleProportionallyDown
    open var imageHugsTitle = false
    open var isBordered = true { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    open var bezelStyle = NSBezelStyle.rounded { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    open var bezelColor: NSColor?
    open var contentTintColor: NSColor? { didSet { needsDisplay = true } }
    open var keyEquivalent = "" { didSet { needsDisplay = true } }
    open var keyEquivalentModifierMask = NSEvent.ModifierFlags()
    open var state = StateValue.off { didSet { needsDisplay = true } }
    open var allowsMixedState = false
    open var showsBorderOnlyWhileMouseInside = false
    open var hasDestructiveAction = false
    open var sound: NSSound?
    open var isSpringLoaded = false
    open var type = NSButtonType.momentaryPushIn
    public func setButtonType(_ t: NSButtonType) { type = t; invalidateIntrinsicContentSize(); needsDisplay = true }
    public override init(frame r: CGRect) { super.init(frame: r); cell = NSButtonCell() }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public convenience init(title t: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero); title = t; self.target = target; self.action = action
    }
    public convenience init(checkboxWithTitle t: String, target: AnyObject?, action: Selector?) {
        self.init(title: t, target: target, action: action); setButtonType(.switch)
    }
    public convenience init(radioButtonWithTitle t: String, target: AnyObject?, action: Selector?) {
        self.init(title: t, target: target, action: action); setButtonType(.radio)
    }
    public convenience init(image i: NSImage, target: AnyObject?, action: Selector?) {
        self.init(title: "", target: target, action: action); image = i; imagePosition = .imageOnly
    }
    public convenience init(title t: String, image i: NSImage, target: AnyObject?, action: Selector?) {
        self.init(title: t, target: target, action: action); image = i; imagePosition = .imageLeading
    }
    open override func draw(_ d: CGRect) { withAppearance { drawButton() } }
    var isCheck: Bool { type == .switch || type == .radio }
    open override var intrinsicContentSize: CGSize {
        let f = effectiveFont
        let t = title.isEmpty ? 0 : f.width(title)
        if isCheck { return CGSize(width: t + 20, height: max(16, controlSize.height - 4)) }
        let iw = image?.size.width ?? 0, ih = image?.size.height ?? 0
        if !isBordered {
            if imagePosition == .imageAbove || imagePosition == .imageBelow { return CGSize(width: max(iw, t), height: ih + f.lineHeight + 2) }
            return CGSize(width: t + iw + (t > 0 && iw > 0 ? 4 : 0), height: max(ih, f.lineHeight))
        }
        let w = t + iw + (t > 0 && iw > 0 ? 4 : 0) + (bezelStyle == .rounded ? 22 : 12)
        return CGSize(width: max(w, bezelStyle == .rounded && t > 0 ? 48 : 0), height: bezelStyle == .inline ? 16 : controlSize.height)
    }
    func drawButton() {
        guard let c = ctx else { return }
        let b = bounds
        if isCheck {
            let on = state == .on
            let box = CGRect(x: 1, y: b.midY - 7, width: 14, height: 14)
            if type == .radio {
                c.setFillColor((on ? NSColor.controlAccentColor : NSColor(white: dark ? 1 : 0, alpha: dark ? 0.12 : 0.06)).cgColor)
                c.fillEllipse(in: box)
                if on { c.setFillColor(NSColor.white.cgColor); c.fillEllipse(in: box.insetBy(dx: 4.5, dy: 4.5)) }
            } else {
                c.addPath(CGPath(roundedRect: box, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
                c.setFillColor((on ? NSColor.controlAccentColor : NSColor(white: dark ? 1 : 1, alpha: dark ? 0.12 : 1)).cgColor)
                c.fillPath()
                if !on {
                    c.addPath(CGPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 3, cornerHeight: 3, transform: nil))
                    c.setStrokeColor(NSColor(white: dark ? 1 : 0, alpha: 0.25).cgColor); c.setLineWidth(1); c.strokePath()
                }
                if on {
                    c.setStrokeColor(NSColor.white.cgColor); c.setLineWidth(1.8); c.setLineCap(.round); c.setLineJoin(.round)
                    let flip = isFlipped
                    func Y(_ v: CGFloat) -> CGFloat { flip ? box.maxY - v : box.minY + v }
                    c.move(to: CGPoint(x: box.minX + 3.2, y: Y(7))); c.addLine(to: CGPoint(x: box.minX + 6, y: Y(4))); c.addLine(to: CGPoint(x: box.minX + 10.8, y: Y(10))); c.strokePath()
                }
            }
            drawString(title, in: CGRect(x: 20, y: b.minY, width: b.width - 20, height: b.height), color: isEnabled ? .labelColor : .disabledControlTextColor, alignment: .left, font: effectiveFont)
            return
        }
        let on = state == .on && (type == .pushOnPushOff || type == .toggle || type == .onOff)
        let isDefault = keyEquivalent == "\r"
        if isBordered {
            let r = b.insetBy(dx: bezelStyle == .rounded ? 1 : 0.5, dy: bezelStyle == .rounded ? 1 : 0.5)
            let radius: CGFloat = bezelStyle == .inline || bezelStyle == .recessed ? r.height / 2 : bezelStyle == .circular ? r.height / 2 : 5.5
            let fill: NSColor
            if isDefault { fill = isHighlighted ? NSColor(srgbRed: 0, green: 0.38, blue: 0.85, alpha: 1) : .controlAccentColor }
            else if on { fill = NSColor(white: dark ? 1 : 0, alpha: 0.2) }
            else if isHighlighted { fill = NSColor(white: dark ? 1 : 0, alpha: dark ? 0.32 : 0.12) }
            else if bezelStyle == .recessed || bezelStyle == .inline { fill = NSColor(white: dark ? 1 : 0, alpha: 0.08) }
            else { fill = dark ? NSColor(white: 1, alpha: 0.2) : .white }
            let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if !dark, !isDefault, bezelStyle == .rounded {
                c.saveGState()
                c.setShadow(offset: CGSize(width: 0, height: -0.5 * NSScreen.primaryScale), blur: 1 * NSScreen.primaryScale, color: NSColor(white: 0, alpha: 0.25).cgColor)
                c.addPath(path); c.setFillColor(fill.cgColor); c.fillPath()
                c.restoreGState()
            } else {
                c.addPath(path); c.setFillColor(fill.cgColor); c.fillPath()
            }
        } else if isHighlighted {
            c.setAlpha(0.6)
        }
        let tint = contentTintColor ?? (isDefault && isBordered ? .white : isEnabled ? .labelColor : .disabledControlTextColor)
        let f = effectiveFont
        let t = title
        let showTitle = imagePosition != .imageOnly && !t.isEmpty
        let tw = showTitle ? f.width(t) : 0
        if let img = (state == .on ? alternateImage : nil) ?? image, imagePosition != .noImage {
            var iz = img.size
            if imageScaling == .scaleProportionallyUpOrDown, imagePosition == .imageOnly {
                let k = min(b.width / max(iz.width, 1), b.height / max(iz.height, 1))
                iz = CGSize(width: iz.width * k, height: iz.height * k)
            } else if iz.height > b.height {
                let k = b.height / iz.height
                iz = CGSize(width: iz.width * k, height: iz.height * k)
            }
            let flip = isFlipped
            func place(_ r: CGRect) {
                c.saveGState()
                if flip { c.translateBy(x: r.minX, y: r.maxY); c.scaleBy(x: 1, y: -1) } else { c.translateBy(x: r.minX, y: r.minY) }
                c.scaleBy(x: iz.width / max(img.size.width, 1), y: iz.height / max(img.size.height, 1))
                if !isEnabled { c.setAlpha(0.4) }
                img.render(in: c, tint: tint)
                c.restoreGState()
            }
            switch imagePosition {
            case .imageAbove:
                let total = iz.height + f.lineHeight + 2
                let top = b.midY + total / 2
                let imgY = flip ? b.midY - total / 2 : top - iz.height
                place(CGRect(x: b.midX - iz.width / 2, y: imgY, width: iz.width, height: iz.height))
                let ty = flip ? b.midY + total / 2 - f.lineHeight : top - total
                drawString(t, in: CGRect(x: b.minX, y: ty, width: b.width, height: f.lineHeight), color: tint, alignment: .center, font: f)
            case .imageOnly:
                place(CGRect(x: b.midX - iz.width / 2, y: b.midY - iz.height / 2, width: iz.width, height: iz.height))
            default:
                let total = iz.width + (showTitle ? tw + 4 : 0)
                let x = b.midX - total / 2
                place(CGRect(x: x, y: b.midY - iz.height / 2, width: iz.width, height: iz.height))
                if showTitle { drawString(t, in: CGRect(x: x + iz.width + 4, y: b.minY, width: tw + 2, height: b.height), color: tint, alignment: .left, font: f) }
            }
        } else if showTitle {
            drawString(t, in: b.insetBy(dx: 4, dy: 0), color: tint, alignment: alignment == .natural ? .center : alignment, font: f)
        }
    }
    private var pressedInside = false
    open override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        pressedInside = true
        isHighlighted = true
    }
    open override func mouseDragged(with e: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(e.locationInWindow, from: nil))
        if inside != isHighlighted { isHighlighted = inside }
    }
    open override func mouseUp(with e: NSEvent) {
        guard isEnabled else { return }
        isHighlighted = false
        pressedInside = false
        guard bounds.contains(convert(e.locationInWindow, from: nil)) else { return }
        performClickAction()
    }
    func performClickAction() {
        if isCheck || type == .pushOnPushOff || type == .toggle || type == .onOff {
            state = type == .radio ? .on : (state == .on ? .off : .on)
        }
        fire()
    }
    open func performClick(_ s: Any?) { performClickAction() }
    public func highlight(_ on: Bool) { isHighlighted = on }
}

// MARK: Switch

open class NSSwitch: NSControl {
    open var state = NSControl.StateValue.off { didSet { needsDisplay = true } }
    public override init(frame r: CGRect) { super.init(frame: r); isContinuous = false }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open override var intrinsicContentSize: CGSize { controlSize == .small ? CGSize(width: 32, height: 18) : controlSize == .mini ? CGSize(width: 26, height: 15) : CGSize(width: 38, height: 22) }
    open override func draw(_ d: CGRect) {
        guard let c = ctx else { return }
        withAppearance {
            let z = intrinsicContentSize
            let r = CGRect(x: bounds.midX - z.width / 2, y: bounds.midY - z.height / 2, width: z.width, height: z.height)
            let on = state == .on
            c.addPath(CGPath(roundedRect: r, cornerWidth: z.height / 2, cornerHeight: z.height / 2, transform: nil))
            c.setFillColor((on ? NSColor.controlAccentColor : NSColor(white: dark ? 1 : 0, alpha: dark ? 0.15 : 0.09)).cgColor)
            c.setAlpha(isEnabled ? 1 : 0.5)
            c.fillPath()
            let d = z.height - 2
            let knob = CGRect(x: on ? r.maxX - d - 1 : r.minX + 1, y: r.minY + 1, width: d, height: d)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -0.5 * NSScreen.primaryScale), blur: 1.5 * NSScreen.primaryScale, color: NSColor(white: 0, alpha: 0.3).cgColor)
            c.setFillColor(NSColor.white.cgColor)
            c.fillEllipse(in: knob)
            c.restoreGState()
        }
    }
    open override func mouseUp(with e: NSEvent) {
        guard isEnabled, bounds.contains(convert(e.locationInWindow, from: nil)) else { return }
        state = state == .on ? .off : .on
        fire()
    }
    open override func mouseDown(with e: NSEvent) {}
}

// MARK: Slider

open class NSSlider: NSControl {
    open var minValue = 0.0 { didSet { needsDisplay = true } }
    open var maxValue = 1.0 { didSet { needsDisplay = true } }
    open var numberOfTickMarks = 0
    open var allowsTickMarkValuesOnly = false
    open var tickMarkPosition = 0
    open var trackFillColor: NSColor?
    open var isVertical = false
    public convenience init(value: Double, minValue a: Double, maxValue b: Double, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        minValue = a; maxValue = b; doubleValue = value; self.target = target; self.action = action
        isContinuous = true
    }
    open override var intrinsicContentSize: CGSize { CGSize(width: NSViewNoIntrinsicMetric, height: controlSize == .small ? 15 : controlSize == .mini ? 12 : 20) }
    private var knobD: CGFloat { controlSize == .small ? 12 : controlSize == .mini ? 10 : 16 }
    private var frac: CGFloat { maxValue > minValue ? CGFloat((doubleValue - minValue) / (maxValue - minValue)) : 0 }
    open override func draw(_ d: CGRect) {
        guard let c = ctx else { return }
        withAppearance {
            let b = bounds
            let h: CGFloat = 4
            let track = CGRect(x: b.minX + 1, y: b.midY - h / 2, width: b.width - 2, height: h)
            c.addPath(CGPath(roundedRect: track, cornerWidth: 2, cornerHeight: 2, transform: nil))
            c.setFillColor(NSColor(white: dark ? 1 : 0, alpha: dark ? 0.2 : 0.12).cgColor)
            c.fillPath()
            let x = b.minX + knobD / 2 + (b.width - knobD) * frac
            let done = CGRect(x: track.minX, y: track.minY, width: max(0, x - track.minX), height: h)
            c.addPath(CGPath(roundedRect: done, cornerWidth: 2, cornerHeight: 2, transform: nil))
            c.setFillColor((isEnabled ? (trackFillColor ?? .controlAccentColor) : .disabledControlTextColor).cgColor)
            c.fillPath()
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -0.5 * NSScreen.primaryScale), blur: 1.5 * NSScreen.primaryScale, color: NSColor(white: 0, alpha: 0.35).cgColor)
            c.setFillColor(NSColor.white.cgColor)
            c.fillEllipse(in: CGRect(x: x - knobD / 2, y: b.midY - knobD / 2, width: knobD, height: knobD))
            c.restoreGState()
        }
    }
    private func track(_ e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let u = max(0, min(1, (p.x - knobD / 2) / max(bounds.width - knobD, 1)))
        var v = minValue + Double(u) * (maxValue - minValue)
        if allowsTickMarkValuesOnly, numberOfTickMarks > 1 {
            let step = (maxValue - minValue) / Double(numberOfTickMarks - 1)
            v = minValue + (((v - minValue) / step).rounded() * step)
        }
        doubleValue = v
        if isContinuous { fire() }
    }
    open override func mouseDown(with e: NSEvent) { guard isEnabled else { return }; track(e) }
    open override func mouseDragged(with e: NSEvent) { guard isEnabled else { return }; track(e) }
    open override func mouseUp(with e: NSEvent) { guard isEnabled else { return }; track(e); if !isContinuous { fire() } }
}

// MARK: Segmented control

open class NSSegmentedControl: NSControl {
    public enum SwitchTracking: UInt, Sendable { case selectOne, selectAny, momentary, momentaryAccelerator }
    public enum Style: Int, Sendable { case automatic, rounded, roundRect, texturedRounded, capsule, texturedSquare, smallSquare, separated }
    private var labels: [String] = []
    private var images: [NSImage?] = []
    private var widths: [CGFloat] = []
    private var enabled: [Bool] = []
    private var selected = Set<Int>()
    open var segmentCount = 0 { didSet { resize() } }
    open var trackingMode = SwitchTracking.selectOne
    open var segmentStyle = Style.automatic
    open var segmentDistribution = 0
    open var selectedSegmentBezelColor: NSColor?
    private func resize() {
        func fit<T>(_ a: inout [T], _ v: T) { while a.count < segmentCount { a.append(v) }; if a.count > segmentCount { a.removeLast(a.count - segmentCount) } }
        fit(&labels, ""); fit(&images, nil); fit(&widths, 0); fit(&enabled, true)
        invalidateIntrinsicContentSize()
    }
    public convenience init(labels l: [String], trackingMode m: SwitchTracking, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        segmentCount = l.count; labels = l; trackingMode = m; self.target = target; self.action = action
    }
    public convenience init(images i: [NSImage], trackingMode m: SwitchTracking, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        segmentCount = i.count; images = i; trackingMode = m; self.target = target; self.action = action
    }
    public func setLabel(_ s: String, forSegment i: Int) { labels[i] = s; invalidateIntrinsicContentSize(); needsDisplay = true }
    public func label(forSegment i: Int) -> String? { labels[i] }
    public func setImage(_ m: NSImage?, forSegment i: Int) { images[i] = m; invalidateIntrinsicContentSize(); needsDisplay = true }
    public func image(forSegment i: Int) -> NSImage? { images[i] }
    public func setImageScaling(_ s: NSImageScaling, forSegment i: Int) {}
    public func setWidth(_ w: CGFloat, forSegment i: Int) { widths[i] = w; invalidateIntrinsicContentSize() }
    public func width(forSegment i: Int) -> CGFloat { widths[i] }
    public func setEnabled(_ e: Bool, forSegment i: Int) { enabled[i] = e; needsDisplay = true }
    public func isEnabled(forSegment i: Int) -> Bool { enabled[i] }
    public func setToolTip(_ s: String?, forSegment i: Int) {}
    public func setTag(_ t: Int, forSegment i: Int) {}
    public func setSelected(_ s: Bool, forSegment i: Int) {
        if s { if trackingMode == .selectOne { selected = [i] } else { selected.insert(i) } } else { selected.remove(i) }
        needsDisplay = true
    }
    public func isSelected(forSegment i: Int) -> Bool { selected.contains(i) }
    open var selectedSegment: Int {
        get { selected.min() ?? -1 }
        set { selected = newValue >= 0 ? [newValue] : []; needsDisplay = true }
    }
    open override var intrinsicContentSize: CGSize {
        var w: CGFloat = 0
        for i in 0..<segmentCount { w += natural(i) }
        return CGSize(width: w + 2, height: controlSize.height)
    }
    private func natural(_ i: Int) -> CGFloat {
        if widths[i] > 0 { return widths[i] }
        let tw = labels[i].isEmpty ? 0 : effectiveFont.width(labels[i])
        let iw = images[i]?.size.width ?? 0
        return tw + iw + (tw > 0 && iw > 0 ? 4 : 0) + 16
    }
    private func rects() -> [CGRect] {
        let b = bounds
        let total = (0..<segmentCount).reduce(CGFloat(0)) { $0 + natural($1) }
        let extra = segmentCount > 0 ? (b.width - total) / CGFloat(segmentCount) : 0
        var x = b.minX
        return (0..<segmentCount).map { i in
            let w = natural(i) + extra
            defer { x += w }
            return CGRect(x: x, y: b.minY, width: w, height: b.height)
        }
    }
    private var pressed = -1
    open override func draw(_ d: CGRect) {
        guard let c = ctx else { return }
        withAppearance {
            let b = bounds.insetBy(dx: 0.5, dy: 1)
            c.addPath(CGPath(roundedRect: b, cornerWidth: 6, cornerHeight: 6, transform: nil))
            c.setFillColor(NSColor(white: dark ? 1 : 0, alpha: dark ? 0.1 : 0.06).cgColor)
            c.fillPath()
            let rs = rects()
            for i in 0..<segmentCount {
                let r = rs[i]
                if selected.contains(i) || pressed == i {
                    c.addPath(CGPath(roundedRect: r.insetBy(dx: 1, dy: 2), cornerWidth: 5, cornerHeight: 5, transform: nil))
                    c.setFillColor((selectedSegmentBezelColor ?? (dark ? NSColor(white: 1, alpha: 0.25) : .white)).cgColor)
                    c.fillPath()
                } else if i > 0, !selected.contains(i - 1) {
                    c.setFillColor(NSColor(white: dark ? 1 : 0, alpha: 0.12).cgColor)
                    c.fill(CGRect(x: r.minX, y: r.minY + 5, width: 1, height: r.height - 10))
                }
                let color: NSColor = enabled[i] && isEnabled ? .labelColor : .disabledControlTextColor
                if let img = images[i] {
                    let z = img.size
                    let tw = labels[i].isEmpty ? 0 : effectiveFont.width(labels[i]) + 4
                    let x0 = r.midX - (z.width + tw) / 2
                    c.saveGState()
                    if isFlipped { c.translateBy(x: x0, y: r.midY + z.height / 2); c.scaleBy(x: 1, y: -1) } else { c.translateBy(x: x0, y: r.midY - z.height / 2) }
                    img.render(in: c, tint: color)
                    c.restoreGState()
                    if tw > 0 { drawString(labels[i], in: CGRect(x: x0 + z.width + 4, y: r.minY, width: tw, height: r.height), color: color, alignment: .left, font: effectiveFont) }
                } else {
                    drawString(labels[i], in: r, color: color, alignment: .center, font: effectiveFont)
                }
            }
        }
    }
    private func at(_ e: NSEvent) -> Int {
        let p = convert(e.locationInWindow, from: nil)
        return rects().firstIndex { $0.contains(p) } ?? -1
    }
    open override func mouseDown(with e: NSEvent) { guard isEnabled else { return }; pressed = at(e); needsDisplay = true }
    open override func mouseUp(with e: NSEvent) {
        let i = at(e)
        let was = pressed
        pressed = -1
        needsDisplay = true
        guard isEnabled, i >= 0, i == was, enabled[i] else { return }
        switch trackingMode {
        case .selectOne: selected = [i]
        case .selectAny: if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
        default: selected = [i]
        }
        fire()
        if trackingMode == .momentary || trackingMode == .momentaryAccelerator { selected = [] }
    }
}

// MARK: Pop-up button

open class NSPopUpButton: NSButton {
    public var menuItems = NSMenu()
    public override var menu: NSMenu? { get { menuItems } set { if let newValue { menuItems = newValue } } }
    public var pullsDown = false
    public var autoenablesItems = true
    private var selectedIndex = 0
    public convenience init(frame r: CGRect, pullsDown: Bool) { self.init(frame: r); self.pullsDown = pullsDown }
    public var itemArray: [NSMenuItem] { menuItems.items }
    public var numberOfItems: Int { menuItems.items.count }
    public var itemTitles: [String] { menuItems.items.map(\.title) }
    public var selectedItem: NSMenuItem? { menuItems.items.indices.contains(selectedIndex) ? menuItems.items[selectedIndex] : nil }
    public var indexOfSelectedItem: Int { selectedIndex }
    public var titleOfSelectedItem: String? { selectedItem?.title }
    public func addItem(withTitle t: String) { menuItems.addItem(NSMenuItem(title: t, action: nil, keyEquivalent: "")); changed() }
    public func addItems(withTitles ts: [String]) { for t in ts { addItem(withTitle: t) } }
    public func insertItem(withTitle t: String, at i: Int) { menuItems.insertItem(NSMenuItem(title: t, action: nil, keyEquivalent: ""), at: i); changed() }
    public func removeItem(at i: Int) { menuItems.removeItem(at: i); changed() }
    public func removeAllItems() { menuItems.removeAllItems(); selectedIndex = 0; changed() }
    public func item(at i: Int) -> NSMenuItem? { menuItems.items.indices.contains(i) ? menuItems.items[i] : nil }
    public func item(withTitle t: String) -> NSMenuItem? { menuItems.items.first { $0.title == t } }
    public func indexOfItem(withTitle t: String) -> Int { menuItems.items.firstIndex { $0.title == t } ?? -1 }
    public func indexOfItem(withRepresentedObject o: Any?) -> Int { -1 }
    public func indexOfItem(withTag t: Int) -> Int { menuItems.items.firstIndex { $0.tag == t } ?? -1 }
    public func select(_ m: NSMenuItem?) { if let m, let i = menuItems.items.firstIndex(where: { $0 === m }) { selectedIndex = i; changed() } }
    public func selectItem(at i: Int) { selectedIndex = i; changed() }
    public func selectItem(withTitle t: String) { if let i = menuItems.items.firstIndex(where: { $0.title == t }) { selectedIndex = i; changed() } }
    public func selectItem(withTag t: Int) -> Bool { if let i = menuItems.items.firstIndex(where: { $0.tag == t }) { selectedIndex = i; changed(); return true }; return false }
    public func setTitle(_ t: String) { title = t }
    private func changed() { invalidateIntrinsicContentSize(); needsDisplay = true }
    open override var intrinsicContentSize: CGSize {
        let w = menuItems.items.map { effectiveFont.width($0.title) }.max() ?? 40
        return CGSize(width: w + 34, height: controlSize.height)
    }
    open override func draw(_ d: CGRect) {
        guard let c = ctx else { return }
        withAppearance {
            let r = bounds.insetBy(dx: 1, dy: 1)
            c.addPath(CGPath(roundedRect: r, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
            c.setFillColor((dark ? NSColor(white: 1, alpha: isHighlighted ? 0.3 : 0.2) : NSColor(white: isHighlighted ? 0.92 : 1, alpha: 1)).cgColor)
            c.fillPath()
            let text = pullsDown ? (menuItems.items.first?.title ?? "") : (selectedItem?.title ?? "")
            drawString(text, in: CGRect(x: 9, y: r.minY, width: r.width - 30, height: r.height), color: isEnabled ? .labelColor : .disabledControlTextColor, alignment: .left, font: effectiveFont)
            let ax = r.maxX - 16
            let chip = CGRect(x: ax - 1, y: r.midY - 8, width: 15, height: 16)
            c.addPath(CGPath(roundedRect: chip, cornerWidth: 4, cornerHeight: 4, transform: nil))
            c.setFillColor(NSColor.controlAccentColor.cgColor)
            c.fillPath()
            c.setStrokeColor(NSColor.white.cgColor); c.setLineWidth(1.4); c.setLineCap(.round); c.setLineJoin(.round)
            c.move(to: CGPoint(x: ax + 3, y: r.midY - 2)); c.addLine(to: CGPoint(x: ax + 6.5, y: r.midY - 5)); c.addLine(to: CGPoint(x: ax + 10, y: r.midY - 2)); c.strokePath()
            c.move(to: CGPoint(x: ax + 3, y: r.midY + 2)); c.addLine(to: CGPoint(x: ax + 6.5, y: r.midY + 5)); c.addLine(to: CGPoint(x: ax + 10, y: r.midY + 2)); c.strokePath()
        }
    }
    open override func mouseDown(with e: NSEvent) { guard isEnabled else { return }; isHighlighted = true }
    open override func mouseDragged(with e: NSEvent) {}
    open override func mouseUp(with e: NSEvent) {
        isHighlighted = false
        guard isEnabled else { return }
        menuItems.onPick = { [weak self] item in
            guard let self, let i = self.menuItems.items.firstIndex(where: { $0 === item }) else { return }
            if !self.pullsDown { self.selectedIndex = i; self.changed() }
            self.fire()
        }
        menuItems.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    open override func performClick(_ s: Any?) { fire() }
}

// MARK: Image view

open class NSImageView: NSControl {
    open var image: NSImage? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    open var imageScaling = NSImageScaling.scaleProportionallyDown { didSet { needsDisplay = true } }
    open var imageAlignment = 0
    open var imageFrameStyle = 0
    open var animates = false
    open var contentTintColor: NSColor? { didSet { needsDisplay = true } }
    open var isEditable = false
    open var allowsCutCopyPaste = false
    open var symbolConfiguration: NSImage.SymbolConfiguration? { didSet { if let c = symbolConfiguration, let i = image { image = i.withSymbolConfiguration(c) } } }
    public convenience init(image i: NSImage) { self.init(frame: .zero); image = i }
    open override var intrinsicContentSize: CGSize { image?.size ?? CGSize(width: NSViewNoIntrinsicMetric, height: NSViewNoIntrinsicMetric) }
    open override func draw(_ d: CGRect) {
        guard let c = ctx, let img = image else { return }
        withAppearance {
            let b = bounds
            var z = img.size
            guard z.width > 0, z.height > 0 else { return }
            switch imageScaling {
            case .scaleAxesIndependently: z = b.size
            case .scaleProportionallyUpOrDown:
                let k = min(b.width / z.width, b.height / z.height)
                z = CGSize(width: z.width * k, height: z.height * k)
            case .scaleProportionallyDown:
                let k = min(1, min(b.width / z.width, b.height / z.height))
                z = CGSize(width: z.width * k, height: z.height * k)
            default: break
            }
            let r = CGRect(x: b.midX - z.width / 2, y: b.midY - z.height / 2, width: z.width, height: z.height)
            c.saveGState()
            if isFlipped { c.translateBy(x: r.minX, y: r.maxY); c.scaleBy(x: 1, y: -1) } else { c.translateBy(x: r.minX, y: r.minY) }
            c.scaleBy(x: z.width / img.size.width, y: z.height / img.size.height)
            img.render(in: c, tint: contentTintColor ?? .labelColor)
            c.restoreGState()
        }
    }
}

// MARK: Stack view

open class NSStackView: NSView {
    public typealias Orientation = NSLayoutConstraint.Orientation
    public enum Distribution: Int, Sendable { case gravityAreas = -1, fill = 0, fillEqually, fillProportionally, equalSpacing, equalCentering }
    public enum Gravity: Int, Sendable { case leading = 1, center, trailing; public static let top = Gravity.leading, bottom = Gravity.trailing }
    public static var useDefaultSpacing: CGFloat { .greatestFiniteMagnitude }
    public var orientation = NSLayoutConstraint.Orientation.horizontal { didSet { needsLayout = true } }
    public var alignment = NSLayoutAttribute.centerY { didSet { needsLayout = true } }
    public var distribution = Distribution.gravityAreas { didSet { needsLayout = true } }
    public var spacing: CGFloat = 8 { didSet { needsLayout = true } }
    public var edgeInsets = NSEdgeInsets() { didSet { needsLayout = true } }
    public var detachesHiddenViews = true { didSet { needsLayout = true } }
    public private(set) var arrangedSubviews: [NSView] = []
    private var custom: [ObjectIdentifier: CGFloat] = [:]
    public convenience init(views: [NSView]) { self.init(frame: .zero); for v in views { addArrangedSubview(v) } }
    public func addArrangedSubview(_ v: NSView) { insertArrangedSubview(v, at: arrangedSubviews.count) }
    public func insertArrangedSubview(_ v: NSView, at i: Int) {
        arrangedSubviews.removeAll { $0 === v }
        arrangedSubviews.insert(v, at: min(i, arrangedSubviews.count))
        v.translatesAutoresizingMaskIntoConstraints = false
        if v.superview !== self { addSubview(v) }
        needsLayout = true
    }
    public func removeArrangedSubview(_ v: NSView) { arrangedSubviews.removeAll { $0 === v }; needsLayout = true }
    public func addView(_ v: NSView, in g: Gravity) { addArrangedSubview(v) }
    public func views(in g: Gravity) -> [NSView] { arrangedSubviews }
    public var views: [NSView] { arrangedSubviews }
    public func setViews(_ vs: [NSView], in g: Gravity) { for v in arrangedSubviews { v.removeFromSuperview() }; arrangedSubviews = []; for v in vs { addArrangedSubview(v) } }
    public func setCustomSpacing(_ s: CGFloat, after v: NSView) { custom[ObjectIdentifier(v)] = s; needsLayout = true }
    public func customSpacing(after v: NSView) -> CGFloat { custom[ObjectIdentifier(v)] ?? NSStackView.useDefaultSpacing }
    public func setHuggingPriority(_ p: NSLayoutPriority, for o: NSLayoutConstraint.Orientation) {}
    public func setClippingResistancePriority(_ p: NSLayoutPriority, for o: NSLayoutConstraint.Orientation) {}
    open override func removeFromSuperview() { super.removeFromSuperview() }

    override func generatedConstraints() -> [NSLayoutConstraint] {
        arrangedSubviews.removeAll { $0.superview !== self }
        let vs = arrangedSubviews.filter { !(detachesHiddenViews && $0.isHidden) }
        var out: [NSLayoutConstraint] = []
        func make(_ a: NSView, _ x: NSLayoutAttribute, _ r: NSLayoutRelation, _ b: NSView?, _ y: NSLayoutAttribute, _ c: CGFloat, _ p: NSLayoutPriority = .required, m: CGFloat = 1) {
            let k = NSLayoutConstraint(item: a, attribute: x, relatedBy: r, toItem: b as Any?, attribute: y, multiplier: m, constant: c)
            k.priority = p
            out.append(k)
        }
        let h = orientation == .horizontal
        let lead: NSLayoutAttribute = h ? .leading : .top, trail: NSLayoutAttribute = h ? .trailing : .bottom
        let cLead: NSLayoutAttribute = h ? .top : .leading, cTrail: NSLayoutAttribute = h ? .bottom : .trailing
        let insLead = h ? edgeInsets.left : edgeInsets.top, insTrail = h ? edgeInsets.right : edgeInsets.bottom
        let cInsLead = h ? edgeInsets.top : edgeInsets.left, cInsTrail = h ? edgeInsets.bottom : edgeInsets.right
        guard let first = vs.first, let last = vs.last else { return out }
        make(first, lead, .equal, self, lead, insLead)
        make(last, trail, .equal, self, trail, -insTrail)
        for (a, b) in zip(vs, vs.dropFirst()) {
            let s = custom[ObjectIdentifier(a)].flatMap { $0 == NSStackView.useDefaultSpacing ? nil : $0 } ?? spacing
            if distribution == .equalSpacing || distribution == .equalCentering || distribution == .gravityAreas {
                make(b, lead, .greaterThanOrEqual, a, trail, s)
                if distribution == .gravityAreas { make(b, lead, .equal, a, trail, s, NSLayoutPriority(490)) }
            } else {
                make(b, lead, .equal, a, trail, s)
            }
            if distribution == .fillEqually { make(a, h ? .width : .height, .equal, b, h ? .width : .height, 0) }
        }
        for v in vs {
            // Across the stack: the stack is at least as big as its largest view, and views keep their alignment.
            make(v, cLead, .greaterThanOrEqual, self, cLead, cInsLead)
            make(v, cTrail, .lessThanOrEqual, self, cTrail, -cInsTrail)
            let center: NSLayoutAttribute = h ? .centerY : .centerX
            switch alignment {
            case .leading, .left, .top: make(v, cLead, .equal, self, cLead, cInsLead, NSLayoutPriority(999))
            case .trailing, .right, .bottom: make(v, cTrail, .equal, self, cTrail, -cInsTrail, NSLayoutPriority(999))
            case .centerX, .centerY: make(v, center, .equal, self, center, (cInsLead - cInsTrail) / 2, NSLayoutPriority(999))
            case .width, .height:
                make(v, cLead, .equal, self, cLead, cInsLead, NSLayoutPriority(999))
                make(v, cTrail, .equal, self, cTrail, -cInsTrail, NSLayoutPriority(999))
            case .firstBaseline, .lastBaseline:
                if let f = vs.first, f !== v { make(v, alignment, .equal, f, alignment, 0, NSLayoutPriority(999)) }
            default: break
            }
            // Shrink-wrap the cross axis at low priority.
            make(self, h ? .height : .width, .greaterThanOrEqual, v, h ? .height : .width, cInsLead + cInsTrail, .required)
        }
        return out
    }
    open override var intrinsicContentSize: CGSize { CGSize(width: NSViewNoIntrinsicMetric, height: NSViewNoIntrinsicMetric) }
    public func hugCrossAxisHint() {}
}

// MARK: Scroll view

open class NSClipView: NSView {
    open var documentView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let d = documentView { addSubview(d) }
        }
    }
    open var drawsBackground = false
    open var backgroundColor: NSColor = .clear
    open override var isFlipped: Bool { true }
    open override var clipsSubviewsToBounds: Bool { true }
    public var documentVisibleRect: CGRect { bounds }
    public var documentRect: CGRect { documentView?.frame ?? .zero }
    public func constrainBoundsRect(_ r: CGRect) -> CGRect { r }
}
public enum NSScrollElasticity: Int, Sendable { case automatic, none, allowed }
public enum NSBorderType: UInt, Sendable { case noBorder, lineBorder, bezelBorder, grooveBorder }

open class NSScrollView: NSView {
    public typealias Elasticity = NSScrollElasticity
    public let contentView0 = NSClipView(frame: .zero)
    public var contentView: NSClipView { contentView0 }
    public var documentView: NSView? { get { contentView0.documentView } set { contentView0.documentView = newValue } }
    public var hasVerticalScroller = false
    public var hasHorizontalScroller = false
    public var autohidesScrollers = true
    public var drawsBackground = true { didSet { needsDisplay = true } }
    public var backgroundColor: NSColor = .controlBackgroundColor
    public var borderType = NSBorderType.noBorder
    public var scrollerStyle = 0
    public var horizontalScrollElasticity = NSScrollElasticity.automatic
    public var verticalScrollElasticity = NSScrollElasticity.automatic
    public var automaticallyAdjustsContentInsets = true
    public var contentInsets = NSEdgeInsets()
    public var scrollerInsets = NSEdgeInsets()
    public var usesPredominantAxisScrolling = true
    public var allowsMagnification = false
    public var lineScroll: CGFloat = 32
    public var verticalScroller: AnyObject? = nil
    public var documentVisibleRect: CGRect { contentView0.bounds }
    public override init(frame r: CGRect) {
        super.init(frame: r)
        contentView0.frame = CGRect(origin: .zero, size: r.size)
        contentView0.autoresizingMask = [.width, .height]
        addSubview(contentView0)
    }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open override func draw(_ d: CGRect) {
        if drawsBackground, let c = NSGraphicsContext.current?.cgContext {
            effectiveAppearance.performAsCurrentDrawingAppearance { c.setFillColor(backgroundColor.cgColor); c.fill(bounds) }
        }
    }
    func scroll(to p: CGPoint) {
        let doc = documentView?.frame.size ?? .zero
        let vis = contentView0.frame.size
        let x = max(0, min(p.x, max(0, doc.width - vis.width)))
        let y = max(0, min(p.y, max(0, doc.height - vis.height)))
        contentView0.setBoundsOrigin(CGPoint(x: x, y: y))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: contentView0)
        contentView0.backing.setNeedsDisplay()
    }
    func reveal(_ r: CGRect, in v: NSView) {
        guard let doc = documentView else { return }
        let inDoc = v.convert(r, to: doc)
        let b = contentView0.bounds
        var o = b.origin
        if inDoc.minY < b.minY { o.y = inDoc.minY } else if inDoc.maxY > b.maxY { o.y = inDoc.maxY - b.height }
        scroll(to: o)
    }
    open override func scrollWheel(with e: NSEvent) {
        let step = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * lineScroll
        let b = contentView0.bounds
        scroll(to: CGPoint(x: b.minX, y: b.minY - step))
    }
    public func flashScrollers() {}
    public func tile() {}
}
extension NSView {
    public static let boundsDidChangeNotification = Notification.Name("NSViewBoundsDidChangeNotification")
    public static let frameDidChangeNotification = Notification.Name("NSViewFrameDidChangeNotification")
}

// MARK: Other views

open class NSBox: NSView {
    public enum BoxType: UInt, Sendable { case primary, separator, custom }
    public var boxType = BoxType.primary { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var titlePosition = 0
    public var title = ""
    public var borderWidth: CGFloat = 1
    public var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }
    public var borderColor: NSColor = .clear
    public var fillColor: NSColor = .clear { didSet { needsDisplay = true } }
    public var isTransparent = false
    public var contentViewMargins = CGSize.zero
    public var contentView: NSView? { didSet { oldValue?.removeFromSuperview(); if let c = contentView { addSubview(c) } } }
    open override var intrinsicContentSize: CGSize { boxType == .separator ? CGSize(width: NSViewNoIntrinsicMetric, height: 1) : CGSize(width: NSViewNoIntrinsicMetric, height: NSViewNoIntrinsicMetric) }
    open override func draw(_ d: CGRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if boxType == .separator { c.setFillColor(NSColor.separatorColor.cgColor); c.fill(bounds); return }
            c.addPath(CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            c.setFillColor(fillColor.cgColor)
            c.fillPath()
        }
    }
}

/// Windows has no such blur behind a layered window: this draws the material's flat color.
open class NSVisualEffectView: NSView {
    public enum Material: Int, Sendable { case titlebar, selection, menu, popover, sidebar, headerView, sheet, windowBackground, hudWindow, fullScreenUI, toolTip, contentBackground, underWindowBackground, underPageBackground }
    public enum BlendingMode: Int, Sendable { case behindWindow, withinWindow }
    public enum State: Int, Sendable { case followsWindowActiveState, active, inactive }
    public var material = Material.windowBackground { didSet { needsDisplay = true } }
    public var blendingMode = BlendingMode.behindWindow
    public var state = State.followsWindowActiveState
    public var isEmphasized = false
    public var maskImage: NSImage?
    open override func draw(_ d: CGRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            c.setFillColor(NSColor.windowBackgroundColor.cgColor)
            c.fill(bounds)
        }
    }
}

open class NSProgressIndicator: NSView {
    public enum Style: UInt, Sendable { case bar, spinning }
    public var style = Style.bar { didSet { needsDisplay = true } }
    public var isIndeterminate = true
    public var isDisplayedWhenStopped = true
    public var controlSize = NSControl.ControlSize.regular
    public var minValue = 0.0, maxValue = 100.0
    public var doubleValue = 0.0 { didSet { needsDisplay = true } }
    private var running = false
    public func startAnimation(_ s: Any?) { running = true; needsDisplay = true }
    public func stopAnimation(_ s: Any?) { running = false; needsDisplay = true }
    public func sizeToFit() { frame.size = style == .spinning ? CGSize(width: 16, height: 16) : CGSize(width: frame.width, height: 6) }
    open override var intrinsicContentSize: CGSize { style == .spinning ? CGSize(width: controlSize == .small ? 16 : 32, height: controlSize == .small ? 16 : 32) : CGSize(width: NSViewNoIntrinsicMetric, height: 6) }
    open override func draw(_ d: CGRect) {
        guard running || isDisplayedWhenStopped, let c = NSGraphicsContext.current?.cgContext else { return }
        c.setStrokeColor(NSColor(white: 0.5, alpha: 1).cgColor)
        c.setLineWidth(2)
        c.strokeEllipse(in: bounds.insetBy(dx: 3, dy: 3))
    }
}

open class NSColorWell: NSControl {
    public var color: NSColor = .white { didSet { needsDisplay = true } }
    public var isBordered = true
    public var colorWellStyle = 0
    public var supportsAlpha = false
    public func activate(_ e: Bool) {}
    public func deactivate() {}
    open override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 23) }
    open override func draw(_ d: CGRect) {
        guard let c = ctx else { return }
        c.addPath(CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil))
        c.setFillColor(color.cgColor)
        c.fillPath()
    }
    open override func mouseUp(with e: NSEvent) {
        guard isEnabled else { return }
        if let picked = ColorChooser.choose(from: color) { color = picked; fire() }
    }
}

open class NSTabViewItem: NSObject {
    public var label = ""
    public var view: NSView?
    public var identifier: Any?
    public init(identifier i: Any?) { identifier = i; super.init() }
    public convenience init(viewController c: NSViewController) { self.init(identifier: nil); view = c.view }
}
public protocol NSTabViewDelegate: AnyObject {}
open class NSTabView: NSView {
    public enum TabType: UInt, Sendable { case topTabsBezelBorder, leftTabsBezelBorder, bottomTabsBezelBorder, rightTabsBezelBorder, noTabsBezelBorder, noTabsLineBorder, noTabsNoBorder }
    public var tabViewType = TabType.noTabsNoBorder
    public private(set) var tabViewItems: [NSTabViewItem] = []
    public weak var delegate: NSTabViewDelegate?
    public private(set) var selectedTabViewItem: NSTabViewItem?
    public func addTabViewItem(_ i: NSTabViewItem) { tabViewItems.append(i); if selectedTabViewItem == nil { selectTabViewItem(i) } }
    public func selectTabViewItem(_ i: NSTabViewItem?) {
        selectedTabViewItem?.view?.removeFromSuperview()
        selectedTabViewItem = i
        if let v = i?.view { v.frame = bounds; v.autoresizingMask = [.width, .height]; addSubview(v) }
    }
    public func selectTabViewItem(at i: Int) { selectTabViewItem(tabViewItems[i]) }
}
