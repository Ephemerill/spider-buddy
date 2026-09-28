import AppKit
import QuartzCore

// MARK: - Welcome

/// One of the settings the welcome asks about before it moves in: what it
/// is, a line on what it means, and a switch.
struct WelcomeChoice {
    var title: String
    var detail: String
    var symbol: String
    /// Small print under it, always there.
    var note: String? = nil
    var get: () -> Bool
    var set: (Bool) -> Void
}

/// The first thing anyone sees: pages in one window. A hello, with the
/// spider sitting still on the left and only its eyes following the
/// pointer; where it will live (the menu bar icon, and the panel that drops
/// down from it); a few house rules, set before it moves in; and then the
/// Studio, to make it their own before it comes out. Done in the Studio,
/// and it makes its entrance from its icon.
final class OnboardingController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let pages = NSView()
    private var page = 0
    private let dots = PageDots()
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let skipButton = NSButton(title: "Skip", target: nil, action: nil)
    private var sitter: SittingSpiderView!
    private let design: SpiderDesign
    private let panelPicture: (_ dark: Bool) -> NSImage?
    private let choices: [WelcomeChoice]
    private var finished = false

    /// Page two's "Show Me": the real panel, from the real icon.
    var onOpenMenu: (() -> Void)?
    /// On to the Studio: handed the window's frame, so the Studio can open
    /// exactly where this one is and take its place.
    var onStudio: ((NSRect) -> Void)?
    /// Closed or skipped before the Studio: the spider comes out anyway.
    var onSkip: (() -> Void)?

    /// Same size as the Studio, so the last step is one window becoming
    /// the other rather than a jump.
    static let size = NSSize(width: 920, height: 600)

    /// `panelPicture`: the panel as it drops down from the icon, drawn light
    /// or dark. `choices`: the house rules.
    init(design: SpiderDesign, panelPicture: @escaping (_ dark: Bool) -> NSImage?, choices: [WelcomeChoice]) {
        self.design = design
        self.panelPicture = panelPicture
        self.choices = choices
        window = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingController.size),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "Welcome"
        // (However its pages lay out, it stays the Studio's size.)
        window.contentMinSize = OnboardingController.size
        window.contentMaxSize = OnboardingController.size
        build()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        sitter.start()
    }

    func windowWillClose(_ notification: Notification) {
        sitter.stop()
        if !finished { finished = true; onSkip?() }
    }

    // MARK: Layout

    private func build() {
        let root = NSVisualEffectView()
        root.material = .windowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root

        pages.wantsLayer = true
        pages.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(pages)

        nextButton.target = self
        nextButton.action = #selector(next)
        nextButton.bezelStyle = .rounded
        nextButton.controlSize = .large
        nextButton.keyEquivalent = "\r"
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(nextButton)

        skipButton.target = self
        skipButton.action = #selector(skip)
        skipButton.isBordered = false
        skipButton.contentTintColor = .secondaryLabelColor
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(skipButton)

        // One dot for each page here, and one for the Studio after them.
        dots.count = built.count + 1
        dots.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(dots)

        NSLayoutConstraint.activate([
            pages.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            pages.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pages.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            pages.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -16),
            nextButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            nextButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -26),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            skipButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            skipButton.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
            dots.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            dots.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
            dots.widthAnchor.constraint(equalToConstant: 80),
            dots.heightAnchor.constraint(equalToConstant: 10),
        ])
        show(page: 0, animated: false)
    }

    /// The same tour for everyone: no one's spider's name in it.
    private let name = "your spider"

    private func welcomePage() -> NSView {
        let v = NSView()
        sitter = SittingSpiderView(look: design.look)
        sitter.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(sitter)

        let title = label("Say hello to \(name).", size: 34, weight: .bold)
        let body = label("""
            A little jumping spider is about to move onto your screen. It walks along the edges of \
            your windows, leaps between them, swings on silk, naps in a hammock it spins itself, and \
            keeps an eye on you the whole time.

            You can pick it up and throw it, stroke it with the pointer, feed it, or just let it \
            get on with its day.
            """, size: 15, weight: .regular, colour: .secondaryLabelColor)
        let text = stack([title, body], spacing: 18)
        v.addSubview(text)

        NSLayoutConstraint.activate([
            sitter.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 30),
            sitter.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            sitter.widthAnchor.constraint(equalToConstant: 400),
            sitter.heightAnchor.constraint(equalToConstant: 420),
            text.leadingAnchor.constraint(equalTo: sitter.trailingAnchor, constant: 24),
            text.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -56),
            text.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -10),
        ])
        return v
    }

    private func menuPage() -> NSView {
        let v = NSView()
        let picture = MenuBarPicture(panel: panelPicture)
        picture.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(picture)

        let title = label("It'll live in your menu bar.", size: 30, weight: .bold)
        let intro = label("""
            Up by the clock there's a little spider. Click it and a panel drops down with \
            everything \(name) can do, a page for each.
            """, size: 14, weight: .regular, colour: .secondaryLabelColor)
        let rows = stack([
            bullet("Spider, Play and Feed", "Hide it or pause it, ask it to say hi or swing, hand it a toy, or let a cricket loose."),
            bullet("Behavior, Visitors and Your Mac", "What it makes of your pointer, its silk, other spiders, and the world outside."),
            bullet("Spider Studio", "Along the bottom: how it looks, how it walks, and who it is."),
            bullet("Right-click the spider", "A quick menu, right where it is."),
        ], spacing: 12)
        let soon = label("Any moment now, it'll let itself down from up there and move in.",
                         size: 14, weight: .regular, colour: .secondaryLabelColor)
        let open = NSButton(title: "Show Me", target: self, action: #selector(openMenu))
        open.bezelStyle = .rounded
        let text = stack([title, intro, rows, soon, open], spacing: 16)
        v.addSubview(text)

        NSLayoutConstraint.activate([
            picture.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 40),
            picture.topAnchor.constraint(equalTo: v.topAnchor, constant: 10),
            picture.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            picture.widthAnchor.constraint(equalToConstant: 360),
            text.leadingAnchor.constraint(equalTo: picture.trailingAnchor, constant: 36),
            text.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -48),
            text.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    /// Before it moves in: the settings that most change what having it
    /// about is like, each a switch, set as they are now.
    private func rulesPage() -> NSView {
        let v = NSView()
        let title = label("But first, a few house rules.", size: 30, weight: .bold)
        let intro = label("How lively would you like things? Pick what suits you, and it'll move in just so.",
                          size: 14, weight: .regular, colour: .secondaryLabelColor)
        let inset: CGFloat = 64, gap: CGFloat = 12
        let width = OnboardingController.size.width - inset * 2
        title.preferredMaxLayoutWidth = width
        intro.preferredMaxLayoutWidth = width
        let head = stack([title, intro], spacing: 8)

        // Two to a row.
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = gap
        grid.translatesAutoresizingMaskIntoConstraints = false
        var i = 0
        while i < choices.count {
            let row = NSStackView()
            row.spacing = gap
            row.alignment = .top
            row.translatesAutoresizingMaskIntoConstraints = false
            // (A pair are as tall as the taller of them.)
            let pair = choices[i..<min(i + 2, choices.count)].map { ChoiceCard($0, width: (width - gap) / 2) }
            for c in pair { row.addArrangedSubview(c) }
            if pair.count == 2 { pair[0].heightAnchor.constraint(equalTo: pair[1].heightAnchor).isActive = true }
            grid.addArrangedSubview(row)
            i += 2
        }

        let footnote = NSTextField(labelWithString: "You can change any of these at any time from the menu bar.")
        footnote.font = .systemFont(ofSize: 12)
        footnote.textColor = .tertiaryLabelColor
        footnote.translatesAutoresizingMaskIntoConstraints = false

        let column = stack([head, grid, footnote], spacing: 24)
        column.setCustomSpacing(14, after: grid)
        v.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: inset),
            head.widthAnchor.constraint(equalToConstant: width),
            column.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -6),
        ])
        return v
    }

    // MARK: Paging

    private lazy var built: [NSView] = [welcomePage(), menuPage(), rulesPage()]

    private func show(page i: Int, animated: Bool) {
        page = i
        let incoming = built[i]
        if animated {
            let t = CATransition()
            t.type = .push
            t.subtype = .fromRight
            t.duration = 0.35
            t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pages.layer?.add(t, forKey: "page")
        }
        pages.subviews.forEach { $0.removeFromSuperview() }
        incoming.translatesAutoresizingMaskIntoConstraints = false
        pages.addSubview(incoming)
        NSLayoutConstraint.activate([
            incoming.leadingAnchor.constraint(equalTo: pages.leadingAnchor),
            incoming.trailingAnchor.constraint(equalTo: pages.trailingAnchor),
            incoming.topAnchor.constraint(equalTo: pages.topAnchor),
            incoming.bottomAnchor.constraint(equalTo: pages.bottomAnchor),
        ])
        dots.current = i
        nextButton.title = i < built.count - 1 ? "Next" : "Design Your Spider"
    }

    @objc private func next() {
        if page < built.count - 1 { show(page: page + 1, animated: true); return }
        // On to the Studio: this window fades as the Studio opens in its
        // place, and the rest happens there.
        finished = true
        sitter.stop()
        let frame = window.frame
        onStudio?(frame)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window.orderOut(nil)
            self?.window.alphaValue = 1
        })
    }

    @objc private func skip() {
        finished = true
        sitter.stop()
        window.orderOut(nil)
        onSkip?()
    }

    @objc private func openMenu() { onOpenMenu?() }

    /// Tools only: a picture of the window as it stands, and a turn of the page.
    func debugSnapshot(to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    func debugNextPage() { if page < built.count - 1 { show(page: page + 1, animated: false) } }
    var debugPageCount: Int { built.count }
    func debugAdvance() { next() }

    // MARK: Bits

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight, colour: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = colour
        l.lineBreakMode = .byWordWrapping
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func bullet(_ head: String, _ text: String) -> NSView {
        let h = label(head, size: 14, weight: .semibold)
        let t = label(text, size: 13, weight: .regular, colour: .secondaryLabelColor)
        return stack([h, t], spacing: 2)
    }

    private func stack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
}

