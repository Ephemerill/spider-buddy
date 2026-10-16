import AppKit

// MARK: - Talking back
//
// Click its thought bubble (with "Its Own Words" on) and a little box comes
// up by it to type in: the same cream and brown as the bubble, with a tail
// pointing at the spider. Return sends; the spider thinks (three dots in its
// bubble) and answers there. Escape, or clicking anywhere else, ends the
// conversation. The box is a non-activating panel, as Spotlight's is, so
// whatever app you were in stays the active one.

final class ChatPanel: NSPanel, NSTextFieldDelegate {
    var onSend: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let pill = ChatPill()
    private let field = NSTextField()
    private let send = ChatSendButton()
    private var name = "Spider"
    private var waiting = false
    private var closing = false

    static let size = CGSize(width: 300, height: 52)

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: ChatPanel.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        // Over the spider's own window.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .aqua)

        pill.frame = CGRect(origin: .zero, size: ChatPanel.size)
        pill.autoresizingMask = [.width, .height]
        contentView = pill

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.textColor = ChatPill.ink
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byTruncatingHead
        pill.addSubview(field)

        send.target = self
        send.action = #selector(sendTapped)
        send.toolTip = "Send (Return)"
        pill.addSubview(send)
        layoutInside()
        refreshPlaceholder()
        refreshSend()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Opens by the spider and takes the typing.
    func open(name: String, near spider: CGPoint, bubble: CGRect?) {
        self.name = name.isEmpty ? "Spider" : name
        closing = false
        refreshPlaceholder()
        place(near: spider, bubble: bubble)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        // Opened with no click of ours to give it the keyboard (from a
        // timer, say): the app is brought forward for the typing, and
        // whatever was in front goes back there after.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isKeyWindow else { return }
            self.handBackTo = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
            self.makeFirstResponder(self.field)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            animator().alphaValue = 1
        }
    }

    /// The spider is thinking what to say (or not): Return waits for it.
    func setWaiting(_ w: Bool) {
        waiting = w
        refreshPlaceholder()
        refreshSend()
    }

    /// Kept by the spider: below it, or over its bubble where there is no
    /// room below; the tail points at it either way.
    func place(near spider: CGPoint, bubble: CGRect?) {
        let screen = NSScreen.screens.first { $0.frame.contains(spider) } ?? NSScreen.main
        let room = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 4000, height: 4000)
        let sz = ChatPanel.size
        var x = spider.x - sz.width / 2
        x = min(max(x, room.minX + 6), room.maxX - sz.width - 6)
        var y = spider.y - 34 - sz.height
        var tailUp = true
        if y < room.minY + 4 {
            y = (bubble?.maxY ?? spider.y + 60) + 6
            tailUp = false
        }
        y = min(max(y, room.minY + 4), room.maxY - sz.height - 4)
        let frame = CGRect(x: x.rounded(), y: y.rounded(), width: sz.width, height: sz.height)
        if frame != self.frame { setFrame(frame, display: true) }
        let tailX = min(max(spider.x - frame.minX, 26), sz.width - 26)
        if pill.tailX != tailX || pill.tailUp != tailUp {
            pill.tailX = tailX
            pill.tailUp = tailUp
            layoutInside()
        }
    }

    func finish() {
        guard !closing else { return }
        closing = true
        field.stringValue = ""
        orderOut(nil)
        if let app = handBackTo, app != NSRunningApplication.current { app.activate(options: []) }
        handBackTo = nil
        onClose?()
    }

    /// The app that was in front before this one was brought forward.
    private var handBackTo: NSRunningApplication?

    private func layoutInside() {
        let body = pill.bodyRect
        send.frame = CGRect(x: body.maxX - 32, y: body.midY - 13, width: 26, height: 26)
        field.frame = CGRect(x: body.minX + 16, y: body.midY - 9, width: send.frame.minX - body.minX - 22, height: 18)
    }

    private func refreshPlaceholder() {
        let text = waiting ? "\(name) is thinking…" : "Say something to \(name)…"
        field.placeholderAttributedString = NSAttributedString(string: text, attributes: [
            .foregroundColor: ChatPill.ink.withAlphaComponent(0.45),
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        ])
    }

    private func refreshSend() {
        send.isEnabled = !waiting && !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func controlTextDidChange(_ obj: Notification) {
        if field.stringValue.count > 200 { field.stringValue = String(field.stringValue.prefix(200)) }
        refreshSend()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { sendTapped(); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { finish(); return true }
        return false
    }

    @objc private func sendTapped() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !waiting, !text.isEmpty else { return }
        field.stringValue = ""
        refreshSend()
        onSend?(text)
    }

    override func cancelOperation(_ sender: Any?) { finish() }

    // Clicking anywhere else ends it.
    override func resignKey() {
        super.resignKey()
        finish()
    }

    /// Tools: as if typed and sent.
    func debugSend(_ text: String) {
        field.stringValue = text
        sendTapped()
    }
}