// MARK: - A house rule

/// One setting on the house rules page: its icon, name and a line on what
/// it means, and a switch, on a soft card.
final class ChoiceCard: NSView {
    private let choice: WelcomeChoice
    private let toggle = NSSwitch()

    init(_ choice: WelcomeChoice, width: CGFloat) {
        self.choice = choice
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        toggle.controlSize = .small
        // Icon 16 + 24 + 10 in, the switch and 12 + 16 out.
        let textWidth = width - 50 - 28 - 32

        let icon = NSImageView(image: NSImage(systemSymbolName: choice.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .medium)) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let title = NSTextField(labelWithString: choice.title)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        var lines: [NSView] = [title]
        let detail = NSTextField(wrappingLabelWithString: choice.detail)
        detail.font = .systemFont(ofSize: 12.5)
        detail.textColor = .secondaryLabelColor
        detail.preferredMaxLayoutWidth = textWidth
        lines.append(detail)
        if let note = choice.note {
            let n = NSTextField(wrappingLabelWithString: note)
            n.font = .systemFont(ofSize: 11)
            n.textColor = .tertiaryLabelColor
            n.preferredMaxLayoutWidth = textWidth
            lines.append(n)
        }
        let text = NSStackView(views: lines)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.setCustomSpacing(5, after: detail)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)

        toggle.state = choice.get() ? .on : .off
        toggle.target = self
        toggle.action = #selector(flipped)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggle)

        // As short as its words let it be (or as its neighbour is).
        let snug = bottomAnchor.constraint(equalTo: text.bottomAnchor, constant: 14)
        snug.priority = .defaultLow
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            icon.widthAnchor.constraint(equalToConstant: 24),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            text.widthAnchor.constraint(equalToConstant: textWidth),
            bottomAnchor.constraint(greaterThanOrEqualTo: text.bottomAnchor, constant: 14),
            snug,
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            toggle.topAnchor.constraint(equalTo: topAnchor, constant: 15),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func flipped() {
        choice.set(toggle.state == .on)
        // As it really is now (turning something on may not take).
        toggle.state = choice.get() ? .on : .off
    }

    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.09).setStroke()
        path.stroke()
    }
}

// MARK: - The spider sitting still

/// The welcome page's spider: sitting on a little ledge, three-quarters
/// round toward you, doing nothing at all but watching the pointer —
/// wherever it is on the screen — and blinking now and then.
final class SittingSpiderView: NSView {
    private let look: SpiderLook
    private var timer: Timer?
    private var gaze = V2.zero
    private var gazeVel = V2.zero
    private var blinkIn: CGFloat = 2
    private var blinkT: CGFloat = -1
    private var time: CGFloat = 0
    private let scale: CGFloat
    /// How much bigger or smaller than the welcome's it is drawn.
    private var k: CGFloat { scale / 3.1 }