/// The box itself: a cream pill with a brown rim, and a tail to the spider.
final class ChatPill: NSView {
    static let ink = NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.08, alpha: 1)
    static let paper = NSColor(calibratedRed: 1, green: 0.98, blue: 0.94, alpha: 1)
    static let rim = NSColor(calibratedRed: 0.30, green: 0.18, blue: 0.09, alpha: 0.85)

    var tailX: CGFloat = 150 { didSet { needsDisplay = true } }
    var tailUp = true { didSet { needsDisplay = true } }

    /// The pill, inside the room the tail takes.
    var bodyRect: CGRect {
        let b = bounds.insetBy(dx: 2, dy: 2)
        return tailUp ? CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height - 9)
                      : CGRect(x: b.minX, y: b.minY + 9, width: b.width, height: b.height - 9)
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = bodyRect
        let r = body.height / 2
        let p = NSBezierPath(roundedRect: body, xRadius: r, yRadius: r)
        // The tail: a soft little point toward the spider.
        let tail = NSBezierPath()
        if tailUp {
            tail.move(to: CGPoint(x: tailX - 8, y: body.maxY - 1))
            tail.curve(to: CGPoint(x: tailX, y: body.maxY + 8), controlPoint1: CGPoint(x: tailX - 3, y: body.maxY + 2), controlPoint2: CGPoint(x: tailX - 1, y: body.maxY + 6))
            tail.curve(to: CGPoint(x: tailX + 8, y: body.maxY - 1), controlPoint1: CGPoint(x: tailX + 1, y: body.maxY + 6), controlPoint2: CGPoint(x: tailX + 3, y: body.maxY + 2))
        } else {
            tail.move(to: CGPoint(x: tailX - 8, y: body.minY + 1))
            tail.curve(to: CGPoint(x: tailX, y: body.minY - 8), controlPoint1: CGPoint(x: tailX - 3, y: body.minY - 2), controlPoint2: CGPoint(x: tailX - 1, y: body.minY - 6))
            tail.curve(to: CGPoint(x: tailX + 8, y: body.minY + 1), controlPoint1: CGPoint(x: tailX + 1, y: body.minY - 6), controlPoint2: CGPoint(x: tailX + 3, y: body.minY - 2))
        }
        tail.close()
        // Rim round the outside of both, then the paper over the join.
        ChatPill.rim.setStroke()
        p.lineWidth = 2.2
        p.stroke()
        tail.lineWidth = 2.2
        tail.stroke()
        ChatPill.paper.setFill()
        p.fill()
        tail.fill()
    }
}

/// A round brown button with an arrow: send.
final class ChatSendButton: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let on = isEnabled
        let down = isHighlighted
        let fill = on ? ChatPill.rim.blended(withFraction: down ? 0.25 : 0, of: .black) ?? ChatPill.rim
                      : ChatPill.ink.withAlphaComponent(0.15)
        fill.setFill()
        NSBezierPath(ovalIn: r).fill()
        let arrow = NSBezierPath()
        let c = CGPoint(x: r.midX, y: r.midY)
        // (Up the screen, whichever way the button's coordinates run.)
        let up: CGFloat = isFlipped ? -1 : 1
        arrow.move(to: CGPoint(x: c.x, y: c.y - 6 * up))
        arrow.line(to: CGPoint(x: c.x, y: c.y + 6 * up))
        arrow.move(to: CGPoint(x: c.x - 5, y: c.y + 1 * up))
        arrow.line(to: CGPoint(x: c.x, y: c.y + 6 * up))
        arrow.line(to: CGPoint(x: c.x + 5, y: c.y + 1 * up))
        arrow.lineWidth = 2
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        (on ? ChatPill.paper : ChatPill.paper.withAlphaComponent(0.8)).setStroke()
        arrow.stroke()
    }
}