    init(look: SpiderLook, scale: CGFloat = 3.1) {
        self.look = look
        self.scale = scale
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Where the body sits in the view, and the head within that.
    private var bodyOrigin: V2 { V2(bounds.midX + 10 * k, bounds.midY - 30 * k) }

    private func tick() {
        let dt: CGFloat = 1.0 / 60.0
        time += dt
        // The pointer, wherever it is on the screen, in this view's terms.
        var target = V2.zero
        if let w = window {
            let screenPt = NSEvent.mouseLocation
            let inWindow = w.convertPoint(fromScreen: screenPt)
            let p = V2(convert(inWindow, from: nil))
            let head = bodyOrigin + V2(SpiderRenderer.head.c.x * 0.4, SpiderRenderer.head.c.y) * scale
            let d = p - head
            // Full gaze once the pointer is a little way off; softer close in.
            target = d.normalized * clamp(d.length / 160, 0, 1)
        }
        // A quick, slightly springy eye movement.
        gazeVel += ((target - gaze) * 220 - gazeVel * 22) * dt
        gaze += gazeVel * dt
        if blinkT >= 0 {
            blinkT += dt
            if blinkT > 0.19 { blinkT = -1; blinkIn = CGFloat.random(in: 1.8...5.5) }
        } else {
            blinkIn -= dt
            if blinkIn <= 0 { blinkT = 0 }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let o = bodyOrigin
        // A soft ledge to sit on.
        let ledgeY = o.y + SpiderRenderer.ground * scale
        let ledge = CGRect(x: o.x - 150 * k, y: ledgeY - 16 * k, width: 300 * k, height: 16 * k)
        ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.07).cgColor)
        ctx.addPath(CGPath(roundedRect: ledge, cornerWidth: 8 * k, cornerHeight: 8 * k, transform: nil))
        ctx.fillPath()

        var pose = SpiderRenderer.restPose(look: look, yaw: 0.45, scale: scale)
        pose.pos = o
        pose.look = gaze.clampedLength(1)
        pose.blink = blinkT >= 0 ? sin(blinkT / 0.19 * .pi) : 0
        pose.time = time
        pose.grounded = 1
        // A camouflaged coat takes on the window behind it.
        if let bg = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) {
            pose.surroundings = RGB(bg.redComponent, bg.greenComponent, bg.blueComponent)
        }
        let r = SpiderRenderer.spriteSide(for: scale)
        SpiderRenderer.draw(pose, in: ctx, bounds: CGRect(x: o.x - r / 2, y: o.y - r / 2, width: r, height: r))
    }
}

// MARK: - The panel, pictured

/// A strip of menu bar with the spider's icon lit, and its real panel
/// hanging from it — a picture of the panel itself, so it is never out of
/// date.
final class MenuBarPicture: NSView {
    private let panel: (_ dark: Bool) -> NSImage?
    private var cached: (dark: Bool, image: NSImage?)?

    init(panel: @escaping (_ dark: Bool) -> NSImage?) {
        self.panel = panel
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let barH: CGFloat = 26
        // The bar.
        let bar = CGRect(x: 0, y: 0, width: bounds.width, height: barH)
        ctx.setFillColor((dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).cgColor)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.fillPath()
        // Some other things that live up there, for scale.
        let fg = NSColor.labelColor
        let clock = NSAttributedString(string: "Tue 9:41", attributes: [.font: NSFont.menuBarFont(ofSize: 12), .foregroundColor: fg])
        clock.draw(at: CGPoint(x: bounds.width - clock.size().width - 12, y: 5))
        for (i, name) in ["wifi", "battery.75", "magnifyingglass"].enumerated() {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
                let r = CGRect(x: bounds.width - clock.size().width - 40 - CGFloat(i) * 26, y: 6, width: 15, height: 14)
                img.isTemplate = true
                tint(img, fg).draw(in: r)
            }
        }
        // The spider's icon, lit, as it is when its panel is open.
        let iconX = bounds.width - clock.size().width - 40 - 3 * 26 - 12
        let lit = CGRect(x: iconX - 5, y: 3, width: 28, height: barH - 6)
        ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.16).cgColor)
        ctx.addPath(CGPath(roundedRect: lit, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.fillPath()
        let icon = SpiderRenderer.statusItemImage(size: 17)
        tint(icon, fg).draw(in: CGRect(x: iconX, y: 4.5, width: 17, height: 17))

        // The panel hanging from it, as small as it has to be to fit.
        if cached?.dark != dark { cached = (dark, panel(dark)) }
        guard let image = cached?.image, image.size.width > 0 else { return }
        let arrow: CGFloat = 8
        let top = barH + 4 + arrow
        let s = min(1, (bounds.height - top - 4) / image.size.height, (bounds.width - 12) / image.size.width)
        let w = image.size.width * s, h = image.size.height * s
        let iconMid = iconX + 8.5
        let rect = CGRect(x: clamp(iconMid - w / 2, 6, bounds.width - w - 6), y: top, width: w, height: h)
        let radius: CGFloat = 12
        let shape = CGMutablePath()
        shape.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        // (The popover's little arrow, up to the icon.)
        shape.move(to: CGPoint(x: iconMid - arrow, y: top + 0.5))
        shape.addLine(to: CGPoint(x: iconMid, y: top - arrow))
        shape.addLine(to: CGPoint(x: iconMid + arrow, y: top + 0.5))
        shape.closeSubpath()
        let fill = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 20, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setFillColor(fill.cgColor)
        ctx.addPath(shape)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.strokePath()
    }

    private func tint(_ img: NSImage, _ colour: NSColor) -> NSImage {
        let out = NSImage(size: img.size)
        out.lockFocus()
        img.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        colour.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }
}

/// A little dot for each page: which page this is.
final class PageDots: NSView {
    var count = 3 { didSet { needsDisplay = true } }
    var current = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = 7, gap: CGFloat = 10
        let total = CGFloat(count) * d + CGFloat(count - 1) * gap
        var x = bounds.midX - total / 2
        for i in 0..<count {
            let c: NSColor = i == current ? .controlAccentColor : NSColor.labelColor.withAlphaComponent(0.2)
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: bounds.midY - d / 2, width: d, height: d)).fill()
            x += d + gap
        }
    }
}
